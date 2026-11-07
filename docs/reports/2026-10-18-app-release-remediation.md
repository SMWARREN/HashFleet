# Direct Astra app/release remediation, 2026-10-18

Owner: `ladybug`, direct native OpenAI Astra. Repository: `/Users/USER/dev/hashfleet`.

Status: implementation delivered for coordinator integration, with final simulator acceptance **not fully passing**: 238 passed, 3 host-force-quit failures, 0 skipped. Both Mac products and the push-enabled simulator product built successfully. The coordinator took ownership of core and FleetStore boundary integration at 21:33 UTC and requested this worker stop after reporting the focused rerun. This is not a live fleet status report. No child agents, commits, real miner requests, hardware writes, installs into `/Applications`, or production fleet preference operations were performed by this worker. The canonical mining playbook opening and hard limits were read before source inspection.

## Implemented behavior

- PF-01/PF-02: optional metrics preserve absent/null/invalid/sentinel values and genuine zero. App telemetry extraction now uses canonical fan/share/uptime keys, validates numeric integer fields, and does not infer fallback status from pool slot number. The regression exercises the production app conversion through real disposable SQLite readback for all affected columns.
- PF-03: menu-bar snapshot publication is independent of strict widget aggregate completeness. Missing power no longer freezes per-miner rows, count, date, or rate. Mixed SHA-256/CPU rates are not summed. Publication task identity includes the richer snapshot and foreground bootstrap invokes it even when the widget payload is unavailable.
- PF-05/PF-14: the actual menu formatter and native UI label expired rows stale, prevent cached/demo rows from looking green Live, show unavailable metrics rather than fabricated zero, and identify demo data in closed title, tooltip and popover header. Legacy menu snapshots remain decodable. `FleetGlance` retains exactly its original six keys and all existing privacy/schema assertions.
- PF-06: the iOS 17 result-based confirmation API receives exactly the same detailed dialog as iOS 18+, with `showPrompt: true`. Authentication, preflight safety, cancellation and confirmation remain.
- PF-08: app clearing waits for the checked throwing database operation before resetting achievement baselines or inbox state, displays failure, refuses demo clearing, and supports retry without clearing unrelated persistence errors. Core transaction semantics remain owned by the coordinator/core worker.
- PF-15: post-write refresh invalidates older foreground reads, rejects changed/deleted targets, and waits for a new complete observation before reloading forms. Older fallback reads cannot overwrite it. Failed readback retains the draft. Unchanged but freshly revalidated snapshots are current. Fleet cancellation also cancels capability work, and test sessions wait for canceled probes before invalidation.
- PF-16: retained future XMRig controls use shared freshness/cache/reconnection checks, display last-known state honestly, revalidate before command, support cancellation, and do not claim confirmed current state when post-command readback fails.
- Release treatment: one reversible flag, `FleetReleaseFeatures.xmrigEnabled = false`, hides XMRig add choices, dashboard/sidebar cards and totals, detail navigation and history inputs. Saved devices, credentials, adapters, CLI/core implementation and future-feature tests remain. Existing CPU implementation assertions continue via the retained internal content view, with separate shipping-visibility tests.
- PF-04/PF-12: packaging always invokes the app build, uses the actual SwiftPM product directory, and requires two explicit inputs for prebuilt mode. Source/output overlap is rejected before removal. Documentation and generated install notes describe the actual primary app plus CLI payload, not an unbundled companion or nonexistent LaunchAgent.
- PF-07/NF-01 integration: app and push-provider calls forward block height and uptime to the current core key API. Provider notification identity uses that same key. The ESP-only provider excludes saved XMRig configurations. Core identity/atomicity caveats below are not claimed fixed by app changes.
- Native rendering follow-through: existing assertions exposed the absent direct settings link in the tools list and the lack of a readable retained-history rate when the current metric disappears. The actual UI now provides reviewed Settings & pools navigation and an explicitly labelled retained-history average. Existing assertions were not weakened.

## Files changed by this worker

```text
App/HashFleetApp+Routing.swift
App/HashFleetApp.swift
App/Features/Dashboard/AddMinerView.swift
App/Features/Dashboard/DashboardView+Demo.swift
App/Features/Dashboard/DashboardView+Sections.swift
App/Features/Dashboard/DashboardView+WideLayout.swift
App/Features/Dashboard/DashboardView.swift
App/Features/Dashboard/FleetSplitView.swift
App/Features/Dashboard/FleetStatusTickerModel.swift
App/Features/Miner/MinerDetailView+Desktop.swift
App/Features/Miner/MinerDetailView+Sections.swift
App/Features/Miner/MinerDetailView.swift
App/Features/Miner/MinerEndpointView+Extraction.swift
App/Features/Miner/MinerSettingsView+DirectSave.swift
App/Features/Miner/XMRigControlView.swift
App/Features/Settings/FleetPreferencesView.swift
App/Features/SystemIntegrations/FleetMinerControlIntents.swift
App/Store/FleetGlanceCoordinator.swift
App/Store/FleetStore+Evaluation.swift
App/Store/FleetStore+Monitoring.swift
App/Store/FleetStore+Persistence.swift
App/Store/FleetStore+Totals.swift
App/Store/FleetStore.swift
App/Store/MinerCapabilitiesStore.swift
AppTests/FleetGlanceTests.swift
AppTests/FleetMonitoringBoundaryTests.swift
AppTests/FleetPersistenceBoundaryTests.swift
AppTests/FleetTelemetryCompletenessTests.swift
AppTests/FleetViewRenderHarness.swift
AppTests/MinerDetailRenderingCoverageTests.swift
AppTests/MinerDirectSavePolicyTests.swift
AppTests/MinerLiveAndXMRigIsolationCoverageTests.swift
MacMenuBar/HashFleetMenuBarApp.swift
PushProvider/PushProvider.swift
Scripts/package-hashfleet-mac.sh
Scripts/tests/test_package_hashfleet_mac.py
Shared/FleetGlance.swift
docs/MAC-DISTRIBUTION.md
docs/reports/2026-10-18-app-release-remediation.md
```

`Shared/FleetGlance.swift` was explicitly authorized by the coordinator. This worker did not edit `Sources/HashFleetCore/`, `Sources/hashfleet/`, or their tests. The coordinator added direct GRDB linkage to the app-test target in `project.yml` and the generated Xcode project. That integration is necessary for the full SQLite readback regression and is not attributed to this worker. At 21:33 UTC the coordinator also edited and assumed ownership of `App/Store/FleetStore.swift` and `App/Store/FleetStore+Monitoring.swift`. The working-tree diff for those two files now includes both workers' changes.

## Validation receipts

Logs and result bundles: `.build/app-release-remediation-20261018/`.

- Five actual packaging-script regressions passed, most recently at 21:28 UTC (`packaging-final.log`, 5 tests in 0.488 seconds), using isolated build/archive tool doubles. Cases cover two controlled revisions, failed rebuild preservation, explicit prebuilt consent, actual payload/documentation alignment, and unsafe output/source rejection. No installer was executed.
- Shell syntax passed for `package-hashfleet-mac.sh`, `install-hashfleet-mac.sh`, `uninstall-hashfleet-mac.sh`, and `hash-fleet-menu-bar.sh`.
- Native `HashFleetMenuBar` Debug arm64 macOS build passed again after the last production app edit: `mac-menu-final.log`.
- Primary Designed-for-iPad Mac app DebugNoAppPush arm64 build passed again after the last production app edit: `mac-main-final.log`.
- Actual push-enabled iOS Simulator app and extension Debug arm64 build passed: `push-enabled-build.log`.
- Actual app and all test sources compiled after the core checked-clear API landed. Initial unit-test linking correctly exposed missing direct GRDB linkage. No source assertion was removed to bypass it.
- Final actual iOS 26.5 simulator run: **238 passed, 3 failed, 0 skipped, 241 total named tests**, Xcode exit 65. Result: `focused-tests-final.xcresult`; exact summary: `focused-tests-final-summary.json`; log: `focused-tests-final.log`. The per-device count including dynamic parameter cases is 291 passed and 3 failed, not an additional test run.
- Passing focused suites cover capability cancellation, glance/schema/completeness, intents, monitoring, persistence failures, ticker, store, real SQLite telemetry readback, direct-save policy, post-write ordering and safety. Rendering suites contain the three unresolved process terminations listed below. No failed expectation assertions or session-invalidation exception were recorded in the final run.
- Both final Mac builds completed successfully at approximately 21:26 UTC. Simulator tests compiled at approximately 21:28 and finished executing at 21:30 UTC, before the coordinator's 21:33 integration edits. A fresh integration verifier is required after those later edits.
- `git diff --check` passed after implementation and final packaging verification, and again after coordinator handoff.

Owned simulator: `07B58F1A-21E0-4BF6-BE41-EB8A0CC7E724`, iPhone 17 Pro, iOS 26.5. It contains only isolated test preferences and mock/demo fixtures for this work. It remains booted and is now released to the coordinator for reproduction. No test driver from this worker remains running. Native rendering tests capture SwiftUI pixels and use Vision OCR, not fabricated expected output. They are not equivalent to full accessibility/touch acceptance.

### Preserved failures and retries

1. Initial no-push app build failed on the not-yet-landed `clearAllDataChecked()` public core API. The later app build passed after integration.
2. First native companion invocation used `-target` together with `-derivedDataPath`, which Xcode rejects. Corrected to its generated scheme and passed.
3. Attempting to build the generated PushProvider scheme also built its containing app and initially encountered the same pending checked-clear API. The later push-enabled app/extension build passed.
4. Initial app-test linking failed because GRDB was not a direct test dependency. A temporary validation-only object-link override was attempted, but overlapped the coordinator's permanent package-product integration and duplicated GRDB at runtime, causing its thread-ownership precondition to fail. That run was stopped and its log/result retained. Subsequent runs use only the normal integrated project, without that override.
5. Native runs exposed a fixture teardown race: background capability probes could create a task after their session had been invalidated. The integrated run recorded 224 passed and 4 crash failures, with no failed expectation assertions. Cancellation now exposes the pending handles, and fixtures wait for completion before invalidation. Final rerun results determine acceptance, not partial passes from crashed/restarted runs.
6. Two existing native UI assertions initially failed. Actual UI behavior was fixed rather than deleting or relaxing either assertion.
7. Final remaining failures are `MinerDetailRenderingCoverageTests.detailKeepsReportedAndUnavailableReadingsHonest(_:)`, `MinerDetailRenderingCoverageTests.missingHashrateHasNoInventedUnit()`, and `MinerLiveAndXMRigIsolationCoverageTests.statusStripSeparatesDemoConnectedAndLivePresentation(_:)`. Xcode records `Test crashed with signal kill`. Simulator logs explicitly record host-requested force-quit `0xFBFBFBFB`, including at 21:28:46 UTC. The initiating host client is not established, so these remain failed acceptance checks rather than being relabelled passes or blamed on another worker.
8. After all test execution ended at 21:30:38 UTC, Xcode's child `simctl diagnose` collector stalled. Only that owned diagnostic collector was terminated at 21:33:59 UTC to let Xcode finalize the result bundle. This was after, and did not cause, the three earlier test-process kills. No assertions, test selection, timeout checks or runtime checking were weakened.

## Integration assumptions and remaining release gates

- App code consumes `public func MinerTelemetryDatabase.clearAllDataChecked() async throws` and `FleetSharedStore.blockKey(deviceID:count:height:uptimeSeconds:)`, plus `FleetBlockDetection.Result.uptimeSeconds`.
- The coordinator changed checked-clear VACUUM to best-effort at 21:33 UTC, addressing the source-level post-commit error-reporting concern. An in-flight flush guard also landed. Those later changes still require the coordinator's transaction/concurrency acceptance checks and fresh integrated app run. App copy does not guarantee history was preserved for an unknown failure phase.
- At final inspection the core key prefers height and otherwise buckets reported uptime by 60 seconds. Reported uptime is not a reboot timestamp or stable event ID across independent pollers: a single event across a minute boundary can get different keys, while repeated heightless events can collide after resets. Coin identity is absent. Cross-process UserDefaults claim atomicity also needs dedicated acceptance proof. These remain core-owned release gaps, not fixed merely by forwarding height/uptime arguments.
- Full signed App Group interoperability, real notification delivery, iOS 17 runtime confirmation presentation/cancel, macOS status-item/popover/login runtime, signed installation/notarization, and release archives remain separate release gates. Unsigned builds and isolated fixtures do not establish those outcomes.
- No real miner control or live fleet acceptance was attempted or authorized by this remediation task.

## Follow-up coordinated release validation, 2026-10-19

This section supersedes the provisional status above for the current working tree while preserving the historical receipts and their limitations.

- All actionable Astra findings in the remediation scope are addressed across the core, CLI, iOS, Mac menu-bar, packaging, and shared block-identity paths. The shared observer now persists boot identity and event sequence, gives flag edges and counter increases distinct event identities, reuses an identity for replay, and drops event identity across a detected reboot. New tests cover reset, flag replay and distinct episodes, and counter replay and distinct events.
- App Push Provider is disabled in `Debug`, `Release`, `DebugNoAppPush`, and `ReleaseNoAppPush`. The current `HashFleet` app target has no PushProvider dependency and the final iOS product has no embedded `PushProvider.appex`. The PushProvider target, source, and legacy entitlements remain in the repository for a future separately approved release.
- XMRig is hidden for this release through `FleetReleaseFeatures.xmrigEnabled = false`, including add choices, dashboard/sidebar cards and totals, detail navigation, and history inputs. Saved data, adapters, CLI/core implementation, and future-feature tests remain available for a later release.
- Final real-project checks passed: 252 core tests in 26 suites, `hashfleet` build and `--help`, unknown CLI option exit 64, diff check, iOS Release product build, Mac menu-bar Release build, no-push test build, and the focused real iOS telemetry suite with 21/21 tests. The five packaging regressions and shell syntax checks also passed.
- Remaining release gates are distribution-level, not source-level: no signed archive, App Store upload, notarization, real push delivery, signed App Group interoperability, installed companion/login lifecycle, or broad UI acceptance was performed. The historical simulator host-force-quit results remain preserved above. The original Opus attempts were incomplete and are not represented as completed review evidence.
