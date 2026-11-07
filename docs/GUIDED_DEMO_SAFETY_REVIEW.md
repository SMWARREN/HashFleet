# Guided Demo Safety Review

**Date:** 2026-09-12  
**Scope:** Read-only review of the guided tour's real production screen embeddings under isolated demo stores and coordinators. No production source edits, builds, or spawned agents were used for this review.

## Result

The guided environment's toolbar omission removes the concrete navigation-bar action leak identified during review. The reported 14-step physical tap route passed. With the notification-settings appearance query guarded, no remaining concrete unsafe appearance side-effect path was found.

## Concrete findings and required guards

### 1. Notification settings queries iOS state on appearance

- **Path:** `App/Features/Settings/FleetNotificationSettingsView.swift` → `FleetNotificationSettingsSections.body` → `.task { await model.refresh() }`
- **Path:** `App/Features/Settings/FleetNotificationSettingsModel.swift` → `refresh()` → default `readAccess` and `readBackgroundStatus` closures
- **Effects:** Reads `UNUserNotificationCenter.current().notificationSettings()` and `UIApplication.shared.backgroundRefreshStatus` when the screen appears. This does not request permission, but it is still a real OS query and is outside the intended no-OS-effects tour contract.
- **Required narrow guard:** In guided-demo mode, skip the appearance refresh or inject no-op/test read closures. Keep explicit user actions unavailable in the guided environment.

### 2. Dashboard can present its own feature tour

- **Path:** `App/Features/Dashboard/DashboardView.swift` → `.onChange(of: startupReady, initial: true)`
- **Effect:** With `startupReady == true` and fresh demo preferences allowing the feature tour, Dashboard can present a nested app tour. Its sheet dismissal writes `store.preferences.hasSeenFeatureTour = true`.
- **Required narrow guard:** Require `!fleetGuidedDemo` before presenting the app's automatic tour. The guided instance must not use the normal automatic-tour presentation path.

### 3. Dashboard and Miner navigation toolbars

- **Effect:** `.allowsHitTesting(false)` and accessibility hiding on the underlying screen do not reliably cover navigation-bar toolbar items. Toolbar actions could escape into the outer sheet.
- **Resolution:** Guided mode omits the complete Dashboard and Miner toolbars. This is preferred over relying only on `.disabled(true)` or hiding the entire navigation bar, because the outer guided-tour Close control must remain available.

## Paths verified safe under the stated isolation

- **FleetStore demo loading:** `FleetStore.loadDemo()` uses the isolated defaults and in-memory `DemoFleet` data. Demo state cancels refresh work and the hardware gate is nil.
- **Dashboard chain data:** `FleetChainCard` starts an insights task, but `MiningInsightsStore.setDemo` and `refresh()` route to `applyDemoData()` without network requests.
- **Connected pool data:** `FleetPoolsCard` starts a pool refresh task, but `ConnectedPoolsStore.prepareRefresh` detects `fleet.isDemo`, loads in-memory demo data, and returns before provider clients/network work.
- **Miner detail firmware check:** `MinerDetailView`'s firmware task already guards `!store.isDemo`.
- **Miner notice state:** `MinerDetailView` reads snooze state on appearance. The reviewed fix passes `store.defaults`, preventing reads and expired-key cleanup through shared `UserDefaults.standard`.
- **FleetCoinSelectionView:** Reads preferences on appearance and only persists changes after an explicit toggle or button action. It does not switch miner pools.
- **FleetEnergyView:** Initializes `FleetEnergySettings` from the injected demo defaults and computes estimates in memory. No network, hardware, or OS permission path runs on appearance.
- **FleetReportView:** `onAppear` calls `FleetReportSnapshot.capture`, which is a synchronous in-memory copy of stored readings. PDF rendering and `FleetReportPDFPreview` are in memory.
- **Report filesystem:** `FleetReportTemporaryFile.create` and `FileManager` temporary-directory writes occur only from explicit Share PDF/CSV actions, not report appearance or PDF preview. Guided controls do not invoke those actions.
- **FleetGlanceCoordinator:** `isTesting: true` blocks WidgetKit reloads, ActivityKit reads/requests/updates/ends, and shared widget storage writes. The isolated defaults prevent production preference writes.
- **Performance monitor:** `fleetPerformanceScreen` only claims/releases an in-memory global screen token. CADisplayLink is active only when frame-pacing diagnostics are explicitly enabled, and it has no persistence or external system output.

## Final assessment

After the guided environment omits embedded screen toolbars, guards Dashboard automatic-tour presentation, guards or injects the notification settings appearance refresh, and uses the isolated demo stores/coordinator described above, the guided tour has no remaining concrete unsafe storage, system, hardware, network, notification, share, control, or filesystem side effect on screen appearance. Explicit OS actions remain unreachable from the guided route.
