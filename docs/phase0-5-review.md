# Phase 0–5 Implementation Review

Review date: 2026-08-08

## Outcome

The review closed the correctness and safety gaps that could produce an invalid
Manifest, expose a wrong resource, corrupt a resumed download, delete a path
outside RetroLive storage, or duplicate a PhotoKit import. Current-SDK automated
checks pass; archived-toolchain and physical-device acceptance remain separate
release gates.

## Findings resolved

| Phase | Finding | Resolution |
| --- | --- | --- |
| 0 | Zero-length resources, still time equal to motion duration, and inconsistent ISO/unix timestamps could pass different parsers. | Schema, Python, Objective-C, and Swift validators now share strict boundaries; fixtures use matching timestamps. |
| 1 | A forged asset path could reach recursive deletion; resource sizes were not required to be positive. | Store operations validate canonical UUIDs and exact managed directories before load/delete/commit. |
| 2 | Trimmed motion could leave the still frame outside the output duration. | Capture degrades safely to photo-only instead of committing an unusable motion asset. |
| 3 | The API advertised a thumbnail that did not exist, accepted malformed numeric inputs, and could send success headers before proving the media file was readable. | Optional resources are truthful, pagination/range/body lengths are strict and bounded, and streaming holds an opened regular-file descriptor before headers are sent. |
| 4 | Pagination loops, unsafe cache identifiers, corrupt-cache deletion, and incomplete `Content-Range` checks could hide server or disk faults. | Client validates identifiers/pages; corrupt cache is quarantined; resume validates exact range and total length before commit. |
| 5 | Rapid taps and crash windows could duplicate imports; assembly replacement and output validation were incomplete. | Per-asset in-flight guard, durable submission journal, uncertain recovery state, injectable PhotoKit boundary, attempt staging/recovery, safe replacement, and reopened-media validation are implemented. |

## Verification standard

- Protocol fixtures must pass or fail for the documented reason in both host
  validators.
- Legacy host tests cover transactions, recovery, path deletion boundaries,
  pairing/authentication, pagination, optional resources, ranges, and errors.
- The modern test bundle must report discovered test counts from the xcresult,
  not merely a successful `xcodebuild` process.
- Current-SDK legacy builds are source-compatibility checks only. They do not
  replace an archived Xcode build for the iOS 6 deployment target.

## Remaining release gates

1. Build both legacy targets using the pinned archived Xcode toolchain and run
   capture/share flows on the supported iOS 6 and iOS 8 devices.
2. Run the Phase 2 capture matrix for orientation, audio, trimming, interruption,
   low storage, and at least 20 repeated captures.
3. Exercise Bonjour, pairing lockout, token replacement, Range resume, Wi-Fi
   loss, and concurrent client pressure on physical devices.
4. Add deterministic synthetic JPEG/MOV fixtures to verify real assembly output,
   plus mock PhotoKit tests for permission, resource selection, failure, and
   uncertain completion.
5. Confirm normal photo and Live Photo behavior in Photos after relaunch and
   interrupted submission. Plain HTTP remains limited to a trusted local network;
   transport encryption is outside the current protocol scope.

These gates are intentionally not represented as completed by simulator or host
tests.
