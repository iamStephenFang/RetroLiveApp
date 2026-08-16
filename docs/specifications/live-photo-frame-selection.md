---
title: Live Photo Frame Selection
status: provisional
type: specification
---

# Live Photo Frame Selection

## Goal

Enable the Legacy and Classic camera apps to save a user-chosen still frame from the captured motion clip as a persisted Live Photo candidate. The feature must preserve the project’s current guarantees: the original JPEG and motion clip remain immutable, selection happens in a separate time-normalization step, and the final saved asset still validates against the Manifest contract.

## Principles

1. The shutter event remains the authoritative capture moment.
2. The user-selected frame is a normalized offset within the motion clip, not a new source media file.
3. The camera app commits only one canonical asset directory per UUID.
4. Legacy and Classic share the same selection logic through `RLVFrameSelection` so behavior stays consistent across both apps.
5. A selection that falls outside valid motion bounds never creates an invalid Manifest or out-of-range still time.

## Product boundary

The app exposes a still-frame selection step during review or save, but it does not modify the source `photo.jpg` or `motion.mov` in place. Instead, it derives a `stillImageTimeSeconds` value for the selected frame and stores that value in the Manifest for a downstream import pass.

This is intentionally separate from the normal auto-detected shutter frame. The automatic frame remains the default for captures taken without user interaction. The explicit selection flow is a manual override that still preserves the auditability of the original motion timeline.

## User flow

1. The user captures a motion asset.
2. The app records the shutter-centered default still time and stores it in the Manifest.
3. In the library review flow, the user can choose a frame from the motion clip to save as the retained still.
4. The app normalizes the requested time to the valid motion range.
5. The resulting time is persisted as `capture.stillImageTimeSeconds` for the asset, while the original media and metadata remain untouched.
6. A future import or export pass uses the normalized frame as the still-image anchor for paired-output assembly.

## Selection algorithm

Given a motion duration `D` and a requested time `T`:

- if `D <= 0`, return `0.0` and preserve the fallback photo-only path;
- if `T < 0`, return `0.0`;
- if `T > D`, return `D` for clamp semantics, but the Manifest validator must reject equality when the asset is a motion asset; therefore the final write path must treat the maximum valid time as `D - epsilon` when a motion asset is committed;
- when the app presents a user frame preview, it must clamp to a safe valid range `[0, D)` and sample nearest valid frame index.

The helper should also support a safe preview window to avoid selecting an exact end boundary. `stillImageTimeSeconds` must remain strictly less than `motion.durationSeconds` for motion assets as required by the Manifest and parser contracts.

## Data contract

The feature adds no new top-level Manifest fields. It reuses the existing `capture.stillImageTimeSeconds` semantics and the existing motion metadata. This keeps the change compatible with the established protocol and avoids a schema fork.

The selected frame must satisfy all current requirements:

- `capture.stillImageTimeSeconds >= 0`
- `capture.stillImageTimeSeconds < motion.durationSeconds` when `motion` is non-null
- `preRollSeconds` and `postRollSeconds` remain consistent with the selected anchor
- `stillImageTimeAccuracy` remains `measured` or `estimated` depending on the selection source

## Implementation notes for Legacy and Classic

The shared camera core should own the new helper in the same style as the other capture and layout utilities:

- Add a small Objective-C utility in the shared `Shared/Utilities` layer.
- Keep the logic independent from UI and AVFoundation session state.
- Do not write the selection result back into the original captured media files.
- Only the asset creation pipeline may update the Manifest and finalize the asset commit.

The helper should be called by review/save flows before they write a manifest or final asset record, not by the raw capture controller. That preserves the capture-manager boundary described in the architecture reference.

## Acceptance criteria

- A requested frame before the clip starts maps to the earliest valid frame.
- A requested frame after the clip ends maps to the latest safe frame before end-of-video.
- A frame selection is never written as `== motion.durationSeconds` for a motion asset.
- Photo-only assets still allow `stillImageTimeSeconds = 0` and zero motion timings.
- The selection logic is shared between Legacy and Classic and remains free of UI-specific assumptions.
- Existing Manifest parser and validation tests remain green.

## Non-goals

- Re-encoding the original motion clip with a different chosen still frame.
- Writing a new media file for each frame preview.
- Changing the wire protocol schema or adding a new asset type.
- Automatically modifying the original shutter time when the user changes the selected frame.

## Validation

The repository already validates the Manifest contract with fixture parsing and asset-store checks. This feature must satisfy the same acceptance path by verifying:

- selection normalization is bounded and deterministic;
- the final `stillImageTimeSeconds` remains valid for both motion and photo-only assets;
- no asset directory is modified in place once committed.
