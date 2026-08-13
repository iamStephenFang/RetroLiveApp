---
title: Phase 6 — Batch Import, Storage, and Metadata Fidelity
status: implemented-pending-device-validation
type: history
---

# Phase 6 — Batch Import, Storage, and Metadata Fidelity

> Implemented delivery scope with physical-device acceptance pending. Current
> behavior and acceptance remain defined by the [Modern Import Workflow](../specifications/modern-import-workflow.md).

## Goal

Turn the existing one-asset import path into a durable, user-controlled batch
workflow, prevent avoidable storage failures, and preserve the capture time and
source metadata when the generated photo or Live Photo is added to Photos.

Phase 6 builds on the existing read-only Protocol V1 endpoints, resumable
downloads, immutable verified cache, separate Assembly workspace, and durable
import journal. It does not require a server-side batch endpoint or a Protocol
V2 change.

## Current boundary

The importer currently presents one import action per asset and starts one
independent task for that asset. It has per-asset progress and duplicate
protection, but it does not provide multi-selection, a persisted ordered queue,
queue-level controls, or automatic recovery of pending queue items after an app
relaunch.

The camera advertises `capabilities.batchExport` as `false`. Phase 6 batch import
does not change that value: the modern importer continues to use the existing
manifest and resource endpoints and serializes those individual operations on
the client.

## Delivered scope

### P6.1 Multi-selection and queue creation

- Add a selection mode to the modern asset list with select, deselect, select
  all visible, and clear selection actions.
- Create one ordered queue from the selected assets through a single explicit
  import action.
- Classify every selected asset before enqueueing:
  - skip an asset with a confirmed `imported` record;
  - keep `needsConfirmation` out of automatic execution and require an explicit
    user decision;
  - reuse a freshly revalidated immutable cache entry;
  - enqueue available or explicitly retryable assets.
- Report how many items will run, be skipped, or require confirmation before the
  queue starts.

### P6.2 Durable serial import queue

- Process one asset at a time by default. The old camera must not receive
  concurrent large resource downloads from one importer queue.
- Persist the queue and each item state atomically before starting work so an app
  relaunch can reconstruct pending work without relying on view state.
- Keep the existing per-asset stages visible: queued, downloading with progress,
  verifying, cached, assembling, awaiting Photos authorization, importing,
  imported, retryable failure, cancelled, and `needsConfirmation`.
- Resume the first safe pending item after relaunch. Revalidate local cached or
  assembled resources before reuse.
- Never automatically retry an interrupted or uncertain PhotoKit submission.
  Such an item becomes `needsConfirmation` even when later queue items can
  continue.
- A known download, verification, assembly, permission, or PhotoKit failure is
  recorded against only that item. The queue policy may continue with later
  items while retaining a clear retry action for the failed item.

### P6.3 Queue controls and lifecycle

- Allow cancellation of queued items that have not started.
- Cancellation of an active item is stage-aware: stop cancellable network or
  assembly work, clean only that attempt's temporary files, and never infer that
  a PhotoKit submission was cancelled after its result became uncertain.
- Retry only failures known not to have created a Photos asset.
- Provide queue-level pause and resume without losing the persisted order.
- Disconnecting from the camera pauses items that still need network data but
  does not invalidate verified local cache entries or stop a safe local-only
  assembly/import step.
- Queue recovery is an app-relaunch guarantee, not a promise of continuous
  background networking. Background `URLSession` scheduling remains outside
  this phase.

### P6.4 Storage estimation and preflight

- Before starting a queue, calculate the declared source bytes from the selected
  manifests and estimate peak modern-device usage for download staging, verified
  cache, generated JPEG/MOV output, and attempt-scoped temporary files.
- Base the estimate on items that are not already safely cached or assembled;
  do not double-count reusable committed resources.
- Compare the conservative peak estimate with available capacity and warn before
  work starts when the safety margin is insufficient.
- Recheck available capacity before each download and assembly because free
  space can change while a long queue is running.
- A failed preflight must not delete data automatically. It presents storage
  requirements and valid cleanup choices.

### P6.5 Cache usage and safe cleanup

- Show separate byte totals for verified downloads, committed Assembly output,
  and abandoned or retryable temporary data.
- Allow cleanup of:
  - verified download cache entries that are not in use by an active queue item;
  - committed Assembly output that can be regenerated from a valid cached asset;
  - abandoned download and Assembly temporary attempts.
- Resolve cleanup targets through the owning stores and canonical asset IDs;
  never accept an arbitrary filesystem path from the UI.
- Coordinate cleanup with the queue so it cannot remove a resource currently
  being validated, assembled, or submitted to PhotoKit.
- Cleanup never changes camera-side originals, performs a remote delete, edits a
  verified source file in place, or rewrites import history.
- If cleanup removes a local prerequisite for a pending item, the item returns to
  the earliest safe reproducible stage rather than being marked imported or
  failed.

### P6.6 Capture time and metadata fidelity

- Treat the Manifest `createdAt` value as the canonical capture time after strict
  parsing and pass it to the Photos creation request for both normal photos and
  Live Photos.
- Verify the expected timezone/absolute-date mapping and reject an invalid date
  rather than silently replacing it with import time.
- Preserve JPEG pixel dimensions, EXIF orientation, color profile, and existing
  EXIF/TIFF/GPS/Maker metadata unless the documented ImageIO transformation
  requires a specific change.
- Preserve MOV video/audio tracks, preferred transform, duration, and timing in
  addition to the Live Photo content identifier and still-image-time metadata.
- Treat Manifest camera position, flash mode, mirrored state, aspect ratio, and
  orientation as validation and diagnostic facts. Do not invent unsupported
  PhotoKit fields or overwrite standard source metadata merely to duplicate
  Manifest values.
- Reopen generated resources and compare required metadata with the source and
  Manifest before PhotoKit submission.

## Technical boundaries

- Introduce a queue coordinator as the single owner of ordered execution,
  queue-item transitions, cancellation, and relaunch recovery. SwiftUI displays
  state but does not own the transaction.
- Extend the durable journal or add a separate atomically written queue store.
  Confirmed import history remains authoritative for duplicate prevention.
- Keep `DownloadStore`, `LivePhotoAssembler`, and the PhotoKit adapter responsible
  for their existing filesystem and framework boundaries.
- Add capture date to the injectable PhotoKit request boundary so deterministic
  tests can assert it without writing to the user's Photos library.
- Keep Protocol V1 read-only. Phase 6 does not enable remote deletion, upload,
  cloud transfer, or server-side batch export.

## Repository delivery standard

Phase 6 is repository-complete only when all of the following are true:

1. Multi-selection creates a deterministic queue and accurately reports skipped,
   runnable, and confirmation-required items.
2. The default executor performs at most one asset download/assembly/import
   pipeline at a time.
3. Queue order and safe item states survive store re-creation and app relaunch.
4. Confirmed imports are never resubmitted; `needsConfirmation` is never retried
   automatically.
5. Cancelling or retrying one item cannot corrupt another item's state or remove
   its committed cache.
6. Storage estimates include peak temporary and committed requirements, and
   preflight failure leaves all existing data unchanged.
7. Cleanup removes only explicitly selected local cache/Assembly targets and is
   excluded while those targets are in use.
8. Normal-photo and Live Photo requests use the canonical capture date, and
   generated resource metadata passes source/Manifest comparison tests.
9. Tests prove camera originals and verified cached inputs retain the same
   filenames, byte lengths, and SHA-256 hashes across success, failure,
   cancellation, cleanup, and retry.
10. User-visible queue, storage, metadata, error, and recovery text is localized
    in English, Simplified Chinese, and Traditional Chinese.

## Automated verification matrix

| Area | Required cases | Passing evidence |
| --- | --- | --- |
| Queue classification | available, cached, imported, retryable failure, `needsConfirmation`, duplicate selection | Exact queue and skip/confirmation summaries |
| Serial execution | multiple photo and motion assets, slow download, slow assembly | Instrumented maximum active pipeline count equals one |
| Relaunch recovery | queued, downloading, verifying, assembling, submitting, paused | Safe restored state and no duplicate PhotoKit request |
| Cancellation and retry | queued cancellation, active download/assembly cancellation, known failure, uncertain submission | Attempt cleanup and valid next action per state |
| Storage preflight | uncached, partially cached, assembled, insufficient capacity, capacity change during queue | Conservative peak calculation and non-destructive failure |
| Cleanup | unused cache, in-use cache, committed assembly, abandoned attempts, corrupt metadata | Only canonical eligible targets removed |
| Capture date | valid offsets, UTC boundary, invalid date, photo-only, Live Photo | Mock PhotoKit request receives the expected absolute date |
| JPEG metadata | EXIF, TIFF, GPS, Maker data, orientation, color profile | Reopened output comparison and unchanged input hash |
| MOV metadata | audio/video tracks, transform, duration, timed metadata | Reopened AVAsset assertions and unchanged input hash |

## Physical-device acceptance

1. Select and import at least 30 mixed photo and motion assets from each intended
   legacy-camera family. The importer executes serially and produces one Photos
   asset per confirmed source asset.
2. Relaunch the importer with queued, downloaded, assembled, failed, and
   confirmation-required items. It restores accurate states and performs no
   duplicate PhotoKit submission.
3. Disconnect and reconnect the camera during a queue. Network-dependent items
   pause or fail clearly while local-only safe work and committed caches remain
   valid.
4. Cancel pending items and retry known failures. No cancelled item starts later,
   and no uncertain item retries without an explicit decision.
5. Fill storage below the estimated requirement, verify the queue is stopped
   non-destructively, clean selected local data, and successfully continue after
   capacity is available.
6. Compare reported cache/Assembly usage with the application container and
   confirm cleanup never changes any source asset on the camera.
7. For portrait, landscape, front/rear, flash modes, mirrored capture, and every
   supported aspect ratio, compare the imported Photos asset with the Manifest
   and source resources.
8. Verify the Photos capture date matches Manifest `createdAt` across timezone and
   day-boundary cases rather than the time the import was performed.
9. Verify JPEG orientation, color, and relevant EXIF metadata, plus Live Photo
   motion orientation, audio, duration, and still point after device relaunch.

## Explicitly excluded

- Server-side batch archive or a `batchExport: true` Protocol V1 capability
- Concurrent large downloads from one legacy camera
- Guaranteed background transfer while the importer is suspended or terminated
- Remote deletion or automatic deletion of camera originals after import
- Upload, internet transfer, cloud sync, albums, editing, or sharing extensions
- Protocol V2 or encrypted transport changes

## Definition of done

Phase 6 is complete only when the repository delivery standard passes and the
physical-device acceptance record covers both intended legacy-camera families
and a modern iPhone. A queue UI prototype, simulator-only run, or successful
single-item import is not sufficient evidence of Phase 6 completion.
