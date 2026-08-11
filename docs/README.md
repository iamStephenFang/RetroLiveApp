# Documentation Guide

This index separates current contracts and acceptance criteria from historical
phase records. A phase document describes the decision or audit at that point in
time; it is not automatically the current source of truth.

## Sources of truth

| Area | Document | Role |
| --- | --- | --- |
| Manifest | [`../protocol/manifest.schema.json`](../protocol/manifest.schema.json) | Normative machine-readable Manifest V1 contract |
| HTTP API | [`../protocol/api.openapi.yaml`](../protocol/api.openapi.yaml) | Normative camera/importer API contract |
| Protocol explanation | [`protocol.md`](protocol.md) | Human-readable protocol overview |
| Component ownership | [`architecture.md`](architecture.md) | Current runtime boundaries and data flow |
| Camera asset storage | [`asset-format.md`](asset-format.md) | Current on-device asset representation |
| Live Photo assembly | [`live-photo-format.md`](live-photo-format.md) | Current paired-resource rules |
| Repository and device acceptance | [`test-plan.md`](test-plan.md) | Current verification matrix |

When prose conflicts with a machine-readable contract, the JSON Schema or
OpenAPI file wins. When a historical phase record conflicts with current code or
the test plan, update the current design document and keep the historical record
as context.

## Active feature specifications

- [`camera-ui-measurements.md`](camera-ui-measurements.md) records provisional
  camera layout metrics and the physical-device comparison procedure.
- [`specs/tap-to-focus.md`](specs/tap-to-focus.md) defines the proposed shared
  Tap to Focus behavior for Legacy and Classic.
- [`phase3-delivery.md`](phase3-delivery.md) remains the detailed transfer
  contract and physical-device acceptance list.
- [`phase4-5-delivery.md`](phase4-5-delivery.md) remains the detailed download,
  assembly, PhotoKit, and recovery contract.

## Build notes

- [`ios6-build-environment.md`](ios6-build-environment.md) records the archived
  Xcode/iOS SDK boundary. A current-SDK compile check is not an old-device build.

## Historical phase records

These files explain earlier scope and decisions. They should not be used alone
to determine current completion status.

- [`phase1-audit.md`](phase1-audit.md): state found before Phase 1 and its design decisions.
- [`phase2-plan.md`](phase2-plan.md): original motion-capture delivery plan.
- [`phase0-2-completion-audit.md`](phase0-2-completion-audit.md): Phase 0-2 repository audit snapshot.
- [`phase0-5-review.md`](phase0-5-review.md): dated cross-phase correctness review.

## Maintenance rule

New feature work should add or update one active specification and the central
test plan. Avoid copying the same acceptance criteria into a new phase file;
link to the source-of-truth document instead. Keep delivery snapshots only when
their historical decisions remain useful.
