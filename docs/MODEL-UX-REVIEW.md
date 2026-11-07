# Model-aware UX and safety review

Scope: existing miner detail, settings, tuning, endpoint explorer, and endpoint detail screens, reviewed against `docs/CAPABILITY-CONTRACT.md`. Findings are ordered by user impact and implementation priority. This review intentionally does not modify app code.

## Findings

### 1. P2: Advanced operations need clearer expert-tool framing without removing requested endpoints

- **Evidence:** `App/Features/Miner/MinerSettingsView.swift:193-200` places `Scan Wi-Fi networks`, raw ASIC access, and both OTA operations under Advanced tools. `App/Features/Miner/MinerEndpointCatalogView.swift:17-24` lists every catalog operation, including writes and firmware operations, as directly navigable.
- **Risk:** This is not an unauthorized feature boundary: the user requested access to all endpoints, and the contract's Info/ASIC-only restriction applies to agent physical verification. The UX risk is instead that broad expert operations can look like ordinary diagnostics, especially before a model-aware compatibility result is available.
- **Action for root:** Preserve the complete endpoint explorer and manually gated Advanced tools. Add a concise expert-tools label and per-operation risk/capability status, with `MinerCompatibilityView` as the friendly identity and compatibility entry point rather than a gate that removes functionality. Keep the existing review/APPLY confirmation and make clear that catalog listing is not support validation.

### 2. P2: Endpoint errors could explain uncertainty more usefully

- **Evidence:** `App/Features/Miner/MinerEndpointView.swift:7-12` starts every operation at `Unverified on this firmware`; `:38-60` changes any thrown error to `Request failed. Support is not confirmed`. The catalog uses `Support: unverified on this firmware` at `App/Features/Miner/MinerEndpointCatalogView.swift:44-53`.
- **Risk:** The current wording is honest uncertainty, not a false unsupported claim. However, transport failure, authentication failure, throttling, HTTP 500, malformed data, and a genuine 404/405/501 still lead to nearly identical user-facing uncertainty, making the next action less clear.
- **Action for root:** Keep the uncertainty semantics, but use typed error/status presentation where available: distinguish `Not checked`, `Failed to check`, and `Unsupported` only for the contract's 404/405/501 cases. Add a friendly retry/recheck action and a last-checked timestamp. Do not derive support from a successful arbitrary endpoint call, and do not block expert tools solely because compatibility is unverified.

### 3. P1: Detail can show old telemetry as current and does not distinguish telemetry freshness from compatibility freshness

- **Evidence:** `App/Features/Miner/MinerDetailView.swift:51` labels the device `CONNECTED` when `snapshot?.error == nil && info != nil`; `:68-75` labels the value `LATEST HASHRATE`; `:55-60` only shows relative `Last sample` age. `FleetStore.swift:122-130` retains the previous `snapshot.info` when a later refresh fails.
- **Risk:** After suspension, a delayed poll, or a failed refresh that has not yet surfaced, stale values can look live. A user may use those values to judge cooling or tuning while the compatibility report is independently older or absent.
- **Action for root:** Add an explicit freshness policy and stale badge based on `updatedAt`, with copy such as “Last reported” once outside the threshold. Keep connection status separate from telemetry status, and show compatibility status plus its own `checkedAt` on the detail screen. Never let a stale sample imply a live device or current support.

### 4. P1: Settings and dangerous controls are available from telemetry alone, not a successful current capability report

- **Evidence:** `App/Features/Miner/MinerSettingsView.swift:38-40` derives all settings state from `store.snapshots[device.id]?.info`; `:47-55` renders General, Cooling, Display, Pools, Manual tuning, and Advanced tools unconditionally; `:178-182` passes only `info` into tuning. Cooling text hard-codes audited input bounds at `:206-224`, while tuning validation uses encoding bounds in `App/Features/Miner/MinerTuningDraft.swift:25-45`.
- **Risk:** An unknown model, missing field, stale snapshot, or custom firmware can still receive controls and apparently valid defaults. The warnings correctly say bounds are not safe ranges, but the affordance itself implies the setting exists and is supported.
- **Action for root:** Pass the capability report into settings and only enable/show a native control when the current report successfully returned the relevant raw field/options. For missing fields use `Not reported` plus “Check compatibility,” not an inferred default or generic control. Keep advanced JSON as the escape hatch, but label it as unverified and never treat wire bounds as model support or safety limits.

### 5. P1: ASIC references can become stale and are visually close to actionable defaults

- **Evidence:** `App/Features/Miner/MinerTuningSection.swift:72-88` performs its own GET `/api/system/asic` and stores a local `reference` without a timestamp or probe status; `:101-112` presents `Reported default frequency` and `Reported default core voltage` beside options. The warning says these are not safe recommendations, but does not identify when they were read or whether the response was partial.
- **Risk:** A user can mistake firmware-reported defaults/options for a safe combination, or use references from an earlier firmware/device state. This duplicates the planned capability probe and makes stale-vs-live information hard to understand.
- **Action for root:** Source ASIC identity/options from the shared capability report, show `checkedAt` and a clear `Not reported`/`Failed` state, and invalidate or replace the whole report on every manual check. Keep defaults/options read-only references, visibly label them “firmware-reported reference, not a recommendation,” and never populate or validate tuning drafts as safe from them.

## Positive safeguards to preserve

- The existing separate review/APPLY confirmation and demo write lock in `MinerEndpointView.swift:115-145` and `:241-245` are good safety boundaries.
- The tuning warning and risk acknowledgement in `MinerTuningSection.swift:20-24` and `:53-66`, and the full-slot replacement acknowledgement in `MinerSettingsView.swift:278-289`, should remain after capability-aware gating is added.
