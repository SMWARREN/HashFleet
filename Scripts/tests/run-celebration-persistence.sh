#!/bin/bash
# Read-only production-source regression runner. No simulator or network access.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OPT="${1:--O}"
case "$OPT" in -O|-Onone) ;; *) echo "Usage: $0 [-O|-Onone]" >&2; exit 2 ;; esac
SCRATCH="${JCODE_SCRATCH_DIR:-$HOME/.jcode/scratch}"
mkdir -p "$SCRATCH"
OUT="$(mktemp -d "$SCRATCH/celebration-persistence.XXXXXX")"
# Extract the actual display model, excluding only its three Core-event adapters and the
# unrelated SwiftUI view. Storage code, payload fields and notification coding stay unchanged.
awk '
/\/\/\/ Full-screen celebration/ { exit }
/^import SwiftUI$/ { print "import Foundation"; next }
/^import HashFleetCore$/ { next }
/^    init\(_ event: MinerBestShareEvent\)/ { skip = 1 }
/^    var eyebrow: String/ { skip = 0 }
!skip { print }
' "$ROOT/App/Features/Celebration/FleetCelebrationView.swift" > "$OUT/FleetCelebrationModel.swift"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="$(uname -m)-apple-macos15.0"
swiftc -sdk "$SDK" -target "$TARGET" "$OPT" -parse-as-library -swift-version 6 -o "$OUT/checks" \
  "$ROOT/App/Features/Celebration/FleetCelebrationQueue.swift" \
  "$ROOT/App/Features/Celebration/FleetCelebrationQueueStorage.swift" \
  "$OUT/FleetCelebrationModel.swift" \
  "$ROOT/Tests/FleetCelebrationPersistenceRegressionTests.swift" \
  "$ROOT/Tests/FleetCelebrationPersistenceRegressionTests+Failures.swift"
"$OUT/checks"
swiftc -sdk "$SDK" -target "$TARGET" "$OPT" -parse-as-library -swift-version 6 -o "$OUT/background-checks" \
  "$ROOT/App/Features/Celebration/FleetCelebrationQueue.swift" \
  "$ROOT/App/Features/Celebration/FleetCelebrationQueueStorage.swift" \
  "$ROOT/App/Features/Celebration/FleetCelebrationQueueFactory.swift" \
  "$ROOT/App/Features/Celebration/FleetCelebrationQueueController.swift" \
  "$OUT/FleetCelebrationModel.swift" \
  "$ROOT/Tests/FleetCelebrationBackgroundRegressionTests.swift"
"$OUT/background-checks" "$OUT/background-databases"
printf "Preserved executable and extracted production model: %s\n" "$OUT"
