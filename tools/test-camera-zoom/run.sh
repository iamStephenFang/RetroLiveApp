#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/retrolive-camera-zoom-test"
mkdir -p "$BUILD_DIR"

clang -fobjc-arc -framework Foundation -framework CoreGraphics \
  -I "$ROOT/legacy-camera/RetroLiveCamera/Shared/Utilities" \
  "$ROOT/tools/test-camera-zoom/main.m" \
  -o "$BUILD_DIR/test-camera-zoom"
"$BUILD_DIR/test-camera-zoom"
