# RetroLive

RetroLive is a two-generation legacy camera and modern importer for producing motion-photo assets on iPhones that never supported native Live Photo capture.

The repository now contains the code-complete portions of **Phase 0–5**: the versioned protocol, iOS 6 Legacy and iOS 8 Classic capture targets, transactional still-plus-motion storage, paired read-only HTTP/Bonjour transfer, a modern downloader with resumable checksum-verified caching, Live Photo assembly, and idempotent PhotoKit import. Hardware-dependent capture, LAN, Photos, and Live Photo playback checks remain device acceptance work.

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
python3 tools/validate-manifest/validate.py --expect-invalid protocol/fixtures/invalid-date/manifest.json
python3 tools/validate-manifest/validate.py --expect-invalid protocol/fixtures/invalid-types/manifest.json
python3 tools/validate-manifest/validate.py --expect-unsupported protocol/fixtures/unsupported-schema/manifest.json

clang -fobjc-arc -framework Foundation \
  -I legacy-camera/RetroLiveCamera/Assets \
  tools/test-legacy-parser/main.m \
  legacy-camera/RetroLiveCamera/Assets/RLVAssetManifest.m \
  legacy-camera/RetroLiveCamera/Assets/RLVManifestParser.m \
  -o /tmp/retrolive-legacy-parser
/tmp/retrolive-legacy-parser protocol/fixtures/valid-v1/manifest.json
/tmp/retrolive-legacy-parser protocol/fixtures/photo-only-v1/manifest.json
/tmp/retrolive-legacy-parser --expect-invalid protocol/fixtures/invalid-date/manifest.json
/tmp/retrolive-legacy-parser --expect-invalid protocol/fixtures/invalid-types/manifest.json

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

clang -fobjc-arc -framework Foundation -framework AVFoundation \
  -framework ImageIO -framework CoreGraphics \
  -I legacy-camera/RetroLiveCamera/Shared/Transfer \
  -I legacy-camera/RetroLiveCamera/Shared/Asset \
  -I legacy-camera/RetroLiveCamera/Shared/Capture \
  -I legacy-camera/RetroLiveCamera/Shared/Device \
  tools/test-transfer-router/main.m \
  legacy-camera/RetroLiveCamera/Shared/Transfer/RLVHTTPResponse.m \
  legacy-camera/RetroLiveCamera/Shared/Transfer/RLVTransferRouter.m \
  legacy-camera/RetroLiveCamera/Shared/Asset/RLVAsset.m \
  legacy-camera/RetroLiveCamera/Shared/Asset/RLVAssetStore.m \
  legacy-camera/RetroLiveCamera/Shared/Asset/RLVManifest.m \
  -o /tmp/retrolive-transfer-router
/tmp/retrolive-transfer-router

xcodebuild test \
  -project modern-importer/RetroLiveImporter.xcodeproj \
  -scheme RetroLiveImporter \
  -destination 'platform=iOS Simulator,id=<installed-simulator-udid>'
```

The legacy project deliberately keeps its deployment target at iOS 6.0. Building it for an actual iOS 6 device requires the archived Xcode/iOS SDK environment described in [docs/ios6-build-environment.md](docs/ios6-build-environment.md).

## Validation status

- Both camera schemes compile with the current SDK when deployment and architecture are overridden for host source validation.
- Protocol fixtures cover both motion and `motion: null`; the asset-store runner covers a motion commit.
- iOS 6 archived-toolchain builds, real-camera capture, 20-shot stability, restart persistence, orientation, and pixel-fidelity checks still require the target devices.
- Real-camera timing, audio, orientation, and 20-shot stability still require the target devices.
- Phase 3 routing, pairing, bearer authorization, pagination, immutable media access, and Range behavior are covered by a host integration test.
- Bonjour discovery, real-device transfer, capture/download concurrency, and archived iOS 6 builds remain device acceptance checks.
- Phase 4 API, discovery, pairing, pagination, resumable download, SHA-256 verification, and immutable cache code compile with the modern app test bundle.
- Phase 5 JPEG/MOV identifier injection, still-image-time metadata, PhotoKit paired import, photo-only fallback, and idempotent history code compile with the modern app test bundle.
- Modern importer unit tests require an available iOS Simulator to execute; current-host build-for-testing is not a substitute for the physical-device acceptance cases.

See [docs/phase0-2-completion-audit.md](docs/phase0-2-completion-audit.md), [docs/phase2-plan.md](docs/phase2-plan.md), [docs/phase3-delivery.md](docs/phase3-delivery.md), [docs/phase4-5-delivery.md](docs/phase4-5-delivery.md), [docs/camera-ui-measurements.md](docs/camera-ui-measurements.md), and [docs/test-plan.md](docs/test-plan.md).
