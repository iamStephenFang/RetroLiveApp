---
title: Read-only LAN Transfer
status: implemented-pending-device-validation
type: specification
---

# Read-only LAN Transfer

## Goal

The transfer feature makes every committed RetroLive asset downloadable from a modern device on the same local network. It does not capture motion, implement the modern import UI, assemble Live Photos, write to PhotoKit, upload files, or remotely delete assets.

It serves both photo-plus-motion assets and the supported photo-only fallback. The motion endpoint exists only when the committed asset contains `motion.mov`; a photo-only asset returns 404 for that optional resource without affecting its photo or Manifest.

## Product scope

The Legacy and Classic applications provide a Transfer screen reachable from the local library. The user explicitly starts or stops sharing. While sharing is active, the screen shows the local HTTP address, Bonjour state, a six-digit pairing code, and a foreground-use reminder.

The server is read-only. It exposes health, pairing, device information, paginated asset summaries, manifests, photos, optional motion videos, and a photo-backed thumbnail response. Only directories already committed under Assets are visible.

## Technical design

### Compatibility

- Objective-C with ARC and Foundation/UIKit APIs available to the iOS 6 SDK.
- A small HTTP/1.1 server built on BSD sockets and GCD; no third-party server dependency.
- NSNetService advertises _retrolive._tcp. on the local domain.
- One request per connection with Connection: close. Request headers are capped at 64 KiB.
- Media is streamed from an immutable file in 64 KiB chunks instead of being loaded into memory.

### Security and session boundary

- GET /api/v1/health and POST /api/v1/session are the only unauthenticated operations.
- Pairing requires the displayed six-digit code and a non-empty client name.
- A successful pairing returns an opaque temporary bearer token valid for 15 minutes.
- Five failed pairing attempts trigger a 30-second lockout.
- Stopping or restarting sharing replaces the router and invalidates the previous token.
- Asset identifiers must be UUIDs and are resolved through RLVAssetStore; request paths are never appended directly to the filesystem.
- There are no write, upload, mutation, or delete routes.
- HTTP protects against accidental or unauthorized API use through pairing, but does not encrypt traffic from another observer on the same network. The feature therefore assumes a trusted local Wi-Fi network.

### HTTP behavior

- The implementation follows protocol/api.openapi.yaml under /api/v1.
- Asset pagination accepts limit=1...100 and an asset UUID cursor.
- Photo, motion, and thumbnail routes support one byte range in bytes=start-end, bytes=start-, or bytes=-suffixLength form.
- Valid ranges return 206, Accept-Ranges, and Content-Range; invalid ranges return 416.
- A thumbnail request serves the immutable photo when no separate thumbnail exists, matching the Protocol V1 rule that thumbnails are optional and may be derived from photo.jpg.

### Ownership

- RLVTransferRouter owns protocol routing, authentication, pagination, and range decisions and is host-testable without a socket.
- RLVTransferService owns the listening socket, Bonjour publication, request parsing, and streaming.
- RLVAssetStore remains the only authority for discovering committed assets.
- RLVTransferViewController owns only the start/stop UI.

## Delivery standard

The feature is repository-complete when all checks below pass:

1. Both camera targets contain the same shared transfer sources and the project can be inspected by xcodebuild -list.
2. The host-side router integration test verifies health, failed and successful pairing, bearer authorization, device information, pagination, manifest/photo access, normal and suffix ranges, 404, and 416.
3. Existing Manifest, parser, and asset-store checks remain green.
4. plutil -lint and git diff --check pass.
5. Both targets compile with the current SDK using the existing host-compatible deployment and architecture overrides.

The feature is device-accepted only after recording all of the following on one iOS 6 Legacy device and one iOS 8 Classic device:

1. A modern phone discovers _retrolive._tcp., pairs using the displayed code, and lists every committed asset in the same order as the local library.
2. A complete photo download and, when present, a motion download match Manifest byte lengths and SHA-256 values.
3. At least three interrupted downloads resume with Range and produce byte-identical files.
4. Invalid codes, expired or replaced tokens, unknown UUIDs, malformed paths, and unsatisfiable ranges do not expose data and return the documented status.
5. Twenty assets can be downloaded while the camera preview remains usable; five new captures made while sharing appear in a subsequent asset-list request.
6. Starting and stopping sharing ten times does not crash, leak the listening port, or leave an old token usable.
7. Foreground-only behavior, Wi-Fi loss/recovery, free-space reporting, device/system versions, app version, IP address, and Bonjour name are recorded in the test log.

Current-host checks are not substitutes for the archived iOS 6 toolchain, real-device networking, Bonjour discovery, or capture/download concurrency acceptance.
