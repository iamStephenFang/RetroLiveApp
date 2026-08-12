---
title: RetroLive Documentation
status: current
type: index
---

# RetroLive Documentation

This directory separates current references and feature specifications from
historical delivery records. Start with the current documents below; use
historical records only when earlier decisions or audit context are relevant.

## Sources of truth

Machine-readable contracts take precedence over explanatory prose.

| Area | Source of truth | Supporting document |
| --- | --- | --- |
| Manifest V1 | [`../protocol/manifest.schema.json`](../protocol/manifest.schema.json) | [`reference/protocol-v1.md`](reference/protocol-v1.md) |
| HTTP API | [`../protocol/api.openapi.yaml`](../protocol/api.openapi.yaml) | [`specifications/lan-transfer.md`](specifications/lan-transfer.md) |
| Component ownership | Current implementation | [`reference/architecture.md`](reference/architecture.md) |
| Asset storage | Current implementation and Manifest V1 | [`reference/asset-storage.md`](reference/asset-storage.md) |
| Live Photo paired-media output | Current implementation and tests | [`reference/live-photo-assembly.md`](reference/live-photo-assembly.md) |
| Verification routing | Test evidence | [`reference/verification-guide.md`](reference/verification-guide.md) |

If a historical record conflicts with a current contract, implementation,
feature specification, or verification evidence, follow the current source and
update its supporting document.

## Directory map

### `reference/`

Current system facts and verification boundaries:

- [`architecture.md`](reference/architecture.md) — components, ownership, and data flow.
- [`protocol-v1.md`](reference/protocol-v1.md) — human-readable Manifest V1 rules.
- [`asset-storage.md`](reference/asset-storage.md) — immutable camera-side asset layout.
- [`live-photo-assembly.md`](reference/live-photo-assembly.md) — paired-media output contract.
- [`verification-guide.md`](reference/verification-guide.md) — evidence levels and verification index.

### `guides/`

Task-oriented operational guidance:

- [`ios-6-build-environment.md`](guides/ios-6-build-environment.md) — archived toolchain and device-build requirements.
- [`remote-legacy-build.md`](guides/remote-legacy-build.md) — one-way source synchronization, remote Xcode builds, and signing.

### `specifications/`

Feature behavior, implementation boundaries, and acceptance criteria:

- [`camera-ui-measurements.md`](specifications/camera-ui-measurements.md)
- [`capture-and-storage.md`](specifications/capture-and-storage.md)
- [`tap-to-focus.md`](specifications/tap-to-focus.md)
- [`asset-preview-paging.md`](specifications/asset-preview-paging.md)
- [`lan-transfer.md`](specifications/lan-transfer.md)
- [`modern-import-workflow.md`](specifications/modern-import-workflow.md)

### `history/`

Historical scope, decisions, validation, and remaining acceptance by phase:

- [`history/README.md`](history/README.md) provides the complete Phase 0–5 map.
- `history/phase-00-*.md` through `history/phase-05-*.md` provide one consistent
  scope summary per phase.
- Earlier plan, audit, and review findings are consolidated into their owning
  phase; exact previous wording remains available through Git history.

## Document metadata

Every Markdown document begins with YAML front matter using these fields:

| Field | Meaning |
| --- | --- |
| `title` | Human-readable document name |
| `status` | `current`, `provisional`, `implemented-pending-device-validation`, or `historical` |
| `type` | `index`, `reference`, `guide`, `specification`, or `history` |
| `reviewed` | Review date for a dated snapshot; omit when no reliable date is recorded |

## Maintenance rules

1. Use lowercase kebab-case filenames and descriptive names rather than only a phase number.
2. Update an existing current reference or specification before creating a new document.
3. Keep one source for each acceptance criterion and link to it elsewhere.
4. Consolidate superseded plans and dated reviews into the owning Phase history;
   preserve their conclusions and rely on Git for exact earlier wording.
5. Distinguish repository checks, current-SDK builds, simulator tests, archived-toolchain builds, and physical-device acceptance.
