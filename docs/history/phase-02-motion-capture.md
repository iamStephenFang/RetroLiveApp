---
title: Phase 2 — Motion Capture
status: historical
type: history
---

# Phase 2 — Motion Capture

> Historical phase summary. See the [documentation index](../README.md) for
> current contracts and acceptance status.

## Goal

Add a short motion resource around the shutter event without replacing or
weakening the independently captured still photo.

## Planned scope

- Maintain a bounded compressed rolling QuickTime movie on disk.
- Capture the independent JPEG immediately and trim motion around the same
  shutter event.
- Record actual duration, still time, dimensions, frame rate, audio presence,
  length, and hash in Manifest V1.
- Commit photo and motion through the existing asset transaction.
- Preserve a valid photo-only asset when any motion step fails.

HTTP transfer, modern download, Live Photo pairing metadata, PhotoKit, and
pixel-level camera chrome were outside the phase.

## Delivered boundary

- `AVCaptureMovieFileOutput` rolling segments under a temporary
  `RetroLiveRolling` directory, bounded to 30 seconds.
- Optional microphone input and accurate `hasAudio` metadata.
- Up to approximately 1.5 seconds of pre-roll and post-roll around the shutter.
- Motion media inspection and Manifest timing/media metadata.
- Atomic `photo.jpg`, `motion.mov`, and `manifest.json` commit under one asset
  identifier.
- Photo-only fallback without losing or replacing the JPEG.

The initial delivery was recorded in `5ce441d feature: phase 2`.

## Important decisions

- Use disk-backed compressed recording instead of retaining uncompressed frames
  in iPhone 4S-class memory.
- Keep the JPEG as the authoritative independent still; never substitute a
  movie frame.
- Record actual shortened timing near startup, segment boundaries, or
  interruptions rather than padding or fabricating motion.
- Treat a trimmed movie whose still time falls outside its duration as a motion
  failure and commit the valid photo-only representation.
- Remove abandoned rolling files without exposing them through the library.

## Validation at completion

Repository checks covered motion and photo-only asset lifecycles, media metadata,
hashes, Manifest validation, corrupted assets, temporary recovery, and both
camera source builds. The completion audit recorded all repository-implementable
Phase 0–2 requirements as present after those gaps were closed.

These checks did not measure real shutter timing, microphone behavior, movie
orientation, or sustained camera-session stability.

## Remaining acceptance

- On intended iOS 6/iOS 8 devices, verify warmed captures, segment-boundary
  captures, still-time error no greater than 200 ms, orientation, and audio with
  granted and denied permission.
- Complete at least 20 sequential captures without crash, session loss, orphaned
  files, or identifier replacement.
- Exercise backgrounding, forced termination, low storage, camera switching,
  and orientation changes.
- Treat current-SDK builds as source checks, not old-device acceptance.

## Related current documentation

- [Capture and Storage](../specifications/capture-and-storage.md)
- [Asset Storage](../reference/asset-storage.md)
- [Protocol V1](../reference/protocol-v1.md)
- [Verification Guide](../reference/verification-guide.md)
