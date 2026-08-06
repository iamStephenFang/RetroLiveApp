# Live Photo Format Boundary

Live Photo assembly belongs exclusively to the modern importer. It will copy the original JPEG and MOV to an assembly directory, add a shared content identifier, add the still-image-time timed metadata to the video, validate the result, and submit `.photo` and `.pairedVideo` resources in one PhotoKit creation request.

No Live Photo metadata code is implemented in Phase 0. The original RetroLive asset remains valid even if future Live Photo conversion fails.

