# HashWatcher-inspired acceptance, 2026-09-12

## Request and interpretation

The user requested useful missing capabilities inspired by https://hashwatcher.app/ and a swarm. We interpreted this as bounded native enhancements, not copying branding, renaming the app, claiming additional miner protocols, adding cloud services, or performing hardware writes. Five scoped workers were launched. Three delivered the thermal, report, and backup work. Two stalled scopes were stopped: the coordinator completed energy estimates and the reports worker completed address privacy. The separate splash owner's work and all miner artwork were preserved.

## Verification evidence

- Core `swift test`, 16:25 UTC: **184 tests in 21 suites passed**.
- Native simulator, iPhone 16 Pro Max / iOS 26.5, final combined run: **572 tests passed, zero failures/skips**, including two UI tests. Xcode reports **771 expanded executions** across parameterized tests.
- Result: `Test-HashFleet-2026.09.12_12-26-40--0400.xcresult` under the local DerivedData Logs/Test directory.
- Earlier native UI run: privacy reveal/background re-hide, thermal demo guard, energy navigation, and existing Settings/preferences/search all passed. Only first PDF preview failed. Result: `Test-HashFleet-2026.09.12_12-20-44--0400.xcresult`. The final run repeated and passed PDF/backup and strengthened energy checks with an actual tariff save.
- Initial native suite exposed strict-key validation and stale-preview errors in backup. Corrected unknown-key decoding and added a current-fleet fingerprint; all nine native backup tests now pass.
- Real UI exposed a blank first PDF sheet. Replaced independently changing presentation flags/payloads with an item-driven presentation carrying the payload. The unchanged first-preview assertion now passes, and the PDF closes back to Reports before navigating to backup.

## Requirement-to-check mapping

| User-facing output | Concrete checks and observed result |
| --- | --- |
| All new tools reachable | Real Settings navigation reaches Reports, Temperature alerts, Electricity estimates, and Backup & restore. Four dedicated native UI tests pass across the two runs. |
| Per-miner opt-in thermal policy | `defaultOffAndSettingsRoundTripPerMiner`, `perMinerPoliciesAndSuppressionRemainIndependent`, permission denied/invalid draft/disable tests pass. Native thermal page excludes demo miner configuration. |
| Suppression survives background store recreation | `freshStorePreservesHotLatchAndCooldownAfterRecovery` and `twoLiveStoresShareLatestPolicyAndSuppressionState` pass against native app source and UserDefaults. Core thresholds, hysteresis, cooldown, invalid/stale readings pass. |
| No fabricated alerts from merged socket data | `retainedTemperatureInPartialUpdateDoesNotFabricateAnAlert` exercises actual `applyLiveMessage`: hashrate-only update does not alert; explicit fresh temperature can. |
| Multi-miner delivery and safety | `inactiveDeliveryPostsEveryEnabledEventExactlyOnce`, `foregroundRetainsAllSimultaneousThermalWarnings`, deleted-miner, demo, opt-out, and active/no-replay tests pass. Posting is captured at the real delivery owner's boundary; these tests are not proof of iOS banner display. |
| Electricity estimates and saved local tariff | Native UI enters 0.15 and observes saved confirmation. Math tests verify 1000 W = 24 kWh/day, daily 3.60 at 0.15, 30-day 108. Unknown versus zero, nonfinite overflow, persistence, invalid input, grouping rejection, and precise editing round-trip across en_US/de_DE/ar_EG pass. |
| Only fresh power counted | `staleOfflineCachedFutureAndMissingPowerAreExcluded` and `partialSocketFrameDoesNotFreshenOldPower` pass. Independent power timestamp prevents a hashrate-only socket frame from refreshing old power. Native page shows projection assumptions. |
| Anonymous frozen PDF/CSV reports | Native first PDF preview opens and dismisses. Actual UIKit/PDFKit tests verify empty PDF and multi-page large fleet. Capture test excludes private source fields; CSV formula prefix, escaping, shape, units, scope, timestamps, and demo labeling tests pass. |
| Report freshness | Snapshot subtotal/invalid/overflow/skew tests pass. Actual merged socket capture test confirms old power remains absent from preview, CSV, and subtotal until fresh power arrives. |
| Export-file safety | Scoped unique naming, cleanup, pruning, and invalid storage-root tests pass. PDF/CSV export prepares files locally for user-selected sharing. |
| Local configuration backup | All nine `FleetBackupTests` pass: bounded schema and file read, names/addresses-only export, canonical duplicates, cancellation/no mutation, additive identity-preserving restore/reload, demo safeguards, and stale confirmation rejection. Native backup page correctly disables demo export and has no unconfirmed Add action. |
| Private address reveal | Seven model tests pass. Actual miner detail UI shows no value/copy before reveal, exposes both only after explicit tap, and hides both again after Home/background and activation. Copy policy remains local-only with expiry. |
| Existing UX preserved | Existing `testFleetPreferencesAndSearchStayLocal` passes in native app. Full native/core suites pass. No artwork/launch assets changed in these commits. |

## Honest remaining boundaries

- No real miner was deliberately overheated, reset, flashed, or tuned. Thermal event tests use controlled readings through production model/store code. Live thermal detection under an actual over-temperature event is unverified.
- iOS background scheduling and displayed notifications depend on OS permission, local network reachability, Focus and suspension policy. Tests do not prove banners or exact background intervals. The user's earlier “verified iPhone” refers to the prior installed build, not these new features.
- Native PDF preview and PDF rendering/pagination are exercised. Sending a report through external destinations, confirmed Files-provider import/export, and restoring a backup into the user's real fleet are not exercised. Native share-sheet presentation/dismissal and Files-picker cancellation were subsequently exercised successfully below. Restore mutation/reload is tested with isolated native UserDefaults stores. No user fleet was overwritten.
- Energy is a current-load projection, not historical measured energy, a bill, or mining profit. Reports are captured snapshots, not automated daily history.
- Private address masking is scoped to the miner detail Address row. It is not screenshot prevention or universal masking of all addresses in the app.
- Signed device packaging/install evidence is recorded below once completed.

## Device delivery

- Executable source: `28fce49` (includes worker commits through `b65f8eb`).
- Signed `xcodebuild build` for the paired iPhone succeeded at 16:30 UTC, including embedded widget validation. `codesign --verify --deep --strict` succeeded.
- Initial install transport closed unexpectedly. One retry successfully installed `app.hashfleet` at 16:31 UTC, device installation database sequence 2112.
- Remote launch was explicitly denied because the iPhone was locked. Installation is verified; running the new features on the physical phone is not. No attempt was made to unlock or bypass this restriction.

## Additional real system-boundary acceptance at 16:35 UTC

`testFleetToolsNativeSharingAndImportCancellation` passed in the production simulator app. Both PDF and CSV opened the actual iOS activity sheet and closed back to Reports without export errors. Backup opened the actual system document picker; Cancel returned to Backup & restore with no confirmation pending and demo export still disabled. No report was sent and no user fleet was changed. Screenshots are attached to `Test-HashFleet-2026.09.12_12-34-36--0400.xcresult`. This closes share-sheet presentation/cancellation and Files-picker cancellation gaps, not external destination delivery or confirmed Files restore. No executable source changed in this follow-up.


## Current-source cross-goal rerun at 17:31 UTC
All mapped executable tests were rerun together on executable source `e750fc2`, already installed on the iPhone. Core: **189 tests / 21 suites passed**. Native: **573 unit functions plus seven real UI workflows passed**, 779 expanded executions, zero failures and zero skips. Result: `Test-HashFleet-2026.09.12_13-27-03--0400.xcresult`.

| Actual end-user workflow | Observed outcome in this rerun |
|---|---|
| `testFleetPreferencesAndSearchStayLocal` | Passed in51.696s. Existing Settings/preferences/search remained usable. |
| `testFleetToolsEnergyPageUsesExplicitEstimateCopy` | Passed in22.382s. Native energy page and explicit estimate wording reached; tariff save path passed. |
| `testFleetToolsNativeSharingAndImportCancellation` | Passed in41.415s. Actual iOS PDF/CSV activity sheets opened and dismissed; actual Files picker Cancel returned safely, without pending restore. |
| `testFleetToolsPrivateAddressRequiresRevealAndRehidesAfterBackground` | Passed in18.705s. No raw value/copy before reveal; explicit reveal exposed them, background/return hid them again. |
| `testFleetToolsReportPreviewAndBackupDemoSafety` | Passed in30.622s. First actual PDF preview rendered and dismissed; backup demo/export and unconfirmed-restore safeguards held. |
| `testFleetToolsThermalPageNeverConfiguresDemoMiners` | Passed in18.795s. Native thermal settings remained reachable but did not configure demo miners. |
| `testProductionPublicDataRendersAutomaticallyOnNativeHome` | Passed in51.176s. All six live coin rows, 20 pool readings, XEC/DGB detail readings, navigation, and no-write journals passed using production public APIs. |

The full native run also repeated the mapped report generation/privacy/freshness, backup validation/restore, energy math/persistence/locales, thermal state/suppression, and delivery-owner tests. Those controlled production-code tests are separate from the seven actual UI workflows above. Their success is not a claim of physical notification banner delivery or an unsafe real overheat test. The physical-device lock limitation and no-real-fleet-restore boundary remain unchanged. No executable changes were needed after this run.
