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

usage() {
    cat <<'EOF'
Usage: scripts/legacy-sync.sh [--dry-run]

Options:
  --dry-run  Show additions, updates, and deletions without changing the legacy Mac.
  -h, --help Show this message.
EOF
}

dry_run=NO
case "${1:-}" in
    "") ;;
    --dry-run) dry_run=YES ;;
    help|-h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        fail "unknown option: $1"
        ;;
esac
[ "$#" -le 1 ] || fail "expected at most one option"

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
    */) fail "RETROLIVE_SYNC_ROOT must not end with '/'" ;;
    *//*|*/./*|*/.|*/../*|*/..) fail "RETROLIVE_SYNC_ROOT must not contain empty, '.' or '..' path components" ;;
esac
case "$RETROLIVE_SYNC_ROOT" in
    *[!A-Za-z0-9_./-]*)
        fail "RETROLIVE_SYNC_ROOT may contain only letters, numbers, underscore, dot, slash, and hyphen"
        ;;
esac

[ -f "$EXCLUDE_FILE" ] || fail "missing rsync exclude file: $EXCLUDE_FILE"
[ -d "$REPOSITORY_ROOT/legacy-camera" ] || fail "legacy-camera source directory is missing"

run_rsync() {
    if [ "$dry_run" = YES ]; then
        rsync -an "$@"
    else
        rsync -a "$@"
    fi
}

if [ "$dry_run" = YES ]; then
    printf 'Dry run: no destination files will be changed.\n'
fi
printf 'Synchronizing legacy-camera/ to %s:%s/legacy-camera/\n' \
    "$RETROLIVE_SYNC_REMOTE" "$RETROLIVE_SYNC_ROOT"
run_rsync -i --delete --exclude-from="$EXCLUDE_FILE" \
    "$REPOSITORY_ROOT/legacy-camera/" \
    "$RETROLIVE_SYNC_REMOTE:$RETROLIVE_SYNC_ROOT/legacy-camera/" ||
    fail "source synchronization failed"

printf 'Synchronizing the local build script and its example config.\n'
(
    cd "$REPOSITORY_ROOT" || exit 1
    run_rsync -iR \
        scripts/legacy-build.sh \
        scripts/legacy-build.env.example \
        "$RETROLIVE_SYNC_REMOTE:$RETROLIVE_SYNC_ROOT/"
) || fail "build-script synchronization failed"

if [ "$dry_run" = YES ]; then
    printf 'Dry run complete. No files were changed.\n'
    exit 0
fi

printf 'Sync complete. Build locally on the legacy Mac with:\n'
printf '  cd %s && ./scripts/legacy-build.sh build RetroLiveCamera\n' "$RETROLIVE_SYNC_ROOT"
