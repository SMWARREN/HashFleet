#!/bin/bash
# Hosted release runner only. Never installs or launches the Mac app.
set -euo pipefail
umask 077
for name in RUNNER_TEMP RELEASE_VERSION RELEASE_SHA MACOS_CERTIFICATE_P12 MACOS_CERTIFICATE_PASSWORD APPLE_SIGNING_IDENTITY APPLE_TEAM_ID APPLE_API_KEY_P8 APPLE_API_KEY_ID APPLE_API_ISSUER_ID; do
    [[ -n "${!name:-}" ]] || { echo "Missing release setting: $name" >&2; exit 1; }
done
[[ "$(uname -m)" == arm64 && "$(uname -s)" == Darwin ]] || { echo 'Release requires Apple Silicon macOS.' >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$RELEASE_SHA" ]] || { echo 'Source SHA mismatch.' >&2; exit 1; }
[[ "$(cat version.txt)" == "$RELEASE_VERSION" ]] || { echo 'Version mismatch.' >&2; exit 1; }
python3 -B -c 'import os,re; assert re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)",os.environ["RELEASE_VERSION"])'
STAGE="$RUNNER_TEMP/hashfleet-unsigned"
[[ "$(cat "$STAGE/source-sha.txt")" == "$RELEASE_SHA" && "$(cat "$STAGE/version.txt")" == "$RELEASE_VERSION" ]]

WORK="$(mktemp -d "$RUNNER_TEMP/hashfleet-signing.XXXXXX")"
OUT="$RUNNER_TEMP/hashfleet-release"
[[ ! -e "$OUT" ]] || { echo 'Release output already exists.' >&2; exit 1; }
mkdir -m 700 "$OUT"
KEYCHAIN="$WORK/release.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
cleanup() {
    status=$?
    trap - EXIT
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    # WORK is an exclusively-created runner-temp directory, never a user checkout.
    rm -rf "$WORK"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export WORK
python3 -B - <<'PY'
import base64, os
from pathlib import Path
work = Path(os.environ['WORK'])
(work / 'certificate.p12').write_bytes(base64.b64decode(os.environ['MACOS_CERTIFICATE_P12'], validate=True))
(work / 'notary.p8').write_text(os.environ['APPLE_API_KEY_P8'])
PY
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/certificate.p12" -k "$KEYCHAIN" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
rm "$WORK/certificate.p12"

# Compilation already completed in prepare.sh without signing secrets or a keychain.
APP="$WORK/Hash Fleet.app"
ditto "$STAGE/Hash Fleet.app" "$APP"
[[ ! -e "$APP/Contents/MacOS/hashfleet" ]] || { echo 'Public Mac download must not contain the CLI.' >&2; exit 1; }
# This native target has no embedded app extensions. Fail rather than blindly --deep-sign new ones.
[[ ! -d "$APP/Contents/PlugIns" ]] || { echo 'New embedded extensions require signing review.' >&2; exit 1; }
codesign --force --keychain "$KEYCHAIN" --sign "$APPLE_SIGNING_IDENTITY" --options runtime --timestamp \
    --entitlements MacApp/Resources/HashFleet.entitlements "$APP"
bash Scripts/validate-native-mac-app.sh "$APP"
codesign --verify --deep --strict "$APP"

CLI="$WORK/hashfleet-cli-$RELEASE_VERSION-macos-arm64"
ditto "$STAGE/hashfleet-cli-$RELEASE_VERSION-macos-arm64" "$CLI"
codesign --force --keychain "$KEYCHAIN" --sign "$APPLE_SIGNING_IDENTITY" --identifier app.hashfleet.cli --options runtime --timestamp "$CLI/hashfleet"
codesign --verify --strict "$CLI/hashfleet"
for target in "$APP" "$CLI/hashfleet"; do
    details="$(codesign -dv --verbose=4 "$target" 2>&1)"
    printf '%s\n' "$details" | grep -F "TeamIdentifier=$APPLE_TEAM_ID" >/dev/null
    printf '%s\n' "$details" | grep -F 'Authority=Developer ID Application:' >/dev/null
    printf '%s\n' "$details" | grep -F 'Timestamp=' >/dev/null
    printf '%s\n' "$details" | grep -F '(runtime)' >/dev/null
    [[ "$(lipo -archs "$target/Contents/MacOS/Hash Fleet" 2>/dev/null || lipo -archs "$target")" == arm64 ]] || { echo 'Unexpected binary architecture.' >&2; exit 1; }
done

for kind in mac cli; do
    if [[ "$kind" == mac ]]; then target="$APP"; else target="$CLI"; fi
    ditto -c -k --keepParent "$target" "$WORK/$kind-notary.zip"
    xcrun notarytool submit "$WORK/$kind-notary.zip" --key "$WORK/notary.p8" \
        --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" \
        --output-format json --wait --timeout 10m > "$WORK/$kind-notary.json"
    python3 -B -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted", "Notarization was not accepted"' "$WORK/$kind-notary.json"
done
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
codesign --verify --deep --strict "$APP"
codesign --verify --strict "$CLI/hashfleet"
ditto -c -k --keepParent "$APP" "$OUT/HashFleet-$RELEASE_VERSION-macos-arm64.zip"
COPYFILE_DISABLE=1 tar -czf "$OUT/hashfleet-cli-$RELEASE_VERSION-macos-arm64.tar.gz" -C "$WORK" "$(basename "$CLI")"
export OUT
python3 -B - <<'PY'
import hashlib, json, os
from pathlib import Path
out = Path(os.environ['OUT'])
v = os.environ['RELEASE_VERSION']
names = [f'HashFleet-{v}-macos-arm64.zip', f'hashfleet-cli-{v}-macos-arm64.tar.gz']
hashes = {n: hashlib.sha256((out / n).read_bytes()).hexdigest() for n in names}
(out / 'SHA256SUMS.txt').write_text(''.join(f'{hashes[n]}  {n}\n' for n in names))
(out / 'verification.json').write_text(json.dumps({'version': v, 'sha': os.environ['RELEASE_SHA'], 'signed_and_notarized': True, 'sha256': hashes}, indent=2) + '\n')
PY
printf 'Signed, notarized separate app and CLI archives prepared. No installation performed.\n'
