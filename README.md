# RetroLive

RetroLive is a two-generation legacy camera and future modern importer for producing motion-photo assets on iPhones that never supported native Live Photo capture.

The repository now contains the **Phase 2 Legacy Motion Capture Foundation**: iOS 6 Legacy and iOS 8 Classic targets, shared still-plus-motion capture, transactional local asset storage, Manifest V1 writing, and a local RetroLive library. Networking, the modern import workflow, and Live Photo assembly remain out of scope.

## Repository layout

```text
docs/              Architecture, protocol, build, format, and test documentation
protocol/          JSON Schema, OpenAPI description, examples, and fixtures
legacy-camera/     Shared Objective-C core plus iOS 6 Legacy and iOS 8 Classic camera targets
modern-importer/   SwiftUI application targeting iOS 17.0
tools/             Dependency-free protocol validation utilities
```

## Protocol validation

```sh
python3 tools/validate-manifest/validate.py protocol/examples/manifest-v1.json
python3 tools/validate-manifest/validate.py protocol/fixtures/valid-v1/manifest.json
python3 tools/validate-manifest/validate.py protocol/fixtures/photo-only-v1/manifest.json
python3 tools/validate-manifest/validate.py --expect-invalid protocol/fixtures/invalid-hash/manifest.json
python3 tools/validate-manifest/validate.py --expect-unsupported protocol/fixtures/unsupported-schema/manifest.json

clang -fobjc-arc -framework Foundation \
  -I legacy-camera/RetroLiveCamera/Assets \
  tools/test-legacy-parser/main.m \
  legacy-camera/RetroLiveCamera/Assets/RLVAssetManifest.m \
  legacy-camera/RetroLiveCamera/Assets/RLVManifestParser.m \
  -o /tmp/retrolive-legacy-parser
/tmp/retrolive-legacy-parser protocol/fixtures/valid-v1/manifest.json

clang -fobjc-arc -framework Foundation -framework AVFoundation \
  -framework ImageIO -framework CoreGraphics \
  -I legacy-camera/RetroLiveCamera/Shared/Asset \
  -I legacy-camera/RetroLiveCamera/Shared/Capture \
  -I legacy-camera/RetroLiveCamera/Shared/Device \
  tools/test-asset-store/main.m \
  legacy-camera/RetroLiveCamera/Shared/Asset/RLVAsset.m \
  legacy-camera/RetroLiveCamera/Shared/Asset/RLVAssetStore.m \
  legacy-camera/RetroLiveCamera/Shared/Asset/RLVManifest.m \
  legacy-camera/RetroLiveCamera/Shared/Capture/RLVCaptureEvent.m \
  -o /tmp/retrolive-asset-store
/tmp/retrolive-asset-store

xcodebuild test \
  -project modern-importer/RetroLiveImporter.xcodeproj \
  -scheme RetroLiveImporter \
  -destination 'platform=iOS Simulator,id=<installed-simulator-udid>'
```

The legacy project deliberately keeps its deployment target at iOS 6.0. Building it for an actual iOS 6 device requires the archived Xcode/iOS SDK environment described in [docs/ios6-build-environment.md](docs/ios6-build-environment.md).

## Phase 2 validation status

- Both camera schemes compile with the current SDK when deployment and architecture are overridden for host source validation.
- Protocol fixtures cover both motion and `motion: null`; the asset-store runner covers a motion commit.
- iOS 6 archived-toolchain builds, real-camera capture, 20-shot stability, restart persistence, orientation, and pixel-fidelity checks still require the target devices.
- Real-camera timing, audio, orientation, and 20-shot stability still require the target devices.
- No network layer, PhotoKit write, or Live Photo assembly is implemented.

See [docs/phase2-plan.md](docs/phase2-plan.md), [docs/camera-ui-measurements.md](docs/camera-ui-measurements.md), and [docs/test-plan.md](docs/test-plan.md).
