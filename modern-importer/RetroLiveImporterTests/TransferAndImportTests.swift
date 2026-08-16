import CryptoKit
@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import ImageIO
import XCTest
@testable import RetroLiveImporter

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class TransferAndImportTests: XCTestCase {
    func testImportQueueRecoveryRestartsSafeStagesAndQuarantinesImporting() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetroLiveTests-\(UUID().uuidString)/queue", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("import-queue.json")
        let summaryA = CameraAssetSummary(
            assetId: UUID().uuidString,
            createdAt: "2026-08-13T00:00:00Z",
            thumbnailURL: nil,
            manifestURL: "/manifest-a",
            hasMotion: true
        )
        let summaryB = CameraAssetSummary(
            assetId: UUID().uuidString,
            createdAt: "2026-08-13T00:01:00Z",
            thumbnailURL: nil,
            manifestURL: "/manifest-b",
            hasMotion: false
        )
        let store = ImportQueueStore(fileURL: fileURL)
        try await store.save([
            ImportQueueItem(deviceId: "device", summary: summaryA, status: .downloading, progress: 0.5),
            ImportQueueItem(deviceId: "device", summary: summaryB, status: .importing, progress: 1)
        ])

        let recovered = try await ImportQueueStore(fileURL: fileURL).loadRecoveringInterruptedItems()
        XCTAssertEqual(recovered[0].status, .queued)
        XCTAssertEqual(recovered[0].progress, 0)
        XCTAssertEqual(recovered[1].status, .needsConfirmation)
    }

    func testStoragePreflightRetainsSafetyMargin() {
        let sufficient = ImportStoragePreflight(
            requiredAdditionalBytes: 100,
            availableBytes: ImportStoragePreflight.safetyMarginBytes + 100
        )
        let insufficient = ImportStoragePreflight(
            requiredAdditionalBytes: 101,
            availableBytes: ImportStoragePreflight.safetyMarginBytes + 100
        )
        XCTAssertTrue(sufficient.isSufficient)
        XCTAssertFalse(insufficient.isSufficient)
    }

    func testStoragePreflightArithmeticSaturatesInsteadOfOverflowing() {
        XCTAssertEqual(
            ImportStoragePreflight.clampedAdd(Int64.max - 1, 2),
            Int64.max
        )
        XCTAssertEqual(
            ImportStoragePreflight.clampedMultiply(Int64.max / 2 + 1, by: 2),
            Int64.max
        )
        XCTAssertEqual(ImportStoragePreflight.clampedAdd(20, -10), 20)
    }

    func testManifestCaptureDateUsesCanonicalUnixMilliseconds() throws {
        let manifest = try ManifestParser().parse(try fixtureData("valid-v1"))
        XCTAssertEqual(
            manifest.captureDate.timeIntervalSince1970,
            Double(manifest.createdAtUnixMilliseconds) / 1_000,
            accuracy: 0.000_001
        )
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testCameraURLAndPaginatedAPI() async throws {
        let camera = DiscoveredCamera(
            id: "camera",
            name: "RetroLive-1234",
            host: "camera.local.",
            port: 8080
        )
        XCTAssertEqual(camera.baseURL.absoluteString, "http://camera.local:8080/api/v1")
        XCTAssertEqual(camera.endpointDescription, "camera.local:8080")
        let session = mockSession()
        let client = CameraAPIClient(baseURL: camera.baseURL, session: session)
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/session") {
                return Self.response(request, status: 200, json: [
                    "token": "abcdefghijklmnopqrstuvwxyz123456",
                    "expiresInSeconds": 900
                ])
            }
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer abcdefghijklmnopqrstuvwxyz123456"
            )
            if path.hasSuffix("/device") {
                return Self.response(request, status: 200, json: [
                    "protocolVersion": 1,
                    "deviceId": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
                    "deviceName": "Camera",
                    "modelIdentifier": "iPhone4,1",
                    "systemVersion": "6.1.6",
                    "appVersion": "1.0",
                    "assetCount": 2,
                    "capabilities": [
                        "rangeDownload": true,
                        "batchExport": false,
                        "delete": false
                    ]
                ])
            }
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "cursor" })?.value
            let id = cursor == nil
                ? "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
                : "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"
            let nextCursor: Any = cursor == nil ? id : NSNull()
            return Self.response(request, status: 200, json: [
                "items": [[
                    "assetId": id,
                    "createdAt": "2026-08-08T10:00:00.000Z",
                    "manifestURL": "/api/v1/assets/\(id)/manifest"
                ]],
                "nextCursor": nextCursor
            ])
        }

        try await client.pair(code: "123456", clientName: "Tests")
        let deviceInfo = try await client.deviceInfo()
        XCTAssertEqual(deviceInfo.assetCount, 2)
        let assets = try await client.allAssets(pageSize: 1)
        XCTAssertEqual(assets.map(\.assetId), [
            "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB",
            "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"
        ])
    }

    func testPairingSessionCanBeRestoredAndThumbnailIsAuthorized() async throws {
        let session = mockSession()
        let baseURL = URL(string: "http://camera.local:8080/api/v1")!
        let client = CameraAPIClient(baseURL: baseURL, session: session)
        let thumbnail = Data("thumbnail-payload".utf8)
        let photo = Data("full-photo-payload".utf8)
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/session") {
                return Self.response(request, status: 200, json: [
                    "token": "abcdefghijklmnopqrstuvwxyz123456",
                    "expiresInSeconds": 900
                ])
            }
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer abcdefghijklmnopqrstuvwxyz123456"
            )
            if path.hasSuffix("/thumbnail") {
                return Self.response(request, status: 200, data: thumbnail)
            }
            if path.hasSuffix("/photo") {
                return Self.response(request, status: 200, data: photo)
            }
            return Self.response(request, status: 200, json: [
                "protocolVersion": 1,
                "deviceId": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
                "deviceName": "Camera",
                "modelIdentifier": "iPhone4,1",
                "systemVersion": "6.1.6",
                "appVersion": "1.0",
                "assetCount": 1,
                "capabilities": [
                    "rangeDownload": true,
                    "batchExport": false,
                    "delete": false
                ]
            ])
        }

        let pairingSession = try await client.pair(
            code: "123456",
            clientName: "Tests",
            rememberDevice: true
        )
        XCTAssertTrue(pairingSession.isValid)
        let summary = CameraAssetSummary(
            assetId: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB",
            createdAt: "2026-08-08T10:00:00.000Z",
            thumbnailURL: "/api/v1/assets/BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB/thumbnail",
            manifestURL: "/api/v1/assets/BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB/manifest",
            hasMotion: true
        )
        let loadedThumbnail = try await client.previewData(for: summary)
        XCTAssertEqual(loadedThumbnail, thumbnail)
        let loadedPhoto = try await client.photoData(for: summary)
        XCTAssertEqual(loadedPhoto, photo)

        let restoredClient = CameraAPIClient(baseURL: baseURL, session: session)
        try await restoredClient.restore(pairingSession)
        let device = try await restoredClient.deviceInfo()
        XCTAssertEqual(device.deviceName, "Camera")
    }

    func testPaginationLoopIsRejected() async throws {
        let session = mockSession()
        let client = CameraAPIClient(
            baseURL: URL(string: "http://camera.local:8080/api/v1")!,
            session: session
        )
        let assetId = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        MockURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/session") {
                return Self.response(request, status: 200, json: [
                    "token": "abcdefghijklmnopqrstuvwxyz123456",
                    "expiresInSeconds": 900
                ])
            }
            let hasCursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(where: { $0.name == "cursor" }) == true
            let items: [[String: String]] = hasCursor ? [] : [[
                "assetId": assetId,
                "createdAt": "2026-08-08T10:00:00.000Z",
                "manifestURL": "/api/v1/assets/\(assetId)/manifest"
            ]]
            return Self.response(request, status: 200, json: [
                "items": items,
                "nextCursor": assetId
            ])
        }
        try await client.pair(code: "123456", clientName: "Tests")
        do {
            _ = try await client.allAssets(pageSize: 1)
            XCTFail("Expected repeated pagination cursor to fail")
        } catch {
            XCTAssertEqual(error as? CameraAPIError, .paginationLoop)
        }
    }

    func testRangeResumeValidationAndHistoryIdempotency() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let assetId = "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD"
        let photo = Data("verified-photo-payload".utf8)
        let manifestData = try photoOnlyManifest(
            assetId: assetId,
            photo: photo
        )
        let partialCount = 7
        let staging = temporary
            .appendingPathComponent("Downloads/Temporary/\(assetId)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try manifestData.write(to: staging.appendingPathComponent("manifest.json"))
        try photo.prefix(partialCount).write(
            to: staging.appendingPathComponent("photo.jpg.partial")
        )

        let session = mockSession()
        let client = CameraAPIClient(
            baseURL: URL(string: "http://camera.local:8080/api/v1")!,
            session: session
        )
        MockURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/session") {
                return Self.response(request, status: 200, json: [
                    "token": "abcdefghijklmnopqrstuvwxyz123456",
                    "expiresInSeconds": 900
                ])
            }
            if request.url!.path.hasSuffix("/manifest") {
                return Self.response(request, status: 200, data: manifestData)
            }
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Range"),
                "bytes=\(partialCount)-"
            )
            return Self.response(
                request,
                status: 206,
                data: photo.dropFirst(partialCount),
                headers: [
                    "Content-Range": "bytes \(partialCount)-\(photo.count - 1)/\(photo.count)"
                ]
            )
        }
        try await client.pair(code: "123456", clientName: "Tests")
        let store = DownloadStore(
            rootURL: temporary.appendingPathComponent("Downloads"),
            session: session
        )
        let cached = try await store.download(
            summary: CameraAssetSummary(
                assetId: assetId,
                createdAt: "2026-08-08T10:00:00.000Z",
                thumbnailURL: nil,
                manifestURL: "/api/v1/assets/\(assetId)/manifest"
            ),
            api: client
        )
        XCTAssertEqual(try Data(contentsOf: cached.photoURL), photo)
        XCTAssertNil(cached.motionURL)

        let history = ImportHistoryStore(
            fileURL: temporary.appendingPathComponent("history.json")
        )
        let first = ImportRecord(
            assetId: assetId,
            localIdentifier: "photos-1",
            kind: .photo,
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let replacement = ImportRecord(
            assetId: assetId,
            localIdentifier: "photos-2",
            kind: .livePhoto,
            importedAt: Date(timeIntervalSince1970: 2)
        )
        try await history.save(first)
        try await history.save(replacement)
        let records = try await history.allRecords()
        XCTAssertEqual(records, [replacement])
    }

    func testImportJournalPersistsUnconfirmedSubmissionAndMigratesLegacyHistory() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let fileURL = temporary.appendingPathComponent("history.json")
        let assetId = "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE"
        let history = ImportHistoryStore(fileURL: fileURL)

        let began = try await history.beginSubmission(assetId: assetId, kind: .livePhoto)
        let beganTwice = try await history.beginSubmission(assetId: assetId, kind: .livePhoto)
        let isUnconfirmed = try await history.hasUnconfirmedSubmission(for: assetId)
        let pendingRecord = try await history.record(for: assetId)
        XCTAssertTrue(began)
        XCTAssertFalse(beganTwice)
        XCTAssertTrue(isUnconfirmed)
        XCTAssertNil(pendingRecord)

        let relaunched = ImportHistoryStore(fileURL: fileURL)
        let relaunchedIsUnconfirmed = try await relaunched.hasUnconfirmedSubmission(for: assetId)
        XCTAssertTrue(relaunchedIsUnconfirmed)
        try await relaunched.cancelSubmission(for: assetId)
        let cancelledIsUnconfirmed = try await relaunched.hasUnconfirmedSubmission(for: assetId)
        XCTAssertFalse(cancelledIsUnconfirmed)

        let legacyRecord = ImportRecord(
            assetId: assetId,
            localIdentifier: "legacy-photo-id",
            kind: .photo,
            importedAt: Date(timeIntervalSince1970: 10)
        )
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode([legacyRecord]).write(to: fileURL, options: .atomic)
        let migrated = ImportHistoryStore(fileURL: fileURL)
        let migratedRecord = try await migrated.record(for: assetId)
        XCTAssertEqual(migratedRecord, legacyRecord)
        try await migrated.save(legacyRecord)
        let migratedRecords = try await migrated.allRecords()
        XCTAssertEqual(migratedRecords, [legacyRecord])
    }

    func testAssemblerAppliesSameFourThreeFrameToPhotoAndMotion() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let photoURL = temporary.appendingPathComponent("photo.jpg")
        let motionURL = temporary.appendingPathComponent("motion.mov")
        try writeTestJPEG(to: photoURL, size: CGSize(width: 640, height: 480))
        try await writeTestMovie(to: motionURL, size: CGSize(width: 640, height: 360))
        let assetId = UUID().uuidString.uppercased()
        let manifest = try ManifestParser().parse(try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "assetId": assetId,
            "createdAt": "2026-08-10T00:00:00.000Z",
            "createdAtUnixMilliseconds": 1_786_320_000_000,
            "capture": [
                "cameraPosition": "back", "orientation": 1, "mirrored": false,
                "flashMode": "off", "aspectRatio": "4:3", "stillImageTimeSeconds": 0.5,
                "stillImageTimeAccuracy": "measured", "preRollSeconds": 0.5,
                "postRollSeconds": 0.5
            ],
            "photo": [
                "filename": "photo.jpg", "mimeType": "image/jpeg", "width": 640,
                "height": 480, "byteLength": 1, "sha256": String(repeating: "0", count: 64)
            ],
            "motion": [
                "filename": "motion.mov", "mimeType": "video/quicktime", "durationSeconds": 1.0,
                "width": 640, "height": 360, "frameRate": 30, "hasAudio": false,
                "byteLength": 1, "sha256": String(repeating: "0", count: 64)
            ],
            "device": ["modelIdentifier": "test", "systemVersion": "test", "appVersion": "1"]
        ]))
        let assembler = LivePhotoAssembler(
            rootURL: temporary.appendingPathComponent("assembly", isDirectory: true)
        )
        let cached = CachedAsset(
            manifest: manifest,
            directoryURL: temporary,
            photoURL: photoURL,
            motionURL: motionURL
        )
        let assembled = try await assembler.assemble(cached)
        try FileManager.default.removeItem(at: photoURL)
        try FileManager.default.removeItem(at: motionURL)
        let reused = try await assembler.assemble(cached)
        XCTAssertEqual(reused.photoURL, assembled.photoURL)
        XCTAssertEqual(reused.pairedVideoURL, assembled.pairedVideoURL)

        let photoSource = try XCTUnwrap(CGImageSourceCreateWithURL(assembled.photoURL as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(photoSource, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 480)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 360)
        let makerApple = try XCTUnwrap(
            properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any]
        )
        XCTAssertEqual(makerApple["17"] as? String, assetId)
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary] as? [String: Any])
        XCTAssertEqual(tiff["Make"] as? String, "RetroLive")
        XCTAssertEqual(tiff["Model"] as? String, "Test Camera")
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [String: Any])
        XCTAssertEqual(exif["Flash"] as? NSNumber, 1)
        XCTAssertEqual(exif["DateTimeOriginal"] as? String, "2026:08:10 00:00:00")
        let videoAsset = AVURLAsset(url: try XCTUnwrap(assembled.pairedVideoURL))
        let tracks = try await videoAsset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let bounds = CGRect(origin: .zero, size: try await track.load(.naturalSize))
            .applying(try await track.load(.preferredTransform))
        XCTAssertEqual(abs(bounds.width), 480, accuracy: 1)
        XCTAssertEqual(abs(bounds.height), 360, accuracy: 1)
    }

    func testAssemblerSuppliesMissingCameraMakeAndModelFromManifestDevice() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let photoURL = temporary.appendingPathComponent("photo.jpg")
        let motionURL = temporary.appendingPathComponent("motion.mov")
        try writeTestJPEG(
            to: photoURL,
            size: CGSize(width: 640, height: 480),
            properties: [
                kCGImagePropertyExifDictionary: [
                    "LensModel": "iPhone 5c back camera 4.12mm f/2.4"
                ]
            ]
        )
        try await writeTestMovie(to: motionURL, size: CGSize(width: 640, height: 480))
        let assetId = UUID().uuidString.uppercased()
        let manifest = try ManifestParser().parse(try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "assetId": assetId,
            "createdAt": "2026-08-16T00:00:00.000Z",
            "createdAtUnixMilliseconds": 1_786_838_400_000,
            "capture": [
                "cameraPosition": "back", "orientation": 1, "mirrored": false,
                "flashMode": "off", "stillImageTimeSeconds": 0.5,
                "stillImageTimeAccuracy": "measured", "preRollSeconds": 0.5,
                "postRollSeconds": 0.5
            ],
            "photo": [
                "filename": "photo.jpg", "mimeType": "image/jpeg", "width": 640,
                "height": 480, "byteLength": 1, "sha256": String(repeating: "0", count: 64)
            ],
            "motion": [
                "filename": "motion.mov", "mimeType": "video/quicktime", "durationSeconds": 1.0,
                "width": 640, "height": 480, "frameRate": 30, "hasAudio": false,
                "byteLength": 1, "sha256": String(repeating: "0", count: 64)
            ],
            "device": [
                "modelIdentifier": "iPhone5,3", "systemVersion": "7.1.2", "appVersion": "1"
            ]
        ]))
        let assembler = LivePhotoAssembler(
            rootURL: temporary.appendingPathComponent("assembly", isDirectory: true)
        )
        let cached = CachedAsset(
            manifest: manifest,
            directoryURL: temporary,
            photoURL: photoURL,
            motionURL: motionURL
        )
        let firstAssembly = try await assembler.assemble(cached)
        try writeTestJPEG(
            to: firstAssembly.photoURL,
            size: CGSize(width: 640, height: 480),
            properties: [
                kCGImagePropertyExifDictionary: [
                    "LensModel": "iPhone 5c back camera 4.12mm f/2.4"
                ]
            ]
        )
        let assembled = try await assembler.assemble(cached)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(assembled.photoURL as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary] as? [String: Any])
        XCTAssertEqual(tiff["Make"] as? String, "Apple")
        XCTAssertEqual(tiff["Model"] as? String, "iPhone 5c")
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [String: Any])
        XCTAssertEqual(exif["LensModel"] as? String, "iPhone 5c back camera 4.12mm f/2.4")
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func writeTestJPEG(
        to url: URL,
        size: CGSize,
        properties: [CFString: Any]? = nil
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.jpeg" as CFString,
            1,
            nil
        ))
        let defaultProperties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                "Make": "RetroLive",
                "Model": "Test Camera"
            ],
            kCGImagePropertyExifDictionary: [
                "Flash": 1,
                "DateTimeOriginal": "2026:08:10 00:00:00"
            ]
        ]
        CGImageDestinationAddImage(
            destination,
            try XCTUnwrap(context.makeImage()),
            (properties ?? defaultProperties) as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func writeTestMovie(to url: URL, size: CGSize) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, Int32(frame * 3), CVPixelBufferGetBytesPerRow(pixelBuffer) * Int(size.height))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            XCTAssertTrue(adaptor.append(
                pixelBuffer,
                withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)
            ))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }

    private func photoOnlyManifest(assetId: String, photo: Data) throws -> Data {
        let source = try fixtureData("photo-only-v1")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: source) as? [String: Any]
        )
        object["assetId"] = assetId
        var image = try XCTUnwrap(object["photo"] as? [String: Any])
        image["byteLength"] = photo.count
        image["sha256"] = SHA256.hash(data: photo)
            .map { String(format: "%02x", $0) }
            .joined()
        object["photo"] = image
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "manifest",
                withExtension: "json",
                subdirectory: "fixtures/\(name)"
            )
        )
        return try Data(contentsOf: url)
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        json: Any
    ) -> (HTTPURLResponse, Data) {
        response(
            request,
            status: status,
            data: try! JSONSerialization.data(withJSONObject: json)
        )
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        data: some DataProtocol,
        headers: [String: String] = [:]
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!,
            Data(data)
        )
    }
}
