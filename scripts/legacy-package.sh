#!/bin/sh

# Build an unsigned IPA on the archived-toolchain Mac. The IPA is a standard
# Payload archive; installation still requires signing for the target device.

set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
REPOSITORY_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd) || exit 1
CONFIG_FILE=${RETROLIVE_PACKAGE_CONFIG:-"$REPOSITORY_ROOT/.retrolive-legacy-build.env"}

fail() {
    printf 'legacy-package: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: scripts/legacy-package.sh <command> [scheme]

Commands:
  doctor            Check the archived packaging environment.
  package [scheme] Build and package an unsigned IPA.
  help              Show this message.

Schemes:
  RetroLiveCamera, RetroLiveClassic, or all (default: RetroLiveCamera)
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
RETROLIVE_PACKAGE_CONFIGURATION=${RETROLIVE_PACKAGE_CONFIGURATION:-Release}
RETROLIVE_PACKAGE_ROOT=${RETROLIVE_PACKAGE_ROOT:-"$REPOSITORY_ROOT/Artifacts"}

case "$RETROLIVE_PACKAGE_CONFIGURATION" in
    Debug|Release) ;;
    *) fail "RETROLIVE_PACKAGE_CONFIGURATION must be Debug or Release" ;;
esac
case "$RETROLIVE_DEVELOPER_DIR" in
    /*) ;;
    *) fail "RETROLIVE_DEVELOPER_DIR must be an absolute path" ;;
esac
case "$RETROLIVE_DERIVED_DATA" in
    /*) ;;
    *) fail "RETROLIVE_DERIVED_DATA must be an absolute path" ;;
esac
case "$RETROLIVE_DERIVED_DATA" in
    "$REPOSITORY_ROOT"|"$REPOSITORY_ROOT"/*)
        fail "RETROLIVE_DERIVED_DATA must be outside the synchronized repository"
        ;;
esac
case "$RETROLIVE_PACKAGE_ROOT" in
    /*) ;;
    *) fail "RETROLIVE_PACKAGE_ROOT must be an absolute path" ;;
esac
[ -x /usr/bin/xcodebuild ] || fail "/usr/bin/xcodebuild is unavailable"
[ -x /usr/bin/zip ] || fail "/usr/bin/zip is unavailable"
[ -x /usr/bin/unzip ] || fail "/usr/bin/unzip is unavailable"
[ -x /usr/bin/shasum ] || fail "/usr/bin/shasum is unavailable"
[ -d "$RETROLIVE_DEVELOPER_DIR" ] ||
    fail "archived toolchain does not exist: $RETROLIVE_DEVELOPER_DIR"
[ -d "$REPOSITORY_ROOT/legacy-camera/RetroLiveCamera.xcodeproj" ] ||
    fail "the synchronized Xcode project is missing"

run_xcodebuild() {
    DEVELOPER_DIR="$RETROLIVE_DEVELOPER_DIR" /usr/bin/xcodebuild "$@"
}

validate_scheme() {
    case "$1" in
        RetroLiveCamera|RetroLiveClassic) ;;
        *) fail "scheme must be RetroLiveCamera or RetroLiveClassic" ;;
    esac
}

package_scheme() {
    scheme=$1
    scheme_derived_data="$RETROLIVE_DERIVED_DATA/$scheme"
    app_path="$scheme_derived_data/Build/Products/${RETROLIVE_PACKAGE_CONFIGURATION}-iphoneos/$scheme.app"
    staging_root=$(mktemp -d "${TMPDIR:-/tmp}/retrolive-package.XXXXXX") ||
        fail "could not create temporary packaging directory"
    trap '/bin/rm -rf "$staging_root"' 0 1 2 3 15

    /bin/mkdir -p "$scheme_derived_data" "$RETROLIVE_PACKAGE_ROOT" ||
        fail "could not create build or package directory"

    printf 'Building unsigned %s with Derived Data at %s\n' \
        "$scheme" "$scheme_derived_data"
    run_xcodebuild \
        -project "$REPOSITORY_ROOT/legacy-camera/RetroLiveCamera.xcodeproj" \
        -scheme "$scheme" \
        -configuration "$RETROLIVE_PACKAGE_CONFIGURATION" \
        -sdk iphoneos \
        -derivedDataPath "$scheme_derived_data" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        build || fail "$scheme unsigned build failed"

    [ -d "$app_path" ] || fail "built application not found: $app_path"
    [ -f "$app_path/Info.plist" ] || fail "built application has no Info.plist: $app_path"

    bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Info.plist") ||
        fail "could not read CFBundleVersion from $app_path"
    short_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Info.plist") ||
        fail "could not read CFBundleShortVersionString from $app_path"
    artifact_name="$scheme-$short_version-build$bundle_version"
    payload_root="$staging_root/Payload"
    ipa_path="$RETROLIVE_PACKAGE_ROOT/$artifact_name.ipa"
    checksum_path="$RETROLIVE_PACKAGE_ROOT/$artifact_name.sha256"
    metadata_path="$RETROLIVE_PACKAGE_ROOT/$artifact_name.txt"

    /bin/mkdir -p "$payload_root" || fail "could not create IPA Payload directory"
    /bin/cp -R "$app_path" "$payload_root/" || fail "could not copy $scheme.app into IPA"
    (
        cd "$staging_root" || exit 1
        /usr/bin/zip -qry "$ipa_path" Payload
    ) || fail "could not create unsigned IPA: $ipa_path"
    /usr/bin/unzip -tq "$ipa_path" >/dev/null 2>&1 ||
        fail "created IPA failed archive validation: $ipa_path"
    (cd "$RETROLIVE_PACKAGE_ROOT" && /usr/bin/shasum -a 256 "$(basename "$ipa_path")") \
        > "$checksum_path" || fail "could not write SHA-256: $checksum_path"

    {
        printf 'scheme=%s\n' "$scheme"
        printf 'configuration=%s\n' "$RETROLIVE_PACKAGE_CONFIGURATION"
        printf 'signed=NO\n'
        printf 'bundle_version=%s\n' "$bundle_version"
        printf 'short_version=%s\n' "$short_version"
        printf 'xcodebuild='; run_xcodebuild -version | tr '\n' ' '; printf '\n'
        printf 'developer_dir=%s\n' "$RETROLIVE_DEVELOPER_DIR"
        printf 'source_root=%s\n' "$REPOSITORY_ROOT"
        printf 'ipa=%s\n' "$ipa_path"
        printf 'sha256_file=%s\n' "$checksum_path"
    } > "$metadata_path" || fail "could not write package metadata: $metadata_path"

    printf 'Created unsigned IPA: %s\n' "$ipa_path"
    printf 'SHA-256: %s\n' "$checksum_path"
    printf 'Metadata: %s\n' "$metadata_path"
    trap - 0 1 2 3 15
    /bin/rm -rf "$staging_root"
}

case "$command_name" in
    doctor)
        [ "$#" -eq 1 ] || fail "doctor does not accept a scheme"
        /usr/bin/sw_vers
        printf '\nArchived toolchain:\n'
        run_xcodebuild -version || fail "could not read the archived Xcode version"
        run_xcodebuild -showsdks || fail "could not list SDKs from the archived Xcode"
        printf '\nDerived Data root: %s\n' "$RETROLIVE_DERIVED_DATA"
        printf 'Package root: %s\n' "$RETROLIVE_PACKAGE_ROOT"
        printf 'Signing: disabled; this script creates an unsigned IPA container.\n'
        ;;
    package)
        [ "$#" -le 2 ] || fail "package accepts at most one scheme"
        scheme=${2:-RetroLiveCamera}
        if [ "$scheme" = all ]; then
            package_scheme RetroLiveCamera
            package_scheme RetroLiveClassic
        else
            validate_scheme "$scheme"
            package_scheme "$scheme"
        fi
        ;;
    *)
        usage >&2
        fail "unknown command: $command_name"
        ;;
esac
