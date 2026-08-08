import Photos

enum PhotoLibraryImportError: Error, LocalizedError {
    case permissionDenied
    case missingPlaceholder
    case photoKitFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "没有添加照片的权限，请在系统设置中允许 RetroLive 写入照片。"
        case .missingPlaceholder:
            "Photos 没有返回新素材的标识。"
        case .photoKitFailed:
            "Photos 未能完成素材写入。"
        }
    }
}

struct PhotoLibraryImporter: Sendable {
    func importPhoto(photoURL: URL) async throws -> String {
        try await authorize()
        return try await createAsset(photoURL: photoURL, pairedVideoURL: nil)
    }

    func importLivePhoto(photoURL: URL, pairedVideoURL: URL) async throws -> String {
        try await authorize()
        return try await createAsset(photoURL: photoURL, pairedVideoURL: pairedVideoURL)
    }

    private func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryImportError.permissionDenied
        }
    }

    private func createAsset(photoURL: URL, pairedVideoURL: URL?) async throws -> String {
        var placeholderIdentifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let photoOptions = PHAssetResourceCreationOptions()
            photoOptions.shouldMoveFile = false
            request.addResource(with: .photo, fileURL: photoURL, options: photoOptions)
            if let pairedVideoURL {
                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.shouldMoveFile = false
                request.addResource(
                    with: .pairedVideo,
                    fileURL: pairedVideoURL,
                    options: videoOptions
                )
            }
            placeholderIdentifier = request.placeholderForCreatedAsset?.localIdentifier
        }
        guard let placeholderIdentifier else {
            throw PhotoLibraryImportError.missingPlaceholder
        }
        return placeholderIdentifier
    }
}
