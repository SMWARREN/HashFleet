# Simple vs. Expert Mode & Progressive Disclosure UX Analysis for HashFleet

**Document Path**: `docs/research/simple-expert-comparison.md`  
**Date**: 2026-09-07  
**Scope**: Bounded UX/Product research comparing progressive disclosure vs. Simple/Expert mode for HashFleet, benchmarking against AxeOS and competing fleet tools.

---

## Coordinator review boundary

This is a design recommendation, not a live competitor usability test. The Fleet Manager feature document was independently fetched and supports its documented scanner, expandable cards, density modes and guarded restart descriptions. Other detailed competitor statements require source/code verification before adoption. Do not infer hardware-safe temperatures, voltages, stock presets or support for arbitrary SHA-256 coins from this comparison. No generic "safe" or automatic overclock profiles are approved for HashFleet. Only exact manufacturer/firmware-verified profiles could be considered, still through existing explicit review. Prefer the implemented card-local disclosure while evaluating whether an additional display-density setting is useful.

## 1. Executive Summary & Core Recommendation

HashFleet manages local-network Bitcoin/SHA-256 micro-miners (Bitaxe, NerdQAxe, and AxeOS-compatible hardware). The user base spans novice hobbyists trying solo mining for the first time to experienced multi-device operators tuning frequency (MHz) and core voltage (mV).

### Core Recommendation: Progressive Disclosure with Card-Local Depth (Reject Global Simple/Expert Toggle)
We recommend **context-sensitive progressive disclosure** across cards rather than a global binary "Simple vs. Expert Mode" switch.

**Why a Global Simple/Expert Toggle Fails for Fleets:**
1. **The Mode Trap & Hidden Faults**: Global simple modes routinely hide critical secondary indicators (such as voltage regulator/VR temperatures or rising hardware error rates) to look "clean". When hardware runs hot or silent faults occur, novices operating in simple mode remain uninformed until physical thermal shutdown or degradation occurs.
2. **Action Fragmentation**: Even beginners need access to essential "advanced" operations—such as rebooting an unresponsive unit, switching pool stratum addresses, or adjusting fan speed—but need them presented safely with plain-English guardrails rather than hidden behind an intimidating mode switch.
3. **Hardware Heterogeneity**: Bitaxe revisions (BM1366 Ultra, BM1368 Supra, BM1370 Gamma) and NerdQAxe units have differing voltage limits, register definitions, and auto-fan capabilities. A global simple/expert toggle treats the entire fleet with a broad brush instead of respecting per-device capabilities.

**Proposed Solution**:
- **Default State (Scannable Cards)**: Clean visual hierarchy with "easy buttons" (reviewed Restart and firmware-supported Identify/Locate) and primary metrics (Hashrate, Health badge, Freshness).
- **Expandable Depth (Card-Local)**: Inline chevron disclosing VR/ASIC thermal splits, power/efficiency (J/TH), and stratum rejected-share percentages.
- **Deep Inspection (Detail View)**: Full parameter tuning, register diagnostics, and live device logs, protected by strict confirmation sheets and sanity bounds.

---

## 2. Competitive Landscape & Primary Source Analysis

### A. AxeOS (Native ESP-Miner Web UI)
- **Primary Source**: [AxeOS / ESP-Miner GitHub Repository](https://github.com/bit-axe/ESP-Miner) & [OpenAPI Contract](https://github.com/bit-axe/ESP-Miner/blob/master/docs/openapi.yaml).
- **Observed Behavior**:
  - Direct embedded web server running on the ESP32-S3 microcontroller.
  - Presents monolithic tabbed forms (`System`, `Network`, `Stratum`, `Hardware`).
  - Configuration changes require submitting a JSON `PATCH` to `/api/system`, modifying non-volatile storage (NVS), and executing a device reboot (`/api/system/restart`).
- **Strengths**: Direct, low-latency register/parameter control; zero abstraction layer; immediate visibility into raw JSON responses.
- **Shortcomings for Beginners**: Overwhelming cognitive load. Users are immediately confronted with raw frequency (MHz), core voltage (mV), stratum difficulty, and extranonce flags without safety guardrails. An accidental misconfiguration can crash the miner or overheat the board.

### B. AxeOS Fleet Manager (Chrome Extension)
- **Primary Sources**:
  - [AxeOS Fleet Manager Repository](https://github.com/TheFabione/AxeOS-Fleet-Manager)
  - [Official Feature Specifications](https://raw.githubusercontent.com/TheFabione/AxeOS-Fleet-Manager/main/FEATURES.md)
- **Observed Behavior**:
  - Browser extension communicating with miners over the local subnet.
  - Implements a 3-tier card view toggle: **Minimal**, **Balanced**, and **Detailed** (Detailed includes hashrate sparkline).
  - Multi-coin pool manager supporting 16 SHA-256 coins, automatic worker name appending (`.devicename`), and watchdog automations (auto-reboot on 0 GH/s or overheat).
- **Marketed vs. Actual Implementation**:
  - *Marketed*: Seamless browser-based fleet dashboard with real-time logs and writes.
  - *Observed Reality*: Browser CORS and CSRF protections require tab injection into the device's web UI to obtain session cookies and execute cross-origin `fetch` calls.
- **UX Insights for HashFleet**:
  - Minimal/Balanced/Detailed density modes help scale views from 3 to 30 miners.
  - However, tuning remains modal and raw; it lacks beginner presets or guided optimization.

### C. Bitaxe Baller (Desktop & LAN Dashboard)
- **Primary Sources**:
  - [Bitaxe Baller Repository](https://github.com/465media/bitaxe-baller)
  - [Bitaxe Baller Documentation & README](https://raw.githubusercontent.com/465media/bitaxe-baller/main/README.md)
- **Observed Behavior**:
  - 2-tier architecture: **Scannable Home (`/`)** and **Device Detail (`/device/<ip>`)**.
  - **Health Borders**: Dynamic card borders colored by the highest-severity diagnostic (green = optimal/tunable, yellow = warning, red = critical, such as VR temp ≥ 65°C or HW error rate > 0.5%).
  - **Preset-Driven Tuning**: Rather than raw numeric inputs, it offers stepped presets: **Stock, Mild OC, Balanced, Aggressive, Max**.
  - **Automated Recommendations**: Rule-based engine analyzing rolling averages (e.g., *"VR temp ≥ 65°C → Drop core voltage 15 mV"*).
  - **Server-Enforced Guardrails**: Refuses writes outside strict bounds (400–900 MHz, 1000–1300 mV).
- **Strengths**: Superb beginner ergonomics; clear distinction between ASIC temperature and VR temperature (crucial for hardware longevity); presets eliminate raw-input guesswork.
- **Shortcomings**: Navigation friction; adjusting routine settings requires leaving the fleet overview and navigating into a full detail page.

---

## 3. Comparison Matrix

| Dimension | AxeOS Native UI | AxeOS Fleet Manager | Bitaxe Baller | HashFleet Proposed Synthesis |
| :--- | :--- | :--- | :--- | :--- |
| **UX Model** | Monolithic tabs | 3 Card Density Toggles | 2-Tier: Home + Detail Page | **Progressive Card Disclosure + Detail Sheet** |
| **Beginner Ergonomics** | Low (Raw inputs only) | Medium (Card view modes; raw forms) | High (Named presets + Recommendation Engine) | **High (One-click presets, plain status, guided wizards)** |
| **Expert Capabilities** | Full (Direct API/NVRAM) | High (Manual MHz/mV, watchdogs, bulk pool) | High (Step tuning, raw metrics, CSV export) | **Full (Diagnostic views, raw register catalog, live logs)** |
| **Thermal Monitoring** | Raw ASIC temp | ASIC temp on card | Explicit ASIC & VR temp with severity borders | **Dual ASIC/VR split, thermal badges, throttle warnings** |
| **Data Freshness** | Direct connection | 15s polling status | 5s polling with 3-minute settling window | **Explicit relative freshness ("4s ago") + stale visual state** |
| **Write Protection** | Manual restart prompt | Tab-injected fetch | Warning banner + clamp bounds | **Two-stage confirmation sheet + diff review (no silent writes)** |

---

## 4. UI/UX Specification: Progressive Disclosure for HashFleet

### Level 0: Default Card View (Scannable & Accessible)
- **Header**: Miner user-assigned nickname, hardware model badge (e.g., `Gamma 601`), IP address.
- **Primary Metric**: Live Hashrate (e.g., `1.22 TH/s`) with color-coded operational dot (Green: Mining, Amber: Warning/Throttled, Red: Fault/Offline).
- **Freshness Pill**: Explicit indicator (`Updated 3s ago`; turns amber/gray if refresh misses a polling cycle).
- **Essential Actions ("Easy Buttons")**:
  - `Profiles` (future, conditional): only independently verified manufacturer/firmware profiles, never generic safe/overclock promises; all changes remain reviewed.
  - `Restart`: Prompts confirmation sheet before rebooting.
  - `Locate`: Flashes onboard RGB LED to physically identify the miner.
- **Disclosure Control**: Expand chevron ("Show Details") for inline Level 1 data.

### Level 1: Inline Card Expansion (Intermediate Telemetry)
- **Thermal Breakdown**: Separate gauges for **ASIC Temp** and **VR (Voltage Regulator) Temp** with warning thresholds (>65°C ASIC, >70°C VR).
- **Efficiency & Power**: Current power draw in Watts (W) and efficiency in Joules per Terahash (J/TH).
- **Pool Status**: Active pool domain, share count, and hardware error rate percentage (<0.1% normal, >0.5% alert).
- **Link**: Direct button to "Full Diagnostics & Settings" (Level 2).

### Level 2: Full Miner Detail & Advanced Form (`MinerDetailView` / `MinerSettingsView`)
- Granular frequency (MHz) and voltage (mV) sliders with visual safety zones.
- Stratum fallback configuration (primary and secondary failover pools).
- Raw endpoint catalog, live WebSocket logs, and JSON response inspector.

---

## 5. Non-Negotiable Safety, Freshness, and Confirmation Safeguards

1. **Uncompromised Fault & Freshness Visibility**:
   - Telemetry must never hide faults behind an "All Good" simplification. If hardware error rate exceeds 0.5% or VR temperature exceeds safe limits, the card must show a prominent warning badge regardless of whether it is collapsed or expanded.
   - If a miner stops responding, the card must not display frozen stale numbers as active; it must immediately reflect stale status (`Offline / Stale since 12:44:02`).
2. **Mandatory Explicit Write Confirmations**:
   - No setting change, preset application, or restart command may execute silently.
   - Any write action must trigger a native sheet displaying:
     - Target miner name and IP.
     - Parameter diff (`Frequency: 500 MHz → 525 MHz`, `Voltage: 1150 mV → 1160 mV`).
     - Plain-language risk acknowledgement for overclocking settings.
3. **Card-Local Accessibility**:
   - Beginners should not have to hunt through complex multi-page settings hierarchies to perform standard maintenance. Essential actions must be accessible right from the overview card.

---

## 6. Prioritized Implementation Roadmap

1. **Priority 1: Card-Local Quick Actions & Safety Presets**
   - Add a lightweight action bar to `MinerOverviewCard` with `Presets` (Stock, Eco, Balanced) and `Restart`.
   - Wire all preset selections directly into the existing `MinerTuningDraft` validation and review sheet.
2. **Priority 2: Dual Thermal & Health Reporting on Overview Cards**
   - Incorporate explicit **VR Temp** alongside **ASIC Temp** on overview cards, mirroring Bitaxe Baller's proven prevention model against board burnout.
3. **Priority 3: Stale Telemetry & Fault Indication**
   - Standardize relative freshness timers and ensure uncontacted devices show clear visual decay rather than stale 0 GH/s readings.
4. **Priority 4: Guided Stratum Pool Wizard**
   - Provide safe, pre-formatted templates for prominent pools (CKPool Solo, Braiins, Public-Pool) to prevent invalid stratum URL syntax and worker configuration errors.
