# Mac freeze diagnostics and responsiveness testing methodology

Date: November 6, 2026
Recipient: Rabbit, for incorporation into the application testing methodology
Status: Proposed methodology and implementation requirements, not implemented or runtime-validated by this handoff
Scope: Reusable native Mac application diagnostics, with HashFleet-specific acceptance examples

## 1. Purpose and authorization

Make freezes produce usable evidence automatically and make regressions fail acceptance before delivery. This is an observability and testing layer, not an automatic repair system and not a guarantee of finding every cause.

The operator authorized creating this document and giving it to Rabbit for incorporation into testing methodology. This handoff does not authorize installing a service, changing application code, running acceptance, restarting applications, resetting storage, driving iOS, scanning the LAN or controlling miners. Existing separately authorized work retains its own scope. Do not interpret receiving this document as permission to expand that scope.

Keep the receiving session's configured model unchanged. Do not spawn workers or switch models merely to incorporate this document.

## 2. Why HashFleet needs this

Read the following existing records before changing direction:

- `CLAUDE.md`: owner requirements, including one visible Mac application and actual visual/workflow evidence.
- `docs/MAC-ONBOARDING-INVESTIGATION-2026-11-06.md`: observations, rejected hypotheses, correction and remaining acceptance gaps.
- `docs/MAC-NATIVE-INSTALL.md`: native target, canonical installation and generated-app boundaries.
- `docs/ACCEPTANCE-MATRIX.md`: requirement-to-check evidence format. Its September baseline is historical, not current acceptance for all features.
- `Scripts/tests/native_mac_navigation_smoke.py` and `Tools/test_native_mac_smoke.py`: existing PID-scoped native navigation harness and its tests. Inspect current arguments before using it.

The November 6 investigation records a fresh-launch tour freeze with a busy SwiftUI main thread and substantial memory growth. Removing the nested navigation stack, history card, spotlight or targets individually did not solve it. The later macOS correction guarded removal of a legacy preferences key so constructing unpresented destinations did not repeatedly issue preferences changes. The source guard is in `App/Features/Dashboard/LocalNetworkAuthorization.swift`.

Treat that as the recorded correction, not an independently certified explanation for every freeze. At the investigation's 09:40 UTC entry, the tour and navigation had positive observations, while actual discovery, newly discovered Add all, post-reset workflows and independent defaults-loop review were still open. Check subsequent records before asserting their present state.

This case demonstrates why a stack sample alone is insufficient: it can identify busy framework work without establishing which application mutation keeps triggering it.

## 3. Layered design to incorporate

### A. Shared in-process diagnostic module

Use one reusable module, initialized from the actual native Mac lifecycle. Keep HashFleet's workspace and menu bar in the existing executable and shared store. No second user-facing app, persistent LaunchAgent or privileged helper is required by this proposal.

Requirements:

- Observe main-thread responsiveness from a dedicated background execution context, not a timer or task isolated to the same main actor being monitored.
- Keep at most one outstanding main-thread acknowledgement. Do not enqueue an unlimited stream of pings during a freeze.
- Use a monotonic clock, attempt/generation identifiers and synchronization appropriate to the Swift concurrency model. A stale acknowledgement must not mark a later stall recovered.
- Handle start, stop, recovery and cancellation exactly once. Test late callbacks after shutdown.
- Suppress or annotate debugger pauses, sleep/wake and process suspension. Discard a measurement spanning a known suspension rather than reporting it as a proven application freeze.
- Treat responsiveness as one signal. A responsive heartbeat does not prove buttons work or state transitions complete.
- Keep a bounded, sanitized breadcrumb ring recording fixed event names, anonymous correlation identifiers, route transitions and operation start/end/outcome. Do not record raw UI text or payloads by default.
- Avoid synchronous file/database work on main and avoid per-view-update preference writes for instrumentation. Do not recreate the preferences-notification loop being diagnosed.
- Use structured logging and signposted intervals for navigation, local persistence, response decoding, fleet refresh and rendering-related transitions where application boundaries are observable. Do not claim custom signposts expose all SwiftUI internals.

Proposed starting settings, to be measured and explicitly accepted rather than advertised as platform standards:

| Setting | Initial candidate |
| --- | --- |
| Responsiveness suspicion | 500 ms without acknowledgement |
| Developer capture trigger | Sustained 1 s stall while actively testing |
| Outstanding acknowledgements | 1 |
| Breadcrumb capacity | 256 fixed-size entries with an explicit total-byte bound |
| Capture cooldown | 60 s, maximum 3 captures per process session |
| Capture deadline | 10 s for the whole collection, including failed attempts |
| Raw stack/log collection | Maximum 8 MiB per capture; truncate with an explicit marker |
| Evidence retention | Maximum 100 MiB and 7 days, whichever limit is reached first |

Choose final values from paired measurements on the supported Macs and configurations. Record skipped, suppressed and truncated collection honestly. Monitoring must remain useful when a collector is unavailable.

### B. Developer-side evidence collector

Full stack collection belongs in an explicitly enabled developer/test workflow, outside the unresponsive main thread. It must not depend on executing UI code in the frozen application.

Capture the exact process identity, observed binary path, build/version, executable UUID when available, matching symbols, macOS/toolchain version, UTC and monotonic timing, current test step, sanitized recent actions, CPU/memory observations and bounded stack evidence. Record collection failures and permissions explicitly.

Use the installed tools' documented interfaces, such as process sampling or bounded Instruments recordings. Validate PID identity before attaching and handle exit/PID reuse. Never attach to an unrelated process or follow a stale PID silently. Do not invoke privileged tools automatically or disable sandboxing, hardened runtime or code signing to make capture work. Attach permissions and release-signing behavior need real validation.

A sampler timeout, denied attachment or missing symbols is an evidence gap, not a passing health check. Collection must not kill, restart or reinstall the app. Any test harness cleanup must be limited to its own explicitly launched fixture PID, never an attached existing process.

Deep diagnosis is selected from evidence:

- Busy main thread: Time Profiler and SwiftUI Instruments, including update causes and effects where supported.
- Waiting main thread: thread-state/System Trace analysis for locks, synchronization, I/O or IPC.
- Memory growth: allocation/lifetime investigation alongside responsiveness evidence.
- UI action fails while heartbeat remains responsive: investigate overlays, routing, disabled state and action/state-transition logic. Do not dismiss the failure because the process is alive.

Stack patterns and AI summaries are hypotheses. Preserve original evidence, compare controlled reproductions, and do not label a sampled framework frame as a proven application root cause.

### C. Field diagnostics, separately scoped

MetricKit is a possible additional source of system-collected hang/crash diagnostics for supported deployment targets. Verify the exact API and availability against the project's SDK and minimum OS. It is not a replacement for the developer collector, a guaranteed report for every freeze or a synchronous support command.

Preserve HashFleet's local-first/no-analytics product policy. Any diagnostic export is user-initiated and sanitized. No Sentry, Crashlytics, cloud upload, external model submission or analytics dependency is authorized by this document. Treat any later service proposal as a separate decision.

## 4. Testing sequence

### Gate 1: Deterministic offline module tests

Use injected clocks, schedulers, persistence and collectors. Do not block the test runner's main thread intentionally.

Verify threshold boundaries, one outstanding ping, stale acknowledgements, recovery deduplication, cancellation, repeated start/stop, cooldown, capture limits, truncation, unavailable permissions, collector timeout, app exit/PID reuse, full/unwritable storage and sleep/debugger suppression. Verify that a responsive process with an incomplete UI action does not pass workflow acceptance.

Use synthetic sensitive strings in nested events, errors and paths. Assert they never appear in exported evidence. Check preservation of explicit unknown/unavailable states. Test the logger itself for data races with appropriate diagnostics in a separate supported configuration.

### Gate 2: Explicit diagnostic fault fixtures

Only after execution is separately authorized, use a clearly identified synthetic fixture to create a bounded busy-main stall, a bounded waiting-main stall and a UI action that fails without blocking the heartbeat. Never inject these into the owner's normal app session or a hardware-connected workflow.

Verify detection, bounded collection and recovery for each fixture, and verify that a healthy control does not generate a stall report. Ensure a fault cannot deadlock the test runner indefinitely. Stop cleanup at the owned fixture process boundary.

A separate launched fixture must be disclosed first because it can create Dock/LaunchServices entries. Follow the single-app policy for nonindexed staging and reversible retirement. Test policy that allows offline synthetic tests does not automatically authorize launching another application.

### Gate 3: Real native workflow regression

Extend the existing Mac navigation harness rather than replacing it with screenshot existence or a new competing app. If attaching to an explicitly selected existing demo PID, preserve its lifecycle and preferences. Test launch arguments and fixtures must isolate real fleet storage.

A proposed minimum scenario set is below. Counts are initial acceptance candidates, not historical passes:

1. Fresh first-launch fixture: tour Next, Back and Close respond and lead to the correct stable screen.
2. Empty Overview and populated synthetic Overview both become interactive.
3. At least six tuning round trips using Overview and sidebar entrances, two same-miner reselections and eight sidebar replacements. Verify editable content, correct destination and usable back navigation, not only accessibility node presence.
4. Add all with injected discovery fixtures: complete success, partial failure, retry and cancel. Assert successful additions persist, failures remain visible and populated Overview stays interactive. Do not use a real subnet scan as the fixture.
5. Repeated sheet open/close, settings reselection, scrolling and window resizing, with visual inspection across multiple frames.
6. Background/foreground and window/menu-bar transitions, verifying the intended single-process behavior.
7. Preferences regression: repeat empty-defaults destination construction and assert no redundant legacy-key removals; seed the key and assert exactly one retirement. Follow with real rendered navigation acceptance because a unit pass cannot prove UI responsiveness.

Each action needs a bounded completion assertion and a visible or accessibility-confirmed result. Capture failure evidence before cleanup. A timeout must fail the scenario, not trigger a longer unbounded retry. Preserve known idempotency rules so retrying an ambiguous click cannot perform an action twice.

HashFleet-specific constraints: no physical iPhone automation/reset/reinstall, neither scanner, no hardware Apply, pool/frequency/voltage/fan/firmware changes and no mining/recovery service action under this handoff. Demo mode is not evidence by itself that every public HTTPS request is disabled. Inspect and explicitly disable external services or use injected transports, then verify the request journal. Assert zero device-control requests and zero unauthorized real destinations.

### Gate 4: Performance and instrumentation overhead

Run paired baseline and instrumented builds on the same supported Mac, OS, build configuration, input and workflow. Include an optimized build without a debugger for representative timings. Keep sanitizer and diagnostic-heavy runs separate because their overhead changes measurements.

Record action-completion latency percentiles, responsiveness delays, idle/active CPU, resident/physical memory with the measurement definition, memory growth after settling and evidence size. Use enough repetitions to make the chosen statistic meaningful and publish sample counts.

Before changing code, define acceptable per-action latency and instrumentation overhead budgets. No universal CPU percentage proves health. As an initial investigation trigger, compare instrumented idle CPU and memory against the matched baseline, then agree final budgets from measured variance. Do not move a failing threshold after observing a regression just to obtain a pass.

Run a bounded steady-state/soak scenario and confirm event storage, pending pings, file counts and observer/task counts remain bounded. Report duration and limits, not an indefinite-stability claim.

## 5. Requirement-to-evidence acceptance matrix

All rows below start **NOT RUN**. Replace statuses only with observed receipts from the actual implementation. Proposed test names or cases are not existing tests merely because they appear here.

| ID | Requirement | Required check/evidence |
| --- | --- | --- |
| FD01 | Detect sustained busy and waiting stalls | Offline boundary tests plus separately authorized bounded runtime fixtures and healthy control |
| FD02 | Monitor does not worsen a stall | One-ping invariant, concurrency/lifecycle tests and observed bounded task/queue counts |
| FD03 | No false recovery or suspension diagnosis | Stale-generation, shutdown, debugger and sleep/wake cases with suppression reasons |
| FD04 | Capture is bounded and failure-tolerant | Deadline/size/cooldown/retention tests; denied, missing, disk-full and timeout receipts |
| FD05 | Evidence identifies the right binary | PID/path/build/symbol identity checks, app exit and PID-reuse tests |
| FD06 | Sensitive data stays private | Export adversarial tests and inspected sanitized bundle; no automatic upload |
| FD07 | Test preserves owner state | Isolated suite/transport assertions, no real saved-fleet mutation, attached PID never stopped |
| FD08 | Onboarding remains interactive | Real native tour interaction and stable multi-frame screen evidence |
| FD09 | Navigation remains interactive | Repeated real native route transitions with correct rendered editable fields |
| FD10 | Bulk add does not freeze Overview | Injected discovery success/partial failure/cancel with persistent state and action assertions |
| FD11 | Historical mutation loop stays fixed | Exact removal-count regression plus populated native rendering acceptance |
| FD12 | Instrumentation overhead is acceptable | Paired optimized-build measurements against predeclared budgets and soak bounds |
| FD13 | One-app installation policy holds | Canonical process path and generated bundle/LaunchServices/Dock evidence when execution creates artifacts |
| FD14 | No unauthorized device/network work | Request journal and action inventory demonstrating scope compliance |
| FD15 | Failure evidence cannot become success silently | Nonzero named-test count, zero hidden skips, preserved failed attempts and final post-edit verifier |

For each row record: status, exact named checks, source commit and dirty-tree manifest, binary identity, UTC timestamp, actual commands/arguments, environment, assertion result, evidence paths, and limitations. Use PASS, FAIL, NOT RUN or BLOCKED with the indispensable external dependency stated. A planned test, successful compile, empty filter match, framework sample or reviewer opinion alone cannot pass an actual workflow row.

## 6. Failure investigation loop

1. Preserve the original failure and capture before changing anything.
2. Separate busy, waiting, memory-related and responsive-but-broken UI symptoms using evidence.
3. State one falsifiable hypothesis and one controlled change. Keep the original failing test.
4. Run the same reproduction with matched inputs. Record negative controls, not just successes.
5. Revert disproven experiments and remove temporary render/runtime switches before shipping.
6. Rerun named affected cases and a final integration/acceptance verifier after the last edit.
7. Report what was observed, what is inferred, what remains untested and which operations were not authorized.

## 7. Evidence packaging and privacy

Keep evidence in a user-private, nonindexed directory outside the source tree. Default to allowlisted fields. Exclude wallet addresses, pool/Wi-Fi credentials, tokens, private keys, raw device responses and personal paths. Apply sanitization to error messages and filenames too. Do not commit raw captures.

A useful bundle contains a manifest, test-step timeline, sanitized breadcrumb/log excerpt, bounded stack sample or trace reference, measurements, collection outcomes, matching-symbol identity and a short human diagnosis separating facts from hypotheses. Hash artifacts when available. Trace formats that cannot be reliably sanitized must remain local and must not be exported automatically.

Apply retention only inside the diagnostic-owned evidence directory, without following symlinks or deleting owner files. Evidence from a failed acceptance remains traceable even if retained raw data expires, through a sanitized failure receipt. No broad cleanup of scratch, Applications or LaunchServices is authorized by the collector.

## 8. Incorporation checklist for Rabbit

- Add a reference to this document from the testing methodology or acceptance index Rabbit actually owns. Do not rewrite unrelated records.
- Adopt the evidence matrix and failure-first loop now as methodology. Mark implementation-dependent checks NOT RUN until implemented and executed.
- Keep engineering implementation as a separate scoped task. Stage shared diagnostic contracts, deterministic tests, bounded developer collection and real workflow acceptance in that order.
- Preserve the one-app requirement, no-analytics policy, original failed evidence, current scanner/phone/hardware holds and each session's model configuration.
- Report incorporation with the changed document path and commit. Do not report automatic freeze capture as delivered merely because methodology was documented.

## 9. Primary references and evidence provenance

Local evidence above was inspected read-only on November 6, 2026. The source tree contained unrelated active modifications. This handoff authors one new documentation file only and does not certify those modifications.

Apple references verified during the preceding assessment on November 6, 2026:

- Apple Developer, *Getting started with hang analysis*: distinguishes busy-main diagnosis from blocked-main diagnosis and selects profiling tools. Documentation path: `https://developer.apple.com/tutorials/instruments/getting-started-with-hang-analysis`.
- Apple Developer, *Optimize SwiftUI performance with Instruments*, WWDC25 session 306: SwiftUI update work, Time Profiler and the Cause & Effect graph. Session path: `https://developer.apple.com/videos/play/wwdc2025/306/`.
- Apple Developer, *Understanding and improving SwiftUI performance*: repeated and long-running view updates, including geometry work. Documentation path: `https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance`.
- Apple Developer, *OSSignposter*: custom intervals recorded and correlated in Instruments. Documentation path: `https://developer.apple.com/documentation/os/ossignposter`.
- Apple Developer, *MetricKit*: system-collected metrics and diagnostics, with platform/API availability to validate for the actual deployment target. Documentation path: `https://developer.apple.com/documentation/metrickit`.

These sources support the diagnostic techniques. They do not establish that HashFleet currently implements this design, that an arbitrary heartbeat detects all hangs or that any proposed acceptance gate has passed.
