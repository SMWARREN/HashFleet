#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${HASH_FLEET_DIST_DIR:-$ROOT_DIR/dist/hashfleet-mac}"
DERIVED_DATA="${HASH_FLEET_DERIVED_DATA:-$ROOT_DIR/.build/hashfleet-mac-xcode}"
APP_SOURCE="${HASH_FLEET_APP_SOURCE:-$DERIVED_DATA/Build/Products/Release/Hash Fleet.app}"
VALIDATOR="$ROOT_DIR/Scripts/validate-native-mac-app.sh"
CODESIGN="${CODESIGN:-/usr/bin/codesign}"

cd "$ROOT_DIR"

canonicalize_path() {
    local candidate="$1" name parent
    [[ "$candidate" == /* ]] || candidate="$ROOT_DIR/$candidate"
    [[ "$candidate" != / ]] || { printf '/\n'; return; }
    candidate="${candidate%/}"
    name="${candidate##*/}"
    parent="${candidate%/*}"
    [[ -n "$parent" ]] || parent="/"
    while [[ ! -d "$parent" && "$parent" != / ]]; do
        name="${parent##*/}/$name"
        parent="${parent%/*}"
        [[ -n "$parent" ]] || parent="/"
    done
    [[ -d "$parent" ]] || return 1
    parent="$(cd -P "$parent" && pwd)"
    printf '%s/%s\n' "${parent%/}" "$name"
}

OUTPUT_DIR="$(canonicalize_path "$OUTPUT_DIR")" || { echo "Cannot resolve output path parent." >&2; exit 1; }
[[ "$OUTPUT_DIR" == */hashfleet-mac && ! -L "$OUTPUT_DIR" ]] || { echo "Refusing unsafe output path: $OUTPUT_DIR" >&2; exit 1; }

if [[ "${HASH_FLEET_USE_PREBUILT_APP:-0}" == 1 ]]; then
    [[ -n "${HASH_FLEET_APP_SOURCE:-}" ]] || { echo "Prebuilt mode requires HASH_FLEET_APP_SOURCE." >&2; exit 1; }
    echo "Using explicitly selected prebuilt native app: $APP_SOURCE" >&2
else
    [[ -z "${HASH_FLEET_APP_SOURCE:-}" ]] || { echo "HASH_FLEET_APP_SOURCE requires HASH_FLEET_USE_PREBUILT_APP=1." >&2; exit 1; }
    xcodebuild \
        -project HashFleet.xcodeproj \
        -scheme HashFleetMac \
        -configuration Release \
        -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "$DERIVED_DATA" \
        build
fi

[[ -d "$APP_SOURCE" ]] || { echo "Native app not found: $APP_SOURCE" >&2; exit 1; }
APP_SOURCE="$(cd -P "$APP_SOURCE" && pwd)"
case "$APP_SOURCE" in "$OUTPUT_DIR"|"$OUTPUT_DIR"/*) echo "App source cannot be inside output being replaced." >&2; exit 1;; esac
bash "$VALIDATOR" "$APP_SOURCE"

swift build -c release --product hashfleet
CLI_BIN_DIR="$(swift build -c release --show-bin-path)"
CLI_SOURCE="$CLI_BIN_DIR/hashfleet"
[[ -f "$CLI_SOURCE" && -x "$CLI_SOURCE" ]] || { echo "Release CLI missing: $CLI_SOURCE" >&2; exit 1; }

OUTPUT_PARENT="$(dirname "$OUTPUT_DIR")"
mkdir -p "$OUTPUT_PARENT"
STAGE="$(mktemp -d "$OUTPUT_PARENT/.hashfleet-mac-stage.XXXXXX")"
OUTPUT_BACKUP=""
cleanup() {
    local status=$?
    if [[ -n "$OUTPUT_BACKUP" && -d "$OUTPUT_BACKUP" && ! -e "$OUTPUT_DIR" ]]; then
        mv "$OUTPUT_BACKUP" "$OUTPUT_DIR" || echo "WARNING: previous package remains at $OUTPUT_BACKUP" >&2
    fi
    [[ -z "$STAGE" || ! -e "$STAGE" ]] || rm -rf "$STAGE"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
APP_DEST="$STAGE/hashfleet-mac/Hash Fleet.app"
mkdir -p "$(dirname "$APP_DEST")"
ditto "$APP_SOURCE" "$APP_DEST"
mkdir -p "$APP_DEST/Contents/MacOS"
install -m 755 "$CLI_SOURCE" "$APP_DEST/Contents/MacOS/hashfleet"
# Adding code changes the sealed resource envelope. Sign the CLI first without host entitlements,
# then re-seal the host while preserving its own metadata. Avoid --deep while signing because
# the native host and any embedded helper may require different entitlements.
SIGNING_IDENTITY="${HASH_FLEET_CODESIGN_IDENTITY:--}"
"$CODESIGN" --force --sign "$SIGNING_IDENTITY" "$APP_DEST/Contents/MacOS/hashfleet"
"$CODESIGN" --force --preserve-metadata=identifier,entitlements,flags,runtime \
    --sign "$SIGNING_IDENTITY" "$APP_DEST"
bash "$VALIDATOR" "$APP_DEST"

cat > "$STAGE/hashfleet-mac/INSTALL.md" <<'EOF'
# Native Hash Fleet for Mac

This package contains the native macOS `Hash Fleet.app` and its bundled
`hashfleet` CLI at `Contents/MacOS/hashfleet`. It does not contain or install the
iOS/iPad app. See `docs/MAC-NATIVE-INSTALL.md` for installation and signing notes.

Run `Scripts/install-hashfleet-mac.sh` to stage and install the app for the current user.
The separate `Hash Fleet.pkg` performs a system installation into `/Applications`
and exposes the same bundled CLI at `/usr/local/bin/hashfleet`. It installs no helper
app or LaunchAgent. Building a local package does not notarize it for distribution.
EOF
ARCHIVE="$STAGE/Hash Fleet Mac.zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/hashfleet-mac/Hash Fleet.app" "$ARCHIVE"
INSTALLER="$STAGE/Hash Fleet.pkg"
PKG_ROOT="$STAGE/pkgroot"
mkdir -p "$PKG_ROOT/Applications" "$PKG_ROOT/usr/local/bin"
ditto "$APP_DEST" "$PKG_ROOT/Applications/Hash Fleet.app"
ln -s '/Applications/Hash Fleet.app/Contents/MacOS/hashfleet' "$PKG_ROOT/usr/local/bin/hashfleet"
VERSION="$("${PLIST_BUDDY:-/usr/libexec/PlistBuddy}" -c 'Print :CFBundleShortVersionString' "$APP_DEST/Contents/Info.plist")"
[[ -n "$VERSION" ]] || { echo "Missing app version for installer." >&2; exit 1; }
PKG_ARGUMENTS=(--root "$PKG_ROOT" --identifier app.hashfleet.mac --version "$VERSION" --install-location /)
if [[ -n "${HASH_FLEET_INSTALLER_IDENTITY:-}" ]]; then
    PKG_ARGUMENTS+=(--sign "$HASH_FLEET_INSTALLER_IDENTITY")
fi
pkgbuild "${PKG_ARGUMENTS[@]}" "$INSTALLER"
[[ -s "$INSTALLER" ]] || { echo "Native installer was not produced." >&2; exit 1; }

# Only replace the generated distribution directory after a complete validated package exists.
if [[ -e "$OUTPUT_DIR" ]]; then
    OUTPUT_BACKUP="${OUTPUT_DIR}.previous.$$.${RANDOM}"
    mv "$OUTPUT_DIR" "$OUTPUT_BACKUP"
fi
mv "$STAGE/hashfleet-mac" "$OUTPUT_DIR"
STAGE=""
mv "$ARCHIVE" "${OUTPUT_DIR%/*}/Hash Fleet Mac.zip"
mv "$INSTALLER" "${OUTPUT_DIR%/*}/Hash Fleet.pkg"
printf 'Created native macOS app at %s, ZIP at %s and installer at %s\n' "$OUTPUT_DIR" "${OUTPUT_DIR%/*}/Hash Fleet Mac.zip" "${OUTPUT_DIR%/*}/Hash Fleet.pkg"
[[ -z "$OUTPUT_BACKUP" ]] || printf 'Previous distribution retained at %s\n' "$OUTPUT_BACKUP"
rm -rf "$(dirname "$ARCHIVE")"
