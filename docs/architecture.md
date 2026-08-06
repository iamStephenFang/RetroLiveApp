# Architecture

RetroLive is split across an iOS 6 capture application and a modern iOS importer. Their only shared contract is the versioned protocol under `protocol/`.

```text
RetroLive Camera (iOS 6)
  -> photo.jpg + motion.mov + thumbnail.jpg + manifest.json
  -> read-only LAN HTTP API
  -> RetroLive Importer (modern iOS)
  -> validated download cache
  -> paired Live Photo resources
  -> PhotoKit
```

## Boundaries

The camera owns capture, original asset storage, local playback, and read-only LAN serving. The importer owns discovery, resumable downloads, checksum verification, Live Photo metadata, previews, PhotoKit writes, and import history.

Original downloads and generated paired resources must use separate directories. No conversion stage may modify a source file in place.

## Phase 0

Phase 0 establishes one Manifest V1 schema, one API description, shared fixtures, and parsers on both platforms. It intentionally excludes capture, networking, media conversion, and persistence.

