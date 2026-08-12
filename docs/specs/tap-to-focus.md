# Tap to Focus Specification

- Status: Implemented; physical-device acceptance pending
- Targets: `RetroLiveCamera` (iOS 6) and `RetroLiveClassic` (iOS 7/8)
- Owner boundary: shared camera UI plus `RLVCaptureController`

## Outcome

Tapping a visible point in the camera preview requests one-shot focus and
exposure metering at the corresponding camera point, then shows a short focus
reticle at the tapped location. Unsupported hardware degrades without an error
dialog: focus and exposure are applied independently, and a device supporting
neither ignores the tap.

This behavior belongs only to the camera preview. It does not change the saved
Manifest, asset format, motion timing, transfer protocol, or importer.

## Implementation

The shared camera implements this path:

1. `RLVBaseCameraViewController` installs a tap recognizer on `previewView`.
2. It converts the view point into `AVCaptureVideoPreviewLayer` coordinates.
3. `captureDevicePointOfInterestForPoint:` converts that point to normalized
   device coordinates while accounting for preview geometry and `videoGravity`.
4. `RLVCaptureController` serializes the request on its session queue, configures
   supported focus and exposure independently while holding the device lock, and
   reports the accepted capabilities to the UI.
5. The shared camera UI shows one clipped yellow reticle only for an accepted
   request. Camera switching, capture, and leaving the view invalidate pending
   reticle feedback.
6. Subject-area changes, camera switching, interruption recovery, and session
   restart restore centered continuous automatic behavior.

Repository source builds and localization lint pass. Exact focus/exposure
behavior and visual fidelity remain pending on the intended iOS 6 and iOS 7/8
devices.

## Compatibility decision

Use the Objective-C AVFoundation APIs available to the iOS 6 SDK:

- `AVCaptureVideoPreviewLayer captureDevicePointOfInterestForPoint:` is available
  from iOS 6 and handles orientation, layer size, and `videoGravity` conversion.
- `focusPointOfInterest`, `exposurePointOfInterest`, their support checks, and
  `lockForConfiguration:` are available to both camera targets.
- `AVCaptureDeviceSubjectAreaDidChangeNotification` and
  `subjectAreaChangeMonitoringEnabled` are available from iOS 5.

Do not introduce modern photo-output, lens-position, async configuration, or
Swift-only APIs into the shared implementation.

## Interaction contract

1. Accept a tap only when the camera is running, no camera switch is pending,
   and the tap lies inside `previewLayer.frame`. The surrounding preview view may
   be larger than the selected `4:3`, `1:1`, or `16:9` layer.
2. Keep the original tap location in `previewView` coordinates for the reticle.
   Convert a separate point into preview-layer coordinates, then call
   `captureDevicePointOfInterestForPoint:`. Reject a non-finite or out-of-range
   result rather than forwarding invalid device coordinates.
3. Dispatch device work to `RLVCaptureController`'s serial session queue. Read
   the active `videoInput.device` on that queue so a simultaneous camera switch
   cannot configure the retired device.
4. Acquire the device configuration lock once. Configure focus and exposure
   independently:
   - if point focus and `AVCaptureFocusModeAutoFocus` are supported, set the
     focus point and request one-shot autofocus;
   - if point exposure and `AVCaptureExposureModeAutoExpose` are supported, set
     the exposure point and request one-shot auto exposure;
   - if one-shot auto exposure is unavailable but continuous auto exposure is
     supported, use continuous auto exposure at the selected point.
5. Enable subject-area monitoring after a manual adjustment. On
   `AVCaptureDeviceSubjectAreaDidChangeNotification`, return supported focus and
   exposure modes to continuous automatic operation at the center point
   `(0.5, 0.5)`, then disable monitoring until the next manual tap.
6. Camera switching, interruption recovery, and a newly prepared session also
   restore the centered continuous automatic state. Notifications must follow
   the current input device rather than a removed camera.
7. Do not present configuration-lock or unsupported-capability failures as modal
   capture errors. The camera remains usable; record a diagnostic if logging is
   available.

## Reticle behavior

- Draw the reticle in the shared camera UI so Legacy and Classic use the same
  focus semantics. Each target may override only visual styling when later
  reference screenshots justify a difference.
- Center a square reticle on the accepted tap and keep it clipped to the visible
  preview-layer frame. Suggested provisional size: 72 points with a 1-point
  yellow stroke.
- Start slightly enlarged, animate to its normal size in about 0.15 seconds,
  hold briefly, then fade out. A newer tap cancels the previous animation and
  moves the same view; do not accumulate reticle views.
- The reticle must not intercept touches and must stay above the preview layer
  but below shutter feedback and other camera controls.
- VoiceOver should expose a localized camera-preview hint explaining that a
  double tap adjusts focus and exposure. Do not announce success merely because
  a request was sent; old AVFoundation provides no reliable semantic "focused"
  completion event for this flow.

The exact size, color, line width, and timing remain provisional until the
device/screenshot comparison in `../camera-ui-measurements.md` is completed.

## Code boundaries

`RLVBaseCameraViewController` owns gesture recognition, preview hit-testing,
coordinate conversion, reticle animation, and localized accessibility text.

`RLVCaptureController` owns all device capability checks, configuration locking,
session-queue serialization, subject-area notification handling, centered-auto
reset, and camera-switch cleanup. The UI must not access `videoInput.device`
directly.

Prefer a result callback containing only whether focus and/or exposure was
accepted. It lets the UI avoid showing a reticle on fully fixed hardware without
leaking `AVCaptureDevice` into the view controller. The callback returns on the
main queue.

## Acceptance

### Repository checks

- Both camera target source sets compile without raising their deployment
  targets or introducing APIs newer than iOS 6.
- A focused controller test or test seam covers: focus plus exposure, focus-only,
  exposure-only, neither supported, configuration-lock failure, and a camera
  switch racing with a tap.
- Preview hit-testing covers all three aspect ratios and rejects taps in the
  surrounding non-preview area.
- Repeated taps reuse one reticle and do not leave animations or observers
  attached after the camera view disappears.
- English, Simplified Chinese, and Traditional Chinese accessibility strings are
  present and plist/string lint still passes.

### Physical-device checks

- Rear-camera taps near all four corners and the center meter the same visible
  location on the iOS 6 Legacy and iOS 7/8 Classic devices.
- A fixed-focus front camera does not crash or show a false focus failure;
  exposure-only behavior is recorded separately when supported.
- `4:3`, `1:1`, and `16:9` taps remain aligned after relaunch and after changing
  orientation. Taps outside the reduced preview frame have no effect.
- Rapid taps, a tap during camera switching, background/foreground transitions,
  and a tap immediately before the shutter do not freeze the session or lose the
  subsequent still/motion capture.
- After a manual tap, a substantial scene change returns the camera to centered
  continuous automatic behavior.
- Compare the reticle against the native Camera app on each exact device/OS pair
  before marking visual fidelity complete.

Current-SDK compilation can validate source compatibility only; it cannot prove
focus, exposure, coordinate alignment, or reticle timing on period hardware.

## References

- Apple: [`captureDevicePointOfInterestForPoint:`](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer/capturedevicepointofinterest(for:))
- Apple: [`focusPointOfInterest`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/focuspointofinterest)
- Apple: [`exposurePointOfInterest`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/exposurepointofinterest)
- Apple: [`AVCaptureDeviceSubjectAreaDidChangeNotification`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/subjectareadidchangenotification)

The compatibility floor above was also checked against the installed iPhoneOS
SDK headers: preview-layer point conversion is marked iOS 6.0, and subject-area
monitoring is marked iOS 5.0.
