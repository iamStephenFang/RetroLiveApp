#!/bin/sh

# Run on the modern development Mac. It performs a one-way source sync and does
# not execute build or deployment commands on the legacy Mac.

set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
REPOSITORY_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd) || exit 1
CONFIG_FILE=${RETROLIVE_SYNC_CONFIG:-"$REPOSITORY_ROOT/.retrolive-legacy-sync.env"}
EXCLUDE_FILE="$SCRIPT_DIR/legacy-rsync-excludes.txt"

fail() {
    printf 'legacy-sync: %s\n' "$*" >&2
    exit 1
}

command -v rsync >/dev/null 2>&1 || fail "rsync is unavailable"
[ -f "$CONFIG_FILE" ] ||
    fail "copy scripts/legacy-sync.env.example to .retrolive-legacy-sync.env first"

# The config is a private shell fragment owned by the developer.
# shellcheck disable=SC1090
. "$CONFIG_FILE"

: "${RETROLIVE_SYNC_REMOTE:?set RETROLIVE_SYNC_REMOTE in $CONFIG_FILE}"
: "${RETROLIVE_SYNC_ROOT:?set RETROLIVE_SYNC_ROOT in $CONFIG_FILE}"

case "$RETROLIVE_SYNC_REMOTE" in
    -*) fail "RETROLIVE_SYNC_REMOTE must not begin with '-'" ;;
    *[!A-Za-z0-9_.@-]*) fail "RETROLIVE_SYNC_REMOTE must be an SSH alias, host, or user@host" ;;
esac
case "$RETROLIVE_SYNC_ROOT" in
    /*/*/*) ;;
    *) fail "RETROLIVE_SYNC_ROOT must be an absolute, dedicated path at least three components deep" ;;
esac
case "$RETROLIVE_SYNC_ROOT" in
    *[!A-Za-z0-9_./-]*)
        fail "RETROLIVE_SYNC_ROOT may contain only letters, numbers, underscore, dot, slash, and hyphen"
        ;;
esac

[ -f "$EXCLUDE_FILE" ] || fail "missing rsync exclude file: $EXCLUDE_FILE"
[ -d "$REPOSITORY_ROOT/legacy-camera" ] || fail "legacy-camera source directory is missing"

printf 'Synchronizing legacy-camera/ to %s:%s/legacy-camera/\n' \
    "$RETROLIVE_SYNC_REMOTE" "$RETROLIVE_SYNC_ROOT"
rsync -a --delete --exclude-from="$EXCLUDE_FILE" \
    "$REPOSITORY_ROOT/legacy-camera/" \
    "$RETROLIVE_SYNC_REMOTE:$RETROLIVE_SYNC_ROOT/legacy-camera/" ||
    fail "source synchronization failed"

printf 'Synchronizing the local build script and its example config.\n'
(
    cd "$REPOSITORY_ROOT" || exit 1
    rsync -aR \
        scripts/legacy-build.sh \
        scripts/legacy-build.env.example \
        "$RETROLIVE_SYNC_REMOTE:$RETROLIVE_SYNC_ROOT/"
) || fail "build-script synchronization failed"

printf 'Sync complete. Build locally on the legacy Mac with:\n'
printf '  cd %s && ./scripts/legacy-build.sh build RetroLiveCamera\n' "$RETROLIVE_SYNC_ROOT"
