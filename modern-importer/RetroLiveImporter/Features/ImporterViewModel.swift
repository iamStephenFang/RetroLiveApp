import Combine
import Foundation

enum ImporterAssetState: Equatable {
    case available
    case downloading(Double)
    case cached
    case assembling
    case importing
    case imported
    case failed(String)

    var title: String {
        switch self {
        case .available:
            "下载并导入"
        case .downloading(let progress):
            "下载 \(Int(progress * 100))%"
        case .cached:
            "已下载"
        case .assembling:
            "正在生成"
        case .importing:
            "正在写入照片"
        case .imported:
            "已导入"
        case .failed:
            "重试"
        }
    }

    var isBusy: Bool {
        switch self {
        case .downloading, .assembling, .importing:
            true
        default:
            false
        }
    }
}

@MainActor
final class ImporterViewModel: ObservableObject {
    @Published private(set) var cameras: [DiscoveredCamera] = []
    @Published var selectedCamera: DiscoveredCamera?
    @Published var pairingCode = ""
    @Published private(set) var deviceInfo: CameraDeviceInfo?
    @Published private(set) var assets: [CameraAssetSummary] = []
    @Published private(set) var assetStates: [String: ImporterAssetState] = [:]
    @Published private(set) var isPairing = false
    @Published private(set) var isLoadingAssets = false
    @Published var errorMessage: String?

    private let discovery: DeviceDiscovery
    private let downloadStore: DownloadStore
    private let assembler: LivePhotoAssembler
    private let photoImporter: PhotoLibraryImporter
    private let history: ImportHistoryStore
    private var api: CameraAPIClient?
    private var cancellables: Set<AnyCancellable> = []

    init(
        discovery: DeviceDiscovery = DeviceDiscovery(),
        downloadStore: DownloadStore = DownloadStore(),
        assembler: LivePhotoAssembler = LivePhotoAssembler(),
        photoImporter: PhotoLibraryImporter = PhotoLibraryImporter(),
        history: ImportHistoryStore = ImportHistoryStore()
    ) {
        self.discovery = discovery
        self.downloadStore = downloadStore
        self.assembler = assembler
        self.photoImporter = photoImporter
        self.history = history
        discovery.$cameras
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.cameras = $0 }
            .store(in: &cancellables)
        discovery.$errorMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.errorMessage = $0 }
            .store(in: &cancellables)
    }

    func startDiscovery() {
        discovery.start()
    }

    func select(_ camera: DiscoveredCamera) {
        selectedCamera = camera
        pairingCode = ""
        deviceInfo = nil
        assets = []
        assetStates = [:]
        api = CameraAPIClient(baseURL: camera.baseURL)
    }

    func pair() {
        guard let api, pairingCode.count == 6 else { return }
        isPairing = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await api.pair(code: pairingCode, clientName: "RetroLive Importer")
                deviceInfo = try await api.deviceInfo()
                pairingCode = ""
                isPairing = false
                await refreshAssets()
            } catch {
                isPairing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshAssets() async {
        guard let api else { return }
        isLoadingAssets = true
        do {
            let loaded = try await api.allAssets()
            assets = loaded
            for summary in loaded {
                if try await history.record(for: summary.assetId) != nil {
                    assetStates[summary.assetId] = .imported
                } else if (try? await downloadStore.cachedAsset(assetId: summary.assetId)) != nil {
                    assetStates[summary.assetId] = .cached
                } else {
                    assetStates[summary.assetId] = .available
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingAssets = false
    }

    func importAsset(_ summary: CameraAssetSummary) {
        guard let api, assetStates[summary.assetId]?.isBusy != true else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                if try await history.record(for: summary.assetId) != nil {
                    assetStates[summary.assetId] = .imported
                    return
                }
                assetStates[summary.assetId] = .downloading(0)
                let cached = try await downloadStore.download(
                    summary: summary,
                    api: api
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.assetStates[summary.assetId] = .downloading(progress)
                    }
                }
                assetStates[summary.assetId] = .assembling
                let assembled = try await assembler.assemble(cached)
                assetStates[summary.assetId] = .importing
                let localIdentifier: String
                let kind: ImportedAssetKind
                if let pairedVideoURL = assembled.pairedVideoURL {
                    localIdentifier = try await photoImporter.importLivePhoto(
                        photoURL: assembled.photoURL,
                        pairedVideoURL: pairedVideoURL
                    )
                    kind = .livePhoto
                } else {
                    localIdentifier = try await photoImporter.importPhoto(
                        photoURL: assembled.photoURL
                    )
                    kind = .photo
                }
                try await history.save(
                    ImportRecord(
                        assetId: summary.assetId,
                        localIdentifier: localIdentifier,
                        kind: kind,
                        importedAt: Date()
                    )
                )
                assetStates[summary.assetId] = .imported
            } catch {
                assetStates[summary.assetId] = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        if let api {
            Task { await api.disconnect() }
        }
        api = nil
        selectedCamera = nil
        deviceInfo = nil
        assets = []
        assetStates = [:]
        pairingCode = ""
        discovery.start()
    }
}
