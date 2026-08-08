# Phase 4 and Phase 5 Delivery Plan

## Product boundary

Phase 4 turns the modern iOS application into a verified downloader for the Phase 3 read-only API. Phase 5 converts a verified photo-plus-motion download into new paired resources and imports them into Photos as one Live Photo. A photo-only fallback is imported as a normal photo.

The immutable files under Downloads/Assets are never edited. Phase 5 writes generated resources under Assembly/{assetId}, validates their identity and timing, and only then calls PhotoKit.

## Phase 4: Discover, pair, download, verify

### Technical design

- NetServiceBrowser discovers and resolves _retrolive._tcp. services on the local network.
- CameraAPIClient owns API paths, JSON decoding, bearer authorization, status-code mapping, and URLSession requests.
- Pairing uses the six-digit code displayed by the camera. The token remains in memory and is discarded when the device session is disconnected.
- DownloadStore owns Application Support/RetroLive/Downloads.
- Downloads first fetch and parse Manifest V1, then stream photo and optional motion resources into Temporary/{assetId}.
- Existing partial files use Range bytes=N-. A 206 response appends; a 200 response safely restarts that resource.
- File length and incremental SHA-256 must match the Manifest before the staging directory is atomically moved to Assets/{assetId}.
- A committed cache entry is reusable only after a fresh validation. Corrupted cache entries are rejected rather than exposed.
- Original and assembly directories remain separate.

### Repository delivery standard

1. Discovery, pairing, device information, pagination, manifest loading, and bearer request construction are represented by production code.
2. Download code supports complete responses and Range resume without loading the full movie into memory.
3. Manifest parsing, safe filenames, expected byte lengths, and SHA-256 are enforced before commit.
4. The SwiftUI flow displays discovery, pairing, asset list, busy/progress, retryable failure, cached, and imported states.
5. API and store boundaries accept injected URLSession and filesystem roots for deterministic tests.
6. The importer target and test bundle compile with the current iOS SDK; protocol and legacy-camera regression checks remain green.

### Device acceptance

1. Discover and resolve one iOS 6 Legacy and one iOS 8 Classic camera over Bonjour.
2. Reject an incorrect code, pair with the displayed code, and recover from expired/replaced tokens.
3. Paginate at least 120 assets without duplicates or missing identifiers.
4. Interrupt and resume at least three photo and three movie downloads; committed bytes and SHA-256 match the Manifest.
5. Relaunch during a partial download and resume without exposing the partial asset.
6. Lose and restore Wi-Fi, stop and restart camera sharing, and recover through a clear retry path.
7. Verify progress remains responsive and cache cleanup never modifies camera-side originals.

## Phase 5: Assemble and import

### Goal and input contract

Phase 5 starts only from a Phase 4 `CachedAsset` whose Manifest, byte lengths, and
SHA-256 values have just been validated. It produces either one normal photo or
one Live Photo in the system Photos library. It does not repair corrupt source
media, infer a missing still time, or fabricate motion for a photo-only asset.

The following preconditions are enforced before PhotoKit is called:

1. `assetId` is the canonical UUID from the validated Manifest and is also used
   as the Live Photo content identifier.
2. The cached JPEG exists and remains readable. For a motion asset, the cached
   MOV also exists, contains at least one video track, and has a positive duration.
3. `capture.stillImageTimeSeconds` is finite, non-negative, and strictly less
   than the actual MOV duration. The actual media duration is authoritative when
   it differs slightly from the Manifest duration.
4. A photo-only Manifest has no motion input or generated paired-video output.
5. Phase 5 has sufficient free space for a second JPEG and remuxed MOV. A storage
   failure is reported without deleting the verified Phase 4 cache.

### Current baseline and remaining gap

The implementation now covers the main correctness boundaries in the Phase 5
design:

- `LivePhotoAssembler` uses attempt-scoped staging, removes abandoned attempts,
  safely replaces committed output, and reopens generated JPEG/MOV resources to
  validate identifiers, tracks, dimensions, transforms, duration, and timed
  still-image metadata.
- `PhotoLibraryImporter` is behind an injectable protocol, requests add-only
  permission, and chooses paired or photo-only PhotoKit resources.
- `ImportHistoryStore` persists `submitting` and `imported` journal states. The
  view model uses a synchronous per-asset in-flight guard and restores uncertain
  submissions as `needsConfirmation` rather than automatically duplicating an
  import.
- Focused tests cover manifest boundaries, pagination loops, journal migration,
  relaunch recovery, and the download resume path.

The remaining delivery gap is evidence rather than known transactional logic:
synthetic-media assembly tests, mock PhotoKit coordinator tests, and the physical
device acceptance matrix below are still required before declaring Phase 5
production-complete.

Implementation is delivered in the following merge order so each slice has an
independent verification gate:

| Slice | Main code area | Concrete output | Merge gate |
| --- | --- | --- | --- |
| P5-A | `LivePhotoAssembler` | Attempt-scoped staging, safe replacement, startup cleanup | Filesystem recovery tests pass |
| P5-B | ImageIO/AVFoundation validators | Exact JPEG identifier and decoded properties; exact MOV identifier, timed sample, tracks, transform, duration | Synthetic media integration tests pass |
| P5-C | `PhotoLibraryWriting` adapter | Injectable authorization and one-request photo/paired-video creation | Mock resource/permission tests pass |
| P5-D | `ImportJournal` + `ImportCoordinator` | Durable state machine, in-flight guard, uncertain-result handling | Relaunch/concurrency/failure tests pass |
| P5-E | View model and SwiftUI | Stage-specific states and valid recovery actions | UI state tests plus manual simulator review pass |
| P5-F | Physical device | Photos and Live Photo acceptance record | All required device cases have attached evidence |

### Work breakdown

#### P5.1 Assembly workspace and lifecycle

- `LivePhotoAssembler` owns `Application Support/RetroLive/Assembly` and no
  other component writes generated paired resources there.
- Each attempt writes to `Temporary/{assetId}-{attemptId}`. It never edits or
  moves a file under `Downloads/Assets/{assetId}`.
- Generated files are fully closed and validated before the attempt directory is
  renamed to `Assets/{assetId}`. Replacement uses a filesystem-level replace or
  backup-and-restore sequence so an old valid assembly is not deleted before the
  new one can be committed.
- Startup recovery removes abandoned attempt directories. A committed assembly
  may be reused only after its identifiers, tracks, and timing metadata are
  validated again.
- Assembly failure removes only the current attempt. Downloaded originals and a
  previously committed valid assembly remain available for retry.

#### P5.2 Paired JPEG generation

- Copy the source image through ImageIO and preserve the original image type,
  dimensions, orientation, color profile, EXIF, and other metadata unless
  ImageIO must normalize the container.
- Add the shared identifier at Apple Maker dictionary key `17` without replacing
  unrelated Maker metadata.
- Reopen the generated image and verify that it decodes, retains the expected
  pixel dimensions and orientation, and contains the exact identifier.
- The source and generated JPEG hashes are recorded during tests to prove the
  source was not modified; byte equality between source and generated JPEG is
  not expected because metadata changes.

#### P5.3 Paired MOV generation

- Use `AVAssetReader` and `AVAssetWriter` with `outputSettings: nil` for source
  video and audio tracks. This remuxes compressed samples and avoids deliberate
  transcoding.
- Preserve every supported video and audio track, sample timing, preferred
  transform, and movie duration. Unsupported non-audio/video tracks are not
  copied and are documented rather than silently treated as required.
- Write `com.apple.quicktime.content.identifier` with the same identifier used
  in the JPEG.
- Add a timed `mdta/com.apple.quicktime.still-image-time` metadata sample at
  `capture.stillImageTimeSeconds`. Use a stable timescale and ensure the sample
  range remains inside the movie duration.
- Treat reader failure, writer failure, cancelled transfer, missing video,
  invalid timing, or failure to append any sample as a failed assembly. Cancel
  the other tracks and finish every continuation exactly once.
- Reopen the generated MOV and verify the exact content identifier, timed
  metadata identifier and timestamp, at least one playable video track, expected
  audio presence, duration tolerance, and preferred transform. Timestamp and
  duration tolerances are `max(1/600 second, one source video frame)`; the content
  identifier and transform require exact equality.

#### P5.4 PhotoKit import boundary

- Request `.addOnly` authorization immediately before the first import. Explain
  `.denied` and `.restricted` separately from media/assembly failures and provide
  a path to Settings after denial.
- For a motion asset, submit `.photo` and `.pairedVideo` on one
  `PHAssetCreationRequest`. For a photo-only asset, submit only `.photo`.
- Set `shouldMoveFile = false`; PhotoKit must not consume the assembly cache.
- Treat `performChanges` completion plus a non-empty placeholder local identifier
  as the success boundary. Do not report success when only assembly completed.
- Wrap PhotoKit behind an injectable protocol so unit tests can cover permission,
  resource selection, success, and failure without writing to the real library.

#### P5.5 Import journal and duplicate protection

PhotoKit and the local filesystem cannot participate in one atomic transaction.
With add-only permission the app also cannot scan Photos after a crash to discover
whether an interrupted submission succeeded. Phase 5 therefore uses a durable
journal instead of claiming impossible cross-system atomicity.

The per-asset states are:

```text
notImported -> assembling -> ready -> submitting -> imported
                    |          |           |
                    +----------+-----------+-> failed / needsConfirmation
```

- Persist `submitting` atomically before calling `performChanges` and persist
  `imported` only after PhotoKit returns success and a local identifier.
- An `imported` record contains `assetId`, import kind, Photos local identifier,
  assembly fingerprint/version, and import date. Repeated taps return this record
  and never call PhotoKit again.
- A stale `submitting` record becomes `needsConfirmation` after relaunch. The app
  must not retry it automatically because that could create a duplicate. The user
  may confirm that the asset exists or explicitly choose to import again.
- A known PhotoKit failure returns to a retryable state. Failure to persist the
  success record is surfaced as `needsConfirmation`, not as an ordinary retry.
- In-memory in-flight ownership is acquired synchronously before starting a Task,
  so rapid repeated taps cannot launch concurrent assembly/import operations for
  the same asset.
- Journal writes use atomic replacement. Corrupt journal data is retained for
  diagnostics and surfaced explicitly rather than overwritten with an empty file.

#### P5.6 UI, cancellation, and diagnostics

- Show distinct row states for assembling, awaiting Photos permission, importing,
  imported, retryable failure, and result-needs-confirmation. Phase 4 download
  progress remains separate from Phase 5 state.
- Error text identifies the failed stage and provides only valid actions: retry,
  open Settings, or confirm/re-import. It must not label an uncertain PhotoKit
  submission as failed.
- Disconnecting from the camera does not cancel an import that already owns a
  verified local cache. Navigating away may hide progress but must not start a
  second operation.
- Log `assetId`, stage, attempt identifier, duration, and stable error category.
  Never log pairing tokens, media bytes, or full private filesystem paths.

### Technical structure

```text
CachedAsset (verified, immutable)
        |
        v
LivePhotoAssembler ----> Assembly/Temporary/{assetId}-{attemptId}
        |                         |
        |                  validate generated pair
        |                         |
        +----------------> Assembly/Assets/{assetId}
                                  |
                         ImportCoordinator
                         /               \
                 ImportJournal       PhotoLibraryWriting
                    (durable)          (PhotoKit adapter)
                         \               /
                          imported / needsConfirmation
```

`ImportCoordinator` owns the state transition and duplicate guard. The assembler,
journal, clock/identifier generator, and PhotoKit adapter are injected. This keeps
AVFoundation/ImageIO integration tests separate from deterministic coordinator
tests and prevents SwiftUI from becoming the transaction owner.

### Repository delivery standard

Phase 5 is repository-complete only when all of the following are true:

1. **Source isolation:** no Phase 5 success, failure, cancellation, cleanup, or
   retry changes any byte or filename under `Downloads/Assets`.
2. **Transactional output:** abandoned staging is recoverable and committing a
   replacement cannot destroy the last valid assembly on a failed move.
3. **JPEG contract:** the generated JPEG decodes, preserves expected dimensions
   and orientation, and contains the exact shared content identifier.
4. **MOV contract:** the generated MOV contains the same identifier, a timed
   still-image metadata sample at the declared time within the defined tolerance,
   a playable video track, expected audio presence, duration, and transform.
5. **No deliberate re-encode:** compressed video/audio samples use pass-through
   reader/writer settings; an automated test compares track codec descriptions
   and representative sample sizes/timestamps before and after remuxing.
6. **Correct resource decision:** `Manifest.motion != nil` produces exactly
   `.photo + .pairedVideo`; `motion == nil` produces exactly `.photo` and no MOV.
7. **Explicit failures:** invalid timing, unreadable image, missing video track,
   reader/writer/metadata failure, insufficient space, permission denial,
   PhotoKit failure, journal corruption, and uncertain submission have distinct
   error categories and user-visible recovery paths.
8. **Duplicate protection:** confirmed imports and concurrent taps never submit
   twice. An interrupted/uncertain submission never retries automatically.
9. **Testability:** filesystem roots, PhotoKit adapter, journal, and attempt ID are
   injectable. Tests do not depend on the user's Photos library.
10. **Build quality:** the importer app and test bundle compile with warnings
    treated as errors for changed Phase 5 files; focused tests, `plutil -lint`,
    and `git diff --check` pass.

### Automated verification matrix

| Area | Required cases | Passing evidence |
| --- | --- | --- |
| JPEG assembly | metadata insertion, existing Maker metadata, orientation/color metadata, unreadable input | Reopened output assertions and unchanged source hash |
| MOV assembly | video-only, video+audio, rotated video, boundary still times, invalid/empty tracks, forced reader/writer failure | Reopened AVAsset track/metadata assertions and unchanged source hash |
| Commit/recovery | clean commit, valid replacement, failed replacement, abandoned staging, cancellation | Filesystem integration tests using a temporary root |
| Import decision | motion and photo-only manifests | Mock adapter receives exact resource types and URLs |
| Authorization | authorized, denied, restricted, later granted | Coordinator tests assert state and recovery action |
| Journal | first import, repeated tap, concurrent tap, corrupt file, write failure, stale `submitting` | Deterministic state-transition tests across store re-creation |
| PhotoKit result | success with identifier, failure, missing placeholder, interruption/unknown result | `imported`, retryable, or `needsConfirmation` asserted as appropriate |

Synthetic JPEG/MOV fixtures are generated or checked into the test bundle with
known dimensions, transform, codec, duration, audio presence, and still time.
Tests must inspect the timed metadata sample itself; merely finding a metadata
track is not sufficient.

### Physical-device acceptance

Run on at least one modern iPhone using source assets transferred from both the
iOS 6 Legacy target and the iOS 8 Classic target. Record device/OS/app build,
asset IDs, screenshots or screen recordings, and pass/fail notes.

1. Import ten motion assets covering portrait, both landscape orientations,
   front/rear camera, with-audio, and without-audio. Each appears as exactly one
   playable Live Photo in Photos.
2. Long-press playback has the correct still frame, direction, orientation, and
   audio. Compare the displayed still point with the Manifest; error is no more
   than 200 ms.
3. Import at least three `motion: null` assets. Each appears as a normal photo,
   has no Live Photo badge, and no paired video is generated or submitted.
4. Deny Photos access, retry, grant access in Settings, and finish the import.
   Verified downloads and committed assemblies remain reusable throughout.
5. Force-quit during assembly. Relaunch cleans staging, preserves originals, and
   completes a retry without duplicate output.
6. Force-quit immediately before and during PhotoKit submission. Relaunch shows
   `needsConfirmation` and does not automatically submit again.
7. Tap the import action repeatedly and concurrently for one asset. PhotoKit is
   invoked once. Reopening an asset with a confirmed history record also creates
   no duplicate.
8. Fill storage until assembly fails, then free space and retry. The cached source
   remains checksum-valid and no success history is written for the failed run.
9. Compare all source filenames, sizes, and SHA-256 values before and after the
   suite and confirm no source byte was modified.
10. Relaunch the app and verify imported, retryable, and needs-confirmation states
    are restored from durable data rather than inferred from the current UI.

### Phase 5 definition of done

Phase 5 is complete only when the repository delivery standard passes, the
physical-device acceptance sheet is attached to the release record, and every
failure or unperformed case is listed explicitly. Simulator compilation alone is
not delivery evidence for PhotoKit persistence or Live Photo playback.

## Explicitly deferred

- Remote deletion or upload to the legacy camera
- Internet or cloud transfer
- Encrypted transport beyond the existing trusted-LAN HTTP design
- Background URLSession scheduling
- Editing, sharing extensions, albums, or cloud sync of import history

Current-host compilation and unit tests do not replace Bonjour, real network interruption, Live Photo playback, Photos permission, or PhotoKit persistence checks on a physical modern iPhone.
