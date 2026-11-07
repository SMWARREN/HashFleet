# Firmware telemetry and fleet activity

Implemented October 24, 2026. These are read-only presentation changes, not a firmware updater or a hardware tuning recommendation.

The later navigation correction on October 24 removes the primary app's added bell, activity display submenu and activity-list picker. Historical acceptance receipts below describe their original checkpoints, not the current navigation. See `NAVIGATION-AND-SESSION-OPTOUT.md` for the latest correction and checks.

## iPhone, iPad and the primary Mac app

- Open **App settings** and expand **Notifications and banners**. The controls stay on App settings instead of opening a Notifications subpage. Previews appear above that same settings screen, and **Keep mining** returns to the controls and scroll position you left.
- **Session-best alerts** uses the same illustrated miner popup as all-time records while the app is open. The popup stays until dismissed, rather than using a brief session-record toast. Records from other miners wait in order instead of replacing the popup being read. Ordinary safety/status banners and background system notifications retain their existing delivery routes.
- **Preview session-best popup**, **Preview high-score celebration**, and **Preview block-found celebration** let you inspect each presentation without generating a mining event or changing alert choices.
- The dashboard uses its original brand, title, settings menu and add button. There is no added bell, Fleet activity entry, Activity display submenu or session-alert toggle in that menu.
- A session popup offers a quiet **Turn off session-best alerts** action. It dismisses current and waiting session popups and saves only the session preference. It does not mute all-time records, blocks or safety/status alerts. Re-enable **Session-best alerts** inside the existing App settings notification controls.
- The overall **Best-share alerts** switch must remain enabled for either kind of best-share alert. Existing explicit opt-outs are preserved.
- New installations enable best-share and session-best alert preferences. This does not bypass system permission, Focus, background scheduling, or the app's one-channel delivery rules. Unrelated alert defaults do not change.
- A session-best share is not a claim that a block was found. The native Mac companion's display choices do not enable alerts.
- Cached, failed, reconnecting or expired live session readings are not presented as current. Demo data is explicitly marked.

Open a miner's detail screen for **ASIC hashrate** and **Pool connection**. Supported firmware reports `hashrateMonitor.asics[].domains` in GH/s. Nominal references divide the reported aggregate `expectedHashrate` by the complete domain count, rather than assuming a model's domain geometry. Old or malformed geometry is unavailable, not zero.

Domain history consists only of observed foreground snapshots on that detail screen. It is bounded, in-memory and not a device-side statistics log. The horizontal axis orders observed samples, not uniform elapsed-time intervals. Dashed lines show the current nominal reference. A miner identity, firmware, uptime-session or domain-topology change resets the history. Cached, failed, reconnecting or stale frames are not new samples. Opening the view does not fabricate historical points or send additional device requests.

Pool banners and primary-pool reasons are bounded, stripped of control characters and redacted. Fallback selection must be explicit. Transport labels describe the selected pool's configuration, not verified encryption or a successful TLS handshake. Malformed/duplicate slot tables fail closed instead of borrowing a legacy primary-pool setting.

## Native Mac menu-bar companion

The actual `HashFleetMenuBar` popup retains **Notifications**, **Session best**, and **Both**, defaulting to Notifications. Its choice is saved independently of alert delivery and visibility. It can also be changed in the primary Mac app's Fleet preferences under **Mac menu bar**. The primary-app header correction does not remove or redesign this separate native companion.

Base fleet metrics and health notices remain visible regardless of this cosmetic choice. Session records are explicitly labeled and suppressed as current when the shared snapshot is stale or the miner is offline. Older cached payloads decode without the new optional fields. The fixed-width status item remains stationary, and the popup scrolls instead of clipping extra rows.

The companion reads the primary app's bounded presentation cache. Recent notifications are at most eight event-inbox summaries, not system Notification Center history. They follow current effective alert choices, so disabling an alert kind can hide its older summaries without deleting the underlying inbox. The companion does not contact miners, post miner alerts, or keep telemetry live after the app stops publishing. Use the primary app's notification settings to control delivery.

## CLI

```sh
swift build --product hashfleet
.build/debug/hashfleet status gamma.local
.build/debug/hashfleet status --details gamma.local
.build/debug/hashfleet status --json gamma.local
```

Text status includes separate **BEST (ALL)** and **BEST (SESSION)** columns. `--details` adds pool routing, safe pool messages, configured transport and each reported ASIC domain's measured and nominal rates. It prints a single response, not a historical sparkline. Missing data is `--` or Not reported.

`--json` preserves the existing full raw status schema, including unknown firmware fields. It is an advanced diagnostic export and can contain sensitive device information. It is an alternative to `--details`, not a promise that raw JSON is redacted. Offline exits, invalid-usage errors and corrupt-fleet discovery protection remain unchanged.

## Reproducible checks

```sh
swift test
python3.12 -B Scripts/tests/test_cli_firmware_activity.py
xcodegen generate
xcodebuild -project HashFleet.xcodeproj -scheme HashFleetMenuBar \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project HashFleet.xcodeproj -scheme HashFleetNoAppPush \
  -configuration DebugNoAppPush \
  -destination 'platform=macOS,arch=arm64,variant=Designed for iPad' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project HashFleet.xcodeproj -scheme HashFleet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HashFleetUITests/NotificationAuthorizationGrantUITests \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project HashFleet.xcodeproj -scheme HashFleet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO -only-testing:HashFleetTests \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project HashFleet.xcodeproj -scheme HashFleet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO -only-testing:HashFleetUITests/FleetActivityUITests \
  CODE_SIGNING_ALLOWED=NO test
```

Choose an installed simulator destination from `xcodebuild -showdestinations -scheme HashFleet` when reproducing. The primary Mac app is the iPad app running on Mac, not a native macOS binary. Its valid compatibility destination builds with an iPhoneOS SDK. Only the separate `HashFleetMenuBar` target is native macOS.

The simulator-only provisioning command above must precede the real-system delivery tests.

The helper uses the real **Send a test notification** action and taps the system **Allow** prompt. It verifies both the authorized state and successful request scheduling. UI-testing launch mode intentionally does not request permission automatically. Keep this provisioning run and the subsequent real-system tests on the same isolated simulator, without parallel cloned destinations. A previously denied permission is a setup failure, not a passing delivery result.

Native suites include `FleetActivityPresentationTests`, `FleetActivityDeliveryTests`, `SessionBestNotificationPreferencesTests`, `FleetNotificationSettingsTests`, `FirmwareTelemetryHistoryTests`, `FleetFirmwareTelemetryRenderTests`, and `FleetActivityUITests`. Simulator tests use demo/loopback data, not real miner writes. The current UI suite checks the restored original header/menu, the quiet session-popup opt-out, independent preferences with relaunch/re-enable, and accessible popup controls. The superseded primary activity-menu scenarios below remain historical receipts, not the current acceptance contract.

Source parsing was checked against the local frozen ESP-Miner fleet source `d8511a14`, particularly `main/http_server/system_api_json.c`. This is field compatibility evidence, not a claim that all firmware/board combinations have been tested. No miner settings, service configuration, firmware or power wiring are changed by these features.

## Initial feature validation: October 24, 2026

| Scope | Observed result |
| --- | --- |
| Complete Swift package | 260 tests in 27 suites passed |
| Actual CLI with a loopback HTTP fixture | 7 tests passed, including raw JSON compatibility, missing session values, sanitized details and usage/offline exits |
| Final affected native scope | 158 tests in 15 suites passed, including preferences, delivery/permissions, old payloads, history/provenance, rendered views and report capture |
| Final activity UI | 4 tests passed: all display modes and relaunch persistence, dashboard-menu selection, menu-to-popup alert-toggle propagation, and largest-text/desktop reachability |
| Primary Mac app | Designed-for-iPad arm64 build succeeded after the last popup edit |
| Native Mac companion | The separate `HashFleetMenuBar` macOS target built successfully |

The final native acceptance bundle is `activity-hardened.xcresult`, with `ios-hardened.log`, `primary-mac-hardened.log`, `mac-final.log`, `core-final.log` and `cli-final.log` under `$JCODE_SCRATCH_DIR/hashfleet-activity-20261024`. Actual final phone and large-text screenshots were exported to `hardened-ui-review` and visually inspected. Builds used Xcode 27.1; simulator interaction used an iPhone 17 Pro on iOS 26.5.

The initial broader native audit was **not green**. Its retained `activity-full-final.xcresult` receipt contains 21 failing tests before the affected-scope corrections. Old default assumptions were updated with explicit opt-out fixtures and fresh-default coverage. A report observation-clock defect exposed by that run was fixed without changing its existing acceptance assertions. Those corrected scopes passed in `activity-hardened.xcresult`. At that checkpoint, unchanged layout-inset and background-recovery checks, and real Notification Center tests blocked by missing simulator authorization, remained outside the passing scope. This initial record is not a full-suite success claim. Subsequent closeout evidence is recorded below rather than replacing the failures.

An earlier final attempt also recorded one missed popup-switch tap. The same original test passed three unchanged diagnostic repetitions. The popup's periodic freshness clock was then restricted to read-only values, leaving controls outside it. Original switch-off/persistence assertions were kept, the menu propagation check was added, and the final affected-scope run passed. This hardens the view lifecycle without claiming proof of that intermittent failure's cause.

These are local source, fixture, simulator and build results. No production application or CLI was installed, no store release was submitted, and no physical miner behavior or physical-device notification delivery was certified. The native Mac companion was not launched against the user's installed service during this task, avoiding duplicate status items and changes to live shared preferences.

## Workflow closeout: October 24, 2026

- `recovery-before.xcresult` reproduced the unchanged background-recovery failure and added regression cases for complete and partial identical telemetry. An in-memory healthy reading could suppress recovery even after a background store had persisted an offline baseline. Commit `479543d` reconciles that offline state before deduplicating identical payloads. The original assertion was preserved. The added cases also require that the next identical reading does not announce recovery again and that partial telemetry does not invent a fresh complete-snapshot timestamp.
- Commit `565daa1` repairs the authorization provisioning helper, not the production permission policy. `notification-permission.xcresult` records the actual simulator system prompt and the authorized/scheduled state. Its exported screenshot in `permission-review` was visually inspected. Only the isolated iOS 26.5 simulator's app permission changed, not the host Mac's or a production installation's permission.
- `recovery-system-after.xcresult` passed 82 native tests in five suites, including all 10 unchanged real `UNUserNotificationCenter` delivery tests, recovery replacement, status clearing, ordinary duplicate telemetry and the complete/partial recovery regressions. This proves real simulator request processing, not a guarantee of banners, sounds, Focus behavior or physical-device delivery.
- The known layout contract conflict is preserved: `FleetAdaptiveLayoutTests.macPagesShareOneThirtyPointSideInset()` expects a 16-point phone dashboard inset, but commit `f33cf37` deliberately changed the production inset to 12 points on October 11, 2026. The Mac margin remains 30 points. Neither the design nor this acceptance assertion was changed just to obtain a passing audit.
- Both Mac builds passed again after the recovery fix. `primary-mac-workflow-final.log` covers the arm64 Designed-for-iPad compatibility app and `companion-workflow-final.log` covers the separate native macOS menu-bar companion. These remain build receipts, not production installation or live status-item runtime checks.
- The finalized full native unit audit is `workflow-units-final.xcresult` with `workflow-units-final.log`. Its test summary reports **1,194 passed, one failed, zero skipped**. The log records 1,190 Swift Testing tests in 107 suites plus five XCTest tests. The sole failed test is the preserved layout-inset contract above. Background recovery, actual simulator Notification Center delivery and the new activity/telemetry tests pass in this whole-unit run. Runtime warnings are retained in the receipt, so this audit is neither fully passing nor warning-free.
- `workflow-ui-final.xcresult` and `workflow-ui-final.log` passed **all five UI tests, zero skipped**: the four activity acceptance tests plus a repeat of the real-permission provisioning flow. The repeat verifies an already authorized simulator still reports actual authorization and schedules the test request. Final normal-text, largest-text and permission screenshots were exported to `workflow-ui-review` and visually inspected.

An earlier combined unit-and-UI invocation hit the tool's 600-second deadline during UI execution, after its unit tests finished. `workflow-final.log` and the incomplete `workflow-final.xcresult` directory are retained only as interrupted diagnostics, not as a finalized acceptance bundle. Full units and activity UI are run separately to obtain complete receipts without removing assertions or masking the layout failure.

The requested feature workflow is implemented and locally validated within these boundaries. The unresolved pre-existing design/test contract prevents a fully green whole-app audit. Production installation, a store release, physical-device alert certification and changes to mining hardware or services are not part of this closeout.

## Inline-settings and session-popup correction: October 24, 2026

The subsequent correction keeps notification controls inside App settings and routes session records through the existing illustrated miner popup rather than a brief session-record toast. Preview dismissal preserves the settings screen and its scroll position. Its optional primary-app bell and list controls were subsequently rejected and removed by the navigation correction documented in `NAVIGATION-AND-SESSION-OPTOUT.md`.

`SESSION-POPUP-CORRECTION.md` maps these requirements to the retained receipts: 127 focused native tests, 10 actual simulator Notification Center tests, and 11 distinct UI scenarios have passing results across the scoped runs. It also records the repeated popup checks, the two final preference/search passes using observed native-switch controls, the Mac compatibility build, and the earlier failed attempts. This is not a new fully green whole-app audit and does not change the existing phone-inset design/test conflict or authorize production installation.
