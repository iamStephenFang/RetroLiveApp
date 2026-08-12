# RetroLive

RetroLive brings motion-photo capture to older iPhones and imports the result as a Live Photo on a modern iPhone.

The project has two parts:

- a legacy Objective-C camera app that captures an independent JPEG and a short motion clip; and
- a modern SwiftUI importer that discovers the camera over the local network, verifies the downloaded files, assembles a Live Photo, and saves it to Photos.

RetroLive is under active development. The protocol, storage, transfer, and import paths are implemented and covered by host or simulator tests, but archived iOS toolchain builds and the complete two-device workflow still require physical-device acceptance. See [Project status](#project-status) before relying on it for irreplaceable photos.

## Features

- Legacy-style camera interfaces for iOS 6 and the iOS 7/8 era
- Independent full-resolution JPEG capture with a short, shutter-centered motion clip
- Persistent `4:3`, `1:1`, and `16:9` framing without modifying the camera-side originals
- On-device asset library with still and motion playback
- Explicit, six-digit pairing over the local network
- Bonjour discovery and a versioned, read-only HTTP API
- Resumable downloads with byte-length and SHA-256 verification
- Live Photo metadata assembly and PhotoKit import
- Photo-only fallback when motion capture is unavailable
- English, Simplified Chinese, and Traditional Chinese localization
- No package-manager or third-party runtime dependencies

## Apps and compatibility

| Target | Purpose | Project setting | Development toolchain |
| --- | --- | --- | --- |
| `RetroLiveCamera` | iOS 6-style camera and local asset server | iOS 6.0 | An archived Xcode/iOS 6 SDK is required for an authentic device build |
| `RetroLiveClassic` | iOS 7/8-era camera using the same capture and storage core | iOS 7.0 | Use a toolchain that can build and sign for the target device |
| `RetroLiveImporter` | Discovers a camera, downloads assets, and imports them into Photos | iOS 17.0 | Current Xcode with Swift 6 support |

Both camera targets use Objective-C and ARC. The importer is a SwiftUI application. A modern Xcode installation can inspect and host-check much of the camera source, but it cannot prove that the iOS 6 binary builds, installs, or behaves correctly on period hardware.

## How it works

1. The camera captures `photo.jpg` and, when available, a short `motion.mov` around the shutter event.
2. It writes the media and `manifest.json` into a temporary asset directory, validates them, and atomically commits the asset.
3. The importer pairs with the camera, downloads immutable resources, and verifies their declared byte lengths and SHA-256 hashes.
4. For a motion asset, the importer writes a shared content identifier and still-image-time metadata into a separate working copy before submitting the pair to PhotoKit. A photo-only asset is imported as a normal photo.

The original files on the camera and the verified download cache are never edited in place. The cross-device contract is described by [Protocol V1](docs/reference/protocol-v1.md), with [`protocol/manifest.schema.json`](protocol/manifest.schema.json) as the normative Manifest specification.

## Build from source

### Clone the repository

```sh
git clone https://github.com/iamStephenFang/RetroLive.git
cd RetroLive
```

The repository has no external dependency bootstrap step.

### Modern importer

1. Open `modern-importer/RetroLiveImporter.xcodeproj` in a current version of Xcode.
2. Select the `RetroLiveImporter` target.
3. In **Signing & Capabilities**, choose your development team. Change the bundle identifier if your account cannot sign `com.retrolive.importer`.
4. Select an iPhone running iOS 17 or later and run the app.
5. Allow Local Network and Photos access when prompted.

The importer can be built in the simulator, but Bonjour, local-network transfer, PhotoKit persistence, and Live Photo playback should be tested on a physical iPhone.

### Legacy and Classic cameras

1. Read [the legacy build-environment notes](docs/guides/ios-6-build-environment.md).
2. For a modern editing Mac plus an isolated archived-toolchain Mac, follow the [legacy Mac sync and build guide](docs/guides/legacy-mac-sync-build.md).
3. Open `legacy-camera/RetroLiveCamera.xcodeproj` with the toolchain appropriate for the target device.
4. Choose either the `RetroLiveCamera` or `RetroLiveClassic` scheme.
5. Configure a signing identity and, if necessary, a unique bundle identifier.
6. Build and run on a physical iPhone. Grant camera, microphone, and local-network access when the OS requests them.

Do not raise the deployment target or replace legacy APIs merely to make the iOS 6 scheme build in current Xcode. That would stop the build from representing the device it is intended to support.

## Usage

### Capture on the old iPhone

1. Open the camera app and select `4:3`, `1:1`, or `16:9` from the framing control.
2. Use the shutter button to capture an asset. Motion capture starts in the background; if it cannot produce a valid clip, RetroLive keeps the JPEG as a photo-only asset.
3. Tap the thumbnail button to open the local library. Select an item to review its still image and, when present, its motion.

Captured assets stay inside RetroLive. The camera app does not add them directly to the system Camera Roll.

### Share from the old iPhone

1. Connect both iPhones to the same trusted Wi-Fi network.
2. Open the camera's local library.
3. Tap the transfer button in the navigation bar.
4. Tap **Start Sharing** and keep this screen open. Note the six-digit pairing code.

Sharing advertises a `_retrolive._tcp.` Bonjour service and exposes only committed assets. Stopping sharing invalidates the temporary session token.

### Import on the modern iPhone

1. Open `RetroLiveImporter` and select the camera under nearby devices.
2. Enter the six-digit code shown by the camera. The importer submits it automatically after the sixth digit.
3. Optionally keep **Remember This Device** enabled to store the pairing session in the modern iPhone's Keychain.
4. Choose an asset and tap **Import**. Keep both apps available until downloading and import complete.
5. Open Photos to verify the imported photo or Live Photo.

If discovery fails, confirm that both devices are on the same Wi-Fi network, Local Network permission is enabled for both apps, sharing is still running, and the network does not isolate wireless clients.

> [!IMPORTANT]
> Camera transfer uses authenticated but unencrypted HTTP. Use it only on a trusted local network, stop sharing when finished, and do not expose its port to the internet.

## Repository layout

```text
legacy-camera/       Objective-C camera targets and their shared core
modern-importer/     SwiftUI importer and XCTest target
protocol/            JSON Schema, OpenAPI contract, examples, and fixtures
tools/               Dependency-free host-side validation and integration runners
docs/                Architecture, formats, build notes, delivery notes, and test plans
design/              Source artwork and interface-icon tooling
```

The main runtime flow is:

```text
Legacy / Classic UI
        |
RLVCaptureController
        |
RLVAssetStore -> Assets/{assetId}/{photo.jpg,motion.mov,manifest.json}
        |
RLVTransferService + RLVTransferRouter
        |
Bonjour + paired read-only HTTP
        |
CameraAPIClient -> DownloadStore -> LivePhotoAssembler -> PhotoLibraryImporter
```

For component ownership and data boundaries, read [Architecture](docs/reference/architecture.md). For the on-disk representation, read [Asset storage](docs/reference/asset-storage.md) and the [Live Photo assembly contract](docs/reference/live-photo-assembly.md).
The [documentation guide](docs/README.md) identifies current specifications,
acceptance criteria, build notes, and historical phase records.

## Development guidelines

Changes should preserve these project boundaries:

- Treat `protocol/manifest.schema.json` as the source of truth. Update the schema, examples, fixture catalog, Objective-C parser, Swift parser, and tests together when the contract changes.
- Keep the `RLV` prefix for shared and legacy Objective-C symbols.
- Keep the iOS 6 target under ARC and use APIs available to its intended SDK.
- Let `RLVCaptureController` own AVFoundation capture, `RLVAssetStore` own asset paths and commits, and the transfer router serve only committed assets.
- Never modify camera originals or verified downloads in place. Assembly belongs in a separate working directory.
- Add user-visible text to English, Simplified Chinese, and Traditional Chinese resources for every affected target.
- Do not treat a current-SDK build, simulator test, or host runner as evidence of old-device camera, Wi-Fi, PhotoKit, or Live Photo behavior.

### Run the checks

Run the shared Manifest catalog through both the Python and Objective-C parsers:

```sh
python3 tools/test-manifest-fixtures/run.py
```

Build and run the transactional asset-store integration check:

```sh
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
```

Build and run the transfer-router integration check:

```sh
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
```

Run the modern test bundle with Xcode's **Product > Test**, or from the command line with an installed simulator:

```sh
xcodebuild test \
  -project modern-importer/RetroLiveImporter.xcodeproj \
  -scheme RetroLiveImporter \
  -destination 'platform=iOS Simulator,id=<simulator-udid>'
```

Before opening a pull request, also run:

```sh
find legacy-camera/RetroLiveCamera modern-importer/RetroLiveImporter \
  -name '*.strings' -print0 | xargs -0 plutil -lint
git diff --check
```

The verification levels and feature-specific acceptance indexes are in the [verification guide](docs/reference/verification-guide.md). When building both camera schemes in parallel, give them different `-derivedDataPath` values to avoid Xcode's build-database lock.

## Project status

The repository contains the implemented protocol, capture/storage, local transfer, verified download, assembly, and import paths. Current automated coverage includes the shared Manifest fixture catalog, asset transactions, transfer routing, pagination and byte ranges, checksum-verified/resumable downloads, aspect-ratio geometry, generated JPEG/MOV assembly, and import-history recovery.

The following checks remain hardware- or environment-dependent:

- authentic iOS 6 builds with an archived Xcode and SDK;
- real-camera timing, audio, orientation, interruption, low-storage, and sustained-capture behavior;
- UI fidelity on each intended legacy device and OS version;
- Bonjour discovery and transfer between physical devices, including interrupted Wi-Fi and capture/download concurrency; and
- PhotoKit persistence and Live Photo playback on a physical modern iPhone.

Detailed acceptance criteria are owned by the feature specifications linked from the [verification guide](docs/reference/verification-guide.md).

## Contributing and support

Bug reports and focused pull requests are welcome through [GitHub Issues](https://github.com/iamStephenFang/RetroLive/issues). Include the target, Xcode build, iPhone model, iOS version, reproduction steps, and relevant logs. For camera, network, or Live Photo changes, describe which simulator, host, or physical-device checks you actually performed.

Protocol changes should start with an issue so compatibility and fixture changes can be agreed before implementation. Keep pull requests scoped, preserve legacy-device compatibility, and update the documentation and test catalog with behavior changes.

The repository does not yet include separate `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, or `SECURITY.md` files. These should be added before growing a public contributor community.

## License

No open-source license has been added yet. Until the repository owner selects and adds one, the source is publicly visible but no permission to use, modify, or redistribute it is granted. Add an OSI-approved license before presenting RetroLive as an open-source release.
