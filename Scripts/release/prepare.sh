#!/bin/bash
# Compile on the hosted runner before signing credentials enter any build process.
set -euo pipefail
umask 077
: "${RUNNER_TEMP:?}" "${RELEASE_VERSION:?}" "${RELEASE_SHA:?}"
for name in MACOS_CERTIFICATE_P12 MACOS_CERTIFICATE_PASSWORD APPLE_SIGNING_IDENTITY APPLE_TEAM_ID APPLE_API_KEY_P8 APPLE_API_KEY_ID APPLE_API_ISSUER_ID; do
    [[ -z "${!name:-}" ]] || { echo "Refusing to compile with signing secret in environment: $name" >&2; exit 1; }
done
[[ "$(uname -m)" == arm64 && "$(uname -s)" == Darwin ]]
[[ "$(git rev-parse HEAD)" == "$RELEASE_SHA" && "$(cat version.txt)" == "$RELEASE_VERSION" ]]
STAGE="$RUNNER_TEMP/hashfleet-unsigned"
[[ ! -e "$STAGE" ]]
mkdir -m 700 "$STAGE"
xcodebuild -project HashFleet.xcodeproj -scheme HashFleetMac -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$STAGE/mac-derived" \
    -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= \
    ARCHS=arm64 MACOSX_DEPLOYMENT_TARGET=14.0 MARKETING_VERSION="$RELEASE_VERSION" \
    CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" build
ditto "$STAGE/mac-derived/Build/Products/Release/Hash Fleet.app" "$STAGE/Hash Fleet.app"
[[ ! -e "$STAGE/Hash Fleet.app/Contents/MacOS/hashfleet" ]]
[[ ! -d "$STAGE/Hash Fleet.app/Contents/PlugIns" ]]
swift build --scratch-path "$STAGE/cli-build" -c release --arch arm64 --force-resolved-versions --product hashfleet
BIN="$(swift build --scratch-path "$STAGE/cli-build" -c release --arch arm64 --show-bin-path)"
CLI="$STAGE/hashfleet-cli-$RELEASE_VERSION-macos-arm64"
mkdir "$CLI"
cp "$BIN/hashfleet" "$CLI/hashfleet"
ditto "$BIN/GRDB_GRDB.bundle" "$CLI/GRDB_GRDB.bundle"
cp LICENSE "$CLI/LICENSE"
[[ -f "$STAGE/cli-build/checkouts/GRDB.swift/LICENSE" ]]
{ printf 'HashFleet: GPL-3.0\n\n'; cat LICENSE; printf '\n\nGRDB.swift: MIT\n\n'; cat "$STAGE/cli-build/checkouts/GRDB.swift/LICENSE"; } > "$CLI/THIRD_PARTY_NOTICES.txt"
printf '%s\n' "$RELEASE_SHA" > "$STAGE/source-sha.txt"
printf '%s\n' "$RELEASE_VERSION" > "$STAGE/version.txt"
