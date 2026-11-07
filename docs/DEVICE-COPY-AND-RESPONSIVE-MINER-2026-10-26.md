# Device copy, responsive miner cards and transient menu navigation

Date: October 26, 2026 (UTC). Scoped UI follow-up to the approved native installation recorded in `MAC-NATIVE-INSTALL-2026-10-26.md`. Implementation and regression tests: `519c5d1`.

## Scope and safety boundary

This change corrects current-host wording, the Mac status-item title, miner-card sizing and actionable hit areas, and status-popover destination selection. It does not change mining behavior, settings-write authorization, firmware, saved miner identities, history linkage or monitoring services.

The installed real-data Mac app was not replaced, relaunched, activated or navigated during this follow-up. No hardware commands or live fleet checks were performed for these UI checks. All runtime UI fixtures use isolated Demo/testing flags. The native render runner uses a separate defaults suite, a network-blocking session, prohibited activation and no windows. This report makes no claim about current fleet telemetry or full installed-app acceptance.

## Implementation

- `FleetDeviceCopy` derives current-host identity from the actual platform and, on mobile, `UIDevice` idiom. Narrow iPad windows do not become iPhones. Shared onboarding, discovery, preferences, About, monitoring and notification copy uses the appropriate Mac/iPhone/iPad and macOS/iOS/iPadOS terminology.
- Notification copy retains permission and delivery caveats. On Mac, closing the workspace leaves app monitoring running and quitting stops local checks. On mobile, background refresh remains best effort, not continuous monitoring. A test notification explicitly does not test miner connectivity or background refresh. Legitimate companion-app references remain.
- `FleetMacChrome.statusTitle` preserves the existing compact count/hashrate and Demo/stale/disconnected disclosures without prepending the app name. The status-item icon remains.
- `FleetMinerDetailGrid` measures contents at actual cell widths, gives siblings their row's tallest natural height, uses real item counts instead of empty adaptive columns, fills an odd last row and balances four actions as 2-by-2 until all four fit. Accessibility layouts select one column. There are no fixed equalizing card heights or whole-page scale transforms.
- Metric surfaces and action labels fill their proposed row height. Shorter collapsed content is vertically centered. Expanded reading sections retain top alignment. Best shares/identity and diagnostics/pools use the same row measurement policy.
- Navigation-link and disclosure labels own their full width, padding and empty height. Settings links remain independent controls. Reading-only metrics have not been given invented actions. Demo review forms still disable command submission.
- Status-popover miner and notification rows resolve the destination by UUID. Selection closes the transient popover before opening that destination. Missing/deleted identities fall back to Overview. This does not indiscriminately hide the persistent sidebar.

## Requirement-to-check mapping

| Requirement | Concrete checks and limits |
| --- | --- |
| Correct current-host wording | `FleetDeviceCopyTests` checks explicit Mac/iPhone/iPad policies, actual host identity and notification-model integration. Existing notification permission, saved-choice and local-delivery tests retain their behavioral assertions. Source audit distinguishes genuine companion references. |
| Compact status-item title | `FleetNativeBrandingTests` and `check-native-chrome.swift` retain count/hashrate, Demo and stale assertions while rejecting the app-name prefix. This is not a live system-status-item click test. |
| Fluid, equal-height rows | `FleetMinerDetailGridTests` covers 320/480/728/1028/2056-point widths, full trailing edges, balanced action rows, taller siblings, actual-width measurement for an odd last item, explicit single-column policy and nonfinite/negative inputs. Native production-view geometry/pixel checks cover paired surfaces in both appearances. |
| Whole-card interactions | iPad UI acceptance uses lower-right padding coordinates for all four quick actions, asserts the correct review destination and disabled Demo send button, returns to detail, checks original best-share reading IDs, compares metric pairs, toggles diagnostics away from the chevron and opens the full diagnostics tool row in portrait and landscape. |
| Largest-text behavior | A separate mounted-app UI test launches at `UICTContentSizeCategoryAccessibilityXXXL`, asserts all four action frames stack in one equal-width column at landscape width, taps action padding, checks the Demo write lock and asserts stacked Power/Input-voltage readings. The offscreen runner only establishes enlarged-text growth, not parent-environment column selection. |
| Dismiss transient menu before routing | `FleetMacMenuNavigationTests` checks dismiss-before-open order for eight destinations, child-path reset, UUID distinction and removed/nil identity fallback. Production callback and full-row label wiring were inspected. Physical current-source native popover selection remains deferred. |
| Preserve platform builds and page shell | Genuine native Debug/test and Release builds, mobile app/test build, native bundle validator, shared-page-shell source guard, native navigation source guard and whitespace checks. |

## Verification receipts

Owner-private artifacts are under `/Users/USER/.jcode/scratch/`. These are separate scoped test runs, not one combined test count or evidence of every application workflow.

### Final native source

- `hashfleet-final-native-debug0614.log`: native `HashFleetMac` Debug build-for-testing succeeded after the last production edit, the best-share parent-ID correction.
- `hashfleet-final-native-release0614.log`: genuine native Release build succeeded. `Scripts/validate-native-mac-app.sh` accepts `.build/native-mac/Build/Products/Release/Hash Fleet.app`. This is a build artifact, not a replacement installation.
- `hashfleet-final-native-policy0614.log`: 11 Swift Testing test functions in four suites passed through the isolated no-window package linked to the current Debug app module. The four suites are device-copy policy, responsive detail geometry, command/sidebar navigation and menu-destination navigation. Parameter cases are not added again to the headline count.
- `hashfleet-chrome0612/`: 32 no-window native chrome checks passed, including actual hosted 44-point Menu targets, compact status copy and light/dark rounded surfaces.
- `hashfleet-miner-layout0622/`: final compiled `check-native-miner-layout0622` passed 24 native production-surface/geometry/growth checks, five widths, both appearances and enlarged text, with no windows or activation. This repeats the earlier `0614` render result after clarifying the runner's coverage wording. Root inspected the original `metrics-actions-728-dark.png` and `paired-cards-1028-light.png` renders from `0614`.
- Shared-page-shell guard, native navigation integration guard, native Release bundle validator and `git diff --check` passed after the final runner edit at 06:22 UTC.

### Mobile

- `hashfleet-final-mobile-build0619.log`: final mobile app/test build succeeded after the last production edit and the added largest-text acceptance test.
- `hashfleet-final-ipad0619.xcresult`: **46 passed, 0 failed, 0 skipped**, comprising 44 unit test functions and two UI workflows. The normal workflow covers both portrait and landscape, all four lower-right-padding action taps, review destinations, Demo write locks, original best-share IDs, metric geometry, disclosure-center taps and full tool-row navigation. The second workflow verifies actual mounted largest-text single-column action and reading frames and a padded action tap. Root inspected original largest-text captures in `hashfleet-final-ipad0619-attachments/`. This is scoped changed-card acceptance, not a whole-sidebar accessibility audit.
- `hashfleet-final-iphone0629.xcresult` and `.log`: **56 passed, 0 failed, 0 skipped**, across device copy, grid geometry, notification settings, notification test delivery and the complete selected `MinerDetailRenderingCoverageTests` suite. The unchanged final artifact completed with `TEST EXECUTE SUCCEEDED` and command exit 0 in 52.4 seconds. `-collect-test-diagnostics never` avoids the earlier stalled collector without disabling tests, failures, screenshots or assertions. Package resolution/update suppression was also used for the existing resolved dependencies.
- Preceding `0611` artifacts passed 45 iPad tests and 56 iPhone unit/render test functions with no failures or skips. They remain attributed to that earlier artifact, not added to the final counts.

## Preserved failures and corrections

- `hashfleet-responsive-ipad0603.xcresult` contains a real `EXC_BAD_ACCESS` in `NavigationLink`'s `StateOrBinding` copy beneath `desktopTelemetrySections`, not merely an unsuccessful tap. Its exported `.ips` and attachments are retained in `hashfleet-responsive-ipad0603-attachments/`. Narrow `AnyView` boundaries now isolate the navigation-heavy control subtrees. The unchanged two-orientation workflow subsequently passed in `0606`, and expanded padding-coordinate checks passed in `0611`. This is not proof against every compiler/runtime path.
- Earlier UI output showed a group accessibility identifier propagating onto the four quick-action links. The unused parent identifier was removed, while individual action identifiers and containment semantics remain. The same audit removed an unused new parent identifier that masked existing best-share reading identifiers. Final acceptance explicitly checks those original child IDs.
- `hashfleet-iphone-copy0552.xcresult` retained a failing cooling-tour anchor OCR check. Root inspected the original attached capture and confirmed the full `Cooling anchor published` marker was visible, centered on an OCR tile seam. Only the test marker's alignment was moved to the leading edge. The production anchor and exact positive/missing-anchor assertions were not changed. The full selected phone render suite passed in `0611`.
- `hashfleet-final-iphone0619.log` records all 56 test functions passing, then Xcode failed to finish the result bundle while its `simctl diagnose --timeout=600` child remained active for several minutes. The owned test command was cancelled and its exact orphaned diagnostic-collector PID was stopped. This incomplete bundle is not counted as a clean passing command or attributed to a proven package-resolution cause. The same unchanged final test artifact passed cleanly in `0629` with verbose diagnostics collection disabled.
- Configured review/implementation workers failed before producing coherent work. No successful independent review is credited. Source audit, integration and verification were completed by the root session.

## Deferred acceptance

Actual current-source native window/padding clicks, opening the system status popover and selecting its rows, and full native window-transition/menu acceptance have not been performed because the installed real-data workspace must not be taken over without permission. No claim of operator visual approval for these new changes is made. Legacy-history UUID linkage remains a separately recorded unresolved installation issue and was not altered by this UI patch.
