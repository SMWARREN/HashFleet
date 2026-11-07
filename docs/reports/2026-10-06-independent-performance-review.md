# Independent Hash Fleet performance review, October 6, 2026

## Scope and outcome

Cow accepted eagle's request for an independent **analysis-only** review. This work changed no production app code, miner configuration, firmware, service, recovery policy or wiring. It made no new miner API/SSH requests and performed no app launch, activation, navigation, preference change or new runtime recording. Earlier user-authorized notification/layout delivery is a separate completed workflow.

The strongest accepted priorities are **repeated layout measurement and ImageIO/WebP work in the supplied recorded Mac CPU window**. Optional WAN waits explain a distinct refresh-spinner mechanism. Persistence and glance publication are real source paths, but neither a synthetic fixture nor this short profile certifies their cost in every user incident. No before/after performance fix or complete frame-latency attribution is claimed.

## Independently checked recorded CPU evidence

The original native Time Profiler export represents the installed application at **09:00:01.859-09:00:22.582 UTC on October 6**. The coordinator independently checked the export's SHA-256 against the recorded summary, resolved the XML reference graph, identified the main thread from its actual thread label rather than copying a hardcoded thread ID, and re-counted the target rows, weights, truncated stacks and named categories.

| Re-counted quantity | Observed result |
| --- | ---: |
| Target CPU samples | 16,022 |
| Main-thread samples / sample weight | 15,894 / 15,894 ms |
| Total target sample weight | 16,022 ms |
| Truncated stacks | 1,162 |
| Balanced layout on main-thread stack | 5,026 ms, 31.62% of main sample weight |
| WebP decoder on main-thread stack | 4,394 ms, 27.65% |
| ImageIO on main-thread stack | 4,628 ms, 29.12% |
| Matching FleetStore persistence frames on stack | 57 ms, 0.36% |

The independently derived totals match the supplied summary. These are **inclusive, overlapping sampled stack categories** and must not be added. A category's presence on the stack is not its exclusive self time. Sampling and truncated/inlined stacks do not account for every possible caller or establish precise wall time, frame intervals, a specific asset's culpability, or every intermittent freeze.

The separate SwiftUI-only attempt exited zero but its saved result explicitly says **no SwiftUI data**. It is not accepted as a usable cause-and-effect graph or successful frame-hitch trace. The earlier combined-instrument attempt also remains a failure. Zero potential-hang rows above the 250 ms threshold in the supplied recording does not exclude shorter hitches or incidents outside that window.

Owner-private reanalysis artifacts are `hashfleet-independent-perf-20261006/verify_recorded_profile.py` and `coordinator-profile-check.json`. Original traces were neither changed nor republished.

## Source-backed interpretation

### Layout measurement

`App/Design/FleetBalancedColumnsLayout.swift:46-75` uses an empty explicit Layout cache. `sizeThatFits` measures all children at an unspecified proposal to calculate an ideal width even when a finite proposal width will be used. It then measures heights at assigned widths. `placeSubviews` computes those frames and child measurements again.

This establishes repeated app-level measurement paths and no explicit app-provided measurement-plan cache. It does not prove SwiftUI has no internal caching or identify which invalidation initiated each layout pass. The native stack presence makes this a stronger profiling priority than a purely hypothetical issue.

Any later optimization must preserve the accepted one/two-column rule, narrow-window fallback, equal margins, measured row heights and full-width odd final cards. Existing geometry tests are correctness evidence, not a performance comparison.

### Animated images

`App/Design/AnimatedWebPImage.swift:45-166` owns a MainActor image view, runs a display link on the main run loop and creates frames through ImageIO with caching disabled. It keeps the currently displayed frame rather than pre-decoding the entire animation.

Important counterexamples are retained: `sourceData != data` avoids rebuilding an unchanged image source, and `index != currentFrameIndex` avoids decoding the same frame on every display-link tick. A display link does **not** imply a decode occurs at every screen refresh. The source does not prove which image or update drives the recorded decoder stacks or subsequent SwiftUI layout. Disabling all branding/animation permanently is not an authorized or validated solution.

### Refresh wait versus UI thread work

`DashboardView.swift:354-364` awaits both `store.refresh()` and forced `insights.refresh()` when external data is enabled. `MiningInsightsStore.swift:103-145` shows that forcing bypasses normal refresh cooldown and market-cache gating, and joins external results before combined publication.

`FleetStore.swift:311-350` processes sequential batches of four while applying each completed response inside a batch incrementally. A slow member can postpone a later batch and total refresh/bootstrap completion, but it does not withhold every already-finished batchmate's snapshot. `FleetStore+Monitoring.swift:30-39` waits for the full REST bootstrap before starting its normal live-monitoring phase.

The automatic freshness watchdog and REST fallback at `FleetStore+Monitoring.swift:12-13,125-150` disprove the earlier manual-only/no-timer account. Check cadence and maximum-age settings are not hard wall-clock guarantees during asynchronous requests or scheduling.

These are verified mechanisms, not a measured WAN outage or incident-specific spinner duration. Awaiting network operations is not itself proof that the main thread was blocked.

### Persistence, publication and history

`FleetStore+Evaluation.swift:18-80,113-114,171,197` records successful results and persists state/share/block baselines. `FleetStore+Persistence.swift:97-121` separately guards full cached-reading serialization with a per-device five-second/settings-change/force rule. The cache guard does not cover every baseline write.

`HashFleetApp.swift:198-244` has two distinct task identities. `GlancePublishingIdentity` contains the advancing glance timestamp and can rekey publication as observations arrive. `MonitoringIdentity` contains phase, roster, demo mode and real-time preference, **not the reading timestamp**. It must not be characterized as restarting merely for every telemetry frame.

`FleetGlanceCoordinator.swift:69-105` saves snapshots separately from its 60-second WidgetKit reload guard. Unstructured `Task { }` at the examined MainActor call sites inherits actor isolation, rather than being `Task.detached`. The database uses batched, awaited GRDB transactions and range indexes. Long-window history in `FleetHistoryCard.swift:245-284` returns and maps all matching rows, while the daily path uses bounded in-memory history. Query/chart cost depends on retained rows and was not measured by this review.

The persistence review's hand-written, optimized Swift fixture measured its own encode/set path on this Mac. It is **not execution of the shipped application**, not an on-device bound and not evidence that real per-frame persistence is necessarily sub-millisecond or incapable of an outlier. Residual broad claims in that scratch report are not accepted. The observed matching persistence-frame category is small in this one native recording, which supports prioritizing the measured layout/decoder paths for this window only.

## Other peer findings and rejection boundaries

The sanitized transport summary records an earlier same-board info GET taking 5.631 seconds while a 528,414-byte log export took 5.795 seconds at **08:14 UTC on October 6**. That is dated HTTP reporting evidence, not this coordinator's fresh fleet status, an ASIC hashing stall or a measured UI freeze. The configured ordinary app request timeout is 15 seconds, so that one event is not proof of an app timeout.

The source-confirmed low-scale hashrate formatting defect remains separate from responsiveness. It has not been repaired by this analysis. A zero-finding Sonar scan is not a claim that this known functional defect or every untested workflow is resolved.

The earlier manual-only monitoring account was rejected. The broad assertion that every apparent domain loss was merely telemetry was not adopted, and historic genuine faults must not be erased. The normal watchdog is not characterized as exporting complete logs on every tick. No suggestion to stop safety monitoring, broaden recovery limits or compensate for power wiring with voltage is made.

## Review process and actual completion limits

Three analysis roles were requested through the current operator-configured automatic routing, without per-worker model overrides. Two initial delegates failed to deliver their scoped final artifacts within bounded waits and were stopped, not counted as successful independent reviews. Fresh bounded fallbacks were launched, bringing the attempt count to five for three roles.

- The persistence role delivered a source review through the configured NVIDIA NIM GLM-5.3 route. Coordinator checks corrected actor/task-identity and benchmark interpretation errors. Remaining unsupported app-cost claims are explicitly rejected above.
- The refresh fallback delivered a bounded four-file review through the configured Antigravity Gemini 3.6 Flash High route. Its mechanisms were checked against the source. Its blanket 100% confidence label is not adopted as runtime certification.
- The UI fallback used the configured NVIDIA NIM Nemotron 3.5 Lightning route. Its initial ready response was only `Now`, with no deliverable, and was not accepted. After a bounded correction request it delivered `01-ui-review.md`. Its source guards, recorded category weights and SwiftUI no-data limit were checked. Its category-sum arithmetic, unsupported layout-to-decoder causality, conflation of data/frame guards and proposed experiments that remove protective guards or change responsive geometry were rejected. The coordinator's independent original-export re-count and two-file source review establish the accepted UI evidence. A usable frame trace and controlled before/after test remain absent. No claim is made that three workers independently passed a final runtime review.

Model availability, a ready flag and a benchmark ranking are not evidence that a requested artifact exists or that its claims are correct. Acceptance here rests on files, source comparisons, the recorded export re-count and explicit limitations.

## Requirement-level closure verification

The [closure audit](2026-10-06-closure-audit.md) maps each analysis requirement and changed public conclusion to concrete evidence and its boundary. Fresh offline execution checked the complete production layout geometry across 1,680 edge combinations and byte-identical refresh methods against gated fixture dependencies. Fourteen profile-verifier edge tests reproduced and corrected three false-acceptance gaps in the scratch analysis helper. Recounting the original export after correction retained exactly the same numeric result.

The audit separately re-read 35 named checks from the prior native result and freshly verified build 6 artifact signatures/package inclusion. Neither fixture execution, prior native results nor static package checks are presented as new installed-app profiling or an app-speed improvement. No production performance change was made.

## Next authorized validation, not performed

1. Compare equivalent static/animated artwork under an explicitly authorized session, preserving branding and useful UI behavior. Capture actual frame timing, CPU samples and bounded memory to test decoder attribution rather than changing a live session silently.
2. Compare existing and cached/less-redundant layout measurement in an authorized controlled build. Exercise resize, dynamic text, one/two columns, paired heights and odd full-width rows. Verify both user-visible frame behavior and all existing geometry contracts.
3. Separately measure LAN completion, optional WAN completion and spinner completion with equivalent fixtures. Do not attribute an asynchronous WAN wait to CPU-bound layout.
4. Retain timestamp freshness and widget/live-activity behavior if later change-only or bounded snapshot publication is considered. Do not infer a fix from a synthetic encoding microbenchmark.

No performance implementation, asset replacement, service restart or hardware change is authorized by or included in this report. The analysis outcome is validated prioritization and a bounded follow-up plan, not a claim that the application has been made faster.
