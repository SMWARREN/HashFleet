# Fleet Journal Architecture & Design Specification

**Document Version:** 1.1

**Date:** 2026-10-06

**Target System:** `hashfleet` (iOS / macOS / iPadOS)

**Status:** Architecture Audit & Design Specification

---

## 1. Executive Summary & Design Goals

The **Fleet Journal** (`FleetJournalView`) is a planned primary workspace in `hashfleet` designed to provide a rich, visually dynamic chronological timeline of fleet activity, miner health, performance trends, and milestone achievements.

Rather than showing only real-time instantaneous gauge readings, the Fleet Journal contextualizes historical events per miner and across the whole fleet. It combines stored SQLite telemetry, persisted event observations, durable notification inbox records, and live snapshots into a unified presentation.

### Core Principles
1. **Zero Synthetic / Invented Telemetry:** All charts, events, and metrics are derived strictly from recorded data (`MinerTelemetryDatabase`, `UserDefaults` observations, and live `MinerSnapshot` objects). Downtime and app-closed unpolled intervals are presented as honest gaps.
2. **Desktop Column Balance:** The proposed Mac journal uses `FleetBalancedColumnsLayout` with at most two columns and full-width unpaired final sections. The current `FleetSectionGrid` keeps iPhone and iPad sections stacked. A future wide-iPad journal can opt into the same balanced engine explicitly.
3. **Strict Privacy Boundaries:** No private keys, wallet addresses, pool passwords, Wi-Fi credentials, or tokens are logged, displayed, or persisted in journal views.
4. **Firmware-Reported Retained Records vs Locally Observed Events:** Timeline events explicitly distinguish firmware-reported retained records, reconciled with locally observed events, from periodic app polling estimates and external third-party pool metrics. They do not imply block network confirmation, independent hardware truth, or pool acceptance from these endpoints alone.

---

## 2. Telemetry Architecture & Verified Code Paths

To ensure technical accuracy, every claim in this specification is verified against actual call sites in the repository rather than assumed from database schema declarations.

| Component / Layer | Verified Repository Path | Actual Implemented Behavior & Call Sites |
| :--- | :--- | :--- |
| **Database Core** | `Sources/HashFleetCore/Database/MinerTelemetryDatabase.swift` | GRDB SQLite instance (`miner_telemetry.db` in `Application Support`). Schema defines `miner_readings`, `achievement_events`, `connectivity_events`, and `pool_switches`. Thread-safe batch queueing (`batchSize = 10`). |
| **Telemetry Ingestion** | `App/Store/FleetStore+Evaluation.swift:295` | `recordReading` is called during live evaluation when fresh `MinerInfo` arrives while the app is active in foreground or during background refresh. |
| **Scoreboard Import** | `App/Store/FleetStore+Monitoring.swift:75`<br>`Sources/HashFleetCore/Database/MinerTelemetryDatabase+Achievements.swift:182` | Firmware-reported retained scoreboard records are imported from `/api/system/scoreboard` via `reconcileScoreboard`. Authoritative only within the firmware's own retained scoreboard, subject to device resets, retention limits, and firmware updates. Does not imply independent hardware truth, network confirmation, or pool acceptance. Devices exposing this endpoint populate `scoreboardSupportedDeviceIDs`. |
| **Polling Achievement Fallback** | `App/Store/FleetStore+Evaluation.swift:152` | `recordPollingBestShareAchievement` is called ONLY when a device has not confirmed scoreboard support. Once scoreboard support is confirmed, polling writes are skipped to prevent duplicate rounded rows. |
| **Connectivity Event Ingestion** | `App/Store/FleetStore+Evaluation.swift:252, 270` | `recordConnectivityEvent` is called ONLY for `"disconnect"` and `"error"`. **No call site exists in the app for `"online"`**. |
| **Pool Switch Persistence** | `Sources/HashFleetCore/Database/MinerTelemetryDatabase+Connectivity.swift:32` | `recordPoolSwitch` is declared in HashFleetCore but has **zero call sites** in the app. Pool switches are currently not persisted to SQLite. |
| **Telemetry Pruning** | `Sources/HashFleetCore/Database/MinerTelemetryDatabase+Maintenance.swift:8`<br>`App/HashFleetApp.swift:221` | `pruneOldReadings(olderThan:)` deletes rows from `miner_readings`, `connectivity_events`, and `pool_switches` older than retention days, then runs `VACUUM`. It **preserves `achievement_events`**. |
| **Destructive User Reset** | `App/Store/FleetStore+Persistence.swift:161`<br>`Sources/HashFleetCore/Database/MinerTelemetryDatabase+Maintenance.swift:49` | `clearAllTelemetryAndAchievements()` deletes ALL tables in SQLite (`miner_readings`, `achievement_events`, `connectivity_events`, `pool_switches`), vacuums SQLite, resets `UserDefaults` achievement baselines, and removes block/share items from `notificationInbox`. |
| **Session In-Memory Series** | `App/Store/FleetStore+Evaluation.swift:36`<br>`App/Features/Dashboard/FleetHistoryCard.swift:218` | In-memory `snapshot.history` holds a ring buffer of up to 360 points per miner. Used for the `.daily` chart window. Resets when the app process exits. |
| **Durable Notification Inbox** | `App/Store/FleetStore+Persistence.swift:187`<br>`App/Store/FleetNotificationDelivery.swift` | Holds up to 100 `FleetNotificationInboxEntry` records in `UserDefaults` (`app.hashfleet.notification-inbox.v1`) retained for 14 days. Stores state changes, temperature warnings, power alerts, and metric alerts. |
| **Desktop Layout Engine** | `App/Design/FleetBalancedColumnsLayout.swift`<br>`App/Design/FleetAdaptiveLayout.swift` | `FleetBalancedColumnsLayout` and `FleetSectionGrid` enforce a maximum of two columns on desktop. `FleetBalancedRowGeometry` automatically allocates full width (`cellWidth = width`) to any unpaired trailing section. |

---

## 3. Data Storage & Lifecycle Realities

### 3.1 Actual SQLite Database Location & Name
- Database filename: `miner_telemetry.db`
- Storage path: `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, ...).appendingPathComponent("miner_telemetry.db")`
- Initialized by `MinerTelemetryDatabase.shared` using GRDB `DatabaseQueue`.

### 3.2 App-Active Recording vs Continuous Background History
- The `hashfleet` application **does not** run a background daemon, continuous logging agent, or remote collector.
- `miner_readings` are accumulated only when telemetry storage is enabled and the running app actually receives fresh miner data through its permitted polling or WebSocket sessions. Schema fields are nullable, and a field's existence is not proof that every firmware/provider supplies it.
- The app does not guarantee collection while suspended, closed, or terminated. Brief OS-permitted refresh work is not a continuous recorder.
- Gaps between observed readings are collection gaps, not proof that a miner stopped hashing. Render them as breaks in the chart line rather than interpolating or labeling an unobserved interval as a hardware outage.

### 3.3 External M1 Recorder Integration
- **Status: Non-existent in `hashfleet`.**
- While external operational hosts (such as an M1 Mac running `axestallwatch`) may exist in physical fleet environments, `hashfleet` contains no code, API endpoints, SSH transports, or database synchronization hooks for any external M1 recorder.
- All telemetry in `hashfleet` is polled or received directly by the native app from the miners on the local network.

### 3.4 Persistent Storage vs Ephemeral 360-Point Memory Series
- **In-Memory 360 Series (`snapshot.history`):**
  - Retains at most 360 samples per miner in memory (`snapshot.history = Array(snapshot.history.suffix(360))`).
  - Used by `FleetHistoryCard` for the current-session `.daily` chart view.
  - Completely erased when the app terminates or when demo mode is toggled.
- **Persistent SQLite Series (`miner_readings`):**
  - Stored in SQLite up to the user-selected retention period. Configured default is 30 days (`FleetPreferences.defaultTelemetryRetention = .month`).
  - Supported options in `FleetPreferences.TelemetryRetention` are 7 days (`.week`), 30 days (`.month`), 90 days (`.quarter`), 365 days (`.year`), and Forever (`.forever = 36500` days / 100 years). Maximum configurable duration is 36,500 days.
  - Used by `FleetHistoryCard` when selecting non-daily windows (e.g. weekly or monthly).
  - Queried via `MinerTelemetryDatabase.shared.getHashrateReadings(minerId:since:)` and `getTemperatureReadings(minerId:since:)`.

### 3.5 Retention Pruning vs Destructive User Reset
It is critical to distinguish between scheduled maintenance pruning and the user-initiated destructive clear action:

1. **Automatic Retention Pruning (`pruneOldReadings`):**
   - Triggered on app launch or during background maintenance based on `FleetPreferences.TelemetryRetention` (default 30 days, maximum 36,500 days).
   - Deletes rows older than user-specified days from `miner_readings`, `connectivity_events`, and `pool_switches`.
   - **Does NOT delete `achievement_events`:** Historical block solves and best difficulty shares are deliberately preserved across retention cutoffs.
   - Does NOT touch `UserDefaults` baselines.
   - Durable notification inbox maintains its own independent retention of 14 days (`FleetStore.notificationInboxRetention`), capped at 100 entries (`FleetStore.notificationInboxLimit`).
2. **Destructive User Reset (`clearAllTelemetryAndAchievements`):**
   - Triggered only by explicit confirmation in Settings under "Clear all telemetry data".
   - Executes `DELETE FROM miner_readings`, `DELETE FROM achievement_events`, `DELETE FROM connectivity_events`, and `DELETE FROM pool_switches`.
   - Clears `pendingReadings` buffer and vacuums the SQLite file.
   - Clears `blockObservations` and `bestShareObservations` in `UserDefaults` so miners re-baseline cleanly without generating false alerts.
   - Purges `.blockFound` and `.bestShare` entries from `notificationInbox` so stale celebrations are not rehydrated.

---

## 4. Firmware-Reported Data vs Locally Observed Events vs Provider Data

The Fleet Journal must clearly distinguish between four distinct tiers of data authority:

1. **Firmware NVS Scoreboard (Firmware-Reported Retained Records):**
   - Sourced from `/api/system/scoreboard` on supported ESP-Miner hardware.
   - Persisted in miner non-volatile storage (NVS), subject to board resets, NVS clearing, and firmware revisions.
   - Contains firmware-reported decimal difficulty, block timestamp (`ntime`), and coin identifier.
   - Does NOT imply block network confirmation, independent hardware truth, or pool acceptance from this endpoint alone.
   - Reconciled with locally observed events into SQLite by `MinerTelemetryDatabase.shared.reconcileScoreboard`.
   - Badge in UI: `Firmware Scoreboard`.
2. **App-Detected Milestones (Fallback Local Observation):**
   - Sourced from polling `/api/system/info` when scoreboard endpoint is unsupported.
   - Stored via `recordPollingBestShareAchievement`.
   - Carries integer-rounded difficulties without ASIC job timestamps.
   - Badge in UI: `App Polled Record`.
3. **App State & Health Observations:**
   - Sourced from app-level connectivity monitoring (`stateObservations`, `notificationInbox`).
   - Reflects the native app's ability to reach the miner over the local network.
   - Badge in UI: `Fleet Monitor`.
4. **External Provider Data (Informational Public Data):**
   - Sourced via `MiningInsightsStore` from third-party public endpoints (SoloFury, CKPool, Mempool.space, Blockchair, CoinGecko).
   - Completely external to the miner hardware.
   - Never written to `miner_telemetry.db`.
   - Badge in UI: `External Pool / Network`.

---

## 5. Supported Today vs New Implementation Required

To prevent architectural drift and ungrounded assumptions, the capabilities are explicitly partitioned:

### 5.1 Fully Supported in Codebase Today
- Persistent telemetry storage in `miner_telemetry.db` (`miner_readings`).
- Querying historical hashrate and temperature points by date window (`getHashrateReadings`, `getTemperatureReadings`).
- Firmware-reported scoreboard reconciliation from `/api/system/scoreboard` (`reconcileScoreboard`).
- Durable, retention-exempt `achievement_events` with deduplication. They are still subject to explicit user deletion and supported reconciliation cleanup.
- Durable notification inbox (`notificationInbox`) retaining state changes, temperature alerts, power alerts, and metric alerts for 14 days.
- In-memory 360-sample session history in `snapshot.history`.
- Desktop layout engine `FleetBalancedColumnsLayout` (max 2 columns on Mac, full-width unpaired final rows).
- Telemetry retention pruning with achievement preservation.
- Full destructive user reset with baseline and notification purging.

### 5.2 Gaps & New Implementation Required
1. **Connectivity Ingestion Gap:**
   - `recordConnectivityEvent` is only called for `"disconnect"` and `"error"` in `FleetStore+Evaluation.swift`.
   - An explicit call for `eventType: "online"` must be added when a miner transitions from disconnected back to reachable.
2. **Pool Switch Persistence Gap:**
   - `recordPoolSwitch` is implemented in GRDB database layer but never called by `FleetStore`.
   - A caller in `FleetStore+Evaluation.swift` must detect changes in `info.pool` or `active_pool_index` and persist `recordPoolSwitch`.
3. **Journal View Layer:**
   - `FleetJournalView`, `FleetJournalSummaryCard`, `MinerJournalCard`, `MinerJournalTimelineView`, and `MinerJournalViewModel` do not yet exist and must be constructed.
4. **Unified Event Aggregator:**
   - A repository query that joins SQLite `achievement_events`, SQLite `connectivity_events`, and `notificationInbox` items into a single chronological feed for each miner.

---

## 6. Proposed Fleet Journal UI Design

The proposed Fleet Journal interface follows the strict desktop layout guidelines of `hashfleet`:

```
FleetJournalView
├── FleetJournalSummaryCard (Full Width Header, 30pt Desktop Padding)
│   ├── Fleet Health Counters (Online / Reconnecting / Offline)
│   ├── Live Fleet Totals (Hashrate, Power, Avg Temp)
│   ├── High-Score Milestone Spotlight
│   └── Event Type Filter (All | Milestones | Alerts | Connectivity)
│
└── FleetSectionGrid (FleetBalancedColumnsLayout: 2 cols on Mac, 1 on iOS)
    ├── MinerJournalCard (Workshop Gamma, demo example)
    │   ├── Header: Name, Model, IP, Status Pill
    │   ├── 24-Hour Hashrate & Temperature Micro-Charts (with honest offline gaps)
    │   └── Chronological Timeline Rows (Scoreboard shares, alerts, disconnects)
    │
    ├── MinerJournalCard (Office Gamma, demo example)
    │   ├── Header: Name, Model, IP, Status Pill
    │   ├── 24-Hour Hashrate & Temperature Micro-Charts
    │   └── Chronological Timeline Rows
    │
    └── MinerJournalCard (Little Supra, demo example) [Unpaired Final Card: Automatically Spans Full Width]
        ├── Header: Name, Model, IP, Status Pill
        ├── 24-Hour Hashrate & Temperature Micro-Charts
        └── Chronological Timeline Rows
```

### 6.1 Desktop Layout & Spanning Invariant
- Uses `FleetSectionGrid` wrapping `FleetBalancedColumnsLayout`.
- On a sufficiently wide Mac viewport, `columns = 2`. Narrow windows and accessibility text sizes fall back to one column. Wide iPad adoption is a separate explicit layout choice, not current behavior of `FleetSectionGrid`.
- `FleetBalancedRowGeometry` ensures that if there are an odd number of miner cards (e.g. 1, 3, or 5 miners in the fleet), the final unpaired card is assigned `cellWidth = width`, spanning across both columns so no empty half-row is left on screen.

### 6.2 Per-Miner Journal Card Anatomy
1. **Header Row:**
   - Display name (`MinerDevice.name`).
   - Hardware badge (Gamma 601a, Gamma 602, Naja Duo, XMRig).
   - Redacted host or mDNS endpoint (`192.168.86.xxx` or `.local`).
   - Connection status pill (`Online`, `Reconnecting`, `Offline`).
2. **Micro-Trend Sparkline (`MinerJournalTrendChart`):**
   - Dual compact line charts for Hashrate and Temperature.
   - Hashrate and temperature are queried separately through `getHashrateReadings` and `getTemperatureReadings`, with missing values preserved as unavailable.
   - Split series using a documented threshold based on the actual recording cadence. A gap represents missing observations. Only an explicitly recorded connectivity event may annotate the app's inability to reach a miner.
3. **Timeline Event Feed (`MinerJournalTimelineView`):**
   - Merged chronological list of verified events:
     - **Reported Block Candidate:** Gold trophy symbol, reported block height when present, coin label and explicit provenance. Do not label a firmware report as a network-confirmed block.
     - **Best Share:** Purple star symbol, formatted difficulty, `Firmware Scoreboard` badge.
     - **Disconnect:** Red warning symbol, outage timestamp, error detail.
     - **Metric Alert:** Orange caution symbol, drop/spike percentage from `MinerMetricAlertEvent`.

---

## 7. Privacy, Sanitization & Data Safety

1. **Sensitive Data Boundary:**
   - Journal queries and view models must allowlist display-safe fields. Never pass wallet addresses, pool passwords, Wi-Fi keys, tokens, or SSH credentials to the journal UI.
   - Do not assume existing free-form database metadata, pool strings, or error messages are sanitized. Validate and redact these at the presentation boundary, including when ingesting older records.
2. **Pool URL Sanitization:**
   - Any pool URL shown in timeline rows is stripped of username, worker name, and password parameters, displaying only hostname and port (e.g. `stratum.ckpool.org:3333`).
3. **Local-Only Execution:**
   - All journal aggregation runs entirely on-device using local SQLite and local `UserDefaults`. No analytics or cloud telemetry endpoints are contacted.

---

## 8. Verification & Test Plan

When implementing the Fleet Journal, validation must cover both data aggregation correctness and desktop layout geometry:

1. **Layout Tests (`AppTests/FleetBalancedColumnsLayoutTests.swift`):**
   - Verified that odd item counts (1, 3, 5, 7) assign full container width to the final item (`frames.last?.width == width`).
   - Verified that even item counts (2, 4, 6) allocate equal half-widths (`width == pairedWidth`).
2. **Planned Event Merging Tests (`AppTests/FleetJournalTests.swift`, not yet implemented):**
   - Verify merging of SQLite `AchievementEvent`, SQLite `ConnectivityEvent`, and `UserDefaults` `FleetNotificationInboxEntry`.
   - Verify descending chronological sort order across heterogenous event types.
3. **Gap Integrity Tests:**
   - Verify that periods of app closure or miner disconnect produce split line marks rather than false linear connections.
4. **Destructive Reset Isolation:**
   - Verify that running `clearAllTelemetryAndAchievements()` leaves the journal view in a valid empty state without rehydrating deleted achievements.

---

*End of Architecture Specification.*
