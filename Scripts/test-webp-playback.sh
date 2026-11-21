#!/bin/bash
# Compile the real production player and its Swift Testing cases without an app host,
# saved fleet, network calls, Simulator, installation, or operator-display actions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${JCODE_SCRATCH_DIR:-${TMPDIR:-$HOME/.jcode/scratch}}"
WORK="$BASE/hashfleet-webp-$(date -u +%Y%m%dT%H%M%SZ)-$$.noindex"
mkdir -p "$WORK/Sources/HashFleetMac" "$WORK/Tests/PlaybackTests/Resources"
for SOURCE in AnimatedWebPImage WebPFrameStore FleetAnimatedArt; do
    ln -s "$ROOT/App/Design/$SOURCE.swift" "$WORK/Sources/HashFleetMac/$SOURCE.swift"
done
ln -s "$ROOT/MacAppTests/AnimatedWebPPlaybackTests.swift" "$WORK/Tests/PlaybackTests/AnimatedWebPPlaybackTests.swift"
for ASSET in HashFleetBrandLoop FleetClusterArtLoop MinerCoolingArtLoop; do
    cp "$ROOT/App/Resources/Assets.xcassets/$ASSET.dataset/$ASSET.webp" "$WORK/Tests/PlaybackTests/Resources/"
done
cat > "$WORK/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WebPPlaybackChecks", platforms: [.macOS(.v14)], targets: [
    .target(name: "HashFleetMac"),
    .testTarget(name: "PlaybackTests", dependencies: ["HashFleetMac"],
        resources: [.process("Resources")], swiftSettings: [.define("WEBP_STANDALONE_TESTS")])
])
PACKAGE
printf 'Evidence directory: %s\n' "$WORK"
swift test --package-path "$WORK" --scratch-path "$WORK/.build" 2>&1 | tee "$WORK/tests.log"
python3 - "$WORK/tests.log" <<'CHECK'
import pathlib, re, sys
log = pathlib.Path(sys.argv[1]).read_text()
counts = re.findall(r'Test run with (\d+) tests?(?: in \d+ suites?)? passed', log)
if not counts or int(counts[-1]) < 13:
    raise SystemExit('Expected all thirteen actually executed Swift Testing methods, not an empty selector pass')
CHECK
