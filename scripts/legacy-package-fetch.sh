#!/bin/sh

# Run on the modern development Mac. Build an unsigned IPA remotely, then
# fetch only the legacy Mac's package artifacts back over SSH/rsync.

set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
REPOSITORY_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd) || exit 1
CONFIG_FILE=${RETROLIVE_SYNC_CONFIG:-"$REPOSITORY_ROOT/.retrolive-legacy-sync.env"}

fail() {
    printf 'legacy-package-fetch: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: scripts/legacy-package-fetch.sh [scheme]

Builds an unsigned IPA on the configured legacy Mac and fetches its artifacts.
The source tree must already have been synchronized with legacy-sync.sh.

Scheme:
  RetroLiveCamera, RetroLiveClassic, or all (default: RetroLiveCamera)
EOF
}

case "${1:-RetroLiveCamera}" in
    RetroLiveCamera|RetroLiveClassic|all) scheme=${1:-RetroLiveCamera} ;;
    help|-h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        fail "scheme must be RetroLiveCamera, RetroLiveClassic, or all"
        ;;
esac
[ "$#" -le 1 ] || fail "expected at most one scheme"

command -v ssh >/dev/null 2>&1 || fail "ssh is unavailable"
command -v rsync >/dev/null 2>&1 || fail "rsync is unavailable"
[ -f "$CONFIG_FILE" ] ||
    fail "copy scripts/legacy-sync.env.example to .retrolive-legacy-sync.env first"

# The config is a private shell fragment owned by the developer.
# shellcheck disable=SC1090
. "$CONFIG_FILE"

: "${RETROLIVE_SYNC_REMOTE:?set RETROLIVE_SYNC_REMOTE in $CONFIG_FILE}"
: "${RETROLIVE_SYNC_ROOT:?set RETROLIVE_SYNC_ROOT in $CONFIG_FILE}"
: "${RETROLIVE_REMOTE_PACKAGE_ROOT:?set RETROLIVE_REMOTE_PACKAGE_ROOT in $CONFIG_FILE}"
RETROLIVE_LOCAL_PACKAGE_ROOT=${RETROLIVE_LOCAL_PACKAGE_ROOT:-artifacts}

case "$RETROLIVE_SYNC_REMOTE" in
    -*) fail "RETROLIVE_SYNC_REMOTE must not begin with '-'" ;;
    *[!A-Za-z0-9_.@-]*) fail "RETROLIVE_SYNC_REMOTE must be an SSH alias, host, or user@host" ;;
esac
case "$RETROLIVE_SYNC_ROOT" in
    /*/*/*) ;;
    *) fail "RETROLIVE_SYNC_ROOT must be an absolute, dedicated path at least three components deep" ;;
esac
case "$RETROLIVE_REMOTE_PACKAGE_ROOT" in
    /*/*/*) ;;
    *) fail "RETROLIVE_REMOTE_PACKAGE_ROOT must be an absolute path at least three components deep" ;;
esac
case "$RETROLIVE_SYNC_ROOT:$RETROLIVE_REMOTE_PACKAGE_ROOT" in
    *[!A-Za-z0-9_./:-]*)
        fail "remote paths may contain only letters, numbers, underscore, dot, slash, colon, and hyphen"
        ;;
esac
case "$RETROLIVE_LOCAL_PACKAGE_ROOT" in
    /*) LOCAL_PACKAGE_ROOT=$RETROLIVE_LOCAL_PACKAGE_ROOT ;;
    *) LOCAL_PACKAGE_ROOT=$REPOSITORY_ROOT/$RETROLIVE_LOCAL_PACKAGE_ROOT ;;
esac

[ -d "$REPOSITORY_ROOT/legacy-camera" ] || fail "legacy-camera source directory is missing"
/bin/mkdir -p "$LOCAL_PACKAGE_ROOT" || fail "could not create local package directory"

printf 'Building %s on %s.\n' "$scheme" "$RETROLIVE_SYNC_REMOTE"
printf 'The legacy Mac must already contain the synchronized source and private build config.\n'
ssh "$RETROLIVE_SYNC_REMOTE" \
    "cd $RETROLIVE_SYNC_ROOT && ./scripts/legacy-package.sh package $scheme" ||
    fail "remote packaging failed"

printf 'Fetching package artifacts to %s.\n' "$LOCAL_PACKAGE_ROOT"
rsync -a \
    "$RETROLIVE_SYNC_REMOTE:$RETROLIVE_REMOTE_PACKAGE_ROOT/" \
    "$LOCAL_PACKAGE_ROOT/" || fail "package fetch failed"

printf 'Package fetch complete.\n'
