import CryptoKit
import Foundation
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

final class Phase45Tests: XCTestCase {
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

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
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
