---
title: Phase 3 — LAN Transfer
status: historical
type: history
---

# Phase 3 — LAN Transfer

> Historical phase summary. See the [documentation index](../README.md) for
> current contracts and acceptance status.

## Goal

Make committed camera assets readable by a modern device on the same trusted
local network without introducing remote mutation.

## Planned scope

- A foreground, user-controlled service shared by both camera targets.
- Bonjour discovery, six-digit pairing, temporary bearer authorization, and a
  versioned read-only HTTP API.
- Paginated committed assets and streamed Manifest/photo/optional-motion data.
- Strict identifier/path validation and resumable byte-range responses.

Upload, deletion, remote mutation, cloud transfer, modern cache ownership, Live
Photo assembly, and PhotoKit were excluded.

## Delivered boundary

- `_retrolive._tcp.` publication through `RLVTransferService`.
- Pairing attempt lockout, 15-minute bearer sessions, and token invalidation when
  sharing restarts.
- Health, device, asset-list, Manifest, photo, optional motion, and thumbnail
  fallback routes.
- `RLVTransferRouter` ownership of authorization, pagination, UUID validation,
  optional-resource decisions, and single byte ranges.
- File streaming in bounded chunks while serving only committed assets resolved
  through `RLVAssetStore`.

Delivery and hardening were recorded in
`143b674 feature: phase 3 transfer and protocol hardening`.

## Important decisions

- Keep the server read-only and foreground-controlled.
- Separate host-testable routing from socket and Bonjour ownership.
- Never append an unvalidated request path directly to the filesystem.
- Treat optional thumbnails truthfully and use the immutable photo as the
  documented fallback.
- Pairing reduces accidental or unauthorized API use but does not encrypt LAN
  traffic; the design assumes trusted local Wi-Fi.

## Validation at completion

The host router runner covered health, failed and successful pairing, lockout,
bearer authorization, device information, pagination, Manifest/photo/optional
motion routing, thumbnail fallback, normal and suffix ranges, 404, and 416.

Later hardening rejected malformed numeric input, bounded pagination/range/body
lengths, and ensured media files are opened and proven regular/readable before
success headers are sent.

## Remaining acceptance

- Verify Bonjour publication/discovery, real listening-socket behavior, Wi-Fi
  loss/recovery, foreground suspension, and token lifecycle on both intended
  legacy-device families.
- Verify interrupted Range downloads, byte-identical output, repeated service
  restart, and capture/download concurrency on physical devices.
- Do not treat host routing tests or current-SDK builds as network acceptance.

## Related current documentation

- [LAN Transfer](../specifications/lan-transfer.md)
- [`api.openapi.yaml`](../../protocol/api.openapi.yaml)
- [Architecture](../reference/architecture.md)
- [Verification Guide](../reference/verification-guide.md)
