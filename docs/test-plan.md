# Test Plan

## Phase 0 automated checks

- The example and `valid-v1` fixture pass the dependency-free protocol validator.
- The malformed hash fixture is rejected as invalid.
- The unsupported schema fixture reports an unsupported-version error rather than a generic decoding failure.
- The modern parser loads the shared valid fixture.
- The modern parser ignores an unknown top-level field.
- The modern parser classifies malformed hashes and unsupported versions separately.
- The Objective-C parser is exercised on a modern macOS host using the Foundation-only runner under `tools/test-legacy-parser`; final compatibility remains an archived-toolchain/device check.

## Commands

See the root README for validator and modern XCTest commands. To inspect project configuration without signing:

```sh
xcodebuild -list -project legacy-camera/RetroLiveCamera.xcodeproj
xcodebuild -list -project modern-importer/RetroLiveImporter.xcodeproj
```

## Deferred acceptance

Phase 0 does not validate camera stability, media integrity, Range downloads, Bonjour, Live Photo assembly, or PhotoKit behavior. Those checks enter the plan with their implementation phases. iOS 6 device acceptance remains blocked until the archived build environment and hardware are available.
