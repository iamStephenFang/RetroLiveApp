# Asset Preview Paging Specification

- Status: Implemented; physical-device acceptance pending
- Targets: `RetroLiveCamera` (iOS 6) and `RetroLiveClassic` (iOS 7/8)
- Owner boundary: shared asset-detail UI only

## Outcome

Horizontal photo navigation follows the user's finger continuously and settles
to the previous or next asset with native paging behavior. It replaces the
current recognize-then-animate swipe transition without changing asset order,
sharing, metadata, deletion, playback-mode persistence, or close navigation.

## Compatibility decision

Use an iOS 6-compatible paging `UIScrollView` with three reusable image views:
previous, current, and next. Do not create one view controller or full-resolution
image per asset. Do not use APIs newer than the Legacy target's iOS 6 floor.

The scroll view owns horizontal interaction. The toolbar, metadata panel, and
Live badge remain fixed above it. Horizontal dragging pauses the current
player. A cancelled page turn resumes that same player; a committed page change
tears it down before preparing the newly settled asset.

## Interaction contract

1. The image position tracks `contentOffset` for the entire drag; no fixed
   `CATransition` is used for user-initiated paging.
2. A completed page changes `selectedIndex` by exactly one. A cancelled or
   insufficient drag returns to the current page.
3. At the first and last asset, dragging may show the normal short scroll-view
   resistance but must not settle on an empty page or change the selection.
4. Rapid swipes cannot skip assets, display a stale image, or attach playback to
   the wrong asset.
5. A single asset disables paging while all fixed controls remain usable.
6. A single tap on the settled preview toggles immersive full-screen display.
   Full screen hides the navigation bar, toolbar, Live badge, and metadata while
   expanding the preview into the released space. A second single tap restores
   the prior chrome and metadata visibility without restarting playback,
   changing zoom, or changing the selected asset.
7. Single tap waits for double tap and long press to fail. It must not steal a
   double-tap zoom or briefly toggle chrome when a long press is recognized.
8. A stationary long press on any motion asset starts playback; it never enters
   the generic interaction-pause path. This remains available when the saved
   mode is Still, where the press temporarily plays the motion and release
   returns to the still. Starting a horizontal drag stops playback first.

## Zoom contract

1. Every settled photo supports pinch-to-zoom from `1×` to at least `4×` and
   panning in both axes while enlarged. Zoom is part of the preview's required
   behavior, not an optional enhancement.
2. Double tapping the settled photo toggles between `1×` and a useful detail
   scale (provisionally `2×`), centered on the tapped point. Double tapping an
   already enlarged photo returns it to `1×`.
3. At `1×`, horizontal drags belong to the outer paging scroll view. Above
   `1×`, drags belong to the current photo so the user can inspect detail
   without accidentally changing assets. Pinching must not trigger paging.
4. Changing assets resets all three reusable pages to `1×`. Zoom state must not
   leak from one asset to another through page reuse.
5. The enlarged photo remains centered whenever its rendered width or height is
   smaller than the viewport. Panning must not reveal unintended blank margins
   beyond normal scroll-view elasticity.
6. Beginning a pinch or enlarged-photo pan may pause Live playback while the
   gesture is active, but releasing the gesture must resume the current asset's
   selected Live/Loop/Bounce behavior from the paused playback position, even
   when the photo remains enlarged. Zoom changes the viewed region; it must not
   restart or disable Live playback.

## Motion transition contract

- All player mutations and accepted asynchronous completions are serialized on
  the main thread. `playbackRequested` is the single permission to advance
  media; no periodic observer, end notification, seek callback, preroll
  callback, KVO callback, or reverse-playback callback may start playback when
  that permission is false.
- Every asynchronous playback operation captures the current player, item, and
  playback generation. It must become a no-op if paging, mode changes,
  foreground changes, interaction pauses, or teardown supersede it.
- Treat playback as one queued audio/video request. While the current
  `AVPlayerItem` status is `Unknown`, do not seek or start playback; wait for
  `ReadyToPlay`. If it becomes `Failed`, keep the still visible and cancel the
  request. A seek API with a completion handler must never be called before the
  item is ready.
- Audio must not be allowed to start through a stale or superseded request.
  After the ready-gated seek completes, preroll the player, then reveal video
  and start audio only when the layer has a displayable first frame and the
  player, item, asset, and playback generation still match. Swiping away,
  leaving the screen, or changing playback mode invalidates that generation
  before teardown.
- Keep the still visible while the movie item prepares. Do not expose the black
  backing of `AVPlayerLayer`; reveal it only when `readyForDisplay` is true.
- The player layer must follow the settled image view's bounds even when the
  player is prepared before the first layout pass. A zero-sized initial frame
  must expand with the image view; audio-only playback is never an acceptable
  fallback.
- Interaction interruption distinguishes preparation from active playback. If
  a pinch or page drag interrupts seek/preroll, releasing it restarts the
  ready-gated preparation path. If it interrupts active playback, releasing it
  resumes from the paused position. A cancelled page turn must not destroy and
  recreate the player.
- Teardown invalidates requests, cancels preroll, pauses, removes observers,
  and detaches the layer without issuing a redundant seek. Runtime item failure
  always returns to the still. End-of-item Loop/Bounce work must revalidate the
  playback permission and generation before it can seek or change rate.
- Starting and ending playback must not change the visible aperture, image-view
  frame, zoom center, or paging offset.
- A decoded-still upgrade arriving during playback or zoom must not tear down and
  rebuild the player.

## Image-loading contract

- Show the stored thumbnail as an immediate placeholder when available.
- Resolve one final Live presentation aperture before showing an asset. For a
  motion asset, the motion track's transformed display aspect ratio is the
  canonical base aperture: crop the oriented still into it first. If capture
  selected `4:3`, `1:1`, or `16:9`, present both media through that same further
  crop; `native` retains the canonical Live aperture. The placeholder, decoded
  still, and `AVPlayerLayer` must use this one aperture from their first visible
  frame. Photo and motion are never allowed to derive independent geometry.
- Replacing a placeholder with its decoded still must be an in-place contents
  update when the aperture is unchanged. It must not reset zoom, relayout the
  page, briefly clear the image, or recreate the player.
- Keep only a small cache of display-sized images, keyed by immutable asset ID.
- Load, orient, crop, resize, and pre-decode photos off the main thread. Retain
  the current page at its available source resolution for detail zoom. Decode
  only the adjacent reusable pages to viewport resolution; promote an adjacent
  asset to source resolution when it becomes current. This bounds decoded-memory
  use without reducing the settled photo's clarity. Never upscale the source.
- Apply a result only if the target page still represents the same asset ID.
- Memory warnings cancel queued work and discard decoded images outside the
  visible page.

## Existing behavior preserved

- Assets retain the array's existing newest-first order.
- Metadata and Live mode controls always describe the settled current asset.
- Share and delete operate only on the settled current asset.
- Deleting the final asset exits detail; otherwise the nearest remaining asset
  becomes current.
- The preview continues hiding the library Tab Bar through the existing
  container-controller behavior.

## Acceptance

### Repository checks

- Both camera targets compile without raising deployment targets.
- The old `UISwipeGestureRecognizer` and fixed push transition are absent from
  photo paging.
- The detail controller holds at most three page image views and a bounded image
  cache, and full photo processing is not performed on the main thread.
- Existing localization resources remain unchanged.

### Physical-device checks

- On the intended iOS 6 and iOS 7/8 devices, slow drags track the finger without
  a delayed jump; short drags cancel naturally; fast flicks advance one asset.
- Pinch and double-tap zoom remain centered on the intended detail, enlarged
  panning does not page accidentally, and returning to `1×` restores paging.
- Releasing a pinch or enlarged-photo pan resumes the selected Live behavior
  without resetting zoom. Still-to-motion and thumbnail-to-detail transitions
  retain exactly one aperture and show no black or geometry flash.
- First/last-page resistance, repeated direction changes, large JPEGs, mixed
  aspect ratios, and motion assets do not flash a stale photo or freeze input.
- After settling, Live playback, long press, metadata, share, and delete still
  target the visible asset.
- Single tapping repeatedly preserves the visible aperture and toggles chrome
  without a black frame. Double tap still zooms, and holding long enough to
  recognize a press plays motion without an intermediate full-screen toggle or
  pause.
- Observe peak memory while repeatedly paging through at least 30 assets.

Current-SDK compilation validates source integration only. It does not prove
gesture feel, decode latency, playback timing, or memory behavior on period
hardware.
