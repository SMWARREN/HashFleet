# Second firmware audit: model-aware native coverage

## Scope and pinned evidence

Audit date: **2026-09-06**, source inspection beginning at approximately **21:14 UTC**. This audit owns only this document. It did not build, run tests, commit, contact a physical miner, scan a network, or execute any device mutation.

- GitHub [`commits/master`](https://api.github.com/repos/bitaxeorg/ESP-Miner/commits/master) resolved to **`2943d206f6c8a4b249bc74c820fb56c874ac316d`**, committed 2026-09-02 16:58:33 UTC, message `typo (#1942)`.
- This is **exactly the existing `2943d206` baseline**, not a newer firmware revision. There is no upstream commit or endpoint delta to attribute to this second audit.
- Downloaded the archive addressed by that full commit, not a moving branch, into `$JCODE_SCRATCH_DIR/hashfleet-second-audit/`.
- Pinned `main/http_server/http_server.c` SHA-256 is `3511fb32cb75a444ab7c7ae64988652630c71e952193276dca9f233ee413d63c`. Pinned `theme_api.c` SHA-256 is `1bd3077f226e5b00ee382e5870a10ff6a71af12cd4fb52152a683cba813e8348`. Both match `docs/API-COVERAGE.md` exactly.
- App reference commit during inspection: **`be7c730cfd1869ca7cbc4fa841144dc9646b65db`**, plus concurrent uncommitted capability work. Findings below distinguish the pre-capability screen behavior from work being integrated. App line numbers can move during that integration, so symbols are also supplied.
- Read `docs/CAPABILITY-CONTRACT.md`, `docs/API-COVERAGE.md`, and `docs/SWARM-SETTINGS-PARITY.md`. The contract's two-GET, explicit-check, partial-result, no-device-mutation restrictions govern this report.

**Bottom line:** Transport/API inventory is already broad. The highest-value remaining work is truthful telemetry and model-aware presentation, not more endpoints, more automatic requests, or electrical presets.

## Source index

All upstream references below are relative to [the pinned tree](https://github.com/bitaxeorg/ESP-Miner/tree/2943d206f6c8a4b249bc74c820fb56c874ac316d), not `master`.

| Ref | Pinned source | Relevant evidence |
|---|---|---|
| U1 | [`main/http_server/http_server.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/http_server/http_server.c) | Info handler 1380–1418, unconditional Info/ASIC registrations 1885–1910, settings validation 839–1033, hostname response 1074–1116, statistics 1547–1598 |
| U2 | [`main/http_server/system_api_json.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/http_server/system_api_json.c) | Full Info shape: telemetry 47–118, identity/config 120–240, ASIC monitor 242–268, reject reasons 271–284, partitions 312–343 |
| U3 | [`main/http_server/axe-os/api/system/asic_settings.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/http_server/axe-os/api/system/asic_settings.c) | ASIC handler 24–71, flat reference payload 40–66 |
| U4 | [`main/device_config.h`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/device_config.h) | ASIC identities/options 105–124, family counts 135–144, board hardware flags 158–183 |
| U5 | [`main/device_config.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/device_config.c) | Known board lookup and custom NVS configuration path |
| U6 | [`main/thermal/thermal.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/thermal/thermal.c) | Fan 1/2 77–97, temperature 1/2 99–132, unavailable and initialization sentinels |
| U7 | [`main/http_server/cjson_utils.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/http_server/cjson_utils.c) | Recursive object diffs, whole-array replacement, no deleted-key tombstones, 17–54 |
| U8 | [`main/http_server/websocket_api.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/http_server/websocket_api.c) | `event:update` envelope, full initial state, 500 ms rate limit |
| U9 | `main/http_server/axe-os/src/app/components/` | `home/home.component.html`, `system/system.component.ts`, `edit/edit.component.ts`, `network-edit/network.edit.component.ts`, `pool/`, `update/`, `scoreboard/`, `swarm/` |
| U10 | [`main/nvs_config.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/nvs_config.c) | Actual REST storage/type bounds, particularly hostname 57, cooling 75–77, statistics 83 |

## Payload and probe semantics: implementation handoff

These findings were communicated to the root during inspection and the model constraints were also sent to the UI worker.

### Info is not ASIC, and neither is a capabilities manifest

`GET /api/system/info` returns a **flat JSON object** assembled by U2, with nested `pools`, `partitions`, `sharesRejectedReasons`, and optionally `hashrateMonitor`. U1 adds `fullHostname` and, when available, `mdnsHostname`.

`GET /api/system/asic` returns a **flat JSON object** with:

```json
{
  "ASICModel": "BM1370",
  "deviceModel": "Gamma",
  "swarmColor": "green",
  "asicCount": 1,
  "hashDomains": 4,
  "defaultFrequency": 525,
  "frequencyOptions": [400, 490, 525, 550, 600, 625, 690],
  "defaultVoltage": 1150,
  "voltageOptions": [1000, 1060, 1100, 1150, 1200, 1250]
}
```

This example is derived from U3 and U4, not captured from a device. Units are MHz and mV. It describes firmware-selected identity/reference values. It does **not** establish safe combinations, physical limits, successful ASIC initialization, or PATCH support.

Per-chip runtime data instead appears at **`info.hashrateMonitor.asics`**, as entries containing `total`, `errorCount`, and `domains: number[]`. U2:243 omits the entire monitor before initialization. A missing monitor is therefore **Not reported**, not proof of an unsupported ASIC endpoint or board.

### Required state distinctions

| Observation | Correct user-facing interpretation |
|---|---|
| No manual check yet | Not checked |
| Recognized object from Info | Info responded with recognizable data |
| Recognized object from ASIC | ASIC reference endpoint responded |
| Info succeeds, ASIC fails or is absent | Preserve Info success and show an independent ASIC state |
| HTTP 404 / 405 / 501 | Endpoint unavailable/not implemented on this firmware or target, not “this model is unsupported” |
| HTTP 401 / 403 | Access/authentication failure, not unsupported hardware |
| HTTP 429 / 500 / transport/TLS/timeout error | Check failed, retry explicitly |
| HTTP 200 HTML, scalar, array, `{}`, unknown-only/error-only object | Unrecognized response, not a valid miner and not model non-support |
| Recognized identity with missing telemetry | Identity may be reported while each missing metric is Not reported |
| Cancellation | Stop the task without converting it into hardware non-support |

Both U1 and U3 explicitly return **401** when `is_network_allowed` fails and **500** if CORS-header setup fails. Info and ASIC registration is unconditional in this pinned build, independent of named model. Their presence in the endpoint catalog is not evidence that an older or custom installed build supports them.

Recognition should accept meaningful typed identity/reference/metric fields without requiring a named ASIC. Document the recognized keys centrally and reuse that policy at admission to the fleet. Do not accept arbitrary JSON merely because decoding succeeded. A permissive recognized-field policy remains compatibility recognition, not cryptographic device identification. Preserve unknown fields in raw JSON. Never include response-body secrets in compact failures.

## Model constraints that materially change the UI

| Family in pinned source | Reported ASIC | Count | Consequence |
|---|---|---:|---|
| Max | BM1397 | 1 | One hash domain in U4. Do not require four-domain arrays. |
| Ultra / Hex | BM1366 | 1 / 6 | Same chip name, different board scale and cooling. |
| Supra / SupraHex | BM1368 | 1 / 6 | Do not derive chip count from the ASIC string. |
| Gamma / GammaDuo / GammaTurbo / GammaHex | BM1370 | 1 / 2 / 2 / 6 | Same chip string does not select tuning defaults or sensor count. |
| NajaDuo | BM1372/BM1373 | 2 | Literal combined ASIC name is legitimate, not an unsupported model string. |
| Custom NVS boards/forks | May differ | Reported | U5 supports a custom configuration path. Unknown identity must remain readable without pretending model certainty. |

U4:121–123 defines **three BM1370 configurations with default frequencies 525, 400, and 690 MHz**. Model-name lookup alone would produce the wrong configured reference for at least two families. Read the current ASIC payload, and keep configured Info `frequency`/`coreVoltage` separate from `actualFrequency`/`coreVoltageActual` measurements.

**Sensor presence trap:** U2 emits `temp2` and `fan2rpm` unconditionally. U6 returns `-1` for unavailable temperature and before ASIC initialization. Fan 2 returns `0` without EMC2302. These values do not establish a permanent hardware absence, and a reported `0 RPM` can also be a stopped fan. In pinned U4, Hex/SupraHex boards use EMC2302/TMP1075, while GammaTurbo/NajaDuo/GammaHex use EMC2103. GammaDuo has two ASICs but EMC2101. Do not equate ASIC count with temperature or fan count. Model/board tables are explanatory evidence, not write authorization.

## Prioritized concrete gaps

### P1. Reject unrecognized Info on the normal fleet polling path

**Observed at audit start:** `Sources/HashFleetCore/MinerInfo.swift:init(from:)` accepts any object. `App/Store/FleetStore.swift:performRefresh` calls `client.info()`, saves that result, appends `info.hashRate`, and counts any non-error object as online through `activeSnapshots`. A 200 `{}` or error-only object therefore becomes an online miner with fabricated zero history. Rejecting it only in the new manual capability probe does not close the ordinary polling path.

**Improve:** Reuse recognized Info shape validation before admitting a successful poll, without adding an ASIC GET to polling. Keep the last known valid snapshot explicitly stale on failure. Distinguish missing hashrate, shares and uptime from zero in `MinerOverviewCard.reading` and `MinerDetailView.hashrateHero`/`identity`. Fleet power/efficiency must state incomplete coverage if participating miners omit those measurements, instead of mixing default-zero power with valid hashrate.

**Model constraint:** Missing optional sensors are legitimate on old/custom firmware. Do not reject a known-shape response just because it lacks a metric or expected model name.

**Acceptance:** Synthetic HTTP 200 `{}`, error-only, and unknown-only payloads are not Online and add no zero history. A partial recognized Info object remains readable but missing telemetry is not rendered as a real zero. A valid stopped-mining `hashRate:0` remains zero.

### P1. Surface reported miner faults and distinguish reachable from mining normally

**Evidence:** U2:103–117 emits `miningPaused`, `overheat_mode`, and conditional `power_fault`/`hardware_fault`. U9 home explicitly suppresses normal hashrate presentation for power faults. Native `MinerOverviewCard.status` currently equates successful telemetry with “Online”, and `MinerDetailView.heading` says “CONNECTED”. Neither screen initially promotes these mining/fault states.

**Improve:** Keep connectivity and operational status separate. Show reported hardware/power fault messages prominently in detail, a compact warning in the fleet card, and a clear paused state. Show the firmware-reported thermal/overheat state as read-only information, without offering a reset or thermal-protection bypass.

**Model constraint:** Fault strings and flags are firmware-dependent. Their absence is not proof of hardware health. Do not invent universal temperature thresholds from model name.

**Acceptance:** Reachable+paused is not shown as unreachable or healthy-mining. Reachable+fault is visible without opening raw JSON. Missing flags remain unknown. No mutation is triggered by viewing or dismissing UI-only disclosures.

### P1. Make Info/ASIC support evidence visible and use it consistently in settings

**Evidence:** Initial `MinerSettingsView` lists all categories, defaults automatic fan to `true`, inversion to `false`, and pool selection to slots 0/1 when values are absent. `MinerTuningSection` originally makes an independent manual ASIC request but exposes no consolidated Info/ASIC status. `MinerEndpointCatalogView.endpointLabel` always says support is unverified. The core has all endpoints already, so this is a presentation/admission gap, not a missing route.

**Improve:** Implement the existing capability contract: an explicit two-GET check, independent status rows, timestamp, model/board/firmware identity, and compact partial-failure states. Native forms should distinguish reported current values from provisional drafts and gate by relevant reported field types in a successful current report. An Info success with ASIC 404 must not disable unrelated reported display/pool settings. A missing ASIC options list must not imply tuning safety or unsupported hardware. Clear outdated support on identity/firmware changes.

**Model constraint:** Info and ASIC give read evidence only. Label writable settings “reported by firmware”, not “verified safe/supported”. Do not infer pool endpoint/SV2 support from ASIC model.

**Integration status:** New capability core/store/view files appeared during this audit and are being integrated by their owners. This item is a baseline gap and acceptance checklist, not a claim that that parallel work is missing or tested. Avoid a second independent ASIC request when a fresh shared report already exists.

### P1/P2. Distinguish configured primary pool from the active fallback connection

**Evidence:** U2:159–168 emits `poolConnectionInfo`, `isUsingFallbackStratum`, primary/fallback indices and fallback enablement. U2:199 always emits `stratumURL` from the configured **primary** slot. `MinerInfo.poolURL` and `MinerDetailView.identity` display that value under the unqualified label “Pool”. It can be mistaken for the currently active connection while the miner is using fallback.

**Improve:** Use “Configured primary pool” for the existing row, or present a read-only active pool summary resolved from `isUsingFallbackStratum` and the explicitly indexed slot. Also show connection information and configured fallback status. Add optional latency, pending shares and rejection reasons in a pool diagnostics disclosure, not the fleet hero.

**Model constraint:** Resolve slots by their `id`, never array position. Legacy firmware can lack slots or active-status flags. In that case say active connection Not reported. SV1/SV2/TLS are firmware/pool properties, not ASIC properties.

**Acceptance:** Noncontiguous pool IDs and fallback-active fixtures select the correct URL. Missing active-status information never silently calls the primary active. Passwords are not copied or exposed in the friendly summary.

### P2. Add compact secondary telemetry and configuration-versus-measurement labels

**Evidence:** Detail currently shows one chip temperature, one fan RPM and configured `frequency`. U2 already provides `temp2`, `fan2rpm`, `actualFrequency`, `coreVoltageActual`, `expectedHashrate`, averaging windows and `errorPercentage`. U9 home displays second-temperature/fan information and expected/error diagnostics.

**Improve:** Promote available second-temperature/fan readings and actual-versus-configured clock/voltage inside a compact telemetry disclosure. Add an optional 1m/10m/1h hashrate summary and ASIC error percentage. These require no extra endpoint when Info is already available.

**Model constraint:** Respect the sentinel/init caveats above. Do not derive the expected number of sensors from a model name, convert sentinel `-1` into a real temperature, or label an observed zero fan as permanently unsupported. Error percentage is an ASIC diagnostic, not the rejected-share percentage.

**Acceptance:** Single-chip, two-chip and six-chip fixtures render without fixed array assumptions. Missing/negative sensor data is Not reported/unavailable rather than healthy zero. Measured and configured values are not conflated.

### P2. Add hostname-change recovery, not automatic redirect following

**Evidence:** U1:1016–1023 builds a new `.local` hostname, applies it live at 1090–1094, and returns JSON `redirect.url`, `delay`, `message` at 1097–1105. Native `MinerEndpointModel.execute` treats this as raw output. `MinerEndpointView.execute` subsequently refreshes the unchanged stored device address. The app has add/remove but no obvious address-edit flow in the inspected dashboard.

**Improve:** Before hostname review, warn that a miner saved by its old `.local` name may become unreachable. After confirmed success, offer a user-reviewed address update or explicit recovery instructions. Validate the address through `MinerDevice.validatedURL` and require a deliberate selection. Do not automatically follow arbitrary response URLs or resend writes.

**Model constraint:** This matters for hostname-addressed miners on firmware applying hostname changes live. IP-addressed entries may continue working. Preserve custom ports/schemes only when justified by the user-selected target, not guessed from firmware's hardcoded HTTP URL.

**Acceptance:** A synthetic hostname-change response offers recovery without silently changing the target. Invalid/untrusted URLs are not followed. A successful mutation followed by failed refresh is not relabeled as a failed mutation.

### P2. Improve pool advanced-field preservation without hiding replacement semantics

**Evidence:** `MinerTuningPoolDraft.payload` intentionally sends four basic connection fields plus the password-retention sentinel. U1's `update_pool_nvs` constructs replacement values for omitted fields. Existing replacement notices and acknowledgement are accurate and valuable. However, changing just a worker in the friendly form can reset TLS/certificate/difficulty/SV2 authentication unless the user adds those fields to JSON.

**Improve:** Prefer a deliberate advanced-fields disclosure with the current reported TLS and SV2 authentication state and an explicit preservation/replacement decision. At minimum, prominently flag a current nondefault TLS/SV2 configuration before producing a basic replacement. Do not silently replay stale hidden fields or credentials. This is a usability/safety improvement, not an assertion that the existing warning is absent.

**Model constraint:** Gate pool version/options using firmware evidence, not chip identity. Do not promise slot PUT support just because Info happens to contain legacy primary fields.

**Acceptance:** Existing secure slot fixtures cannot appear to be a harmless worker-only edit. Retention sentinel behavior and full-slot warnings remain. No secrets are read back into editable drafts.

### P2/P3. History, runtime ASIC registers, system diagnostics and scoreboard remain raw

**Evidence:** `FleetHistoryCard` correctly labels its local, bounded samples as “this session”. It does not consume U1's `labels` plus `statistics` rows or device-relative `currentTimestamp`. `MinerEndpointView` offers raw statistics and scoreboard reads. Native identity lacks most U9 System fields, including reset reason and running partition. Per-chip/domain monitor data is raw-only.

**Improve in order:** (1) A small system diagnostics disclosure with board/ASIC counts, reset reason, versions and running partition. (2) Optional explicit on-device history load with proper labels and reboot-aware timestamp reconstruction. (3) Optional per-chip totals/errors before considering a full domain heatmap. (4) A basic best-share/scoreboard view only if product demand justifies it.

**Model constraint:** Device history is volatile, can be disabled by `statsFrequency:0`, and must be decoded by labels rather than hardcoded column order. Per-chip monitor can be absent during initialization. Domain count varies, and network/coinbase block information is conditionally emitted only when available.

**Acceptance:** Empty history, reordered columns, reboot, absent monitor, one domain and six-chip fixtures are all meaningful empty/partial states. Do not mix on-device history with app-session history without labeling the source.

### P3. Future live-state expansion must respect upstream diff semantics

**Evidence:** `MinerLiveModel.connect` uses shallow `latestFields.merge(update)` at `MinerLiveView.swift:46–50`. U7 recursively diffs objects and replaces arrays/scalars wholesale. It iterates only new keys, so fields deleted from the full state do **not** generate tombstones. Current native live tiles are five top-level scalars, so this is primarily a limitation on expanding the console, not a demonstrated bug in those five displayed values.

**Improve:** If nested fields are promoted, merge objects recursively and replace arrays. Validate `event == "update"`. Never use this stream alone as authoritative current fault absence because omitted conditional faults can remain stale without deletion events. A user-requested full Info refresh or new connection provides a new baseline. Do not add automatic polling/reconnection to this audit's two-GET compatibility check.

**Acceptance:** Synthetic nested object updates preserve unchanged siblings, arrays replace instead of concatenate, and conditional-field removal does not claim cleared faults without full-state evidence.

## Screen-by-screen coverage disposition

| Native area inspected | Compared firmware UX | Disposition |
|---|---|---|
| Dashboard, MinerOverviewCard | Swarm and Home | Fleet aggregates/cards/search/ordering exist. Truthful partial telemetry and mining/fault state are higher priority than cloning the web dashboard grid. |
| FleetHistoryCard | Chart/history | Session history is implemented and correctly labeled. Device history is a separate optional workflow, not already covered by this chart. |
| AddMinerView, FleetOnboardingView | Swarm discovery/add | Manual host entry and explicit demo are sufficient. Automatic network discovery is intentionally not required or authorized. |
| MinerDetailView | Home/System | Core metrics exist. Compatibility/identity, operational faults, active pool and secondary readings are the main friendly-data gaps. |
| General settings | Edit/Network | Hostname and statistics interval exist. Keep app refresh separate from on-device statistics. Hostname recovery is a concrete follow-through gap. |
| Cooling settings | Edit | Automatic/manual, target and minimum fan exist. Missing-field states need improvement. Existing 0–99 minimum fan and 35–66 target bounds match U10, but are accepted-input bounds, not safe operating recommendations. |
| Display settings | Edit | Rotation/inversion/timeout exist. Hardware display type is intentionally advanced. “Colors” in category copy means inversion here, not a native AxeOS theme editor. |
| Pools settings | Pool | Slot/legacy workflows and replacement warnings exist. Active-status presentation and secure-field preservation are better investments than adding speculative protocol controls. |
| Manual tuning | Edit with optional overclock unlock | Explicit risky drafts and reported references exist. Consolidate with current compatibility results. No boost presets or hardcoded safe ranges. |
| Endpoint explorer / endpoint result | Full registered API plus legacy route | Existing 23 operations plus one explicit legacy entry remain valid. Binary OTA, logs export, boot, theme, Wi-Fi scan, scoreboard and recovery escape hatches already exist. No new endpoint inventory work is justified by this unchanged upstream HEAD. |
| Live console | Logs/live telemetry | Explicit connect, bounded frames and cancellation behavior exist. Nested diff caveats constrain future expansion. |
| Fleet preferences / Monitoring settings | App-specific settings, not firmware Edit | Refresh/sort/cards/widgets/Live Activity are app concerns. Do not fold them into miner PATCH or expose raw capability data to widget storage. |
| About / release information | No required firmware analogue | App/version/help surface is not a device capability guarantee and needs no firmware-parity control. |

## Intentionally advanced or not worth promoting now

- **Thermal protection controls and overclock unlock:** Keep `overheat_mode`/`overclockEnabled` out of normal forms. Read-only thermal status is valuable. A bypass toggle or model-derived boost preset is not.
- **Display hardware/type:** The existing raw editor is appropriate unless replaceable-display setup becomes a core use case. It is board-specific, not an obvious fleet-management omission. Rotation/inversion/timeout already cover everyday use.
- **Firmware OTA, web image upload, alternate boot and recovery:** Keep deliberate advanced workflows and strong confirmation. Do not promote one-tap latest-firmware installs, automatic image choice from ASIC name, or auto-reboot after an unrelated setting. ASIC/board/version identity is useful context, not image verification.
- **Wi-Fi credentials and scanning:** Raw advanced access already exists. A friendly provisioning flow would need secret handling, restart/reconnect recovery and explicit scan consent. It is not a prerequisite for useful read-only fleet monitoring.
- **Theme API, custom web UI appearance, animated web decorations:** Native app design should not mirror AxeOS's web theme just because `/api/theme` exists. Keep those endpoints discoverable in advanced tools.
- **Full domain heatmap, coinbase outputs, signals/scriptsig, developer heap breakdowns:** Useful specialist diagnostics, but not all belong on the first miner screen. Promote a compact system/fault summary first.
- **Pool TLS certificates, arbitrary SV2 authority settings, suggested difficulty and extranonce:** Keep advanced by default. Improve preservation warnings before expanding the form. They are firmware/pool-specific, not hardware compatibility toggles.
- **Legacy dashboard statistics, CORS OPTIONS, recovery HTML:** Explicitly label compatibility/developer paths. Do not probe them as part of a broad “supported operations” scan.
- **Bulk writes, automatic retries, network discovery, mutation-as-probe:** Not warranted by any gap in this audit. A successful Info/ASIC check is never authorization for these operations.

## Concurrent remediation observed at report close

At approximately **21:23 UTC**, a final source recheck found that the implementation owners had already added `MinerShapeValidator.isValidInfoShape` admission in `MinerAPIClient.info()`, guarded fleet history insertion with a genuinely reported nonnegative rate, and added detail fault-banner and active-pool presentation code. The compatibility core/store/view also exists. These observations address portions of the baseline P1 findings above. They are **source-level remediation observations, not build or behavioral verification by this worker**. Root should use the acceptance criteria to verify the final integrated result and track any remaining partial-metric, fleet-card, or paused-state work rather than treating every baseline item as still open.

## Validation and reporting notes

1. Resolved current upstream master through GitHub and compared the full hash to the prior baseline.
2. Downloaded only pinned public firmware source into scratch. Matched both baseline firmware source SHA-256 hashes.
3. Inspected handler registrations, actual C JSON generation, board/family constants, thermal sentinels, settings validators, hostname application, and live diff code. Compared these with native screen/model/store source and existing documentation.
4. Inspected `JSONValue.stringValue` before finalizing a preliminary numeric-difficulty concern. **Retraction:** numeric `bestDiff` is already stringified by that accessor, including integer/unsigned integer cases. It is not a confirmed missing-difficulty bug. The preliminary concern was explicitly corrected to the root and is not in the backlog above.
5. Capability work is concurrent. New core/store/view/test files were observed, but this audit did not claim they compile or that acceptance checks passed. Root owns final integration/test verification and can mark baseline gaps addressed.
6. All prioritized items include source evidence, a bounded improvement, model/firmware constraints and acceptance criteria. No acceptance tests were executed by this worker. No physical behavior or successful settings/OTA outcome is claimed.

**Recommended next delivery slice:** finish the explicit model-aware Info/ASIC screen and form evidence states, close ordinary-polling false-success/zero-data behavior, then add read-only fault/paused/active-pool summaries. Defer specialist controls and firmware workflows until these correctness and clarity gaps are verified.
