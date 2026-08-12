---
title: Live Photo Assembly
status: current
type: reference
---

# Live Photo Assembly

This reference defines the paired-media output contract. Workflow state,
permissions, recovery behavior, and acceptance criteria belong to the
[Modern Import Workflow specification](../specifications/modern-import-workflow.md).

## Input boundary

Assembly accepts only a freshly validated immutable cached asset:

- `photo.jpg` is required;
- `motion.mov` is required only when Manifest `motion` is non-null;
- the Manifest asset identifier, byte lengths, hashes, media properties, and
  still-image time have already passed validation.

A photo-only asset bypasses paired-media assembly and is imported as a normal
photo. Assembly does not fabricate motion or infer missing timing metadata.

## Output boundary

```text
Downloads/Assets/{assetId}/       immutable verified input
Assembly/Temporary/{attemptId}/   generated staging output
Assembly/Assets/{assetId}/        validated committed output
```

Input and output directories are separate. Assembly may copy, crop, remux, or
encode generated resources, but it never edits or moves a file under the
verified download cache.

## Paired-media contract

- The generated JPEG and MOV contain the same content identifier, derived from
  the canonical Manifest `assetId`.
- The MOV contains `com.apple.quicktime.content.identifier` and a timed
  `mdta/com.apple.quicktime.still-image-time` sample at the validated still time.
- The generated JPEG remains decodable and retains the expected display
  dimensions and orientation semantics.
- The generated MOV contains a playable video track and retains the expected
  duration, transform, and audio presence.
- Generated resources are reopened and validated before they become committed
  assembly output.

## Framing contract

When `capture.aspectRatio` is present, the display-oriented motion aperture is
the common field of view. The still is first center-cropped into that aperture;
the chosen `4:3`, `1:1`, or `16:9` frame is then applied consistently to both
generated resources. Photo orientation is flattened in the generated JPEG.

Assets without `capture.aspectRatio` retain the earlier pass-through behavior.
The original downloaded JPEG and MOV remain unchanged in both cases.

## Non-goals

This reference does not define:

- legacy-library playback modes or gestures;
- download, retry, cancellation, or assembly-replacement behavior;
- PhotoKit authorization, submission, duplicate protection, or uncertain-result
  recovery;
- current delivery status or physical-device acceptance.

Those behaviors are owned by [Asset Preview Paging](../specifications/asset-preview-paging.md)
and [Modern Import Workflow](../specifications/modern-import-workflow.md).
