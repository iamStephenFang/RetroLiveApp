import CryptoKit
import Foundation

struct CachedAsset: Sendable {
    let manifest: ManifestV1
    let directoryURL: URL
    let photoURL: URL
    let motionURL: URL?
}

enum DownloadStoreError: Error, LocalizedError, Equatable {
    case assetIdentifierMismatch
    case invalidStatus(Int)
    case invalidContentRange
    case lengthMismatch(resource: String)
    case hashMismatch(resource: String)
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .assetIdentifierMismatch:
            "素材列表与 Manifest 的标识不一致。"
        case .invalidStatus(let status):
            "下载返回了不支持的 HTTP 状态 \(status)。"
        case .invalidContentRange:
            "相机返回的断点续传范围不正确。"
        case .lengthMismatch(let resource):
            "\(resource) 的文件长度与 Manifest 不一致。"
        case .hashMismatch(let resource):
            "\(resource) 的 SHA-256 与 Manifest 不一致。"
        case .missingResource(let resource):
            "缓存中缺少 \(resource)。"
        }
    }
}

actor DownloadStore {
    typealias ProgressHandler = @Sendable (Double) -> Void

    private let rootURL: URL
    private let session: URLSession
    private let fileManager: FileManager
    private let parser = ManifestParser()

    init(
        rootURL: URL? = nil,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.rootURL = rootURL ?? applicationSupport
            .appendingPathComponent("RetroLive/Downloads", isDirectory: true)
        self.session = session
        self.fileManager = fileManager
    }

    func cachedAsset(assetId: String) throws -> CachedAsset? {
        let directory = assetsURL.appendingPathComponent(assetId, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        do {
            return try validateAsset(at: directory)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func download(
        summary: CameraAssetSummary,
        api: CameraAPIClient,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> CachedAsset {
        if let cached = try cachedAsset(assetId: summary.assetId) {
            progress(1)
            return cached
        }
        try ensureDirectories()
        let manifestData = try await api.manifestData(assetId: summary.assetId)
        let manifest = try parser.parse(manifestData)
        guard manifest.assetId == summary.assetId else {
            throw DownloadStoreError.assetIdentifierMismatch
        }

        let staging = temporaryURL.appendingPathComponent(summary.assetId, isDirectory: true)
        try prepareStaging(staging, manifestData: manifestData)
        progress(0.05)

        let totalBytes = manifest.photo.byteLength + (manifest.motion?.byteLength ?? 0)
        try await downloadResource(
            assetId: manifest.assetId,
            endpoint: "photo",
            destination: staging.appendingPathComponent(manifest.photo.filename),
            expectedLength: manifest.photo.byteLength,
            expectedHash: manifest.photo.sha256,
            api: api
        ) { downloaded in
            progress(0.05 + 0.9 * Double(downloaded) / Double(max(totalBytes, 1)))
        }

        if let motion = manifest.motion {
            let photoLength = manifest.photo.byteLength
            try await downloadResource(
                assetId: manifest.assetId,
                endpoint: "motion",
                destination: staging.appendingPathComponent(motion.filename),
                expectedLength: motion.byteLength,
                expectedHash: motion.sha256,
                api: api
            ) { downloaded in
                progress(0.05 + 0.9 * Double(photoLength + downloaded) / Double(max(totalBytes, 1)))
            }
        }

        _ = try validateAsset(at: staging)
        let finalURL = assetsURL.appendingPathComponent(manifest.assetId, isDirectory: true)
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: staging, to: finalURL)
        let committed = try validateAsset(at: finalURL)
        progress(1)
        return committed
    }

    func removeCachedAsset(assetId: String) throws {
        guard UUID(uuidString: assetId) != nil else { return }
        let assetURL = assetsURL.appendingPathComponent(assetId, isDirectory: true)
        let partialURL = temporaryURL.appendingPathComponent(assetId, isDirectory: true)
        if fileManager.fileExists(atPath: assetURL.path) {
            try fileManager.removeItem(at: assetURL)
        }
        if fileManager.fileExists(atPath: partialURL.path) {
            try fileManager.removeItem(at: partialURL)
        }
    }

    private func downloadResource(
        assetId: String,
        endpoint: String,
        destination: URL,
        expectedLength: Int64,
        expectedHash: String,
        api: CameraAPIClient,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let partialURL = destination.appendingPathExtension("partial")
        if fileManager.fileExists(atPath: destination.path) {
            guard try fileSize(destination) == expectedLength,
                  try sha256(destination) == expectedHash else {
                try fileManager.removeItem(at: destination)
                return try await downloadResource(
                    assetId: assetId,
                    endpoint: endpoint,
                    destination: destination,
                    expectedLength: expectedLength,
                    expectedHash: expectedHash,
                    api: api,
                    progress: progress
                )
            }
            progress(expectedLength)
            return
        }

        var offset = (try? fileSize(partialURL)) ?? 0
        if offset > expectedLength {
            try fileManager.removeItem(at: partialURL)
            offset = 0
        }
        let request = try await api.authorizedRequest(
            assetId: assetId,
            resource: endpoint,
            rangeStart: offset
        )
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CameraAPIError.invalidResponse
        }
        if http.statusCode == 401 { throw CameraAPIError.unauthorized }
        if http.statusCode == 404 { throw CameraAPIError.notFound }
        guard http.statusCode == 200 || http.statusCode == 206 else {
            throw DownloadStoreError.invalidStatus(http.statusCode)
        }
        if offset > 0, http.statusCode == 206 {
            guard http.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes \(offset)-") == true else {
                throw DownloadStoreError.invalidContentRange
            }
        } else if http.statusCode == 200 {
            offset = 0
            try? fileManager.removeItem(at: partialURL)
        }

        if !fileManager.fileExists(atPath: partialURL.path) {
            fileManager.createFile(atPath: partialURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partialURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var received = offset
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count == 64 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(received)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
            progress(received)
        }
        try handle.synchronize()
        guard received == expectedLength else {
            throw DownloadStoreError.lengthMismatch(resource: endpoint)
        }
        guard try sha256(partialURL) == expectedHash else {
            try? fileManager.removeItem(at: partialURL)
            throw DownloadStoreError.hashMismatch(resource: endpoint)
        }
        try fileManager.moveItem(at: partialURL, to: destination)
    }

    private func validateAsset(at directory: URL) throws -> CachedAsset {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw DownloadStoreError.missingResource("manifest.json")
        }
        let manifest = try parser.parse(Data(contentsOf: manifestURL))
        guard directory.lastPathComponent == manifest.assetId else {
            throw DownloadStoreError.assetIdentifierMismatch
        }
        let photoURL = directory.appendingPathComponent(manifest.photo.filename)
        try validate(
            photoURL,
            name: manifest.photo.filename,
            length: manifest.photo.byteLength,
            hash: manifest.photo.sha256
        )
        var motionURL: URL?
        if let motion = manifest.motion {
            let url = directory.appendingPathComponent(motion.filename)
            try validate(url, name: motion.filename, length: motion.byteLength, hash: motion.sha256)
            motionURL = url
        }
        return CachedAsset(
            manifest: manifest,
            directoryURL: directory,
            photoURL: photoURL,
            motionURL: motionURL
        )
    }

    private func validate(_ url: URL, name: String, length: Int64, hash: String) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw DownloadStoreError.missingResource(name)
        }
        guard try fileSize(url) == length else {
            throw DownloadStoreError.lengthMismatch(resource: name)
        }
        guard try sha256(url) == hash else {
            throw DownloadStoreError.hashMismatch(resource: name)
        }
    }

    private func prepareStaging(_ staging: URL, manifestData: Data) throws {
        if fileManager.fileExists(atPath: staging.path) {
            let existing = try? Data(contentsOf: staging.appendingPathComponent("manifest.json"))
            if existing != manifestData {
                try fileManager.removeItem(at: staging)
            }
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try manifestData.write(
            to: staging.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
    }

    private var assetsURL: URL {
        rootURL.appendingPathComponent("Assets", isDirectory: true)
    }

    private var temporaryURL: URL {
        rootURL.appendingPathComponent("Temporary", isDirectory: true)
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
