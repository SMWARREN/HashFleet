# Rendering and resource stress validation, November 7, 2026

## Scope and delivery boundary

Changes are committed only in this separate fix copy. The original development tree and the sanitized public-source tree are preserved. No GitHub publication, TestFlight upload, physical-device install, production preference change, or real miner request is part of this validation.

The test app uses the real optimized app, FleetStore, parser, polling and WebSocket paths with isolated diagnostic identities/defaults. Its 20 synthetic miner endpoints bind only to loopback. Mutating requests are denied. This is an adversarial telemetry/UI workload, not a physical model of miner thermodynamics.

## Changes

1. **Per-miner observation boundary, `b54df63`.** Dashboard card construction now creates a dedicated `FleetObservedMinerOverviewCard`. Its body reads `store.snapshot(for: device.id)` through the existing per-miner observation cells. `FleetStore.snapshots` remains canonical, and the cells remain synchronized read projections. No second independently writable fleet store was added. Navigation identity, context menus, accessibility identifiers, error/live state and market data are preserved.
2. **Layout measurement reuse, `24dfd90` and `123a874`.** `FleetMinerDetailGrid` caches the actual production frame calculation between sizing and placement. Width, layout parameters and item count key the cache. SwiftUI cache updates clear measurements when content/subviews change. Width changes safely recompute. Regression tests exercise the production resolver and an actual hosted view.
3. **iOS type-complexity boundary, `d1f39b2`.** The iOS navigation decorator receives an `AnyView` base instead of repeatedly embedding its entire growing `Self`. This addresses a source candidate consistent with the observed type-demangling watchdog stack. It is not yet proof that the physical iPhone background watchdog is fixed.

## Checks already passed

- Thirty fixture/safety tests, including 20 distinct identities, independent wide random values, reproducibility, counter monotonicity, GET/WebSocket delivery, write rejection, exclusive loopback binding and resource-stop conditions.
- Ten checks against the actual production card body using `withObservationTracking`: unrelated-card isolation, own changes, fleet aggregate observation, canonical/cell agreement, equal-update suppression, initial arrival, removal, bulk reset and connection errors.
- Six layout regression groups compiled under Swift 6 with `-O` and active `precondition` checks. These include actual production cache hits/misses, every geometry key, finite degenerate geometry, height expansion/shrink, same-root observed `NSHostingView` updates, resizing and larger dynamic text.
- Optimized Mac and simulator iOS app builds with the candidate source.
- Twelve source-identical remote-close controls using the real production client and direct Foundation WebSocket control. Real frames were required before teardown assertions. Task-list drainage passed. Object retention observations remain unresolved, and task-list drainage is not deallocation proof.

The first layout tests were not accepted: a modeled cache, a misplaced standalone entry point and disabled optimized `assert` checks were corrected before the final independent release verification. An earlier socket-cancel hypothesis was not promoted to production.

## Twenty-miner wide random workload

Each miner has its own changing values rather than a shared repeating waveform:

- Instant and windowed hashrates: 0 to 100,000 GH/s, independently varying.
- Power: 0 to 5,000 W. Temperatures: 0 to 100 degrees Celsius. Fans: 0 to 8,400 RPM.
- Measured voltage/current, actual frequency, actual core voltage and Wi-Fi strength vary within test bounds.
- Shares, uptime and distinct numeric best-share values advance monotonically.
- Hardware configuration templates remain static. No hardware control operations are sent.

The requested cadence is 20 Hz per miner, nominally 400 frames/s total. Actual sent-frame counts are recorded separately and are not equated with app-applied updates or render passes. macOS already coalesces incoming telemetry into periodic publication.

## Mac comparison

| Evidence | Baseline | Combined rendering candidate |
| --- | --- | --- |
| Execution | Sampled through 595.59 s, outer wrapper timed out | Completed 300.02 s, normal duration budget |
| Main-thread profile denominator | 451 samples | 434 samples |
| Largest identified `placeSubviews` call branch | 178 samples, 39.47% | 52 samples, 11.98% |
| Median RSS in requested 60 to 295 s window | 690,976 KiB | 607,664 KiB |
| Median process CPU in that window | 101.45% | 98.8% |
| Last socket count in that window | 161 | 169 |
| 60 s `leaks` snapshot | 292 allocations, 19,104 bytes | 286 allocations, 18,688 bytes |

The baseline window contains 46 samples from 61.10 to 290.03 s. The candidate window contains 47 from 61.11 to 294.63 s. Profile captures are single five-second samples near startup, not a repeated statistical benchmark. The branch weights are inclusive and do not represent total grid time, wall-clock latency or a count of rendered frames. Other grid branches exist, including nested calls.

The candidate sent 89,749 frames and 46,656,887 payload bytes across all 20 miners during the approximately 300 s run. This is approximately 299 sent frames/s, below the nominal 400 target. Per-device counts range from 4,384 to 4,780. Reasons for the delivery gap were not isolated.

The result supports a reduced placement hotspot, and resolver checks directly verify that a matching placement proposal does not repeat child measurement. It does **not** establish a large overall CPU reduction, isolate the separate effects of the two rendering changes, measure scrolling frame rate, or prove every parent invalidation has disappeared. Fleet-wide totals/history legitimately observe aggregate state. Shared error/live collections and market data still have broader observation boundaries. If all 20 miners change, all affected cards may need to update.

The candidate reached its full duration with clean owned-process teardown. The baseline did not: the 600 s outer tool deadline interrupted its normal `finally`, leaving an app and fixture that were subsequently identified and terminated by the coordinator. The interruption and recovery are preserved, not converted into a successful 600 s receipt.

## Remaining limits and unresolved findings

- Socket descriptors accumulated across reconnects in the diagnostic runs described above. The November 8 timeout-control addendum below supersedes any interpretation of those runs as evidence of accumulation under the shipped session configuration. The rendering changes themselves do not modify networking. `CLOSED`, `CLOSE_WAIT` and `ESTABLISHED` states remain observations, not proof of a specific Foundation ownership mechanism.
- Reported leak roots in the sampled runs are NSXPC/AppIntents cycles. This describes those tool findings only, not app-wide leak-freedom or proof of the Mac panic's cause.
- The iPhone report was a background scene-creation watchdog termination, not a jetsam/OOM report. The physical-device timing and launch context differ from foreground simulator UI tests.
- System-wide ENFILE before the Mac launchd panic does not identify the process responsible. Moderate app RSS does not exclude descriptor growth or slower memory growth.
- Earlier database fault injection demonstrated that repeated failed writes retain pending telemetry without a hard cap. No queue eviction policy is introduced by this rendering patch.
- At the time of this rendering investigation, `FleetCelebrationQueue.pending` was a FIFO array with ID deduplication but no explicit depth cap or time throttle. Default-alert startup screenshots showed a full-screen new-best celebration covering the dashboard. Queue growth rates and its contribution to resource use were not measured. That rendering patch did not change record acknowledgment semantics. The later operator-authorized durable queue, pause/resume controls, bounded in-memory page and alerts-enabled acceptance are documented separately in `DURABLE-RECORD-QUEUE-2026-11-07.md`. This historical finding is not the current queue implementation.

## iOS runtime acceptance

The stronger optimized iOS run with 20 wide-random feeds exposed a separate concrete crash about eight seconds after app launch: `EXC_BREAKPOINT` / `SIGTRAP`, with `KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS` below Charts frames and a runtime message naming duplicate `HashableText` keys. This is not the earlier physical-device background watchdog termination. Crash evidence and the failed test are retained.

A scratch-only, two-line control normalizes the line and selected-point Y dimension labels to the same literal `"Hashrate"` already used by area and single-point marks. This is an empirical hypothesis, not proof of Charts internals or the origin of the failing key. It has not been promoted to this fix copy. The first control survived startup but failed miner-card hittability. A bounded gutter-scroll retry then reached its 240-second integration deadline. Direct screenshot review shows a full-screen new-best celebration over the dashboard, so neither failure is counted as navigation acceptance or repaired by removing an assertion.

A separately labeled interaction control **passed** on the optimized iOS 27.0 simulator app: 225.77 seconds, all twelve complete detail/back cycles, chart tap selection, and drag selection to a different recorded timestamp/value. The selected readings changed from 40.96 TH/s to 59.72 TH/s. Foreground dashboard readiness was 6.132 seconds, which is not physical background-watchdog equivalence. All 20 endpoints sent data: 21,372 frames, with 1,066 to 1,073 per device. These are observed counts, not the nominal cadence.

Only isolated diagnostic best/session alert presentation preferences were disabled in this control. All independent wide-random feeds, advancing best-share values, production evaluation and achievement persistence remained enabled. The control does not certify operation under continuous modal alert flood. No production notification preferences or celebration behavior were changed. The original-label reversal also passed: 239.853 seconds, twelve complete detail/back cycles and chart tap/drag assertions, with all 20 endpoints sending 22,368 frames (1,116 to 1,120 per device). Its chart source matches this fix copy. Therefore the two-line label hypothesis did not distinguish the failure, and the chart-label modification was rejected rather than promoted. The original Charts crash remains unresolved and its evidence is preserved.

Both interaction runs used the same requested telemetry seed, presentation control and acceptance assertions, but the diagnostic SQLite history persisted across sequential launches. Initial database state was not identical, so these runs are not a causal/statistical A/B experiment. A passing reversal does not establish crash-freedom or invalidate the earlier crash. It does provide an actual navigation/chart acceptance result for the committed production source under the explicitly limited interaction-control configuration.

## Evidence and cleanup

Private diagnostic receipts, source hashes, actual check output, test summaries, workload journals and a compact reproducible harness are retained outside the source trees. Large generated builds, app copies, trace bundles, disposable simulator and diagnostic state are removed only after evidence export and stopped-process checks. Cleanup and final source preservation are separately verified.

## November 8, 2026 follow-up: diagnostic timeout reversal

The newer owned simulator workspace is `hashfleet-stability-20261108T0110.noindex`. Three complete alerts-enabled, 20-endpoint UI runs used the same requested workload and UI test source. Each passed pause/relaunch/FIFO acknowledgment/resume, chart interaction and twelve detail/back cycles. All owned child processes and the diagnostic app were stopped afterward. These are simulator results, not physical background scene-create acceptance.

The controlled source variable was the resource timeout of the **injected diagnostic ephemeral session**. The request timeout remained five seconds. Production `FleetStore` normally uses `URLSession.shared`, not this injected configuration.

| Run | Diagnostic resource timeout | Peak sockets / file descriptors | Last sockets / file descriptors | Retained TCP states |
| --- | --- | --- | --- | --- |
| A, `ios-stability-network-observed` | 10 s | 60 / 77 | 60 / 76 | Up to 40 CLOSED and 20 CLOSE_WAIT |
| B, `ios-stability-resource-budget-control` | 600 s | 20 / 37 | 0 / 16 | No CLOSED or CLOSE_WAIT observed |
| A reversal, `ios-stability-resource-budget-reversal` | 10 s | 60 / 77 | 60 / 76 | Up to 40 CLOSED and 20 CLOSE_WAIT |

The 10-second A and reversal used the same executable hash and fixture bytes. B's fixture differs by exactly the resource-timeout literal. Each run recorded 80 WebSocket requests, 220 information requests and zero forbidden writes. B returned to zero sockets after each of three peer-close generations. This reversal supports dependence on the diagnostic resource budget in this harness. It does not identify the retaining code path, establish an app socket-leak root cause, measure the shipped session configuration, or explain the Mac launchd ENFILE panic. B has one run per condition and three observed generations, not a long-duration production soak.

B's successful build log is preserved as `ios-stability-resource-budget-build.stdout`. Its 600-second fixture copy was reconstructed after the run and matches the recorded source-identity hash, rather than being a contemporaneous capture. The executable hash is recorded in its receipt, but the shared build directory was subsequently rebuilt. A's resource samples have elapsed time only, whereas B and the reversal add absolute observation times and PIDs. These provenance and clock differences must remain visible in comparisons.

The scratch diagnostic session was returned to 600 seconds after the reversal. This is a **diagnostic-harness correction, not a production networking patch**. Intervals of roughly 85 to 95 seconds with zero observed session tasks and sockets while the store still reports connected remain unexplained. Source inspection shows that the flag spans consumer-loop lifetime, not an independent transport-level observation. Buffer draining, actor scheduling and suspended operations have not been discriminated.

## November 8, 2026 follow-up: startup and chart acceptance still open

The existing `d1f39b2` boundary has a measured structural effect: a representative thirteen-level presentation chain grows to 3,303,997 type-name bytes without the boundary, but stays at 679 bytes or less with it. Head tests pass and the pre-boundary negative comparison fails as expected. These are type-size measurements, not timing of the physical watchdog. The actual dashboard test records a 63-byte static opaque metadata name and a 910-byte runtime instance name. An earlier assertion that those names must be equal was an invalid test assumption and its failed receipt is retained. The corrected runtime-name tripwire is not proof that all opaque helpers expand, nor physical-device acceptance.

At the time of these newer chart-lab runs, the original Charts `HashableText` SIGTRAP remained unreproduced by them and unresolved. It subsequently recurred in the candidate18 ordinary-dashboard profile on November 8 at 05:39:12 UTC, with the first 53 main-thread frames matching the original by image UUID, offset and symbol. See `DASHBOARD-CPU-PROFILE-2026-11-08.md` for the preserved failed capture and limits. New test-only chart workloads must not be mistaken for a production Charts fix:

- The first mounted 120-step workload passed, but a later five-point sliding-window square-wave workload is a different test version. These results do not establish run-to-run instability of an identical test.
- With the later workload and layer capture, the 120-step and 2,400-step tests produced 25 and 448 digest changes against unchanged requirements of 80 and 1,600. Their model-computed unit transitions are not observations of displayed units.
- A later build, whose churn-test source changed capture to `drawHierarchy(afterScreenUpdates: true)`, produced 36 and 864 digest changes. That run also differed in diagnostic timeout, project/test membership, app binary, driver and test selection, so it is not a capture-only comparison. The 2,400-step loop took 114.92 seconds against its unchanged 90-second budget. Both tests still fail; neither the extra cost nor the changed digest counts have been isolated from these other differences or from whole-loop work.
- A new native accessibility-descriptor feasibility observer failed at its first step because traversal did not find the SwiftUI target. Its retained PNG visibly contains a chart and a GH/s header. This is an unavailable observation method in that test context, not evidence that the chart was absent. One image and local OCR do not demonstrate subsequent plot updates or visible unit transitions.

All of these failed receipts remain preserved. Raster acceptance thresholds and time budgets have not been reduced to obtain a pass.

A November 8 source-only review at 07:02 UTC further bounded this observer: `FleetHistoryMountedChurnTests.swift` computes unit transitions from model aggregation, not the displayed chart header, and hashes a downscaled 40 × 20 whole-card image rather than an isolated plot. Successful capture and nonuniform pixels therefore do not establish step-aligned graph updates. Fresh timestamps and the five-point, six-step low/high workload do not by themselves supply a plot-specific oracle for the 80/1,600 digest requirements. Production chart X-scale configuration supplies range padding, not a fixed-hour domain. Root inspection and independent Whale review agree on these source limits; no new runtime result is claimed.

The smallest proposed supplemental diagnostic keeps the existing workload, assertions and failed outcomes intact, while associating a calibrated plot-only capture or line mask with each step's expected series and observing displayed units at bounded checkpoints. Crop validity, expected-series matching, capture alignment and measurement overhead still require validation. This proposal is not implemented, and the separate twelve-step feasibility test below does not establish that it works for the original stress workload.

A further source trace at 10:42 UTC found a concrete distinction between raw inputs and displayed data: `FleetHistorySource.mergedPoints` keys readings by whole Unix seconds, retaining the latest reading within each source and preferring current history over stored history for a shared second. `FleetHistoryCard.minerSeries` uses that merge before window filtering and chart construction. The churn test instead computes its expected aggregate/unit directly from the raw five-point histories. Distinct sub-second inputs can therefore collapse before presentation. Root checked the merge implementation independently of Whale's source trace. This is not evidence of how many collisions occurred in a preserved stress run or a cause of its raster failure or Charts SIGTRAP. The 48-point display budget does not itself downsample a five-point series. A useful supplemental record must retain precise input timestamps/values, the resolved merged/windowed series and post-segmentation/plotted series alongside the same capture, rather than assuming those are identical. The existing 120/2,400-step workloads, 80/1,600 thresholds and 30/90-second budgets remain unchanged.

A separately labeled, scratch-only image/OCR feasibility test now passes and was independently reviewed in `native-stability-image-observation`. On one persistent installed host with twenty synthetic devices, all twelve captures succeeded. Six steps showed GH/s and six showed TH/s, each with an expected rank-zero OCR candidate at confidence 1.0 in the measured unit-header band and no opposite-unit candidate. All eleven consecutive binary gold-line-mask digests changed. Full captures were 1080 × 720 pixels and the calibrated, text-free plot crops were 780 × 141 pixels. First/last full images and crops are retained alongside all twelve JSON observation rows. The suite passed in 6.938 seconds against its separately registered 30-second feasibility budget.

The receipt binds source identity `ab8b4e476fa46432a3a7be543c6b98a0a2677479431213e4bf94c3440a8f9eb9` and scratch observer source `a32cc374c002879a7e57849eb9016d5ad3f8b578783413d3facf58a7238ec6a8`, reports unchanged source/binaries, and confirms the app and owned child processes stopped. This validates one fixed-host observation method with a different deterministic workload, not the failed 80/1,600 digest-change stress requirements, the original SIGTRAP, or physical background startup. No new production stability fix is justified by this image-observation phase's evidence, and no overall completion or physical acceptance is claimed.

### Real Dashboard type-name negative control, November 8 at 04:29 UTC

A separate private copy of candidate11, based on `74dca25`, changed exactly one production file: `App/Design/FleetPagePresentation.swift` was replaced with its `d1f39b2^` blob. The iOS navigation boundary therefore passes `Self` rather than `AnyView`. This is an intentional regression control, not a production patch or a reconstruction of TestFlight build 21. The committed Dashboard test remained byte-identical (`c997c10325d4f684bb7a758057ef04b5a61d273a6dd2217ead79c283835faeaf`), including its 4,096-byte assertion.

The actual iOS-simulator test measured a 63-byte static opaque name and a **35,234,632-byte runtime instance type name**. Exactly one test in one suite failed with exactly one issue at `FleetDashboardTypeBoundaryTests.swift:118`, the unchanged size-budget assertion. The real xcodebuild exit **65** is retained as a failed test, not converted to a pass. Its preregistered negative-control discriminator succeeded because the measured name exceeded 9,100 bytes and no other failure occurred. Root and Tiger independently checked the stopped result in `native-stability-prebound-control-offline`.

The receipt records unchanged private/shared source, shared build and control artifacts, no errors or deadline overrun, and stopped owned children, process groups and simulator app. Two earlier pre-compilation failures remain preserved: nested manifest sandbox application, then a file-only policy rejecting an HTTPS submodule fetch. The successful build used the exact already-local submodule commit under an invocation-local URL substitution, without permitting HTTPS or removing the outer loopback sandbox.

This establishes that the tripwire detects the real Dashboard type-size regression in this simulator setup. It does not measure scene-creation latency, total interned metadata work, physical watchdog behavior or crash freedom. The ordinary candidate15 simulator app was reinstalled afterward and its executable hash verified before any subsequent profiling. The original Charts SIGTRAP and physical startup acceptance remain open.

## November 8, 12:50 UTC: actual chart-input observation

A scratch-only observer captured the values at the actual chart construction boundary without adding published SwiftUI state or changing the original workload, chart-construction suffix, assertions or budgets. All 120 steps had fresh matching step/timestamp/value/unit evidence against the resolved merge projection. The displayed series had one point on 100 steps and two points on 20 steps, consistent with the whole-second merge. This observes actual input collapse in this run, not merely a source-level possibility. It does not prove the collapse caused the raster threshold failure or the original Charts SIGTRAP.

The original 120-step test still failed with raw exit 65: 120 captures, 2,400 raw input points, 19 raw-model unit flips and 39 raster changes against the unchanged requirement of 80. The measured loop took 4.889259 s. Source identity was `d70300d84d6478bc2de496ffe3f3e9d0a4d5e7a0191d536e894bb61369386078`; `results/native-chart-input/receipt.json` SHA-256 is `602d6f6ba53ef59fe1f9be5728a16c94d9711e3cd6dec82b41e681804f660f2f`. Root verified source/product/log bindings and observed native idle at 12:50:27 UTC. No production chart patch or acceptance relaxation followed.

Offline Vision OCR on six retained captures observed the expected displayed units at steps 0, 6, 10, 12, 16 and 119: GH/s, TH/s, TH/s, GH/s, GH/s and TH/s respectively, each at confidence 1.0. The retained JSON is `results/native-chart-input-ocr.json`, SHA-256 `2dad1dfc1f78fc01a4f39b210e53d1a6cbe49bd652d713547cfa290b5c6d8bbc`. This is sampled header-text evidence, not every-frame graph correctness. OCR ran afterward and is not part of the measured native test loop. Its first compiler attempt failed from a missing target SDK; the corrected explicit-SDK build succeeded without changing the captures. All original failures remain preserved.
