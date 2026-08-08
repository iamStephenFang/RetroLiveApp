@preconcurrency import AVFoundation
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
    case imageMetadata
    case missingVideoTrack
    case reader
    case writer
    case timedMetadata
    case identifierMismatch
    case mediaValidation

    var errorDescription: String? {
        switch self {
        case .invalidStillTime:
            "Manifest 中的静态帧时间不在视频范围内。"
        case .imageSource:
            "无法读取源照片。"
        case .imageDestination:
            "无法生成配对照片。"
        case .imageMetadata:
            "配对照片的内容标识写入失败。"
        case .missingVideoTrack:
            "动态素材不包含视频轨道。"
        case .reader:
            "无法读取源动态视频。"
        case .writer:
            "无法生成 Live Photo 配对视频。"
        case .timedMetadata:
            "无法写入 Live Photo 静态帧时间。"
        case .identifierMismatch:
            "生成资源的配对标识不一致。"
        case .mediaValidation:
            "生成资源的尺寸、轨道、方向或时间信息与源素材不一致。"
        }
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

actor LivePhotoAssembler {
    private let rootURL: URL
    private let fileManager: FileManager
    private var activeStagingURLs: Set<URL> = []

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

        let pairedPhoto = staging.appendingPathComponent("paired-photo.jpg")
        try writePairedPhoto(sourceURL: cached.photoURL, destinationURL: pairedPhoto, assetId: assetId)
        var pairedVideo: URL?
        if let sourceVideo = cached.motionURL {
            let destination = staging.appendingPathComponent("paired-video.mov")
            try await writePairedVideo(
                sourceURL: sourceVideo,
                destinationURL: destination,
                assetId: assetId,
                stillTimeSeconds: cached.manifest.capture.stillImageTimeSeconds
            )
            pairedVideo = destination
        }
        try validatePhoto(
            pairedPhoto,
            assetId: assetId,
            expectedWidth: cached.manifest.photo.width,
            expectedHeight: cached.manifest.photo.height
        )
        if let pairedVideo {
            try await validateVideo(
                pairedVideo,
                sourceURL: cached.motionURL!,
                assetId: assetId,
                stillTimeSeconds: cached.manifest.capture.stillImageTimeSeconds
            )
        }

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

    private func writePairedPhoto(sourceURL: URL, destinationURL: URL, assetId: String) throws {
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
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoAssemblyError.imageDestination
        }
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

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            let state = AssemblyTransferState()
            let io = AssemblyIO(reader: reader, writer: writer)
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
                if state.isFailed() || io.reader.status == .failed {
                    io.writer.cancelWriting()
                    continuation.resume(
                        throwing: io.reader.error ?? io.writer.error ?? LivePhotoAssemblyError.reader
                    )
                    return
                }
                io.writer.finishWriting {
                    if io.writer.status == .completed {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: io.writer.error ?? LivePhotoAssemblyError.writer
                        )
                    }
                }
            }
        }
    }

    private func validatePhoto(
        _ url: URL,
        assetId: String,
        expectedWidth: Int,
        expectedHeight: Int
    ) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == expectedWidth,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == expectedHeight,
              let makerApple = properties[kCGImagePropertyMakerAppleDictionary]
                as? [String: Any],
              makerApple["17"] as? String == assetId else {
            throw LivePhotoAssemblyError.imageMetadata
        }
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
