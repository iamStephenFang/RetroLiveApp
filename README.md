# RetroLive

RetroLive is a two-app system for capturing motion-photo assets on an iOS 6 device and importing them as Live Photos on a modern iPhone.

This repository is currently at **Phase 0: project and protocol foundations**. It contains the versioned asset protocol, fixtures, and compilable skeletons for both applications. Camera capture, the local HTTP server, transfer, and Live Photo assembly are intentionally out of scope for this phase.

## Repository layout

```text
docs/              Architecture, protocol, build, format, and test documentation
protocol/          JSON Schema, OpenAPI description, examples, and fixtures
legacy-camera/     Objective-C UIKit application targeting iOS 6.0
modern-importer/   SwiftUI application targeting iOS 17.0
tools/             Dependency-free protocol validation utilities
```

## Phase 0 validation

```sh
python3 tools/validate-manifest/validate.py protocol/examples/manifest-v1.json
python3 tools/validate-manifest/validate.py protocol/fixtures/valid-v1/manifest.json
python3 tools/validate-manifest/validate.py --expect-invalid protocol/fixtures/invalid-hash/manifest.json
python3 tools/validate-manifest/validate.py --expect-unsupported protocol/fixtures/unsupported-schema/manifest.json

clang -fobjc-arc -framework Foundation \
  -I legacy-camera/RetroLiveCamera/Assets \
  tools/test-legacy-parser/main.m \
  legacy-camera/RetroLiveCamera/Assets/RLVAssetManifest.m \
  legacy-camera/RetroLiveCamera/Assets/RLVManifestParser.m \
  -o /tmp/retrolive-legacy-parser
/tmp/retrolive-legacy-parser protocol/fixtures/valid-v1/manifest.json

xcodebuild test \
  -project modern-importer/RetroLiveImporter.xcodeproj \
  -scheme RetroLiveImporter \
  -destination 'platform=iOS Simulator,id=<installed-simulator-udid>'
```

The legacy project deliberately keeps its deployment target at iOS 6.0. Building it for an actual iOS 6 device requires the archived Xcode/iOS SDK environment described in [docs/ios6-build-environment.md](docs/ios6-build-environment.md).

## Current limitations

- Media files in fixtures are protocol placeholders; Phase 0 does not perform media decoding or checksum comparison against files.
- The legacy skeleton has no capture session or asset persistence yet.
- The modern skeleton has no discovery, transfer, PhotoKit, or Live Photo assembly code yet.
- Modern Xcode versions may reject or warn about the iOS 6 deployment target. That does not change the committed legacy target.
