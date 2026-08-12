---
title: Phase 4 — Download and Verification
status: historical
type: history
---

# Phase 4 — Download and Verification

> Historical phase summary. See the [documentation index](../README.md) for
> current contracts and acceptance status.

## Goal

Discover a RetroLive camera, pair with it, and convert remote committed assets
into a verified immutable cache on the modern device.

## Planned scope

- Bonjour discovery and camera-session connection.
- Pairing, authorization, device information, and bounded pagination.
- Temporary download staging with complete and Range-resumed transfers.
- Streaming byte-length and SHA-256 verification before atomic cache commit.
- Revalidation of committed cache entries and separate photo-only handling.

Media assembly, PhotoKit permission/submission, and mutation of camera-side or
cached source files were excluded.

## Delivered boundary

- `NetServiceBrowser` discovery and `CameraAPIClient` request ownership.
- In-memory bearer session and paginated asset loading.
- `DownloadStore` staging under `Temporary/{assetId}`.
- Safe append for valid 206 responses and restart for complete 200 responses.
- Atomic commit only after Manifest, filename, length, and hash verification.
- Rejection or quarantine of corrupt cache entries.

The Phase 4 implementation first appeared in the Phase 4 portion of
`8e22376 feature: phase 4 and 5 importer workflow`.

## Important decisions

- Keep verified downloads immutable and physically separate from assembly.
- Treat response metadata and cached files as untrusted until revalidated.
- Bound pages and reject duplicate identifiers/cursors so a malformed server
  cannot create an infinite pagination loop.
- Validate exact `Content-Range`, start offset, total length, and final resource
  length before committing a resumed download.
- Retain partial files only in temporary storage; never expose them as cached
  assets.

## Validation at completion

Current-SDK importer and test-bundle builds covered the client/store boundaries.
Focused tests exercised authorization and pagination behavior, resumable verified
download, unsafe cache identifiers, corrupt-cache handling, photo-only fallback,
and Manifest parsing.

Build-for-testing or simulator evidence did not establish real Bonjour or Wi-Fi
behavior.

## Remaining acceptance

- Discover and pair with both intended legacy-camera families over real Wi-Fi.
- Exercise incorrect/expired/replaced credentials, pagination at scale,
  interruption/relaunch resume, camera service restart, and Wi-Fi loss/recovery.
- Confirm committed bytes and hashes match the Manifest and cache cleanup never
  modifies camera originals.

## Related current documentation

- [Modern Import Workflow](../specifications/modern-import-workflow.md)
- [Protocol V1](../reference/protocol-v1.md)
- [Architecture](../reference/architecture.md)
- [Verification Guide](../reference/verification-guide.md)
