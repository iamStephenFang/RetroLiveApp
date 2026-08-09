# Live Photo Format Boundary

Live Photo assembly belongs exclusively to the modern importer. It copies or crops the original JPEG and MOV into an assembly directory, adds a shared content identifier, adds the still-image-time timed metadata to the video, validates the result, and submits `.photo` and `.pairedVideo` resources in one PhotoKit creation request.

When `capture.aspectRatio` is present, the assembler uses the display-oriented motion aperture as the common field of view, center-crops the photo into that aperture, and applies the chosen `4:3`, `1:1`, or `16:9` frame to both resources. Photo orientation is flattened in the generated paired JPEG and cropped motion video is encoded only on the modern device. The original downloaded asset is not modified. Assets without `capture.aspectRatio` keep the prior pass-through behavior.

The legacy library previews the original `photo.jpg` and `motion.mov` pair through the selected framing window. Motion assets play once when opened, support press-and-hold playback, and offer Live, Loop, Bounce, and Still viewing effects. This is a local playback preference saved outside the immutable asset directory; it does not add Live Photo metadata or change the effect of the Live Photo later created by the modern importer.

No Live Photo metadata code is implemented in Phase 0. The original RetroLive asset remains valid even if future Live Photo conversion fails.
