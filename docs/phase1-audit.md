# Phase 0 to Phase 1 Audit

Document status: Historical design record. Use [`README.md`](README.md) to find
the current contracts and acceptance criteria.

## Existing state found

| Area | Phase 0 state |
|---|---|
| Targets | `RetroLiveCamera` iOS app and `RetroLiveImporter` app/tests |
| Deployment | Camera 6.0; importer 17.0 |
| Architectures | Camera inherited the archived toolchain default; importer inherited current defaults |
| Shared code | Objective-C Manifest model/parser only |
| Manifest | V1 required photo, motion, thumbnail, capture timing, device metadata, hashes, and UUID |
| Asset ID | UUID string in Manifest, with no capture-time generator |
| Filesystem | `Assets`/staging layout documented but not implemented |
| Camera/UI | Placeholder view controller; no AVFoundation session or local library |

## Phase 1 decisions

- Preserve the existing project rather than reinitialize it.
- Keep `RetroLiveCamera` at iOS 6.0/armv7 and add `RetroLiveClassic` at iOS 8.0/armv7+arm64.
- Compile identical Shared source files into both targets; `RLV_CLASSIC` selects only the camera entry UI.
- Evolve Manifest V1 without breaking motion assets: `motion` is required and nullable, while `thumbnail` becomes optional.
- Generate the permanent UUID and shutter timestamp in `RLVCaptureController` before asynchronous JPEG completion.
- Use `Documents/RetroLive/Temporary/{UUID}` followed by validated directory move to `Documents/RetroLive/Assets/{UUID}`.
- Keep the app portrait-locked and rotate individual controls through one orientation coordinator.

## Compatibility boundary

The Legacy source intentionally uses `AVCaptureStillImageOutput`, `UIAlertView`, `UITextAlignment`, Foundation accessor methods, and UIKit/Core Animation primitives available to the iOS 6-era toolchain. Newer replacements are not used in the shared core because they would raise the minimum OS. Exact archived Xcode/iOS 6 SDK compilation remains a separate required check.
