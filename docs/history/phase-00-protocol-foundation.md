---
title: Phase 0 — Protocol Foundation
status: historical
type: history
---

# Phase 0 — Protocol Foundation

> Historical phase summary. See the [documentation index](../README.md) for
> current contracts and acceptance status.

## Goal

Define a versioned, implementation-neutral cross-device contract and compilable
application foundations before camera capture, transfer, or Photos import.

## Planned scope

- A normative Manifest schema and read-only HTTP API description.
- Language-neutral fixtures consumed by legacy and modern parsers.
- Foundation-only Objective-C parsing for the legacy target.
- Swift parsing and a modern importer test target.
- Compilable camera and importer skeletons without product workflows.

Camera capture, persistent asset transactions, motion recording, network
serving, download, Live Photo assembly, and PhotoKit were explicitly deferred.

## Delivered boundary

- Manifest V1 JSON Schema for asset identity, capture metadata, media resources,
  hashes, timing, and device information.
- OpenAPI contract for the future camera/importer API.
- Valid, invalid, and unsupported-version fixture coverage.
- Objective-C and Swift model/parser foundations.
- `RetroLiveCamera` and `RetroLiveImporter` project skeletons.

The original delivery was recorded in `ab6b7d9 feature: first commit`.

## Important decisions

- The machine-readable schema and OpenAPI files are normative; prose and
  fixtures explain or verify them.
- V1 parsers reject missing or malformed required data and report unsupported
  versions rather than guessing.
- Media bytes remain untrusted until their declared length and SHA-256 are
  verified.
- Product UI must not expose internal Phase labels.

## Validation at completion

Repository checks established that the app foundations compiled and that shared
fixtures exercised both parser families. Later hardening aligned strict
boundaries across schema, Python, Objective-C, and Swift: zero-length resources,
invalid still-time ranges, boolean-as-number values, inconsistent timestamps,
unsafe filenames, and unsupported versions are rejected consistently.

The OpenAPI asset summary was also aligned with Manifest V1 so thumbnails are
optional rather than falsely required.

## Remaining acceptance

- A current-SDK compile does not establish compatibility with the archived iOS
  6 toolchain or a physical legacy device.
- Protocol parser success does not establish camera, networking, PhotoKit, or
  Live Photo runtime behavior.

## Related current documentation

- [Protocol V1](../reference/protocol-v1.md)
- [`manifest.schema.json`](../../protocol/manifest.schema.json)
- [`api.openapi.yaml`](../../protocol/api.openapi.yaml)
- [Verification Guide](../reference/verification-guide.md)
