#!/bin/sh

# Runs on the archived build Mac through `ssh ... /bin/sh -s`. Keep this file
# compatible with the POSIX shell shipped by OS X Mavericks.

set -u

fail() {
    printf 'legacy-remote: %s\n' "$*" >&2
    exit 1
}

require_absolute_path() {
    path_value=$1
    path_label=$2

    case "$path_value" in
        /*/*/*) ;;
        *) fail "$path_label must be an absolute, dedicated path at least three components deep" ;;
    esac

    case "$path_value" in
        /|/Users|/Users/*|/Volumes|/Volumes/*)
            # The first pattern accepted above already rejects the shallow
            # forms. Keep the explicit list here as a second safety boundary.
            case "$path_value" in
                /Users/*/*|/Volumes/*/*/*) ;;
                *) fail "$path_label is too broad: $path_value" ;;
            esac
            ;;
    esac
}

require_safe_mirror_root() {
    mirror_root=$1
    require_absolute_path "$mirror_root" "remote mirror root"
    case "$mirror_root" in
        *[!A-Za-z0-9_./-]*)
            fail "remote mirror root may contain only letters, numbers, underscore, dot, slash, and hyphen"
            ;;
    esac
}

require_mirror() {
    mirror_root=$1
    require_safe_mirror_root "$mirror_root"
    [ -f "$mirror_root/.retrolive-build-mirror" ] ||
        fail "remote mirror is not initialized; run 'legacy-remote.sh init' first"
}

run_xcodebuild() {
    developer_dir=$1
    shift

    [ -x /usr/bin/xcodebuild ] || fail "/usr/bin/xcodebuild is unavailable"
    DEVELOPER_DIR="$developer_dir" /usr/bin/xcodebuild "$@"
}

command_name=${1:-}
[ -n "$command_name" ] || fail "missing worker command"
shift

case "$command_name" in
    init)
        remote_root=$1
        derived_data=$2
        require_safe_mirror_root "$remote_root"
        require_absolute_path "$derived_data" "remote derived-data path"

        if [ -d "$remote_root" ] &&
           [ ! -f "$remote_root/.retrolive-build-mirror" ] &&
           [ -n "$(/bin/ls -A "$remote_root" 2>/dev/null)" ]; then
            fail "refusing to initialize a non-empty directory: $remote_root"
        fi

        /bin/mkdir -p "$remote_root/legacy-camera" "$derived_data" ||
            fail "could not create remote build directories"
        : > "$remote_root/.retrolive-build-mirror" ||
            fail "could not create the remote mirror marker"
        printf 'Initialized source mirror: %s\n' "$remote_root"
        printf 'Initialized build output: %s\n' "$derived_data"
        ;;

    verify-mirror)
        require_mirror "$1"
        ;;

    metadata)
        remote_root=$1
        revision=$2
        source_state=$3
        synced_at=$4
        require_mirror "$remote_root"
        {
            printf 'revision=%s\n' "$revision"
            printf 'source_state=%s\n' "$source_state"
            printf 'synced_at=%s\n' "$synced_at"
        } > "$remote_root/.retrolive-source-state" ||
            fail "could not write source metadata"
        ;;

    doctor)
        remote_root=$1
        derived_data=$2
        developer_dir=$3
        signing_xcconfig=$4
        signing_allowed=$5

        printf '%s\n' 'Remote host:'
        /usr/bin/sw_vers || fail "could not read macOS version"
        printf '\n%s\n' 'Archived toolchain:'
        run_xcodebuild "$developer_dir" -version || fail "Xcode is not usable"
        run_xcodebuild "$developer_dir" -showsdks || fail "could not list installed SDKs"

        printf '\n%s\n' 'Build paths:'
        printf '  mirror:       %s\n' "$remote_root"
        printf '  derived data: %s\n' "$derived_data"
        require_mirror "$remote_root"
        require_absolute_path "$derived_data" "remote derived-data path"

        if [ "$signing_xcconfig" != "-" ]; then
            [ -f "$signing_xcconfig" ] ||
                fail "signing xcconfig does not exist: $signing_xcconfig"
            printf '  xcconfig:     %s\n' "$signing_xcconfig"
        else
            printf '  xcconfig:     not configured\n'
        fi

        printf '\nCode signing identities:\n'
        /usr/bin/security find-identity -v -p codesigning || true
        printf 'CODE_SIGNING_ALLOWED=%s\n' "$signing_allowed"

        ;;

    build)
        remote_root=$1
        derived_data=$2
        developer_dir=$3
        scheme=$4
        configuration=$5
        signing_allowed=$6
        signing_xcconfig=$7

        require_mirror "$remote_root"
        require_absolute_path "$derived_data" "remote derived-data path"
        [ -d "$remote_root/legacy-camera/RetroLiveCamera.xcodeproj" ] ||
            fail "the Xcode project has not been synchronized"

        case "$scheme" in
            RetroLiveCamera|RetroLiveClassic) ;;
            *) fail "unsupported scheme: $scheme" ;;
        esac
        case "$configuration" in
            Debug|Release) ;;
            *) fail "unsupported configuration: $configuration" ;;
        esac
        case "$signing_allowed" in
            YES|NO) ;;
            *) fail "RETROLIVE_CODE_SIGNING_ALLOWED must be YES or NO" ;;
        esac

        if [ "$signing_xcconfig" != "-" ]; then
            [ -f "$signing_xcconfig" ] ||
                fail "signing xcconfig does not exist: $signing_xcconfig"
            set -- -project "$remote_root/legacy-camera/RetroLiveCamera.xcodeproj" \
                -scheme "$scheme" -configuration "$configuration" \
                -sdk iphoneos -derivedDataPath "$derived_data" \
                -xcconfig "$signing_xcconfig" \
                CODE_SIGNING_ALLOWED="$signing_allowed" build
        else
            set -- -project "$remote_root/legacy-camera/RetroLiveCamera.xcodeproj" \
                -scheme "$scheme" -configuration "$configuration" \
                -sdk iphoneos -derivedDataPath "$derived_data" \
                CODE_SIGNING_ALLOWED="$signing_allowed" build
        fi

        log_dir="$derived_data/RetroLiveLogs"
        /bin/mkdir -p "$log_dir" || fail "could not create build log directory"
        log_file="$log_dir/${scheme}-${configuration}-$(date -u '+%Y%m%dT%H%M%SZ').log"

        printf 'Building %s (%s); remote log: %s\n' "$scheme" "$configuration" "$log_file"
        if run_xcodebuild "$developer_dir" "$@" > "$log_file" 2>&1; then
            /bin/cat "$log_file"
            printf 'BUILD SUCCEEDED: %s\n' "$scheme"
        else
            build_status=$?
            /bin/cat "$log_file"
            printf 'BUILD FAILED: %s (status %s)\n' "$scheme" "$build_status" >&2
            exit "$build_status"
        fi
        ;;

    *)
        fail "unknown worker command: $command_name"
        ;;
esac
