#!/bin/sh

# Synchronize the legacy camera source to an isolated archived-toolchain Mac,
# then invoke its Xcode installation. This script intentionally keeps Git and
# GitHub credentials on the modern development Mac.

set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
REPOSITORY_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd) || exit 1
WORKER_SCRIPT="$SCRIPT_DIR/legacy-remote-worker.sh"
EXCLUDE_FILE="$SCRIPT_DIR/legacy-rsync-excludes.txt"
CONFIG_FILE=${RETROLIVE_REMOTE_CONFIG:-"$REPOSITORY_ROOT/.retrolive-legacy.env"}

fail() {
    printf 'legacy-remote: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: tools/legacy-remote.sh <command> [scheme]

Commands:
  init              Create and mark the dedicated remote mirror directories.
  doctor            Inspect SSH, the archived Xcode toolchain, and signing.
  sync              Mirror legacy-camera/ to the remote Mac.
  build [scheme]    Sync, then build RetroLiveCamera (default) or RetroLiveClassic.
  help              Show this message.

Set RETROLIVE_REMOTE_CONFIG to use a config file other than
.retrolive-legacy.env at the repository root.
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

require_absolute_remote_path() {
    path_value=$1
    path_label=$2

    case "$path_value" in
        /*) ;;
        *) fail "$path_label must be an absolute path" ;;
    esac
    case "$path_value" in
        *"'"*) fail "$path_label must not contain a single quote" ;;
    esac
}

load_config() {
    [ -f "$CONFIG_FILE" ] || fail "missing config: copy tools/legacy-remote.env.example to .retrolive-legacy.env"

    # The config is a local shell fragment owned by the developer. It must not
    # be accepted from an untrusted source or committed to the repository.
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"

    : "${RETROLIVE_REMOTE:?set RETROLIVE_REMOTE in $CONFIG_FILE}"
    : "${RETROLIVE_REMOTE_ROOT:?set RETROLIVE_REMOTE_ROOT in $CONFIG_FILE}"
    : "${RETROLIVE_REMOTE_DERIVED_DATA:?set RETROLIVE_REMOTE_DERIVED_DATA in $CONFIG_FILE}"
    : "${RETROLIVE_REMOTE_DEVELOPER_DIR:?set RETROLIVE_REMOTE_DEVELOPER_DIR in $CONFIG_FILE}"

    RETROLIVE_CONFIGURATION=${RETROLIVE_CONFIGURATION:-Debug}
    RETROLIVE_CODE_SIGNING_ALLOWED=${RETROLIVE_CODE_SIGNING_ALLOWED:-NO}
    RETROLIVE_SIGNING_XCCONFIG=${RETROLIVE_SIGNING_XCCONFIG:-}

    case "$RETROLIVE_REMOTE" in
        -*) fail "RETROLIVE_REMOTE must not begin with '-'" ;;
        *[!A-Za-z0-9_.@-]*) fail "RETROLIVE_REMOTE must be an SSH alias, host, or user@host" ;;
    esac
    case "$RETROLIVE_REMOTE_ROOT" in
        /*/*/*) ;;
        *) fail "RETROLIVE_REMOTE_ROOT must be an absolute, dedicated path at least three components deep" ;;
    esac
    case "$RETROLIVE_REMOTE_ROOT" in
        *[!A-Za-z0-9_./-]*)
            fail "RETROLIVE_REMOTE_ROOT may contain only letters, numbers, underscore, dot, slash, and hyphen"
            ;;
    esac
    require_absolute_remote_path "$RETROLIVE_REMOTE_ROOT" "RETROLIVE_REMOTE_ROOT"
    require_absolute_remote_path "$RETROLIVE_REMOTE_DERIVED_DATA" "RETROLIVE_REMOTE_DERIVED_DATA"
    require_absolute_remote_path "$RETROLIVE_REMOTE_DEVELOPER_DIR" "RETROLIVE_REMOTE_DEVELOPER_DIR"
    if [ -n "$RETROLIVE_SIGNING_XCCONFIG" ]; then
        require_absolute_remote_path "$RETROLIVE_SIGNING_XCCONFIG" "RETROLIVE_SIGNING_XCCONFIG"
    fi
    case "$RETROLIVE_CONFIGURATION" in
        Debug|Release) ;;
        *) fail "RETROLIVE_CONFIGURATION must be Debug or Release" ;;
    esac
    case "$RETROLIVE_CODE_SIGNING_ALLOWED" in
        YES|NO) ;;
        *) fail "RETROLIVE_CODE_SIGNING_ALLOWED must be YES or NO" ;;
    esac
}

optional_arg() {
    if [ -n "$1" ]; then
        printf '%s\n' "$1"
    else
        printf '%s\n' '-'
    fi
}

run_worker() {
    remote_command='/bin/sh -s --'
    for remote_argument do
        case "$remote_argument" in
            *"'"*) fail "remote arguments must not contain a single quote" ;;
        esac
        remote_command="$remote_command '$remote_argument'"
    done
    ssh "$RETROLIVE_REMOTE" "$remote_command" < "$WORKER_SCRIPT"
}

validate_scheme() {
    case "$1" in
        RetroLiveCamera|RetroLiveClassic) ;;
        *) fail "scheme must be RetroLiveCamera or RetroLiveClassic" ;;
    esac
}

source_revision() {
    if command -v git >/dev/null 2>&1 && git -C "$REPOSITORY_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$REPOSITORY_ROOT" rev-parse --verify HEAD
    else
        printf '%s\n' unknown
    fi
}

source_state() {
    if command -v git >/dev/null 2>&1 &&
       [ -n "$(git -C "$REPOSITORY_ROOT" status --porcelain -- legacy-camera 2>/dev/null)" ]; then
        printf '%s\n' dirty
    else
        printf '%s\n' clean
    fi
}

do_init() {
    run_worker init "$RETROLIVE_REMOTE_ROOT" "$RETROLIVE_REMOTE_DERIVED_DATA"
}

do_doctor() {
    require_command ssh
    require_command rsync
    printf 'Local rsync: '
    rsync --version | sed -n '1p'
    printf 'SSH target: %s\n\n' "$RETROLIVE_REMOTE"
    run_worker doctor \
        "$RETROLIVE_REMOTE_ROOT" \
        "$RETROLIVE_REMOTE_DERIVED_DATA" \
        "$RETROLIVE_REMOTE_DEVELOPER_DIR" \
        "$(optional_arg "$RETROLIVE_SIGNING_XCCONFIG")" \
        "$RETROLIVE_CODE_SIGNING_ALLOWED"
}

do_sync() {
    require_command ssh
    require_command rsync
    [ -f "$EXCLUDE_FILE" ] || fail "missing rsync exclude file: $EXCLUDE_FILE"
    [ -d "$REPOSITORY_ROOT/legacy-camera" ] || fail "legacy-camera source directory is missing"

    run_worker verify-mirror "$RETROLIVE_REMOTE_ROOT"
    printf 'Synchronizing legacy-camera/ to %s:%s/legacy-camera/\n' \
        "$RETROLIVE_REMOTE" "$RETROLIVE_REMOTE_ROOT"
    rsync -a --delete --exclude-from="$EXCLUDE_FILE" \
        "$REPOSITORY_ROOT/legacy-camera/" \
        "$RETROLIVE_REMOTE:$RETROLIVE_REMOTE_ROOT/legacy-camera/" ||
        fail "rsync failed"

    revision=$(source_revision) || fail "could not determine source revision"
    state=$(source_state)
    synced_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    run_worker metadata "$RETROLIVE_REMOTE_ROOT" "$revision" "$state" "$synced_at"
    printf 'Synchronized revision %s (%s).\n' "$revision" "$state"
}

do_build() {
    scheme=$1
    validate_scheme "$scheme"
    do_sync
    run_worker build \
        "$RETROLIVE_REMOTE_ROOT" \
        "$RETROLIVE_REMOTE_DERIVED_DATA" \
        "$RETROLIVE_REMOTE_DEVELOPER_DIR" \
        "$scheme" \
        "$RETROLIVE_CONFIGURATION" \
        "$RETROLIVE_CODE_SIGNING_ALLOWED" \
        "$(optional_arg "$RETROLIVE_SIGNING_XCCONFIG")"
}

command_name=${1:-help}
case "$command_name" in
    help|-h|--help)
        usage
        exit 0
        ;;
esac

load_config
[ -f "$WORKER_SCRIPT" ] || fail "missing remote worker: $WORKER_SCRIPT"

case "$command_name" in
    init)
        [ "$#" -eq 1 ] || fail "init does not accept a scheme"
        do_init
        ;;
    doctor)
        [ "$#" -eq 1 ] || fail "doctor does not accept a scheme"
        do_doctor
        ;;
    sync)
        [ "$#" -eq 1 ] || fail "sync does not accept a scheme"
        do_sync
        ;;
    build)
        [ "$#" -le 2 ] || fail "build accepts at most one scheme"
        do_build "${2:-RetroLiveCamera}"
        ;;
    *)
        usage >&2
        fail "unknown command: $command_name"
        ;;
esac
