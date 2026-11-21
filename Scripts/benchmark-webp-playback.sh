#!/bin/bash
# Isolated forced-first-draw comparison. Does not launch Hash Fleet, touch saved
# preferences/miners, install an app, or create/activate a display window.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${JCODE_SCRATCH_DIR:-${TMPDIR:-$HOME/.jcode/scratch}}"
WORK="$BASE/hashfleet-webp-benchmark-$(date -u +%Y%m%dT%H%M%SZ)-$$.noindex"
mkdir -p "$WORK"
printf 'Benchmark evidence: %s\n' "$WORK"
xcrun swiftc -O -swift-version 6 -parse-as-library \
    "$ROOT/App/Design/WebPFrameStore.swift" "$ROOT/Tools/benchmark_webp_playback.swift" \
    -o "$WORK/webp-render-benchmark"
"$WORK/webp-render-benchmark" "$ROOT" | tee "$WORK/results.json"
