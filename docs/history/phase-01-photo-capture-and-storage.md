---
title: Phase 1 — Photo Capture and Storage
status: historical
type: history
---

# Phase 1 — Photo Capture and Storage

> Historical phase summary. See the [documentation index](../README.md) for
> current contracts and acceptance status.

## Goal

Turn one shutter press into one durable, immutable photo-only RetroLive asset on
both legacy camera targets.

## Planned scope

- Preserve the existing repository and add capture/storage incrementally.
- Keep `RetroLiveCamera` at iOS 6 and add `RetroLiveClassic` for the iOS 8-era
  experience using the same shared source set.
- Capture an independent still, assign permanent identity at shutter time, and
  commit it transactionally.
- Provide startup recovery, a local library, orientation coordination, camera
  switching, and supported flash behavior.

Rolling motion, LAN transfer, modern download, Live Photo metadata, and PhotoKit
were deferred.

## Delivered boundary

- Shared `RLVCaptureController` ownership for Legacy and Classic.
- Permanent UUID and shutter timestamp before asynchronous JPEG completion.
- Independent high-quality still with orientation and camera metadata.
- `Temporary/{assetId}` staging followed by validated atomic commit into
  `Assets/{assetId}` through `RLVAssetStore`.
- Manifest V1 photo-only representation using `motion: null`, zero motion
  timings, and no fabricated MOV.
- Startup recovery, committed-asset loading, and local-library foundations.

The initial delivery was recorded in `e34cd1f feature: phase 1`.

## Important decisions

- Keep Objective-C ARC and APIs available to the intended iOS 6-era SDK.
- Compile the same shared capture/storage sources into both camera targets;
  target-specific code selects only the UI surface.
- Generate asset identity before asynchronous media completion so retries cannot
  replace or fork an accepted shutter event.
- Keep the app portrait-locked while one orientation coordinator maps preview,
  capture, Manifest, movie, and control orientation.
- `RLVAssetStore`, not a view controller, owns paths, validation, commit, load,
  deletion boundaries, and recovery.

## Validation at completion

Repository runners covered photo-only commit, reload, malformed or missing
resources, and abandoned staging recovery. Later audit hardening added canonical
UUID and managed-directory checks before load, delete, or commit; required
positive resource sizes; and filtered corrupted-hash or missing-photo assets
from the library.

Both camera source sets were checked against the current SDK, but that evidence
was explicitly limited to source integration.

## Remaining acceptance

- Build and sign both targets with the preserved historical toolchain.
- Verify still capture, orientation, camera switching, flash, recovery, storage
  failure, and repeated-capture stability on intended iOS 6/iOS 8 hardware.
- Complete exact-device camera UI comparison rather than inferring fidelity from
  programmatic layout or a host build.

## Related current documentation

- [Architecture](../reference/architecture.md)
- [Asset Storage](../reference/asset-storage.md)
- [Capture and Storage](../specifications/capture-and-storage.md)
- [Verification Guide](../reference/verification-guide.md)
