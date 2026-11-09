#!/usr/bin/env bash
# Full HashFleet audit recipe. No Sonar publication and no live-miner operations.
# Every independent phase runs, failures remain failures, and prior output is preserved.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="build/swift-sonar-project"
PROJECT="HashFleet.xcodeproj"
IOS_SCHEME="${HF_IOS_SCHEME:-HashFleetNoAppPush}"
MAC_SCHEME="${HF_MAC_SCHEME:-HashFleetMac}"
IOS_DESTINATION="${HF_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1}"
UNIT_DESTINATION="${HF_UNIT_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro Max,OS=26.5}"
MAC_DESTINATION="${HF_MAC_DESTINATION:-platform=macOS}"
if [ -n "${PYTHON:-}" ]; then
  PYTHON="$PYTHON"
elif [ -x "$ROOT/.swift-sonar/python/bin/python" ]; then
  PYTHON="$ROOT/.swift-sonar/python/bin/python"
else
  PYTHON="python3.12"
fi
STATUS=0

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

CHECK_PREREQUISITES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-prerequisites)
      CHECK_PREREQUISITES=1
      shift
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

for tool in xcodebuild xcrun swift; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required."
done

command -v "$PYTHON" >/dev/null 2>&1 || fail "Python interpreter '$PYTHON' was not found."

if ! "$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
  fail "Python interpreter '$PYTHON' is not Python 3.11+. Python 3.11+ is required."
fi

if ! "$PYTHON" -c 'import coverage' >/dev/null 2>&1; then
  fail "Python interpreter '$PYTHON' is missing coverage.py.
To set up an isolated environment with the required dependency, run:
  python3.12 -m venv .swift-sonar/python && .swift-sonar/python/bin/pip install 'coverage==7.17.2'
Or select an existing interpreter using:
  export PYTHON=/path/to/bin/python"
fi

if [ "$CHECK_PREREQUISITES" -eq 1 ]; then
  printf 'Prerequisites satisfied: xcodebuild, xcrun, swift, and %s with coverage are available.\n' "$PYTHON"
  exit 0
fi

[ ! -e "$OUT" ] || fail "$OUT exists. Move it aside deliberately before rerunning."
mkdir -p "$OUT"

run_step() {
  local label="$1" code=0
  shift
  printf '\n==> %s\n' "$label"
  if "$@" > "$OUT/$label.log" 2>&1; then
    printf 'PASS %s\n' "$label"
  else
    code=$?
    STATUS=1
    printf 'FAIL %s (exit %s), preserving evidence and continuing independent checks\n' "$label" "$code"
    tail -30 "$OUT/$label.log"
  fi
  printf '%s\t%s\n' "$label" "$code" >> "$OUT/phase-exits.tsv"
}

# Fresh build products avoid accidentally testing a previously installed app.
run_step ios-build xcodebuild build-for-testing -quiet -project "$PROJECT" \
  -scheme "$IOS_SCHEME" -destination "$IOS_DESTINATION" \
  -derivedDataPath "$OUT/ios-derived" -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO

run_unit_shard() {
  local index="$1" cls classes destination="$UNIT_DESTINATION"
  if [ "$index" = 3 ]; then destination="$IOS_DESTINATION"; fi
  classes="$("$PYTHON" -c 'import json, sys; tests = json.load(open(sys.argv[1], encoding="utf-8")); print("\n".join(sorted({test.split("/", 1)[0] for test in tests})))' "Tools/sonar-test-identities-unit-$index.json")" || return
  local only=()
  while IFS= read -r cls; do
    [ -n "$cls" ] && only+=("-only-testing:HashFleetTests/$cls")
  done <<< "$classes"
  [ "${#only[@]}" -gt 0 ] || return 1
  # Keep xcresults, screenshots and assertion failures. Automatic sysdiagnose
  # collection repeatedly stalled for 600 seconds after the test worker finished.
  xcodebuild test-without-building -quiet -collect-test-diagnostics never -project "$PROJECT" -scheme "$IOS_SCHEME" \
    -destination "$destination" -derivedDataPath "$OUT/ios-derived" \
    -parallel-testing-enabled NO -enableCodeCoverage YES \
    -resultBundlePath "$OUT/unit-$index.xcresult" "${only[@]}" CODE_SIGNING_ALLOWED=NO
}
for shard in 1 2 3; do run_step "ios-unit-$shard" run_unit_shard "$shard"; done

run_step mac-tests xcodebuild test -quiet -collect-test-diagnostics never -project "$PROJECT" -scheme "$MAC_SCHEME" \
  -destination "$MAC_DESTINATION" -derivedDataPath "$OUT/mac-derived" \
  -parallel-testing-enabled NO -enableCodeCoverage YES \
  -resultBundlePath "$OUT/mac.xcresult" CODE_SIGNING_ALLOWED=NO

run_step tuning-ui xcodebuild test-without-building -quiet -collect-test-diagnostics never -project "$PROJECT" \
  -scheme "$IOS_SCHEME" -destination "$IOS_DESTINATION" -derivedDataPath "$OUT/ios-derived" \
  -parallel-testing-enabled NO -enableCodeCoverage YES -resultBundlePath "$OUT/ui.xcresult" \
  -only-testing:HashFleetUITests/DashboardCardInteractionUITests/testEasyFrequencyConfirmsOneFrequencyOnlyLoopbackWrite \
  -only-testing:HashFleetUITests/DashboardCardInteractionUITests/testEasyFrequencySafetyAndApplyAreVisibleWithoutScrolling \
  -only-testing:HashFleetUITests/DashboardCardInteractionUITests/testEasyLargeTextKeepsSafetyAndApplyAdjacentBeforeTechnicalDetails \
  -only-testing:HashFleetUITests/DashboardCardInteractionUITests/testEasyPairConfirmsOneCombinedLoopbackWriteAndRejectsInvalidInput \
  -only-testing:HashFleetUITests/PhoneTuningAndTelemetryUITests/testEasyDirectFrequencyAndAdvancedUseTheSameGuardedDraft \
  -only-testing:HashFleetUITests/PhoneTuningAndTelemetryUITests/testEasyDirectVoltageAndAdvancedKeepAVoltageOnlyDraft \
  -only-testing:HashFleetUITests/PhoneTuningAndTelemetryUITests/testEasyPairCommitsOnFocusChangeAndResetClearsInvalidText \
  CODE_SIGNING_ALLOWED=NO

# Includes the retained ticker assertion failure. Never reinterpret it as a pass,
# and never abort the remaining audit merely because this known failure recurs.
run_step broader-ui xcodebuild test-without-building -quiet -collect-test-diagnostics never -project "$PROJECT" \
  -scheme "$IOS_SCHEME" -destination "$IOS_DESTINATION" -derivedDataPath "$OUT/ios-derived" \
  -parallel-testing-enabled NO -enableCodeCoverage YES -resultBundlePath "$OUT/broader-ui.xcresult" \
  -only-testing:HashFleetUITests/CompactDashboardUITests/testAccessibilityTickerExposesStaticUntruncatedMinerSummaries \
  -only-testing:HashFleetUITests/CompactDashboardUITests/testExactNumericBestShareRendersAs392MThroughNativeTransport \
  -only-testing:HashFleetUITests/CompactDashboardUITests/testFleetToolsAndMinerControlsAreExplicitlyDiscoverable \
  CODE_SIGNING_ALLOWED=NO

# Keep the normal-size, scrolling, motion, accessibility and Session Support checks
# in the same source-bound audit, rather than relying on an earlier focused run.
run_step support-ui xcodebuild test-without-building -quiet -collect-test-diagnostics never -project "$PROJECT" \
  -scheme "$IOS_SCHEME" -destination "$IOS_DESTINATION" -derivedDataPath "$OUT/ios-derived" \
  -parallel-testing-enabled NO -enableCodeCoverage YES -resultBundlePath "$OUT/support.xcresult" \
  -only-testing:HashFleetTests/FleetInformationPageViewportTests \
  -only-testing:HashFleetUITests/DeveloperSupportUITests CODE_SIGNING_ALLOWED=NO

run_step native-merge xcrun xcresulttool merge \
  "$OUT/unit-1.xcresult" "$OUT/unit-2.xcresult" "$OUT/unit-3.xcresult" \
  "$OUT/mac.xcresult" "$OUT/ui.xcresult" "$OUT/broader-ui.xcresult" "$OUT/support.xcresult" \
  --output-path "$OUT/merged.xcresult"

# Dedicated scratch storage plus exact output paths prevent stale-profile selection.
# Xcode and SwiftPM share the root lockfile. Preserve its complete app graph,
# including app-only Lucide, rather than pruning it halfway through a bound audit.
SWIFTPM_LOCK=(--force-resolved-versions --skip-update)
run_step swiftpm-tests swift test "${SWIFTPM_LOCK[@]}" --scratch-path "$OUT/swiftpm" --enable-code-coverage
export_swift_coverage() {
  local bin profile binary
  bin="$(swift build "${SWIFTPM_LOCK[@]}" --scratch-path "$OUT/swiftpm" --show-bin-path)" || return
  profile="$bin/codecov/default.profdata"
  binary="$bin/HashFleetCoreTests.xctest/Contents/MacOS/HashFleetCoreTests"
  if [ ! -f "$binary" ]; then
    binary="$bin/HashFleetCorePackageTests.xctest/Contents/MacOS/HashFleetCorePackageTests"
  fi
  [ -f "$profile" ] && [ -f "$binary" ] || return 1
  xcrun llvm-cov export --format=lcov -instr-profile "$profile" "$binary" > "$OUT/package.lcov" || return
  "$PYTHON" Tools/swiftpm_coverage.py "$OUT/package.lcov" "$OUT/swift-package-coverage.xml" --root "$ROOT"
}
run_step swiftpm-coverage export_swift_coverage
run_step cli-release swift build "${SWIFTPM_LOCK[@]}" --scratch-path "$OUT/swiftpm" -c release --product hashfleet
CLI_BIN="$(swift build "${SWIFTPM_LOCK[@]}" --scratch-path "$OUT/swiftpm" -c release --show-bin-path)/hashfleet"

export COVERAGE_FILE="$ROOT/$OUT/.coverage"
# Match sonar.test.inclusions: named test modules are tests, while the explicit
# native_mac_*_smoke entry points remain production tooling and need real coverage.
COVERAGE=("$PYTHON" -m coverage run --append --branch --source=Tools,Scripts '--omit=Tools/test_*,Scripts/tests/test_*')
run_step python-tools "${COVERAGE[@]}" -m unittest discover -s Tools -p 'test_*.py' -v
# These are script entry points that initialize their executable fixture from
# --binary. Generic pytest collection would omit that initialization.
for suite in dashboard settings firmware_activity; do
  run_step "cli-$suite" "${COVERAGE[@]}" "Scripts/tests/test_cli_$suite.py" --binary "$CLI_BIN"
done
run_step mac-packaging "${COVERAGE[@]}" Scripts/tests/test_package_hashfleet_mac.py
run_step python-coverage "$PYTHON" -m coverage xml -o "$OUT/python-coverage.xml"

if [ "$STATUS" -eq 0 ]; then
  printf '\nAll configured phases passed. No scan was published.\n'
else
  printf '\nAudit FAILED. Phase results and failed native evidence retained in %s. No scan was published.\n' "$OUT"
fi
exit "$STATUS"
