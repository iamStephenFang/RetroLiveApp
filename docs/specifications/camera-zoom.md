---
title: Camera Zoom
status: implemented-pending-device-validation
type: specification
---

# Camera Zoom

| Scope | Value |
| --- | --- |
| Targets | `RetroLiveCamera` (iOS 6) and `RetroLiveClassic` (iOS 7/8) |
| Owner boundary | Shared camera UI plus `RLVCaptureController` |

## Outcome

Pinching anywhere inside the visible camera preview continuously changes the
capture magnification. The gesture feels direct: its scale is relative to the
magnification at the beginning of that pinch, it may reverse direction without
starting a new gesture, and a later pinch continues from the committed value.

Zoom changes the field of view used by preview, still capture, and the rolling
motion companion. It does not transform only the preview view, change the
selected aspect ratio, or add fields to the Manifest.

## Compatibility decision

- On iOS 7 and later, use `AVCaptureDevice.videoZoomFactor`. Device-level zoom
  is the single source of truth for every output and matches the native capture
  pipeline.
- On iOS 6, where device zoom is unavailable, apply the same clamped
  `videoScaleAndCropFactor` to the preview, still-image, and movie connections
  that advertise a usable range. This is a compatibility fallback, not a view
  transform.
- Use only APIs available to the target SDK. Do not introduce modern virtual
  device, constituent lens, system zoom slider, or Photo Output APIs.

The app quality limit is `3.0x`. The effective maximum is the smaller of that
limit and the active device/connection maximum. A device whose effective
maximum is not greater than `1.0x` silently leaves pinch disabled.

## Interaction contract

1. Install one `UIPinchGestureRecognizer` on `previewView`. Accept it only when
   the camera is running, asset storage is not pending, and the gesture begins
   inside the actual `previewLayer.frame`; letterboxed space and controls are
   outside the zoom surface.
2. On `.began`, snapshot the recognizer scale. On `.changed`, multiply the
   controller-owned requested factor by the change since the previous event,
   then advance the scale snapshot. This rebases continuously at both limits,
   so reversing direction responds immediately without a dead zone.
3. Clamp every request to `[1.0, effectiveMaximum]` before touching AVFoundation.
   Reject non-finite and non-positive factors. Crossing a boundary stays pinned
   there and reversing the same pinch responds immediately.
4. Serialize AVFoundation mutations on the existing session queue. Give every
   request a generation and discard stale UI callbacks. A configuration failure
   resolves the latest requested factor back to the applied factor.
5. Coalesce changed events: callers may submit updates at gesture frequency,
   but the serial queue applies only the newest pending factor when it catches
   up. The main thread must not wait on device locks.
6. Camera switching resets the new camera to `1.0x`; interruption and preview-
   layer rebuilding preserve the active camera's zoom. Stopping and reopening
   the camera view resets to `1.0x`.
7. Capturing or beginning a camera switch cancels the UI gesture. A camera
   switch is an explicit non-interactive controller state, preventing requests
   from racing the old and new devices. An already applied factor remains
   stable for the capture that follows.
8. Unsupported hardware and configuration-lock failures degrade silently and
   log a diagnostic; they do not show a modal capture error.

## Magnification feedback

- While a pinch or discrete double-tap change is active, show the effective
  committed magnification as a compact circular `1.0×` label near the lower
  edge of the visible preview. Update it only after the capture controller
  successfully applies the clamped factor.
- At `1.0×`, keep the label visible briefly after the interaction ends, then
  fade it out. At any committed factor other than `1.0×`, keep the label
  visible so the cropped field of view is never mistaken for the optical
  baseline. The applied controller factor is the only source used to decide
  this visibility; capture, camera-switch, and application lifecycle states do
  not add separate visibility rules. Leaving the camera clears the UI feedback.
- Treat the visible factor as a button. A single tap requests `1.0×`; keep the
  old value visible until the controller commits the reset, then show `1.0×`
  briefly and fade it out. Tapping this button must not also focus or trigger
  the preview's double-tap gesture.
- Keep the label centered on the preview's physical lower edge and rotate only
  its contents with the other controls. Orientation must not move it sideways.

## Gesture coexistence and accessibility

- Pinch and tap-to-focus must not recognize simultaneously. Keep the focus
  recognizer limited to one touch and reject it while pinch is beginning or
  changing, so lifting fingers from a pinch cannot leave a focus request.
- A one-finger double tap toggles between `1.0×` and `2.0×`, bounded by the
  effective device maximum. Single-tap focus waits for the double-tap recognizer
  to fail, so one double tap cannot also move the focus point.
- Update the localized preview hint to describe both centered focus activation
  and two-finger zoom. The transient factor is an accessibility element with a
  localized value, but zoom remains a direct gesture and does not announce
  every intermediate update.

## Code boundaries

`RLVBaseCameraViewController` owns recognizer lifecycle, preview hit-testing,
per-gesture scale deltas, feedback request identity, and accessibility copy. It
does not retain a requested/applied zoom factor or access an `AVCaptureDevice`
or output connection.

`RLVCaptureController` is the sole zoom source of truth. It owns requested and
applied factors, request generations, effective capability discovery, clamping,
session-queue coalescing, device locking, connection fallback, camera-switch
state/reset, and the committed factor reported back to the UI.

## Acceptance

### Repository checks

- Both camera schemes compile without increasing either deployment target.
- Static seams cover clamping, invalid values, a `1.0x`-only device, and the
  multiplicative `startFactor * gestureScale` calculation.
- Pinch and focus recognizers are mutually exclusive; a two-finger pinch and
  either finger lift cannot trigger focus.
- English, Simplified Chinese, and Traditional Chinese strings remain valid.
- Zoom does not alter Manifest or transfer fixtures.

### Physical-device checks

- On Legacy iOS 6 and Classic iOS 7/8 hardware, pinch is continuous in both
  directions, clamps without jumping, and a second pinch continues smoothly.
- Preview, saved JPEG, and Live motion have matching framing at `1.0x`, an
  intermediate factor, and the effective maximum for rear and front cameras.
- Test pinch followed immediately by shutter, camera switch, aspect-ratio
  change, rotation, and repeated background/foreground transitions.
- Confirm switching cameras resets to `1.0x`, while foreground recovery on the
  same camera preserves zoom and still yields a visible, capturable preview.
- Compare responsiveness and image quality with the native Camera app on each
  exact device/OS pair before marking experience fidelity complete.

Current-SDK builds prove source integration only. They do not prove connection-
level zoom on iOS 6 hardware, framing parity, performance, or gesture fidelity.

## References

- Apple: [`AVCaptureDevice.videoZoomFactor`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/videozoomfactor)
- Apple: [`AVCaptureConnection.videoScaleAndCropFactor`](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videoscaleandcropfactor)

The compatibility floor was checked against the installed iPhoneOS SDK headers:
connection scale-and-crop is marked iOS 5.0 and device zoom is marked iOS 7.0.
