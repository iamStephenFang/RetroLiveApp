---
title: RetroLive Phase History
status: current
type: index
---

# RetroLive Phase History

This directory reconstructs the original Phase 0–5 delivery sequence and records
the Phase 6 implementation scope. It is organized only by phase: plans,
implementation decisions, audit findings, and remaining acceptance are
consolidated into the phase that owns them.

## Phase map

| Phase | Historical goal | Primary output | Document |
| --- | --- | --- | --- |
| 0 | Establish the cross-device contract and compilable app foundations | Manifest V1, OpenAPI, shared fixtures, legacy and modern parsers | [`phase-00-protocol-foundation.md`](phase-00-protocol-foundation.md) |
| 1 | Capture and persist an immutable photo-only asset | Shared camera core, permanent asset identity, transactional asset store, local library | [`phase-01-photo-capture-and-storage.md`](phase-01-photo-capture-and-storage.md) |
| 2 | Add shutter-centered motion while preserving the independent still | Rolling movie, trimming, optional audio, motion metadata, photo-only fallback | [`phase-02-motion-capture.md`](phase-02-motion-capture.md) |
| 3 | Expose committed assets over a read-only local-network API | Bonjour service, pairing, bearer session, pagination, ranges | [`phase-03-lan-transfer.md`](phase-03-lan-transfer.md) |
| 4 | Discover cameras and build a verified immutable download cache | Discovery, pairing client, resumable download, length/hash verification | [`phase-04-download-and-verification.md`](phase-04-download-and-verification.md) |
| 5 | Assemble and import a normal photo or Live Photo | Paired JPEG/MOV assembly, PhotoKit boundary, durable duplicate protection | [`phase-05-live-photo-import.md`](phase-05-live-photo-import.md) |
| 6 | Make importing practical at library scale while preserving storage and metadata boundaries | Durable serial batch queue, storage preflight/cleanup, capture-time and metadata fidelity | [`phase-06-batch-import-and-storage.md`](phase-06-batch-import-and-storage.md) |

## Dependency sequence

```text
Phase 0: protocol contract
    -> Phase 1: immutable photo asset
    -> Phase 2: optional motion resource
    -> Phase 3: read-only camera API
    -> Phase 4: verified importer cache
    -> Phase 5: Live Photo assembly and Photos import
    -> Phase 6: durable batch import, storage management, and metadata fidelity
```

Each phase consumes the committed boundary of the previous phase. A later phase
must not mutate an earlier phase's immutable output.

## Reading rule

These documents explain delivered scope and decisions. Use the main
[documentation index](../README.md), current references, and feature
specifications for present behavior and acceptance status. Phase 6 still requires
physical-device acceptance; exact earlier wording remains available through Git
history.
