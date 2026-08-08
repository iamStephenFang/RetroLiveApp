import Foundation

struct DiscoveredCamera: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let host: String
    let port: Int

    var baseURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host.hasSuffix(".") ? String(host.dropLast()) : host
        components.port = port
        components.path = "/api/v1"
        return components.url!
    }
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

    var id: String { assetId }
}

struct CameraAssetPage: Codable, Equatable, Sendable {
    let items: [CameraAssetSummary]
    let nextCursor: String?
}

enum CameraAPIError: Error, LocalizedError, Equatable {
    case invalidResponse
    case unauthorized
    case lockedOut
    case notFound
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "相机返回了无法识别的响应。"
        case .unauthorized:
            "配对已失效，请重新输入相机上的配对码。"
        case .lockedOut:
            "配对尝试过多，请稍后再试。"
        case .notFound:
            "相机上已找不到这个素材。"
        case .server(let status, let message):
            "相机请求失败（\(status)）：\(message)"
        }
    }
}

actor CameraAPIClient {
    private struct PairingRequest: Encodable {
        let pairingCode: String
        let clientName: String
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

    func pair(code: String, clientName: String) async throws {
        var request = URLRequest(url: endpoint("session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PairingRequest(pairingCode: code, clientName: clientName))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let sessionResponse = try JSONDecoder().decode(SessionResponse.self, from: data)
        guard !sessionResponse.token.isEmpty, sessionResponse.expiresInSeconds > 0 else {
            throw CameraAPIError.invalidResponse
        }
        token = sessionResponse.token
    }

    func disconnect() {
        token = nil
    }

    func deviceInfo() async throws -> CameraDeviceInfo {
        try await decode(CameraDeviceInfo.self, request: authorizedRequest(path: "device"))
    }

    func allAssets(pageSize: Int = 100) async throws -> [CameraAssetSummary] {
        var result: [CameraAssetSummary] = []
        var cursor: String?
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
            result.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return result
    }

    func manifestData(assetId: String) async throws -> Data {
        let request = authorizedRequest(path: "assets/\(assetId)/manifest")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    func authorizedRequest(assetId: String, resource: String, rangeStart: Int64? = nil) throws -> URLRequest {
        guard UUID(uuidString: assetId) != nil,
              ["photo", "motion", "thumbnail"].contains(resource) else {
            throw CameraAPIError.notFound
        }
        var request = authorizedRequest(path: "assets/\(assetId)/\(resource)")
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

    private func authorizedRequest(path: String) -> URLRequest {
        authorizedRequest(url: endpoint(path))
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
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
