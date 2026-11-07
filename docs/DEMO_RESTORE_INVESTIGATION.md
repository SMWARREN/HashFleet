# Demo / Restore Investigation

Read-only investigation. No shared files edited. Scope: `FleetStore` demo/load/clear/persistence,
app startup, Dashboard tour, and global demo routes. Focus: how previously saved items (devices and
preferences) can be lost or hidden by the demo/tour flow.

## TL;DR

- The **new guided tour** (`FleetTourView` + `FleetGuidedDemoSandbox`, commit `06a3297`) is fully
  isolated: private `UserDefaults` suite, deny-all `URLSession`, `hardwareControlGate: nil`. It
  cannot touch real devices or real preferences. This path is safe.
- **CONFIRMED issue: preference leakage in global demo (P3).** `store.preferences` stays bound to
  real `.standard` defaults during the global demo (`loadDemo()`/`clearDemo()`, reachable from
  **AboutView**, **onboarding empty-state**, and `--demo`). Any settings screen shown over the demo
  writes straight through to the user's real preferences, and there is no restore on exit. This is
  the real, reproducible way "saved items" (settings such as dashboard coins, sort, appearance) are
  lost.
- **The device fleet is NOT lost by the global demo.** Correction to an earlier draft: `add()` and
  `rename()` persist immediately (`FleetStore+Devices.swift:29,43`); `loadDemo()` never overwrites
  the canonical disk key `app.hashfleet.devices.v1`; `init` reloads that key on every launch before
  any demo entry (`FleetStore.swift:73`); and `clearDemo()` is guarded by `guard isDemo`
  (`FleetStore+Persistence.swift:45`) so it cannot restore an empty list in a non-demo state. A
  relaunch/force-terminate mid-demo therefore returns to the intact canonical fleet on next launch.
- No claim is made about any interim deployed build. The reproducible defect in the current code is
  the preference leakage (P3) below.

## Confirmed production paths that lose or hide saved state

### P3. Global demo mutates real preferences with no snapshot/restore  (settings loss) [CONFIRMED, the defect]
`FleetPreferences` (`App/Store/FleetPreferences.swift`) persists every setter directly to the
injected defaults. In global demo the injected defaults are `.standard`. During global demo the
Dashboard can still present `MonitoringSettingsView` / `FleetPreferencesView` /
`FleetCoinSelectionView`, all bound to `store.preferences`:
- `dashboardCoins`, `appearance`, `sort`, `ascending`, `compactCards`, `realtimeMonitoring`,
  notification toggles all write through to real defaults immediately.
- `clearDemo()` restores devices/snapshots but **does nothing for preferences**. So a coin/sort/
  appearance change made "just to see the demo" permanently overwrites the user's real settings.
- Contrast: the sandbox tour explicitly scopes coin edits to its throwaway suite
  (`FleetTourView.goTo` lines 228-229) precisely because it has private defaults. The global demo
  has no such protection.

### P4. Device fleet is safe (was over-reported)
Corrected: there is no device data loss from the global demo. `add()`/`rename()` persist
immediately, the canonical disk key is never overwritten by demo, `init` reloads it before any demo
entry, and `clearDemo()`'s `guard isDemo` prevents an empty non-demo restore. `savedDevices` being
in-memory is fine because a relaunch returns to the intact canonical disk fleet, not to
`savedDevices`. No durable pre-demo device backup is needed.

### P5. "No saved fleet" + demo entry from onboarding
`DashboardView+Sections.swift:14` offers `exploreDemo: { store.loadDemo() }` from the empty-state.
Benign for devices. P3 still applies: preference changes during that demo overwrite real defaults
with no restore.

## Paths that are SAFE (no change needed)

- **Guided sandbox tour** (`FleetGuidedDemoSandbox`): private suite + deny-all session; cleaned up
  on `onDisappear`. Cannot lose or alter real data. (`App/Features/Tour/FleetGuidedDemoSandbox.swift`)
- **`persist()`** is not called while `isDemo` for the device list: `remove()` guards on `!isDemo`
  (`FleetStore.swift:174`); `rename()` throws `demoReadOnly` (`FleetStore+Devices.swift:35`);
  `add()` calls `clearDemo()` first then persists real data (`FleetStore+Devices.swift:19`).
  So demo device content is never written to the real key. Good.
- **Backup import during demo** (`FleetBackupStoreIntegration.swift:78`) writes real bytes first,
  verifies readback, then transitions out of demo without persisting demo data. Good.
- **Firmware `persist()`** (`FleetStore+Firmware.swift:158`) writes only firmware notices, not the
  fleet; harmless but note it runs regardless of `isDemo` (writes demo-derived notices keyed by
  demo device IDs to real defaults; low impact, cosmetic cache only).

## On the "after a walkthrough" report

No claim is made about any interim deployed build. `0007ee0`'s `FleetTourView` was a static,
read-only tour that did not call `loadDemo()`, and current HEAD's tour is the isolated sandbox. The
reproducible defect in the current code that matches "settings lost after exploring" is P3:
entering the global demo (About / onboarding / `--demo`), changing a preference on a settings screen
shown during demo, then leaving demo, with no preference restore. The device fleet is not affected.

## Proposed fix boundary (for root to approve; no edits made)

Owner: root owns builds and shared files. Scope is P3 only (device fleet needs no change).

1. **Scoped durable demo preference checkpoint (the fix).** On `loadDemo()`, snapshot the real
   preference keys into a dedicated durable checkpoint (either an in-defaults recovery blob or a
   scoped copy), so the checkpoint survives a relaunch mid-demo. While `isDemo`, either (a) rebind
   `store.preferences` to a scoped demo defaults suite (mirrors the sandbox, cleanest), or (b) keep
   real defaults but restore from the checkpoint on `clearDemo()`. On `clearDemo()` restore the
   checkpoint and delete it. On `init`, if a live checkpoint exists (relaunch happened mid-demo),
   restore real preferences from it before first render, then clear it.
   - Must **preserve the existing canonical fleet** and must **not** overwrite a newer canonical
     fleet from any backup path; this checkpoint covers preferences only and is independent of the
     device list, which is already durable.
2. **Optional:** guard firmware demo notices with `!isDemo` to avoid writing demo-derived notices to
   real defaults (cosmetic cache only, low priority).

Hooks needed (root to place): `loadDemo()` (checkpoint create), `clearDemo()` (restore+delete),
`FleetStore.init` (relaunch-mid-demo restore), and a scoped defaults handle if option (a) is chosen.

Validation to run after a fix (root): unit tests for (i) preference round-trip across
loadDemo -> mutate -> clearDemo (real prefs unchanged); (ii) relaunch-mid-demo restore from
checkpoint on init; (iii) canonical fleet and any newer backup-imported fleet are untouched by the
preference checkpoint; (iv) sandbox tour tests still pass.

## File index

- `App/Store/FleetStore.swift` (init/disk load lines 73-99; remove guard 174)
- `App/Store/FleetStore+Persistence.swift` (loadDemo 8; clearDemo 43; persist 105)
- `App/Store/FleetStore+Devices.swift` (add 8; rename 34)
- `App/Store/FleetPreferences.swift` (direct defaults setters)
- `App/HashFleetApp.swift` (startup, `--demo` handling via init, scenePhase 139-147)
- `App/Features/Dashboard/DashboardView.swift` (tour sheet 88-97; loadDemo 269)
- `App/Features/Dashboard/DashboardView+Sections.swift` (onboarding exploreDemo 14)
- `App/Features/About/AboutView.swift` (demo toggle 76-79)
- `App/Features/Tour/FleetTourView.swift`, `FleetGuidedDemoSandbox.swift` (isolated tour, safe)
- `App/Features/Backup/FleetBackupStoreIntegration.swift` (safe demo import 78)

_No shared/production files were modified during this investigation._
