# Contributing to RetroLive

Focused bug reports and pull requests are welcome. Before making a substantial
change, open an issue so the intended behavior, compatibility boundary, and
acceptance evidence can be agreed.

## Project boundaries

- Treat `protocol/manifest.schema.json` as the normative Manifest contract.
  Protocol changes must update the schema, OpenAPI description, examples,
  fixture catalog, Objective-C and Swift parsers, and relevant tests together.
- Preserve the iOS 6 Legacy and iOS 7/8 Classic deployment targets. Shared
  camera changes must account for both targets and use APIs available to their
  intended SDKs.
- Keep original camera assets and verified downloads immutable. Perform Live
  Photo assembly in a separate working directory.
- Keep LAN routes read-only and expose only committed assets. Never log or
  commit pairing codes, bearer tokens, personal media, device identifiers,
  signing files, provisioning profiles, or private filesystem paths.
- Add user-visible text to the English, Simplified Chinese, and Traditional
  Chinese resources for every affected target.
- Add or update a specification before implementing a user-visible feature or
  protocol behavior change.

## Pull requests

Keep each pull request scoped to one concern. Describe the motivation, affected
targets, compatibility impact, tests run, and remaining device acceptance. Do
not include unrelated formatting or generated Xcode user data.

Run the checks relevant to the change as documented in the
[verification guide](docs/reference/verification-guide.md). Every pull request
must also pass:

```sh
find legacy-camera/RetroLiveCamera modern-importer/RetroLiveImporter \
  -name '*.strings' -print0 | xargs -0 plutil -lint
find legacy-camera/RetroLiveCamera modern-importer/RetroLiveImporter \
  -name 'PrivacyInfo.xcprivacy' -print0 | xargs -0 plutil -lint
git diff --check
```

Record evidence honestly: repository checks, host runners, current-SDK builds,
simulator tests, archived-toolchain builds, and physical-device acceptance are
different levels. Unrun iOS 6/iOS 8 hardware, camera, Bonjour, Wi-Fi, PhotoKit,
or Live Photo cases must remain listed as not run.

## Contribution rights

Only submit material that you created or have the right to contribute. Retain
required third-party notices and identify generated or externally sourced visual
assets in the pull request. Do not submit Apple system-provided images as new
project-owned artwork.

By submitting a contribution for inclusion, you agree to license it under the
project's MIT License unless a separate written agreement says otherwise. The
MIT License does not override the terms governing third-party material; retain
the notices and exclusions documented in `THIRD_PARTY_NOTICES.md`.
