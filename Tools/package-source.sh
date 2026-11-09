#!/bin/bash
# Creates an unsigned release from committed files. Audit tracked contents before sharing.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]]; then
    echo "Use a semantic version such as 0.1.0 or 0.1.0-beta.1" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "Commit all source changes first. The archive contains committed files only." >&2
    exit 1
fi

COMMIT="$(git rev-parse --short=12 HEAD)"
ARCHIVE="build/releases/HashFleet-${VERSION}-source-${COMMIT}.zip"
mkdir -p build/releases
if [[ -e "$ARCHIVE" || -e "$ARCHIVE.sha256" ]]; then
    echo "Archive already exists. Refusing to overwrite: $ARCHIVE" >&2
    exit 1
fi
git archive --format=zip --prefix="HashFleet-${VERSION}/" --output="$ARCHIVE" HEAD
(cd build/releases && shasum -a 256 "$(basename "$ARCHIVE")") > "$ARCHIVE.sha256"
echo "Source archive: $ARCHIVE"
cat "$ARCHIVE.sha256"
echo "No signing, upload or publication performed. Only committed files included; audit before sharing."
