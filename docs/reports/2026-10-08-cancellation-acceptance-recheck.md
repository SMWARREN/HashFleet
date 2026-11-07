# Cancellation observation fix and final acceptance recheck

October 8, 2026. All times below are UTC. This follow-up supersedes the earlier 12:15 Sonar publication for current dashboard status, while retaining that receipt and every failed run as historical evidence.

## Scope and delivered fix

The whole-result recheck of the unit-test expansion exposed a test-side race in `FirmwareUpdateBoundaryTests.cancelledCheckLeavesNoTrace`. The app task can finish after URLSession throws `URLError.cancelled`, before the separate `URLProtocol.stopLoading()` callback updates the test registry. Observing the cancellation count immediately after `await task.value` therefore sometimes read zero. The no-notice, no-persistence, and immediate-retry production assertions still passed.

Commit **`a5c280c`** adds seven lines in `AppTests/FirmwareUpdateBoundaryTests.swift:726-732`: a comment and the existing bounded `waitUntil` helper around the actual cancellation observation. The strict `== 1` assertion and every no-trace/retry assertion are unchanged. The helper polls the lock-protected per-test registry, yields the main actor, and fails with a recorded issue after five seconds if the callback never arrives. This is not a fixed-delay workaround, operation retry, or relaxed expectation.

No production, Core, tooling, Sonar configuration, hardware, pool, firmware, recovery, voltage, frequency, fan, or wiring change was made in this follow-up. UI writes target only the explicitly confirmed loopback fixture.

## Requirement-to-observation map

| Requirement | Concrete check | Observed result |
|---|---|---|
| A cancelled release check is actually torn down exactly once, leaves no notice or persisted failure, and permits an immediate retry | Targeted `cancelledCheckLeavesNoTrace()` with `-test-iterations 20`, then the complete app run | All 20 repetitions passed; the same strict test also passed in both complete post-fix app-unit runs |
| Test synchronization is bounded and actor-safe without hiding a real missing callback | Review of `waitUntil`, `noteStopped`, registry lock, main-actor suite and unchanged assertions | No defects in root and independent read-only review; strict SwiftLint returned zero violations |
| The whole app and all eight public tuner workflows remain valid | Complete `HashFleetNoAppPush` / `DebugNoAppPush` run with code coverage, serial UI execution and unchanged acceptance assertions | **988 logical passes: 980 app units plus eight public UI workflows**, zero failures, skips, expected failures or runtime warnings; 1,368 parameter-expanded executions |
| Final results correspond to the current source, not a stale binary | SHA-256 manifest of all 415 Git-tracked `.swift` files before and after testing and before scanning | Exact match; compared with the earlier 411-file manifest, the four additional tracked paths are `Package.swift`, two Swift tooling scripts and the logo-research Swift helper |
| Real Core and Python coverage is preserved, not estimated | Existing fresh post-map Core run and physical-line reconciliation, byte comparison of its XML with the imported XML, fresh stock-Python tooling run and final Sonar components | Core framework reports 246 tests in 26 suites with six opt-in live cases skipped; 43 files reconcile to 3,363/4,091 covered lines; all 19 tooling tests pass on stock macOS Python 3.9; converter coverage remains 77/78 statements |
| Publish the actual accepted app bundle without weakening the gate | Fresh local scan using `app-and-eight-public-ui-cancellation-fixed-recovered.xcresult`, existing Core/Python XML and exact-analysis server receipt | CE SUCCESS, gate OK, new coverage 87.0%, overall coverage 55.7%, zero unresolved issues; thresholds, exclusions and new-code period unchanged |

The logical unit expansion remains 123 app tests, 21 Core tests, and 15 tooling tests, or 159 new logical tests. The 20 repetitions above validate one existing logical test and are not added to that total.

## Final public UI workflows

The recovered Xcode summary covers the actual app, not copied view logic. Every named case passed:

| Public case | Duration |
|---|---:|
| `testUnifiedTuningWorkspaceShowsLiveContextStagesCombinedChangesAndRemembersAcknowledgment` | 47.981 s |
| `testCockpitConfirmsOneLoopbackWriteAndReportsReadbackMismatchHonestly` | 72.966 s |
| `testCockpitControlsMenuSurvivesHTTPRefreshAndOpensTuner` | 28.526 s |
| `testCockpitLargestTextKeepsBothDialsAndReviewReachable` | 64.896 s |
| `testCockpitMissingVoltageKeepsFrequencyUsableWithoutInventingPayloadFields` | 21.906 s |
| `testCockpitStagesEachDialTogetherAndRestoresWithoutWriting` | 73.773 s |
| `testTuningSessionOpensFromControlsMenuAndShowsNumberedRails` | 33.335 s |
| `testCollapsedTuningCardOpensUnifiedSessionAndDemoWriteLock` | 40.673 s |

The final attachment manifest retains 19 screenshots and the rim-drag coordinates. The actual frequency rim drag again changed 525 to 675 MHz with zero writes during staging. Root visually checked `C3B982AE-0217-4D3D-8E54-27C13F6F4895.png`: largest-text summaries fully show **FREQ 535 MHz / +10 from 525** and **VCORE 1155 mV / +5 from 1150**. The partially scrolled decorative in-dial caption is still truncated, as previously documented. No claim is made that every decorative caption is untruncated.

## Run history and bounded infrastructure recovery

- **12:39:34-12:46:13:** the initial post-map bundle passed 987 logical tests, including all eight UI cases, but failed the cancellation observation once with count zero. This is retained as `app-and-eight-public-ui.xcresult`, not represented as a pass.
- **12:55:31-12:55:54:** the post-fix targeted cancellation stress completed all 20 iterations, exit 0.
- **13:01:57-13:03:16:** the first complete post-fix bundle passed all 980 app units but failed all eight UI cases. Seven reported `kAXErrorAPIDisabled`; `testTuningSessionOpensFromControlsMenuAndShowsNumberedRails` could not resolve the target app. This failed bundle is retained and was not published to Sonar.
- **13:04:50-13:05:02:** root performed one shutdown, boot and `bootstatus -b` of only the owned simulator `5AE0257A-7733-4411-9611-25C576DA2B7E`. There was no erasure, permission reset, other-simulator shutdown or hardware restart. The monitor exited zero and reported `Finished`. This recovery log was generated after the failure and is not evidence of an earlier unclean boot. The underlying reason for the earlier AX unavailability is not established.
- **13:05:15-13:11:56:** the unchanged-source recovered run passed all 988 tests. The enclosing background command completed at 13:11:57, exit 0.
- **13:14:29:** the fresh Sonar analysis finished processing successfully using that recovered green bundle.

The independent reviewer initially misattributed the post-run boot log to the earlier failure and treated its terminal sentinel as an error. Root checked the timestamps, exit status and actual UI progress, rejected those claims, and required their correction. The corrected review retains only the observed accessibility-harness failures, not an invented boot cause or a recommendation to erase the simulator.

## Exact latest Sonar publication

Analysis **`951ae330-1e23-4e16-919c-a2de6054466c`**, CE task **`d27d2afa-149f-49e7-bdbf-4de84b4ac28a`**, processed **October 8, 2026 at 13:14:29 UTC**. The committed raw receipt is `2026-10-08-cancellation-fixed-sonar-receipt.json` and is byte-identical to the fetched server receipt.

- Gate **OK**, new-code coverage **87.0%**: 1,009 covered of 1,160 coverable lines, with 151 uncovered. The minimum remains 80%.
- Overall coverage **55.7%**: 18,375 covered of 32,976 coverable lines, with 14,601 uncovered. The previous 12:15 measurement was 55.6%; the fresh app/UI execution covered 32 additional lines. This small difference is a measured run result, not a claim that coverage is invariant or a controlled production improvement.
- New violations 0 against the unchanged maximum 0. New duplication 0.0% against the unchanged maximum 3%. Bugs, vulnerabilities, code smells, security hotspots and unresolved issues are all 0.
- No ignored conditions. The new-code period remains `PREVIOUS_VERSION`, starting October 8 at 03:20:07 UTC.
- Sonar reports 1,355 imported tests and zero test failures. This plugin-derived number does not replace Xcode's authoritative 988 logical tests or 1,368 expanded executions.
- The receipt fetcher checked the latest project analysis before and after retrieving project-level measures, anchoring them to the same exact analysis. The independent read-only reviewer separately checked the final summary, all eight workflow outcomes and timings, raw receipt and permanent byte equality, unchanged conditions, historical failure retention and per-file Core/converter coverage. It returned final signoff with no defects in `final-signoff-recovered.md`. Its source-freeze statement relies on root's separately verified SHA-256 manifest.

The original `2026-10-08-unit-coverage-sonar-receipt.json` remains the intact historical receipt for analysis `2ce4079c`, rather than being silently overwritten.

## Artifacts and remaining boundaries

Artifact root: `/Users/USER/.jcode/scratch/unit-swarm-20261008/post-map-recheck/`.

- `cancelled-check-race-investigation.md` and `cancelled-check-review-and-sonar-refresh.md`: original race investigation and independent test-only review.
- `cancellation-observation-stress.{log,xcresult}`: 20-iteration stress evidence.
- `app-and-eight-public-ui-cancellation-fixed.{log,xcresult}` and summary JSON: retained 980-unit/8-UI infrastructure failure.
- `cancellation-fixed-simulator-boot.log`: bounded recovery observation, not an earlier failure diagnosis.
- `app-and-eight-public-ui-cancellation-fixed-recovered.{log,xcresult}`, its summary JSON, `app-and-eight-public-ui-cancellation-fixed-source-fingerprint.txt` and `cancellation-fixed-recovered-attachments/`: authoritative final acceptance.
- `post-map-core-tools-receipt.json`, Core physical-line evidence and Python logs: unchanged production-layer recheck.
- `sonar-cancellation-fixed-{scan.log,receipt.json,components.json}`: fresh actual publication and per-file reconciliation.
- `final-signoff-recovered.md`: independent final acceptance, gate, component and permanent-report fact check.

The separate real-Mac read-only tuner acceptance at 12:43-12:46 remains documented in `2026-10-08-tuner-real-mac-acceptance.md`. This follow-up did not reinstall the Mac or phone, unlock the phone, or issue any miner writes. The phone's last observed `passcodeRequired: true` at 12:43 still means physical-phone tuner acceptance is unverified, not that its current lock state was freshly checked here. Firmware-cache production fixes remain committed and simulator-tested, not claimed as installed on physical devices. Guarded live-account smoke cases and real hardware writes remain untested without authorization.
