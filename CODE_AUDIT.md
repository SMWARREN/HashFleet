# Hash Fleet iOS code audit

Audit date: 2026-09-13  
Repository: `/Users/USER/dev/hashfleet`  
Scope: Swift sources and tests under `App`, `Shared`, `Sources`, `Widgets`, `AppTests`, `Tests`, and `UITests`.

## 1. Executive summary

The audit found no unresolved Critical or High findings in the reviewed Swift code. The working tree now contains fixes for the compiler warnings, deprecated App Intents confirmations, an optional-to-`Any` metadata coercion, an unnecessarily mutable encoder, an unassigned app-icon asset, stale UI-test navigation contracts, and missing dismissal/tour accessibility targets.

The scoped tree contains 326 Swift files and 56,263 lines: 195 product files and 131 test files. Verification results are:

- SwiftLint strict: 0 violations.
- Swift package tests: 189 tests passed in 21 suites.
- Native app target tests: 616 tests passed in 65 suites.
- Simulator build: succeeded with no compiler, linker, or asset-catalog warnings.
- Focused UI checks: adaptive splash, appearance switching, miner-detail reopening, and the guided tour passed.
- Local SonarQube with the `sonar-apple` Swift analyzer: analysis succeeded, quality gate `OK`, 0 new violations, 0 unresolved issues.

The complete UI target was also exercised before the final focused contract fixes. That run executed 95 tests with 1 skipped and 18 failures. Those results are recorded in section 11 because they were concentrated in stale test assumptions, simulator sheet/live-data flows, and unavailable external fixtures; they do not invalidate the passing native target or the focused appearance/navigation checks rerun afterward.

## 2. Quick wins and hygiene

### 2.1 Fixed compiler and lint hygiene

`FleetBackupCodec.encode` now uses a `let` encoder (`App/Features/Backup/FleetBackupCodec.swift:11-18`). Block telemetry metadata no longer inserts an optional into `[String: Any]`; it is emitted only when a height exists (`App/Store/FleetStore+Monitoring.swift:282-289`). Numeric-motion and performance tests no longer contain ineffective optional assertions or swallowed requirements (`AppTests/FleetNumericMotionTests.swift:14-22`, `AppTests/FleetPerformanceMonitorTests.swift:83-225`).

### 2.2 Removed the asset-catalog warning without losing the old binary

The unused legacy `AppIcon.png` was moved into `LegacyAppIcon.imageset` while the active light/dark app-icon pair remains in `AppIcon.appiconset`. The fresh simulator build reports no asset-catalog warnings.

### 2.3 Repaired UI-test navigation contracts

The app uses the dashboard toolbar menu for Settings and About. `UITests/FleetUINavigation.swift:3-104` centralizes that contract, handles nested settings dismissal, and keeps the accessibility identifiers stable. Stale `dashboard.appearance` and tab-bar assumptions were updated across the UI tests. Missing tour targets for the fleet preferences and appearance picker were restored at `App/Features/Settings/MonitoringSettingsView.swift:30-40` and `App/Features/Settings/FleetPreferencesView.swift:68-77`.

### 2.4 Added deterministic dismissal targets

Settings and About now expose explicit Done actions (`App/Features/Settings/MonitoringSettingsView.swift:187-198`, `App/Features/About/AboutView.swift:110-122`). This removes reliance on simulator swipe timing when returning from nested sheets.

## 3. Concurrency and isolation

### 3.1 Resolved the Swift 6 main-actor warning

`FleetTabBarAppearance` is explicitly `@MainActor` (`App/Design/FleetTabBarAppearance.swift:10-29`). The synchronous `App.init` applies UIKit appearance through `MainActor.assumeIsolated` (`App/HashFleetApp.swift:54-59`), which matches the UIKit launch boundary. The simulator build completes without concurrency warnings.

### 3.2 Lifecycle cancellation remains explicit

Foreground monitoring is keyed by scene/device state and non-active phases cancel refresh, capability work, and public insights (`App/HashFleetApp.swift:126-194`). No unbounded task or actor-isolation warning was introduced by the audited changes.

## 4. API modernity

### 4.1 Replaced deprecated App Intents confirmation calls

Restart, frequency, and fan-speed intents now share `requestFleetConfirmation`, using the dialog-aware API on iOS 18 and retaining a confirmation prompt on the iOS 17 deployment target (`App/Features/SystemIntegrations/FleetMinerControlIntents.swift:25-33`, `61-69`, `97-122`). The app target build is warning-free.

### 4.2 Recorded the remaining build-tool warning

The native test/build log contains `appintentsmetadataprocessor: Metadata extraction skipped. No AppIntents.framework dependency found.` for the widget metadata phase. This is a toolchain/target dependency notice, not an app-source warning; the app target tests and build still pass.

## 5. Bugs and correctness

### 5.1 Fixed an invalid optional metadata shape

The block-found event previously attempted to store an optional height in an `Any` dictionary. It now uses the observed height only when present and preserves the count fallback for the event field (`App/Store/FleetStore+Monitoring.swift:282-289`).

### 5.2 Made launch verification trait-aware

The storyboard uses `systemBackground` and adaptive launch artwork (`App/Resources/LaunchScreen.storyboard:18-40`). `LaunchBrandTests` now applies the requested appearance before loading the controller and checks white in light mode or black in dark mode (`AppTests/LaunchBrandTests.swift:108-145`). This matches the runtime behavior and passes for both portrait and landscape sizes.

### 5.3 Improved accessibility state reporting

The dashboard Settings control reports either the selected Light/Dark mode or the effective System mode (`App/Features/Dashboard/DashboardView.swift:175-186`). This makes the current state available to VoiceOver and UI automation without changing the control flow.

## 6. Security and privacy

### 6.1 Public-data transport is constrained

`MiningInsightsClient` strips cookies, caches, credential storage, and caller headers, bounds timeouts, permits fixed HTTPS endpoints, rejects redirects, caps responses at 1 MiB, and exposes no arbitrary-URL execution method (`Sources/HashFleetCore/MiningInsightsClient.swift:8-24`, `99-156`, `179-211`).

### 6.2 Pool lookup validates identity and transport

`SoloPoolClient` re-validates provider, coin, documented host, and address; rejects path/query/fragment injection; uses a fixed HTTPS API host; blocks redirects; requires a 200 response; and applies the same 1 MiB response cap (`Sources/HashFleetCore/SoloPoolClient.swift:54-145`).

### 6.3 Backups are bounded and redacted by design

Backup encoding/decoding enforces a maximum file size and entry count and accepts only the `version`/`entries` schema. The documented payload excludes passwords, wallets, raw snapshots, authentication material, and seeds (`App/Features/Backup/FleetBackupCodec.swift:4-59`). No new Critical or High security issue was identified.

## 7. Performance and resource use

### 7.1 In-memory history is bounded

Successful readings retain only the most recent 360 points per miner (`App/Store/FleetStore+Monitoring.swift:141-145`). The performance monitor uses bounded sample capacity and its tests cover 60 Hz, 120 Hz, throttling, hitch detection, and baseline resets (`AppTests/FleetPerformanceMonitorTests.swift:83-225`).

### 7.2 Monitoring work is gated by app state

Realtime monitoring is active only while the scene is active and the preference is enabled; refresh and related capability/insight work are cancelled when the scene leaves the foreground (`App/HashFleetApp.swift:126-194`). Instruments and long-duration battery profiling were not run; see section 11.

## 8. SwiftUI and UI behavior

### 8.1 Appearance-aware launch and splash behavior is covered

The launch storyboard uses `systemBackground` and the `HashFleetLaunch` light/dark image set (`App/Resources/LaunchScreen.storyboard:18-40`, `App/Resources/Assets.xcassets/HashFleetLaunch.imageset/Contents.json`). The in-app splash uses the shared adaptive canvas and keeps its ambient artwork dark-mode-only (`App/Design/FleetStartupSplash.swift:21-118`). The splash skip/resume test passed in both modes.

### 8.2 Settings and About have stable return paths

Explicit Done buttons and centralized UI-test navigation cover nested settings, About, appearance changes, and returning to the fleet list. The focused appearance and miner-detail tests passed after these changes.

### 8.3 Broad UI verification remains environment-sensitive

The broad UI run captured before the final focused contract fixes produced 77 passes, 1 skip, and 18 failures out of 95. The failing groups included old tour ordering, pool-icon demo reachability, history/chart fixtures, search expectations, live/public network flows, and one stale XEC test selector. The corrected guided tour, splash, appearance, and miner-detail flows were rerun separately and passed. The broad target was not rerun after those final focused fixes because several cases require live/public fixtures and take roughly 42 minutes sequentially.

## 9. Dead code, duplication, and refactoring

### 9.1 No production TODO/FIXME or force-cast markers were found

The scoped marker search found no `TODO`, `FIXME`, `HACK`, `XXX`, `try!`, or `as!` in product code. A small number of force unwraps remain for compile-time URLs, preview defaults, and test fixtures; they are deterministic literals or test setup and were not treated as production findings.

### 9.2 Large files are follow-up refactoring candidates

The largest product files include `App/Store/MinerSnapshot.swift` (548 lines), `App/Features/Dashboard/DashboardView+Sections.swift` (454), `App/Features/Dashboard/MinerOverviewCard.swift` (408), and `Sources/HashFleetCore/ConfiguredMiningPool.swift` (395). They are coherent feature areas and passed the current checks, but splitting them would reduce review and change-risk surface in future work.

## 10. Cross-cutting maintainability

### 10.1 Accessibility identifiers are now treated as an interface

The dashboard settings menu, settings Done action, About Done action, and tour targets have named contracts in product code and are consumed through shared UI-test helpers. This reduces repeated selector logic and makes future shell changes visible in one place (`UITests/FleetUINavigation.swift:12-104`).

### 10.2 Static checks are reproducible locally

The repository already provides `.swiftlint.yml`, `sonar-project.properties`, and `Tools/sonar-scan.sh`. The audit ran SwiftLint, Swift package tests, the native app target, a simulator build, focused UI tests, and the Docker-backed Sonar scan. No commit was created; fixes remain reviewable in the working tree.

## 11. Out of scope and verification limits

The audit did not certify physical Bitaxe hardware, production pool availability, App Store signing/submission, localization, StoreKit, third-party package internals, Instruments battery/memory profiles, or the behavior of external public APIs when their fixtures are unavailable. The broad UI failures listed in section 8.3 are retained as follow-up work rather than hidden behind a green focused run. Sonar's Xcode Warnings, Periphery, and MobSF sensors reported no parsed findings because those optional tools were unavailable in the local container; SwiftLint parsed zero issues. Sonar SCM blame was disabled for the uncommitted working tree.

## 12. Verification and severity sign-off

### 12.1 Critical and High findings

None remain unresolved in the audited scope. No exact-range remediation is required for a Critical or High finding.

### 12.2 Commands and results

- `swiftlint lint --config .swiftlint.yml --strict --quiet` — exit 0, 0 violations.
- `swift test` — 189 passed, 21 suites.
- `xcodebuild test ... -only-testing:HashFleetTests` — 616 passed, 65 suites (`/tmp/HashFleetAuditAppTestsFinal4.log`).
- `xcodebuild build ... -sdk iphonesimulator` — `BUILD SUCCEEDED`; no `warning:` or `error:` entries (`/tmp/HashFleetAuditBuildFinal2.log`).
- Focused splash — 1 passed (`/tmp/HashFleetAuditSplashFinal.log`).
- Focused appearance/miner-detail UI checks — 2 passed (`/tmp/HashFleetAuditUITargeted.log`).
- Guided feature tour — 1 passed (`/tmp/HashFleetAuditTourFinal2.log`).
- Local SonarQube scan — analysis `SUCCESS`, quality gate `OK`, `new_violations=0`, `unresolved issues=0` (`/tmp/HashFleetAuditSonarFinalExact.log`).
