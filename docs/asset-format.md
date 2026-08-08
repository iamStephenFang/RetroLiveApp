# Asset Format

Each completed Phase 2 motion asset is an immutable directory:

```text
Assets/{assetId}/
  photo.jpg
  motion.mov
  manifest.json
```

The camera writes into `Temporary/{assetId}` first, validates the JPEG, dimensions, byte length, SHA-256, identifier, and Manifest, then atomically moves the directory into `Assets`. A directory in `Assets` is therefore committed; startup removes leftover temporary directories.

`photo.jpg` is always the independently captured high-quality still. A successful Phase 2 capture adds the trimmed QuickTime movie and a motion object without changing `assetId`. If motion capture fails, the valid fallback remains the Phase 1 representation: `motion` is JSON `null`, timing values are zero, and no fake MOV is created.
