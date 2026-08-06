import Foundation
import XCTest
@testable import RetroLiveImporter

final class ManifestParserTests: XCTestCase {
    private let parser = ManifestParser()

    func testValidFixture() throws {
        let manifest = try parser.parse(try fixtureData("valid-v1"))
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.assetId, "75A14CE4-3E3F-4BB1-BC27-EFE37D8C2A84")
        XCTAssertTrue(manifest.motion.hasAudio)
        XCTAssertEqual(manifest.capture.stillImageTimeSeconds, 1.486)
    }

    func testInvalidHashFixture() throws {
        XCTAssertThrowsError(try parser.parse(try fixtureData("invalid-hash"))) { error in
            XCTAssertEqual(error as? ManifestParserError, .invalidField("$.photo.sha256"))
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
