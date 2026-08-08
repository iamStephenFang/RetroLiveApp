# Asset Format

Each completed Phase 1 asset is an immutable directory:

```text
Assets/{assetId}/
  photo.jpg
  manifest.json
```

The camera writes into `Temporary/{assetId}` first, validates the JPEG, dimensions, byte length, SHA-256, identifier, and Manifest, then atomically moves the directory into `Assets`. A directory in `Assets` is therefore committed; startup removes leftover temporary directories.

`photo.jpg` is always the independently captured high-quality still. In Phase 1, `motion` is JSON `null`, motion timing values are zero, and no fake MOV is created. In Phase 2, the same asset directory may gain `motion.mov` and a motion object without changing `assetId`.
