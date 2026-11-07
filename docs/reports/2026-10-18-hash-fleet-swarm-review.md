# Hash Fleet historical Sonnet swarm review, 2026-10-18

Baseline: `f7363e9`. Repository: `/Users/USER/dev/hashfleet`. This is a review report, not a repair or a live fleet status report. Source references below are relative to the repository at that baseline.

**Provider correction, October 18:** this was the earlier Sonnet-only pass. The user explicitly rejected treating Sonnet 5.5 as fulfillment of the best-agent request, and rejected Antigravity in favor of existing direct Claude access. This report is retained as historical evidence, not relabeled as Opus or Astra and not counted as satisfying that corrected requirement. See `2026-10-18-hash-fleet-native-opus-astra-review.md` for the separate direct-native review, its actual reviewer identities, new evidence and remaining limitations.

## 1. Executive summary

Scope is the iOS/iPadOS app, the primary Apple Silicon Mac app (Designed for iPad), the separate native Mac menu-bar companion, the `hashfleet` CLI, and their shared core. Four native Claude Sonnet 5.5 reviewers were admitted at high effort, one per scope. The coordinator independently checked material findings, built the iOS app with and without app-push plus the primary Mac app and native companion, built the native test targets, ran the package tests, and exercised isolated fixtures. See §10 and §12 for the exact configuration matrix and evidence boundaries.

The review accepts **16 findings: 6 P2 and 10 P3, with no P1 established**. The existing test suite passes, but it does not cover the following important integration failures. Findings marked **reproduced** have an isolated behavioral reproduction. **Source-confirmed** means the coordinator independently traced the relevant code and guards, not that the full app behavior was exercised.

| Priority | Finding | Evidence | Detail |
| --- | --- | --- | --- |
| P2 | Missing sensor readings become measured zero in shared status and the CLI | Reproduced with loopback ESP fixture | §5.1 |
| P2 | Recorder key mismatches discard available fan/share/uptime values | Source-confirmed against core and static firmware keys | §5.2 |
| P2 | Any online miner without power can block all Mac menu-bar snapshot updates | Source-confirmed, including XMRig translation | §5.3 |
| P2 | Repeated packaging can ship an old Mac app alongside a freshly built CLI | Source-confirmed shell control flow | §5.4 |
| P2 | Cached Mac miner rows remain green and say “Live” after the snapshot is stale | Source-confirmed UI inputs and freshness logic | §8.1 |
| P2 | iOS 17 control-intent confirmation drops the app's detailed target/value/risk dialog | Source-confirmed branch, exact system UI rendering untested | §8.3 |
| P3 | Cross-channel block-announcement claim is not atomic | Primitive race reproduced, end-to-end duplicate notification not reproduced | §3.1 |
| P3 | Database write/delete failure is hidden from callers | Source-confirmed failure paths | §5.5 |
| P3 | XMRig accepts unrelated successful JSON as a valid summary | Source-confirmed, existing passing test accepts `{}` | §5.6 |
| P3 | Unreadable configured fleet and genuinely empty fleet are conflated | Source-confirmed fallback, local entitlement/storage corroboration only | §5.7 |
| P3 | Unknown CLI flags are silently ignored | Reproduced with loopback fixture | §5.8 |
| P3 | Distribution guide promises a companion and LaunchAgent not shipped by the current package script | Source-confirmed documentation/script mismatch | §5.9 |
| P3 | Unbounded HTTP error text, including terminal controls, reaches CLI output | Reproduced with synthetic loopback error | §6.1 |
| P3 | Menu-bar title and tooltip do not distinguish a demo snapshot | Source-confirmed formatting and demo publication | §8.2 |
| P3 | Post-write refresh can join a pre-write read and repopulate old settings | Source-confirmed ordering possibility, timing not reproduced | §3.2 |
| P3 | XMRig control renders cached state without freshness labeling and lacks the shared write-availability gate | Source-confirmed cache/control path | §8.4 |

P2 means medium-priority correctness or shipping risk. P3 means lower-priority correctness, contract, or hardening work. No production incident, credential compromise, hardware malfunction, or end-to-end notification duplication is claimed from these findings.

## 2. Quick wins

1. Preserve missing metrics as `nil` in the shared snapshot accessors, then cover partial ESP and XMRig responses (§5.1).
2. Centralize the wire-to-database mapping instead of maintaining another set of field names in the app (§5.2).
3. Split Mac per-miner snapshot publication from the intentionally strict widget aggregate gate (§5.3). Do not make a partial fleet power subtotal look complete.
4. Always invoke the incremental app build during normal packaging (§5.4).
5. Pass freshness into every menu-bar row, label demo data outside the popover, and reject unsupported CLI flags (§8.1, §8.2, §5.8).
6. Surface database failures and retain failed batches before treating “clear” or “record” as successful (§5.5).
7. Preserve the detailed hardware-risk confirmation on every supported iOS version, and reuse freshness-aware state in XMRig controls (§8.3, §8.4).

These are proposed changes. No product implementation or acceptance tests were changed during this review.

## 3. Concurrency

### 3.1. P3: the shared block-announcement claim has multiple winners

**Location:** `Sources/HashFleetCore/FleetSharedStore.swift:96-105`. Callers include `PushProvider/PushProvider.swift:54-61` and `App/Store/FleetStore+Evaluation.swift:215-216`.

The method reads an array from UserDefaults, checks membership, appends, and writes the array back. Individual defaults operations do not make that sequence atomic. Its comment promises one announcement channel, but concurrent callers can both return `true`, and concurrent claims for different keys can overwrite each other.

**Reproduction:** the coordinator compiled the production `FleetSharedStore.swift` unchanged with small unused-model stubs and an isolated defaults-suite harness. Sixteen callers raced on the same key in each of twelve trials. Winner counts were `[8, 4, 4, 4, 4, 4, 4, 3, 4, 4, 5, 4]`, rather than one. The harness removed only its own random suite. Evidence: `atomic_claim_harness.swift` and `atomic-claim-results.json` in the scratch evidence directory in §12.

**Practical boundary:** the provider's 90-second app-active heartbeat suppresses its claim while the foreground app is active. This greatly narrows cross-process overlap. The review did not reproduce two delivered OS notifications or fully exercise background scheduling. The proven defect is the claim primitive, not a demonstrated duplicate alert in the deployed app. The app and provider also use different notification identifier construction, so that should be reconciled if the channel guarantee is retained.

**Recommendation and regression check:** use a cross-process transactional claim, such as a unique SQLite insert or a coordinated App Group file lock. A process-local actor alone is insufficient. Assert exactly one winner in simultaneous callers and consistent notification identity across channels.

### 3.2. P3: post-write refresh can join a read that began before the write

**Location:** `App/Store/FleetStore.swift:254-279,312-332`, `App/Features/Miner/MinerSettingsView+DirectSave.swift:47-50,81-106`, and `App/Features/Miner/MinerEndpointView.swift:231-253`.

After an accepted write, direct-save and reviewed endpoint paths await `store.refresh()`. If a refresh is already running, that method joins the existing task instead of starting a later read. Direct-save then resets `loaded` and reloads the form from the snapshot. An older suspended read can therefore finish after the write and repopulate the form with pre-write values. Ordinary refresh does not itself mark an otherwise fresh live snapshot as reconnecting, so the write-availability gate does not categorically eliminate the overlap.

The dedicated tuning path already avoids this hazard with a new one-shot info request (`App/Features/Miner/MinerTuningApplyService.swift:22-23,63-70`). This finding concerns post-write form fidelity, not the safety or correctness of that verified tuning path. Completion copy correctly avoids claiming a verified readback, which limits the severity.

**Evidence boundary:** the coordinator verified the join, direct-save reload, and availability gate. No suspended-response app fixture was run, so the timing-dependent stale form was not reproduced.

**Recommendation and regression check:** perform a new targeted info read after the write, reject results for a changed/deleted target, and only then reload the form. Use a suspended pre-write fetch and a distinct post-write response to assert that accepted writes cannot reload the old value.

## 4. API modernity and compiler health

The existing SwiftPM tests and all app builds succeeded. The review did not establish a new product compiler-error or deprecation finding. Build success does not establish correctness of App Group entitlement behavior, background execution, or UI presentation.

The test command's `--skip-update` option is a tooling deprecation, not a Hash Fleet source defect. Native test targets were built with `build-for-testing`, not executed. Simulator tooling has a concrete version mismatch, documented in §11.

The primary Mac target is an iOS/iPadOS app running on Apple Silicon. Treating it as a separate native macOS main app would lead to incorrect audit and packaging expectations. The menu-bar companion is a distinct native target.

## 5. Bugs and logic

### 5.1. P2: missing temperature, power, and uptime become real zeros

**Location:** `Sources/HashFleetCore/MinerStatusSnapshot.swift:30-32`, `Sources/HashFleetCore/MinerInfo.swift:21-23,62-63,79`, and `Sources/hashfleet/main.swift:78-79`.

`MinerInfo` provides legacy numeric accessors that default an absent field to zero. Wrapping those accessors in `info.map` produces non-nil `0` whenever an info object exists. The CLI therefore renders missing temperature and power as `0.0 °C` and `0.0 W`, rather than `--`. XMRig summaries do not populate either sensor field, so this also affects configured CPU miners through the shared service.

**Reproduction:** a loopback `/api/system/info` fixture returned only hostname, version, and hashrate. The compiled CLI exited zero and printed an ONLINE row with `0.0 °C` and `0.0 W`. `cli-loopback-results.json`, case `valid_partial_esp_table`, records the request and output. No physical miner was contacted.

**Recommendation and regression check:** read optional raw values with finiteness/range checks, preserving absence. Test both a minimal valid ESP response and an XMRig summary. Expect absent metrics to stay nil and table cells to say `--`. Keep genuine zero readings distinct from missing ones. Raw JSON output is a separate contract and is not changed by fixing these accessors.

### 5.2. P2: the telemetry recorder uses the wrong wire keys

**Location:** `App/Store/FleetStore+Evaluation.swift:305-319`; schema at `Sources/HashFleetCore/Database/MinerTelemetryDatabase.swift:72-85`; existing accessors at `Sources/HashFleetCore/MinerInfo.swift:66-67,76-79`.

The recorder reads `fan`, `fanRpm`, `accepted`, `rejected`, and `uptime`. The canonical ESP firmware source and core accessors use `fanspeed`, `fanrpm`, `sharesAccepted`, `sharesRejected`, and `uptimeSeconds`. XMRig translation also emits the canonical share/uptime keys. The recorder additionally expects top-level `poolIndex` and `isFallback`, which the inspected ESP info response does not emit in that form.

For responses matching that canonical wire contract, those seven database fields become NULL even when fan/share/uptime values are available. This is not a claim that every third-party firmware uses the same keys. The coordinator independently inspected the static firmware JSON builder, without contacting a board. Current history consumers mainly use hashrate, which limits immediate visible impact but does not restore the discarded history.

**Recommendation and regression check:** create one tested, nil-preserving `MinerInfo` to `MinerReadingInput` conversion. Use canonical keys and supported aliases. Derive pool selection from the actual pool shape only when authoritative information is available. Feed representative wire fixtures through the app conversion, record and flush them, and assert populated database columns. Database tests that directly construct `MinerReadingInput` do not cover this boundary.

### 5.3. P2: the widget completeness gate starves the Mac menu-bar snapshot

**Location:** `App/Store/FleetStore+Totals.swift:146-151`, `App/Store/FleetStore.swift:168-194`, `App/HashFleetApp.swift:189-200,222-234`, `App/Store/FleetStore+Monitoring.swift:36-38`, and `App/Store/FleetGlanceCoordinator.swift:69-81`.

`canPublishGlance` requires both hashrate and power completeness for every online miner. That policy is intentionally appropriate for widget aggregates whose schema has no completeness flag. However, both publication paths also gate the separate Mac per-miner snapshot. `Sources/HashFleetCore/XMRigAPIClient.swift:95-132` never translates a power field, so adding an online CPU miner makes the gate remain false. The menu-bar list can stay empty or retain an earlier snapshot even while the main app receives useful per-miner readings.

**Evidence boundary:** source-confirmed across both publishers and the only menu-bar snapshot writer. Signed app-to-companion behavior was not run.

**Recommendation and regression check:** publish per-miner state and freshness separately from aggregate eligibility, or extend the companion payload to represent metric completeness. Keep the conservative widget policy. Test an all-ASIC fleet, an ASIC plus online XMRig, a partial sensor response, and an all-offline fleet. The companion should receive current rows without advertising incomplete totals as complete.

### 5.4. P2: a second packaging run can reuse a stale primary app

**Location:** `Scripts/package-hashfleet-mac.sh:59-74`, with persistent default derived data near the top of that script.

The script invokes `xcodebuild` only when `APP_SOURCE` is not already a directory. After a successful first run, a source change followed by the same packaging command skips the main app build. The script nevertheless rebuilds the release CLI and bundles both. It can produce a distribution with an old app and a new CLI.

**Evidence boundary:** the coordinator verified the shell branch and subsequent copy operations. Packaging, signing, installer construction, and installation were not executed during the audit.

**Recommendation and regression check:** always invoke the normal incremental app build, except for a documented explicit prebuilt-app override. In an isolated packaging test, build revision A, change an app-only marker, package revision B with the same derived data, and assert the bundled marker is B.

### 5.5. P3: database failure is hidden and failed reading batches are dropped

**Location:** `Sources/HashFleetCore/Database/MinerTelemetryDatabase.swift:13-38`, `Sources/HashFleetCore/Database/MinerTelemetryDatabase+Reading.swift:42-58`, `Sources/HashFleetCore/Database/MinerTelemetryDatabase+Maintenance.swift:49-66`, and `App/Store/FleetStore+Persistence.swift:162-173`.

A failed database open leaves an optional nil queue. Writes through optional chaining then silently do nothing. `flushReadings` removes its pending batch before the write and does not restore it on error. `clearAllData` returns Void and catches errors internally, so `clearAllTelemetryAndAchievements` resets app baselines and pending events even if the database delete failed. The UI has no result with which to distinguish success from failure.

The accepted impact is silent loss of failed batches and inconsistent clear-data state. A subsequent duplicate announcement was not demonstrated and is not required for this finding. No production database was opened, cleared, corrupted, or made read-only for testing.

**Recommendation and regression check:** expose database availability and typed operation results. Requeue failed writes with a bounded policy. Reset app baselines only after confirmed deletion. Inject a failing/read-only/closed test queue and assert a surfaced error, retained batches, and unchanged baselines on delete failure.

### 5.6. P3: XMRig summary parsing does not validate the response shape

**Location:** `Sources/HashFleetCore/XMRigAPIClient.swift:15-25,95-132`; online state at `Sources/HashFleetCore/MinerStatusSnapshot.swift:20`; existing fixture at `Tests/HashFleetCoreTests/XMRigAPIClientTests.swift:98-111`.

Any successfully decoded JSON can become an empty `MinerInfo`, even if it is `{}`, an array, or unrelated gateway JSON. The shared service regards a non-nil info object without an error as online. ESP-Miner info has a shape validator, but XMRig has no corresponding check. The existing authorization-header test deliberately returns `{}` and expects summary parsing to succeed, so a passing suite does not protect this behavior.

**Recommendation and regression check:** reject responses without a meaningful XMRig signature, with a dedicated incompatible-service error. Require enough structure to avoid accepting a generic `version` field alone. Test empty objects, arrays, unrelated JSON, a minimal valid summary, and the v2-to-v1 404 fallback. The coordinator verified the parser and existing test, but did not run a new standalone XMRig service reproduction.

### 5.7. P3: unreadable configured state falls through to discovery

**Location:** `Sources/HashFleetCore/FleetSharedStore.swift:17-19,30-35` and `Sources/hashfleet/main.swift:13-24,51`.

`readDevices` returns the same empty array for absent data, inaccessible state, or decoding failure. With no explicit hosts, the CLI interprets that as no configured fleet and performs local discovery. An empty discovery result has no offline miners, so the command can exit zero without checking the intended configured targets.

**Corroboration and limit:** read-only inspection on the review machine found the devices key in the App Group container preferences but not in the ordinary suite-named preferences file. The freshly built debug CLI has no application-groups entitlement. This supports a shipping integration concern, not proof that every installed CLI fails App Group access. The coordinator did not run bare `hashfleet status`, because doing so could scan the real LAN. No target list or private preference values were copied into this report.

Discovery is documented behavior for a genuinely unconfigured fleet. The defect is conflating unreadable configured state with that condition. Severity is conservatively P3 because the shipped signed entitlement and end-to-end access were not established.

**Recommendation and regression check:** distinguish empty, unavailable, and invalid configuration. Provide a supported configured-fleet bridge or explicit portable config and make fallback selection observable. Use isolated stores to assert that invalid/unreadable configuration produces an actionable error rather than silent discovery.

### 5.8. P3: unknown CLI flags are silently ignored

**Location:** `Sources/hashfleet/main.swift:7-15`.

The parser checks only for help and JSON, then discards every dash-prefixed argument from the address list. A typo such as `--not-a-valid-option` is ignored, and a valid explicit target is still queried successfully. Unknown command words are instead treated as host strings, not validated as commands.

**Reproduction:** `status --not-a-valid-option --json <loopback-host>` queried `/api/system/info` and exited zero. Evidence is case `unknown_flag_accepted` in `cli-loopback-results.json`.

**Recommendation and regression check:** validate supported flags and the single optional `status` verb before any device request. Unknown flags and verbs should print usage to stderr and exit with a usage error. Test that invalid input causes zero requests. Retain the documented no-verb status shorthand if desired.

### 5.9. P3: the Mac distribution guide describes components the script does not ship

**Location:** `docs/MAC-DISTRIBUTION.md:3,11-25`, `Scripts/package-hashfleet-mac.sh:82-119`, `Scripts/install-hashfleet-mac.sh:61-67`, and `App/Features/Settings/FleetPreferencesView.swift:131-172`.

The distribution guide describes a companion app and LaunchAgent in the package/install flow. The current script stages the primary wrapped app and CLI only. The top-level README already treats the companion as separate. A fresh installation following the distribution guide can therefore lack the executable needed by the Preferences menu-bar toggle, whose failure text tells the user to open an app that was not installed.

**Evidence boundary:** source and document comparison, not a fresh installer smoke test. This does not establish that a manually installed companion fails.

**Recommendation and regression check:** choose and document one distribution contract. Either ship the companion through a supported path, or clearly describe its separate installation and detect its absence in Preferences. Inspect a freshly produced installer file list in CI and test the clean-install toggle experience on a disposable user account.

## 6. Security and privacy

### 6.1. P3: raw HTTP error bodies reach the terminal without a bound or control-character filtering

**Location:** `Sources/HashFleetCore/MinerAPIClient.swift:205-215`, `Sources/HashFleetCore/FleetStatusService.swift:39`, and `Sources/hashfleet/main.swift:80-86`. App error persistence also consumes the string at `App/Store/FleetStore+Evaluation.swift:262-290`.

The API client takes JSON error text or the entire trimmed response body as its localized error message. A configured or scanned untrusted service can return long text, newlines, or terminal control sequences. The CLI interpolates the resulting error directly into its table. App connectivity logging can persist the same unbounded text.

**Reproduction:** a loopback-only fixture returned HTTP 500 with an ANSI color escape, a newline, and 5,000 repeated characters. The compiled CLI exited one and preserved the controls and full repeated content in captured stdout. Case `unbounded_control_text_error` in `cli-loopback-results.json` contains JSON-escaped evidence. It was captured rather than printed as executable terminal controls. No command execution or credential theft is claimed.

**Recommendation and regression check:** cap display/persisted error length, remove control characters and line breaks at the presentation/logging boundary, and prefer concise status descriptions for non-JSON responses. Preserve raw bodies only in explicitly requested, separately protected diagnostics. Assert bounded length and absence of controls with synthetic malicious responses.

### 6.2. Reviewed boundaries and non-findings

The reviewers inspected strict host parsing, mutation endpoint construction, redirect blockers on the primary ESP and XMRig API clients, numeric conversion, recursive JSON redaction, and the app's hardware-control safety gates. This review found no evidence that the CLI exposes restart, OTA, tune, monitor, or record commands. The CLI only polls status.

`--json` intentionally serializes the raw firmware info object, which may contain wallet/worker/network identifiers. The review did not establish its intended privacy contract, so this is a **hardening/product decision, not an accepted secret-disclosure defect**. Document that the output is unredacted or offer a redacted export mode. Do not paste real raw exports into public reports.

The discovery client's redirect behavior is a follow-up hardening candidate, not an independently reproduced accepted finding here. A full hostile-network, transport, or credential audit was not performed.

## 7. Performance

No measured performance regression was established. Compilation time and model review duration are not runtime app benchmarks. The static review considered recorder batching, bounded history, polling, and publish throttling, but did not profile CPU, memory, energy, database growth, or network utilization.

A future performance pass should use deterministic recorded fixtures, bounded large-fleet inputs, and real instruments. Do not tune miner frequency, voltage, power, or cooling to investigate app performance.

## 8. SwiftUI and user-interface correctness

### 8.1. P2: stale per-miner rows still say “Live” and remain green

**Location:** `MacMenuBar/HashFleetMenuBarApp.swift:104-106,133-135,219-233`.

The popover header and title evaluate snapshot staleness, but each miner row receives only its persisted miner summary. `statusText` maps cached `.online` directly to “Live” and `statusColor` maps it to green. No age is passed to those functions. After publication stops, the companion can display a stale warning above rows that continue to claim live readings.

**Evidence boundary:** both the worker and coordinator independently traced the UI inputs and freshness guards. No production app or companion was launched.

**Recommendation and regression check:** pass snapshot freshness or per-row observation time into the row. Render stale/last-seen state consistently and avoid green “Live” for expired data. Test with a frozen clock and a previously online snapshot older than the staleness limit, including when the main app has closed.

### 8.2. P3: demo data is not labeled in the menu-bar title or accessibility tooltip

**Location:** `MacMenuBar/HashFleetMenuBarApp.swift:252-262` and `App/Store/FleetGlanceCoordinator.swift:75-81`.

Demo glances can be written to the same companion cache. Both compact and accessibility title formatters ignore `isDemo`. A DEMO badge exists inside a miner row, but it does not protect the normal closed-popover menu-bar presentation. Synthetic fleet counts/hashrate can therefore appear like live totals at a glance.

**Recommendation and regression check:** label the compact title, tooltip, and header when `isDemo` is true. Add pure formatter tests comparing otherwise identical real/demo snapshots. Do not erase or overwrite a useful live snapshot merely to hide the labeling issue.

### 8.3. P2: the iOS 17 control-intent path discards detailed consent context

**Location:** `App/Features/SystemIntegrations/FleetMinerControlIntents.swift:109-121`, `App/Features/SystemIntegrations/FleetMinerControlExecutor.swift:206-217,223-236`, and the iOS 17 deployment target in `project.yml:4-5`.

The executor builds a confirmation dialog naming the saved miner, address, requested action/value, and hardware-risk explanation. The iOS 18-or-newer branch forwards that text to system confirmation. The supported iOS 17 branch calls bare `requestConfirmation()` and discards the supplied dialog. The app's explicit risk explanation is therefore not forwarded on that branch, despite the control intents' promise to confirm risks.

This is a consent-context fidelity defect, not an unauthenticated write. Local device authentication, user confirmation, demo isolation, target re-resolution, parameter validation, cancellation checks, and fresh preflight reads remain present. System-generated UI may independently show parameter information. Exact visible rendering on iOS 17 was not inspected, so the review does not claim that the system hides every target/value detail.

The native intent tests check the string supplied to the injected confirmation closure, not the OS-version-specific presentation adapter (`AppTests/FleetMinerControlIntentTests.swift:30-71`). They were compiled but not executed here.

**Recommendation and regression check:** use a supported presentation path that actually shows the target/value/risk text on every supported OS, or limit these control intents to versions where that contract can be met. Do not remove authentication or confirmation as a workaround. Test the version adapter separately, then perform a controlled, non-mutating confirmation/cancel acceptance run on iOS 17.

### 8.4. P3: XMRig control shows cached state without labeling it and omits the shared freshness gate

**Location:** `App/Features/Miner/XMRigControlView.swift:37-52,101-130`, `App/Store/MinerSnapshotCacheEntry.swift:10-17,45-52`, and `App/Store/FleetStore+Persistence.swift:79-94`.

The cache explicitly preserves `miningPaused` and hashrate, restoring a snapshot marked cached, reconnecting, and errored. The XMRig control screen reads its info directly to display “Mining” or “Paused” and select which button is enabled. It does not label that info as cached/offline or consult `MinerWriteAvailability`. Its button gate checks the current paused value, sending state, and demo mode, and send proceeds directly to the XMRig client after confirmation. Cached or stale state can therefore be presented as current and used to choose the enabled command.

Pause/resume is reversible and the UI has confirmation plus surfaced send errors, so this is conservatively P3. It is not a claim that an unreachable host can successfully receive a command or that a failed send is reported as success. The coordinator traced the cache and control sources, but did not launch this screen or send a CPU-miner command.

**Recommendation and regression check:** label last-known state and reuse the freshness-aware availability/notice policy where appropriate. Recheck state when confirming a command. Render cached, stale, offline, and fresh fixtures and assert honest labels and enabled states without contacting a real XMRig host.

## 9. Dead code, duplication, and maintainability

No deletion or broad refactor is recommended solely from this review. The most useful consolidation is a tested nil-preserving wire-to-telemetry mapping (§5.2), followed by separate presentation contracts for complete aggregates and partial per-miner state (§5.3).

A lower-confidence Mac observation is that Preferences initializes its menu-bar toggle into local `@State`, while Hide in the companion changes the shared preference independently. An already-open Preferences view may display the old value. This needs a signed runtime lifecycle test before it is counted as a confirmed UI finding.

The earlier root `CODE_AUDIT.md` is a historical audit and is deliberately not overwritten by this dated report.

## 10. Cross-cutting review method, scope, and routing

### 10.1. What the request was interpreted to mean

The initial response incorrectly treated routing clarification as a reason not to start. That was not fulfillment of the user's request. After the user clarified “review all of these apps,” the task was executed as a source/integration review, not as fleet operation or permission to repair every finding. “amd cli” was interpreted as “and CLI.” The primary Mac app and separate menu-bar target were both included.

The remaining interpretations are explicit rather than presented as user confirmations: the CLI scope is this repository's `hashfleet` executable, not an AMD GPU-specific CLI, and “review” does not authorize automatic repairs or hardware operations. The coordinator initially interpreted “top-tier-only” as allowing four specialists on the Sonnet route. The user later explicitly rejected that interpretation. It was not fulfillment of the model requirement. The scope check below establishes coverage of the interpreted applications, not proof of an unstated AMD-specific requirement or user acceptance of the historical reviewer choice.

All accepted work was rechecked against that scope. Builds covered the actual app targets, CLI checks used its actual status-only interface, and core findings were traced to app/CLI consumers. No claim relies on the abandoned initial admission attempts or on stale playbook telemetry.

### 10.2. Accepted worker routes

| Scope | Worker | Persisted provider/model | Requested effort |
| --- | --- | --- | --- |
| iOS/iPadOS | chick | `claude-oauth` / `claude-sonnet-5-5` | high |
| Mac app, companion, distribution | cow | `claude-oauth` / `claude-sonnet-5-5` | high |
| CLI | chipmunk | `claude-oauth` / `claude-sonnet-5-5` | high |
| Shared core/security/contracts | crocodile | `claude-oauth` / `claude-sonnet-5-5` | high |

Actual provider/model identity was checked through session metadata and completed worker reports, not inferred from worker self-description. Specific account labels were not exposed and are not invented. These were four role-specialized reviewers on the then-selected Sonnet route, not four independent model families, a new market leaderboard ranking, or fulfillment of the user's subsequently clarified model preference.

The first automatic admissions landed on models outside the requested top-tier-only scope. They were stopped and their output was not accepted. To admit the actual review workers, only the configured default `agents.swarm_model` was temporarily set from `auto` to `claude-oauth:claude-sonnet-5-5` at 07:53:59 UTC, then restored to `auto` at 07:54:41 UTC on October 18, 2026. Spawns omitted per-worker model/account overrides. Approved pools, accounts, credentials, and provider balancing were not changed. No daemon restart or paid benchmark run was performed.

### 10.3. Evidence discipline

Worker findings were deduplicated and checked against actual guards. The suspected missing menu-bar URL scheme was **rejected** after the coordinator inspected the freshly compiled companion Info.plist and found `hashfleet-menubar` registration. Raw JSON privacy, standalone explicit-XMRig CLI selection, the external-toggle refresh, and discovery redirects are called out as contract decisions or follow-ups rather than inflated into unproven critical defects.

### 10.4. Post-delivery scope recheck

The automatic follow-up prompted a fresh comparison with the original all-app review request. The initial iOS and Mac main-app builds used `DebugNoAppPush`. The original iOS log proves that `PushProvider.swift` compiled, so it would be incorrect to call the extension entirely unbuilt. However, the main app's `APP_PUSH_PROVIDER_ENABLED` branches, including its push-manager integration, were excluded by that configuration. A separate unsigned generic-simulator build using scheme `HashFleet`, configuration `Debug`, completed successfully at **08:26:39 UTC on October 18, 2026**. Its receipt includes the app-push compilation define and compilation of both `FleetLocalPush.swift` and `PushProvider.swift`.

This closes the compile-branch gap without launching the app or exercising background push. Findings remain 16, not a new claim that all have runtime reproductions. The intent remains review, not unrequested repairs. The admitted Sonnet route is historical provenance only. The user later rejected that choice, so this compile-branch recheck did not close the corrected reviewer-selection requirement.

## 11. What was not audited or could not be accepted at runtime

- No real ASIC or mining Mac was contacted by HTTP, WebSocket, SSH, discovery, or app launch. No live fleet status, temperature, hashrate, shares, or online-state claim is made. The canonical playbook was used for safety and scope, not telemetry.
- No restart, self-test, OTA, tune, pool change, power/wiring change, service restart, lockout reset, or hardware-control mutation was performed.
- The app and UI test bundles compile, but simulator runtime acceptance is blocked. Xcode logs report installed CoreSimulator `1171.7.0` older than the framework's required `1174.9.2`. An owned hanging enumeration command was canceled. CoreSimulator and other system services were not restarted.
- No signed App Group interoperability test between Designed-for-iPad app, plain CLI, and sandboxed companion was run. App Group access cannot be guaranteed by successful unsigned compilation.
- No fresh installer was executed. Signing, notarization, App Store distribution, LaunchAgent registration, login behavior, upgrades, and clean-install behavior remain unvalidated.
- Native unit/UI tests were built, not run. No accessibility, screenshots, memory profiling, energy profiling, background-push delivery, or OS notification acceptance was completed.
- Compilation is configuration-specific: iOS `DebugNoAppPush` and `Debug`, Mac Designed-for-iPad `DebugNoAppPush`, and native companion `Debug`. No Release/archive, signed distribution, or push-enabled Designed-for-iPad Mac configuration is claimed. Successful app-push compilation does not establish entitlement approval, registration, or delivery.
- Source review is bounded, not exhaustive. Public pool/insights clients, address validators, StoreKit/commercial flows, and every third-party firmware variant were not all reviewed in full. Passing opt-out smoke tests is not a live-service acceptance result.
- The CLI has no explicit miner-kind flag: positional hosts default to ESP-Miner. A loopback XMRig-only fixture confirms the CLI requests `/api/system/info`, not `/2/summary`, and exits one. Because explicit CPU-host selection is not documented, this is recorded as a **capability gap**, not a separate promised-feature defect. A future explicit-kind option should be tested with bearer-token handling and zero token disclosure.

## 12. Verification, artifacts, and handoff

### 12.1. Baseline checks actually completed

| Requirement | Observed check | Result and boundary |
| --- | --- | --- |
| Shared core baseline | Cached SwiftPM tests, all four live-network/private-fixture opt-ins explicitly removed | 52 XCTest methods plus 246 Swift Testing tests passed, zero failures |
| iOS NoAppPush configuration | `HashFleetNoAppPush`, `DebugNoAppPush`, generic iOS Simulator, isolated derived data, signing disabled | `BUILD SUCCEEDED` |
| iOS app-push-enabled configuration | `HashFleet`, `Debug`, generic iOS Simulator, separate isolated derived data, signing disabled | `BUILD SUCCEEDED`, app-push define and main-app/provider compilation verified |
| Primary Mac app | `HashFleetNoAppPush`, `DebugNoAppPush`, `platform=macOS,arch=arm64,variant=Designed for iPad`, isolated derived data | `BUILD SUCCEEDED` |
| Native Mac companion | `HashFleetMenuBar`, Debug, generic macOS, isolated derived data | `BUILD SUCCEEDED` |
| Native test target compilation | `HashFleetNoAppPush`, `DebugNoAppPush`, iOS generic simulator `build-for-testing` | `TEST BUILD SUCCEEDED`, not executed |
| CLI contract | Compiled CLI help and four assertion-checked cases against an HTTP server bound only to `127.0.0.1` | Expected defects reproduced, no LAN discovery |
| Claim primitive | Unchanged production file plus isolated harness/defaults suite | Multiple winners in all twelve trials |
| Mac script syntax | `bash -n` on all three distribution/LaunchAgent scripts | Passed, scripts not executed |
| Suspected URL scheme omission | Fresh companion's compiled Info.plist | Scheme exists, candidate rejected |
| Config restoration | Read-only check of configured `swarm_model` after admission | `auto`, pools unchanged |

The package baseline command was:

```sh
env -u HASHFLEET_SOLOFURY_SMOKE \
    -u HASHFLEET_PRIVATE_INFO_FILE \
    -u HASHFLEET_PUBLIC_DATA_SMOKE \
    -u HASHFLEET_SOLOPOOL_SMOKE \
    swift test --skip-update
```

Xcode invocations used cached SourcePackages with `-disableAutomaticPackageResolution -skipPackageUpdates`, isolated scratch derived-data paths, and `CODE_SIGNING_ALLOWED=NO`. No implementation or existing test was modified to obtain a pass.

### 12.2. Local evidence

Directory: `/Users/USER/.jcode/scratch/hashfleet-review-20261018/`.

- `review-manifest.json`: baseline, exact worker session IDs, routing restoration, build results, and safety boundaries.
- `ios-review.md`, `mac-review.md`, `cli-review.md`, `core-review.md`: scoped worker artifacts, including their uncertainty and checked-no-defect lists.
- `swift-test-all-live-optins-disabled.log`: authoritative package baseline. `swift-test.log` is an earlier run and is not used to claim disabled opt-ins.
- `ios-build.log`, `ios-push-build.log`, `mac-main-build.log`, `mac-menu-build.log`, `ios-tests-build.log`: fresh configuration-specific app/test-target build receipts.
- `reproduce_cli_contract.py`, `cli-loopback-results.json`: loopback-only requests, captured outputs, and assertions for partial metrics, ignored flags, explicit XMRig endpoint selection, and unbounded control-text errors.
- `atomic_claim_harness.swift`, `atomic-claim-results.json`: exact isolated claim reproduction and winner counts.
- `verify_review.py`: read-only report/evidence consistency checker for section numbering, finding counts, source paths, build/test receipts, fixture outcomes, config restoration, and report-only repository changes.

Scratch logs are local evidence, not a portable checked-in test suite. The dated review report is the durable repository handoff. Findings should become small independently tested changes, beginning with the P2 items. Hardware acceptance or configuration changes require separate explicit operator authorization.

### 12.3. Final whole-result check through actual project interfaces

The final pass ran **08:33:59-08:35:33 UTC on October 18, 2026**, after the full requirement map was established. It invoked the unchanged repository's own SwiftPM tests, built the actual CLI product, ran its public commands, rebuilt every app configuration listed above, rebuilt the native test bundles, checked all three scripts, and reran report consistency validation. A Python runner only launched these tools and captured their output. It did not replace the production code or stand in for app runtime acceptance.

| Request or output | Final observed behavior | Acceptance boundary |
| --- | --- | --- |
| Execute the swarm, not just propose it | Four accepted workers were observed `ready`, all reporting Sonnet 5.5 at high effort, with four completed scope artifacts | Initial wrong-tier admissions are excluded; no new latest-model ranking is claimed |
| Review the iOS app | Both actual iOS schemes rebuilt successfully: `HashFleetNoAppPush` / `DebugNoAppPush` and `HashFleet` / `Debug` | Compile coverage, including the earlier missing app-push branch, not an executed iOS UI flow |
| Review the Mac app and companion | Designed-for-iPad primary app and separate native companion both rebuilt successfully | Their unsigned builds do not establish signed App Group exchange or visible UI behavior |
| Review the real CLI entry point | `swift build --skip-update --product hashfleet` succeeded; the built executable's `--help` exited zero and printed `Usage: hashfleet status` | This is the real product, not a copied-source harness |
| Exercise CLI JSON and terminal status | Against one explicitly selected unavailable loopback endpoint, JSON and table commands each exited one; JSON contained one miner with `The request timed out.` and no info; the table printed `0/1 online`, `--` metrics, and `OFFLINE: The request timed out.` | No HTTP fixture or mock server responded. This exercises actual transport-error and public-output paths, not a healthy miner or configured-fleet discovery |
| Check the shared production implementation | All **52 XCTest methods plus 246 Swift Testing tests passed again** | Includes real in-memory SQLite via the production database API, not a mocked database; does not establish disk reopening or the app's wire-to-reading conversion |
| Check observed persistence operations | Existing write/read, batch-flush, achievement readback, and empty-keep-set deletion-guard tests each reported `passed` | Assertions read real SQLite rows. Forced database failures and signed cross-process storage remain untested |
| Recheck native test and distribution boundaries | Native `build-for-testing` succeeded again; all three actual shell scripts passed `bash -n` | Test bundles were not executed; package/install/LaunchAgent scripts were not run |
| Exercise the actual simulator interface | Read-only `xcrun simctl list devices available --json` did not return within 15 seconds and only that command was terminated; fresh Xcode logs again reported installed CoreSimulator `1171.7.0` versus required `1174.9.2` | Runtime acceptance remains blocked. No service restart or speculative simulator repair was performed |
| Validate the changed public deliverable | All 16 finding/table pairs, source references, reviewer artifacts, historical reproductions, and fresh tool receipts are checked by the final verifiers; repository diff is the dated report only | Verifying a review is not a regression fix. Source-only findings remain source-only, and recommended future regression checks are not claimed as run |

New receipts are in the evidence subdirectory `acceptance-0830/`: `actual-project-results.json`, per-command stdout/stderr logs, and the final report-verification receipt. The two CLI requests used a port reserved by a bound, non-listening loopback socket, not a simulated miner. The product reported timeouts, so this report does not relabel them as immediate connection-refusal results. All live/private opt-ins and `XMRIG_TOKEN` were removed from the check environment. The simulator probe's timeout is an explicit blocked observation, not counted as UI success merely because the bounded check runner exited zero.

**What improved:** the task progressed from an initial non-executed routing response to four completed scoped reviews, an inspectable 16-finding handoff, verified compilation of the previously excluded main-app push branch, and observed real CLI and SQLite behavior. A false missing-URL-scheme candidate was rejected using the actual compiled companion plist. These are concrete improvements in execution and review evidence, not a claim that the 16 product defects were repaired. No product implementation, existing test, miner, production database, or service was changed.

**Where closure stops:** iOS UI execution is externally blocked by the simulator toolchain. Mac UI, signed interoperability, fresh installer acceptance, background push/notification delivery, and healthy live-miner paths were not exercised. The historical custom harness and HTTP fixtures remain supplementary defect evidence, not substitutes for these missing acceptance paths. The review handoff is complete within its stated scope; end-user acceptance and repaired-product acceptance are not established.
