import Combine
import Foundation

enum ImporterAssetState: Equatable {
    case available
    case downloading(Double)
    case cached
    case assembling
    case authorizing
    case importing
    case imported
    case needsConfirmation
    case failed(String)

    var title: String {
        switch self {
        case .available:
            L10n.text("asset.action.import")
        case .downloading(let progress):
            L10n.format("asset.action.downloading", Int(progress * 100))
        case .cached:
            L10n.text("asset.state.cached")
        case .assembling:
            L10n.text("asset.state.assembling")
        case .authorizing:
            L10n.text("asset.state.authorizing")
        case .importing:
            L10n.text("asset.state.importing")
        case .imported:
            L10n.text("asset.state.imported")
        case .needsConfirmation:
            L10n.text("asset.state.needs_confirmation")
        case .failed:
            L10n.text("common.retry")
        }
    }

    var isBusy: Bool {
        switch self {
        case .downloading, .assembling, .authorizing, .importing:
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
    private let photoImporter: any PhotoLibraryImporting
    private let history: ImportHistoryStore
    private var inFlightAssetIds: Set<String> = []
    private var api: CameraAPIClient?
    private var cancellables: Set<AnyCancellable> = []

    init(
        discovery: DeviceDiscovery = DeviceDiscovery(),
        downloadStore: DownloadStore = DownloadStore(),
        assembler: LivePhotoAssembler = LivePhotoAssembler(),
        photoImporter: any PhotoLibraryImporting = PhotoLibraryImporter(),
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
        discovery.stop()
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
                if inFlightAssetIds.contains(summary.assetId) {
                    continue
                } else if try await history.record(for: summary.assetId) != nil {
                    assetStates[summary.assetId] = .imported
                } else if try await history.hasUnconfirmedSubmission(for: summary.assetId) {
                    assetStates[summary.assetId] = .needsConfirmation
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
        guard let api,
              assetStates[summary.assetId]?.isBusy != true,
              assetStates[summary.assetId] != .imported,
              assetStates[summary.assetId] != .needsConfirmation,
              inFlightAssetIds.insert(summary.assetId).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { inFlightAssetIds.remove(summary.assetId) }
            do {
                if try await history.record(for: summary.assetId) != nil {
                    assetStates[summary.assetId] = .imported
                    return
                }
                if try await history.hasUnconfirmedSubmission(for: summary.assetId) {
                    assetStates[summary.assetId] = .needsConfirmation
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
                let kind: ImportedAssetKind
                let photoURL: URL
                let pairedVideoURL: URL?
                if cached.motionURL != nil {
                    assetStates[summary.assetId] = .assembling
                    let assembled = try await assembler.assemble(cached)
                    guard let assembledVideoURL = assembled.pairedVideoURL else {
                        throw LivePhotoAssemblyError.missingVideoTrack
                    }
                    kind = .livePhoto
                    photoURL = assembled.photoURL
                    pairedVideoURL = assembledVideoURL
                } else {
                    kind = .photo
                    photoURL = cached.photoURL
                    pairedVideoURL = nil
                }
                assetStates[summary.assetId] = .authorizing
                try await photoImporter.authorizeForAdditions()
                guard try await history.beginSubmission(assetId: summary.assetId, kind: kind) else {
                    assetStates[summary.assetId] = try await history.record(for: summary.assetId) == nil
                        ? .needsConfirmation
                        : .imported
                    return
                }
                assetStates[summary.assetId] = .importing
                let localIdentifier: String
                do {
                    if let pairedVideoURL {
                        localIdentifier = try await photoImporter.importLivePhoto(
                            photoURL: photoURL,
                            pairedVideoURL: pairedVideoURL
                        )
                    } else {
                        localIdentifier = try await photoImporter.importPhoto(photoURL: photoURL)
                    }
                } catch let error as PhotoLibraryImportError {
                    switch error {
                    case .permissionDenied, .photoKitFailed:
                        do {
                            try await history.cancelSubmission(for: summary.assetId)
                        } catch {
                            assetStates[summary.assetId] = .needsConfirmation
                            return
                        }
                        throw error
                    case .missingPlaceholder:
                        assetStates[summary.assetId] = .needsConfirmation
                        return
                    }
                } catch {
                    assetStates[summary.assetId] = .needsConfirmation
                    return
                }
                do {
                    try await history.save(
                        ImportRecord(
                            assetId: summary.assetId,
                            localIdentifier: localIdentifier,
                            kind: kind,
                            importedAt: Date()
                        )
                    )
                } catch {
                    assetStates[summary.assetId] = .needsConfirmation
                    return
                }
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
