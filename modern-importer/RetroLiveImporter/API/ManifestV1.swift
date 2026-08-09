import Foundation

struct ManifestV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let assetId: String
    let createdAt: String
    let createdAtUnixMilliseconds: Int64
    let capture: Capture
    let photo: ImageResource
    let motion: MotionResource?
    let thumbnail: ImageResource?
    let device: Device

    struct Capture: Codable, Equatable, Sendable {
        let cameraPosition: CameraPosition
        let orientation: Int
        let mirrored: Bool
        let flashMode: FlashMode
        let aspectRatio: AspectRatio?
        let stillImageTimeSeconds: Double
        let stillImageTimeAccuracy: StillImageTimeAccuracy
        let preRollSeconds: Double
        let postRollSeconds: Double
    }

    struct MediaResource: Codable, Equatable, Sendable {
        let filename: String
        let mimeType: String
        let byteLength: Int64
        let sha256: String
    }

    struct ImageResource: Codable, Equatable, Sendable {
        let filename: String
        let mimeType: String
        let width: Int
        let height: Int
        let byteLength: Int64
        let sha256: String
    }

    struct MotionResource: Codable, Equatable, Sendable {
        let filename: String
        let mimeType: String
        let durationSeconds: Double
        let width: Int
        let height: Int
        let frameRate: Double
        let hasAudio: Bool
        let byteLength: Int64
        let sha256: String
    }

    struct Device: Codable, Equatable, Sendable {
        let modelIdentifier: String
        let systemVersion: String
        let appVersion: String
    }

    enum CameraPosition: String, Codable, Sendable { case front, back }
    enum FlashMode: String, Codable, Sendable { case off, on, auto }
    enum AspectRatio: String, Codable, Sendable {
        case fourThree = "4:3"
        case square = "1:1"
        case sixteenNine = "16:9"

        var landscapeValue: CGFloat {
            switch self {
            case .fourThree: 4.0 / 3.0
            case .square: 1.0
            case .sixteenNine: 16.0 / 9.0
            }
        }
    }
    enum StillImageTimeAccuracy: String, Codable, Sendable { case measured, estimated }
}
