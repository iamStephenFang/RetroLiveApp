---
title: Architecture
status: current
type: reference
---

# Architecture

RetroLive consists of two legacy camera targets and one modern importer. The
camera targets share Objective-C capture, storage, library, Manifest, and
transfer code. The Swift importer communicates only through the versioned
protocol and does not share legacy implementation code.

## System overview

```text
Legacy UI (iOS 6) ----\
                       -> RLVCaptureController -> RLVAssetStore
Classic UI (iOS 8) ---/                         -> committed camera assets
                                                           |
                                                  RLVTransferService
                                                           |
                                                read-only HTTP + Bonjour
                                                           |
                                                CameraAPIClient
                                                           |
                                                  DownloadStore
                                                           |
                                             verified immutable cache
                                                           |
                                  LivePhotoAssembler -> ImportCoordinator
                                                           |
                                                        PhotoKit
```

## Component ownership

| Component | Owns | Must not own |
| --- | --- | --- |
| Legacy and Classic UI | Layout, gestures, navigation, and user-visible state | AVFoundation device configuration or asset paths |
| `RLVCaptureController` | Capture session, inputs/outputs, still and rolling-motion capture | Permanent asset-directory commits |
| `RLVCameraOrientationCoordinator` | Preview, capture, Manifest, movie, and control orientation mapping | Media storage |
| `RLVAssetStore` | Camera-side paths, validation, atomic commit, recovery, and committed-asset discovery | Camera session or HTTP request parsing |
| `RLVManifest` and parsers | Cross-device metadata contract | Media-byte trust without length/hash verification |
| `RLVTransferRouter` | Authorization, pagination, UUID validation, optional resources, and byte ranges | Socket lifecycle or direct unvalidated path construction |
| `RLVTransferService` | Listening socket, Bonjour, request parsing, and streaming | Asset discovery rules |
| `CameraAPIClient` | API requests, responses, authorization, and pagination | Download-cache commits |
| `DownloadStore` | Resumable staging, length/hash verification, and immutable cache commits | Assembly output or Photos writes |
| `LivePhotoAssembler` | Generated paired resources in a separate assembly workspace | Mutation of verified downloads or PhotoKit submission state |
| `ImportCoordinator` | Import state transitions and duplicate protection | Media transformation details |
| `PhotoLibraryImporter` | PhotoKit authorization and creation requests | Cache or assembly ownership |

## Data boundaries

### Camera asset

A shutter event receives its permanent identifier and capture metadata before
asynchronous media completion. `RLVAssetStore` validates staged resources and
moves a complete directory into committed storage. Motion failure retains the
independently captured still as the supported photo-only representation.

See [Asset Storage](asset-storage.md) for the filesystem contract and
[Capture and Storage](../specifications/capture-and-storage.md) for behavior and
acceptance criteria.

### Network transfer

Only committed assets are visible through the read-only API. The router resolves
asset identifiers through `RLVAssetStore`; neither request paths nor socket code
construct arbitrary filesystem locations.

See the [LAN Transfer specification](../specifications/lan-transfer.md) and the
normative [`api.openapi.yaml`](../../protocol/api.openapi.yaml).

### Modern import

Downloads are staged and verified before entering the immutable cache. Assembly
uses a separate workspace, and PhotoKit receives only validated generated output.
No download, conversion, retry, or cleanup operation may modify camera-side or
cached source media in place.

See [Live Photo Assembly](live-photo-assembly.md) for the paired-media format
boundary and [Modern Import Workflow](../specifications/modern-import-workflow.md)
for behavior and recovery rules.

## Compatibility boundaries

- Shared camera code must remain compatible with the intended iOS 6-era SDK and
  Objective-C/ARC implementation model.
- Protocol files under `protocol/` are the cross-device boundary; legacy and
  modern implementations evolve independently behind it.
- A current-SDK compile is source-integration evidence, not an archived-toolchain
  build or physical-device acceptance result.
- Historical delivery sequencing belongs in [Phase History](../history/README.md),
  not in this current component map.
