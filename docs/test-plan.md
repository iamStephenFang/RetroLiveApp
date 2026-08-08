# Phase 2 Test Plan

## Automated repository checks

- Validate motion, photo-only, malformed-hash/date/type, and unsupported-version fixtures with `tools/validate-manifest/validate.py`.
- Parse both valid asset lifecycles with the Foundation-only Objective-C runner.
- Type-check the modern Swift Manifest model/parser.
- Run the Objective-C asset-store integration runner against a temporary Documents root. It commits generated photo/motion payloads, validates both hashes and media metadata, reloads the same UUID, and verifies conservative Temporary recovery.
- Run the host-side transfer-router integration test for pairing, bearer authorization, pagination, immutable resource routing, byte ranges, and protocol errors.
- Inspect both camera targets with `xcodebuild -list`.
- Compile both target source sets with the current SDK using host-compatible deployment/architecture overrides. This is not an iOS 6 binary acceptance build.
- Run `plutil -lint` and `git diff --check`.

## Additional transaction checks on an iOS test host

1. Inject a temporary Documents URL through `initWithDocumentsURL:`.
2. Commit motion and photo-only assets; assert their required files exist and the photo-only asset has no fabricated MOV.
3. Verify the Manifest UUID, byte length, SHA-256, dimensions, timestamp, camera, and orientation.
4. Place partial directories under `Temporary`, recreate the store, and assert they are removed.
5. Place malformed/photo-missing directories under `Assets` and assert `loadAssets:` does not expose them.
6. Capture five assets, terminate the app, relaunch, and confirm identifiers and order are unchanged.
7. Verify successful captures contain `motion.mov`, and force a motion failure to verify the JPEG is retained as `motion: null` with zero timings.

## Real-device capture acceptance

- Legacy: iPhone 4S or iPhone 5 running iOS 6.x, built with the archived toolchain.
- Classic: iPhone 5s, iPhone 6, or iPhone 6 Plus running an iOS 8-era system.
- Capture 20 photos continuously without crash, freeze, or session loss.
- Verify Portrait, Landscape Left, and Landscape Right preview/capture/Manifest agreement.
- Exercise rear/front switching, supported flash modes, focus, background/foreground, low storage, forced termination during staging, and relaunch recovery.
- Confirm no capture is copied into the system Camera Roll.
- For warmed captures, verify approximately 1.5 seconds of pre-roll and post-roll, still-time error no greater than 200 ms, correct movie orientation, and audio when permission is granted.
- Repeat near startup and a rolling-segment boundary and verify any shortened duration is reported accurately rather than padded or fabricated.

## UI fidelity acceptance

Capture one native Camera reference and one RetroLive screenshot for each exact device/system pair. Compare at 1:1 and with a 50% opacity overlay. Record preview/top/bottom frames, shutter and thumbnail centers/sizes, flash/switch frames, colors, typography, highlight timing, shutter feedback, and control rotation. The current programmatic chrome is a calibrated first pass; it is not pixel-accepted until these device comparisons are completed.

## Phase 3 device transfer acceptance

Use the Legacy and Classic device pairs, checksums, interrupted-download cases, capture/download concurrency run, and repeated server lifecycle checks defined in phase3-delivery.md. Host routing tests do not validate Bonjour, the listening socket on iOS, Wi-Fi behavior, or foreground suspension.
