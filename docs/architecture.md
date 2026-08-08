# Architecture

RetroLive has two legacy camera targets and a future modern importer. The camera targets share source-level Capture, Device, Asset, Manifest, and Library foundations. The importer shares only the versioned protocol under `protocol/`.

```text
Legacy UI (iOS 6) ----\
                       -> RLVCaptureController -> RLVAssetStore
Classic UI (iOS 8) ---/                         -> Assets/{assetId}/photo.jpg
                                                  Assets/{assetId}/manifest.json
```

## Boundaries

UI code owns layout and user interaction. `RLVCaptureController` exclusively owns the AVFoundation session. `RLVAssetStore` exclusively owns media paths and commits. `RLVManifest` writes the cross-device contract. No ViewController writes asset files.

Original downloads and generated paired resources must use separate directories. No conversion stage may modify a source file in place.

## Phase 1

Each shutter press creates `RLVCaptureEvent` immediately, including the permanent UUID, shutter timestamp, orientation, and camera position. The still JPEG and Manifest are written into `Temporary/{assetId}`, validated, then moved into `Assets/{assetId}` as the final commit. Startup recovery conservatively removes uncommitted temporary directories.

`RLVCameraOrientationCoordinator` is the single source for preview/capture orientation, EXIF-style manifest orientation, and control transforms. Phase 2 can attach a rolling buffer around the same capture event without changing asset identity or UI ownership.
