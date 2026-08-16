---
title: Capture and Storage
status: implemented-pending-device-validation
type: specification
---

# Capture and Storage

## Product boundary

The Legacy and Classic targets capture one independent still for every accepted
shutter event. When motion capture is enabled and succeeds, the same asset also
contains a short shutter-centered movie. Any motion failure preserves a valid
photo-only asset rather than losing the still or fabricating video.

The camera stores RetroLive assets only in its private application storage. It
does not copy captures into the system Camera Roll.

## Capture contract

1. Create the permanent UUID, shutter timestamp, orientation, camera position,
   mirroring state, flash mode, and selected aspect ratio before asynchronous
   JPEG completion.
2. Capture `photo.jpg` independently at the shutter event; never substitute a
   frame extracted from `motion.mov`.
3. Keep a bounded compressed rolling movie on disk and close it after the
   configured post-roll window.
4. Trim motion around the same shutter event and record actual duration,
   dimensions, frame rate, audio presence, pre-roll, post-roll, and still time.
5. If recording, trimming, or motion validation fails, commit `motion: null`,
   zero motion timings, and no MOV while retaining the captured JPEG.
6. Camera switching, orientation changes, interruptions, backgrounding, and
   session restart must not expose partial assets or reuse an asset identifier.

## Storage transaction

`RLVAssetStore` is the only component that constructs permanent asset paths.
Each capture is written under `Temporary/{assetId}`, validated, and atomically
moved into `Assets/{assetId}`. Only committed directories are visible to the
library and transfer service.

Before commit or exposure, validate the canonical UUID, Manifest semantics,
filenames, media presence, dimensions, timing ranges, byte lengths, and exact
lowercase SHA-256 values. Startup recovery removes abandoned temporary asset
directories without modifying committed assets.

The filesystem representation is defined by [Asset Storage](../reference/asset-storage.md),
and Manifest fields are defined by [Protocol V1](../reference/protocol-v1.md).

## Framing and orientation

`RLVCameraOrientationCoordinator` is the single source for still, movie,
Manifest, and control orientation. Because the camera UI is portrait-locked,
the preview connection remains portrait while control contents rotate and
captured media records the device orientation. The selected `4:3`, `1:1`, or
`16:9` ratio is presentation intent; original media retains the maximum
recoverable source area. Preview hit-testing and saved composition must agree.

## Repository acceptance

- The Manifest fixture catalog passes in every parser implementation.
- The asset-store integration runner covers motion and photo-only commits,
  reload, corrupt or missing resources, hash/media validation, and temporary
  recovery using an injected Documents root.
- Both camera target source sets compile without raising their intended source
  compatibility boundary.
- Plists and localization resources lint successfully, and `git diff --check`
  passes.
- A current-SDK build is reported only as source-integration evidence.

## Physical-device acceptance

Run Legacy on an iPhone 4S or iPhone 5 with iOS 6.x and Classic on an intended
iOS 7/8-era device. Record the exact device, OS, archived toolchain, signing
state, and app build.

1. Capture 20 assets continuously without crash, freeze, session loss, partial
   library entries, or identifier replacement.
2. Verify Portrait, Landscape Left, and Landscape Right preview, still, movie,
   and Manifest orientation agreement for front and rear cameras.
3. Exercise supported flash modes, camera switching, background/foreground,
   low storage, forced termination during staging, and relaunch recovery.
4. For warmed motion captures, verify approximately 1.5 seconds of pre-roll and
   post-roll, still-time error no greater than 200 ms, correct movie orientation,
   and audio when permission and hardware allow it.
5. Repeat near startup and a rolling-segment boundary; shortened motion must be
   reported accurately rather than padded or fabricated.
6. Force a motion failure and confirm that the JPEG remains available as
   `motion: null` with zero motion timings and no `motion.mov`.
7. For `4:3`, `1:1`, and `16:9`, verify persistence across relaunch, control
   rotation, preview/focus alignment, and saved still/motion composition.
8. Confirm no capture is written to the system Camera Roll.

Focus/exposure cases are owned by [Tap to Focus](tap-to-focus.md). Camera chrome
comparison is owned by [Camera UI Measurements](camera-ui-measurements.md).
Library paging, zoom, decoding, and Live/Loop/Bounce/Still playback are owned by
[Asset Preview Paging](asset-preview-paging.md).
