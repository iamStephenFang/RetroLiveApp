import Foundation

enum RetroLiveISO8601 {
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
}

enum ManifestParserError: Error, Equatable, LocalizedError {
    case invalidJSON(String)
    case unsupportedSchemaVersion(found: Int, supported: [Int])
    case invalidField(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            "Invalid Manifest JSON: \(detail)"
        case .unsupportedSchemaVersion(let found, let supported):
            "Unsupported schemaVersion \(found); supported versions: \(supported.map(String.init).joined(separator: ", "))."
        case .invalidField(let field):
            "Manifest field is missing or invalid: \(field)."
        }
    }
}

struct ManifestParser: Sendable {
    static let supportedSchemaVersions = [1]

    func parse(_ data: Data) throws -> ManifestV1 {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ManifestParserError.invalidJSON(error.localizedDescription)
        }
        guard let root = object as? [String: Any] else {
            throw ManifestParserError.invalidJSON("Root value must be an object.")
        }
        guard let schemaVersion = root["schemaVersion"] as? Int else {
            throw ManifestParserError.invalidField("$.schemaVersion")
        }
        guard Self.supportedSchemaVersions.contains(schemaVersion) else {
            throw ManifestParserError.unsupportedSchemaVersion(
                found: schemaVersion,
                supported: Self.supportedSchemaVersions
            )
        }
        guard root.keys.contains("motion") else {
            throw ManifestParserError.invalidField("$.motion")
        }

        let manifest: ManifestV1
        do {
            manifest = try JSONDecoder().decode(ManifestV1.self, from: data)
        } catch let error as DecodingError {
            throw ManifestParserError.invalidField(Self.path(from: error))
        } catch {
            throw ManifestParserError.invalidJSON(error.localizedDescription)
        }
        try validate(manifest)
        return manifest
    }

    private func validate(_ manifest: ManifestV1) throws {
        guard UUID(uuidString: manifest.assetId) != nil else {
            throw ManifestParserError.invalidField("$.assetId")
        }
        guard let createdAt = RetroLiveISO8601.date(from: manifest.createdAt) else {
            throw ManifestParserError.invalidField("$.createdAt")
        }
        guard manifest.createdAtUnixMilliseconds >= 0 else {
            throw ManifestParserError.invalidField("$.createdAtUnixMilliseconds")
        }
        guard abs(createdAt.timeIntervalSince1970 * 1_000 - Double(manifest.createdAtUnixMilliseconds)) <= 1 else {
            throw ManifestParserError.invalidField("$.createdAtUnixMilliseconds")
        }
        guard (1...8).contains(manifest.capture.orientation) else {
            throw ManifestParserError.invalidField("$.capture.orientation")
        }
        guard manifest.capture.stillImageTimeSeconds >= 0,
              manifest.capture.preRollSeconds >= 0,
              manifest.capture.postRollSeconds >= 0 else {
            throw ManifestParserError.invalidField("$.capture")
        }
        try validateImage(manifest.photo, path: "$.photo")
        if let thumbnail = manifest.thumbnail {
            try validateImage(thumbnail, path: "$.thumbnail")
        }
        if let motion = manifest.motion {
            try validateMotion(motion)
            guard manifest.capture.stillImageTimeSeconds < motion.durationSeconds else {
                throw ManifestParserError.invalidField("$.capture.stillImageTimeSeconds")
            }
        } else if manifest.capture.stillImageTimeSeconds != 0 ||
                    manifest.capture.preRollSeconds != 0 ||
                    manifest.capture.postRollSeconds != 0 {
            throw ManifestParserError.invalidField("$.capture")
        }
        guard !manifest.device.modelIdentifier.isEmpty,
              !manifest.device.systemVersion.isEmpty,
              !manifest.device.appVersion.isEmpty else {
            throw ManifestParserError.invalidField("$.device")
        }
    }

    private func validateImage(_ resource: ManifestV1.ImageResource, path: String) throws {
        try validateResource(
            filename: resource.filename,
            mimeType: resource.mimeType,
            byteLength: resource.byteLength,
            sha256: resource.sha256,
            path: path
        )
        guard resource.width > 0, resource.height > 0 else {
            throw ManifestParserError.invalidField("\(path).dimensions")
        }
    }

    private func validateMotion(_ resource: ManifestV1.MotionResource) throws {
        try validateResource(
            filename: resource.filename,
            mimeType: resource.mimeType,
            byteLength: resource.byteLength,
            sha256: resource.sha256,
            path: "$.motion"
        )
        guard resource.durationSeconds > 0,
              resource.width > 0,
              resource.height > 0,
              resource.frameRate > 0 else {
            throw ManifestParserError.invalidField("$.motion")
        }
    }

    private func validateResource(
        filename: String,
        mimeType: String,
        byteLength: Int64,
        sha256: String,
        path: String
    ) throws {
        guard !filename.isEmpty,
              filename != ".",
              filename != "..",
              !filename.contains("/"),
              !filename.contains("\\") else {
            throw ManifestParserError.invalidField("\(path).filename")
        }
        guard !mimeType.isEmpty else {
            throw ManifestParserError.invalidField("\(path).mimeType")
        }
        guard byteLength > 0 else {
            throw ManifestParserError.invalidField("\(path).byteLength")
        }
        let lowercaseHex = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.count == 64,
              sha256.unicodeScalars.allSatisfy(lowercaseHex.contains) else {
            throw ManifestParserError.invalidField("\(path).sha256")
        }
    }

    private static func path(from error: DecodingError) -> String {
        let codingPath: [CodingKey]
        switch error {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            codingPath = context.codingPath
        @unknown default:
            return "$"
        }
        let suffix = codingPath.map(\.stringValue).joined(separator: ".")
        return suffix.isEmpty ? "$" : "$.\(suffix)"
    }
}
