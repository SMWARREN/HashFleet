#!/bin/bash
set -euo pipefail

# Validate a built native macOS app bundle before packaging or installation.
APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "Usage: $0 /path/to/Hash Fleet.app" >&2
    exit 2
fi
INFO="$APP/Contents/Info.plist"
PLIST_BUDDY="${PLIST_BUDDY:-/usr/libexec/PlistBuddy}"
FILE_TOOL="${FILE_TOOL:-/usr/bin/file}"
OTOOL="${OTOOL:-/usr/bin/otool}"
CODESIGN="${CODESIGN:-/usr/bin/codesign}"
fail() { echo "Native macOS app validation failed: $*" >&2; exit 1; }
[[ -f "$INFO" ]] || fail "missing Contents/Info.plist"
[[ ! -L "$APP" && ! -L "$APP/Contents" && ! -L "$INFO" ]] || fail "bundle identity paths must not be symbolic links"
[[ -x "$PLIST_BUDDY" ]] || fail "PlistBuddy is unavailable"
plist_value() { "$PLIST_BUDDY" -c "Print :$2" "$1" 2>/dev/null; }
[[ "$(plist_value "$INFO" CFBundlePackageType)" == APPL ]] || fail "CFBundlePackageType is not APPL"
[[ "$(plist_value "$INFO" CFBundleIdentifier)" == app.hashfleet.mac ]] || fail "unexpected bundle identifier"
[[ "$(plist_value "$INFO" CFBundleExecutable)" == "Hash Fleet" ]] || fail "unexpected executable name"
[[ "$(plist_value "$INFO" CFBundleName)" == "Hash Fleet" ]] || fail "unexpected bundle name"
SUPPORTED="$(plist_value "$INFO" CFBundleSupportedPlatforms)" || fail "missing supported-platform metadata"
[[ "$SUPPORTED" == *MacOSX* ]] || fail "CFBundleSupportedPlatforms does not include MacOSX"
[[ "$SUPPORTED" != *iPhoneOS* && "$SUPPORTED" != *iPhoneSimulator* ]] || fail "iOS platform metadata is present"
if plist_value "$INFO" UIDeviceFamily >/dev/null 2>&1; then fail "iOS device-family metadata is present"; fi
if plist_value "$INFO" LSRequiresIPhoneOS >/dev/null 2>&1; then fail "iOS application requirement metadata is present"; fi
if [[ "$(plist_value "$INFO" LSUIElement || true)" == true ]]; then fail "the workspace must not be an agent-only application"; fi
if PLATFORM_NAME="$(plist_value "$INFO" DTPlatformName 2>/dev/null)"; then
    [[ "$PLATFORM_NAME" == macosx ]] || fail "DTPlatformName is '$PLATFORM_NAME', expected macosx"
fi
if SDK_NAME="$(plist_value "$INFO" DTSDKName 2>/dev/null)"; then
    [[ "$SDK_NAME" != iphone* ]] || fail "iOS SDK metadata is present"
fi
[[ ! -e "$APP/Wrapper" && ! -e "$APP/WrappedBundle" ]] || fail "wrapper bundle layout is prohibited"
NESTED_APP="$(/usr/bin/find "$APP" -mindepth 1 \( -name '*.app' -o -name '*.appex' -o -name Wrapper -o -name WrappedBundle \) -print -quit)"
[[ -z "$NESTED_APP" ]] || fail "nested applications, extensions, and wrappers are prohibited"
EXECUTABLE="$APP/Contents/MacOS/Hash Fleet"
[[ -f "$EXECUTABLE" && -x "$EXECUTABLE" && ! -L "$EXECUTABLE" ]] || fail "missing regular native Contents/MacOS/Hash Fleet executable"
validate_macho() {
    local binary="$1" label="$2" desc commands platforms
    desc="$("$FILE_TOOL" -b "$binary" 2>/dev/null)" || fail "cannot inspect $label executable format"
    [[ "$desc" == *Mach-O* ]] || fail "$label executable is not Mach-O"
    [[ "$desc" != *iOS* ]] || fail "$label executable identifies as iOS"
    commands="$("$OTOOL" -l "$binary" 2>/dev/null)" || fail "cannot inspect $label Mach-O load commands"
    [[ "$commands" == *LC_BUILD_VERSION* ]] || fail "$label Mach-O has no LC_BUILD_VERSION platform marker"
    # Mach-O platform 1 is macOS. Reject iOS/device, simulator, and Catalyst IDs.
    platforms="$(printf '%s\n' "$commands" | awk '
        /cmd LC_BUILD_VERSION/ { in_build=1; next }
        in_build && /platform[[:space:]]+[0-9]+/ { print $2; in_build=0 }
        in_build && /cmd / { in_build=0 }
    ')"
    [[ -n "$platforms" ]] || fail "$label Mach-O platform is unknown"
    while IFS= read -r platform; do
        [[ "$platform" == 1 ]] || fail "$label Mach-O platform is '$platform', expected native macOS (1)"
    done <<< "$platforms"
}
validate_macho "$EXECUTABLE" "main"
CLI="$APP/Contents/MacOS/hashfleet"
if [[ -e "$CLI" ]]; then
    [[ -f "$CLI" && -x "$CLI" && ! -L "$CLI" ]] || fail "bundled CLI is not a regular executable"
    validate_macho "$CLI" "bundled CLI"
fi
[[ -x "$CODESIGN" ]] || fail "codesign is unavailable"
"$CODESIGN" --verify --deep --strict "$APP" >/dev/null 2>&1 || fail "app signature verification failed"
printf 'Validated native macOS app: %s\n' "$APP"
