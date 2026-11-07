# Integration acceptance audit, 2026-09-12

## Request interpretation and limits

The user wants the current app installed on their iPhone, multiple discovered miners added without leaving the scan page, block and best-share notifications, broader open-source miner coverage, and five-agent premium UX improvements. Existing single-miner artwork must remain unchanged. A separate agent owns the splash screen.

Interpretations that were necessary: broader coverage means compatible ESP-Miner/AxeOS-family devices, not arbitrary open-source protocols. “The Fleet” was a naming suggestion, not approval to rename the app or bundle identifier. Premium UX was broad rather than a fixed visual specification. None of these interpretations establish user approval of every visual output. Earlier dual-fan appearance acceptance is NOT established by the checks below.

## Requirement-to-observation map

| Requirement / changed output | Executed check and result | Remaining limit |
| --- | --- | --- |
| Install current build | Signed iPhone build and embedded widget validation passed; devicectl confirmed app.hashfleet installed at 15:34 UTC | Launch attempts at 15:34 and 15:50 returned explicit iOS Locked error. Physical launch not observed |
| Add more than one scan result without leaving | `Add miner multi-selection` suite passed, including custom-name-first-only and rejecting duplicate re-add; coordinator tests passed retaining partial results on cancel and returning idle when none found; ordering/grouping suite passed | These are unit/coordinator checks, not a two-live-miner UI acceptance run. Live hardware behavior remains unverified |
| Broader miner naming and compatibility | `MinerDisplayNameTests` and `Firmware family identification` suites passed; `automaticModelNameAndExplicitLocalNameSurviveRefreshAndRelaunch`, `explicitGenericNameIsPreservedAndLegacyDefaultUpgrades`, `oldDeviceJSONDecodesWithoutNamingMode`, and lowercase-hashrate compatibility test passed | Store/decoder fixtures do not prove arbitrary hardware compatibility. Family inference from hostname is only a hint, not authoritative firmware compatibility |
| Preserve identity and protected artwork | New coordinator commits 550175a and e997bd4 touch only notification code/tests and one UI test; external splash commit 0246290 remains in history | This verifies these changes did not modify protected assets, not historical visual approval of dual-fan variants |
| Five-agent premium UX integration | Discovery da88371, details 5f60093, naming 84441f4, dashboard 28137de and Settings 9f0b9f1 integrated. Final full unit run passed. Real UI test opened Notifications, found test action, changed compact/realtime preferences, dismissed Settings, revealed search, searched Workshop, opened miner detail, returned and confirmed compact preference retained | Demo-backed real app navigation does not prove live discovery, every detail screen, accessibility size, light/dark rendering, or subjective visual quality |
| Notification event detection and queueing | `Best share alerts`, `Multi-miner notification delivery` suites passed; equal/lower-share suppression and separate block-flag transition tests passed | Local tests do not prove OS background scheduling or physical notification display |
| Notification permissions and diagnostics | `Notification settings` suite passed, including denied/granted/quiet states, revoked access, all saved-toggle combinations, duplicate submission prevention, cancellation, permission errors/retry and exact five-second guidance. Real UI test verified Notifications page and diagnostic button reachable | Diagnostic model tests inject dependencies. Real UN notification scheduling and actual display were not exercised on physical iPhone. No guarantee of periodic background execution |
| Test health and packaging | 507 tests in 48 suites passed; real `testFleetPreferencesAndSearchStayLocal` passed in 52 seconds; signed app and embedded-widget validation passed | Focused UI test is not the whole UI suite. Aggregate count alone is not acceptance mapping |
| Offline, persistence, cancellation and integration failures | Executed tests passed: `cachedSnapshotRelaunchIsOfflineAndRetainsObservedTime`, `snapshotCacheNeverPersistsCredentialsOrUnknownFirmwareFields`, `unrecognizedHTTP200PayloadsAreOfflineWithoutFabricatedHistory`, `enteringDemoCancelsRealRequestsAndRejectsTheirResults`, `offlineGuardBlocksEveryMutationBeforeNetworking`, `rotatingPoolUpdatesDashboardDetailDiagnosticsAndSetupWithoutFallbackFlagChanging` | Fixture-driven integration tests, not production network/hardware observation |

## Evidence and improvement

Unit result: `Test-HashFleet-2026.09.12_11-32-10--0400.xcresult` in the normal DerivedData Logs/Test directory. The saved build log explicitly reports the diagnostic feedback test passed and 507 tests/48 suites passed.

UI result: `Test-HashFleet-2026.09.12_11-48-51--0400.xcresult`. Earlier test failed before completing Settings/search due to stale scroll ordering, unscoped back-button queries and a short drag that did not dismiss the sheet. The corrected test scopes navigation bars, asserts sheet disappearance, uses actual pull-to-reveal search, clears the search to restore the toolbar, and preserves original preference/search/detail assertions. It now completes with zero failures. No app logic was weakened to make it pass.

Notification implementation is committed as 550175a. Passing UI regression repair is e997bd4. Working tree was clean at the confidence audit.

## Deferred acceptance, not completed

- Unlock physical iPhone and observe app launch and a clearly labelled test notification.
- Observe a genuine block/best-share notification and OS-scheduled refresh under real network conditions.
- Add two live compatible miners in a single scan sheet and observe retained results.
- Review all changed visual surfaces in both appearances and accessibility sizes, including new dual-fan artwork. No claim of user visual approval.

These are explicit evidence gaps. Installation, unit tests and one real UI workflow do not close them.
