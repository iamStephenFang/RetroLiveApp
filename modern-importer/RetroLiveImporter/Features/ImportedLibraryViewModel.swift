import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

struct ImportedLibraryItem: Identifiable, Equatable {
    let assetId: String
    let localIdentifier: String
    let kind: ImportedAssetKind
    let importedAt: Date
    let creationDate: Date?

    var id: String { localIdentifier }
}

struct ImportedAssetDetails: Equatable, Sendable {
    let filename: String
    let format: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int64
    let latitude: Double?
    let longitude: Double?
}

struct ImportedShareResource: Sendable {
    let url: URL
    let typeIdentifier: String
}

enum ImportedLibraryAccess {
    case notDetermined
    case available
    case limited
    case denied
    case restricted

    var canRead: Bool {
        self == .available || self == .limited
    }
}

enum ImportedLibraryError: Error, LocalizedError {
    case assetUnavailable
    case imageUnavailable
    case livePhotoUnavailable

    var errorDescription: String? {
        switch self {
        case .assetUnavailable: L10n.text("library.asset_unavailable")
        case .imageUnavailable: L10n.text("library.image_unavailable")
        case .livePhotoUnavailable: L10n.text("library.live_photo_unavailable")
        }
    }
}

private final class PhotoRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

private final class PhotoResourceByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total: Int64 = 0

    func add(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        let (value, overflow) = total.addingReportingOverflow(Int64(count))
        total = overflow ? Int64.max : value
    }

    var value: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return total
    }
}

@MainActor
final class ImportedLibraryViewModel: ObservableObject {
    @Published private(set) var items: [ImportedLibraryItem] = []
    @Published private(set) var thumbnails: [String: UIImage] = [:]
    @Published private(set) var access: ImportedLibraryAccess = .notDetermined
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let history: ImportHistoryStore
    private let imageManager: PHCachingImageManager
    private var loadingThumbnailIds: Set<String> = []
    private var assetsByIdentifier: [String: PHAsset] = [:]

    init(
        history: ImportHistoryStore = ImportHistoryStore(),
        imageManager: PHCachingImageManager = PHCachingImageManager()
    ) {
        self.history = history
        self.imageManager = imageManager
        access = Self.mapAuthorization(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        access = Self.mapAuthorization(status)
        await refresh()
    }

    func refresh() async {
        access = Self.mapAuthorization(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        guard access.canRead else {
            items = []
            thumbnails = [:]
            assetsByIdentifier = [:]
            loadingThumbnailIds = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let records = try await history.allRecords()
            let identifiers = records.map(\.localIdentifier)
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: identifiers,
                options: assetFetchOptions(prefetchExtendedMetadata: true)
            )
            var fetchedAssets: [String: PHAsset] = [:]
            result.enumerateObjects { asset, _, _ in
                fetchedAssets[asset.localIdentifier] = asset
            }
            for record in records where fetchedAssets[record.localIdentifier] == nil {
                try await history.removeRecord(for: record.assetId)
            }
            assetsByIdentifier = fetchedAssets
            items = records.compactMap { record in
                guard let asset = fetchedAssets[record.localIdentifier] else { return nil }
                return ImportedLibraryItem(
                    assetId: record.assetId,
                    localIdentifier: record.localIdentifier,
                    kind: record.kind,
                    importedAt: record.importedAt,
                    creationDate: asset.creationDate
                )
            }
            let visibleIds = Set(items.map(\.id))
            thumbnails = thumbnails.filter { visibleIds.contains($0.key) }
            loadingThumbnailIds.formIntersection(visibleIds)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadThumbnail(for item: ImportedLibraryItem) {
        guard thumbnails[item.id] == nil,
              let asset = asset(for: item),
              loadingThumbnailIds.insert(item.id).inserted else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 360, height: 360),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            let degraded = info?[PHImageResultIsDegradedKey] as? Bool == true
            guard let self else { return }
            Task { @MainActor in
                if let image { self.thumbnails[item.id] = image }
                if !degraded { self.loadingThumbnailIds.remove(item.id) }
            }
        }
    }

    func previewImage(for item: ImportedLibraryItem) async throws -> UIImage {
        guard let asset = asset(for: item) else { throw ImportedLibraryError.assetUnavailable }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        let manager = imageManager
        return try await withCheckedThrowingContinuation { continuation in
            let gate = PhotoRequestGate()
            manager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if info?[PHImageResultIsDegradedKey] as? Bool == true { return }
                guard gate.claim() else { return }
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ImportedLibraryError.imageUnavailable)
                }
            }
        }
    }

    func livePhoto(for item: ImportedLibraryItem) async throws -> PHLivePhoto? {
        guard item.kind == .livePhoto else { return nil }
        guard let asset = asset(for: item) else { throw ImportedLibraryError.assetUnavailable }
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let manager = imageManager
        return try await withCheckedThrowingContinuation { continuation in
            let gate = PhotoRequestGate()
            manager.requestLivePhoto(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                if info?[PHImageResultIsDegradedKey] as? Bool == true { return }
                guard gate.claim() else { return }
                if let livePhoto {
                    continuation.resume(returning: livePhoto)
                } else {
                    continuation.resume(throwing: ImportedLibraryError.livePhotoUnavailable)
                }
            }
        }
    }

    func details(for item: ImportedLibraryItem) async throws -> ImportedAssetDetails {
        try await Self.loadDetails(
            localIdentifier: item.localIdentifier,
            kind: item.kind
        )
    }

    func shareResources(for item: ImportedLibraryItem) async throws -> [ImportedShareResource] {
        try await Self.exportShareResources(
            localIdentifier: item.localIdentifier,
            kind: item.kind
        )
    }

    func removeSharedResources(_ resources: [ImportedShareResource]) {
        guard let directory = resources.first?.url.deletingLastPathComponent(),
              directory.deletingLastPathComponent().lastPathComponent == "RetroLiveShare" else {
            return
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private nonisolated static func exportShareResources(
        localIdentifier: String,
        kind: ImportedAssetKind
    ) async throws -> [ImportedShareResource] {
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard let asset = result.firstObject else { throw ImportedLibraryError.assetUnavailable }
        let resources = primaryResources(for: asset, kind: kind)
        guard !resources.isEmpty else { throw ImportedLibraryError.assetUnavailable }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetroLiveShare", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            var exported: [ImportedShareResource] = []
            for (index, resource) in resources.enumerated() {
                let filename = shareFilename(for: resource, index: index)
                let url = directory.appendingPathComponent(filename)
                try await write(resource, to: url)
                exported.append(
                    ImportedShareResource(
                        url: url,
                        typeIdentifier: resource.uniformTypeIdentifier
                    )
                )
            }
            return exported
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private nonisolated static func loadDetails(
        localIdentifier: String,
        kind: ImportedAssetKind
    ) async throws -> ImportedAssetDetails {
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard let asset = result.firstObject else { throw ImportedLibraryError.assetUnavailable }
        let resources = primaryResources(for: asset, kind: kind)
        guard let primaryResource = resources.first else {
            throw ImportedLibraryError.assetUnavailable
        }

        var byteCount: Int64 = 0
        for resource in resources {
            let count = try await resourceByteCount(for: resource)
            let (total, overflow) = byteCount.addingReportingOverflow(count)
            byteCount = overflow ? Int64.max : total
        }

        let contentType = UTType(primaryResource.uniformTypeIdentifier)
        let format = contentType?.localizedDescription
            ?? contentType?.preferredFilenameExtension?.uppercased()
            ?? URL(fileURLWithPath: primaryResource.originalFilename)
                .pathExtension.uppercased()

        return ImportedAssetDetails(
            filename: primaryResource.originalFilename,
            format: format,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            byteCount: byteCount,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude
        )
    }

    func delete(_ item: ImportedLibraryItem) async throws {
        guard let asset = asset(for: item) else { throw ImportedLibraryError.assetUnavailable }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
        try await history.removeRecord(for: item.assetId)
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        assetsByIdentifier[item.id] = nil
        loadingThumbnailIds.remove(item.id)
    }

    private func asset(for item: ImportedLibraryItem) -> PHAsset? {
        assetsByIdentifier[item.localIdentifier]
    }

    private func assetFetchOptions(prefetchExtendedMetadata: Bool) -> PHFetchOptions {
        let options = PHFetchOptions()
        if #available(iOS 27.0, *), prefetchExtendedMetadata {
            options.prefetchAssetExtendedMetadata = true
        }
        return options
    }

    private nonisolated static func primaryResources(
        for asset: PHAsset,
        kind: ImportedAssetKind
    ) -> [PHAssetResource] {
        let resources = PHAssetResource.assetResources(for: asset)
        if kind == .livePhoto {
            return resources.filter { $0.type == .photo || $0.type == .pairedVideo }
        }
        if let photo = resources.first(where: { $0.type == .photo }) {
            return [photo]
        }
        return []
    }

    private nonisolated static func resourceByteCount(
        for resource: PHAssetResource
    ) async throws -> Int64 {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let counter = PhotoResourceByteCounter()
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options
            ) { data in
                counter.add(data.count)
            } completionHandler: { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        return counter.value
    }

    private nonisolated static func write(
        _ resource: PHAssetResource,
        to url: URL
    ) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: url,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private nonisolated static func shareFilename(
        for resource: PHAssetResource,
        index: Int
    ) -> String {
        let original = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
        guard !original.isEmpty else { return "RetroLive-\(index + 1)" }
        return index == 0 ? original : "\(index + 1)-\(original)"
    }

    private static func mapAuthorization(_ status: PHAuthorizationStatus) -> ImportedLibraryAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .available
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}
