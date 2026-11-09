# Offline chart lifetime lab

## Scope and safety

`Scripts/ChartLifetimeLab.swift` is a diagnostic entry point, not a shipping target member. It mounts the production `FleetHistoryCard.historyChart` or the complete history card with synthetic data. It does not construct the production app, store, monitoring runtime, widget coordinator, or hardware-control gate. Full-card fixtures use `isDemo: true`, which skips stored-history loading. Fixture addresses use the reserved `.invalid` domain.

The runner refuses a bundle identifier outside `app.hashfleet.chartlab.*`. Never replace an installed production app, launch the normal app to run this benchmark, reset a simulator, or contact miners as part of this test. Native Mac tests must retain the sandbox and use only the diagnostic app's container for output. The phone installation is a separate workflow.

## What was fixed

The compact point budget is **per displayed series**, not per recording segment. Previously, a fleet aggregate with 128 recording segments could plot 6,144 points despite its 48-point dashboard budget. A detail chart could similarly exceed its 180-point budget.

`FleetHistoryChartSeries` now produces one immutable, bounded rendering payload. It establishes real recording segments before sampling, samples across the entire series, and maps the sampled subsequence back to its original segment IDs. This also avoids inventing gaps when a continuous day's downsampled points are more than five minutes apart. Real gaps and rejected fleet alignments still break lines. Very sparse segments may be omitted at compact resolution. The original histories remain available for full-resolution inspection and storage.

Selection continues to use the original history. The custom overlay remains the sole selection owner. This change does not reintroduce Swift Charts' competing built-in x-selection recognizer.

## October 29, 2026 investigation

The original incident was HashFleet 0.1.0 build 7 on the iOS 27.0 simulator, hosted by macOS 26.6.2. Its main-thread stack entered Charts, SwiftUI and AttributeGraph before `SIGABRT`. The simulator's unified log supplied the missing reason at **18:06:11 UTC**:

```text
com.apple.attributegraph: precondition failure: exhausted data space
```

This is an application abort. The report's virtual-allocation totals are not measurements of resident memory. The confirmed rendering-budget defect has **not** been established as the cause of that incident. The original abort was not reproduced in the bounded tests below. A permanent cure, ten-hour stability, phone stability, and simulator-only causation are not claimed.

### Recorded real-framework tests

The frozen baseline was commit `18f409c65a592cc184ece91e109e60f880d9756f`. The repaired source was that exact baseline plus the scoped rendering changes. Pre-existing working-tree optimizations, including per-mark accessibility removal, page-height rounding and merge changes, were excluded from the comparison.

| Case | Runtime | Completed updates | Distinct root revisions | Physical footprint, start to finish |
| --- | --- | ---: | ---: | ---: |
| Baseline single series with selection | iOS 27.0 simulator | 2,000 | 2,001 | 21.99 to 23.68 MB |
| Baseline complete history card | iOS 27.0 simulator | 10,000 | 10,001 | 23.94 to 24.12 MB |
| Baseline fragmented aggregate | iOS 27.0 simulator | 100 | 101 | 50.97 to 41.42 MB |
| Repaired fragmented aggregate | iOS 27.0 simulator | 100 | 101 | 21.74 to 22.61 MB |
| Repaired complete history card | iOS 27.0 simulator | 10,000 | 10,001 | 23.94 to 24.07 MB |
| Repaired detail, selection, windows and remounts | iOS 26.5 simulator | 5,000 | 5,001 | 33.64 to 33.79 MB |

MB means decimal megabytes of `TASK_VM_INFO.phys_footprint`, not virtual allocation. The fragmented baseline settled near 41.4 MB after initialization. Both sides of that comparison used the same simulator and profiling-enabled Debug configuration. These measurements include the diagnostic host. They are evidence for the fixture, not general production-memory guarantees.

The direct detail test cycles selected/unselected marks every ten updates, all four window formats every hundred updates, and chart remounts every 250 updates. These are programmatic state transitions, not physical gesture acceptance. Full-card mode exercises the real pager, height preferences, data caches and chart as a mounted view.

The iOS chart/history regression selection passed **73 tests in five suites on each of iOS 27.0 and iOS 26.5**. The iOS 26.5 run was the final verifier after restoring the unchanged repaired sampler from the negative control. Native macOS validation passed **16 tests in three suites**, including a real Charts/ImageRenderer plot-containment check with a deliberately unclipped positive control. A native windowed lifetime run emitted no chart checkpoints because this environment could not present its window. It was stopped and is **not** counted as passed. Two independent review workers failed before delivering a review. No provider, account or routing settings were changed to bypass those failures.

Reintroducing the old per-segment sampler in an isolated negative control produced ten assertion issues, including 6,144 plotted points versus 48 and 12,288 versus 180. The final sampler was restored unchanged. After the assertions finished, test-result packaging hung and the command timed out at 300 seconds with exit 124. There is no complete XCResult for that negative control. Only the observed assertion failures establish its sensitivity, not a completed test-command receipt.

Private crash, build, JSON and test-result receipts are retained under the operator's Jcode scratch directory. No wallet addresses, credentials or live fleet telemetry belong in committed receipts.

## Reproduce safely

1. Create a private source snapshot under `$JCODE_SCRATCH_DIR`, or the operator's approved Jcode scratch directory. Archive the exact revision to compare. Do not copy an unreviewed dirty workspace over it.
2. **In the snapshot only**, change the project bundle-identifier prefix from `app.hashfleet` to `app.hashfleet.chartlab`, including test and extension identifiers. Do not edit shipping identifiers in the working repository.
3. Remove only `@main` from the snapshot's existing `HashFleetApp` type, retaining the type for its existing extensions. Append `Scripts/ChartLifetimeLab.swift` to that entry file. For iOS this is `App/HashFleetApp.swift`. For native Mac this is `MacApp/HashFleetMacApp.swift`. The original app type must never be instantiated by the diagnostic entry.
4. Use an already booted simulator and a separate derived-data directory. Resolve only the repository's pinned package versions. Keep the same configuration and coverage settings on both sides of a memory comparison.
5. Build and install **only** the isolated bundle. Confirm its actual `CFBundleIdentifier` before installation or launch.

Example simulator build, with operator-provided snapshot, package-cache and simulator paths:

```bash
xcodebuild -project "$LAB/HashFleet.xcodeproj" \
  -scheme HashFleetNoAppPush -configuration DebugNoAppPush \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$ROOT/derived" \
  -clonedSourcePackagesDirPath "$PACKAGES" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO build

xcrun simctl install "$SIM" \
  "$ROOT/derived/Build/Products/DebugNoAppPush-iphonesimulator/HashFleet.app"

xcrun simctl launch --console-pty "$SIM" app.hashfleet.chartlab.app \
  --chart-updates 100 --fragmented --exit-on-complete
```

The default simulator result is `Documents/chart-lab-result.json` inside the diagnostic app's container. Copy each completed run to a uniquely named private receipt before the next run overwrites that diagnostic-only file. Validate the JSON's requested and completed updates, arguments, runtime, sample statuses and rendered count. A launch command returning success is not sufficient proof that the test passed.

### Runner options

- `--chart-updates N`: clamp to 1 through 20,000 updates, default 2,000. Each update yields at least 22 ms so work can reach Swift Charts.
- `--single-series`: one line and area instead of four miner lines.
- `--fragmented`: 12,288 points across 128 real recording segments. Use for a compact aggregate rendering-cap comparison.
- `--detail`: use the 180-point detail budget.
- `--selection`: alternate selected and unselected marks.
- `--windows`: cycle daily, weekly, monthly and yearly axis formats.
- `--remount`: recreate the chart/card subtree every 250 updates, retaining the diagnostic model.
- `--no-axes`: direct-chart diagnostic control only.
- `--full-card`: mount the complete production history card. It cannot be combined with direct-chart-only options `--fragmented`, `--selection`, `--windows` or `--no-axes`.
- `--result-path PATH`: write a new receipt without overwriting an existing file. Required on macOS. Use a unique path under the sandboxed diagnostic app's own container, never the user's real Documents folder.
- `--exit-on-complete`: terminate the diagnostic app after reporting. A non-passing run exits nonzero. Always inspect the JSON and console because launch wrappers may not propagate application exit codes.

Failure-path checks confirmed that incompatible full-card options report `CHART_LAB_FAILED` without a completion message, and that an unwritable result path does not silently succeed. The simulator launch wrapper returned zero even when the app rejected its options, confirming why console and JSON validation are necessary.

The runner stops if a sampled physical footprint exceeds 256 MiB or memory measurement fails. A passing receipt requires all updates, valid measurements, no memory-limit stop and at least 95% distinct root revisions. This is a bounded growth/survival test, not a private AttributeGraph node-count profiler.

## Requirement-to-check map

| Requirement | Check |
| --- | --- |
| One budget across fragmented history | `FleetHistoryChartBudgetTests`, including the old per-segment positive control |
| Empty, negative, one, two, odd and large budgets | Parameterized point/segment boundary tests |
| No invented gaps or bridged interruptions | Continuous-day and explicit-alignment-interruption regressions |
| Stable series identity and full-resolution inspection | One hundred rolling payloads with selection of omitted rendering samples |
| Existing merges, caches and fleet alignment unchanged | Existing history, aggregation, selection and storage tests |
| Repeated actual Swift Charts updates | Offline simulator matrices with frame intervals, memory samples and distinct root-revision counts |
| Native plot containment unchanged | Native Charts/ImageRenderer test and intentionally unclipped positive control |
| No silent result-write or incomplete-run success | Runner's explicit failure output and JSON `complete` field |
| No production data or mining operations | Frozen source, diagnostic bundle guard, inert unit-test entry and synthetic demo fixtures |

## Remaining risk

Keep the original AttributeGraph incident open until a representative long-session reproduction or matched cause-and-effect/allocation trace identifies its mechanism. If it recurs, capture the exact app build, runtime, visible window, selected range, number of series/segments, physical footprint over time, unified-log precondition message and original crash report. Do not work around an unproven framework problem by restarting hardware, changing miner settings, or resetting production app storage.
