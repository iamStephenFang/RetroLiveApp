import Foundation

struct DiscoveredCamera: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let host: String
    let port: Int

    var hostDescription: String {
        host.hasSuffix(".") ? String(host.dropLast()) : host
    }

    var endpointDescription: String {
        hostDescription + ":" + String(port)
    }

    var baseURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = hostDescription
        components.port = port
        components.path = "/api/v1"
        return components.url!
    }
}

struct PairingSession: Codable, Equatable, Sendable {
    let token: String
    let expiresAt: Date

    var isValid: Bool { expiresAt > Date() }
}

struct CameraDeviceInfo: Codable, Equatable, Sendable {
    struct Capabilities: Codable, Equatable, Sendable {
        let rangeDownload: Bool
        let batchExport: Bool
        let delete: Bool
    }

    let protocolVersion: Int
    let deviceId: String
    let deviceName: String
    let modelIdentifier: String
    let systemVersion: String
    let appVersion: String
    let assetCount: Int
    let capabilities: Capabilities
}

struct CameraAssetSummary: Codable, Identifiable, Equatable, Sendable {
    let assetId: String
    let createdAt: String
    let thumbnailURL: String?
    let manifestURL: String
    let hasMotion: Bool?

    var id: String { assetId }

    init(
        assetId: String,
        createdAt: String,
        thumbnailURL: String?,
        manifestURL: String,
        hasMotion: Bool? = nil
    ) {
        self.assetId = assetId
        self.createdAt = createdAt
        self.thumbnailURL = thumbnailURL
        self.manifestURL = manifestURL
        self.hasMotion = hasMotion
    }
}

struct CameraAssetPage: Codable, Equatable, Sendable {
    let items: [CameraAssetSummary]
    let nextCursor: String?
}

enum CameraAPIError: Error, LocalizedError, Equatable {
    case invalidResponse
    case invalidRequest
    case unauthorized
    case lockedOut
    case notFound
    case invalidPayload(String)
    case paginationLoop
    case duplicateAsset(String)
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            L10n.text("api.invalid_response")
        case .invalidRequest:
            L10n.text("api.invalid_request")
        case .unauthorized:
            L10n.text("api.unauthorized")
        case .lockedOut:
            L10n.text("api.locked_out")
        case .notFound:
            L10n.text("api.not_found")
        case .invalidPayload(let field):
            L10n.format("api.invalid_payload", field)
        case .paginationLoop:
            L10n.text("api.pagination_loop")
        case .duplicateAsset(let assetId):
            L10n.format("api.duplicate_asset", assetId)
        case .server(let status, _):
            L10n.format("api.server_error", status)
        }
    }
}

actor CameraAPIClient {
    private struct PairingRequest: Encodable {
        let pairingCode: String
        let clientName: String
        let rememberDevice: Bool
    }

    private struct SessionResponse: Decodable {
        let token: String
        let expiresInSeconds: Int
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    let baseURL: URL
    private let session: URLSession
    private var token: String?

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    @discardableResult
    func pair(code: String, clientName: String, rememberDevice: Bool = false) async throws -> PairingSession {
        guard code.count == 6, code.allSatisfy(\.isNumber),
              !clientName.isEmpty, clientName.count <= 100 else {
            throw CameraAPIError.invalidRequest
        }
        var request = URLRequest(url: endpoint("session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PairingRequest(
                pairingCode: code,
                clientName: clientName,
                rememberDevice: rememberDevice
            )
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let sessionResponse = try JSONDecoder().decode(SessionResponse.self, from: data)
        guard sessionResponse.token.count >= 32, sessionResponse.expiresInSeconds > 0 else {
            throw CameraAPIError.invalidResponse
        }
        token = sessionResponse.token
        return PairingSession(
            token: sessionResponse.token,
            expiresAt: Date().addingTimeInterval(TimeInterval(sessionResponse.expiresInSeconds))
        )
    }

    func restore(_ session: PairingSession) throws {
        guard session.isValid, session.token.count >= 32 else {
            throw CameraAPIError.unauthorized
        }
        token = session.token
    }

    func disconnect() {
        token = nil
    }

    func deviceInfo() async throws -> CameraDeviceInfo {
        let info = try await decode(CameraDeviceInfo.self, request: authorizedRequest(path: "device"))
        guard info.protocolVersion == 1,
              UUID(uuidString: info.deviceId) != nil,
              !info.deviceName.isEmpty,
              !info.modelIdentifier.isEmpty,
              !info.systemVersion.isEmpty,
              !info.appVersion.isEmpty,
              info.assetCount >= 0 else {
            throw CameraAPIError.invalidPayload("device")
        }
        return info
    }

    func allAssets(pageSize: Int = 100) async throws -> [CameraAssetSummary] {
        var result: [CameraAssetSummary] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        var seenAssetIds: Set<String> = []
        repeat {
            var components = URLComponents(url: endpoint("assets"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "limit", value: String(min(max(pageSize, 1), 100)))
            ]
            if let cursor {
                components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor))
            }
            let page = try await decode(
                CameraAssetPage.self,
                request: authorizedRequest(url: components.url!)
            )
            for item in page.items {
                guard UUID(uuidString: item.assetId) != nil,
                      RetroLiveISO8601.date(from: item.createdAt) != nil,
                      item.manifestURL == "/api/v1/assets/\(item.assetId)/manifest",
                      item.thumbnailURL == nil ||
                        item.thumbnailURL == "/api/v1/assets/\(item.assetId)/thumbnail" else {
                    throw CameraAPIError.invalidPayload("assets.items")
                }
                guard seenAssetIds.insert(item.assetId).inserted else {
                    throw CameraAPIError.duplicateAsset(item.assetId)
                }
                result.append(item)
            }
            if let nextCursor = page.nextCursor {
                guard !page.items.isEmpty,
                      seenCursors.insert(nextCursor).inserted,
                      nextCursor != cursor else {
                    throw CameraAPIError.paginationLoop
                }
            }
            cursor = page.nextCursor
        } while cursor != nil
        return result
    }

    func manifestData(assetId: String) async throws -> Data {
        guard UUID(uuidString: assetId) != nil else { throw CameraAPIError.notFound }
        let request = try authorizedRequest(path: "assets/\(assetId)/manifest")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    func previewData(for summary: CameraAssetSummary) async throws -> Data {
        let resource = summary.thumbnailURL == nil ? "photo" : "thumbnail"
        let request = try authorizedRequest(assetId: summary.assetId, resource: resource)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        guard !data.isEmpty, data.count <= 25 * 1_024 * 1_024 else {
            throw CameraAPIError.invalidPayload("thumbnail")
        }
        return data
    }

    func authorizedRequest(assetId: String, resource: String, rangeStart: Int64? = nil) throws -> URLRequest {
        guard UUID(uuidString: assetId) != nil,
              ["photo", "motion", "thumbnail"].contains(resource) else {
            throw CameraAPIError.notFound
        }
        var request = try authorizedRequest(path: "assets/\(assetId)/\(resource)")
        if let rangeStart, rangeStart > 0 {
            request.setValue("bytes=\(rangeStart)-", forHTTPHeaderField: "Range")
        }
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(type, from: data)
    }

    private func authorizedRequest(path: String) throws -> URLRequest {
        try authorizedRequest(url: endpoint(path))
    }

    private func authorizedRequest(url: URL) throws -> URLRequest {
        guard let token, !token.isEmpty else { throw CameraAPIError.unauthorized }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func endpoint(_ path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { url, component in
            url.appendingPathComponent(String(component), isDirectory: false)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CameraAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            switch http.statusCode {
            case 401:
                throw CameraAPIError.unauthorized
            case 404:
                throw CameraAPIError.notFound
            case 429:
                throw CameraAPIError.lockedOut
            default:
                throw CameraAPIError.server(status: http.statusCode, message: message)
            }
        }
    }
}
