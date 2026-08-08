# Camera UI Measurement Spec

This file separates current implementation metrics from pixel-accepted measurements. Values marked **provisional** must be replaced or confirmed from an exact-device native Camera screenshot.

## Reference inventory

- Legacy behavior reference: [Apple iPhone User Guide for iOS 6, Camera overview](https://www.pdfmanuales.com/manuals/29401/apple-iphone-para-el-software-ios-6.html?page=78) (flash, camera switch, shutter, mode switch, recent-photo placement).
- Classic documentation reference: [Apple's iPhone 6 manuals page](https://support.apple.com/en-me/docs/iphone/134711), including the iPhone User Guide for iOS 8.4.
- Classic visual cross-check: [a 2013 iOS 7 Camera walkthrough](https://9to5mac.com/2013/09/20/how-to-use-the-new-camera-app-in-ios-7/) showing the flat full-screen preview, white shutter, upper flash/switch controls, and lower-left thumbnail. iOS 8 device screenshots remain required for final acceptance.

## Current layout metrics

| Metric | iPhone 4S 320×480 | iPhone 5/5s 320×568 | iPhone 6 375×667 |
|---|---:|---:|---:|
| Legacy top chrome | 44 | 44 | n/a |
| Legacy bottom chrome | 88 | 96 | n/a |
| Legacy shutter visual frame | 76 | 76 | n/a |
| Legacy thumbnail | 48 | 48 | n/a |
| Classic top overlay | n/a | 44 | 44 |
| Classic bottom overlay | n/a | 128 | 142 |
| Classic shutter visual frame | n/a | 78 | 78 |
| Classic thumbnail | n/a | 48 | 48 |

All values are points and **provisional**. Visual sizes are distinct from their surrounding control frames/hit regions.

## Overlay review procedure

1. Capture native Camera and RetroLive at the same screen size and orientation.
2. Normalize neither image; compare at native pixel scale.
3. Measure preview, chrome, shutter, thumbnail, flash, switch, and mode label frames.
4. Overlay at 50% opacity and record each delta in points.
5. Record normal/highlighted/capturing states and control-rotation duration.
6. Adjust structural metrics before gradients, texture, gloss, or other decorative material.

No release claim of native fidelity should be made until at least iPhone 5/iOS 6 and iPhone 5s-or-6/iOS 8 references complete this table.
