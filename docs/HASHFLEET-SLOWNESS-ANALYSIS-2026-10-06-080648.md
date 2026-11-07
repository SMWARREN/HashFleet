# HashFleet / HashFleet intermittent slowness: ten-role analysis

**Date:** October 6, 2026. **Mode:** analysis only. **Requested handoff:** cow, for independent analysis-only review. **Acceptance follow-up:** real installed-app profiling and production CLI observations added after the initial report.

## Bottom line

The strongest measured UI priorities are now **main-thread layout and WebP/image decoding** in the actual installed app. A native 20.7-second Time Profiler recording contained 15.894 seconds of main-thread CPU sample weight, including 31.6% with the app's balanced-columns layout on stack and 27.6% with WebP decoder frames. These are inclusive, overlapping sampling categories, not precise frame durations or proof of every intermittent freeze.

Two reporting problems were also verified: large miner log exports can delay ordinary telemetry by several seconds, and the shared formatter can display a real Mac-scale hashrate as zero. Optional WAN refresh waits remain a source-backed mechanism without measured incident timing. **The analysis is better evidenced, not the app made faster:** no performance implementation or before/after fix was performed.

The closing live check at **08:33:49-08:33:53 UTC / 04:33 EDT** found all four ASICs hashing with **24/24 domains**, reported ten-minute total **22.101 TH/s**, and the M1 mining unpaused. This does not erase earlier genuine 601a domain loss or certify pool-calibrated performance. No app/firmware implementation, miner setting, service, pool, fan, frequency, voltage, recovery lockout, firmware, self-test, restart, or wiring change was made by this analysis. Evidence and documentation are the only changes.

A separate real-interface follow-up at **09:01:57-09:02:02 UTC / 05:02 EDT** checked info/logs on all four ASICs and documented M1 SSH/XMRig reads again. All eight ASIC endpoints returned 200, all 24 domains worked, compared returned configurations and supervisor attempts/lockouts/pending remained unchanged, and accepted work progressed without new rejects. Reported ten-minute ASIC total was **22.096 TH/s / 280.04 W**, with the same mining Mac PID 52840 unpaused at **2.145 / 2.141 / 2.136 kH/s**. These remain dated, uncalibrated observations.

## Priority findings

### 1. Measured installed-app cost: layout and image decoding on the main thread

The actual `/Applications/Hash Fleet.app` wrapper was found running as **HashFleet PID 58178**, bundle `app.hashfleet`, version 0.1.0 (6), iOS-on-Mac, launched **08:30:34 UTC**. The running App Translocation executable and installed executable had matching SHA-256 `0a6ee96292ea78177583b8496931dd71e658f404e5b3963f186a4dbc19be29a0`. This is the real installed application, not a simulator, demo fixture, stub, or rebuilt copied-source harness.

**Correction:** the initial review did not recognize this running app. Its launch time predates the original closing check, so the earlier statement that no app was available is not a valid continuing blocker.

Read-only process CPU readbacks ranged **66.9-98.2%** during the passive observations. A successful standard Time Profiler recording at **09:00:01.859-09:00:22.582 UTC** produced 16,022 target CPU samples, 15,894 on the main thread, all at 1 ms sample weight. The main thread accounted for **99.2% of target CPU sample weight**.

| Actual main-thread stack category | Inclusive sample weight | Share of main-thread sample weight |
| --- | ---: | ---: |
| Graph update / transaction work | 8.160 s | 51.3% |
| `FleetBalancedColumnsLayout` | 5.026 s | 31.6% |
| WebP decoder frames | 4.394 s | 27.6% |
| ImageIO frames, including WebP | 4.628 s | 29.1% |
| FleetStore persistence methods | 0.057 s | 0.36% |

**Do not add these overlapping categories.** The balanced layout's placement and measurement paths occur directly in the native stacks. Top decoder frames `GetCoeffsFast`, `GetLargeValue`, `VP8ParseIntraModeRow`, and `DecodeImageData` resolve to **ImageIO**. These observations prioritize layout/decoder work over persistence for this window, but do not identify one particular asset or the initiating invalidation.

Source context: `FleetBalancedColumnsLayout.swift:46-75` measures child layouts during sizing and placement without a geometry cache. `AnimatedWebPImage.swift:45-166` owns a main-actor image view, advances on a main-run-loop display link, and creates frames without ImageIO caching. Connecting a particular animation to repeated layout invalidations remains an inference to validate, not an already measured cause-and-effect chain.

The passive recording had **zero potential-hang rows at a >250 ms reporting threshold**. That does not exclude short frame hitches, poor frame pacing, or intermittent hangs outside the recording. Of the samples, 1,162 stacks were truncated. The initial combined CPU Profiler/SwiftUI/Hitches/Hangs configuration failed as unsupported and is preserved as a failure. A separate ten-second SwiftUI-only recording subsequently exited 0 but warned **"Trace file had no SwiftUI data"**. It supplies no SwiftUI cause graph or frame-timing observation and is not counted as successful UI instrumentation. A deep accessibility lookup also timed out after 20 seconds, which is not by itself proof of an app freeze. No launch, installation, activation, click, preference change, or restart was performed by this analysis.

**Source and binary scope:** initial source review was against `f6766374bb903b72d35159602319fd93f0e6e6a2`. Other work advanced the repository to `1881dcb03ad06bb26ab6ef669ff9f0e505ef1382` during follow-up. Matching running/installed executable hashes attest the sampled binary, not a build relationship to either source revision. Source line references explain the reviewed mechanisms, while the native runtime stacks independently establish the measured layout and decoder cost. No concurrent repair is credited to this analysis or certified by its passive recording.

**Later validation, not applied:** use a controlled, authorized comparison of static versus animated artwork and cached versus repeated layout measurement, with actual frame timing. Do not claim this passive profile demonstrates a successful performance fix.

### 2. Confirmed: full log downloads block same-board HTTP telemetry

At **08:09 UTC**, ordinary info GETs took **67-84 ms**. Four log GETs took **2.848 / 2.964 / 3.406 / 4.505 seconds**. A bounded overlap check on original Naja `.226` at **08:14:09-08:14:15 UTC** measured:

| Operation | Duration | Response bytes |
| --- | ---: | ---: |
| Earlier normal info GET | 0.067057 s | about 5 KB |
| Full log export | 5.794934 s | 528,414 |
| One info GET started 205 ms into that export | **5.631348 s** | 5,430 |

The info response completed **41.679 ms after the log export finished**. Both returned HTTP 200. This directly establishes a multi-second same-board reporting delay under the tested overlap, not an ASIC hashing stall or measured UI freeze.

Source: `ESP-Miner-profit-switch/main/http_server/http_server.c:133-160` streams the log ring synchronously in 4096-byte chunks, from `abs_pos=0`. `websocket.h` configures a 512 KiB ring. The HTTP server task executes the handler while it exports this data. The log-buffer mutex is taken and released **per chunk, before the TCP send**. A claim that the mutex is held throughout network transmission is rejected. The measured delay is consistent with synchronous server occupancy during the large export, not established as lock contention or ASIC CPU starvation.

Actual M1 process/LaunchAgent reads at **08:15:30 UTC** confirmed the recorder and recovery watchdog are active. `fleet_recorder.py:145-156,294-296` fetches full info and logs for each of four boards every 30 seconds, then locally retains only a bounded log tail. `fleet_watchdog.py:560-580,680-683` normally reads **info only** in `--run` mode. Its log reads occur on recovery/verification paths, not every normal tick. The initial claim of eight standing log exports per 30-second cycle is rejected.

**App caveat:** `MinerEndpoint.swift:99-103` configures a **15-second** ordinary request timeout. The measured 5.63-second stall is below it, so it is not evidence of a production app timeout. Configured request timeouts are not a universal wall-clock deadline for every multi-step refresh.

**Later options, not applied:** bounded/incremental log exports, lower/staggered log cadence, or carefully validated asynchronous export handling. Do not allocate another 512 KiB snapshot casually on the ESP or stop safety monitoring as a shortcut.

### 3. Source-confirmed: the refresh spinner waits for optional internet data

`App/Features/Dashboard/DashboardView.swift:354-364` starts both `store.refresh()` and `insights.refresh(force: true)` and awaits both when external data is enabled. `FleetSplitView.swift:68-77` follows the same pattern.

`App/Store/MiningInsightsStore.swift:126-145` joins public network, pool, coin, and market requests before publishing the combined result. The forced path bypasses the non-forced cooldown and market cache gating (`:103-123`). `MiningInsightsClient` uses 15-second request timeouts.

Thus local miners can answer promptly while pull-to-refresh still waits on an optional WAN service. This is a high-confidence code mechanism, **not a measured third-party outage or spinner duration in this session**. Async waiting does not imply the main thread is blocked.

**Later validation:** time local-info completion and spinner completion separately, then compare equivalent refreshes with external data disabled in a controlled fixture or an already-authorized app session. No preference was changed in this review.

### 4. Confirmed function defect: the Mac's real hashrate can render as zero

The M1 returned **2139.09 H/s**, about **2.139 kH/s**, in the 08:09 live capture. `Sources/HashFleetCore/XMRigAPIClient.swift:99-102` normalizes H/s to GH/s by dividing by one billion. This is numerically valid normalization, but the display lacks appropriate small-unit scaling.

`Sources/HashFleetCore/FleetFormat.swift:23-32` supports GH/s and TH/s only, and rounds values below 1000 GH/s to zero fractional digits. `App/Features/Miner/XMRigControlView.swift:37-46` calls that formatter directly. The resulting `0.00000213909 GH/s` formats as **`0`**. Generic unit-bearing surfaces can consequently show `0 GH/s`.

An isolated executable compiled the **original formatter source** against minimal sensor-type declarations and reproduced `0` / `GH/s` for the actual measured input. No application build, launch, installation, or miner command was performed. This proves function behavior and a source call path, not the exact installed UI binary or every tile's appearance.

**Impact:** misleadingly slow/zero CPU mining presentation. This is separate from UI responsiveness. **Later option:** algorithm-aware H/s, kH/s, MH/s, GH/s, TH/s formatting and separate RandomX vs SHA-256 totals, with low-scale tests.

### 5. Source-backed candidate, not dominant in the sampled window: persistence and snapshots

`FleetStore` is MainActor-owned. Poll results and live frames reach `FleetStore+Evaluation.swift:18-80`, which saves state, best-share, and block observation baselines (`:113-114,171,197`) through synchronous JSON/UserDefaults helpers. `FleetStore+Persistence.swift:97-121` also encodes the entire cached-readings dictionary, with a **per-device five-second throttle** and a 2 MB cap. The small baseline maps have different guard behavior and should not be conflated with the cache throttle.

`HashFleetApp.swift:199-209` keys glance publication by a glance containing an advancing timestamp. `FleetGlanceCoordinator.swift:69-105` throttles **widget timeline reloads to 60 seconds**, but not every App Group snapshot save. Timestamp changes can keep triggering those saves even if the useful metric content barely changes.

These are verified source paths. Their contribution to particular frame stalls remains unmeasured. The real follow-up profile contained only **57 ms of main-thread sample weight with FleetStore persistence methods on stack**, versus 5026 ms with the balanced layout, so the earlier unprofiled priority must not be treated as measured dominance. Other windows and burst patterns can differ. Do not declare synchronous disk flushes or a definite rendering freeze merely from `UserDefaults.set` calls.

**Later validation:** release-build signposts around each encode/save, main-thread Time Profiler samples, and a SwiftUI cause-and-effect trace. Compare live-frame frequency, storage calls, and actual frame gaps before proposing a debounce/change-only publication fix.

### 6. Secondary source-backed candidates, not established bottlenecks

- **Slow-member bootstrap:** `FleetStore.swift:311-349` polls sequential batches of four. Results publish **incrementally within a batch**, so one slow miner does not withhold completed batch-mates. It can delay later batches, the refresh spinner, and live-monitoring startup, which awaits full HTTP bootstrap (`FleetStore+Monitoring.swift:30-47`). The fifth device's actual ordering was not inspected. Existing per-device live tasks, cancellation/generation guards, freshness checks and backoff remain real safeguards.
- **Rendering cadence:** store-wide observable updates, repeated fleet totals/sorts, a 15-second chain-card timeline, and live-sort grid animation are plausible amplification points. Their cost is unmeasured and sorting four/five devices alone is unlikely to explain seconds of delay.
- **History windows:** GRDB writes are batched/async and composite miner/time indexes already exist (`MinerTelemetryDatabase.swift:122-125`). Longer-window history still materializes all matching rows (`MinerTelemetryDatabase+Reading.swift:62-85`, `FleetHistoryCard.swift:245-284`). Profile actual rows/query/map/chart cost before attributing long-window slowness. The current-session chart uses bounded in-memory history, not that same long SQL path.
- **First use / resume:** shared DB initialization and schema setup are synchronous, while scene/monitoring-identity changes can restart bootstrap/maintenance. Menu-bar code also has two two-second update paths. These are conditional candidates, not measured launch or resume regressions.

## Complete tracked fleet readback

Timestamp: **October 6, 08:33:49-08:33:53 UTC / 04:33 EDT**. Values are dated observations, not continuously current telemetry.

| Member | Profile MHz / mV | Domains | Reported 10m rate | Chip / VR C | Reported W |
| --- | --- | --- | ---: | --- | ---: |
| Gamma 602 `.215`, **5 V only** | 750 / 1135 | 4/4 | 1.527 TH/s | 58.5 / 53 | 19.82 |
| Gamma 601a `.221`, 12 V | 525 / 1080 | 4/4 | 1.073 TH/s | 50.5 / 41 | 16.26 |
| Naja Duo `.226`, 12 V | 715 / 1130 | 8/8 | 9.888 TH/s | 51.3, 56.9 / 73 | 121.61 |
| Naja Duo 2 `.232`, 12 V | 695 / 1130 | 8/8 | 9.614 TH/s | 57.3, 61.4 / 74 | 121.78 |
| M1 mining Mac `.127` | XMRig PID 52840, unpaused | CPU RandomX | 2.045 / 2.116 / 2.135 kH/s, 10s/60s/15m | Not measured | Not measured |

ASIC total **22.101 TH/s / 279.47 W reported**, not calibrated pool throughput or a wall-meter reading. From the 08:09 initial capture, ASIC accepted counters advanced **+58 / +29 / +333 / +313**, rejected counters unchanged, and uptimes progressed consistently. M1 accepted work advanced **+5**, with no new rejection and the same PID. Supervisor attempts/pending/lockouts were unchanged. The original Naja's retry-budget lockout and other tuning holds were not cleared.

## Earlier real mining interruptions are preserved

The coherent read-only recorder query requested **October 5 08:14:05 through October 6 08:14:05 UTC**. It returned 2871 samples per Gamma and 2860 per Naja, with ordinary roughly 30-second sampling.

- **601a:** 893 observations with 3/4 domains and one missing-domain startup observation occurred in this 24-hour window. This was genuine earlier loss, not merely UI lag. The 525/1080 profile has 1347 observed 4/4-domain rows through 08:13:37 UTC. This does not prove no sub-poll fault or permanently repaired hardware.
- **Both Najas:** the 361-second gap and 01:20:37/38 UTC power-on starts remain an **operator-reported intentional paired power cycle**, not an unexplained spontaneous outage.
- **Duo 2:** accepted 3350 to 2 at 05:38:10 UTC with continuing uptime is a separate session counter reset. The newly added 08:00 canonical playbook diagnosis corroborates saved Wi-Fi/pool reconnect logs with `reset_share_stats()` in the exact installed build. The initiating cause of Wi-Fi loss remains unknown. Do not subtract counters across resets or claim previously pool-accepted work was erased.

## Ten-role roster and honest completion limits

Operator routing remained `auto`, with no model/account override or configuration change. These are actual persisted routes, not benchmark quality claims. Account labels were not exposed in the inspected session snapshots and were not guessed.

| Role | Analyst / actual route | Result used |
| --- | --- | --- |
| 01 UI rendering | fish, Claude OAuth / claude-sonnet-5 | Source review, impact unprofiled |
| 02 polling latency | fox, NVIDIA NIM / z-ai/glm-5.3 | Completed source review, corrected batch/timeout semantics |
| 03 history/charts | hamster, NVIDIA NIM / poolside/laguna-xs-2.1 | Worker decode timeout, coordinator source-verified recovery |
| 04 task lifecycle | lobster, NVIDIA NIM / nemotron-3.5-lightning-30b-a3b | Incorrect no-timer/no-automatic-poll claims rejected, coordinator correction |
| 05 startup/navigation | ladybug, Claude OAuth / claude-sonnet-5 | Source review, cost unprofiled |
| 06 Mac/internet integration | giraffe, Claude OAuth / claude-opus-4-8 | Completed source review |
| 07 persistence/notifications | original owl, NVIDIA NIM / nemotron-3-ultra-550b-a55b; replacement snake, NVIDIA NIM / moonshotai/kimi-k3 | Overloaded original stopped, replacement completed |
| 08 ASIC health | ox, Antigravity / gemini-3.8-flash-tiered | Current data used, overbroad historical/causal claims qualified |
| 09 share/display semantics | pig, Claude OAuth / claude-sonnet-5 | Reload-interrupted conclusion recovered and independently reproduced |
| 10 firmware responsiveness | mosquito, Claude OAuth / claude-opus-4-8 | Completed, mutex/cadence claims corrected against evidence |

Ten roles were covered. There were **eleven worker launch attempts** because the overloaded seventh slot was replaced, not an added eleventh review role. Two interrupted/failed scope reports needed coordinator recovery, and a materially incorrect report was not accepted blindly. This is not a claim of ten independently passing final reports or unanimous model consensus. The user-requested independent cow review should prioritize these quality and causal limits.

## Validation and artifacts

- Initial live/recent-history verification: **45/45 passed**.
- Final offline requirement-to-observation replay: **57/57 passed**, including current health/configuration continuity, preserved historical incidents, the HTTP overlap, and exact-source formatter output.
- **26 saved ASIC HTTP requests in the original capture**, all whitelisted info/log GETs. The later acceptance capture has eight additional info/log GET records, with actual packaged CLI calls recorded separately. M1 operations were documented SSH/XMRig/status reads and coherent SQLite `mode=ro` / `query_only=ON` transactions.
- The initial review failed to recognize the installed app. Follow-up passively observed and profiled the already-running real process. No app launch/installation, full application build, or simulator run was performed by this investigation. Precise frame-hitch attribution and pool-calibrated throughput remain unmeasured.
- App source revision inspected: `f6766374bb903b72d35159602319fd93f0e6e6a2`. Firmware revision: `b44ff447555af74ee44a034815bf0e6de7169006`, matching the reported fleet build.
- Private evidence root: `/Users/USER/.jcode/scratch/fleet-slow-analysis-20261006-080648/`. Read sanitized `live/summary.json`, `followup/summary.json`, `closing/summary.json`, `transport-summary.json`, `history-window-summary.json`, `offline-validation.json`, `formatter-check-result.json`, and role reports/review qualifications. Raw info/log exports stay owner-private and must not be published.
- Actual native samples and exports are under that root's `runtime/`; `runtime-observations.json` is the bounded summary. Raw native traces can contain process/environment information and remain owner-private.
- Follow-up real-interface evidence is `/Users/USER/.jcode/scratch/fleet-slow-acceptance-20261006-085336/`: sanitized `production-cli-observations.json` and `real-interface-requirement-checks.json` map observations to individual requirements. The first 30 observation predicates passed. The final replay adds an explicit SwiftUI no-data constraint predicate, with all 31 passing. Explicitly unclosed UI/review paths are not converted into passes.

## Requirement and changed-output acceptance mapping

| Requirement or changed output | Actual check and observed result | Limit |
| --- | --- | --- |
| Ten-person swarm analysis | Ten initial scoped analyst session metadata files and reports exist, plus one documented replacement. Failed/recovered/rejected outputs remain identified. | Not ten independently passing final reports or unanimous consensus. |
| Analyze actual intermittent app slowness | Real installed app window observed, installed/running binary hashes match, native Time Profiler recorded CPU stacks. Balanced layout and ImageIO/WebP costs are now measured. | Not a controlled before/after fix or exact frame-hitch cause. |
| Distinguish stale telemetry from hashing | Real ASIC info/log GET overlap measured a 5.63-second delayed info response. Separate fresh all-five checks showed work and uptime progression. | One bounded overlap, not hashing starvation or cross-board contention. |
| Analysis only | GET guards, read-only CLI status commands, SSH/XMRig reads, unchanged compared fleet configuration and supervisor fields, unchanged mining PID, and documentation-only owned commit. | Hidden settings and changes by other tasks are not globally certified. |
| Real project/public monitoring path | **Installed packaged `hashfleet status --json`** read all four real ASICs in **90.9 ms**, exit 0. Its human-readable table returned four online rows in **103.4 ms**, exit 0. | These healthy reads were after log exports completed, not a claim all refreshes are this fast. |
| Integration and input failure modes | Packaged CLI retained a healthy `.215` beside a refused `127.0.0.1:1` TCP member in **99.0 ms**, exit 1. A path-bearing miner address returned an error/no fabricated reading in **9.5 ms**, exit 1. | Real local TCP/validation boundaries, not firmware fault injection or WAN-timeout coverage. |
| Mac display defect | Real M1 API input plus original shared formatter reproduction and its source call path. | The observed installed app header lists four miners. A configured M1 control view was not independently observed, and no miner/preferences were added to force acceptance. |
| Consolidated report and panel | Owned report committed, readable from its real file, and desktop panel confirmed linked to that file and unfocused through `panel list`. | Display delivery does not prove the user or cow read every finding. |
| Canonical playbook current-state output | New all-four info/log and M1 evidence is explicitly dated 09:02 UTC, with old 08:33 and historical incident evidence retained. | Replay times are not live observation times. The private ignored playbook is not force-added to Git. |
| Ping cow, say the app is slow, request capable review | Cross-swarm DM tool confirmed delivery to cow, including the user's slow-app report, findings, quality limits and independent analysis-only review request. Subsequent measured priorities were also delivered. | Cow acknowledgement and completed downstream independent review have not been observed. |

**Improved result:** the analysis moved from unprofiled UI candidates to measured costs on the actual packaged app, exercised the actual production CLI's happy and failure paths, and corrected the earlier unavailable-app claim. **Not claimed:** the app became faster, every slow interaction was explained, or cow finished reviewing. Controlled refresh/WAN timing, cold launch/resume, chart-window transitions, widgets, and exact Mac-control display remain outside the exercised end-user path. No existing preferences, implementation, app installation, or mining operation was changed to manufacture acceptance.

**Public methodological references consulted:** Apple's *Understanding and improving SwiftUI performance* and *Optimize SwiftUI performance with Instruments*, and Espressif's *ESP-IDF HTTP Server* documentation/async-handler example. They support the profiling and server-concurrency method, not the private measured fleet values or a specific UI-cause claim.

## Requested next step for cow

The user reports that **HashFleet/HashFleet intermittently runs slowly** and explicitly asked for the finished findings to be sent to cow. Please arrange an independent, capable, analysis-only review under your configured swarm routing. Prioritize the now-measured balanced-layout and WebP/ImageIO costs, then distinguish WAN-spinner waits, same-board HTTP reporting delays, and actual frame hitches. Treat persistence/glance costs as secondary until a representative trace establishes otherwise. Challenge the findings and review the rejected/qualified reports before accepting them. No performance implementation or mining change is authorized by this report.
