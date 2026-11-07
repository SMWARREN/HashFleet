# Final Hash Fleet acceptance record

Date: October 3, 2026

## Outcome and interpretation

The requested outcome was interpreted as: retain the phone layout while improving Mac responsiveness, complete the Easy and Pro control work, preserve the advanced editor safety contract, deploy the current app to the paired iPhone and Mac, and provide a persistent native Mac menu-bar companion that reads the app's shared aggregate. No physical miner mutation was authorized or performed.

The production and acceptance changes are committed in `8c1ad2c`. Build 6 is installed on the paired iPhone and in the Mac wrapper. The native Mac companion is installed and running. The physical iPhone UI launch is the only externally blocked acceptance step because the device remains passcode locked.

## Requirement-to-check traceability

### Easy and Pro controls, P1 and E1-E19

The complete requirement definitions remain in `EASY-PRO-WHOLE-RESULT-AUDIT-2026-10-02.md` and the product contract remains in `EASY-PRO-CONTROLS-2026-10-02.md`.

| IDs | Concrete real-app checks | Observed result on October 3 |
| --- | --- | --- |
| P1 | Generic-device signed build, strict codesign verification, entitlement inspection, `devicectl` install, independent installed-app inventory | `app.hashfleet` version 0.1.0 build 6 is installed. The NoAppPush artifact contains the app-group and Wi-Fi entitlements and does not contain `app-push-provider`. Launch was attempted and rejected only because the iPhone was locked. |
| E1-E2 | `ExpertModeUITests.testNormalAndDeveloperModesShowTheRightMinerTools`, Normal-mode restart case, Easy/Pro draft case | Easy/Pro presentation boundaries passed. Pro did not reveal Developer-only write tools or grant a power-user session. |
| E3-E5 | `ExpertModeUITests.testEasyAndProPreserveDraftAndExposeReadOnlyDiagnosticsWithoutWrites` plus native Easy settings tests | Pending summaries, reported-before/proposed-after rows, draft preservation, and changed-field-only review passed with an empty write journal. |
| E6 | Native tuning, swarm settings, request-safety, and invalid-draft cases | Invalid and missing values did not fabricate payload fields or bypass review. |
| E7-E12 | Easy/Pro UI diagnostics, compatibility route, and native diagnostics cases | Reported identity, firmware, configured versus measured electrical values, cooling, errors, freshness/source wording, full diagnostics, and compatibility remained read-only and reachable. |
| E13-E17 | Normal/Developer routing, offline cached settings UI, typed restart confirmation, direct safe hostname apply, and power-user lifecycle UI cases | Everyday routes remained available. Risky routes retained Developer gates. Cached settings stayed non-writable. Restart remained reviewed. The bounded power-user lifecycle and safe-hostname path passed. |
| E18 | App XCTest and core package suites | Dashboard, monitoring, persistence, ticker, telemetry database, and integration regressions passed. |
| E19 | Route-gating and catalog safety cases | No preset, automatic recovery, self-test, OTA, multi-miner write, or physical hardware operation was introduced or exercised. |

Eight mapped end-user control workflows passed across the real app UI: role boundaries, Normal typed restart, Developer reviewed restart, Easy/Pro draft and diagnostics, custom JSON staging and cancellation, offline cached settings lock, power-user lifecycle with direct hostname apply, and safe direct hostname apply.

### Advanced editor layout, D1-D6

The detailed controlled diagnostic remains in `ADVANCED-EDITOR-LAYOUT-2026-10-02.md`.

| ID | Concrete check | Observed result |
| --- | --- | --- |
| D1 | Real custom JSON editor entry and reachable Format/Done controls before and after input | Passed on the tested simulator. The top-bar toolbar remained usable with finite layout geometry. |
| D2 | Real staging of nested unknown fields and UInt64 maximum plus native validation cases | Exact nested values and all UInt64 digits were retained. Invalid payload classes remained rejected. |
| D3 | Typed confirmation and cancellation through the actual staged-review path | Staging did not authorize the write. APPLY remained required and cancellation produced no write. |
| D4 | The eight mapped UI workflows and native permission/freshness/preflight suites | Main and edge permission boundaries remained intact. |
| D5 | Strict signed packaging checks and repository diff/commit review | Build 6 packaged the retained implementation without the restricted app-push entitlement. |
| D6 | Final native log scans | No `Invalid frame dimension`, background publishing, Main Thread Checker, Thread Performance Checker, or compiler `error:` signature was found in the final logs. |

The background publishing warning was addressed by receiving the affected notification publishers on the main run loop. The final warning scan was clean.

### Responsive dashboard and detail workflows

The earlier contract is in `RESPONSIVE-CARDS-ACCEPTANCE.md`. October 3 acceptance re-exercised the real project after the latest changes.

| Requirement | Concrete check | Observed result |
| --- | --- | --- |
| Initial compact viewport | `CompactDashboardUITests.testInitialViewportShowsMinerBeforeSecondaryInformation` | Passed after compact spacing and quick-control layout correction. The first complete miner content and intended two-plus-one quick-control grid fit the acceptance geometry. |
| Numeric best share | Compact dashboard numeric-share workflow | Passed with the actual formatted share output. |
| Add-miner discovery and manual fallback | Compact dashboard discovery workflow | Passed. Discovery remained explicit and the manual path remained available. |
| Power and supply voltage | Compact dashboard power/voltage workflow | Passed with reported units and honest missing values. |
| Pull-down miner search | Compact dashboard search workflow | Passed for hidden initial state, reveal, filtering, and result selection. |
| Dashboard card interactions | Ten dashboard/card workflows | 10 of 10 passed for independent collapse, routes, critical output, and accessibility behavior. |
| Stale cooling telemetry | `MinerCardInteractionUITests.testCoolingCardReviewKeepsFaultsAndFreshnessAndNeverWrites` | Passed. Cached values remained readable, the review action remained locked while stale, and no write occurred. |
| Pool integrations | Configured pool preset and explicit offline demo lookup workflows | Passed. The prior pool-page escaping-ViewBuilder crash did not reproduce. |

## Regression totals

Final green results were:

- App XCTest target: 5 tests passed, 0 failures.
- HashFleetCore XCTest: 13 tests passed, 0 failures.
- Swift Testing package suites: 198 tests in 23 suites passed.
- Final native warning scan: clean.

The result logs are retained at:

- `/Users/USER/.jcode/scratch/hash-fleet-native-final-20261003.log`
- `/Users/USER/.jcode/scratch/hash-fleet-core-final2-20261003.log`

## Deployment acceptance

### Paired iPhone

- Device: paired physical iPhone 14 Pro Max, UDID `YOUR_DEVICE_ID`; `devicectl` reported it connected during the October 3 revalidation.
- Independent installed-app inventory reported Hash Fleet `app.hashfleet`, version 0.1.0, build 6.
- Artifact: `/Users/USER/.jcode/scratch/hashfleet-device-build6/Build/Products/DebugNoAppPush-iphoneos/HashFleet.app`. A second device-targeted build at `/Users/USER/.jcode/scratch/hashfleet-mac-build6/Build/Products/DebugNoAppPush-iphoneos/HashFleet.app` independently reported the same bundle identifier, version, and build.
- Strict signature verification passed for both build-6 artifacts. Entitlement inspection found the expected App Group and Wi-Fi access and no app-push-provider entitlement.
- Live lock-state inspection reported `passcodeRequired: true` and `unlockedSinceBoot: true`.
- A direct physical-device launch was attempted. SpringBoard denied it specifically with the locked-device reason, confirming the installed bundle was addressed but foreground launch could not cross the device security boundary.
- `app.hashfleet.iphone-launch-on-unlock` is loaded with `RunAtLoad` and a 10-second interval. While the phone remained locked, its observed run count advanced from 161 to 162 with exit code 0, the success marker remained absent, and no false launch success was recorded. The agent therefore remains armed and will unload itself only after a successful build-6 launch.

This closes artifact, signing, installation, connectivity, locked-state failure handling, and retry-scheduling acceptance. Physical-device UI observation remains acceptance-blocked until the owner unlocks the phone.

### Mac app and menu-bar companion

- Mac-compatible Hash Fleet build 6 is installed inside `/Applications/Hash Fleet.app` and running as a newly launched build-6 process.
- The previous build 5 was backed up before replacement.
- `/Applications/Hash Fleet Menu Bar.app` is installed, signed, and running under a direct `KeepAlive` LaunchAgent.
- The earlier open-and-exit LaunchAgent was backed up and replaced with a direct executable service. A controlled termination restarted the companion automatically under a new PID, proving persistence rather than inferring it from configuration.
- The reproducible repository workflow is `Scripts/hash-fleet-menu-bar.sh`, documented in `docs/MAC-MENU-BAR-COMPANION.md`. Missing-app protection, render/plist validation, uninstall, reinstall, status, and idempotent reinstall all passed. The corrected lifecycle ended with `MENU_BAR_LIFECYCLE_PASS` and left the service running.
- The main app published a fresh non-demo shared aggregate with 4 of 4 miners online. The companion reads the same App Group record and refreshes its compact title and popover every 2 seconds.
- The companion's status title contract is `online/total` plus compact hashrate, with an accessibility label containing Hash Fleet, online count, hashrate, and stale state.
- Process, signature, App Group data, refresh timestamp, source-to-storage integration, and automatic process restart were directly verified. A later direct desktop acceptance pass captured the visible orange Hash Fleet logo and compact title in the real macOS menu bar, opened the real popover, and observed the four grouped miner rows while telemetry changed.

#### Direct installed-app closure at 08:37-08:50 local time

The final feedback-loop pass exercised the installed applications rather than relying on source inspection:

| Requirement | Direct check | Observed result |
| --- | --- | --- |
| One persistent system item | Counted the visible Hash Fleet menu extra, quit the main app, and inspected the companion process and LaunchAgent | Exactly one menu item remained. The direct companion service stayed running after the main app exited. |
| Explicit hide and restore | Used **Preferences → Mac menu bar → Show fleet status** in the installed main app | The item disappeared when disabled and returned when enabled. No dashboard ticker appeared. |
| Logo and compact aggregate title | Inspected the real macOS menu bar | The orange Hash Fleet logo appeared beside the fixed-width `online/total` and compact hashrate title. |
| Compact grouped popover | Opened the real system popover | The popover showed aggregate hashrate, online count, power/freshness, and four compact miner rows grouped in one panel. |
| Stable anchor | Left the popover open through multiple two-second refreshes | Live digits changed without shifting the status item or popover anchor. |
| Responsive installed Mac app | Resized the rebuilt app to 1650×1050, 1100×760, and 760×700 | Large and medium layouts remained intact. The compact pass exposed a sidebar-footer overlap, which was fixed by giving the footer dedicated layout space. A rebuilt signed app then showed all final navigation rows reachable by scrolling above the pinned footer. |
| Installed artifact and service interfaces | Ran strict codesign checks, inspected entitlements, ran `status`, rendered and linted the plist, linted the installed plist, and inspected `launchctl` | Both installed apps verified strictly, both contained `group.app.hashfleet.shared`, the service was running its installed executable, and both plist checks passed. |

The pre-fix payload and the first accepted rebuilt payload were retained for rollback at `~/Library/Application Support/Hash Fleet/Backups/HashFleet-before-compact-sidebar-20261003-0848.app` and `HashFleet-before-final-source-20261003-1007.app`.

#### Exact-final-build end-user replay at 10:10-10:12 local time

After installing the exact source represented by commit `dc9d4ac`, the real end-user path was replayed once more. Opening **Preferences** from the installed app exposed **Show fleet status** as enabled. Switching it off changed the visible control to off and removed the 128-point system item while the companion remained alive as PID 45811. Switching it on restored the system item at `(1383, 0, 128×39)`.

Opening that restored item produced the actual companion popover at `(1254, 31, 366×338)`. It showed the orange Hash Fleet logo, 4/4 status, 21.08 TH/s, 277 W, and four live miner rows in one grouped panel. Five seconds later the same popover retained exactly the same bounds while its freshness advanced from 1 minute 19 seconds to 1 minute 43 seconds, directly confirming a stable anchor during live updates. Quitting the main app then removed the `HashFleet` process while the companion remained PID 45811 and the system item and open popover remained present. This closes the exact-final-build traceability loop through the public Preferences control, the macOS menu-bar boundary, and the separate companion lifecycle.

#### Installed Mac responsive and reconnect closure at 15:00-15:11 local time

A final direct pass used the running build-6 Mac application with all four tracked ASICs online. The app was resized and exercised at 760×700 and 1500×1050 points without using the toolbar refresh control during the observation sequence.

| Requirement | Direct or executable check | Observed result |
| --- | --- | --- |
| Compact navigation and text wrapping | Opened Overview, Network & Chain, Energy & Efficiency, Achievements, Reports & Export, Backup & Restore, Settings, and a real Naja Duo detail from the 760×700 window | Every destination opened. Titles, explanatory copy, live values, warnings, and action labels stayed inside their cards. Sidebar rows remained reachable above the pinned fleet footer. |
| Compact detail reachability | Scrolled the real Naja Duo detail from summary cards into Tuning, Cooling, Pools, four quick actions, Identity & firmware, electrical cards, and cooling telemetry | Lower content and controls were reachable. The two-column and full-width quick-control arrangement remained balanced, and the app did not clip the right column. No control was activated. |
| Wide balanced composition | Resized the same running app to 1500×1050 and opened Overview | Four miner cards formed a balanced three-plus-one adaptive grid. Best Share and Blocks & Achievements formed an equal-width pair, Total Power and Efficiency formed a second equal-width pair, and the history card remained full width. The hero, chain card, sidebar, and footer retained stable alignment. |
| Automatic live refresh | Observed the same running UI across the navigation and resize sequence without pressing refresh | Sidebar and overview hashrates changed between captures while the fleet remained 4/4 online. The App Group preferences file also advanced to 15:07 local time, confirming continued aggregate publication for the separate menu companion. |
| Automatic reconnect state and result replacement | Ran `FleetStoreTests` and `FleetTelemetryCompletenessTests` through the production app test target on the booted iPhone 17 Pro simulator | 43 tests in 2 suites passed. Named cases established automatic bootstrap until a snapshot is fresh, preservation of the prior failure while reconnecting, per-miner recheck before publishing online/offline results, exclusion of failed miners from current totals, and stale-info-plus-new-error handling. `foregroundReconnectChecksEachMinerBeforeShowingItsConnectionResult` specifically transitions one fixture back to online and leaves the failing fixture offline after `runMonitoring()` without a manual refresh action. |
| Packaging and companion continuity | Inspected the installed main wrapper and menu companion metadata, signatures, running processes, and `group.app.hashfleet.shared` defaults | Main `app.hashfleet` and companion `app.hashfleet.menubar` remained signed by team `SAXTXFFJ77`, version 0.1.0. The companion remained running as PID 45811, visibility stayed `always`, and shared glance, snapshot, device, and active-until records were present. |
| Live integration boundary | Performed fresh read-only `/api/system/info` and `/api/system/logs` checks for `.215`, `.221`, `.226`, and `.232`, plus the documented SSH/XMRig checks for the M1 host before using fleet state as evidence | All four ASICs and the M1 host were observed. `.221` had rebooted around 18:44:58 UTC and resumed accepted shares. The app later showed 4/4 online. No outage was deliberately injected because doing so would disturb live monitoring and could affect mining operations. The executable reconnect check above therefore supplies deterministic failure-to-result acceptance, while the installed UI supplies real automatic-refresh evidence. |

The focused reconnect log is retained at `/Users/USER/.jcode/scratch/hashfleet-reconnect-acceptance-20261003.log`. The first attempted macOS-destination rerun was blocked by the currently installed provisioning profiles, so the accepted rerun used the booted simulator and the `DebugNoAppPush` configuration. This is a packaging constraint on that test destination, not a product test failure.

#### Mac visual scale follow-up at 15:15-15:23 local time

The Mac presentation now uses a one-step larger minimum semantic text size, larger sidebar typography and status indicators, a larger fixed Lucide settings icon, taller desktop rows and controls, and a wider 380-point preferred sidebar. Existing user-selected accessibility sizes are never reduced, and iPhone/iPad sizing is unchanged. The updated signed build was installed after preserving the previous inner app at `~/Library/Application Support/Hash Fleet/Backups/HashFleet-before-mac-visual-scale-20261003-1520.app`.

`FleetAdaptiveLayoutTests` passed 6 tests, including explicit checks for Mac-only scaling, unchanged non-Mac values, and preservation of accessibility Dynamic Type sizes. The updated installed app was then exercised at a compact normal window and at 1500×1050. Sidebar names, addresses, metrics, footer, card titles, values, action icons, and explanatory copy remained readable without observed clipping, while the wide detail view used the available desktop area more confidently.

## Boundaries

No live ASIC settings, pools, voltage, frequency, fan configuration, firmware, self-test, restart, recovery, wiring, wallet, password, Wi-Fi secret, or private key was read or changed for this acceptance. Simulator and loopback transport checks validate the application path, not the physical safety or correctness of a miner operation.
