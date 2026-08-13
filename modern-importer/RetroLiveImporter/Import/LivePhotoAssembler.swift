@preconcurrency import AVFoundation
import CoreImage
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

struct AssembledAsset: Sendable {
    let assetId: String
    let directoryURL: URL
    let photoURL: URL
    let pairedVideoURL: URL?
}

enum LivePhotoAssemblyError: Error, LocalizedError {
    case invalidStillTime
    case imageSource
    case imageDestination
    case imageContentIdentifier
    case imageMetadata
    case missingVideoTrack
    case reader
    case writer
    case timedMetadata
    case identifierMismatch
    case mediaValidation
    case crop

    var errorDescription: String? {
        switch self {
        case .invalidStillTime:
            L10n.text("assembly.invalid_still_time")
        case .imageSource:
            L10n.text("assembly.image_source")
        case .imageDestination:
            L10n.text("assembly.image_destination")
        case .imageContentIdentifier:
            L10n.text("assembly.image_content_identifier")
        case .imageMetadata:
            L10n.text("assembly.image_metadata")
        case .missingVideoTrack:
            L10n.text("assembly.missing_video_track")
        case .reader:
            L10n.text("assembly.reader")
        case .writer:
            L10n.text("assembly.writer")
        case .timedMetadata:
            L10n.text("assembly.timed_metadata")
        case .identifierMismatch:
            L10n.text("assembly.identifier_mismatch")
        case .mediaValidation:
            L10n.text("assembly.media_validation")
        case .crop:
            L10n.text("assembly.crop")
        }
    }
}

enum FramingGeometry {
    static func targetRatio(
        _ aspectRatio: ManifestV1.AspectRatio,
        for size: CGSize
    ) -> CGFloat {
        size.width >= size.height
            ? aspectRatio.landscapeValue
            : 1.0 / aspectRatio.landscapeValue
    }

    static func centeredCrop(in bounds: CGRect, ratio: CGFloat) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, ratio > 0 else { return .zero }
        let current = bounds.width / bounds.height
        if current > ratio {
            let width = bounds.height * ratio
            return CGRect(x: bounds.midX - width * 0.5, y: bounds.minY, width: width, height: bounds.height)
        }
        let height = bounds.width / ratio
        return CGRect(x: bounds.minX, y: bounds.midY - height * 0.5, width: bounds.width, height: height)
    }

    static func photoCrop(
        in bounds: CGRect,
        motionSize: CGSize?,
        aspectRatio: ManifestV1.AspectRatio
    ) -> CGRect {
        var aperture = bounds
        if let motionSize, motionSize.width > 0, motionSize.height > 0 {
            aperture = centeredCrop(in: bounds, ratio: motionSize.width / motionSize.height)
        }
        return centeredCrop(
            in: aperture,
            ratio: targetRatio(aspectRatio, for: aperture.size)
        )
    }

    static func evenPixelCrop(_ crop: CGRect, within bounds: CGRect) -> CGRect {
        let width = max(2, floor(crop.width / 2) * 2)
        let height = max(2, floor(crop.height / 2) * 2)
        return CGRect(
            x: min(max(bounds.minX, crop.midX - width * 0.5), bounds.maxX - width),
            y: min(max(bounds.minY, crop.midY - height * 0.5), bounds.maxY - height),
            width: width,
            height: height
        )
    }
}

private final class AssemblyTransferState: @unchecked Sendable {
    private let lock = NSLock()
    private var failed = false

    func markFailed() {
        lock.lock()
        failed = true
        lock.unlock()
    }

    func isFailed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return failed
    }
}

private final class AssemblyTrackTransfer: @unchecked Sendable {
    let output: AVAssetReaderTrackOutput
    let input: AVAssetWriterInput

    init(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) {
        self.output = output
        self.input = input
    }
}

private final class AssemblyIO: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter

    init(reader: AVAssetReader, writer: AVAssetWriter) {
        self.reader = reader
        self.writer = writer
    }
}

private final class AssemblyExport: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

actor LivePhotoAssembler {
    private let rootURL: URL
    private let fileManager: FileManager
    private var activeStagingURLs: Set<URL> = []
    private var activeAssetIds: Set<String> = []

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.rootURL = rootURL ?? applicationSupport
            .appendingPathComponent("RetroLive/Assembly", isDirectory: true)
        self.fileManager = fileManager
    }

    func assemble(_ cached: CachedAsset) async throws -> AssembledAsset {
        let assetId = cached.manifest.assetId
        guard activeAssetIds.insert(assetId).inserted else {
            throw LivePhotoAssemblyError.mediaValidation
        }
        defer { activeAssetIds.remove(assetId) }
        let temporaryRoot = rootURL.appendingPathComponent("Temporary", isDirectory: true)
        let assetsRoot = rootURL.appendingPathComponent("Assets", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assetsRoot, withIntermediateDirectories: true)
        try removeAbandonedStagingDirectories(in: temporaryRoot)
        let staging = temporaryRoot.appendingPathComponent(
            "\(assetId)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        activeStagingURLs.insert(staging)
        var committed = false
        defer {
            activeStagingURLs.remove(staging)
            if !committed, fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
        }

        let aspectRatio = cached.manifest.capture.aspectRatio
        let motionSize = cached.manifest.motion.map {
            CGSize(width: $0.width, height: $0.height)
        }
        let pairedPhoto = staging.appendingPathComponent("paired-photo.jpg")
        let pairedPhotoSize = try writePairedPhoto(
            sourceURL: cached.photoURL,
            destinationURL: pairedPhoto,
            assetId: assetId,
            aspectRatio: aspectRatio,
            motionSize: motionSize
        )
        var pairedVideo: URL?
        var croppedVideo: URL?
        if let sourceVideo = cached.motionURL {
            let assemblySource: URL
            if let aspectRatio {
                let cropped = staging.appendingPathComponent("cropped-video.mov")
                assemblySource = try await writeCroppedVideo(
                    sourceURL: sourceVideo,
                    destinationURL: cropped,
                    aspectRatio: aspectRatio
                )
                if assemblySource == cropped { croppedVideo = cropped }
            } else {
                assemblySource = sourceVideo
            }
            let destination = staging.appendingPathComponent("paired-video.mov")
            try await writePairedVideo(
                sourceURL: assemblySource,
                destinationURL: destination,
                assetId: assetId,
                stillTimeSeconds: cached.manifest.capture.stillImageTimeSeconds
            )
            pairedVideo = destination
        }
        try validatePhoto(
            pairedPhoto,
            sourceURL: cached.photoURL,
            assetId: assetId,
            expectedWidth: Int(pairedPhotoSize.width),
            expectedHeight: Int(pairedPhotoSize.height),
            geometryWasNormalized: aspectRatio != nil
        )
        if let pairedVideo {
            try await validateVideo(
                pairedVideo,
                sourceURL: croppedVideo ?? cached.motionURL!,
                assetId: assetId,
                stillTimeSeconds: cached.manifest.capture.stillImageTimeSeconds
            )
        }
        if let croppedVideo { try fileManager.removeItem(at: croppedVideo) }

        let finalURL = assetsRoot.appendingPathComponent(assetId, isDirectory: true)
        if fileManager.fileExists(atPath: finalURL.path) {
            _ = try fileManager.replaceItemAt(
                finalURL,
                withItemAt: staging,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: staging, to: finalURL)
        }
        committed = true
        return AssembledAsset(
            assetId: assetId,
            directoryURL: finalURL,
            photoURL: finalURL.appendingPathComponent("paired-photo.jpg"),
            pairedVideoURL: pairedVideo == nil
                ? nil
                : finalURL.appendingPathComponent("paired-video.mov")
        )
    }

    func hasCommittedAssembly(assetId: String) -> Bool {
        guard UUID(uuidString: assetId) != nil else { return false }
        return fileManager.fileExists(
            atPath: rootURL
                .appendingPathComponent("Assets", isDirectory: true)
                .appendingPathComponent(assetId, isDirectory: true)
                .path
        )
    }

    func storageUsage() throws -> (committed: Int64, temporary: Int64) {
        (
            try directorySize(rootURL.appendingPathComponent("Assets", isDirectory: true)),
            try directorySize(rootURL.appendingPathComponent("Temporary", isDirectory: true))
        )
    }

    func removeAllCommittedAssemblies(excluding protectedAssetIds: Set<String>) throws {
        let protected = protectedAssetIds.union(activeAssetIds)
        let assetsRoot = rootURL.appendingPathComponent("Assets", isDirectory: true)
        for directory in try childDirectories(at: assetsRoot) {
            let assetId = directory.lastPathComponent
            guard UUID(uuidString: assetId) != nil,
                  !protected.contains(assetId) else { continue }
            try fileManager.removeItem(at: directory)
        }
    }

    func removeTemporaryData() throws {
        let temporaryRoot = rootURL.appendingPathComponent("Temporary", isDirectory: true)
        for directory in try childDirectories(at: temporaryRoot)
            where !activeStagingURLs.contains(directory) {
            try fileManager.removeItem(at: directory)
        }
    }

    private func removeAbandonedStagingDirectories(in temporaryRoot: URL) throws {
        let candidates = try fileManager.contentsOfDirectory(
            at: temporaryRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for candidate in candidates where !activeStagingURLs.contains(candidate) {
            try fileManager.removeItem(at: candidate)
        }
    }

    private func writePairedPhoto(
        sourceURL: URL,
        destinationURL: URL,
        assetId: String,
        aspectRatio: ManifestV1.AspectRatio?,
        motionSize: CGSize?
    ) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let type = CGImageSourceGetType(source) else {
            throw LivePhotoAssemblyError.imageSource
        }
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            type,
            1,
            nil
        ) else {
            throw LivePhotoAssemblyError.imageDestination
        }
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any] ?? [:]
        var properties = sourceProperties
        var makerApple = properties[kCGImagePropertyMakerAppleDictionary]
            as? [String: Any] ?? [:]
        makerApple["17"] = assetId
        properties[kCGImagePropertyMakerAppleDictionary] = makerApple
        let outputSize: CGSize
        if let aspectRatio {
            guard let image = CIImage(
                contentsOf: sourceURL,
                options: [.applyOrientationProperty: true]
            ) else {
                throw LivePhotoAssemblyError.imageSource
            }
            let translated = image.transformed(by: CGAffineTransform(
                translationX: -image.extent.minX,
                y: -image.extent.minY
            ))
            let crop = FramingGeometry.photoCrop(
                in: translated.extent,
                motionSize: motionSize,
                aspectRatio: aspectRatio
            ).integral
            let cropped = translated.cropped(to: crop).transformed(by: CGAffineTransform(
                translationX: -crop.minX,
                y: -crop.minY
            ))
            let context = CIContext(options: [.cacheIntermediates: false])
            guard let image = context.createCGImage(cropped, from: cropped.extent) else {
                throw LivePhotoAssemblyError.crop
            }
            outputSize = CGSize(width: image.width, height: image.height)
            properties[kCGImagePropertyOrientation] = 1
            properties[kCGImagePropertyPixelWidth] = image.width
            properties[kCGImagePropertyPixelHeight] = image.height
            properties[kCGImageDestinationLossyCompressionQuality] = 1.0
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        } else {
            outputSize = CGSize(
                width: (sourceProperties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0,
                height: (sourceProperties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            )
            CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoAssemblyError.imageDestination
        }
        return outputSize
    }

    private func writeCroppedVideo(
        sourceURL: URL,
        destinationURL: URL,
        aspectRatio: ManifestV1.AspectRatio
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw LivePhotoAssemblyError.missingVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformedBounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayBounds = CGRect(
            origin: .zero,
            size: CGSize(width: abs(transformedBounds.width), height: abs(transformedBounds.height))
        )
        let targetRatio = FramingGeometry.targetRatio(aspectRatio, for: displayBounds.size)
        let crop = FramingGeometry.evenPixelCrop(
            FramingGeometry.centeredCrop(in: displayBounds, ratio: targetRatio),
            within: displayBounds
        )
        if abs(crop.width - displayBounds.width) < 1,
           abs(crop.height - displayBounds.height) < 1 {
            return sourceURL
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        let composition = AVMutableVideoComposition()
        composition.renderSize = crop.size
        let frameRate = try await track.load(.nominalFrameRate)
        composition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(max(1, lroundf(frameRate > 0 ? frameRate : 30)))
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let normalization = CGAffineTransform(
            translationX: -transformedBounds.minX - crop.minX,
            y: -transformedBounds.minY - crop.minY
        )
        layerInstruction.setTransform(preferredTransform.concatenating(normalization), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        guard let export = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw LivePhotoAssemblyError.crop
        }
        export.videoComposition = composition
        if #available(iOS 18.0, *) {
            try await export.export(to: destinationURL, as: .mov)
            return destinationURL
        }
        export.outputURL = destinationURL
        export.outputFileType = .mov
        let exportState = AssemblyExport(export)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                exportState.session.exportAsynchronously {
                    switch exportState.session.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    default:
                        continuation.resume(
                            throwing: exportState.session.error ?? LivePhotoAssemblyError.crop
                        )
                    }
                }
            }
        } onCancel: {
            exportState.session.cancelExport()
        }
        return destinationURL
    }

    private func writePairedVideo(
        sourceURL: URL,
        destinationURL: URL,
        assetId: String,
        stillTimeSeconds: Double
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        guard stillTimeSeconds >= 0,
              CMTimeCompare(
                CMTime(seconds: stillTimeSeconds, preferredTimescale: 600),
                duration
              ) < 0 else {
            throw LivePhotoAssemblyError.invalidStillTime
        }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw LivePhotoAssemblyError.missingVideoTrack
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)

        let identifier = AVMutableMetadataItem()
        identifier.identifier = .quickTimeMetadataContentIdentifier
        identifier.value = assetId as NSString
        identifier.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [identifier]

        var transfers: [AssemblyTrackTransfer] = []
        for track in videoTracks + audioTracks {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            guard reader.canAdd(output) else { throw LivePhotoAssemblyError.reader }
            reader.add(output)
            let formatDescriptions = try await track.load(.formatDescriptions)
            let input = AVAssetWriterInput(
                mediaType: track.mediaType,
                outputSettings: nil,
                sourceFormatHint: formatDescriptions.first
            )
            if track.mediaType == .video {
                input.transform = try await track.load(.preferredTransform)
            }
            guard writer.canAdd(input) else { throw LivePhotoAssemblyError.writer }
            writer.add(input)
            transfers.append(AssemblyTrackTransfer(output: output, input: input))
        }

        let metadataSpecification: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                kCMMetadataBaseDataType_SInt8 as String
        ]
        var metadataDescription: CMFormatDescription?
        let descriptionStatus = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [metadataSpecification] as CFArray,
            formatDescriptionOut: &metadataDescription
        )
        guard descriptionStatus == noErr, let metadataDescription else {
            throw LivePhotoAssemblyError.timedMetadata
        }
        let metadataInput = AVAssetWriterInput(
            mediaType: .metadata,
            outputSettings: nil,
            sourceFormatHint: metadataDescription
        )
        guard writer.canAdd(metadataInput) else {
            throw LivePhotoAssemblyError.timedMetadata
        }
        writer.add(metadataInput)
        let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)

        guard writer.startWriting() else {
            throw writer.error ?? reader.error ?? LivePhotoAssemblyError.writer
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw reader.error ?? LivePhotoAssemblyError.reader
        }
        writer.startSession(atSourceTime: .zero)
        let stillItem = AVMutableMetadataItem()
        stillItem.identifier = AVMetadataIdentifier(
            rawValue: "mdta/com.apple.quicktime.still-image-time"
        )
        stillItem.value = NSNumber(value: Int8(0))
        stillItem.dataType = kCMMetadataBaseDataType_SInt8 as String
        let stillTime = CMTime(seconds: stillTimeSeconds, preferredTimescale: 600)
        let nominalMetadataDuration = CMTime(value: 1, timescale: 30)
        let remainingDuration = CMTimeSubtract(duration, stillTime)
        let metadataDuration = CMTimeCompare(nominalMetadataDuration, remainingDuration) < 0
            ? nominalMetadataDuration
            : remainingDuration
        guard CMTimeCompare(metadataDuration, .zero) > 0,
              metadataAdaptor.append(
            AVTimedMetadataGroup(
                items: [stillItem],
                timeRange: CMTimeRange(
                    start: stillTime,
                    duration: metadataDuration
                )
            )
        ) else {
            reader.cancelReading()
            writer.cancelWriting()
            throw LivePhotoAssemblyError.timedMetadata
        }
        metadataInput.markAsFinished()

        let io = AssemblyIO(reader: reader, writer: writer)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                let group = DispatchGroup()
                let state = AssemblyTransferState()
                for (index, transfer) in transfers.enumerated() {
                    group.enter()
                    let queue = DispatchQueue(label: "com.retrolive.assembly.track.\(index)")
                    transfer.input.requestMediaDataWhenReady(on: queue) {
                        while transfer.input.isReadyForMoreMediaData {
                            guard let sample = transfer.output.copyNextSampleBuffer() else {
                                transfer.input.markAsFinished()
                                group.leave()
                                return
                            }
                            if !transfer.input.append(sample) {
                                state.markFailed()
                                io.reader.cancelReading()
                                transfer.input.markAsFinished()
                                group.leave()
                                return
                            }
                        }
                    }
                }
                group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                    if io.reader.status == .cancelled || io.writer.status == .cancelled {
                        io.writer.cancelWriting()
                        continuation.resume(throwing: CancellationError())
                    } else if state.isFailed() || io.reader.status == .failed {
                        io.writer.cancelWriting()
                        continuation.resume(
                            throwing: io.reader.error
                                ?? io.writer.error
                                ?? LivePhotoAssemblyError.reader
                        )
                    } else {
                        io.writer.finishWriting {
                            switch io.writer.status {
                            case .completed:
                                continuation.resume()
                            case .cancelled:
                                continuation.resume(throwing: CancellationError())
                            default:
                                continuation.resume(
                                    throwing: io.writer.error ?? LivePhotoAssemblyError.writer
                                )
                            }
                        }
                    }
                }
            }
        } onCancel: {
            io.reader.cancelReading()
            io.writer.cancelWriting()
        }
    }

    private func validatePhoto(
        _ url: URL,
        sourceURL: URL,
        assetId: String,
        expectedWidth: Int,
        expectedHeight: Int,
        geometryWasNormalized: Bool
    ) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else {
            throw LivePhotoAssemblyError.imageSource
        }
        guard (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == expectedWidth,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == expectedHeight else {
            throw LivePhotoAssemblyError.mediaValidation
        }
        guard let makerApple = properties[kCGImagePropertyMakerAppleDictionary]
                as? [String: Any],
              makerApple["17"] as? String == assetId else {
            throw LivePhotoAssemblyError.imageContentIdentifier
        }
        guard let originalSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let original = CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil)
                as? [CFString: Any] else {
            throw LivePhotoAssemblyError.imageSource
        }
        let preservedTopLevelKeys: [CFString] = [
            kCGImagePropertyProfileName,
            kCGImagePropertyColorModel
        ]
        for key in preservedTopLevelKeys where !metadataValue(original[key], equals: properties[key]) {
            throw LivePhotoAssemblyError.imageMetadata
        }
        if !geometryWasNormalized,
           !metadataValue(original[kCGImagePropertyOrientation], equals: properties[kCGImagePropertyOrientation]) {
            throw LivePhotoAssemblyError.imageMetadata
        }
        guard metadataFieldsArePreserved(
            from: original[kCGImagePropertyGPSDictionary],
            to: properties[kCGImagePropertyGPSDictionary],
            keys: [
                "LatitudeRef", "Latitude", "LongitudeRef", "Longitude", "AltitudeRef", "Altitude",
                "TimeStamp", "DateStamp", "ImgDirectionRef", "ImgDirection", "SpeedRef", "Speed"
            ]
        ) else {
            throw LivePhotoAssemblyError.imageMetadata
        }
        guard metadataFieldsArePreserved(
            from: original[kCGImagePropertyTIFFDictionary],
            to: properties[kCGImagePropertyTIFFDictionary],
            keys: ["Make", "Model", "Software", "DateTime", "Artist", "Copyright"]
        ) else {
            throw LivePhotoAssemblyError.imageMetadata
        }
        guard metadataFieldsArePreserved(
            from: original[kCGImagePropertyExifDictionary],
            to: properties[kCGImagePropertyExifDictionary],
            keys: [
                "DateTimeOriginal", "DateTimeDigitized", "ExposureTime", "FNumber",
                "ExposureProgram", "ISOSpeedRatings", "ShutterSpeedValue", "ApertureValue",
                "BrightnessValue", "ExposureBiasValue", "MeteringMode", "LightSource", "Flash",
                "FocalLength", "SensingMethod", "ExposureMode", "WhiteBalance", "DigitalZoomRatio",
                "FocalLenIn35mmFilm", "SceneCaptureType", "LensSpecification", "LensMake",
                "LensModel", "LensSerialNumber", "BodySerialNumber"
            ]
        ) else {
            throw LivePhotoAssemblyError.imageMetadata
        }
    }

    private func metadataFieldsArePreserved(
        from originalValue: Any?,
        to outputValue: Any?,
        keys: [String]
    ) -> Bool {
        guard let original = originalValue as? [String: Any] else { return true }
        guard let output = outputValue as? [String: Any] else { return false }
        return keys.allSatisfy { key in
            guard let originalField = original[key] else { return true }
            return metadataValue(originalField, equals: output[key])
        }
    }

    private func metadataValue(_ lhs: Any?, equals rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (left?, right?):
            (left as AnyObject).isEqual(right)
        default:
            false
        }
    }

    private func childDirectories(at root: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
    }

    private func directorySize(_ directory: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey
            ])
            guard values.isRegularFile == true else { continue }
            total += Int64(
                values.totalFileAllocatedSize ??
                values.fileAllocatedSize ??
                values.fileSize ?? 0
            )
        }
        return total
    }

    private func validateVideo(
        _ url: URL,
        sourceURL: URL,
        assetId: String,
        stillTimeSeconds: Double
    ) async throws {
        let asset = AVURLAsset(url: url)
        let metadata = try await asset.load(.metadata)
        let identifierItems = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .quickTimeMetadataContentIdentifier
        )
        let contentIdentifier: String?
        if let item = identifierItems.first {
            contentIdentifier = try await item.load(.stringValue)
        } else {
            contentIdentifier = nil
        }
        guard contentIdentifier == assetId else {
            throw LivePhotoAssemblyError.identifierMismatch
        }
        let sourceAsset = AVURLAsset(url: sourceURL)
        let sourceVideoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        let outputVideoTracks = try await asset.loadTracks(withMediaType: .video)
        let sourceAudioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        let outputAudioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !outputVideoTracks.isEmpty,
              outputVideoTracks.count == sourceVideoTracks.count,
              outputAudioTracks.count == sourceAudioTracks.count else {
            throw LivePhotoAssemblyError.mediaValidation
        }
        for (sourceTrack, outputTrack) in zip(sourceVideoTracks, outputVideoTracks) {
            let sourceTransform = try await sourceTrack.load(.preferredTransform)
            let outputTransform = try await outputTrack.load(.preferredTransform)
            let sourceSize = try await sourceTrack.load(.naturalSize)
            let outputSize = try await outputTrack.load(.naturalSize)
            guard sourceTransform == outputTransform, sourceSize == outputSize else {
                throw LivePhotoAssemblyError.mediaValidation
            }
        }
        let sourceDuration = try await sourceAsset.load(.duration)
        let outputDuration = try await asset.load(.duration)
        let frameRate = try await sourceVideoTracks[0].load(.nominalFrameRate)
        let tolerance = max(1.0 / 600.0, frameRate > 0 ? 1.0 / Double(frameRate) : 1.0 / 30.0)
        guard abs(CMTimeGetSeconds(sourceDuration) - CMTimeGetSeconds(outputDuration)) <= tolerance else {
            throw LivePhotoAssemblyError.mediaValidation
        }
        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        var foundStillTime = false
        for metadataTrack in metadataTracks {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)
            guard reader.canAdd(output) else { continue }
            reader.add(output)
            let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
            guard reader.startReading() else { continue }
            while let group = adaptor.nextTimedMetadataGroup() {
                let containsStillItem = group.items.contains {
                    $0.identifier?.rawValue == "mdta/com.apple.quicktime.still-image-time"
                }
                if containsStillItem,
                   abs(CMTimeGetSeconds(group.timeRange.start) - stillTimeSeconds) <= tolerance {
                    foundStillTime = true
                    break
                }
            }
            reader.cancelReading()
            if foundStillTime { break }
        }
        guard foundStillTime else {
            throw LivePhotoAssemblyError.timedMetadata
        }
    }
}
