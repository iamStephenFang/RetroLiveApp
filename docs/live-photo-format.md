# Live Photo Format Boundary

Live Photo assembly belongs exclusively to the modern importer. It will copy the original JPEG and MOV to an assembly directory, add a shared content identifier, add the still-image-time timed metadata to the video, validate the result, and submit `.photo` and `.pairedVideo` resources in one PhotoKit creation request.

The legacy library previews the original `photo.jpg` and `motion.mov` pair directly. Motion assets play once when opened, support press-and-hold playback, and offer Live, Loop, Bounce, and Still viewing effects. This is a local playback preference saved outside the immutable asset directory; it does not add Live Photo metadata or change the effect of the Live Photo later created by the modern importer.

No Live Photo metadata code is implemented in Phase 0. The original RetroLive asset remains valid even if future Live Photo conversion fails.
