import Foundation
import XCTest
@testable import RetroLiveImporter

final class ManifestParserTests: XCTestCase {
    private let parser = ManifestParser()

    func testValidFixture() throws {
        let manifest = try parser.parse(try fixtureData("valid-v1"))
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.assetId, "75A14CE4-3E3F-4BB1-BC27-EFE37D8C2A84")
        XCTAssertTrue(try XCTUnwrap(manifest.motion).hasAudio)
        XCTAssertEqual(manifest.capture.stillImageTimeSeconds, 1.486)
    }

    func testPhotoOnlyFixture() throws {
        let manifest = try parser.parse(try fixtureData("photo-only-v1"))
        XCTAssertNil(manifest.motion)
        XCTAssertNil(manifest.thumbnail)
        XCTAssertEqual(manifest.capture.stillImageTimeSeconds, 0)
    }

    func testMissingMotionIsRejected() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try fixtureData("photo-only-v1")) as? [String: Any]
        )
        object.removeValue(forKey: "motion")
        XCTAssertThrowsError(try parser.parse(try JSONSerialization.data(withJSONObject: object))) { error in
            XCTAssertEqual(error as? ManifestParserError, .invalidField("$.motion"))
        }
    }

    func testInvalidHashFixture() throws {
        XCTAssertThrowsError(try parser.parse(try fixtureData("invalid-hash"))) { error in
            XCTAssertEqual(error as? ManifestParserError, .invalidField("$.photo.sha256"))
        }
    }

    func testInvalidDateFixture() throws {
        XCTAssertThrowsError(try parser.parse(try fixtureData("invalid-date"))) { error in
            XCTAssertEqual(error as? ManifestParserError, .invalidField("$.createdAt"))
        }
    }

    func testBooleanSchemaVersionFixture() throws {
        XCTAssertThrowsError(try parser.parse(try fixtureData("invalid-types"))) { error in
            XCTAssertEqual(error as? ManifestParserError, .invalidField("$.schemaVersion"))
        }
    }

    func testUnsupportedSchemaFixture() throws {
        XCTAssertThrowsError(try parser.parse(try fixtureData("unsupported-schema"))) { error in
            XCTAssertEqual(
                error as? ManifestParserError,
                .unsupportedSchemaVersion(found: 99, supported: [1])
            )
        }
    }

    func testZeroLengthResourceAndStillTimeAtMovieEndAreRejected() throws {
        var zeroLength = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try fixtureData("photo-only-v1")) as? [String: Any]
        )
        var photo = try XCTUnwrap(zeroLength["photo"] as? [String: Any])
        photo["byteLength"] = 0
        zeroLength["photo"] = photo
        XCTAssertThrowsError(
            try parser.parse(try JSONSerialization.data(withJSONObject: zeroLength))
        ) { error in
            XCTAssertEqual(error as? ManifestParserError, .invalidField("$.photo.byteLength"))
        }

        var endFrame = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try fixtureData("valid-v1")) as? [String: Any]
        )
        let motion = try XCTUnwrap(endFrame["motion"] as? [String: Any])
        var capture = try XCTUnwrap(endFrame["capture"] as? [String: Any])
        capture["stillImageTimeSeconds"] = motion["durationSeconds"]
        endFrame["capture"] = capture
        XCTAssertThrowsError(
            try parser.parse(try JSONSerialization.data(withJSONObject: endFrame))
        ) { error in
            XCTAssertEqual(
                error as? ManifestParserError,
                .invalidField("$.capture.stillImageTimeSeconds")
            )
        }
    }

    func testCreatedAtRepresentationsMustMatch() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try fixtureData("valid-v1")) as? [String: Any]
        )
        object["createdAtUnixMilliseconds"] = Int64(0)
        XCTAssertThrowsError(
            try parser.parse(try JSONSerialization.data(withJSONObject: object))
        ) { error in
            XCTAssertEqual(
                error as? ManifestParserError,
                .invalidField("$.createdAtUnixMilliseconds")
            )
        }
    }

    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        guard let fixtureURL = bundle.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "fixtures/\(name)"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: fixtureURL)
    }
}
