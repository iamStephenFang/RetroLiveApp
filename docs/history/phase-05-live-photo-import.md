---
title: Phase 5 — Live Photo Import
status: historical
type: history
---

# Phase 5 — Live Photo Import

> Historical phase summary. See the [documentation index](../README.md) for
> current contracts and acceptance status.

## Goal

Convert a freshly verified cached asset into either a normal photo or one paired
Live Photo and submit it safely to Photos.

## Planned scope

- Attempt-scoped assembly outside the immutable download cache.
- A shared content identifier in generated JPEG and MOV resources.
- Timed QuickTime still-image metadata at the validated Manifest still time.
- Output validation before one PhotoKit creation request.
- Normal-photo handling for `motion: null` assets.
- Durable duplicate protection across rapid taps, failure, crash, and relaunch.

Repairing corrupt input, inferring missing motion data, camera mutation, editing
extensions, albums, and cloud history sync were excluded.

## Delivered boundary

- Separate `Assembly/Temporary` attempts and validated committed assembly output.
- JPEG/MOV identifier insertion and reopened-media validation.
- Injectable PhotoKit adapter selecting `.photo` alone or
  `.photo + .pairedVideo` from the Manifest.
- Durable `submitting` and `imported` journal states.
- Synchronous per-asset in-flight guard and explicit `needsConfirmation` state
  for uncertain PhotoKit crash windows.
- Photo-only path that never fabricates a paired video.

The Phase 5 implementation first appeared in the Phase 5 portion of
`8e22376 feature: phase 4 and 5 importer workflow` and was extended by
`350f312 feature: phase 5`.

## Important decisions

- Never mutate verified downloads; generated output belongs to a separate
  attempt and commit lifecycle.
- Reopen and validate identifiers, tracks, dimensions, transform, duration, and
  timed still metadata before PhotoKit.
- Persist `submitting` before `performChanges` and persist `imported` only after
  PhotoKit reports success with a non-empty placeholder identifier.
- A stale or uncertain submission must not retry automatically because add-only
  Photos access cannot prove whether the interrupted request succeeded.
- A failed replacement must preserve the last known-good assembly.

## Validation at completion

Current-SDK automated checks covered Manifest boundaries, journal migration,
in-flight ownership, relaunch recovery, photo-only resource selection, and
download-to-import state integration. The correctness review recorded path
isolation, assembly replacement, output validation, and duplicate-protection
gaps as fixed in production code.

Synthetic-media assembly coverage, complete mock PhotoKit coordinator evidence,
and physical-device acceptance remained separate release gates.

## Remaining acceptance

- Validate generated JPEG/MOV metadata with deterministic synthetic media,
  including transform, audio, duration, boundary still times, and failure paths.
- Cover PhotoKit permission, resource selection, success, failure, missing
  placeholder, interruption, and uncertain completion through an injected mock.
- On a physical modern iPhone, verify normal photos and Live Photos after
  relaunch, repeated taps, force-quit windows, low storage, and denied/granted
  Photos permission.
- Confirm source filenames, sizes, and hashes remain unchanged throughout.

## Related current documentation

- [Modern Import Workflow](../specifications/modern-import-workflow.md)
- [Live Photo Assembly](../reference/live-photo-assembly.md)
- [Architecture](../reference/architecture.md)
- [Verification Guide](../reference/verification-guide.md)
