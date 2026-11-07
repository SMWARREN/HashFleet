# Production unit coverage swarm, October 8, 2026

**Latest follow-up, 13:14:29 UTC:** `2026-10-08-cancellation-acceptance-recheck.md` records the test-only cancellation observation fix, a fresh 988-pass app/public-UI acceptance, bounded simulator recovery, and the newer Sonar analysis `951ae330` with gate OK, 87.0% new coverage, 55.7% overall coverage, and zero unresolved issues. Its exact current receipt is `2026-10-08-cancellation-fixed-sonar-receipt.json`. The 12:15 publication and its receipt below remain intact historical evidence. Physical-phone acceptance and real hardware writes remain outside the verified result.

## Scope and safety

Request: substantially increase useful unit tests with the swarm and establish the actual Sonar state. Tests exercise production app, Core, and tooling code. Mock URLProtocol cases cover failures and cancellation. UI acceptance launches the real app and navigates its public controls. Its only writes are to an explicitly confirmed loopback HTTP fixture, never a fleet miner.

No hardware settings, firmware flashes, restarts, pools, wiring, recovery limits, secrets, Sonar gate thresholds, coverage exclusions, or new-code baseline were changed. Live account smoke tests remain opt-in and were not enabled.

## Delivered code and tests

- `c3a0444`: ten new app test suites, two new Core suites, production dial-geometry extraction, project registration, and two firmware-check bug fixes.
- `e6483fc`: real SwiftPM physical-line coverage converter and tooling tests. Python `Tools/test_*.py` files are classified as tests. Production tools remain analyzed source.
- `0b91bd7`: the already proven dashboard scrolling body moved unchanged into one `@MainActor` helper. The unified test now uses it only on the tuning screen. All hittability and viewport assertions remain intact, and all eight public workflows pass.
- `deafb4d`: four actual Sonar Python findings resolved by focused parsing helpers and single-throw exception assertions. Postponed annotations retain stock macOS Python 3.9 compatibility.

The app's logical unit count increased from 857 to **980**, an increase of **123 tests**. Two Core suites add **21** logical tests and the coverage converter adds **15** tooling tests, for **159 new logical tests** across those layers. The parameter-expanded app run contains 1,360 executions. Do not add those expanded cases to the logical count.

### Requirement-to-check map

All rows below ran against the actual production implementations through `@testable import HashFleet`, `HashFleetCore`, or the real tooling CLI, not copied implementation code.

| Requirement or changed behavior | Actual suite and explicit checks | Observed result |
|---|---|---|
| Firmware feed checks stay read-only and respect device families, status codes, cache age, concurrent requests, cancellation, and restart persistence | `FirmwareUpdateBoundaryTests`, 24 logical tests. `requestIsReadOnlyGET`, `cacheAgeBoundary`, `futureDatedCacheIsTreatedAsStale`, `cancelledCheckLeavesNoTrace`, concurrent same/different-device checks and corrupt cache cases | All pass in full app units |
| Live monitoring rejects malformed, stale, cached or orphaned frames and merges partial data without losing siblings | `FleetMonitoringBoundaryTests`, 26 tests. Invalid-envelope guards, complete-vs-partial snapshot timestamps, 360-point retention, fresh-key alerting, generation/token cancellation and fallback-poll recovery | All pass |
| Fleet persistence fails closed on corrupt data, preserves recovery bytes, migrates legacy devices, scopes clearing and avoids sensitive storage | `FleetPersistenceBoundaryTests`, 11 tests. Original corrupt store retains failure state; recovered fresh store exports correctly; known-device retention, inbox pruning/dedup and per-device alert corruption cases | All pass |
| Report outputs preserve privacy and spreadsheet safety, connection/freshness classification, subtotal invariants and file lifecycle | `FleetReportBoundaryTests`, 10 tests. Exact privacy header/note, comprehensive formula neutralization, rectangular CSV, temporary attributes and pruning | All pass |
| Telemetry formatting rejects nonfinite or invalid values and respects actual rounding, URL scrubbing and trend boundaries | `FleetTelemetryBoundaryCoverageTests`, 9 tests. Includes `Decimal.nan`, wire difficulty formats and connection/stratum sanitization | All pass |
| Adaptive layouts handle narrow/wide screens, Mac behavior and accessibility text sizes | `FleetAdaptiveBoundaryCoverageTests`, 7 tests. Width boundaries, content-width protections, columns, icon/text scaling and horizontal control decisions | All pass |
| Draft edits survive identical telemetry, restore honestly, clear when returning to baseline and reject invalid wire values | `MinerTuningDraftBoundaryTests`, 6 tests. Negative, NaN, infinite and above-wire-bound values leave state unchanged | All pass |
| Apply performs real preflight, authorization recheck, exact endpoint/payload and honest readback failure reporting | `MinerTuningApplyCoverageTests`, 8 tests. Captures actual streamed JSON body, GET `/api/system/info`, PATCH `/api/system`, exact request counts, cancellation and zero writes after revoked authorization | All pass |
| Production dial geometry clamps, round-trips its sweep, selects bottom-gap endpoints, snaps, chooses major intervals and maps staged drags | `MinerTuningGaugeGeometryTests`, 11 tests. Extracted implementation independently compared against the original, with tight floating-point tolerance rather than rounded-away errors | All pass, 30/30 executable geometry lines covered |
| Journal is newest-first, capped at 12, correctly scoped and safely drops a corrupt blob | `MinerTuningJournalTests`, 11 tests. Missing/non-Data/corrupt payloads, exact return-vs-persisted entries, supplied-list semantics, oversized input and per-device UUID isolation | All pass |
| Core transport, endpoints and firmware wire decoding are faithful at boundaries | `APIClientBoundaryCoverageTests` and `TelemetryDecodingBoundaryTests`, 21 new logical tests. Invalid slots prevent networking, one-request invalid-info rejection, array/error/status handling, scoreboard optionals, URL/WebSocket normalization, counter coercion and zero-divisor derived metrics | Full Core run succeeds; opt-in live cases skipped |
| Coverage conversion never fabricates lines or accepts unsafe paths | `Tools.test_swiftpm_coverage`, 15 new tests, including actual CLI invocation. Rejects traversal, similarly prefixed paths, symlink escapes, stale/out-of-range/invalid DA records, empty/test-only input; unions real duplicate hits | All pass |
| Sonar scan preserves an existing server and refuses unsafe or missing setup | Existing four `Tools.test_sonar_scan` tests run with the new tooling suite | All pass, 19 total Python tests |

## Bugs exposed and fixed

1. A future-dated cached firmware check was incorrectly considered fresh because a negative age is less than the cache interval. The production guard now also requires `checkedAt <= now`. The new regression initially failed, then passed after the fix.
2. URLSession cancellation can report `URLError.cancelled` rather than `CancellationError`. It was recorded as a failed check and throttled a legitimate retry. Production now checks task cancellation after fetch and excludes both cancellation forms from the failure cache. The new no-trace regression initially failed, then passed after the fix.

Neither change writes to miner firmware. Both affect only release-check/cache behavior.

## Real public UI acceptance

Final result bundle: `units-and-tuner-actor-recovered-final.xcresult` under the artifact root below, completed October 8 at 12:13 UTC, exit 0. Its authoritative Xcode summary reports **988 logical tests passed: 980 app units plus eight public UI workflows**, zero failures, zero skips, no expected failures and no runtime warnings. Parameter-expanded executions total 1,368. All 411 Swift source fingerprints match the tested sources.

| Workflow requirement | Public acceptance path and assertion | Final observation |
|---|---|---|
| Unified workspace, live context, ASIC rail reachability, combined staging and remembered acknowledgment | `HashFleetUITests/testUnifiedTuningWorkspaceShowsLiveContextStagesCombinedChangesAndRemembersAcknowledgment` | PASS, 46.348 s |
| One explicitly confirmed loopback write and honest matching/mismatching readback | `DashboardCardInteractionUITests/testCockpitConfirmsOneLoopbackWriteAndReportsReadbackMismatchHonestly` | PASS, 72.060 s |
| First Controls tap survives changed HTTP telemetry while the same menu stays hittable | `DashboardCardInteractionUITests/testCockpitControlsMenuSurvivesHTTPRefreshAndOpensTuner` | PASS, 28.616 s |
| Largest accessibility text keeps both dials, complete FREQ/VCORE deltas and review reachable | `DashboardCardInteractionUITests/testCockpitLargestTextKeepsBothDialsAndReviewReachable` | PASS, 60.480 s |
| Missing voltage does not invent a payload field or disable usable frequency | `DashboardCardInteractionUITests/testCockpitMissingVoltageKeepsFrequencyUsableWithoutInventingPayloadFields` | PASS, 21.619 s |
| Both dials stage together, a real rim drag changes frequency, and restore sends nothing | `DashboardCardInteractionUITests/testCockpitStagesEachDialTogetherAndRestoresWithoutWriting` | PASS, 74.083 s |
| Public Controls route opens the session with correctly numbered ASIC rails | `DashboardCardInteractionUITests/testTuningSessionOpensFromControlsMenuAndShowsNumberedRails` | PASS, 34.579 s |
| Collapsed card opens the unified workspace and demo mode retains its write lock | `MinerCardInteractionUITests/testCollapsedTuningCardOpensUnifiedSessionAndDemoWriteLock` | PASS, 40.415 s |

The preceding current-source run passed 980 units and seven UI workflows. The eighth failed because generic app-center swipes were caught by the dial's own gesture rather than scrolling. The fixed driver starts outside both entire dial frames with 32-point clearance, selects another safe point when the target frame is stationary, uses measured short drags, and retains strict full-viewport/hittability checks. It does not retry menus or weaken assertions.

One earlier bounded shutdown/boot/bootstatus repaired only the owned simulator UUID `5AE0257A-7733-4411-9611-25C576DA2B7E` at 11:47 UTC. No erasure or permission reset occurred. The next full run passed seven workflows and exposed the scrolling-driver bug. The first extracted-driver run was explicitly cancelled after compile diagnostics revealed missing MainActor inheritance. The annotation restores the original actor context. A subsequent run passed all 980 units but failed to initialize its UI runner with a timed-out AX-loaded notification, before any UI case executed. One additional owned-UUID shutdown/boot/bootstatus at 12:06 UTC repaired that infrastructure failure. The unchanged-source rerun then passed all eight workflows. Both failed/cancelled runs and both recovery observations are retained, not represented as passes.

The final real rim drag changed **525 to 675 MHz** with dial frame `(32, 126.333, 338, 338)`, touch start `(201, 160.133)` and endpoint `(336.2, 295.333)`, while asserting zero writes during staging. The final attachment manifest contains 19 PNGs and retained drag-coordinate text. Visually checked settled largest-text screenshot `2C353A29-8331-4A58-B920-6A37C0C2B4AC.png`: FREQ and VCORE each stay intact, with **535 MHz / +10 from 525** and **1155 mV / +5 from 1150** fully readable, without summary clipping. The partially scrolled in-dial caption remains truncated at the largest accessibility size; the complete staged/baseline meaning is carried by the readable summary and verified accessibility labels. No claim is made that every decorative in-dial caption is untruncated.

## Coverage fidelity and measured results

Before the swarm, exact Sonar analysis `f432f1bd-fb45-4432-a06a-99560c766ec2`, processed October 8 at 07:20:37 UTC, reported zero unresolved source issues but a failing 80% new-code coverage gate: **16.4% new coverage**, **37.9% overall coverage**. That analysis imported a bundle with four UI launch failures, so its tuner rendering files had no executed UI coverage.

Fresh app-unit-only measurements from `app-units-5.xcresult`:

| Production file | Actual executable-line coverage |
|---|---:|
| `MinerTuningGaugeGeometry.swift` | 30/30, 100% |
| `FleetStore+Firmware.swift` | 177/178, 99.44% |
| `FleetStore+Persistence.swift` | 431/446, 96.64% |
| `MinerTuningApplyService.swift` | 71/77, 92.21% |
| `MiningDifficultyFormat.swift` | 150/165, 90.91% |
| `FleetStore+Monitoring.swift` | 220/269, 81.78% |

App-unit-only target total is 13,183/51,732, 25.48%. This is not comparable to the prior units-plus-UI total and is not advertised as an overall increase. All-target Xcode aggregate totals also are not the app target total.

The final units-plus-eight-UI **HashFleet.app target** measures **25,186/51,732 executable lines, 48.69%**. In that run `MinerTuningSessionView.swift` is 1,069/1,077 (99.26%), `MinerTuningSessionCards.swift` 540/655 (82.44%), and `MinerTuningGauges.swift` 552/676 (81.66%). The previous baseline app target was 16,031/51,726 (30.99%), from a different selection of UI tests whose launch failed. This improvement reflects both useful new unit coverage and successfully executed real UI paths, not 123 new units alone.

Core's fresh instrumented test binary exports **3,363 covered physical DA lines out of 4,091 across 43 production files**, 82.20%. Every file's line/hit map was independently compared to `llvm-cov show`; all 43 match exactly. LLVM's function/region-expanded LF/LH summary uses a different denominator, so no invented lines are added to make the physical report match that summary. The generic XML imports only actual bounded physical observations.

The final Python converter has **77/78 executable statements covered**, 98.72%. The uncovered line is the conventional module `__main__` guard. Python test files are classified separately from production, and remain analyzed for issues. All 19 tooling tests pass under both stock `/usr/bin/python3` 3.9.6 and current Python 3.14.8. Both interpreters run the real converter CLI on the actual Core LCOV export with byte-identical XML results.

### Exact final Sonar observations

Final analysis **`2ce4079c-8c2c-4f69-b183-c444766a4fc4`**, processed **October 8, 2026 at 12:15:32 UTC**, CE status SUCCESS:

| Metric | Baseline | Final actual observation |
|---|---:|---:|
| New-code coverage | 16.4%, gate ERROR | **87.0%, gate OK**, unchanged minimum 80% |
| Overall coverage | 37.9% | **55.6%** |
| New coverable / uncovered lines | 1,075 / 899 | 1,160 / 151, therefore 1,009 covered |
| Overall coverable / uncovered lines | 29,113 / 18,077 | 32,976 / 14,633, therefore 18,343 covered |
| New source violations | 0 | **0**, unchanged maximum 0 |
| New duplication | 0.0% | **0.0%**, unchanged maximum 3% |
| Unresolved source issues | 0 | **0** |
| Bugs / vulnerabilities / code smells / security hotspots | 0 | **All 0** |

The unchanged new-code period begins October 8 at 03:20:07 UTC. No conditions are ignored. Coverage denominators changed because real Core and Python data and new production code are now included, so the overall comparison is a measured publication improvement, not a controlled unit-only coverage experiment.

An intermediate real scan, `c8178135-fe4c-4a5e-a31f-a34abebfaacc` at 12:09:01 UTC, surfaced four Python issues: cognitive complexity 48 above the allowed 15 in `convert_lcov`, plus three exception assertions with setup calls inside the expected-error block. Those were fixed rather than suppressed. The final scan confirms all four gone and no new issues.

Published per-file components independently reconcile **43 Core files and exactly 3,363/4,091 lines**, and **77/78 converter statements (98.7% rounded by Sonar)**. Sonar's imported test measure is 1,355 with zero test failures. That plugin-derived count is not substituted for Xcode's authoritative 988 logical app/UI tests or 1,368 expanded executions.

## Independent review and reproducibility

Independent reviewer scorpion checked all new suites against production, identified endpoint/preflight fixture errors, verified the two real firmware fixes and coverage fidelity, and reviewed the geometry extraction and journal persistence. It also independently confirmed the final 988 passing app/UI tests, all eight named public workflows, both Python compatibility runs and the actual Core line maps. Its provider failed before examining the final Sonar receipt, so that failure is not counted as final gate signoff.

A separate read-only reviewer, octopus, then checked the exact final server receipt and per-file components, unchanged thresholds and new-code period, permanent JSON equality, and report arithmetic. It returned final Sonar gate signoff with no defects or blockers. The runtime recorded its successful route as native Claude / `claude-opus-4-8`, using configured auto routing with requested high effort. Neither reviewer reran or modified production source during final receipt review. The workers had non-overlapping edit scopes and released ownership before integration.

The configured auto/high model routing was honored. Actual contributors used the approved Gemini, native Claude and NIM Kimi/GLM routes. Failed Nemotron and incomplete DeepSeek assignments are not counted as successful work, and no pool, account, provider or routing policy was redesigned. The routing readiness advisory remains an advisory, not proof of verified inference for every route.

Reproduce from the real project:

```bash
# Real Core package, no private live smoke input.
env -u HASHFLEET_PRIVATE_INFO_FILE swift test --enable-code-coverage

# Real app units and all eight strict public UI workflows.
# Use the owned simulator or a deliberate replacement UUID.
xcodebuild test -project HashFleet.xcodeproj -scheme HashFleetNoAppPush \
  -configuration DebugNoAppPush \
  -destination 'platform=iOS Simulator,id=5AE0257A-7733-4411-9611-25C576DA2B7E' \
  -parallel-testing-enabled NO -enableCodeCoverage YES \
  '-only-testing:HashFleetTests' \
  '-only-testing:HashFleetUITests/HashFleetUITests/testUnifiedTuningWorkspaceShowsLiveContextStagesCombinedChangesAndRemembersAcknowledgment' \
  '-only-testing:HashFleetUITests/DashboardCardInteractionUITests/testCockpitConfirmsOneLoopbackWriteAndReportsReadbackMismatchHonestly' \
  '-only-testing:HashFleetUITests/DashboardCardInteractionUITests/testCockpitControlsMenuSurvivesHTTPRefreshAndOpensTuner' \
  '-only-testing:HashFleetUITests/DashboardCardInteractionUITests/testCockpitLargestTextKeepsBothDialsAndReviewReachable' \
  '-only-testing:HashFleetUITests/DashboardCardInteractionUITests/testCockpitMissingVoltageKeepsFrequencyUsableWithoutInventingPayloadFields' \
  '-only-testing:HashFleetUITests/DashboardCardInteractionUITests/testCockpitStagesEachDialTogetherAndRestoresWithoutWriting' \
  '-only-testing:HashFleetUITests/DashboardCardInteractionUITests/testTuningSessionOpensFromControlsMenuAndShowsNumberedRails' \
  '-only-testing:HashFleetUITests/MinerCardInteractionUITests/testCollapsedTuningCardOpensUnifiedSessionAndDemoWriteLock'

python3 -m unittest Tools.test_swiftpm_coverage Tools.test_sonar_scan -v

# Select fresh matching-source results and actual coverage reports, with a private token.
SONAR_RESULT_BUNDLE=/absolute/path/to/current.xcresult Tools/sonar-scan.sh \
  -Dsonar.coverageReportPaths=build/sonar/core-coverage.xml \
  -Dsonar.python.coverage.reportPaths=build/sonar/python-coverage.xml
```

The original invocation, including isolated build and result paths, is also preserved in the coordinator's background task and log. Swift source fingerprints check that the final result bundle matches every one of the 411 current Swift files.

## Artifact index

Artifact root: `/Users/USER/.jcode/scratch/unit-swarm-20261008/`.

- `app-units-5.{xcresult,log}`, summary/tree/coverage JSON: 980-unit evidence.
- `core-full.log`, `core-full.lcov`, `core-testbinary.json`, `core-all-show.txt`: fresh Core execution and independent physical-line comparison.
- `python-tests-final.log`, `python-tests-system39-final.log`, isolated coverage data and `build/sonar/python-coverage.xml`: actual 19-test tooling runs and compatibility evidence.
- `units-and-tuner-final.{xcresult,log}`: retained 980-unit/7-UI pass with the single original scrolling-driver failure.
- `units-and-tuner-shared-scroll-final.log`: retained cancelled extraction run with actor diagnostics.
- `units-and-tuner-actor-final.{xcresult,log}`: retained UI-runner AX initialization failure, with all 980 app units passed.
- `units-and-tuner-actor-recovered-final.{xcresult,log}`, summary/coverage JSON, 19 exported screenshots, coordinate text and `shared-scroll-actor-frozen-swift-sources.json`: final matching-source 988-pass acceptance.
- `sonar-final-scan.log`, `sonar-final-receipt.json`, `sonar-final-components.json`: exact green final publication and per-file reconciliation. The identical permanent receipt is committed with this report as `docs/reports/2026-10-08-unit-coverage-sonar-receipt.json`.
- `sonar-unit-preflight-{receipt,components}.json`, scan log: retained intermediate four-issue analysis, not the final gate.
- `COVERAGE-AUDIT-REPORT.md`, `sonar-analysis-f432f1bd.json`: independent baseline, with its projections explicitly not treated as final measurements.
- `review/first-pass.md`: independent source and real acceptance review, including failure diagnosis and repairs.
- `review/final-sonar-gate.md`: separate read-only final receipt, thresholds, baseline and component reconciliation signoff, with no blockers.

Compile failures and genuine failed new tests from earlier integration attempts remain in their numbered bundles and logs. Fixture corrections model production contracts; they are not weakened acceptance checks.

## Deployment and remaining limitations

The redesigned tuner was installed in the Mac's Designed-for-iPad **Hash Fleet** app earlier on October 8. The native **Hash Fleet Menu Bar** app is a separate surface. The first delivery check verified binary/runtime identity but could not complete Mac-window interaction. A fresh real-Mac public-path check at **12:43-12:46 UTC** subsequently opened the session from its actual detail quick link, observed both dials and summaries, scrolled to both ASIC rails and the guarded review, confirmed unchanged/unstaged controls and disabled Apply, then returned to the original detail page. This supersedes the earlier window-navigation constraint for those read-only paths, not for physical miner writes. Exact observations and retained screenshots are mapped in `2026-10-08-tuner-real-mac-acceptance.md`. The physical phone still returned version 0.1.0/build 7 at 12:40 and `passcodeRequired: true` at 12:43. No unlock or new foreground launch was attempted, so physical phone tuner acceptance remains unverified.

The full Core framework run reports 246 tests in 26 suites and a successful result. Six guarded live-account/provider cases in four live suites are explicitly skipped and are not claimed as executed live checks.

This unit-test task does not reinstall physical devices. The new firmware-cache fixes are committed and simulator-tested but not claimed as installed on the phone or Mac. Live account smoke tests and real miner writes remain deliberately untested without authorization. Current fleet telemetry and hardware recovery are outside this task.
