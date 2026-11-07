# HashFleet/HashFleet slowness analysis: whole-result acceptance

Date: October 6, 2026. Analysis only. This addendum preserves the original report at `39a0041` and cow's independent review at `1bc1cf5`. It reports the actual interfaces exercised and the paths that were not accepted. No faster-app or hardware-repair outcome is claimed.

## Verified result and why the analysis is better

The original source-level candidates were checked against the **already-running installed app**, not a rebuilt sample. Its successful 09:00:01.859-09:00:22.582 UTC native CPU recording contained 16,022 target samples, 15,894 main-thread samples and 1,162 truncated stacks. Cow independently resolved the original XML reference graph and reproduced the counts and weights:

| Inclusive main-stack category | Weight | Percent of main weight |
| --- | ---: | ---: |
| Balanced-column layout | 5026 ms | 31.62% |
| WebP decoding | 4394 ms | 27.65% |
| ImageIO, including WebP | 4628 ms | 29.12% |
| Matching FleetStore persistence | 57 ms | 0.36% |

**These categories overlap. They are not additive, exclusive CPU costs, exact frame latency or proof of a specific invalidating asset.** This actual observation replaces an unmeasured persistence priority with measured layout/decoder priorities for the sampled window. The independently matching recount is stronger than source inspection or worker-ready status. Zero >250 ms potential-hang rows does not certify hitch-free behavior. The SwiftUI-only attempt warned that it had no SwiftUI data, so frame/cause-graph acceptance remains unavailable.

A separate real same-board HTTP overlap at 08:14 UTC measured a 528,414-byte log export taking 5.794934 seconds and an overlapping info GET taking 5.631348 seconds, completing about 42 ms after logs. This is evidence of same-board HTTP head-of-line delay, **not measured ASIC hashing starvation or a multi-board mutex**. The per-chunk log mutex is released before TCP send. Standing recorder load is four log GETs plus four info GETs per 30 seconds. The normal watchdog loop adds four info GETs, with logs only on recovery/verification paths. The app's 15-second timeout was not reached by that captured delay.

The shared formatter's exact-source reproduction showed M1-scale 2139.09 H/s becoming a displayed zero after GH/s normalization. This is a formatter-function result, not observation of the installed M1 control. Refresh joins, layout invalidation initiators, long-history materialization and lifecycle behaviors remain source-correlated candidates where no incident timing was captured.

## Every requested requirement and changed output

| Requirement / output | Actual check or observation | Result / limit |
| --- | --- | --- |
| Ten-person analysis | Original session metadata, ten role reports and replacement record replayed by the actual verifier | Ten roles, eleven attempts. Failed/rejected/interrupted outputs disclosed, not ten unanimous independent passes. |
| Analysis only | GET-only request provenance, documented read-only SSH/XMRig reads, returned-config digest comparison, mining PID/work continuity and unchanged compared supervisor recovery fields | No app/miner implementation, restart, self-test, firmware, setting, service, policy/lockout, preference or wiring operation issued. Hidden configuration is not certified. |
| Cover the whole fleet | Real info/log GETs to all four ASICs and documented M1 checks at 10:18 UTC | Eight HTTP 200 responses, 24/24 domains and M1 SSH success. All-five dated observations, not current-UI or continuous-health certification. |
| Explain intermittent reporting delay | Actual original same-board overlap and exact firmware source | 5.631-second delayed info response tied to synchronous log export. ASIC CPU/throughput impact was not measured. |
| Explain app-side load | Actual installed-binary CPU trace plus cow's independently resolved recount | Layout/WebP priorities measured. No exact frame-causality or before/after speedup claim. |
| Preserve history and misleading displays | Actual recorder history, original discontinuities and exact formatter-source reproduction | Domain loss and paired power-cycle gap retained. Duo 2 reconnect reset was not relabeled a reboot. Installed M1 control remains unobserved. |
| Public interface and packaging happy paths | Actual `/Applications/Hash Fleet.app/CLI/hashfleet` help and four explicit-host JSON/table invocations | Correct real outputs and exit 0. Not a custom app harness or mock endpoint. |
| Partial-failure and input edges | Same shipped CLI, healthy ASIC plus refused local TCP port and path-bearing input | Healthy result retained; failed members have errors/no info; exit 1. No fabricated success. |
| Configured default integration boundary | Actual shipped `hashfleet status --json`, without hosts | **Not accepted:** exit 1, "no miners configured". Current source uses `FleetSharedStore.readDevices()`. Missing/empty/undecodable shared data can return an empty list; the actual cause was not established. No preferences changed. |
| CPU/RandomX integration boundary | Actual documented M1 SSH/XMRig interface and shipped CLI help/source | SSH path exercised. No advertised explicit-kind CLI flag, so explicit CPU-kind CLI and installed M1 control were not accepted as tested. |
| Current GUI availability | Read-only accessibility and `ps -p 58178` | **Unavailable at 10:23:38 UTC:** old main-app PID absent. Widget presence is not main-app availability. Disappearance time/cause unknown. No app stop/relaunch/input issued. |
| Send cow slow-app findings and ask for capable independent review | Actual sent DMs, received 09:55:58 UTC review, committed-file/hash/recount check and acknowledgement reply | Cow's review completed and acknowledged. Three roles required five attempts; unsupported worker claims were rejected. |
| Original and peer delivered reports | Git committed-file identity and actual unfocused desktop linked-file panel list | Original `39a0041` bytes preserved. Peer `1bc1cf5` remains in Git, with a closure-audit link added by cow in `064b7fbb`. Both report panels present. |
| Canonical latest-state output | Actual 10:18:40.784 UTC capture, per-board numerical table and safety/history checks | Timestamp comes from telemetry, not review or replay time. Private ignored playbook updated without force-adding it to Git. |
| This public addendum | Whole-result verifier compares every mapped fresh observation, delivered output, version and privacy restriction | Documentation-only change. Raw telemetry remains owner-private. No wallet, pool password, Wi-Fi credential or private key included. |

## Whole-result execution, not just aggregate counts

At **10:13 UTC**, the actual original verifier files ran together with all predicates unchanged: 57 original evidence predicates, 31 real-interface/runtime predicates and 35 delivered-output predicates, followed by cow's actual reference-resolving native checker. Only result destinations were redirected. Network access was forbidden in this saved-evidence stage. Every check's requirement and observation is retained in the phase files. All **235 hashed original inputs were unchanged at that stage**.

At **10:18:36.077-10:18:40.784 UTC**, a new bounded actual all-five capture completed. Compared with 09:02 UTC, all four returned-configuration digests matched. Accepted shares advanced **+166 / +104 / +1040 / +1004**, rejects were unchanged and all ASIC uptimes advanced 4598 seconds, consistent with collection spacing. M1 retained PID 52840, was unpaused and advanced from 6185/6185 to **6196/6196** accepted/submitted. Compared supervisor attempts/lockouts/pending fields were unchanged. Missing fault fields are not falsely reported as independently clear.

| Member | MHz / set mV | Actual mV | Reported 10m TH/s | Domains | Chip(s) / VR C | Reported W |
| --- | --- | ---: | ---: | --- | --- | ---: |
| Gamma 602 (.215, **5 V only**) | 750 / 1135 | 1130 | 1.526 | 4/4 | 58.4 / 53 | 19.86 |
| Gamma 601a (.221, 12 V) | 525 / 1080 | 1076 | 1.067 | 4/4 | 50.6 / 41 | 16.28 |
| Naja Duo (.226, 12 V) | 715 / 1130 | 1125 | 9.903 | 8/8 | 51.8 / 57.3 / 74 | 121.92 |
| Naja Duo 2 (.232, 12 V) | 695 / 1130 | 1125 | 9.598 | 8/8 | 57.9 / 61.8 / 75 | 122.34 |
| M1 (.127) | PID 52840, unpaused | Not applicable | 2.101 / 2.133 / 2.124 kH/s (10s/60s/15m) | CPU RandomX | Not measured | Not measured |

ASIC total **22.094 TH/s / 280.41 W reported**, calculated from unrounded APIs, not pool-calibrated throughput or wall-meter power. M1 temperature/power were not measured. All electrical ceilings and existing recovery holds remain in force, including 601a <=1150 mV and no extra fans on its header.

The shipped CLI, not a substitute executable, then exercised six real paths:

| Actual case | Duration | Exit | Observed outcome |
| --- | ---: | ---: | --- |
| Help | 9.9 ms | 0 | Read-only status usage; no advertised explicit-kind flag |
| Four explicit hosts, JSON | 105.2 ms | 0 | All four have info, no errors |
| Four explicit hosts, table | 108.9 ms | 0 | Four online rows, every host represented |
| Healthy ASIC plus refused TCP peer | 66.3 ms | 1 | Healthy info retained; peer error/no info |
| Path-bearing address | 10.0 ms | 1 | Error/no fabricated info |
| Configured default, JSON | 6.9 ms | 1 | **Blocked acceptance:** "no miners configured"; no fleet JSON |

These fast explicit-host observations occurred after log exports completed, not during the historical overlapping export. They do not disprove the measured delay. The default integration failure is a separate newly observed limitation, **not established as the cause of intermittent GUI slowness**.

After the 10:13 passing stage, three identified inputs were revised: this analysis updated the canonical dated state, and cow updated the scratch profile checker and appended a closure-audit link to the peer report. The other **232 original input hashes remain unchanged**, including the raw native export, original capture/receipt data and original `39a0041` report. Cow's original `1bc1cf5` report remains preserved in Git. Its append-only public follow-up is committed as `064b7fbb`. These are explicit versioned revisions, not a claim that every original byte is still unchanged. The original 09:02 output gate remains a dated passing phase, not falsely rerun against a 10:18 header with its old timestamp predicate weakened.

Cow's new `docs/reports/2026-10-06-closure-audit.md` maps P01-P12. It reports seven controlled offline workflow checks, 1,680 geometry combinations and fourteen profile-verifier edge tests, including three reproduced false-acceptance gaps corrected in scratch only. The corrected actual native resolver was rerun over the unchanged original export and returned the same counts/weights. Controlled clients/method-body fixtures, prior named native results and static signatures/package checks are **not** new shipped-app frame measurements. The separate reported coverage gate still fails at 48.6% against 80%, and the journal is design-only, not this analysis's delivered implementation.

## Closure and remaining boundaries

The **analysis and independent-review handoff** have a concrete feedback loop: real native samples replaced a source-only ranking, the peer independently agreed, original gates were rerun as one integrated result, real current APIs and shipped CLI main/error/integration paths were observed, and the user-facing documents map those observations individually. This closes the analysis outcome, not a performance-fix goal.

Precise frame attribution, static/animated or cached-layout comparisons, memory impact, WAN incident timing, cold launch/resume, navigation, long-history screens, widgets, and the installed M1 control were not accepted as exercised. Current main-app availability and configured-default CLI selection are also blocked. Analysis-only authorization was not expanded to force those paths, relaunch the app or change its preferences. Cow's separate quality/coverage comments were reported context, not new checks here.

Owner-private evidence: `~/.jcode/scratch/fleet-slow-whole-result-20261006-100502/`, including `integrated-saved-gates.json`, per-predicate `phases/`, `fresh/live/summary.json`, `fresh/public-cli-observations.json`, `current-app-availability.json` and the final whole-result check output. Original native/history evidence remains at `~/.jcode/scratch/fleet-slow-analysis-20261006-080648/`. Original peer acknowledgement and delivery evidence remains at `~/.jcode/scratch/fleet-slow-acceptance-20261006-085336/`.
