# Hash Fleet native Astra review and incomplete Opus attempt record, 2026-10-18

**Completed source-review handoffs:** four direct native Astra specialists delivered the iOS/iPadOS, Mac apps/distribution, CLI and shared-core reviews. The review retains/refines the historical 16 findings and adds four production-API-backed findings, for **20 open findings: 8 P2 and 12 P3, no P1 established**. All 298 existing package tests pass, which does not mean these defects are repaired. A later real native demo UI run observed **two passing flows and one failed flow**, detailed in §8, not an all-pass native acceptance result. The two original native Opus app attempts remain explicitly incomplete and are not credited as completed reviews.

Repository: `/Users/USER/dev/hashfleet`. Native review began at HEAD `73eb4d083b5a9e014cbb43fa1b17b1bd60789d3a`. Product-source baseline: `f7363e9`, unchanged by this review. This is a review, not a repair or a live fleet status report. Source references are relative to the repository.

## 1. Corrected interpretation and reviewer provenance

The user wanted a swarm to review Hash Fleet's iOS app, Mac app and CLI using the best available agents, then explicitly rejected Sonnet 5.5 and Antigravity. Treating the original Sonnet-only pass as satisfying that request was a coordinator error. Selecting an Antigravity Opus alias rather than existing direct Claude access was another coordinator error. Neither is justified here by a ranking argument.

The corrected scopes include iOS/iPadOS, the primary Apple Silicon Mac app running as Designed for iPad, the separate native Mac menu-bar companion, the `hashfleet` CLI, and shared core/integration boundaries. “amd cli” was interpreted as “and CLI”, not as a separate AMD GPU-specific tool. That interpretation remains disclosed, not invented user confirmation. The later request to review all these apps establishes review intent, not permission to repair products or operate hardware.

| Scope | Worker | Persisted provider/model | Requested effort | Artifact |
| --- | --- | --- | --- | --- |
| iOS/iPadOS | giraffe, bounded recovery | `openai-oauth` / `gpt-6-astra` | xhigh | `ios-recovery-astra.md` |
| Mac main app, companion, distribution | fox, bounded recovery | `openai-oauth` / `gpt-6-astra` | xhigh | `mac-recovery-astra.md` |
| CLI and status contracts | fish | `openai-oauth` / `gpt-6-astra` | xhigh | `cli-native-astra.md` |
| Shared core/security/integration | eagle | `openai-oauth` / `gpt-6-astra` | xhigh | `core-native-astra.md` |

All four members of this completion roster delivered their artifacts by **15:10 UTC**, and each demonstrated real successful source reads. Persisted session metadata verified the original two Opus and two Astra identities at 14:33 and 14:52 UTC, then both fresh Astra app identities at **15:07 UTC** on October 18. Requested effort is not a claim that a provider reproduces a published benchmark setting. Source tools and final artifacts are verified separately. The source-only workers own their artifacts. Builds, tests and runtime observations in this document belong to the coordinator, not to those workers.

**Incomplete native attempts and recovery:** dog and dove really used `claude-oauth` / `claude-opus-5-5`, requested effort max, and successfully read app sources. Neither produced a final artifact after approximately 31 minutes despite finalization requests. Both owned runs were stopped at **15:02 UTC**, not counted completed, and not relabeled as Astra work. At **15:06 UTC**, the initial acceptance verifier recorded **151 checks passed and two missing-artifact checks failed**, exit 1. Its original script, manifest and failure receipt are preserved. Same-session recovery tools could not resume the stopped headless sessions. The coordinator therefore chose two fresh, tightly bounded native Astra app reviews, another family the user named, rather than Sonnet, a proxy or indefinite continuation. This is a task-local handoff recovery, not proof of a provider inference error, a general model-readiness claim or permanent Opus disqualification. The completed app reviewers here are Astra, not Opus. The offline advisory had no recorded local-provider readiness entry for either inspected route. Actual persisted identities, successful source tools and delivered artifacts establish this bounded source-review workflow, not universal coding readiness or future provider reliability.

The single rejected Antigravity admission was stopped at **14:29:39 UTC** and its output is excluded. No Sonnet fallback is accepted into this corrected roster. Only the configured default was temporarily selected for the native admissions, with no per-spawn model/account override, approved-pool change, account switch or paid API-key activation. `agents.swarm_model` was restored to `auto` at **14:31:58 UTC**, temporarily selected as direct native Astra for the two bounded recovery admissions at **15:06:18 UTC**, then immediately restored to **auto at 15:06:52 UTC**. No daemon was restarted. The user reports higher Antigravity cost. This review respects that preference without claiming independently verified prices, zero cost or account billing totals. Argon had no matching advertised local route in the checked route list, not proof that the model does not exist elsewhere.

The earlier `2026-10-18-hash-fleet-swarm-review.md` retains its Sonnet provenance and historical test receipts. It now explicitly states that it did not satisfy the corrected model requirement. Its findings are not silently relabeled as native Opus/Astra discoveries.

## 2. New production-API observations

These four findings add evidence beyond the historical 16. The first three were new core findings. The fourth promotes an earlier discovery follow-up into a reproduced contract defect. No P1 is established. P2 denotes medium-priority correctness/availability work, P3 lower-priority correctness or contract hardening.

| ID | Priority | Finding | Observed evidence |
| --- | --- | --- | --- |
| NF-01 | P2 | Reused block counters suppress a distinct later block announcement | Actual detector returned a new event, but production claim returned false for the reused key |
| NF-02 | P2 | XMRig rejected-share arithmetic can trap on individually representable integers | Disposable actual-client consumer exited on signal 5, normal counter control succeeded |
| NF-03 | P3 | Invalid HTTP-success JSON-RPC bodies are acknowledged as accepted | Production pause returned success for five malformed/error bodies, conventional error control threw |
| NF-04 | P3 | Discovery follows redirects and attributes destination data to the original host | Two owned loopback origins received GETs, result retained the source address with the destination name |

### NF-01. Distinct later block events collide in the shared announcement key

**Locations:** `Sources/HashFleetCore/FleetSharedStore.swift:91-105`, `Sources/HashFleetCore/FleetBlockDetection.swift:29-50,58-62`, `App/Store/MinerSnapshot.swift:254-276`, `App/Store/FleetStore+Evaluation.swift:211-234`, `PushProvider/PushProvider.swift:56-64`.

`blockKey` contains the device UUID and optional block counter, but not block height, coin or reset/session identity. Both detection paths can recognize a subsequent block after a reset. That distinction is lost before the shared claim. In the main app, notification enqueueing and the achievement write are both inside the successful-claim branch.

The coordinator linked the unchanged production library and used one random owned defaults suite. Claiming count 1 succeeded. After a count-0/false-flag reset baseline, a count-1/true-flag event at a distinct height was detected, but its claim failed. Exact output: `first_claim=true fresh_block_detected=true second_claim=false`. The suite was removed afterward. This is a sequential identity defect, separate from the historical non-atomic claim race and unaffected by the foreground heartbeat. Flag-only firmware can also reuse the nil-counter key by source analysis, but that variant was not separately executed.

Suppression lasts while the old key remains among the last 200 retained announcements, not necessarily forever. First-observation/reboot guards remain present. No real missed block, achievement or OS notification was observed.

**Proposed acceptance:** use stable event identity or a persisted reset epoch shared across channels. Two distinct post-reset heights and two separated flag-only events must each be claimable once, while replaying the same event remains rejected. Cross-process atomicity still needs its separate regression.

### NF-02. Malformed XMRig share counters escape throwing error handling through a trap

**Locations:** `Sources/HashFleetCore/XMRigAPIClient.swift:95-108`, `Sources/HashFleetCore/JSONValue.swift:20-23,72-81`, `Sources/HashFleetCore/FleetStatusService.swift:28-39`.

Numeric conversion already rejects out-of-range values. The later `total - accepted` operation lacks nonnegative/order validation and checked subtraction. `Int.max` and `-1` each fit in Int, while their difference does not. A trap is not caught by the service's throwing-error path.

An owned loopback `/2/summary` response supplied `shares_total: 9223372036854775807` and `shares_good: -1`. The actual production client in a disposable child process made one GET and terminated with exit **-5**, signal 5. A normal 10-total/9-good control returned rejected `1.0` and exited 0. The consumer explicitly catches ordinary thrown errors, so this signal is not an unhandled-error artifact. Core dumps were disabled only for these disposable processes.

This demonstrates malformed/adversarial response robustness, not an actual XMRig version emitting those counters or a launched native app crashing. Normal valid counters remain supported. Less extreme accepted-greater-than-total input can also yield impossible negative counts by source analysis.

**Proposed acceptance:** validate nonnegative counters and ordering, use checked arithmetic, and reject or preserve unavailable metrics without trapping. Cover extremes, reversed counts, negatives, zero/zero and normal counters. Do not replace the operation with wrapping arithmetic.

### NF-03. Malformed successful HTTP responses become false command acknowledgment

**Locations:** `Sources/HashFleetCore/XMRigAPIClient.swift:50-77`, `App/Features/Miner/XMRigControlView.swift:117-128`.

After HTTP success, the command parser only recognizes an error object with a string `message`. HTML, empty or malformed JSON, `{}`, and a code-only error fall through as success. The UI refresh is nonthrowing and does not validate the discarded command envelope before showing that XMRig accepted the command.

Five actual production `pause()` calls, each directed only at an owned loopback `/json_rpc` fixture, returned `pause_returned_success` with exit 0 for those five bodies. A conventional message-bearing JSON-RPC error returned the consumer's caught-error marker and exit 2. No real CPU miner received a POST. Resume and native UI presentation were not separately executed.

Non-2xx/non-HTTP failures, conventional message-bearing errors, redirect blocking, UI confirmation and demo guards remain. This is a false-acknowledgment defect, not unauthorized execution. Pause/resume is reversible, supporting P3. It refines the historical XMRig-control claim: recognized errors surface, but not all invalid command responses are recognized.

**Proposed acceptance:** require the supported matching successful response shape and reject malformed/mismatched envelopes and every supported error representation for both pause and resume. Preserve confirmation, demo isolation, redirect protection and summary-only version fallback.

### NF-04. Discovery's scan-plan boundary is not enforced across redirects

**Locations:** `Sources/HashFleetCore/FleetNetworkDiscovery.swift:28-51,107-129,186-205`; contrasting main-client blockers: `Sources/HashFleetCore/MinerAPIClient.swift:219-230` and `Sources/HashFleetCore/XMRigAPIClient.swift:136-145`.

The generated plan promises a single local /24 and one GET per host. Discovery instead uses a plain URLSession without the primary clients' redirect blocker or a final-origin check. A valid destination body is attributed to the original requested host.

The coordinator used an explicit one-host loopback plan, never `scanCurrent()`. Origin A redirected to another port on `127.0.0.1`, where origin B served recognized info. Both received a GET. The returned candidate used A's address with B's `redirect-target-miner` name. This proves redirect following and false attribution across two origins on loopback. It does not claim that an actual outside-subnet request, LAN traversal or CLI exit was exercised.

Initial private-address planning, concurrency/timeouts, cookies disabled, final HTTP/content/shape checks remain. Discovery carries no XMRig bearer token and no write body. Main ESP/XMRig request paths already reject redirects. CLI reviewer proposed P2, core reviewer P3. The coordinator accepts conservative **P3**, with no demonstrated critical SSRF, credential leak or write.

**Proposed acceptance:** block redirects or enforce an explicit origin policy before a second-origin request, then assert no false candidate. Cover 301/302/307/308, direct valid info and final HTML with owned listeners only.

## 3. Coordinator execution and evidence boundaries

The actual unchanged SwiftPM suite passed **52 XCTest methods plus 246 Swift Testing tests, 298 total**, at approximately 14:36 UTC, 14:40 UTC, **14:55 UTC**, and again in the fresh **15:21:43-15:22:48 UTC** actual-project matrix. Live/private smoke-test opt-ins were removed. Actual built `hashfleet --help` exited 0 and printed the supported read-only status usage, with both `--help` and `-h` rerun successfully in the fresh matrix. This pass never ran a bare status command or real discovery. Passing existing tests is not evidence that the reported defects are fixed.

`PublicAPIConsumer.swift` imports `HashFleetCore` and links the actual current `libHashFleetCore.a`. It contains no copied implementation or production-type stubs. `public-api-results.json`, completed **14:44:57 UTC**, records 10 assertion-checked supplementary cases: the reset collision, five false-ack cases, two controls, the arithmetic trap and discovery redirect. All HTTP listeners/targets were `127.0.0.1`. These are actual production API and TCP/HTTP observations, but controlled fixtures remain supplementary evidence, not replacement for native UI or signed integration acceptance.

**Preserved coordinator setup failures:** two consumer compilation attempts selected legacy `.build/arm64-apple-macosx/debug` modules from Swift 6.3.3, incompatible with the current Swift 6.4 compiler. Those failures remain in their logs. `swift build --show-bin-path` and `.build/debug` identified the actual current `.build/out/Products/Debug` output. Linking that production library succeeded. Its SHA256 receipt is `a808f19065695672edb1da61615da31451b2371d93ab11dc4eae4e387fabf195`. This was a coordinator setup error, not a demonstrated current project compiler defect. An early scratch-consumer brace mistake was corrected before final compilation. No product code or existing acceptance assertion was changed.

The earlier coordinator's **08:33:59-08:35:33 UTC** actual-project receipts remain historical, not fresh native-worker execution:

| Actual target/interface | Historical observation | Limit |
| --- | --- | --- |
| iOS/iPadOS, no app push | `HashFleetNoAppPush` / `DebugNoAppPush`, generic iOS Simulator build, exit 0 | Unsigned compile, not launched |
| iOS/iPadOS, app push enabled | `HashFleet` / `Debug`, generic iOS Simulator build, exit 0 | Includes `APP_PUSH_PROVIDER_ENABLED`, not background delivery |
| Primary Apple Silicon Mac app | NoAppPush Designed-for-iPad arm64 build, exit 0 | Not a separate native macOS main app, no signed runtime |
| Native menu-bar companion | `HashFleetMenuBar` / `Debug`, generic macOS build, exit 0 | No popover or login lifecycle run |
| Native app/UI test bundles | `build-for-testing`, exit 0 | At 08:35 UTC compiled only. Later selected real UI execution is recorded separately in §8 |
| CLI actual executable | Build/help exit 0, explicit loopback-only offline JSON and table each exit 1 with timeout | Actual interface, no healthy live-fleet acceptance |
| Three Mac distribution scripts | `bash -n` each exit 0 | Syntax only, no installer/package execution |
| Simulator available-device probe | Historical timeout after 15 seconds, exit 124 | Not a current blocker. The fresh 15:22 UTC probe exited 0, and §8 records actual UI execution |

Historical logs report installed CoreSimulator **1171.7.0** older than required **1174.9.2**. That is historical, not a still-current external blocker: the fresh **15:22 UTC** available-device probe succeeded with exit 0 and no version-conflict output. The coordinator did not restart a service or install a runtime to obtain that result. Selected real native demo UI flows were then exercised as recorded in §8. No signed App Group app/extension/CLI interoperability, installer/notarization/login lifecycle, native hardware-confirmation/popover rendering, background scheduling/notification delivery, Release archive or push-enabled Designed-for-iPad Mac runtime is accepted here. Those remaining gaps are not upgraded by build success or two unrelated passing UI flows.

No real ASIC or mining Mac was contacted by HTTP, WebSocket, SSH or discovery. App launches in §8 were confined to existing demo-only UI tests on a newly owned disposable simulator, not a production fleet app or the host's production preferences. No live fleet status is asserted. The canonical fleet playbook was read only as a safety reference. No miner settings, restarts, self-tests, firmware, pools, wiring, services or lockouts were changed. No production preferences/databases were read or changed. Product and existing test source remain unchanged.

## 4. Application handoffs and prior-finding reconciliation

The table below reconciles all historical 16 using the completed native handoffs and coordinator checks. The original Opus attempts remain incomplete. “Retained” or “refined” means a review finding remains open, not that it was repaired or runtime-accepted. Historical detail and prior reproduction limitations remain in the original report.

**Bounded app coverage and attribution:** the delivered iOS artifact is 68 lines and covers the assigned intent adapter/executor, direct-save/refresh ordering, recorder extraction and block integration. It did not independently inspect the XMRig screen/cache, external wire contract, endpoint-form continuation or every app feature. Native core/CLI findings and coordinator evidence retain those separate attributions. The 63-line Mac artifact covers the foreground publication gate, stale/demo presentation, package staging and documentation mismatch. It did not independently establish the bootstrap caller gate, sole-writer claim or XMRig translation. The coordinator separately checked `App/Store/FleetStore+Monitoring.swift:30-38`, `App/HashFleetApp.swift:222-234` and `Sources/HashFleetCore/XMRigAPIClient.swift:95-132` to confirm bootstrap gating and absent translated power. The coordinator also checked preserved immediate post-confirmation safety reads at `App/Features/SystemIntegrations/FleetMinerControlExecutor.swift:245-304`. None of this worker source review is exhaustive coverage or runtime UI acceptance. The coordinator's later actual UI execution is separately attributed and limited in §8.

| ID | Priority | Prior section | Disposition and finding | Source/evidence boundary | Proposed acceptance after repair |
| --- | --- | --- | --- | --- | --- |
| PF-01 | P2 | §5.1 | Refined: absent shared sensors become zero, true zero rate becomes unknown | `Sources/HashFleetCore/MinerStatusSnapshot.swift:20-32`, `Sources/HashFleetCore/MinerInfo.swift:21-25,57-64,79`, `Sources/hashfleet/main.swift:76-86`; historical actual CLI partial-ESP fixture, fresh Astra trace. Computed table values, not invented raw JSON keys | Actual CLI and snapshot tests distinguish missing/null/invalid/sentinel values from genuine zero for ESP and configured XMRig |
| PF-02 | P2 | §5.2 | Retained: recorder uses mismatched fan/share/uptime wire keys | `App/Store/FleetStore+Evaluation.swift:305-319`, `Sources/HashFleetCore/MinerInfo.swift:66-79`; core/XMRig canonical keys versus app conversion, source-only. External firmware verification remains historical | Exercise actual app conversion through SQLite readback, retain supplied fields, resolve pool role only from authoritative shape |
| PF-03 | P2 | §5.3 | Retained: any online member without power blocks all Mac glance publication | `App/Store/FleetStore.swift:168-173`, `App/Store/FleetStore+Totals.swift:146-151`, `App/HashFleetApp.swift:189-200,222-234`; source guard and XMRig's absent power. Strict aggregate completeness is intentional, but also gates per-miner companion updates | Mixed ESP/XMRig and missing-power fleets update per-miner state while incomplete aggregate power remains explicitly unavailable |
| PF-04 | P2 | §5.4 | Retained: packaging can ship a stale app with a newly built CLI | `Scripts/package-hashfleet-mac.sh:59-80`; conditional app build versus unconditional CLI build, source-only | Produce two controlled packages around a source change and inspect both binary identities, without installing |
| PF-05 | P2 | §8.1 | Retained: stale Mac rows stay green and say Live | `MacMenuBar/HashFleetMenuBarApp.swift:104-106,133-135,219-234`; only title/header receive staleness policy, native UI not launched | Frozen-clock expired snapshot renders stale rows/title/header consistently, including main-app closure |
| PF-06 | P2 | §8.3 | Retained: iOS 17 confirmation adapter drops supplied detailed dialog | `App/Features/SystemIntegrations/FleetMinerControlIntents.swift:109-121`, `App/Features/SystemIntegrations/FleetMinerControlExecutor.swift:206-217,223-236`; target/value/risk text is not forwarded on this branch. Local authentication, confirmation and fresh safety reads remain | Controlled non-mutating confirmation/cancel acceptance on supported OS versions displays target, value and risk without weakening guards |
| PF-07 | P3 | §3.1 | Refined: shared block claim has a non-atomic read/check/write sequence | `Sources/HashFleetCore/FleetSharedStore.swift:99-105`; historical copied-source primitive race, not delivered duplicates. Provider's 90-second app-active heartbeat narrows overlap. Separate from NF-01 | Transactional cross-process claim yields exactly one winner and retains independent keys, then separately verify real channel delivery |
| PF-08 | P3 | §5.5 | Refined: DB failures discard buffered telemetry and hide failed clear | `Sources/HashFleetCore/Database/MinerTelemetryDatabase+Reading.swift:42-58`, `Sources/HashFleetCore/Database/MinerTelemetryDatabase+Maintenance.swift:49-66`, `App/Store/FleetStore+Persistence.swift:162-183`; source-only, no production database fault or corruption observed | Disposable injected queue failures retain recoverable batches, surface errors, preserve app state on failed clear and retry once |
| PF-09 | P3 | §5.6 | Refined: unrelated valid XMRig JSON becomes online info | `Sources/HashFleetCore/XMRigAPIClient.swift:95-132`, `Sources/HashFleetCore/FleetStatusService.swift:28-39`; permissive existing test plus native source trace. Configured-kind path, not an invented CLI selector | Reject unrelated shapes through actual service/CLI while retaining valid minimal, paused and zero-rate XMRig and 404-only fallback |
| PF-10 | P3 | §5.7 | Refined: corrupt/unavailable configured state becomes empty discovery | `Sources/HashFleetCore/FleetSharedStore.swift:30-35`, `Sources/hashfleet/main.swift:13-25,51,67-71`; source-only, no installed signed-storage failure asserted. No eligible interface can also produce misleading scan copy | Inject absent/empty/corrupt/unavailable/valid storage and no-interface outcomes before network selection, preserving intentional discovery only for genuine unconfigured state |
| PF-11 | P3 | §5.8 | Refined: unsupported CLI flags are silently ignored | `Sources/hashfleet/main.swift:7-20,51-64`; historical actual executable loopback receipt, fresh source trace. Unknown words become hostnames, not mutation commands | Documented grammar rejects usage errors before storage or network, preserving valid help/status and intended host shorthand |
| PF-12 | P3 | §5.9 | Retained: distribution guide promises companion/LaunchAgent absent from package payload | `Scripts/package-hashfleet-mac.sh:74-98,105-119` versus `docs/MAC-DISTRIBUTION.md`; source-only, installer not run | Inspect clean produced payload for documented artifacts, then separately verify signed disposable login/Preferences integration |
| PF-13 | P3 | §6.1 | Refined: unbounded ESP error controls/newlines reach CLI table | `Sources/HashFleetCore/MinerAPIClient.swift:205-215`, `Sources/hashfleet/main.swift:80-86`; historical captured actual-CLI fixture plus fresh trace. JSON escapes controls, failed discovery probes are discarded, no shell execution claim | Actual CLI captured bytes yield safe bounded single-row table, valid JSON and correct offline exit while preserving protected diagnostics |
| PF-14 | P3 | §8.2 | Retained: Mac compact title and tooltip omit demo label | `MacMenuBar/HashFleetMenuBarApp.swift:252-262`, `App/Store/FleetGlanceCoordinator.swift:75-81`; source-only, inner row DEMO badge does not label closed popover | Compare actual real/demo formatter outputs and native title/tooltip/header presentation |
| PF-15 | P3 | §3.2 | Retained: post-write refresh can join an older pre-write read | `App/Store/FleetStore.swift:254-279,312-332`, `App/Features/Miner/MinerSettingsView+DirectSave.swift:47-50,81-106`; source ordering, not timing reproduction. Dedicated tuning one-shot readback is excluded | Suspended pre-write read cannot repopulate old form values after the fresh write or target change/deletion |
| PF-16 | P3 | §8.4 | Refined: XMRig controls display cached state without the shared freshness policy | `App/Features/Miner/XMRigControlView.swift:37-52,101-130`, `App/Store/MinerSnapshotCacheEntry.swift:45-52`; source-only, confirmation and demo gates remain. NF-03 corrects the old implication that every send failure surfaces | Cached/stale/offline/fresh fixtures honestly label and gate controls, with command acknowledgment validated separately |

The original suspected missing companion URL scheme remains rejected: the historical compiled Info.plist contained `hashfleet-menubar`. Raw firmware JSON export lacks an established sanitized-export promise, so no credential-disclosure finding is invented. Explicit positional XMRig selection remains a capability gap, not a broken promised option. The external Hide versus already-open Preferences toggle is a lifecycle follow-up until signed runtime acceptance. No measured CPU, memory, energy or latency regression is established.


## 5. Requirement-to-observation map

This table maps the corrected request to observed checks, including blocked or intentionally unperformed acceptance. All four current native handoffs are delivered. Review completion is not native-product runtime certification.

| ID | Requirement | Actual observed result | Acceptance boundary |
| --- | --- | --- | --- |
| R01 | Review iOS/iPadOS and its integrations | Native Astra iOS artifact delivered and read. Fresh push-enabled/no-push builds and UI test-bundle construction succeeded. Actual demo dashboard/About and dashboard/miner-detail navigation passed; the mixed CPU-trend flow failed at unreachable search, §8 | No all-pass UI suite, iOS 17 consent or push-delivery acceptance. Missing-sensor assertions after the failing search were not reached |
| R02 | Review both actual Mac surfaces and distribution | Native Astra Mac artifact delivered and read. Fresh Designed-for-iPad main-app and native companion builds and three distribution-script syntax checks all exited 0. Coordinator separately checked bootstrap/translation guards | No signed App Group, native Mac popover, installer or login lifecycle run. iOS demo UI does not certify the Mac surfaces |
| R03 | Review the actual CLI, not imagined commands | Native Astra CLI artifact complete. Fresh actual CLI build and both `--help`/`-h` exited 0 with identical documented usage. Historical actual table/JSON offline exits and defect cases retained | Help returns before shared fleet storage. No fresh configured-status scan, real fleet contact or separate AMD-tool acceptance |
| R04 | Review shared core and integration robustness | Native Astra core artifact complete. Actual unchanged suite passed 298 tests in all four current runs, including fresh execution at 15:21 UTC. Actual production APIs exhibited the four defects in §2, with controls | Controlled API/defaults observations remain supplementary. Existing passing tests and limited demo UI flows do not repair or close these defects |
| R05 | Use requested direct-native agent families, not Sonnet or Antigravity | Four completion-roster sessions identify native Astra workers, including the two app recoveries. Original native Opus attempts remain explicitly incomplete. Rejected proxy worker stopped, default restored to auto | No universal model ranking or independent provider-price claim. All four completed reviewers are native Astra, not Opus or Sonnet |
| R06 | Recheck earlier work against clarified intent | All 16 historical findings mapped in §4 with guard-aware refinements and historical evidence labeled. Historical report now admits the rejected model interpretation | Bounded application reconciliation complete. Uninspected paths and source-versus-runtime limits remain explicit. No Sonnet/Opus relabeling or user approval implied |
| R07 | Substantiate new material claims | Ten assertion-checked actual-production API cases at 14:44:57 UTC show reset-key collision, arithmetic trap, false RPC acknowledgment and redirect misattribution | No real missed block, native crash, OS alert duplication, outside-subnet request or unauthorized hardware write asserted |
| R08 | Preserve safety, credentials and product state | Product and existing test source baseline unchanged. Only demo/test storage on an owned disposable simulator was used for the later UI flows. No real miner HTTP, SSH, LAN discovery or production store/database access | No hardware settings or production application launch. Canonical safety reference is not live telemetry. No live fleet status |
| R09 | Exercise the real acceptance path where safe and disclose gaps | Fresh actual package suite, built CLI help, both iOS and both Mac target builds and test-bundle build executed. Fresh simulator discovery succeeded. Three unchanged native demo UI tests ran, with two passes and one failure, §8 | Historical version mismatch is not a current blocker. Signed integration, Mac popover, hardware confirmations, installer and background delivery remain unperformed, not fixture-substituted or implied by demo navigation |
| R10 | Deliver an auditable result with source/evidence traceability | Final report, four completed native artifacts, finding ledger, persisted provider record and additive verifier integrated. Final receipt records source/evidence checks and the delivered document hash | No product repair or production outcome improvement claimed |

The final additive verifier checks all 10 requirement rows, every finding/evidence entry, four completed native Astra artifacts, exact persisted routes, source reference ranges and baseline equality, actual test/CLI receipts, all 10 new case outcomes and documentation-only git changes. It does not modify or weaken the historical acceptance scripts to accommodate new documents. Recovery verification uses the explicitly recorded replacement roster and still requires both actual app artifacts. The earlier Opus verifier, manifest and two failed completion checks are preserved, not retroactively converted into a pass.


## 6. Suggested repair order, not executed

1. Contain the XMRig arithmetic trap (NF-02) with validation/checked arithmetic and subprocess boundary regression.
2. Give block announcements stable event/reset identity and atomic cross-process claims (NF-01, PF-07), preserving first-observation and reboot guards.
3. Centralize nil-preserving wire-to-history mapping (PF-01, PF-02) and separate per-miner companion publication from strict aggregate completeness (PF-03).
4. Make packaging deterministically build current app and CLI, then reconcile the documented companion payload (PF-04, PF-12).
5. Correct stale/demo presentation and supported-OS consent context (PF-05, PF-06, PF-14, PF-16), then exercise actual native confirmation/cancel and popover paths when runtime/signing permit.
6. Validate command acknowledgment, enforce discovery origin policy, surface DB failures and tighten CLI usage/error presentation (NF-03, NF-04, PF-08 through PF-13), with actual public-interface checks rather than source-only closure.

No implementation, existing acceptance test or hardware setting was changed to make a reported defect disappear. The product is not claimed improved by this review alone. The review becomes more useful through corrected reviewer provenance, four observed production-API failures with controls, explicit earlier-claim reconciliation and an evidence-to-acceptance map. Proposed regression checks above are future repair criteria, not reported passing repairs.

## 7. Evidence locations

Current owner-local evidence: `/Users/USER/.jcode/scratch/hashfleet-premium-review-20261018-1427/`. Includes the admission manifest, persisted provider metadata recheck, worker artifacts, actual-suite logs, production API consumer/driver/results, preserved setup logs, finding ledger and additive final verifier. No private wallet, pool password, Wi-Fi credential or key is included in this report.

Historical owner-local evidence: `/Users/USER/.jcode/scratch/hashfleet-review-20261018/`, particularly `acceptance-0830/actual-project-results.json`, original CLI loopback cases and the original four Sonnet artifacts. Historical synthetic/copied-source claim-race evidence remains labeled as such, not promoted into native notification acceptance.

## 8. Fresh actual-project and native UI outcome check

### 8.1 Real entry points re-exercised after the complete requirement map

The **15:21:43-15:22:48 UTC, October 18** rerun executed the unchanged repository, not copied app source or a custom replacement app. All **12 actual-project commands** below exited 0. The evidence verifier also exited 0 with 162 checks, separately from those project commands. A separate read-only simulator list exited 0 in 0.145 seconds, with available runtimes and no version-conflict error. The earlier simulator timeout/version mismatch is preserved as history, not used as a current excuse to skip runtime acceptance.

| Actual entry point | Fresh observation | What it does not establish |
| --- | --- | --- |
| `swift test --skip-update` | 52 XCTest plus 246 Swift Testing tests passed, 298 total | Reported defects remain open |
| `swift build --skip-update --product hashfleet` | Exit 0 | Not healthy live-fleet status |
| Actual `hashfleet --help` and `-h` | Both exit 0, identical documented status usage | No configured-status storage read or discovery was run |
| No-app-push and push-enabled iOS target builds | Both exit 0 with actual build-success markers | Not background push delivery |
| Designed-for-iPad Mac primary and native companion builds | Both exit 0 with actual build-success markers | Not signed host App Group or popover acceptance |
| Actual app/UI `build-for-testing` | Exit 0 with test-build success marker | Test execution is separate below |
| Three actual Mac distribution scripts, `bash -n` only | All exit 0 | No package installation, login agent or notarization acceptance |

### 8.2 Actual native UI execution: two observed passes, one observed failure

After confirming the existing `--ui-testing` isolated defaults and demo-before-polling guards, the coordinator created a new owned **iPhone 18 Pro / iOS 27.0** simulator. Only the three selected existing tests were run through the actual `HashFleetNoAppPush` test target. Product and existing test code were not edited. This is actual native app rendering, navigation and accessibility automation with demo data, not a replacement harness for those flows. It is not live-device or hardware-control certification.

| Existing native UI test | Actual test-log outcome | Observation |
| --- | --- | --- |
| `HashFleetUITests.testDemoDashboardAndNativeNavigation` | Passed | Demo dashboard, About navigation, privacy text and return to fleet asserted |
| `NativeOverviewUITests.testCaptureDashboardAndMinerBaseline` | Passed, 14.663 seconds | Demo dashboard and Workshop Gamma detail reached, screenshots attached by the existing test |
| `NativeOverviewUITests.testCPUTrendStaysSeparateAndNeverInventsSensors` | Failed, 62.144 seconds | The helper could not reach `dashboard.search`, assertion at `UITests/NativeOverviewUITests.swift:407`, called from the CPU test at line 104 |

Relevant existing test paths are `UITests/HashFleetUITests.swift:152-167` and `UITests/NativeOverviewUITests.swift:82-120,383-407`. The selected-tests summary at **15:28:29 UTC** says **3 executed, 1 failure, 0 unexpected failures**. The CPU test reached its earlier CPU-unit/chart and empty-history checks, then failed before the later missing-temperature/power assertions. Those later assertions are **not accepted as passed**. This review does not yet distinguish a product navigation/accessibility defect from the existing reveal helper's scrolling assumptions. It is a recorded acceptance failure and follow-up, not an automatically classified twenty-first product defect.

**Result collection limit preserved:** xcodebuild remained alive after the selected-tests failure summary. At 15:33:31 UTC, `xcresulttool` could not open the still-incomplete result bundle because its Info.plist was absent, exit 64. A validated owned-process SIGINT at 15:34:05 did not finish collection within 60 seconds. SIGTERM was then confined to the verified owned collector process group. Its command exit was **-15**, and the driver exited **1**, not an ordinary clean test completion or accepted final xcresult bundle. Raw test logs establish the two passes and one failure. No test was retried, weakened or relabeled. Owned-simulator identity check, shutdown and delete all exited 0, with cleanup complete at **15:35:42 UTC**. Existing user simulators and production preferences were not used or changed.

### 8.3 Goal feedback and remaining limits

The result is a better-evidenced **review**, not an improved or repaired product: four completed direct-native Astra handoffs now replace the rejected reviewer interpretation, four production-core defect observations add evidence beyond the historical 16 findings, fresh actual target builds replace reliance on old build receipts, an obsolete current-blocker claim was disproved, and real native execution supplies two observed end-user-flow passes plus a preserved failure. None of those observations establishes universal best-model ranking, successful Opus completion, zero provider cost, exhaustive source coverage or repaired defect behavior.

| Goal | Outcome observation | Residual boundary |
| --- | --- | --- |
| Interpretation verification | Actual completed roster and artifacts cover iOS, both Mac surfaces, CLI and core using native Astra, with Sonnet/proxy excluded and incomplete Opus retained | “amd cli” remains the disclosed “and CLI” interpretation. Exact recovery roster was a coordinator choice, not invented user confirmation |
| Hash Fleet review | All 20 findings retain evidence and proposed acceptance. Actual unchanged suite and target builds pass. Real demo UI reports two passes and one failure | No all-pass UI acceptance, signed App Group, Mac popover, installer/login lifecycle, iOS 17 consent, background delivery or healthy real-hardware acceptance |
| Correct Hash Fleet reviewer selection | Persisted provider records, four real source-tool handoffs, full requirement map and fresh interface observations support the delivered corrected review | Native app execution belongs to the coordinator, not source-only workers. Evidence verification must not convert the failed UI run or incomplete Opus attempts into passes |

Fresh owner-local evidence is `~/.jcode/scratch/hashfleet-premium-review-20261018-1427/outcome-1519/`: pre-execution `check-plan.json`, all ten per-requirement observations in `actual-project-results.json`, actual command logs, `native-demo-plan.json`, `native-demo-results.json`, raw UI logs and `native-result-collection-note.md`. The incomplete xcresult is retained as an incomplete artifact, not accepted evidence of successful collection. Further product fixes or broader signed/runtime acceptance were not performed by this review follow-through. `verify_outcome.py` and `final-outcome-verification.json` combine the complete requirement map, retained earlier checks, fresh real-project logs and explicitly failing UI acceptance without turning the evidence audit into a product pass.
