> Coordinator reconciliation: this is a source-inspection audit, not a runtime test report. Automatic capability detection already performs the Info/ASIC read-only check after recognized polling, with a manual retry available. The on-demand-only wording below is historical. A hardcoded 70°C thermal recommendation was not adopted because temperature thresholds are device/firmware dependent. Shared exact difficulty formatting was integrated. Ticker lifecycle/precision and setup navigation issues found during integration were repaired. A later native check exposed DisclosureGroup identifier inheritance in expanded pool content. That header is now an independent button, with regression checks for its unique identifier and the separate edit link. See the compact acceptance matrix for runtime status. Line numbers below are from the worker observation and can drift.

# Independent Review: Compact Redesign and Miner Tuning Safety

This audit reviews HashFleet's miner tuning controls, safeguards, unsupported firmware behaviors, pool review paths, and the compact UI redesign.

---

## 1. Frequency & Voltage Overclock Controls and Safeguards

### 1.1 Do Overclock Controls Exist?
Yes. Manual controls for frequency and core voltage are implemented in `MinerTuningSection.swift:42-57` and backed by `MinerTuningDraft.swift:8-37`.
* **Frequency:** Decimal or integer input in MHz, serialized to `{"frequency": <Double>}`.
* **Core Voltage:** Integer input in mV, serialized to `{"coreVoltage": <Int64>}`.
* **No Automated Presets:** There are no automatic overclock profiles or one-click boost toggles. Changes start from configured values reported by telemetry, never measured readings (`MinerTuningDraft.swift:14-23`).

### 1.2 Safeguards in Place
1. **Explicit Multi-Step Confirmation Gate:**
   * In-view toggle required: `"I understand the hardware and overheating risks"` (`MinerTuningSection.swift:67-79`).
   * Modal pre-flight JSON review in `MinerWriteConfirmation` (`MinerEndpointCatalogView.swift:149-195`).
   * Explicit typing of literal `APPLY` required to transmit (`MinerEndpointCatalogView.swift:179-185`).
   * Any edit to the draft immediately revokes acknowledgment (`MinerTuningSection.swift:85`).
2. **Strict Wire Input Bounds Validation:**
   * Frequency must match `^[0-9]+(?:\.[0-9]+)?$` within `1...65535` MHz (`MinerTuningDraft.swift:39-48`).
   * Voltage requires whole integers within `1...65535` mV (`MinerTuningDraft.swift:52-56, 132-140`).
   * Copy explicitly notes: *"The app checks encoding bounds, not a hardware-safe voltage range"* (`MinerTuningSection.swift:55-56`).
3. **Sparse Serialization (Zero Side-Effects):**
   * Only checked fields (`includeFrequency`, `includeCoreVoltage`) are serialized. Unselected fields are omitted from JSON, preventing accidental alteration of thermal limits (`MinerTuningDraft.swift:27-36`).
4. **Credential Redaction:**
   * Passwords and Wi-Fi keys are redacted as `•••••• (will be sent)` in review inspection (`MinerEndpointCatalogView.swift:95-110`).
5. **Full-Slot Replacement Safeguard:**
   * Pool slot writes via PUT `/api/system/pools/{slot}` enforce an explicit replacement acknowledgment toggle (`poolReplacementAcknowledged`), warning that omitted advanced fields revert to firmware defaults (`MinerTuningPoolDraft.swift:15-20`, `MinerSettingsView.swift:361-375`).

### 1.3 Unsupported and Unknown Behavior
* **Device Reference Probing (`GET /api/system/asic`):** Automatically checked once after recognized Info, with explicit manual retry. If unsupported or unread, the UI states: *"The last compatibility check found that this firmware does not serve the ASIC read... Manual entry above still works"* (`MinerTuningSection.swift:114-117`). References are treated as unverified vendor lists, not safe ranges (`:142-144`).
* **Absence vs Zero Differentiation:** Unreported telemetry fields remain `nil` and render `"Not reported"` or `"N/A"`, never coerced to 0 (`MinerDetailView.swift:90-95`, `FleetReadingCaption.swift:388-422`).
* **Demo Isolation:** In Demo mode, all network calls, mutations, and WebSockets are hard-blocked locally (`MinerSafetyTests.swift:74-96`).

---

## 2. Review of Compact Redesign

### 2.1 Navigation & Workspace Layout
* **Dashboard:** Compact hero and metric cards; `FleetStatusTicker` provides cycling miner summaries with accessible static layout for VoiceOver and Reduce Motion (`FleetStatusTicker.swift:85-96`). `FleetHistoryCard` is nested in an expandable disclosure group.
* **Direct Workspace Routes:** `MinerDetailView.swift:246-253` (`quickControls`) provides 1-tap navigation into Tuning, Cooling, and Pools. These navigate to the forms and do **not** bypass risk acknowledgment, JSON review, or the `APPLY` gate.
* **Scoped Pools:** `FleetPoolsCard.swift:3-35` supports `deviceID: UUID?`. When viewed inside `MinerDetailView`, queries are scoped strictly to that miner, preventing address disclosure across units.

### 2.2 Freshness, Disclosures, and Privacy
* **Privacy in Ticker:** `FleetStatusTickerModel.swift:100-107` confirms device addresses, hostnames, pool URLs, and credentials never reach ticker summaries.
* **Freshness Separation:** `FleetChainCard.swift:60-76, 107-120` separates difficulty freshness from market price freshness, tagging stale quotes clearly.
* **Rounding vs Truncation:** `MiningDifficultyFormat.swift` uses exact `Decimal` scaling across SI thresholds (K, M, G, T, P, E) with 3 significant digits, avoiding integer truncation or floating-point artifacts.

### 2.3 Coin Guardrails & Profitability
* **No False Profitability:** Explicit disclaimer that coin price is not mining profitability (`MiningSetupCatalog.swift:134-152`). Prices are only fetched for BTC and BCH; unverified chains report price unavailable.
* **ASIC Coin Compatibility:** Restricted strictly to SHA-256d (`MiningSetupCatalog.swift:51-104`). Model matching against known chips (`BM1370`, `BM1366`, `BM1397`, `BM1368`, `BM1362`, `BM1387`); unknown models remain unverified. Presets clear address drafts when changed to prevent cross-chain errors.

---

## 3. Max 3 Worthwhile Small Features

1. **Compact Thermal Warning on MinerOverviewCard:**
   * *Rationale:* Compact card mode hides metric rows. A compact badge (e.g. `72°C`) when chip temperature $\ge 70^\circ\text{C}$ flags high thermal readings without expanding the card.
   * *Acceptance:* Only displays when finite `temp` is reported; never shows on missing readings; does not displace address or status badge.
2. **Adopt MiningDifficultyFormat in FleetStatusTickerModel:**
   * *Rationale:* Wire `MiningDifficultyFormat.format(json:)` into `FleetStatusTickerModel.bestShareFormatter` to eliminate duplicate difficulty formatting logic.
   * *Acceptance:* Strings (e.g. `18.4G`) pass through; numbers format using exact Decimal SI scaling; malformed values return nil.
3. **Tuning Draft Delta Pill:**
   * *Rationale:* Display an informative indicator (`(Matches active)` or `(Delta: +X MHz)`) when draft differs from reported active frequency.
   * *Acceptance:* Read-only display; compares strictly to reported telemetry; typing clears risk acknowledgment.

---

## 4. Concrete Audit References

| Component | File & Line | Finding & Verification |
| :--- | :--- | :--- |
| **Overclock Controls** | `MinerTuningSection.swift:42-57`<br>`MinerTuningDraft.swift:25-37` | Frequency & voltage manual inputs exist. Sparse payload serialization only includes selected fields. |
| **Tuning Safeguards** | `MinerTuningSection.swift:67-79`<br>`MinerEndpointCatalogView.swift:162-186` | Dual-barrier gate: in-view risk acknowledgment toggle + modal pre-flight review + literal `APPLY` confirmation token. |
| **Unknown ASICs** | `MinerTuningSection.swift:160-162`<br>`MiningSetupCatalog.swift:94-104` | Automatic read-only detection and manual retry. Missing or unverified models stay unverified; manual entry remains available. |
| **Slot Replacement** | `MinerSettingsView.swift:361-375`<br>`MinerTuningPoolDraft.swift:15-20` | Full-slot replacement acknowledgment toggle prevents accidental erasure of omitted advanced fields. |
| **Scoped Pools** | `FleetPoolsCard.swift:3-35`<br>`MinerDetailView.swift:219-241` | `FleetPoolsCard` scoped by `deviceID` ensures viewing one miner never resolves or queries another miner's payout address. |
| **SI Formatting** | `MiningDifficultyFormat.swift:7-59`<br>`FleetTheme.swift:107-115` | Difficulty uses exact Decimal comparison and SI formatting. Hashrate uses formatted floating-point readings rather than raw integer casts. |
| **Coin Guardrails** | `MiningSetupCatalog.swift:51-104`<br>`MiningInsightsMath.swift:22-54` | Strict SHA-256d restriction. Freshness separation on price quotes. Disclaimers confirm price does not equal mining yield. |
