# Phase 2 Motion Capture Delivery Plan

## Scope

Phase 2 turns each supported shutter press into one immutable photo-plus-motion asset. The legacy camera remains the capture owner; networking, modern-device download, Live Photo metadata injection, and PhotoKit import remain later phases.

## Technical design

`RLVCaptureController` adds an `AVCaptureMovieFileOutput` and optional microphone input to the existing session. It continuously records a compressed QuickTime segment under `NSTemporaryDirectory/RetroLiveRolling`, capped at 30 seconds. This disk-backed design avoids retaining uncompressed 720p frames in iPhone 4S-class memory.

At shutter time the controller still creates the permanent UUID and timestamp before asynchronous work. It captures the independent JPEG immediately, keeps recording for a 1.5-second post-roll, then uses `AVAssetExportSession` to trim the rolling file to at most 1.5 seconds before and after the shutter. Orientation changes and camera switches rotate the temporary recording before reconfiguration. Abandoned rolling files are removed on controller startup.

The trimmed movie is inspected for duration, transformed dimensions, nominal frame rate, and audio presence. `RLVAssetStore` copies `photo.jpg` and `motion.mov` into `Temporary/{assetId}`, generates Manifest V1 with actual timing/media metadata and SHA-256 values, validates both resources, and atomically renames the directory into `Assets/{assetId}`. If motion recording or trimming fails, the independently captured JPEG is committed as the already-supported photo-only form and the UI reports the motion error.

## Delivery standard

### Repository acceptance

- Both legacy camera targets compile from the same shared source set with their deployment targets unchanged at iOS 6.0 and iOS 8.0.
- A successful motion capture commits exactly `photo.jpg`, `motion.mov`, and `manifest.json` under one UUID directory.
- The JPEG remains an independent still capture; no video frame is substituted for it.
- Manifest V1 contains positive movie duration/dimensions/frame rate, the actual `hasAudio` value, actual file byte length/SHA-256, and a still time within movie duration.
- Photo-only fallback uses `motion: null` and zero motion timing values.
- Temporary asset directories and abandoned rolling files are not exposed by the local library.
- Protocol fixtures, Objective-C parser/store runners, both camera host-source builds, plist validation, and `git diff --check` pass.

### Real-device acceptance

- After at least 1.5 seconds of camera warm-up, a normal capture produces approximately three seconds of motion, targeting at least 1.35 seconds before and after the shutter. The Manifest records the actual shorter interval at startup, a 30-second segment boundary, or interruption.
- The visual still point agrees with the shutter event within 200 ms. Phase 2 uses a wall-clock estimate and therefore declares `stillImageTimeAccuracy: estimated`.
- Rear/front, Portrait, Landscape Left, and Landscape Right motion orientation agrees with the still image.
- Audio is present when microphone access and hardware are available; denied/unavailable audio still produces a valid silent movie.
- Twenty sequential captures complete without crash, camera-session loss, orphaned temporary files, or UUID replacement.
- Backgrounding, forced termination, low storage, camera switching, and orientation changes recover to a usable camera without exposing partial assets.

## Explicit non-goals

- HTTP discovery or transfer
- Modern importer workflow
- Live Photo pairing metadata or PhotoKit writes
- Pixel-level camera chrome changes

