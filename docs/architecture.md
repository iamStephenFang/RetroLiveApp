# Architecture

RetroLive has two legacy camera targets and one modern importer. The camera targets share source-level Capture, Device, Asset, Manifest, and Library foundations. The importer consumes the versioned protocol under `protocol/` without sharing legacy implementation code.

```text
Legacy UI (iOS 6) ----\
                       -> RLVCaptureController -> RLVAssetStore
Classic UI (iOS 8) ---/                         -> Assets/{assetId}/photo.jpg
                                                  Assets/{assetId}/motion.mov
                                                  Assets/{assetId}/manifest.json
                                                           |
                                           RLVTransferRouter
                                                           |
                                  HTTP + Bonjour read-only transfer
                                                           |
                                  CameraAPIClient + DownloadStore
                                                           |
                                      immutable verified cache
                                                           |
                                LivePhotoAssembler + PhotoKit
```

## Boundaries

UI code owns layout and user interaction. `RLVCaptureController` exclusively owns the AVFoundation session. `RLVAssetStore` exclusively owns media paths and commits. `RLVManifest` writes the cross-device contract. No ViewController writes asset files.

Original downloads and generated paired resources must use separate directories. No conversion stage may modify a source file in place.

## Phase 1

Each shutter press creates `RLVCaptureEvent` immediately, including the permanent UUID, shutter timestamp, orientation, and camera position. The still JPEG and Manifest are written into `Temporary/{assetId}`, validated, then moved into `Assets/{assetId}` as the final commit. Startup recovery conservatively removes uncommitted temporary directories.

`RLVCameraOrientationCoordinator` is the single source for preview/capture orientation, EXIF-style manifest orientation, movie orientation, and control transforms.

## Phase 2

`RLVCaptureController` maintains one bounded, compressed rolling movie on disk. A shutter event captures the JPEG immediately, closes the roll after the post-window, trims a motion clip around that same event, and passes both resources to `RLVAssetStore`. Motion failure degrades to the V1 photo-only representation without losing the independent still.

## Phase 3

The user explicitly starts RLVTransferService from the local library. It publishes _retrolive._tcp., accepts a six-digit pairing code, and streams only committed assets through the versioned read-only HTTP API. RLVTransferRouter owns authorization, pagination, UUID validation, optional-resource handling, and byte ranges; the socket layer never constructs asset filesystem paths. Stopping sharing destroys the router and invalidates its temporary bearer token.

## Phase 4

The modern importer discovers `_retrolive._tcp.` services, pairs through `CameraAPIClient`, paginates the committed asset list, and downloads each Manifest resource through `DownloadStore`. Partial files stay in `Temporary`, byte ranges resume when possible, SHA-256 and byte length are verified while streaming, and only complete assets are atomically committed to the immutable download cache.

## Phase 5

`LivePhotoAssembler` copies verified resources into a separate assembly workspace, writes one content identifier to the JPEG and MOV, writes the Manifest still time to the QuickTime metadata track, then validates the generated pair. `PhotoLibraryImporter` submits `.photo` and `.pairedVideo` in one PhotoKit request; photo-only manifests follow a normal-photo path. `ImportHistoryStore` records the asset identifier after success so repeated imports are idempotent.
