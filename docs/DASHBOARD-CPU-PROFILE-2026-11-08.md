# Ordinary dashboard CPU profile, November 8, 2026

## Purpose and isolation

Following the operator's request, the installed AvdLee `swiftui-expert-skill` was used to record and analyze an app-PID-only Time Profiler trace. The initial candidate15 captures used a separate synthetic simulator workload, not a reproduction of the earlier Charts trap or a physical-device startup acceptance test. The later candidate18 comparison did reproduce the observed Charts trap signature, as recorded below.

The optimized ordinary candidate15 app was built from production commit `2dc9eeddcf4da670f5f440054a06c08b119c3360` plus the recorded diagnostic injection. Its source identity SHA-256 is `b9c21cdac267c329a5a164eeecb14d9903acde0b1977da2b198bd1656bdb08e9` and executable SHA-256 is `98a3821ca20fde0d40ec2f774e4a32e9f4af8a55d9576cb20e9a66f02ebdb027`. It contains the verified cache-metadata fix, not the lifecycle-event instrumentation or the intentional startup negative control.

Only the owned iOS 27.0 simulator was used, with Xcode 27.2 tooling. Twenty synthetic loopback endpoints used 50 ms configured frame intervals, wide/random telemetry, seed 20261107 and clean WebSocket close after 30 seconds. External data and hardware controls were disabled. Navigation-control presentation suppressed record popups. This is not the alerts-enabled durable-queue acceptance workload documented separately.

## Capture outcomes

| Run | Actual outcome | Disposition |
| --- | --- | --- |
| v3, started 04:42:55 UTC | Driver exit 1 after 136.5 seconds. The 60-second trace was saved, but shim cleanup classified its own process-list observer as a child and recorder finalization timed out. Final process scan also preceded reaping of direct children. | Failed capture-hygiene evidence retained unchanged. A later 04:45:54 read-only scan found no owned survivors. Saved trace analyzed only from a copy, never relabeled a successful run. |
| v4, started 04:54:15 UTC | Driver exit 0 with a 79.56-second guardian lifetime. Recorder child exit 0, payload and capture gates passed, all owned processes stopped, no cleanup errors. | Accepted within capture/cleanup/input-preservation scope. Independent reviewer verified receipt and all 12 frozen input hashes. |

The v4 driver changes were confined to launching the membership observer in a separate session and independently waiting/reaping registered direct children before the final process scan. Sixteen mocked regression checks passed. A harmless isolated real helper check changed from observing its own ps child to observing only the owned leader. Source-only independent review preceded the retry. Workload, app, safety thresholds and capture duration were unchanged. This is an observed successful cleanup, not an absolute containment guarantee for every failure mode.

## Measured v4 workload and trace

- Exact target PID: 57371. The trace spans **60.593629 seconds**, from November 7, 23:54:19.667 to 23:55:20.261 EST, corresponding to November 8 UTC.
- Time Profiler exported **57,745 samples** and **57,745 ms of total weighted samples** across app threads. Weighted samples are not equivalent to main-thread busy time, elapsed latency, or completed-frame throughput.
- The fixture reported **12,276 frames written**, 612 to 619 per device, and 6,302,690 bytes. The fixture separately observed 60 info GETs, 40 WebSocket GETs and zero forbidden writes. Frames and bytes are fixture-side egress, not verified app ingress. GET counts are incoming requests observed by the fixture. The 150-second fixture duration is a configured maximum, not the actual elapsed capture.
- Thirty-four process safety samples observed at most **410,896 KiB RSS**, **32 numeric descriptors**, and **20 internet sockets**. Socket counts included a sustained zero-socket interval before reconnecting. They were not continuously 20. Sampled resource bounds are not a leak-freedom guarantee.
- Source inventory, installed executable, and all 12 pinned inputs remained unchanged. The payload's `matched_lifecycle_timing` field is false.
- The exported potential-hangs lane had zero rows. Animation-hitch, SwiftUI-update and cause-graph lanes were unavailable. This does not establish absence of stalls, correctness of every frame, or crash freedom.

The leaf-symbol summary includes convolution (2,427 ms), `__open` (2,060 ms), `_platform_memmove` (1,972 ms), `__proc_info` (1,639 ms), and `JSONWriter.serializeString(_:)` (1,320 ms). These are process-wide leaf weights. The installed helper's `thread` label is the first encountered thread for a symbol, not exclusive main-thread attribution.

## Independently analyzed caller evidence

Full-depth v3 XML and separate v4 calltree text identify the notification inbox as a substantial main-thread path. The following categories are disjoint within this table only:

| Caller into `persistNotificationInbox()` | v3 exact sample weight | v4 approximate text weight |
| --- | ---: | ---: |
| Delivery marking | 6,965 ms | 6,960 ms |
| Best-share enqueue | 4,698 ms | 4,703 ms |
| State/metric enqueue | 1,665 ms | 1,610 ms |
| **Unique inbox union** | **13,328 ms** | **13,273 ms** |

This represents 26.50% of v3's 50,291 ms main-thread sample weight and approximately 26.26% of v4's rounded 50.55 s main-thread tree weight. V4 union rounding is about ±20 ms from its displayed roots, not a statistical confidence interval. V3 remains failed capture hygiene despite the retained usable samples.

V3 `recordSuccessfulInfo` has 17,453 ms inclusive weight, including 6,363 ms of inbox work. Its 14,098 ms JSON union includes 11,079 ms inside inbox persistence. These nested figures must not be added. Preference/entitlement operations in the simulator contribute to the persistence stacks, limiting physical-device extrapolation. Sample weights are not call counts or measured elapsed function durations.

The profile has no event IDs or mutation counters, so separate delivery branches do not demonstrate duplicate event delivery or repeated identical saves. The measured candidate is avoiding re-encoding unchanged full entries while retaining every existing journal setter and state-transition checkpoint. The native correctness tests and independent source/result reviews below are complete. The surviving-run comparison below provides descriptive sampled-weight evidence, not a matched causal benchmark or an overall performance improvement.

## Correctness limits for follow-up changes

The notification inbox path serializes its entire capped journal. Source inspection confirms that a single in-app handoff can intentionally persist three different states: pending acceptance, system delivery suppression, and completed in-app delivery. These are not three identical no-op writes. `UserDefaults.set` does not establish a synchronous physical disk flush.

A proposed simple in-memory equality guard was rejected. A previous encode failure or 512 KiB cap rejection can leave memory newer than persisted storage, and a separate foreground/background store can change the backing domain. In-memory equality alone would not prove a retry is unnecessary. No batching, debounce, dropped telemetry or skipped durability barrier is authorized by this evidence. A bounded entry-encoding reuse candidate is under validation, not a completed performance or stability fix.

The earlier lifecycle run's 92.45 to 94.50 second receiver-to-consumer-end delay is a different instrumented UI workload. This ordinary profile has no matching stream lifecycle markers and cannot explain that interval directly. The Charts `HashableText` SIGTRAP recurred during the candidate18 comparison below; its cause and the physical background scene-creation watchdog remain unresolved.

## Candidate18 comparison failed with a real Charts crash

At **2026-11-08 05:39:12 UTC**, the candidate18 app crashed roughly 3.10 seconds after launch. The planned same-workload comparison therefore produced **no accepted performance result**. Native correctness remains 12 inbox-encoding plus 71 durability tests passed, but it does not establish rendered-dashboard stability or a speedup.

- Frozen comparison: `event-lab/dashboard-profile-candidate18/inputs.json`, SHA-256 `9882664e19b30b29facd04d6dff0171ae21542b392658c4e4c41d10cc77d96de`. Root verified all 13 pinned files, inline/external binding equality, and byte-identical accepted-v4 payload and guardian before execution.
- Failed run: `event-lab/dashboard-profile-candidate18/runs/20261108T053906Z-80967/`, task `3466599dd2`, exit 1, guardian elapsed 17.381 seconds. Its identity sample failed when app PID **81010** disappeared. The recorder independently reported that the target app exited. `capture_passed` and payload `passed` are false despite the recorder saving a partial trace.
- Retained crash: `results/candidate18-profile-crash-20261108T053912.ips`, SHA-256 `fb48efc86633d6038651e2b9f5dbd133e9b64ece89cb658dd589c3f2ac89e07e`, incident `A9D2B23A-E652-4AB1-8507-9B8582851E54`. PID, owned simulator/bundle and app ARM64 UUID `A2AE5916-5469-3B5B-80EB-2CA69A4F223B` match the launched candidate18 binary. The main-thread stack has `KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS` followed by Charts frames and AttributeGraph/SwiftUI rendering.
- A bounded read of that simulator PID's 05:39:08–05:39:15 UTC logs names **duplicate `HashableText` keys** at 05:39:12.512 UTC. Retained assertion log: `results/candidate18-profile-hashabletext-20261108T053912.log`, SHA-256 `366db7e6e43add9d46a4cd6b8d5928624e402ec8c1cd2cb3db5562d1e65940ce`. This establishes the same named assertion class as the earlier failure, not the same offending value or causal mechanism.
- Cleanup reports all owned processes stopped and no cleanup errors. All 13 pinned inputs remained unchanged; the payload also verified its source inventory and installed executable unchanged. Only two resource samples were collected. Fixture totals were 260 frames written, 131,902 bytes, 20 info GETs and 20 WebSocket GETs, with zero forbidden writes. These are fixture egress/request observations, not proof of per-frame app ingestion or continuous socket exposure.

The crash is preserved as failed evidence, not relabeled as a successful profile or automatically blamed on the inbox cache. Whale independently verified failed disposition, cleanup and unchanged inputs. Squid compared the preserved original stress IPS (SHA-256 `bca3d0fffed1fb52a14b72dee5657dbc06ed96664f49176eef3dbb5f3726b063`) with this IPS: the first 53 main-thread frames match by image UUID, offset and symbol, including all 42 Charts frames under image UUID `041A3AA3-913D-3678-9AF0-724E2CCE0A20`. Lower stacks differ (82 versus 78 frames), as do app binaries, simulator identities and run contexts. The Charts frames remain unnamed. This is a narrow signature recurrence, not a complete stack match or identification of the offending mark/key.

The assertion was already observed before the optimization. Conversely, earlier baseline passes do not prove the optimization cannot affect timing or exposure. No production chart fix, performance improvement, matched lifecycle explanation, or physical acceptance follows from this attempt.

Before any retry, `results/inbox-candidate18-unchanged-repeat-plan.md` limited the sequence to **one additional unchanged attempt**, retaining the crash regardless of outcome. That repeat, `runs/20261108T054650Z-83687`, task `810907au8o`, completed with exit 0 and `capture_passed: true` in 78.540 seconds. Its app PID was 83755, with 34 resource samples, no cleanup errors, stopped ownership and unchanged inputs/source/installed executable. Fixture totals were 15,595 frames written, 8,018,412 bytes, 40 info and 40 WebSocket GETs, and zero forbidden writes. Whale independently verified the stopped repeat receipt, target PID, cleanup, integrity gates and fixture counts. Copied-trace CPU analysis is frozen, and independent identity/accounting review found no concrete error within its stated scope. A surviving-run measurement is conditional evidence; the two outcomes are not a crash-rate estimate and cannot establish startup or Charts stability.

## Candidate18 surviving-run CPU comparison

The frozen copied-trace review targets only surviving PID 83755. Its recording spans **60.596754 seconds**, versus baseline v4's 60.593629 seconds. Candidate values below come from full-depth XML; baseline main-thread values come from rounded calltree text. These are weighted samples, not elapsed function duration or call counts.

| Sampled quantity | Baseline v4 | Candidate18 survivor |
| --- | ---: | ---: |
| Whole-process sample weight | 57,745 ms | 59,065 ms |
| Main-thread sample weight | approximately 50,550 ms | 49,174 ms |
| Delivery-marking inbox union | approximately 6,960 ms | 2,066 ms |
| Best-share enqueue inbox union | approximately 4,703 ms | 1,737 ms |
| State/metric enqueue inbox union | approximately 1,610 ms | 583 ms |
| **Disjoint main-thread inbox union** | **approximately 13,273 ms** | **4,386 ms** |
| Inbox share of main-thread sample weight | approximately 26.26% | 8.92% |

The observed named inbox union is about 67% lower in this surviving run. This is evidence of lower sampled weight on that path, not a per-event cost reduction or an overall speedup. Whole-process sample weight increased. The candidate's displayed calltree inbox sum is approximately 4,391 ms, five milliseconds above the exact XML union, consistent with displayed-weight rounding. Baseline rounding is not a statistical confidence interval.

Candidate main-thread JSON-pattern weight is 4,174 ms, including 216 ms inside inbox persistence and 3,958 ms outside it. Its 16,659 ms inclusive `recordSuccessfulInfo` weight contains the 2,320 ms producer-inbox subset. These nested quantities must not be added. Rendering remains substantial, and the helper's process-wide leaf labels must not be mistaken for main-thread-only totals.

**Exposure was not matched:** the survivor fixture sent 15,595 frames / 8,018,412 bytes and observed 40 info GETs / 40 WebSocket GETs, versus baseline 12,276 frames / 6,302,690 bytes and 60 / 40 GETs. These are whole-fixture-run observations, not trace-window counts or verified applied events. Reconnect phases, prior launches, persistence/cache state and host conditions also differ. Do not divide sampled weight by sent frames to infer throughput or normalized work.

Root verified the receipt SHA, all 23 bound artifact/input hashes and recorded disjoint arithmetic with exit 0. This root check did not independently recompute raw XML attribution. Whale separately verified all 23 bound hashes, run identities, displayed caller roots, nested arithmetic and denominator calculations, finding no concrete accounting or identity error. That review cross-checked the retained evidence rather than running a new trace export or claiming an independent full raw-XML recomputation. The first candidate18 Charts crash remains a separate failure. No crash fix, matched 92–94-second drain explanation, physical startup acceptance or overall speedup follows from the surviving trace.

## Encoding candidate: native correctness evidence

The instance-local, MainActor entry-fragment cache in `e7f56ca` / `813911d` always uses default JSONEncoder semantics and compares the complete entry before reuse. It retains every successful `UserDefaults.set`, journal occurrence, ordering and state-transition checkpoint. The byte gate still includes array punctuation and rejects outputs above 524,288 bytes. Failed assembly does not replace the prior cache. A counting observer cannot supply alternate encoded bytes. Retained fragments are bounded to 100 indexed entries and 512 KiB, not a claim that all transient or retained object memory fits in 512 KiB.

Candidate18 at `b9a47c2dc0221257b7893df9dd62b2436ff7fc15` built successfully with Swift 6 and Release optimization. Identity SHA-256 is `c1cafc5d067a89cdbee5a87a41739b77217e7d31c3c33abf902edc681aead364`, app SHA-256 `09597eab4753eccdf515cc1e655989d00370d294f1ca19637d8db0b99b8bb2ba`. Two test-only annotations resolve actual native compiler diagnostics without changing assertions.

- Native encoding suite: **12 tests passed**, including all six real event types, canonical JSON equivalence, fractional dates and escaping, cache hits/invalidation/order/duplicate payloads, actual non-finite event retries, exact one- and two-entry size boundaries, no setter on encoding/cap failure, successful retry, and shared-defaults last-writer-wins with every setter preserved.
- Existing durability suites: **71 tests in four suites passed**, covering notification delivery, notification lifecycle, persistence boundaries and celebration queue behavior. Both native receipts record exit 0, unchanged source/binaries/drivers, stopped owned groups/app and no cleanup errors. Independent stopped-result verification confirmed both runs, all named outcomes and the same candidate18 artifact hashes.
- Preserved failures: the first build stopped before compilation with exit 74 when the file-only Git policy rejected a submodule HTTPS URL. An invocation-local substitution to the exact existing local commit retained the file-only policy. The next build failed 65 on an existing lifecycle callback conversion, corrected by explicitly matching its MainActor/Sendable signature. An attempted delivery-only run stopped before fixture readiness on an exclusive-bind conflict, with no tests executed. The retry waited for strict port availability and selected the four unchanged suites in one run.

The original flawed worker failure test is retained in scratch: identical cached entries bypassed its injected encoder, so it did not establish non-finite failure behavior. Independent review caught it before native acceptance. The corrected test uses actual invalid production event payloads and the fixed encoder strategy. The surviving-run profile above is descriptive and has different exposure. These correctness results and sampled-weight observations do not establish an overall speedup, the historical drain cause, Charts crash freedom or physical-device acceptance.

## Observation-map encoding probe, 15:25 UTC

A source-only follow-up found that changed readings still call best-share, block and
state whole-map persistence on the main actor. An in-memory equality write-skip was
not adopted: the existing foreground/background and retry contracts still require
the setters. A separate 26-line scratch candidate reuses only JSON encoding, retains
one successful value up to 65,536 encoded bytes, returns larger encodings normally
without retaining them, and leaves every caller-side setter intact. No production
file uses this candidate.

An optimized Swift 6 macOS in-memory probe compiled and exited 0. It checked changed
fields, membership and empty maps, Unicode round trips, inclusive retention and eviction,
and repeated real non-finite encoding failures. Three repetitions of 2,000 assignments
used nested dictionaries shaped like best-share records, not the actual FleetStore
pipeline. Median encoding times for unchanged 20/128-record maps were 49.10/299.53 ms
without reuse and 5.35/33.21 ms with reuse. When every assignment changed a record,
reuse was slower: 48.45/292.95 ms became 51.44/307.26 ms. The order was fixed, not a
randomized benchmark. These are aggregate synthetic timings, not per-frame UI latency.

The probe did not execute UserDefaults setters, cross-store integration, an app launch
or a freeze reproduction. It does not justify blanket caching of constantly changing
state or identify the historical drain cause. No additional native build was started
for this candidate. Exact source, compile/run outputs and hashes are retained in
`queue-io-lab/observation-encoding-run1/receipt.json` under the private scratch root.

## Preserved evidence

Private evidence root: `~/.jcode/scratch/hashfleet-stability-20261108T0110.noindex/`. Raw traces remain private and are not committed.

- Failed original: `event-lab/dashboard-profile/runs/20261108T044255Z-51337/`.
- Accepted retry: `event-lab/dashboard-profile/runs/20261108T045415Z-57318/`, including guardian/payload/shim receipts, fixture journal, resource samples and original trace.
- Analysis copies and JSON summaries: `results/dashboard-profile-v3-analysis.*` and `results/dashboard-profile-v4-analysis.*`.
- Combined source-bound caller review: `results/dashboard-profile-v3-cpu-review.md`, SHA-256 `2eb38fc7f49a5884cfd503d26c426eaad7a381eece9edf5858ec18288b0b5855`. Its receipt binds 11 analysis artifacts, and ten cited source files match candidate15. The review distinguishes exact v3 XML from rounded v4 text, nested costs, symbolication gaps and failed intermediate analysis attempts.
- Frozen candidate18 surviving-run CPU review: `results/candidate18-repeat-cpu-review.md`, SHA-256 `1d24f85504ab2584eac4a0a5d90996790352b7d2088f876889faaa1d85526b18`. Receipt `results/candidate18-repeat-cpu-receipt.json`, SHA-256 `eed853fb1261227237ac1249ba2b770363171dc90d51066509d5f60bfab76e70`, binds 14 new artifacts and nine inputs, including the unchanged first-crash evidence. Raw exports remain private.
- Original v3 screenshot: `results/dashboard-profile-v3-visible-20261108T0443.png` and visual-observation timing receipt. It establishes one unobscured synthetic-dashboard frame, not continuous visibility. Its approximately 0.382-second screenshot operation is an observation disturbance in v3 only. No screenshot was taken during v4.
- Frozen driver versions and minimal deltas: `event-lab/dashboard-profile/v1/`, `v2/`, `v3/` and `DELTA-v4.md`. Current v4 guardian SHA-256: `f6db11314be54e25c5221618425156cf332dd46db9b086aff8055710d5da5dc1`.

## Telemetry initialization follow-up, November 8 at 13:44 UTC

Source inspection distinguished steady-state GRDB operations from setup: the 25 read/write/vacuum sites already use async APIs, while the MainActor singleton previously synchronously opened the connection and ran schema creation. Changing DatabaseQueue to DatabasePool would not, by itself, remove that synchronous initialization boundary. No pool conversion or storage migration was made.

A small standalone observer linked the already compiled production Core and GRDB objects from the accepted queue Mac build. Under an isolated injected DatabaseQueue with a 250 ms busy timeout and a separate SQLite BEGIN IMMEDIATE transaction, the original schema initializer took 289.031 ms, allowed zero MainActor heartbeat ticks, and produced a 291.526 ms maximum heartbeat gap. Initialization failed closed; a separate initialization after unlocking successfully persisted a reading. This deliberately configured lock is not evidence of the production default busy timeout, real-disk opening latency, or the original watchdog cause. The first observer compile lacked await on its setup-only GRDB call; that failed log is preserved.

The production singleton now starts one retained detached opening task. All existing asynchronous database methods await its completed schema before SQL access; reading buffers remain MainActor-owned and retain their failure/retry rules. Concurrent callers receive the same prepared queue, and cancelling a waiter does not cancel shared initialization. Existing synchronous public initializers remain unchanged for explicit synchronous clients. Schema definitions, SQL bodies, database filename and DatabaseQueue type are unchanged. The six operation extensions differ only by readiness awaits.

Final targeted package validation passed 34 XCTest methods and 13 Swift Testing methods, including five new initialization tests plus the existing persistence, maintenance, identity-merge and startup-cleanup suites. The real-lock regression waited 320.704 ms for schema failure while observing 43 heartbeat ticks and only a 7.552 ms maximum gap. Separate delayed-opener, schema-readiness, shared-instance, buffered-write, cancellation and failure-refusal assertions passed. These original/repaired measurements use separate harnesses and are not a byte-identical A/B performance experiment. The repaired Core module also compiled for arm64 iOS Simulator with Swift 6 and optimization; this is module compilation, not another whole-app UI acceptance run.

Artifacts are under the stability workspace `queue-io-lab/`: `telemetry-init-run1.*`, `telemetry-regression-run2.*`, `telemetry-ios-build1.*` and `telemetry-initialization-receipt.json`. The receipt binds the eight changed source/test files, original observation objects, test executable, iOS module/object and closed logs. Root verified exact named test counts, unchanged SQL and raw exits; no independent reviewer or new agent was used.

UserDefaults inventory, baseline, notification-journal and snapshot-cache decoding still occurs synchronously during FleetStore initialization. The snapshot decoder has a 2 MiB input bound and restores at most 128 devices, but neither that bound nor source inspection proves acceptable launch latency. No new hydration-order change or measured-defaults-speedup claim is made. Original Charts, reconnect and physical startup acceptance remain open.

## Combined storage regression validation, November 8 at 13:53 UTC

Committed repairs `112f014` (background celebration storage) and `9a39727` (deferred telemetry singleton opening) were validated together in an isolated optimized iOS Simulator build. The frozen 671-file runtime identity is `99c7e2741af2dd4e8db1d8ed340b3ea1df5b1ce4611f786c4d6efa40f619b071`. The build completed with raw exit 0 in 152.332 seconds.

All **117 existing native methods in eight suites passed**, with the native test footer reporting 2.459 seconds and the guarded runner taking 23.871 seconds. Selection comprised celebration queue (6), notification delivery (39), monitoring ownership boundaries (24), inbox encoding (12), persistence boundaries (13), notification windows (9), history-cache metadata (6), and startup maintenance (8). Assertions and workloads were unchanged. This combines the storage repairs with the earlier ownership and cache fixes; it does not count the separate Core initialization tests again.

Evidence under the private stability workspace:

- `results/integrated-io-build/receipt.json`: SHA-256 `f595636da0f16b432db689b705aaa2631c08697b2800d1c33081c5ca3315a381`.
- `results/native-integrated-io/receipt.json`: SHA-256 `aec71463067e9a87a9a45d8f1cca988f84ddfd1a9cd275851f89a90c630c0719`.

Root revalidated all runtime inventory entries, changed-file equality with the repository, all eight test-source files, closed-log and executable bindings, 117 unique test starts/passes, and the eight-suite footer. Both receipts retain unchanged-input and owned-process cleanup gates with no cleanup errors. A fresh native-idle check passed at 13:53:05 UTC. This was root verification, not independent review.

This is selected combined regression acceptance, not full integrated stress or UI acceptance. The original failing 120/2400-step chart workloads were not selected and remain failures. No claim is made that the Charts crash, reconnect resource growth, physical startup watchdog, or synchronous UserDefaults decoding has been resolved. No physical hardware or production data was used.

## Approved telemetry DatabasePool change, November 8 at 14:09 UTC

After the operator explicitly approved the telemetry-only change, file-backed telemetry now uses GRDB DatabasePool with at most two reader connections and one serialized writer. The production singleton still opens the database and prepares its schema in the retained detached task. Explicit synchronous constructors remain synchronous. In-memory storage and the existing injected DatabaseQueue constructor remain supported through GRDB's common DatabaseWriter interface. Celebration SQLite ownership is unchanged.

The filename, table/index definitions, SQL bodies and buffering/retry rules are unchanged. Pool initialization enables SQLite WAL. Because the installed GRDB pool defaults to NORMAL synchronization, the factory explicitly restores FULL on its writer before schema setup, preserving the prior default queue's commit policy. The existing database-size display now sums the owned main file, WAL and shared-memory files off MainActor. This is an approximate footprint, not a transactional measurement. There is no Core Data migration or fabricated busy-timeout policy.

Six new tests use real temporary SQLite files and the production pool factory: legacy queue-file conversion with identical schema and preserved rows after reopening; a held reader concurrent with a second reader and a committed telemetry write; snapshot consistency across that write; retained pending readings after a real external writer lock followed by exactly-once retry; failed-delete rollback with retained pending data; corrupt-file preservation; and WAL-aware size accounting. The concurrency test requires the second read and write to finish before releasing the held reader, and rejects a safety-timeout release. The factory is checked to execute off the main thread. These are behavior checks, not an overall application-speed benchmark.

Validation passed **40 XCTest methods plus 13 Swift Testing methods**, including the six new tests and all 47 previously selected database/init regressions with unchanged assertions. The first attempt failed compilation in a new test-only semaphore wait; its logs are preserved, and the corrected handshake uses a background dispatch queue rather than blocking a Swift cooperative executor. Package evidence is `queue-io-lab/telemetry-pool-receipt.json`, SHA-256 `893e170c47a4b3aea9565f09a2f2e5f10da0df00f14deeaec76bf40152fb6de6`.

The 672-file isolated candidate identity is `d72d80659b5d4f55c9f0d3fcd260ecd650576d20e8d825bd341a319379f59bac`. Its optimized iOS Simulator app build passed in 152.238 seconds, then the same unchanged **117 native methods in eight suites passed** (2.598-second test footer, 21.953-second guarded runner). Build receipt `results/telemetry-pool-build/receipt.json` hashes to `1c298554ff31047e992bc76e63a13f6c4830addd7e02b435e7935cb9b8b4007e`; native receipt `results/native-telemetry-pool/receipt.json` hashes to `19bd35a10aff4af8a0700961594abdc0ab8493b930d09c366524be07b9f82193`. Both retain successful cleanup and immutable-input gates. Root rehashed source, logs, products and test inputs after execution, and a fresh native-idle check passed at 14:09:13 UTC.

No additional agents or new diagnostic framework were used. Pool-specific runtime coverage is the macOS package suite, while the native simulator run verifies the existing app-level suites against the rebuilt candidate. No physical-device acceptance, whole-app latency gain, original Charts/reconnect fix, or independent final review is inferred. The previous sections describe historical queue-backed checkpoints and are superseded only for the explicitly approved telemetry connection type.

## Synthetic startup restoration and snapshot reuse, November 8 at 14:24 UTC

One added persistence test measures the synchronous MainActor `FleetStore` initializer using four synthetic UserDefaults scenarios, three repetitions each. It verifies restored device order, snapshots, cached readings, inbox identities, preserved serialized cache/inbox data, and expected automatic naming. The original 13 persistence tests are unchanged. Test data is freshly prepared in isolated defaults suites, baseline dictionaries are empty, and the simulator is warm. These measurements are not cold physical app launches or evidence of the original watchdog's cause.

Restoration constructed the same sanitized snapshot three times per restored miner. The production change computes it once and reuses its info and snapshot, preserving byte/entry bounds, timestamps, filtering, iteration order and automatic-name persistence. JSON decoding remains synchronous. No async hydration, persistence format, database or startup ordering change is included.

| Synthetic scenario | Cache bytes | Before median ms | After median ms |
| --- | ---: | ---: | ---: |
| 20 miners | 29,941 | 5.966 | 5.050 |
| 128 miners | 191,617 | 35.539 | 30.327 |
| 128 automatic names requiring updates | 191,617 | 77.730 | 66.670 |
| 128 miners plus 900 unrelated cached entries | 1,524,407 | 154.970 | 152.701 |

Each median uses only three observations from the identical test source. The large-cache case barely improved and remains a possible source of UI stalls. These small samples support removal of duplicate work, not a general performance guarantee or a claim that startup freezes are fixed. Raw observations remain in the stopped test logs.

Baseline identity `81caefac906af5b12a4a6d7bea560348fd24b758591f6d989f14a7107af484bc` and candidate identity `86cd5e4241bf5d0fe290bc23cf7f32dac358dfb047c5b5f3b3f88d768cfbabd2` each passed optimized simulator builds and the identical 14-method persistence run. Candidate build receipt `results/startup-reuse-build/receipt.json` hashes to `3ad81fd11c28599300e0768bf6115480becc25465e0cc98de3eea78fa13600b6`. Baseline native receipt hashes to `e62ce1363905d5f9e4739d15083ed9a5fcea11216da8d0b7925d867c6fa74450`; candidate targeted receipt hashes to `72674c18c5c48b7b506d57228edd14c60d49d789a87f7524c4559e8963cb07b4`.

The first combined attempt failed before test launch because the fixture's exclusive bind on port 50401 was unavailable. Its failed receipt and traceback remain at `results/native-startup-reuse-full`. No test failure or successful cleanup acceptance is credited to that attempt. After a fresh native-idle check and simultaneous exclusive availability checks for all 20 ports, one retry changed only its output directory. All **118 native methods in eight suites passed**, comprising the original 117 and the added observation, not 132 distinct tests. Receipt `results/native-startup-reuse-full-run2/receipt.json` hashes to `aedcf612f224f2abf8f37977b02486c5bfb424c1cc4f713de9f3d0ba20880dba`.

Root verified both complete runtime inventories, unchanged test bytes, repository/candidate equality, declared input/log/product hashes, exact unique test counts, and retained cleanup gates. A fresh native-idle check passed at 14:24:11 UTC. No additional agents were used. This is root verification, not independent review. Charts stress failures, transport resource growth and physical watchdog acceptance remain open.

## Batch restored automatic names, November 8 at 14:35 UTC

The next bounded change removes repeated inventory serialization during synchronous cache restoration. Previously every changed automatic name called `persist()`, encoding and saving the complete fleet again. Restoration now requests in-memory name updates, tracks whether any name changed, and saves once after the loop. Ordinary live callers keep the default immediate-save behavior. The name-selection rules, manual-name protection, demo rejection, device order, cache validation and corruption handling are unchanged. This intentionally changes intermediate restore checkpoints into one final save before the synchronous initializer returns; it does not defer that save to a task or change persistent data formats.

The original 14 persistence methods, including their startup measurement body, remain byte-identical. One added regression checks explicit deferred updates, no-op/manual/missing-ID cases, one caller-managed save, immediate live persistence, demo protection, and actual constructor restoration of two names with the final fleet persisted. The isolated optimized simulator build passed, the targeted 15-method suite passed, and all **119 methods across eight suites passed**. Those runs overlap and are not 134 distinct methods.

For the same three-repetition synthetic observation, the 128-device automatic-name median fell from **66.670 ms to 29.827 ms**. Its after samples were 29.827, 30.004 and 29.413 ms. Other medians were 5.042 ms for 20 miners, 29.367 ms for 128 manually named miners and 151.272 ms for the 1.52 MB cache. The last result remains close to the previous 152.701 ms: full-blob synchronous decoding is still present, and this change is not a solution to that large-cache cost. The same warm-simulator, empty-baseline and small-sample limitations apply. No physical launch-speed or watchdog claim is made.

Candidate identity `3ae68314350f8aa182453f5bae67dd71b17b16be57754bf5ac8fd71a8862f016` binds the 672-file source and exact three-file delta. Build receipt `results/startup-name-batch-build/receipt.json` hashes to `7da3d8e72f3f9bfca2cb702ed2589e84fa9bd1aef159bf0f597568114864f071`. Targeted receipt `results/native-startup-name-batch/receipt.json` hashes to `28b138aa39ae4374d063d77f7c2415bdaad41331670bcd79e7581c124f8b07eb`. Combined receipt `results/native-startup-name-batch-full-run2/receipt.json` hashes to `b8853663eddc6e0db7cc727fa08c7b58ea2507bb65008ef8481fc4834521133b`; the directory suffix is inherited from the accepted runner adapter, not evidence of two native runs for this candidate.

A preceding exclusive-bind preflight was refused before the combined runner started. No result directory, fixture or native test was launched by that attempt. A subsequent read-only listener/socket scan showed no matching entries, then all 20 simultaneous exclusive binds and native-idle checks passed before the single combined run. No process was killed to free a port. Root's final source/input/log/product/test-count verification and fresh native-idle check passed at 14:35:13 UTC. No new agents or diagnostic framework were used. Original Charts, transport-resource, physical-startup and independent-final-review requirements remain open.

## Combined native regression selection, November 8 at 15:43 UTC

One run on the existing shared-peer-close simulator build passed **122 unchanged methods across nine suites**: the preceding 119-method selection plus the three remote-close methods. The exact test footer reports 19.532 seconds; the runner records 38.872 seconds including setup and cleanup, with raw exit 0. No rebuild, new worker, altered test assertion or expanded timeout was needed. This supersedes the earlier limitation that these two selections had only been run separately.

The selection-only adapter `native_combined_122.py` hashes to `69652c57be7b0296d913ff8f2326d9b063ab0215d5f198b75f8741029ddd9485`. Its helper functions and main safety flow match the accepted peer-close runner, apart from the receipt scope text. All nine test-source pins match the repository. The frozen candidate's common runtime files differ from the repository only in the documented diagnostic app factory and local GRDB package reference. Source identity remains `cea73d2bd76b4aef24051f25620989820146285f815338d626b0cdaab05ff1ee`.

Stopped receipt `results/native-combined-122-run1/receipt.json` hashes to `77d24b7a1e0e5add7e8520fd60ea1d0f78a471a29700f72375742db4bac010cf`. Root rehashed all 18 declared inputs and four closed logs, checked 122 unique starts and passes with the exact nine-suite footer, and verified the recorded immutable-source/product and cleanup gates. Cleanup errors were empty. Across 35 app samples, system open files peaked at 11,839 against the exclusive 14,115 limit. Fresh native-idle and all 20 loopback-bind checks, using the existing preflight socket options, passed at 15:43:31 UTC. This is root verification, not independent review or proof of socket deallocation.

The original Charts stress failures, prolonged reconnect/resource-retention behavior, historical consumer-drain delay and physical startup watchdog remain unresolved. Also, the earlier 151.272 ms large-cache observation times the **entire FleetStore initializer**, not JSON decoding alone. Moving restoration to an unawaited task would change readiness and demo/backup ordering, so no such speculative patch was made.

## Serialize buffered clear and flush, November 8 at 16:10 UTC

Independent review identified a pre-existing reentrancy bug, not introduced by the pool conversion: a flush could snapshot buffered readings while a DELETE was suspended and insert that pre-clear batch after the delete committed. Two deterministic regressions hold a real SQLite DELETE with a trigger, start the competing flush, then join both tasks. The unchanged queue and pool cases failed before the repair with one resurrected row and `[20, 30]` instead of `[30]`, then both passed after it. Trigger timeout aborts the transaction and fails the test rather than manufacturing a pass.

A small MainActor FIFO gate now covers each flush or clear's SQL and buffered-memory changes. Flush snapshots only after acquiring the gate. Failed deletes retain pending readings, and every acquired gate is released by `defer`. Cancelled waiters still take and release their turn. This does not serialize pool readers, migrate storage, change SQL/schema, or make `recordReading` wait for disk I/O. The existing clear-through-commit buffer behavior remains unchanged.

The final package selection passed **26 XCTest methods plus 10 Swift Testing methods**, raw exit 0. Four ordering tests cover both real queue/pool reproductions, a cancelled FIFO waiter with no overtaking, and failed DELETE retention followed by successful flush and clear. The other XCTest methods cover maintenance, lazy initialization and pool behavior. Developer Support's ten methods are separate Core checks, not StoreKit purchase validation. Original red test bodies and helper are unchanged. Logs are retained under scratch `queue-io-lab/telemetry-clear-{red1,green1,boundary1}.{stdout,stderr,raw-exit}`. Final boundary stdout SHA-256 is `da39ff6ddae4bb71c41f301578f4477bfaecb39103051723eb72680f248d0deb`, and test source SHA-256 is `ca9905f4ae1144626aeec1590b4913008e39d23e24a84fe62873e94ff2a86a31`.

Elephant independently read the root-authored fix, original/current tests and stopped evidence, finding no concrete blocker within this scope. The earlier 122-method simulator run predates this repair and is not represented as post-fix acceptance. Final iOS integration, long-run transport, Charts and physical startup acceptance remain separate work.

### Post-commit persistence integration, 16:44 UTC

On `e8138f7`, an incremental package run passed 37 XCTest methods across the five
maintenance, clear-ordering, persistence, initialization and pool suites, plus
the 10 Core Developer Support Swift Testing methods. The existing 11 persistence
methods broaden the earlier 26-method database selection. All assertions were
unchanged, and stores were injected in-memory or temporary fixtures. Raw exit was
0, with 1.310 seconds reported for XCTest and 0.001 seconds for Swift Testing.
The empty filtered Watch test target is not included in these counts.

Closed logs are `queue-io-lab/telemetry-integrated-post-iap1.{stdout,stderr,raw-exit}`
under the session scratch directory. Stdout SHA-256 is
`f45fcc506086d50cabc3c4763fe1d32e11947d6735c739525749b5edfd90befa`.
Root checked the exact suite counts, zero failures, raw status and unchanged
worktree. This is post-repair macOS package regression evidence, not a rerun of
the 122 iOS methods, independent review, StoreKit testing, or resolution of the
remaining chart, transport and physical-startup failures.

### Cache restoration phase observation, 16:50 UTC

A scratch-only host probe compiled the exact production `MinerSnapshot.swift`,
`MinerSnapshotCacheEntry.swift` and `MiningDifficultyFormat.swift` against the
existing Core archive. It used the earlier synthetic cache shape, a unique
temporary defaults domain, and five repetitions per scenario. It did not create
FleetStore, start monitoring, read user defaults domains, or alter production.
All 15 observations passed count, sanitized-field, cached/reconnecting-state and
unchanged-stored-byte assertions. The temporary defaults domain was removed.

| Scenario | Entries / bytes | Defaults read median | Decode median | Prepare median | Apply median |
| --- | --- | --- | --- | --- | --- |
| 20 devices | 20 / 29,941 | 0.0015 ms | 1.8203 ms | 0.9499 ms | 0.0086 ms |
| 128 devices | 128 / 191,617 | 0.0209 ms | 10.2867 ms | 5.7260 ms | 0.0470 ms |
| 128 devices plus 900 unused entries | 1,028 / 1,524,407 | 0.1337 ms | 81.2866 ms | 5.8118 ms | 0.0496 ms |

Within this probe, full-map Codable decoding dominates the large-cache case.
Preparation includes the actual restored-model sanitization and second cache-entry
construction. Application measures plain dictionary insertion, not Observation
invalidation, automatic-name updates or notification-journal restoration. The
probe/model sources were optimized, but the reused Core archive was a Debug
artifact. These warm macOS measurements are not directly comparable to the
earlier optimized iOS whole-initializer measurement, and do not prove physical
watchdog causality or a speedup. No readiness-changing asynchronous restore or
selective decoder was installed.

The first two compile attempts failed on missing local module/helper inputs,
then compilation succeeded after adding the existing GRDBSQLite module search
path and exact formatter source. No production source or probe assertion changed
between those attempts. Probe and execution raw statuses were 0. Files are under
scratch `queue-io-lab/CacheRestorePhases.swift` and `cache-restore-phases1.*`.
Probe SHA-256 is `a5b4ae2396958877fbd3c28419c206abb218a0416c89821f8dd95be1120dd00f`;
stdout is `703657522f790fb4665045fb7fd7251f04639ad7ef476c80b0250de4b142a983`;
the linked Core archive is `8081e18b3ad06b67626a3d14ad90ba429cccddd288688cb3f82f82dc5efe45b5`.

### Rejected selective-cache shortcut, 16:54 UTC

A bounded worker assessment proposed JSONSerialization filtering to active device
keys before Codable decoding. Root rejected its unmeasured speedup and unchanged-
corruption-behavior claims. A 32-line, in-memory probe using the same exact
production model sources confirmed three counterexamples: an unused entry with
an invalid date, a non-object `fields` value, or missing `fields` makes the existing
full-map decoder reject restoration, while the proposed filter accepts the active
entry. Compilation and execution exited 0. Source and output are retained as
`queue-io-lab/CacheFilterCompatibility.swift` and `cache-filter-compatibility1.stdout`.
The worker retracted the proposal and performance claims. No selective decoder
or production change was installed.

The source review also confirms that the app and other callers construct FleetStore
synchronously. Merely launching an unawaited restore would change readiness and
could publish stale state after demo/backup operations. Visible flicker and an
actual asynchronous race were not executed or observed here. A future off-main
preparation path needs an explicit awaited handoff and lifecycle tests, not a
claim that changing the constructor alone preserves existing callers.
