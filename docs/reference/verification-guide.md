---
title: Verification Guide
status: current
type: reference
---

# Verification Guide

This document is the central verification index. Feature-specific cases and
completion criteria live in their specifications; this guide defines evidence
levels, common repository gates, and where each verification matrix is owned.

## Evidence levels

| Level | What it establishes | What it does not establish |
| --- | --- | --- |
| Static repository check | File consistency, schema/catalog coverage, plist syntax, and clean diffs | Runtime behavior |
| Host integration runner | Foundation-only parser, storage, or routing behavior on the development Mac | UIKit, AVFoundation hardware, Bonjour, or old iOS behavior |
| Current-SDK build | Source and project integration against the installed SDK | Installability or behavior on iOS 6/iOS 8 hardware |
| Simulator XCTest | Discovered modern test cases and supported simulator runtime behavior | Real Wi-Fi, camera hardware, PhotoKit persistence, or period-device performance |
| Archived-toolchain build | Compilation and signing with the preserved historical environment | Complete physical-device interaction acceptance |
| Physical-device acceptance | Behavior on the recorded device, OS, build, network, and permission state | Other untested device/OS combinations |

Do not promote evidence from one level into a stronger level. In particular, a
successful `xcodebuild` process is not sufficient XCTest evidence unless the
result bundle reports the expected discovered test count.

## Common repository gates

Run the commands documented under [Run the checks](../../README.md#run-the-checks) for
the affected area. Every documentation or source change must also pass:

```sh
git diff --check
```

For affected bundles, run `plutil -lint`. When both camera schemes are built in
parallel, use separate `-derivedDataPath` values to avoid build-database locking.

## Verification ownership

| Area | Automated or host entry point | Detailed acceptance owner |
| --- | --- | --- |
| Manifest V1 and parser agreement | `python3 tools/test-manifest-fixtures/run.py` | [Protocol V1](protocol-v1.md) and shared fixture catalog |
| Camera asset transactions and capture | `tools/test-asset-store/main.m`; both camera source builds | [Capture and Storage](../specifications/capture-and-storage.md) |
| Tap to focus and exposure | Both camera source builds and focused seams | [Tap to Focus](../specifications/tap-to-focus.md) |
| Camera layout fidelity | Screenshot and overlay record | [Camera UI Measurements](../specifications/camera-ui-measurements.md) |
| Asset detail paging, zoom, and motion preview | Both camera source builds | [Asset Preview Paging](../specifications/asset-preview-paging.md) |
| Read-only LAN service | `tools/test-transfer-router/main.m` | [LAN Transfer](../specifications/lan-transfer.md) |
| Discovery, verified download, assembly, and Photos import | `modern-importer/RetroLiveImporterTests` | [Modern Import Workflow](../specifications/modern-import-workflow.md) |

## Recording results

For every acceptance run, record:

- commit or build identifier;
- command or manual procedure;
- host/device model, OS, Xcode/SDK, and relevant permission state;
- expected and discovered test counts where applicable;
- pass, fail, or not-run status per required case;
- logs, screenshots, result bundles, or checksums needed to reproduce the claim.

An unperformed physical-device case remains an open acceptance item even when
all repository, host, build, and simulator checks pass.
