#!/bin/sh

# Run locally on the archived-toolchain Mac after legacy-sync.sh has copied the
# current source snapshot. Keep this compatible with the POSIX shell in OS X
# Mavericks.

set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
REPOSITORY_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd) || exit 1
CONFIG_FILE=${RETROLIVE_BUILD_CONFIG:-"$REPOSITORY_ROOT/.retrolive-legacy-build.env"}

fail() {
    printf 'legacy-build: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: scripts/legacy-build.sh <command> [scheme]

Commands:
  doctor            Show macOS, Xcode, SDK, path, and signing information.
  build [scheme]    Build RetroLiveCamera (default) or RetroLiveClassic.
  help              Show this message.
EOF
}

command_name=${1:-help}
case "$command_name" in
    help|-h|--help)
        usage
        exit 0
        ;;
esac

[ -f "$CONFIG_FILE" ] ||
    fail "copy scripts/legacy-build.env.example to .retrolive-legacy-build.env first"

# The config is a private shell fragment owned by the developer.
# shellcheck disable=SC1090
. "$CONFIG_FILE"

: "${RETROLIVE_DEVELOPER_DIR:?set RETROLIVE_DEVELOPER_DIR in $CONFIG_FILE}"
: "${RETROLIVE_DERIVED_DATA:?set RETROLIVE_DERIVED_DATA in $CONFIG_FILE}"
RETROLIVE_CONFIGURATION=${RETROLIVE_CONFIGURATION:-Debug}
RETROLIVE_CODE_SIGNING_ALLOWED=${RETROLIVE_CODE_SIGNING_ALLOWED:-NO}
RETROLIVE_SIGNING_XCCONFIG=${RETROLIVE_SIGNING_XCCONFIG:-}

case "$RETROLIVE_CONFIGURATION" in
    Debug|Release) ;;
    *) fail "RETROLIVE_CONFIGURATION must be Debug or Release" ;;
esac
case "$RETROLIVE_CODE_SIGNING_ALLOWED" in
    YES|NO) ;;
    *) fail "RETROLIVE_CODE_SIGNING_ALLOWED must be YES or NO" ;;
esac
[ -x /usr/bin/xcodebuild ] || fail "/usr/bin/xcodebuild is unavailable"
[ -d "$REPOSITORY_ROOT/legacy-camera/RetroLiveCamera.xcodeproj" ] ||
    fail "the synchronized Xcode project is missing"

run_xcodebuild() {
    DEVELOPER_DIR="$RETROLIVE_DEVELOPER_DIR" /usr/bin/xcodebuild "$@"
}

case "$command_name" in
    doctor)
        [ "$#" -eq 1 ] || fail "doctor does not accept a scheme"
        /usr/bin/sw_vers
        printf '\nArchived toolchain:\n'
        run_xcodebuild -version
        run_xcodebuild -showsdks
        printf '\nDerived Data: %s\n' "$RETROLIVE_DERIVED_DATA"
        printf 'CODE_SIGNING_ALLOWED=%s\n' "$RETROLIVE_CODE_SIGNING_ALLOWED"
        if [ -n "$RETROLIVE_SIGNING_XCCONFIG" ]; then
            [ -f "$RETROLIVE_SIGNING_XCCONFIG" ] ||
                fail "signing xcconfig does not exist: $RETROLIVE_SIGNING_XCCONFIG"
            printf 'Signing xcconfig: %s\n' "$RETROLIVE_SIGNING_XCCONFIG"
        fi
        printf '\nCode signing identities:\n'
        /usr/bin/security find-identity -v -p codesigning || true
        ;;
    build)
        [ "$#" -le 2 ] || fail "build accepts at most one scheme"
        scheme=${2:-RetroLiveCamera}
        case "$scheme" in
            RetroLiveCamera|RetroLiveClassic) ;;
            *) fail "scheme must be RetroLiveCamera or RetroLiveClassic" ;;
        esac
        /bin/mkdir -p "$RETROLIVE_DERIVED_DATA" || fail "could not create Derived Data"

        if [ -n "$RETROLIVE_SIGNING_XCCONFIG" ]; then
            [ -f "$RETROLIVE_SIGNING_XCCONFIG" ] ||
                fail "signing xcconfig does not exist: $RETROLIVE_SIGNING_XCCONFIG"
            set -- -project "$REPOSITORY_ROOT/legacy-camera/RetroLiveCamera.xcodeproj" \
                -scheme "$scheme" -configuration "$RETROLIVE_CONFIGURATION" \
                -sdk iphoneos -derivedDataPath "$RETROLIVE_DERIVED_DATA" \
                -xcconfig "$RETROLIVE_SIGNING_XCCONFIG" \
                CODE_SIGNING_ALLOWED="$RETROLIVE_CODE_SIGNING_ALLOWED" build
        else
            set -- -project "$REPOSITORY_ROOT/legacy-camera/RetroLiveCamera.xcodeproj" \
                -scheme "$scheme" -configuration "$RETROLIVE_CONFIGURATION" \
                -sdk iphoneos -derivedDataPath "$RETROLIVE_DERIVED_DATA" \
                CODE_SIGNING_ALLOWED="$RETROLIVE_CODE_SIGNING_ALLOWED" build
        fi
        run_xcodebuild "$@"
        ;;
    *)
        usage >&2
        fail "unknown command: $command_name"
        ;;
esac
