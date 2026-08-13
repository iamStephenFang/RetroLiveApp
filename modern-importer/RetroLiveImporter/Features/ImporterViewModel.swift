import Combine
import Foundation
import ImageIO
import UIKit

enum ImporterAssetState: Equatable {
    case available
    case queued
    case downloading(Double)
    case verifying
    case cached
    case assembling
    case authorizing
    case importing
    case paused
    case cancelled
    case imported
    case needsConfirmation
    case failed(String)

    var title: String {
        switch self {
        case .available: L10n.text("asset.action.import")
        case .queued: L10n.text("asset.state.queued")
        case .downloading(let progress): L10n.format("asset.action.downloading", Int(progress * 100))
        case .verifying: L10n.text("asset.state.verifying")
        case .cached: L10n.text("asset.state.cached")
        case .assembling: L10n.text("asset.state.assembling")
        case .authorizing: L10n.text("asset.state.authorizing")
        case .importing: L10n.text("asset.state.importing")
        case .paused: L10n.text("asset.state.paused")
        case .cancelled: L10n.text("asset.state.cancelled")
        case .imported: L10n.text("asset.state.imported")
        case .needsConfirmation: L10n.text("asset.state.needs_confirmation")
        case .failed: L10n.text("common.retry")
        }
    }

    var isBusy: Bool {
        switch self {
        case .queued, .downloading, .verifying, .assembling, .authorizing, .importing:
            true
        default:
            false
        }
    }
}

private enum ImportQueueProcessingError: LocalizedError {
    case insufficientStorage(ImportStoragePreflight)

    var errorDescription: String? {
        switch self {
        case .insufficientStorage(let preflight):
            L10n.format(
                "storage.insufficient",
                ByteCountFormatter.string(
                    fromByteCount: preflight.requiredAdditionalBytes,
                    countStyle: .file
                ),
                ByteCountFormatter.string(fromByteCount: preflight.availableBytes, countStyle: .file)
            )
        }
    }
}

@MainActor
final class ImporterViewModel: ObservableObject {
    @Published private(set) var cameras: [DiscoveredCamera] = []
    @Published var selectedCamera: DiscoveredCamera?
    @Published var pairingCode = ""
    @Published var rememberDevice = true
    @Published private(set) var deviceInfo: CameraDeviceInfo?
    @Published private(set) var assets: [CameraAssetSummary] = []
    @Published private(set) var assetStates: [String: ImporterAssetState] = [:]
    @Published private(set) var thumbnailImages: [String: UIImage] = [:]
    @Published private(set) var isPairing = false
    @Published private(set) var isRestoringSession = false
    @Published private(set) var isLoadingAssets = false
    @Published private(set) var pairingErrorMessage: String?
    @Published private(set) var pairingFailureCount = 0
    @Published var errorMessage: String?

    @Published private(set) var selectionMode = false
    @Published private(set) var selectedAssetIds: Set<String> = []
    @Published private(set) var queueItems: [ImportQueueItem] = []
    @Published private(set) var isQueuePaused = false
    @Published private(set) var activeQueueItemId: UUID?
    @Published private(set) var isPreparingBatch = false
    @Published private(set) var storageOverview: ImportStorageOverview?
    @Published private(set) var lastPreflight: ImportStoragePreflight?

    private let discovery: DeviceDiscovery
    private let downloadStore: DownloadStore
    private let assembler: LivePhotoAssembler
    private let photoImporter: any PhotoLibraryImporting
    private let history: ImportHistoryStore
    private let queueStore: ImportQueueStore
    private let rememberedDeviceStore: any RememberedDeviceStoring
    private var loadingThumbnailIds: Set<String> = []
    private var failedThumbnailIds: Set<String> = []
    private var cancellationRequestedItemIds: Set<UUID> = []
    private var pendingQueuePersistenceItemIds: Set<UUID> = []
    private var isResumingQueue = false
    private var lastAttemptedPairingCode: String?
    private var api: CameraAPIClient?
    private var activeQueueTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        discovery: DeviceDiscovery = DeviceDiscovery(),
        downloadStore: DownloadStore = DownloadStore(),
        assembler: LivePhotoAssembler = LivePhotoAssembler(),
        photoImporter: any PhotoLibraryImporting = PhotoLibraryImporter(),
        history: ImportHistoryStore = ImportHistoryStore(),
        queueStore: ImportQueueStore = ImportQueueStore(),
        rememberedDeviceStore: any RememberedDeviceStoring = KeychainRememberedDeviceStore()
    ) {
        self.discovery = discovery
        self.downloadStore = downloadStore
        self.assembler = assembler
        self.photoImporter = photoImporter
        self.history = history
        self.queueStore = queueStore
        self.rememberedDeviceStore = rememberedDeviceStore
        discovery.$cameras
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.cameras = $0 }
            .store(in: &cancellables)
        discovery.$errorMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.errorMessage = $0 }
            .store(in: &cancellables)
        Task { [weak self] in await self?.restoreQueue() }
    }

    var selectedCount: Int { selectedAssetIds.count }

    var visibleQueueItems: [ImportQueueItem] {
        guard let deviceId = deviceInfo?.deviceId else { return [] }
        return queueItems.filter { $0.deviceId == deviceId }
    }

    var activeQueueAssetIds: Set<String> {
        Set(queueItems.filter { !$0.status.isTerminal }.map { $0.summary.assetId })
    }

    func startDiscovery() { discovery.start() }

    func select(_ camera: DiscoveredCamera) {
        discovery.stop()
        selectedCamera = camera
        pairingCode = ""
        deviceInfo = nil
        assets = []
        assetStates = [:]
        thumbnailImages = [:]
        selectionMode = false
        selectedAssetIds = []
        pairingErrorMessage = nil
        lastAttemptedPairingCode = nil
        api = CameraAPIClient(baseURL: camera.baseURL)
        restoreRememberedSession(for: camera)
    }

    func pair() {
        guard let api, let camera = selectedCamera, pairingCode.count == 6,
              !isPairing, lastAttemptedPairingCode != pairingCode else { return }
        let submittedCode = pairingCode
        lastAttemptedPairingCode = submittedCode
        isPairing = true
        pairingErrorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await api.pair(
                    code: submittedCode,
                    clientName: "RetroLive Importer",
                    rememberDevice: rememberDevice
                )
                let info = try await api.deviceInfo()
                if rememberDevice {
                    do {
                        try rememberedDeviceStore.save(RememberedDeviceRecord(
                            serviceName: camera.name,
                            deviceId: info.deviceId,
                            deviceName: info.deviceName,
                            session: session,
                            lastConnectedAt: Date()
                        ))
                    } catch { errorMessage = error.localizedDescription }
                } else {
                    try? rememberedDeviceStore.remove(serviceName: camera.name)
                }
                deviceInfo = info
                pairingCode = ""
                isPairing = false
                await refreshAssets()
                startQueueIfPossible()
            } catch {
                isPairing = false
                pairingErrorMessage = error.localizedDescription
                pairingFailureCount += 1
            }
        }
    }

    func updatePairingCode(_ value: String) {
        let sanitized = String(value.filter(\.isNumber).prefix(6))
        if pairingCode != sanitized { pairingCode = sanitized }
        if sanitized.count < 6 {
            pairingErrorMessage = nil
            lastAttemptedPairingCode = nil
        } else { pair() }
    }

    func retryPairing() {
        lastAttemptedPairingCode = nil
        pair()
    }

    func isRemembered(_ camera: DiscoveredCamera) -> Bool {
        rememberedDeviceStore.record(for: camera.name) != nil
    }

    func loadThumbnail(for summary: CameraAssetSummary) async {
        guard thumbnailImages[summary.assetId] == nil,
              !loadingThumbnailIds.contains(summary.assetId),
              !failedThumbnailIds.contains(summary.assetId), let api else { return }
        loadingThumbnailIds.insert(summary.assetId)
        defer { loadingThumbnailIds.remove(summary.assetId) }
        for attempt in 0..<2 {
            do {
                let image: UIImage?
                if let cached = try? await downloadStore.cachedAsset(assetId: summary.assetId) {
                    let photoURL = cached.photoURL
                    image = try await Task.detached(priority: .utility) {
                        let data = try Data(contentsOf: photoURL, options: .mappedIfSafe)
                        return Self.downsampledThumbnail(from: data)
                    }.value
                } else {
                    let data = try await api.previewData(for: summary)
                    image = await Task.detached(priority: .utility) {
                        Self.downsampledThumbnail(from: data)
                    }.value
                }
                guard let image else { throw CameraAPIError.invalidPayload("thumbnail") }
                thumbnailImages[summary.assetId] = image
                return
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(300))
                    continue
                }
                failedThumbnailIds.insert(summary.assetId)
            }
        }
    }

    private nonisolated static func downsampledThumbnail(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    func refreshAssets() async {
        guard let api else { return }
        isLoadingAssets = true
        defer { isLoadingAssets = false }
        do {
            let loaded = try await api.allAssets()
            assets = loaded
            let loadedIds = Set(loaded.map(\.assetId))
            thumbnailImages = thumbnailImages.filter { loadedIds.contains($0.key) }
            failedThumbnailIds.removeAll()
            for summary in loaded {
                if try await history.record(for: summary.assetId) != nil {
                    assetStates[summary.assetId] = .imported
                } else if try await history.hasUnconfirmedSubmission(for: summary.assetId) {
                    assetStates[summary.assetId] = .needsConfirmation
                } else if (try? await downloadStore.cachedAsset(assetId: summary.assetId)) != nil {
                    assetStates[summary.assetId] = .cached
                } else {
                    assetStates[summary.assetId] = .available
                }
            }
            overlayQueueStates()
            await refreshStorageOverview()
        } catch { errorMessage = error.localizedDescription }
    }

    func setSelectionMode(_ enabled: Bool) {
        selectionMode = enabled
        if !enabled { selectedAssetIds = [] }
    }

    func toggleSelection(_ assetId: String) {
        if selectedAssetIds.contains(assetId) {
            selectedAssetIds.remove(assetId)
        } else if canSelect(assetId) {
            selectedAssetIds.insert(assetId)
        }
    }

    func selectAllAvailable() {
        selectedAssetIds = Set(assets.map(\.assetId).filter(canSelect))
    }

    func canSelect(_ assetId: String) -> Bool {
        guard !activeQueueAssetIds.contains(assetId) else { return false }
        switch assetStates[assetId] ?? .available {
        case .imported, .needsConfirmation: return false
        default: return true
        }
    }

    func startSelectedImports() {
        let selected = assets.filter { selectedAssetIds.contains($0.assetId) }
        enqueueAfterPreflight(selected)
    }

    func importAsset(_ summary: CameraAssetSummary) {
        if let existing = queueItems.last(where: {
            $0.deviceId == deviceInfo?.deviceId &&
            $0.summary.assetId == summary.assetId &&
            ($0.status == .failed || $0.status == .cancelled)
        }) {
            retryQueueItem(existing.id)
            return
        }
        enqueueAfterPreflight([summary])
    }

    private func enqueueAfterPreflight(_ summaries: [CameraAssetSummary]) {
        guard !summaries.isEmpty, !isPreparingBatch, let api, let deviceId = deviceInfo?.deviceId else { return }
        isPreparingBatch = true
        Task { [weak self] in
            guard let self else { return }
            defer { isPreparingBatch = false }
            do {
                var runnable: [CameraAssetSummary] = []
                for summary in summaries {
                    if try await history.record(for: summary.assetId) != nil {
                        assetStates[summary.assetId] = .imported
                    } else if try await history.hasUnconfirmedSubmission(for: summary.assetId) {
                        assetStates[summary.assetId] = .needsConfirmation
                    } else if let existing = queueItems.last(where: {
                        $0.deviceId == deviceId && $0.summary.assetId == summary.assetId &&
                        ($0.status == .failed || $0.status == .cancelled)
                    }) {
                        retryQueueItem(existing.id)
                    } else if !queueItems.contains(where: {
                        $0.deviceId == deviceId && $0.summary.assetId == summary.assetId && !$0.status.isTerminal
                    }) {
                        runnable.append(summary)
                    }
                }
                guard !runnable.isEmpty else {
                    selectedAssetIds = []
                    selectionMode = false
                    return
                }
                let preflight = try await storagePreflight(for: runnable, api: api)
                lastPreflight = preflight
                await refreshStorageOverview()
                guard preflight.isSufficient else {
                    errorMessage = L10n.format(
                        "storage.insufficient",
                        ByteCountFormatter.string(fromByteCount: preflight.requiredAdditionalBytes, countStyle: .file),
                        ByteCountFormatter.string(fromByteCount: preflight.availableBytes, countStyle: .file)
                    )
                    return
                }
                let now = Date()
                let newItems = runnable.map {
                    ImportQueueItem(deviceId: deviceId, summary: $0, enqueuedAt: now, updatedAt: now)
                }
                let newItemIds = Set(newItems.map(\.id))
                pendingQueuePersistenceItemIds.formUnion(newItemIds)
                queueItems.append(contentsOf: newItems)
                do {
                    try await persistQueue()
                } catch {
                    queueItems.removeAll { newItemIds.contains($0.id) }
                    pendingQueuePersistenceItemIds.subtract(newItemIds)
                    overlayQueueStates()
                    throw error
                }
                pendingQueuePersistenceItemIds.subtract(newItemIds)
                selectedAssetIds = []
                selectionMode = false
                overlayQueueStates()
                startQueueIfPossible()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func storagePreflight(
        for summaries: [CameraAssetSummary],
        api: CameraAPIClient
    ) async throws -> ImportStoragePreflight {
        var additionalDownloadBytes: Int64 = 0
        var additionalAssemblyBytes: Int64 = 0
        var peakAttemptBytes: Int64 = 0
        let parser = ManifestParser()
        for summary in summaries {
            let manifest: ManifestV1
            if let cached = try await downloadStore.cachedAsset(assetId: summary.assetId) {
                manifest = cached.manifest
            } else {
                manifest = try parser.parse(try await api.manifestData(assetId: summary.assetId))
                additionalDownloadBytes = ImportStoragePreflight.clampedAdd(
                    additionalDownloadBytes,
                    manifest.photo.byteLength,
                    manifest.motion?.byteLength ?? 0
                )
            }
            let sourceBytes = ImportStoragePreflight.clampedAdd(
                manifest.photo.byteLength,
                manifest.motion?.byteLength ?? 0
            )
            if manifest.motion != nil {
                if !(await assembler.hasCommittedAssembly(assetId: summary.assetId)) {
                    additionalAssemblyBytes = ImportStoragePreflight.clampedAdd(
                        additionalAssemblyBytes,
                        sourceBytes
                    )
                }
                peakAttemptBytes = max(
                    peakAttemptBytes,
                    ImportStoragePreflight.clampedMultiply(sourceBytes, by: 2)
                )
            }
        }
        return ImportStoragePreflight(
            requiredAdditionalBytes: ImportStoragePreflight.clampedAdd(
                additionalDownloadBytes,
                additionalAssemblyBytes,
                peakAttemptBytes
            ),
            availableBytes: try await downloadStore.availableCapacity()
        )
    }

    func pauseQueue() {
        guard !isQueuePaused else { return }
        isQueuePaused = true
        activeQueueTask?.cancel()
    }

    func resumeQueue() {
        guard isQueuePaused, !isResumingQueue else { return }
        isResumingQueue = true
        let settlingTask = activeQueueTask
        Task {
            await settlingTask?.value
            let pausedItems = Dictionary(uniqueKeysWithValues: queueItems.compactMap {
                $0.status == .paused ? ($0.id, $0) : nil
            })
            for index in queueItems.indices where queueItems[index].status == .paused {
                queueItems[index].status = .queued
                queueItems[index].updatedAt = Date()
            }
            do {
                try await persistQueue()
                isQueuePaused = false
                isResumingQueue = false
                overlayQueueStates()
                startQueueIfPossible()
            } catch {
                for (id, previous) in pausedItems {
                    guard let index = queueItems.firstIndex(where: { $0.id == id }),
                          queueItems[index].status == .queued else { continue }
                    queueItems[index] = previous
                }
                isResumingQueue = false
                overlayQueueStates()
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelQueueItem(_ id: UUID) {
        guard let index = queueItems.firstIndex(where: { $0.id == id }),
              !pendingQueuePersistenceItemIds.contains(id) else { return }
        cancellationRequestedItemIds.insert(id)
        if activeQueueItemId == id {
            activeQueueTask?.cancel()
        } else if !queueItems[index].status.isTerminal {
            let previous = queueItems[index]
            queueItems[index].status = .cancelled
            queueItems[index].updatedAt = Date()
            cancellationRequestedItemIds.remove(id)
            overlayQueueStates()
            Task {
                do {
                    try await persistQueue()
                } catch {
                    if let current = queueItems.firstIndex(where: { $0.id == id }),
                       queueItems[current].status == .cancelled {
                        queueItems[current] = previous
                        overlayQueueStates()
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func retryQueueItem(_ id: UUID) {
        guard let index = queueItems.firstIndex(where: { $0.id == id }),
              queueItems[index].status == .failed || queueItems[index].status == .cancelled,
              !pendingQueuePersistenceItemIds.contains(id) else { return }
        let previous = queueItems[index]
        pendingQueuePersistenceItemIds.insert(id)
        queueItems[index].status = .queued
        queueItems[index].progress = 0
        queueItems[index].errorMessage = nil
        queueItems[index].updatedAt = Date()
        cancellationRequestedItemIds.remove(id)
        overlayQueueStates()
        Task {
            do {
                try await persistQueue()
                pendingQueuePersistenceItemIds.remove(id)
                startQueueIfPossible()
            } catch {
                pendingQueuePersistenceItemIds.remove(id)
                if let current = queueItems.firstIndex(where: { $0.id == id }),
                   queueItems[current].status == .queued {
                    queueItems[current] = previous
                    overlayQueueStates()
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func explicitlyReimportUnconfirmed(_ id: UUID) {
        guard let index = queueItems.firstIndex(where: { $0.id == id }),
              queueItems[index].status == .needsConfirmation,
              !pendingQueuePersistenceItemIds.contains(id) else { return }
        let assetId = queueItems[index].summary.assetId
        let previous = queueItems[index]
        pendingQueuePersistenceItemIds.insert(id)
        Task {
            do {
                try await history.cancelSubmission(for: assetId)
                guard let current = queueItems.firstIndex(where: { $0.id == id }),
                      queueItems[current].status == .needsConfirmation else {
                    pendingQueuePersistenceItemIds.remove(id)
                    return
                }
                queueItems[current].status = .queued
                queueItems[current].updatedAt = Date()
                try await persistQueue()
                pendingQueuePersistenceItemIds.remove(id)
                overlayQueueStates()
                startQueueIfPossible()
            } catch {
                pendingQueuePersistenceItemIds.remove(id)
                if let current = queueItems.firstIndex(where: { $0.id == id }),
                   queueItems[current].status == .queued {
                    queueItems[current] = previous
                    overlayQueueStates()
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearFinishedQueueItems() {
        guard let deviceId = deviceInfo?.deviceId else { return }
        let removed = queueItems.filter {
            $0.deviceId == deviceId
                && ($0.status == .imported || $0.status == .cancelled)
                && !pendingQueuePersistenceItemIds.contains($0.id)
        }
        guard !removed.isEmpty else { return }
        let removedIds = Set(removed.map(\.id))
        queueItems.removeAll { removedIds.contains($0.id) }
        overlayQueueStates()
        Task {
            do {
                try await persistQueue()
            } catch {
                let existingIds = Set(queueItems.map(\.id))
                queueItems.append(contentsOf: removed.filter { !existingIds.contains($0.id) })
                queueItems.sort { $0.enqueuedAt < $1.enqueuedAt }
                overlayQueueStates()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startQueueIfPossible() {
        guard activeQueueTask == nil, !isQueuePaused, let api, let deviceId = deviceInfo?.deviceId,
              queueItems.contains(where: {
                  $0.deviceId == deviceId && $0.status == .queued
                      && !pendingQueuePersistenceItemIds.contains($0.id)
              }) else { return }
        activeQueueTask = Task { [weak self] in
            guard let self else { return }
            await runQueue(api: api, deviceId: deviceId)
        }
    }

    private func runQueue(api: CameraAPIClient, deviceId: String) async {
        defer {
            activeQueueTask = nil
            activeQueueItemId = nil
            if !isQueuePaused { startQueueIfPossible() }
        }
        while !Task.isCancelled, !isQueuePaused,
              let item = queueItems.first(where: {
                  $0.deviceId == deviceId && $0.status == .queued
                      && !pendingQueuePersistenceItemIds.contains($0.id)
              }) {
            activeQueueItemId = item.id
            await processQueueItem(item, api: api)
            activeQueueItemId = nil
        }
        await refreshStorageOverview()
    }

    private func processQueueItem(_ original: ImportQueueItem, api: CameraAPIClient) async {
        let id = original.id
        let summary = original.summary
        var submissionStarted = false
        do {
            if try await history.record(for: summary.assetId) != nil {
                try await setQueueStatus(id, .imported, progress: 1)
                return
            }
            if try await history.hasUnconfirmedSubmission(for: summary.assetId) {
                try await setQueueStatus(id, .needsConfirmation)
                return
            }
            try await requireSufficientStorage(for: [summary], api: api)
            try await setQueueStatus(id, .downloading, progress: 0)
            let cached = try await downloadStore.download(summary: summary, api: api) { [weak self] progress in
                Task { @MainActor in self?.setQueueProgress(id, progress: progress) }
            }
            try Task.checkCancellation()
            try await setQueueStatus(id, .verifying, progress: 1)
            guard let validated = try await downloadStore.cachedAsset(assetId: summary.assetId) else {
                throw DownloadStoreError.missingResource(summary.assetId)
            }
            let kind: ImportedAssetKind
            let photoURL: URL
            let pairedVideoURL: URL?
            if validated.motionURL != nil {
                try await requireSufficientAssemblyStorage(for: validated)
                try await setQueueStatus(id, .assembling, progress: 1)
                let assembled = try await assembler.assemble(validated)
                guard let videoURL = assembled.pairedVideoURL else {
                    throw LivePhotoAssemblyError.missingVideoTrack
                }
                kind = .livePhoto
                photoURL = assembled.photoURL
                pairedVideoURL = videoURL
            } else {
                kind = .photo
                photoURL = cached.photoURL
                pairedVideoURL = nil
                try await setQueueStatus(id, .cached, progress: 1)
            }
            try Task.checkCancellation()
            try await setQueueStatus(id, .authorizing, progress: 1)
            try await photoImporter.authorizeForAdditions()
            try Task.checkCancellation()
            guard try await history.beginSubmission(assetId: summary.assetId, kind: kind) else {
                try await setQueueStatus(
                    id,
                    try await history.record(for: summary.assetId) == nil ? .needsConfirmation : .imported,
                    progress: 1
                )
                return
            }
            submissionStarted = true
            try await setQueueStatus(id, .importing, progress: 1)
            let captureDate = validated.manifest.captureDate
            let localIdentifier: String
            do {
                if let pairedVideoURL {
                    localIdentifier = try await photoImporter.importLivePhoto(
                        photoURL: photoURL,
                        pairedVideoURL: pairedVideoURL,
                        captureDate: captureDate
                    )
                } else {
                    localIdentifier = try await photoImporter.importPhoto(
                        photoURL: photoURL,
                        captureDate: captureDate
                    )
                }
            } catch let error as PhotoLibraryImportError {
                switch error {
                case .permissionDenied, .photoKitFailed:
                    try await history.cancelSubmission(for: summary.assetId)
                    submissionStarted = false
                    throw error
                case .missingPlaceholder:
                    try await setQueueStatus(id, .needsConfirmation)
                    return
                }
            }
            do {
                try await history.save(ImportRecord(
                    assetId: summary.assetId,
                    localIdentifier: localIdentifier,
                    kind: kind,
                    importedAt: Date()
                ))
            } catch {
                try await setQueueStatus(id, .needsConfirmation)
                return
            }
            submissionStarted = false
            try await setQueueStatus(id, .imported, progress: 1)
        } catch is CancellationError {
            if submissionStarted {
                try? await setQueueStatus(id, .needsConfirmation)
            } else if cancellationRequestedItemIds.remove(id) != nil {
                try? await setQueueStatus(id, .cancelled)
            } else {
                try? await setQueueStatus(id, .paused)
            }
        } catch {
            if submissionStarted {
                try? await setQueueStatus(id, .needsConfirmation)
            } else {
                try? await setQueueStatus(id, .failed, errorMessage: error.localizedDescription)
            }
        }
    }

    private func requireSufficientStorage(
        for summaries: [CameraAssetSummary],
        api: CameraAPIClient
    ) async throws {
        let preflight = try await storagePreflight(for: summaries, api: api)
        lastPreflight = preflight
        guard preflight.isSufficient else {
            throw ImportQueueProcessingError.insufficientStorage(preflight)
        }
    }

    private func requireSufficientAssemblyStorage(for cached: CachedAsset) async throws {
        let sourceBytes = ImportStoragePreflight.clampedAdd(
            cached.manifest.photo.byteLength,
            cached.manifest.motion?.byteLength ?? 0
        )
        let committedBytes = await assembler.hasCommittedAssembly(assetId: cached.manifest.assetId)
            ? 0
            : sourceBytes
        let preflight = ImportStoragePreflight(
            requiredAdditionalBytes: ImportStoragePreflight.clampedAdd(
                committedBytes,
                ImportStoragePreflight.clampedMultiply(sourceBytes, by: 2)
            ),
            availableBytes: try await downloadStore.availableCapacity()
        )
        lastPreflight = preflight
        guard preflight.isSufficient else {
            throw ImportQueueProcessingError.insufficientStorage(preflight)
        }
    }

    private func setQueueProgress(_ id: UUID, progress: Double) {
        guard let index = queueItems.firstIndex(where: { $0.id == id }),
              queueItems[index].status == .downloading else { return }
        queueItems[index].progress = min(max(progress, 0), 1)
        assetStates[queueItems[index].summary.assetId] = .downloading(queueItems[index].progress)
    }

    private func setQueueStatus(
        _ id: UUID,
        _ status: ImportQueueItemStatus,
        progress: Double? = nil,
        errorMessage: String? = nil
    ) async throws {
        guard let index = queueItems.firstIndex(where: { $0.id == id }) else { return }
        queueItems[index].status = status
        if let progress { queueItems[index].progress = progress }
        queueItems[index].errorMessage = errorMessage
        queueItems[index].updatedAt = Date()
        overlayQueueStates()
        try await persistQueue()
    }

    private func overlayQueueStates() {
        for item in queueItems {
            switch item.status {
            case .queued: assetStates[item.summary.assetId] = .queued
            case .downloading: assetStates[item.summary.assetId] = .downloading(item.progress)
            case .verifying: assetStates[item.summary.assetId] = .verifying
            case .cached: assetStates[item.summary.assetId] = .cached
            case .assembling: assetStates[item.summary.assetId] = .assembling
            case .authorizing: assetStates[item.summary.assetId] = .authorizing
            case .importing: assetStates[item.summary.assetId] = .importing
            case .paused: assetStates[item.summary.assetId] = .paused
            case .cancelled: assetStates[item.summary.assetId] = .cancelled
            case .imported: assetStates[item.summary.assetId] = .imported
            case .needsConfirmation: assetStates[item.summary.assetId] = .needsConfirmation
            case .failed: assetStates[item.summary.assetId] = .failed(item.errorMessage ?? L10n.text("queue.unknown_error"))
            }
        }
    }

    private func persistQueue() async throws {
        try await queueStore.save(queueItems)
    }

    private func restoreQueue() async {
        do {
            queueItems = try await queueStore.loadRecoveringInterruptedItems()
            for index in queueItems.indices {
                let assetId = queueItems[index].summary.assetId
                if try await history.record(for: assetId) != nil {
                    queueItems[index].status = .imported
                    queueItems[index].progress = 1
                } else if try await history.hasUnconfirmedSubmission(for: assetId) {
                    queueItems[index].status = .needsConfirmation
                }
            }
            try await persistQueue()
            overlayQueueStates()
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshStorageOverview() async {
        do {
            let downloads = try await downloadStore.storageUsage()
            let assembly = try await assembler.storageUsage()
            storageOverview = ImportStorageOverview(
                verifiedDownloadsBytes: downloads.verified,
                assemblyBytes: assembly.committed,
                temporaryBytes: downloads.temporary + assembly.temporary,
                availableBytes: try await downloadStore.availableCapacity()
            )
        } catch { errorMessage = error.localizedDescription }
    }

    func cleanVerifiedDownloads() {
        Task { await performCleanup {
            try await downloadStore.removeAllCachedAssets(excluding: activeQueueAssetIds)
        } }
    }

    func cleanAssemblies() {
        Task { await performCleanup {
            try await assembler.removeAllCommittedAssemblies(excluding: activeQueueAssetIds)
        } }
    }

    func cleanTemporaryData() {
        Task { await performCleanup {
            try await downloadStore.removeTemporaryData(excluding: activeQueueAssetIds)
            try await assembler.removeTemporaryData()
        } }
    }

    private func performCleanup(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await refreshStorageOverview()
            await refreshLocalAssetStates()
        } catch { errorMessage = error.localizedDescription }
    }

    private func refreshLocalAssetStates() async {
        for asset in assets where !activeQueueAssetIds.contains(asset.assetId) {
            if (try? await history.record(for: asset.assetId)) != nil {
                assetStates[asset.assetId] = .imported
            } else if (try? await history.hasUnconfirmedSubmission(for: asset.assetId)) == true {
                assetStates[asset.assetId] = .needsConfirmation
            } else if (try? await downloadStore.cachedAsset(assetId: asset.assetId)) != nil {
                assetStates[asset.assetId] = .cached
            } else {
                assetStates[asset.assetId] = .available
            }
        }
        overlayQueueStates()
    }

    func disconnect() {
        pauseQueue()
        if let api { Task { await api.disconnect() } }
        api = nil
        selectedCamera = nil
        deviceInfo = nil
        assets = []
        assetStates = [:]
        thumbnailImages = [:]
        loadingThumbnailIds = []
        failedThumbnailIds = []
        selectedAssetIds = []
        selectionMode = false
        pairingCode = ""
        pairingErrorMessage = nil
        lastAttemptedPairingCode = nil
        isRestoringSession = false
        discovery.start()
    }

    func forgetSelectedDevice() {
        if let camera = selectedCamera { try? rememberedDeviceStore.remove(serviceName: camera.name) }
        disconnect()
    }

    private func restoreRememberedSession(for camera: DiscoveredCamera) {
        guard let api, let record = rememberedDeviceStore.record(for: camera.name) else { return }
        isRestoringSession = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await api.restore(record.session)
                let info = try await api.deviceInfo()
                guard info.deviceId == record.deviceId else {
                    throw CameraAPIError.invalidPayload("deviceId")
                }
                deviceInfo = info
                isRestoringSession = false
                await refreshAssets()
                if isQueuePaused { resumeQueue() } else { startQueueIfPossible() }
            } catch {
                try? rememberedDeviceStore.remove(serviceName: camera.name)
                isRestoringSession = false
                pairingErrorMessage = L10n.text("pairing.saved_expired")
                pairingFailureCount += 1
            }
        }
    }
}
