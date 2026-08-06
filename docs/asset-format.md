# Asset Format

Each completed asset is an immutable directory:

```text
Assets/{assetId}/
  photo.jpg
  motion.mov
  thumbnail.jpg
  manifest.json
  state.json
```

The legacy application writes into `Staging/{assetId}` first, validates the complete set, and atomically moves it into `Assets`. Phase 0 defines the metadata contract only; transactional storage is implemented in a later phase.

`photo.jpg` is always the independently captured high-quality still. `motion.mov` supplies the motion and optional audio. `capture.stillImageTimeSeconds` indicates the natural transition point on the video's timeline and does not claim that the JPEG was extracted from that frame.

