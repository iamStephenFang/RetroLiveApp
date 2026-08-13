import Photos

protocol PhotoLibraryImporting: Sendable {
    func authorizeForAdditions() async throws
    func importPhoto(photoURL: URL, captureDate: Date) async throws -> String
    func importLivePhoto(
        photoURL: URL,
        pairedVideoURL: URL,
        captureDate: Date
    ) async throws -> String
}

enum PhotoLibraryImportError: Error, LocalizedError {
    case permissionDenied
    case missingPlaceholder
    case photoKitFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            L10n.text("photos.permission_denied")
        case .missingPlaceholder:
            L10n.text("photos.missing_placeholder")
        case .photoKitFailed:
            L10n.text("photos.write_failed")
        }
    }
}

struct PhotoLibraryImporter: PhotoLibraryImporting, Sendable {
    func authorizeForAdditions() async throws {
        try await authorize()
    }

    func importPhoto(photoURL: URL, captureDate: Date) async throws -> String {
        try await authorize()
        return try await createAsset(
            photoURL: photoURL,
            pairedVideoURL: nil,
            captureDate: captureDate
        )
    }

    func importLivePhoto(
        photoURL: URL,
        pairedVideoURL: URL,
        captureDate: Date
    ) async throws -> String {
        try await authorize()
        return try await createAsset(
            photoURL: photoURL,
            pairedVideoURL: pairedVideoURL,
            captureDate: captureDate
        )
    }

    private func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryImportError.permissionDenied
        }
    }

    private func createAsset(
        photoURL: URL,
        pairedVideoURL: URL?,
        captureDate: Date
    ) async throws -> String {
        var placeholderIdentifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = captureDate
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
        } catch {
            throw PhotoLibraryImportError.photoKitFailed
        }
        guard let placeholderIdentifier else {
            throw PhotoLibraryImportError.missingPlaceholder
        }
        return placeholderIdentifier
    }
}
