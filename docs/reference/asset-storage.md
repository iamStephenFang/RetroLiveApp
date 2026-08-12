---
title: Asset Storage
status: current
type: reference
---

# Asset Storage

Each committed photo-plus-motion asset is an immutable directory:

```text
Assets/{assetId}/
  photo.jpg
  motion.mov
  manifest.json
```

The camera writes into `Temporary/{assetId}` first, validates the JPEG, dimensions, byte length, SHA-256, identifier, and Manifest, then atomically moves the directory into `Assets`. A directory in `Assets` is therefore committed; startup removes leftover temporary directories.

`photo.jpg` is always the independently captured high-quality still. A
successful motion capture adds the trimmed QuickTime movie and a motion object
without changing `assetId`. If motion capture fails, the valid photo-only
representation uses `motion: null`, zero motion timings, and no fabricated MOV.

New captures include `capture.aspectRatio` (`4:3`, `1:1`, or `16:9`). The field records presentation intent rather than claiming that the encoded JPEG and MOV already have matching dimensions. Original media stays immutable and preserves the maximum recoverable source area. Existing V1 assets without the field are interpreted as `native` and are never retroactively cropped.
