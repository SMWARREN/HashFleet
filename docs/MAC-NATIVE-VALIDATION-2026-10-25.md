# Native Mac and iPad parity validation, October 25, 2026

## Current acceptance status, updated on October 26 at 04:08 UTC

**The operator approved the latest observed Mac appearance at 03:43 UTC and explicitly authorized both native installation and real fleet data at 03:47 UTC.** The approved `3e66594` native binary is now installed at `/Applications/Hash Fleet.app`, with production sandbox/network entitlements, a bundled native CLI and private rollback backups. The actual production process has no Demo or UI-testing flags. All four real ASICs produce fresh snapshots and new persisted readings. All-five independent read-only checks, including the M1 over SSH, succeeded before and after installation. See [the installation and monitoring record](MAC-NATIVE-INSTALL-2026-10-26.md).

This is **not acceptance of the whole Mac app**. Runtime device UUIDs differ from the immediately migrated list, so old per-device history linkage remains an explicit unresolved acceptance gate even though the original and copied history are intact. The M1 API remains loopback-only and is not added to the four-ASIC UI. Opened menus, full window transitions and other clients remain separate tests. The older pending statements and test results below describe their dated checkpoints, not the current installation. Whole-display takeover remains outside the requested review scope.

The visual reference remains the existing real iPad app: shared semantic font roles, weights, design-point metrics, palette, artwork, card surfaces and formatting. Responsive arrangement can change with available space. Native correction **`dec49a9`** is built and verified by **42 native tests in 12 suites** plus actual full/half-display checks described next. The isolated demo preview was actually reopened for those checks. Test-only correction **`97eec0c`** finishes iPad rate editing with the actual system popover/keyboard controls, preserving the original Save and reading-role assertions. Focused run2146 passed. Final run2148 then passed **91 iPad unit tests in nine suites, all nine selected iPad UI workflows and all three selected phone UI workflows**, with zero failed or skipped tests in both result bundles. This closes the selected mobile regression boundary, not the newly reported native title-bar appearance issue.

### Fleet sidebar corners and original iPad title composition, October 26 at 01:21 UTC

At 00:54 UTC the operator rejected the straight edge above **Fleet** and the native wordmark's appearance. The coordinator compared the supplied genuine iPad About/dashboard images with `hashfleet-brand-open0027-overview.png`. The straight edge is the top of the left navigation surface, not the global macOS Fleet command menu. The iPad dashboard uses a standalone centered **Hash Fleet** headline and separate leading artwork. The running Mac candidate puts the artwork and name inline beside Overview. Restoring the original font size alone had not restored that composition.

The current source clips the complete `FleetSidebarView` list/footer surface to a 24pt continuous rounded rectangle, with an 8pt outer top inset and 8pt inner top breathing room. Clipping only a background would leave the List's straight top visible. This is native-only. The original iPad title and artwork are now actual shared `FleetHeaderTitle` / `FleetHeaderArtwork` views. Native branding uses the system principal toolbar placement for the standalone headline and a separate leading 34pt artwork item, retaining its original 8pt image radius. Dashboard owns one principal title/search slot instead of competing with a second brand item. Existing iPad large-content accessibility behavior, semantic headline, line limit and maximum Dynamic Type category are retained. No alternate rounded typeface, font scaling, custom title-bar view or traffic-light positioning was introduced. Native child-page identity toolbars and normal window/page titles remain unchanged; actual pushed-page/overflow composition still requires a live review.

The bare settings gear also has a detecting production-API result. With activation prohibited and zero windows, a real SwiftUI `Menu` hosted in `NSHostingView` fits **17x17pt** when an inner plain designed-menu style precedes the outer toolbar style. The same real Menu fits **44x44pt** with only `fleetToolbarMenu()`. An explicit-label alternative also collapsed and was not used. Only the conflicting inner designed-menu call was removed from the actual Dashboard settings Menu. That helper was already a no-op on iOS, so its removal does not change the mobile menu styling contract.

Validation at 01:10 UTC: **31 no-activation offscreen/hosting checks pass**, with zero windows before and after. These cover strict black/white chrome, controls and text-action targets, dark/light four-corner clipping at three sidebar widths/heights, actual shared wordmark pixel equality against the original iPad text recipe at three Dynamic Type categories, separate artwork dimensions, real gear/ellipsis Menu target sizes and a detecting negative control for the former inner-plain regression. Four illustrative header-width fixtures also retain opaque black bounds. The command-line fixture cannot load the app's named artwork asset and is not proof of a live toolbar or artwork rendering. The coordinator inspected the 1028pt header component and 300pt dark sidebar component, not a new Mac window capture.

The new production call-site guard failed all eight intended integration seams before the correction (`hashfleet-navigation-detect0105.log`) and passes after it, along with the shared page-shell guard and `git diff --check`. The first strengthened pixel run failed because a new sidebar fixture sampled the continuous curve's antialiased endpoint, observing `[250,250,0]` rather than solid yellow (`hashfleet-navigation-offscreen0109.log`). That failure is retained. Only the straight-edge sampling point moved to the middle of the actual vertical straight edge. Corner assertions, exact colors, tolerances and production geometry were not weakened. The final 0110 run then passed. The generated Xcode project changes only add the two new shared source files to native and iOS target membership.

Implementation **`3e66594`** passes native Release, native `build-for-testing` and fresh iOS `build-for-testing` including the app, widget and phone/iPad test sources. Both compile tasks exited zero. These are compilation results, not new app-hosted test execution passes. The final post-edit source guards, whitespace guard and all 31 no-activation component/hosting checks pass again at 01:19 UTC. No coherent independent worker review was received, so no independent review pass is credited.

The current ad-hoc signed, validated and **unlaunched** candidate is `hashfleet-native-review-navigation-20261026-0119/Hash Fleet.app`. Executable SHA-256: `29d6cdb527948618ef004087b50074ab3fc048030ace754dcafe2fc8a0eadf64`. Scratch artifacts: `hashfleet-menu-probe0101.log`, `hashfleet-navigation-offscreen0110.log`, `hashfleet-navigation-components0110/`, final `hashfleet-navigation-final0119.log` / `hashfleet-navigation-components0119/`, and `hashfleet-navigation-{release,testbuild,ios-testbuild}0115.log`. No current-source app launch, new window capture, native menu opening or maximize/minimize/fullscreen review occurred during this correction. Read-only process inspection at 01:15 UTC still finds **PID3445 running the older brand2251 candidate**. The source correction is not yet visible in that running app. The next review step is refreshing only the normal-sized isolated preview when permitted, not taking over the display. Installation, migration and operator appearance approval remain pending.

### Authorized normal-window preview opening, October 26 at 00:27 UTC

The operator approved opening the corrected preview at 00:25 UTC. The staged brand2251 bundle passed its native validator and expected executable hash check. Only the exact previous isolated demo process PID55140 was terminated after comparing its full command with the known scratch2134 path and demo flags. The latest `fd7c3ee` candidate was then actually opened as **PID3445** from `hashfleet-native-review-brand-20261025-2251/Hash Fleet.app`, retaining `--ui-testing --demo --ui-test-asic-telemetry`. The installed app, real preferences/data and mining hardware were not changed.

Actual AX state at 00:27 UTC confirms one active, visible, main **1280x860pt normal window at (220,120)**, not minimized and **fullscreen=false**, with no fullscreen toolbar companions. The coordinator inspected the real window-only `hashfleet-brand-open0027-overview.png`, not a component fixture: the original logo and visible **Hash Fleet** headline appear in the black header. Saved AX reports `desktop.brandMark` with value Hash Fleet, and read-only application-menu inspection returns Apple, Hash Fleet, File, Edit, View, Fleet, Window and Help. The previously unlaunched status of brand2251 is now historical.

This is not full menu/transition acceptance. The actual Dashboard settings trigger is still a bare gear, with saved AX bounds of 15x15pt versus 52x52pt Find/Add peers. The inner plain designed-menu style and outer toolbar style need follow-up; generic rounded-control rendering did not prove this real menu's target. The later Overview-specific workspace probe failed because the current window title had changed to Electricity estimates. That failure is retained, no passing Overview geometry check is claimed, and navigation was not forced back. No fullscreen/minimize cycle or opened-menu/status-popover review was performed. Operator appearance approval and installation/migration remain pending.

Artifacts in scratch: `hashfleet-brand-open0027-state.json`, `-ax.json`, `-capture.json` and `-overview.png`. The failed probe's redirected `hashfleet-brand-open0028-check.json` is empty, not a valid JSON receipt. Its failure was reported on stderr as `FAIL: Expected window title Overview, observed Electricity estimates`. Only the selected app window was captured, not the user's desktop.

### Original iPad brand sizing and preview clarification, 22:51 UTC

At 22:46 UTC the operator asked whether the updated app had been opened and reported not seeing Hash Fleet as in the iPad app. Read-only process inspection at 22:47 and 22:51 UTC confirmed that the running native preview was still PID55140 from `hashfleet-native-review-even-20261025-2134`. Neither the newer chrome candidate nor the latest brand candidate had been launched at that point, consistent with the background-only instruction then in effect. The later authorized launch is recorded above.

The source comparison also found a genuine parity error in the staged chrome candidate: its 26pt artwork and 13pt Mac-only title were smaller than the original iPad's 34pt artwork, 8pt artwork radius and shared headline role. **`fd7c3ee`** restores those original artwork dimensions and the actual `fleetFont(.headline)` modifier, including the iPad title's existing maximum Dynamic Type category. The native brand remains independent of sidebar visibility. No iPad/phone source was changed in this follow-up.

The added offscreen comparison against the actual shared typography first failed on the smaller staged brand (`hashfleet-brand-detect2248.log`). With the production correction and unchanged detecting assertion, all **20 offscreen checks pass** (`hashfleet-brand-offscreen2249.log` and final2251 log). Native Release and native test compilation also pass (`hashfleet-brand-release2249.log`, `hashfleet-brand-testbuild2249.log`). These are direct component checks and compile-only app-hosted test coverage, not a new live toolbar or native test execution pass.

At that 22:51 UTC checkpoint, the latest validated, ad-hoc signed and **unlaunched** candidate was `hashfleet-native-review-brand-20261025-2251/Hash Fleet.app`, superseding the unlaunched chrome2225 candidate. Executable SHA-256: `0ac70d85226e9f41aa1f9a4c35ae1f8cc66a6b958ad5d66ec651abe0b78a3eb1`. The final component runner verified prohibited activation and zero windows. The source guard/diff checks passed. No app was opened, activated, resized, installed or migrated at that checkpoint. The later authorized 00:27 UTC opening is recorded above. Actual toolbar/menu/window-transition acceptance remains separate.

### Background-only native header correction, 22:25 UTC

**`ccc6a44`** separates native window chrome from the slightly blue shared reading canvas. Both split columns now request an opaque black toolbar in Dark appearance and an opaque white toolbar in the existing Light preference. The native window configuration is idempotent and reapplied on representable updates/effective appearance changes. Fullscreen toolbar visibility is explicit on macOS 15 and later. The real AppKit traffic lights, window geometry, native sidebar toggle, page title and keyboard commands remain system-owned. This is a source correction, not a demonstrated diagnosis of every maximize/minimize lifecycle issue.

The compact toolbar mark now includes visible **Hash Fleet** text regardless of sidebar visibility. Native Overview uses its actual page name instead of repeating the new app-name label. The persistent status item also prefixes its existing complete demo/freshness/telemetry text with **Hash Fleet**, using variable width instead of a fixed 164pt allocation. Read-only AX had already confirmed that the system application menu was named Hash Fleet, so bundle naming was not changed. The existing running preview has not loaded this correction.

Toolbar buttons and menu triggers share a 12pt continuous radius, 36pt visible height, text insets and a 44pt target. They explicitly suppress the additional system glass surround rather than drawing one rounded control inside a second pill. The status panel uses an opaque 16pt rounded surface, matching row/control geometry and the selected app appearance. The system-owned sidebar control is restyled through its default item rather than duplicated. Shared iPad/phone styling paths remain no-ops for these native control helpers.

Background verification after the last production edit:

- `hashfleet-chrome-release2222.log`: **Release BUILD SUCCEEDED**.
- `hashfleet-chrome-testbuild2222.log`: **TEST BUILD SUCCEEDED**, including the three new native brand/window-configuration regression methods. This is compilation only, not execution of those app-hosted tests.
- `hashfleet-chrome-ios-testbuild2222.log`: **TEST BUILD SUCCEEDED** for the app, widget and phone/iPad test targets. No simulator or UI workflow was started for this header correction. Earlier final2148 runtime passes remain attributed to their earlier frozen products.
- `hashfleet-chrome-offscreen-final2224.log`: **19 offscreen checks passed** against the actual `MacApp/FleetMacChrome.swift` production components. They cover black/white surface pixels, enabled/disabled control corners, 44pt targets, text-action sizing, all four 16pt menu-surface corners, visible compact brand geometry, complete branded status text and component layouts at 480/728/1028/2056pt. The process asserts prohibited activation, no active application and zero windows before and after rendering.
- The coordinator inspected the 1028pt/480pt component-header fixtures and the rounded menu-surface fixture. These are component renderings, not desktop screenshots. Their CLI bundle does not contain the app artwork. The header fixtures do not include AppKit traffic lights, a real `NSToolbar`, system overflow or an opened native menu. The menu fixture checks the actual production surface modifier, not a populated live popover.
- The common shared-page-shell source guard, `git diff --check` and native bundle validator pass. Existing duplicate-resource-group, deprecated AppIntent confirmation and unused-test-variable warnings are retained, not a zero-warning claim.

The new ad-hoc signed, validated, **unlaunched** scratch candidate is `hashfleet-native-review-chrome-20261025-2225/Hash Fleet.app`. Executable SHA-256: `ba820115c0ed842a2722ae62effa6cd2fe4552d061f3804a88293f408b1a9cee`. Read-only process inspection at 22:25 UTC still found the old even-layout preview PID55140 at its original scratch path. No preview activation, resize, fullscreen/minimize action, desktop capture, installed-app replacement, data migration or hardware operation was performed after the background-only instruction.

The detecting failures remain distinct: the first runner aborted because it tried to set an already prohibited CLI activation policy; it now first checks the current policy and still requires prohibited activation and zero windows. The initial 10pt control radius failed the unchanged corner-pixel requirement, and increasing the production radius to 12pt passes it. The initial mobile compile caught an app-only theme reference in widget-shared code; the choice was moved back to the app boundary, and final2222 compiles all targets. No runtime acceptance assertion was removed to obtain these results.

**Still deferred:** actual maximize/restore/minimize/fullscreen transitions, sidebar-collapse toolbar placement/overflow, opening the real menus/status popover, and operator appearance approval. App-hosted native tests were intentionally not executed because their host could take screen focus. The previous 42 native runtime tests do not count as a runtime pass for this new candidate. Installation and migration remain paused.

### Final native even-layout correction and actual-window review, 21:37-21:44 UTC

The native section layout now measures the actual card surface separately from its natural heading and footer. Compatible row members receive equal surface top/bottom positions, preserving 16pt page/card insets and shared font sizes instead of aligning only total section heights. A very tall third member reduces and remeasures the retained prefix rather than splitting two matching short cards unnecessarily. Explicit full-width introductions use a separate layout key from automatic surface-less introductions, so an internal default cannot overwrite an external full-width marker. Energy/About introductions and the Reports snapshot preview retain full-width placement. The non-macOS grid and section paths remain unchanged.

Native settings values share a trailing edge and stack only when necessary. Settings actions use the shared full-width reading-row treatment rather than AppKit push-button bezels. Energy's text field is plain only on macOS, and its Currency picker keeps the same binding/options and original iOS Picker branch. Native designed network links and miner quick-action cards opt out of unrelated default bezels. Only standalone network grid contents opt into shared row-height expansion, rather than globally stretching every card. The native toolbar uses the actual shared canvas and one page title. Explicit sRGB native palette construction preserves the shared color constants. No fonts, colors or artwork were redesigned for iPad or phone.

Final build evidence:

- `hashfleet-even-final2131-tests.log` / `.xcresult`: **42 tests in 12 suites passed**, including real rendered mixed-header/footer surface alignment at 900/1756pt, explicit full-width placement through a surfaced section/accessibility wrapper, real network source-card expansion, trailing-value layout and tall-third prefix geometry.
- `hashfleet-even-final2131-build.log`: **Release BUILD SUCCEEDED** after the final native quick-action style change.
- The native bundle validator passes for `hashfleet-native-review-even-20261025-2134/Hash Fleet.app`. It was actually staged and reopened at 21:34 UTC as PID55140 with `--ui-testing --demo --ui-test-asic-telemetry`. Executable SHA-256: `f24257d96905a119d6bc1b022edf18ad1117593eb60fade3ef2ff223bcca7969`.
- Only the previous exact isolated scratch preview was terminated. The installed app, production preferences/data, LaunchAgents and live miners were not changed.

The final `hashfleet-even-final2135-matrix.sh` completed successfully at 21:37 UTC. The real display is 2056pt wide. Its actual fullscreen workspace is 2056x1290pt with the system's adjoining 39pt untitled fullscreen toolbar companion; the actual half-display workspace is 1028x1229pt. This is not a pair of arbitrarily resized screenshots. The workspace probe still rejects extra dialogs/workspaces, and accepts a companion only if fullscreen, untitled, at most 100pt high, equal-width and immediately adjoining the workspace.

All **20 root/top route receipts** pass: App settings, Overview, Network insights, Energy, Achievements, Reports, Backup, About, Preferences and Workshop Gamma miner, each at both actual sizes. Repeated root reselection, whole Add target reachability, relevant visible section/control bounds, common 16pt gutters and half-display unified system window controls also pass. Original PNG, AX, capture receipt and check JSON files use the `hashfleet-even-final2135-{full,half}-<page>` prefix. Four additional original captures cover Preferences/miner lower scroll states at both sizes.

The coordinator personally inspected all 24 final native PNGs, not only the geometry receipts. Native headers no longer show the unrelated gray strip or duplicate titles, introductions span their intended width, and compatible card surfaces align. Existing shared typography, white hashrate hero, dark cards, icons and mascot artwork remain. Long values retain their responsive vertical fallback. Equalized reading surfaces can contain blank space beside longer content, and headings retain their natural content height. This is sampled coordinator layout review, not every state, VoiceOver acceptance or operator appearance approval. The Energy half-display capture correctly shows aged demo readings as unavailable after their freshness window, rather than inventing live power.

Dolphin's independent read-only review found no concrete regression in the nine requested source diffs and confirmed separate explicit/automatic span keys and unchanged iOS branches. It did not run builds/tests or inspect the UI. Its report is source review, not independent runtime or visual acceptance. The later quick-action style change was reviewed and visually checked by the coordinator, not that nine-file review.

Failure evidence is retained rather than relabeled: an accidental Release test configuration failed without enable-testing, incomplete test-plugin staging failed codesign before a fresh scratch stage excluded that plugin, a focused native filter executed zero tests and was not counted, and the detecting rendered suite failed six explicit-span expectations before the separate-key fix. The initial actual-window matrix also rejected a no-detail-scrollbar route until the scratch scroll helper used its explicit optional-scroll operation. Final42 and final2135 are the passing post-fix receipts. Silent redirected build output triggered 90s watchdog notices, but actual task/compiler inspection established completion rather than assuming the build was stalled.

### Current mobile regression boundary

The initial `hashfleet-even-ipad2108` run passed **91 unit tests in nine suites and eight of nine iPad UI workflows**; the supplementary phone workflows passed three of three. The remaining iPad shared-reading-role flow typed 0.15 then found Save non-hittable, despite its frame being visibly above the keypad. The actual failure screenshot/AX tree includes a system decimal-input popover with a full-window `PopoverDismissRegion`. Simple geometric keyboard occlusion is not established. Native `FleetAlignedSectionColumnsLayout` is not selected by the iPad grid branch and is not a supported cause.

Focused unchanged rerun2127 reproduced the failure. Diagnostic runs2132/2136 wrongly treated the shared `UIKeyboardLayoutStar Preview` identifier as a unique modal, even though the main keyboard and popover both use it; these failed diagnostic assertions are not product passes. Run2141 could not hit the system Hide Keyboard control while the modal barrier remained. Run2143's initial popover query did not match even though the later AX tree contained that modal; the cause of that query mismatch is not established. The corrected test waits for the observed `PopoverDismissRegion`, asserts and taps that real control, confirms its disappearance, then asserts/taps the real Hide Keyboard control and confirms keyboard absence. It retains Save `isHittable`, tap, Rate saved feedback, typography, bounds and no-sheet requirements. **Focused run2146 passed** in 46.541 seconds (`hashfleet-even-ipad2146-keyboard.log` / `.xcresult`). This finish-editing workflow is not a claim that Save-with-keyboard-open is accepted. No original acceptance assertion was deleted or replaced with a coordinate tap on Save. Commit `97eec0c` contains only this test fixture change, not an iOS product or font change. The complete final regression ran from 21:48:59 to 21:56:45 UTC with frozen compiled2146 inputs. `hashfleet-even-final2148-ipad.log` / `.xcresult` reports 91 Swift Testing unit cases and nine XCTest UI workflows, 100 logical tests total, zero failed/skipped. The per-device count131 includes parameterized invocations and is not 131 distinct tests. `hashfleet-even-final2148-phone.log` / `.xcresult` reports three passing selected phone UI workflows, zero failed/skipped. The iPad rate flow passed in this complete rerun as well as focused2146. The native42 result includes existing out-of-view Environment-read warnings from `FleetNativeChartContainmentTests`; it is not a zero-warning result.

### Earlier common-shell review history

### Actual preview reload and native header correction

The operator's 15:22-15:23 UTC observations were of old review25, not the edited source. No successful rebuild/reload had occurred at that point. Builds26 and27 failed on incomplete shared-section migration syntax. The failure logs were retained. Build28 succeeded at 15:28 UTC and review28 was actually launched at 15:29 UTC, verified by its executable path and isolated demo arguments.

The operator then reported the window Close controls outside the menu. The native `.expanded` toolbar placed Close, Minimize and Zoom in a separate strip above the toolbar. The new read-only `--require-unified-window-controls` probe rejected all three real controls in review28. Changing the scene toolbar style to `.unified` brought them into the same header, without manually positioning system controls. Build29 passed, native tests21 passed **34 tests in 12 suites**, and isolated review29 PID46963 was actually launched at 15:34 UTC. All three control bounds are inside its actual toolbar. The old demo was terminated only after verifying its exact isolated preview executable path. The installed app was not replaced.

Review29 actual-window evidence:

- Energy at 1376pt and 900pt window widths: section groups remain within the common 16pt content-viewport gutters, change from a full-width introduction plus paired sections to one column, and retain the same type roles. The native Close controls are contained in the header at both sizes.
- Achievements at those same widths: the real empty-state section fills the common inset content width and the header controls remain contained. Existing artwork and empty-state meaning are preserved, with no synthetic achievements added for a screenshot.
- Reports in review28: three columns and a full-width snapshot preview are visible, with shared section padding. Its first gutter check incorrectly measured against the NSWindow rather than the content viewport, counting the system's reserved scrollbar lane as page padding. The probe now uses the actual reserved native scroller edge only when the system preference is legacy, while keeping the 16pt requirement. The original failed JSON is retained. Final Reports checks in review29 were interrupted by operator fullscreen/navigation, so no final all-page pass is claimed from that attempt.
- All captures are actual window screenshots, not resized or edited UI substitutes. Intermediate title-mismatch and extra-window checks fail closed rather than inspecting a different route.

Relevant scratch artifacts: `hashfleet-native-common-shell-build-28.log`, `hashfleet-native-common-shell-build-29.log`, `hashfleet-native-common-shell-tests-21.xcresult`, `hashfleet-native-review28-separated-header-check.json`, `hashfleet-native-review29-header-wide-check.json`, and the `hashfleet-native-review29-energy-{wide,narrow}` / `hashfleet-native-review29-achievements-{wide,narrow}` screenshots and check JSONs.

### Integrated common-shell review31 and regression findings

Build31 succeeded after the final page-wrapper migrations. Native tests23 passed **35 tests in 12 suites**, including a real-pixel check that Form and List sections both preserve 16pt inner card padding. Isolated review31 PID50603 was launched from its actual scratch executable, not the installed app. Reports, Energy and Achievements each passed the actual-window 16pt section-gutter and unified-window-controls checks at **1376×1032** and **900×900**. The narrow checks require one column. Reports also passed the **1100×1000** intermediate two-column check, between its three-column wide and one-column narrow arrangements. Screenshots were captured from the actual window without resizing or image edits.

Artifacts: `hashfleet-native-common-shell-build-31.log`, `hashfleet-native-common-shell-tests-23.xcresult`, and `hashfleet-native-review31-{reports,energy,achievements}-{wide,narrow}-check.json` with matching PNGs. The additional intermediate receipt is `hashfleet-native-review31-reports-medium-check.json` and its matching PNG. These establish their stated runtime boundaries, not operator appearance approval.

iPad units15 exposed an incoherent newly added seven-item grid expectation of 3+2+1+1. The documented row-major contract and production algorithm are 3+3+1, with a full-width single final item. The test was corrected to that contract without changing production geometry, retained its order/spacing/non-overlap/bounds checks, added a real invalid preference case, and added a five-item final equal-halves check. The original failed result remains. iPad run16 then passed **91 unit tests in 9 suites**, including the corrected boundary cases, but failed **3 of 8 UI workflows**.

Run16 showed that identifiers attached directly to an iOS `Section` replaced its child control identifiers, making the existing PDF control unreachable by its stable identity. Native cards have their own accessibility group, while iOS sections do not. Section geometry anchors are now scoped to the native group, preserving the original iPad child identities. The new cross-platform sidebar identifiers were also missing on the iPad branch and were added to its real navigation links. Later runs rechecked these repairs and investigated the separate already-selected Overview return failure. The original failed `hashfleet-ipad-workspace-16-20261025.xcresult` is retained. No failed bundle is represented as passing.

Measured reference: real iPad About attachment `hashfleet-ipad-workspace-11-attachments/06B491BA-DB69-4E92-B997-A89E106F7E28.png` has canvas `#02090C`, card surface `#10191D`, sidebar base `#162228`, and selected-row fill `#2A363C`. These are observations of the original pixels after applying only EXIF orientation, not edited screenshot evidence.

### Shared shell and navigation integration, 16:52 UTC

The common `fleetPageContainer` applies the same 16pt outer padding exactly once and inherits the shared body role. Native `FleetSettingsList` and `FleetSettingsForm` both use that shell and the same explicit rounded sections, with 16pt inner card padding, inset section headings and matching palette. iOS retains its List/Form behavior and semantic fonts. `FleetTypography` gives native Mac the measured iPad role metrics and weights without a page/view scale transform or a forced accessibility category. Native readable-width caps and the former 0.8 density multiplier are removed. `Scripts/check-shared-page-shells.py` passes across feature sources, including every raw Form/List root except the navigation sidebar. This source guard supplements runtime checks, not every-page visual approval.

Native review36 passed actual Reports, Energy and Achievements section-gutter and unified-header checks at 1376×1032 and 900×900. Narrow sections must fill the single shared inset column. Reports additionally passed 1100×1000 and actual section-frame comparisons establish three, two and one columns at those respective widths. The new `hashfleet-native-review36-verified-*` screenshots are unedited actual-window captures. Native tests27 passed 35 tests in 12 suites, and core final2 passed 271 tests in 28 suites. Native tests28 also passed after the last scoped Settings ownership edit. Review37 and the final iPad rerun are in progress, so these results are not silently attributed to a later binary.

The original iPad Overview -> miner -> Overview workflow failed through run22 because view-based miner links were not owned by the bound workspace path. Wide dashboard miner links now use the existing `FleetMinerRoute`, while compact phone links preserve their original matched transition. Sidebar activation clears both the bound path and real presentation bindings even on same-root reselection. The original shared-design reference passed in run24; integrated run25 passed 91 unit tests and nine UI workflows before the later direct-Settings regression was added.

Actual native review34 then exposed App settings -> Preferences -> same App settings remaining on Preferences. An identity reset on content inside the stack failed in review35 and was reverted. Path-owned typed Settings destinations fixed that direct-root return in review36, but iPad run26 then passed 91 units and only eight of nine UI workflows: the unchanged toolbar Settings -> Preferences reference failed at line444. A value append above that view-backed Settings presentation displaced its root. The repair is explicit ownership, not a platform or font workaround: only the split workspace's direct Settings root opts into value links; presented Settings and compact phone Settings retain their original view-based pushes. Destination construction remains shared. The expanded repeated-root regression, original reference, no-sheet checks and all assertions remain intact for run27.

Retained harness issues are separate from product passes. The review34 script's first empty Bash array and wrong `energy.loadSection` selector were corrected without changing production requirements; the source identity is `energy.estimateSection`. Review36's redundant AXRaise returned an error even though a subsequent read showed the window already active, main and unminimized. The actual navigation check was then performed without that redundant action. A supplementary native miner check reached the correct Workshop Gamma title but could not observe iOS's `detail.poolContext` identity, so it failed and is not counted as a navigation pass. Its full AX dump also exposed nonfinite hidden accessibility frames in the scratch helper's JSON serializer; those frames are now represented as null without relaxing action/geometry guards.

### Final native37 and post-edit iPad28 receipts, 17:16 UTC

Source milestone **`4747585`** (`Unify shared page typography and responsive native section layout`) contains the shared primitives, page migrations, responsive layout and regression coverage. The later five-line change is confined to iOS's isolated UI-test launch setup, not the native target. The genuine native review37 bundle passes `Scripts/validate-native-mac-app.sh` and is running as PID **65095** from `hashfleet-native-review37/Hash Fleet.app` with `--ui-testing --demo --ui-test-asic-telemetry`, not from an installed app or real data domain.

All seven final review37 layout receipts pass: Reports wide/medium/narrow, Energy wide/narrow and Achievements wide/narrow. They require the common 16pt content-viewport gutters, visible section anchors and unified system window controls. Real Reports section frames establish **three/two/one** columns at **1376/1100/900pt** window widths. The narrow checks require sections to fill the one shared inset column. Matching `hashfleet-native-review37-verified-*.png` files are actual, unedited window captures.

The separate final `hashfleet-native-review37-navigation-check.sh` passes two consecutive Overview -> Workshop Gamma -> already-selected Overview round trips, plus App settings -> Preferences -> already-selected App settings. It verifies the actual route title and reachable controls after each transition. The original supplementary miner probe required a nonexistent native `detail.uptime` identity and failed; that receipt is retained and not counted as a pass. The separate check uses the real existing ASIC disclosure control and the original root/settings return requirements. Final About, Settings, Preferences and Overview screenshots are under the `hashfleet-native-review37-navigation-*` prefix.

Final iPad run27 passed **91 unit tests in 9 suites and all 9 UI workflows**. After the last iOS-only test-bootstrap edit, **run28 independently passed the same 91 unit tests and all 9 UI workflows**, with zero failed or skipped tests in its xcresult summary. These include the original view-backed toolbar Settings -> Preferences reference, repeated direct-root sidebar returns, in-app nested guides, PDF containment, ASIC expand/collapse, shared-role reference pages and full Add target. The summary's logical total is **100 tests**, not 131: its per-device count also includes expanded parameterized invocations. Native tests28 pass **35 tests in 12 suites**. The source guard and `git diff --check` pass. These are explicit sampled workflow boundaries, not every possible page/state or VoiceOver acceptance.

Final iPad evidence: `hashfleet-ipad-workspace-28-final-20261025.xcresult`, matching `.log`, and `hashfleet-ipad-workspace-28-final-attachments/manifest.json`. Genuine Reports/Energy/Achievements captures are `0049F5DE-6AAB-4931-B25E-A00EFF6C4F48.png`, `CDC8FF8A-C417-4D16-B9D7-07B298985BB3.png` and `3DA4A8FF-A861-4EE2-A9A0-89D338DF1423.png`, respectively. Attachments were exported without modifying their images.

#### Supplementary phone preservation finding

The unchanged phone opt-out workflow passed its immediate return and all six alert-choice assertions, then failed at `FleetActivityUITests.swift:60` when relaunching with `--ui-test-preserve-storage --demo`: session alerts were restored to 1 instead of the fixture's 0. The failure reproduced in `hashfleet-phone-optout-followup-20261025.xcresult`. `FleetStore.init` intentionally restores a pre-demo preference checkpoint after a process restart, as required by the existing production demo-safety tests. Simply retaining the isolated suite did not prevent that recovery from replacing its current fixture choices.

Only the iOS isolated UI-test bootstrap now discards that old checkpoint when **both** explicit preserve-storage and demo flags are present. The fixed suite name remains `app.hashfleet.ui-tests`. Fresh tests still reset it, while non-testing and non-demo launches retain the original production checkpoint recovery. No alert preference or assertion was changed to obtain a pass. This five-line correction is committed as **`a312791`** (`Resume explicitly preserved UI demo preferences across test relaunches`).

The fresh rebuilt phone run passes **all 3 unchanged UI workflows**, including two preserved-storage relaunches, opt-out, re-enabling and the other five alert choices. It also passes **5 existing XCTest production demo-checkpoint cases** and **10 Swift Testing demo/persistence cases in 3 suites**. In particular, the original real-preference recovery after a mid-demo restart still passes. Evidence is `hashfleet-phone-common-shell-post-bootstrap-20261025.xcresult` and its matching `.log`. The subsequent complete iPad28 selection passes after that same final source edit. Task `019579x6c1` finished exit 0 at **17:14:59 UTC**. No production demo-restoration behavior was disabled, and the original failing phone bundles remain intact.

## Review and installation boundary

Native workspace/lifecycle milestone: `48cecb9` (`Port Hash Fleet workspace and menu bar to one native Mac app`). Shared page/layout milestone: `4747585`.

The native candidate is for **local visual review only**. Installation, replacement of the old apps/LaunchAgent, and migration of real user data remain paused pending the operator's appearance approval. No ASIC or mining-host operations were performed for this validation. All interactive app checks used isolated test preferences and demo data.

The native app is `HashFleetMac`, bundle `app.hashfleet.mac`, with a single `Window` scene and an application-owned runtime/store. Its status item belongs to the same executable. The iOS target is explicitly not a Mac/Catalyst installation product.

Review bundles are ad-hoc signed local artifacts. They are not notarized distribution releases. No Intel runtime acceptance is claimed.

## Requirement-to-check evidence

| Requirement | Observed check |
| --- | --- |
| Real native Mac executable, not an iPad wrapper | Genuine native review37 passes `Scripts/validate-native-mac-app.sh`; the running process path is the isolated scratch app, not the installed iPad wrapper. |
| Familiar shared appearance, normal button affordance | **Failed operator acceptance at 11:25-11:30 UTC.** Native37 now passes the documented shared-role, surface, gutter and reachable-control checks, with actual-window screenshots. Operator visual acceptance is still pending. |
| Original menu-bar and panel artwork | Existing `MacMenuBar/Resources/HashFleetStatusIcon.png` is bundled in the native target, non-template, aspect-fit at 18pt/24pt. Resource, alpha and sizing checks pass. Real review17 panel screenshot shows the original portrait miner icon. |
| One process for window and status item | Actual review17 PID62575 had one workspace and one status item. Closing the workspace left zero windows and one status item. Clicking the panel's Open button restored exactly one workspace with the same PID, twice. |
| Quit stops both surfaces | App-menu Quit ended PID62575. Subsequent read-only process check found zero native Hash Fleet processes and zero standalone menu-bar helper processes. |
| Correct scene reopening | Delegate invokes view-scoped SwiftUI `openWindow(id: "fleet")`, not only `makeKeyAndOrderFront` on the cached closed window. Native boundary regression passes. |
| Native Settings command matches the sidebar | Final review18's actual Settings command changes the owning window title to App settings, while retaining one window and one status item. |
| iPad app pages stay inside the workspace | Real iPad UI9, without a desktop-layout override, passes Settings, nested guide, return to Settings, Done, and interactive dashboard/sidebar restoration. No sheets are reported; screenshots show the persistent detail-column route. |
| Correct iPad Settings content bounds | UI9 checks semantic rows and hero, readable-width cap, centering, sidebar containment and interaction. Actual notifications row is x474..1202, width728, in a 1376pt viewport with a 300pt sidebar. |
| Read-only collapsible ASIC domain grid | UI9 passes collapsed default, placement below the individual miner chart, expanded grid/child bounds, and collapse removal. Shared/native render checks cover narrow/wide/accessibility layouts, retained/unsupported data and privacy. |
| In-app PDF and preserved report | UI9 passes PDF preview containment, Done, restored report and no export error. Native PDF generation tests pass for populated and empty snapshots. |
| iPhone navigation remains functional | Real phone simulator regression passes demo dashboard, compact About route, Done and dashboard return. The presentation-policy unit test explicitly retains sheets only for iPhone. |
| No network/hardware side effects in fixtures | Demo isolation and renderer fixture checks pass. No real migration, installation or miner-setting operations were run. |

## Earlier automated results, not visual approval

- Native Mac tests13: **24 tests in 11 suites passed**, after the last production-source edit.
- iPad workspace9: **45 unit/render/policy tests in four suites passed**, plus **four UI checks passed** (ASIC grid, PDF, real iPad Settings/nested guide, detecting Settings geometry positive control).
- Phone native regression1: **one UI workflow passed**.
- Final core run2: **271 tests in 28 suites passed**.
- Final offline package/migration run2: **29 tests passed**. These use isolated fixtures/tool doubles, not real installation or migration.
- Native package17: actual staged app, embedded CLI, ZIP and PKG passed validation. Final package18 is recorded below when staging completes.
- `git diff --check` passed before the source milestone commit.

These are scoped checks, not a claim that every existing UI workflow or every macOS version was exercised.

## Fixes established by failures, not relaxed assertions

### iPad Settings layout versus backing AX bounds

Before the readable-form fix, UI7 measured the notifications row at `(158, 300.5, 1060, 84.5)`. It visibly extended behind the sidebar. Replacing the iOS readable-form scroll-content margin with additive safe-area padding moved the real row to `(474, 300.5, 728, 84.5)` in UI8/UI9 and centered the hero in the detail column.

The UIKit List backing accessibility frame remained `(0, 0, 1376, 1032)` both before and after the real visual fix. It was therefore not a valid observer of the visible row's left edge. The test now measures meaningful existing rows/hero for containment while retaining page extent, no-sheet, interactive sidebar, nested navigation and dismissal requirements. It additionally checks a 760pt readable cap, a lower width bound and centering. A positive control explicitly rejects UI7's observed overlapping geometry and an artificially collapsed narrow row. No `.firstMatch` workaround was used to hide the settings-menu label collision; the menu action has its own stable identifier.

### ASIC disclosure accessibility scope

The diagnostic AX snapshot showed that placing the disclosure identifier on the whole DisclosureGroup propagated it into the accessible grid grouping. Scoping the disclosure identifier/value/hint to its label preserves a separate containing grid and the combined domain-tile identities. UI7 and UI9 pass the original tile placement/bounds assertions. No hidden probe, invented telemetry or flattening of the domain tiles was introduced.

### Actual SwiftUI window lifecycle

An isolated NSWindow unit test passed while review16's real closed SwiftUI window could not reopen through the menu panel. That failure is retained. The delegate now requests the named SwiftUI scene, and the actual review17 same-PID repeated close/Open workflow passes. The new boundary test supplements, rather than substitutes for, this live-app check.

### Real icon resource membership

An initial XcodeGen `resources:` declaration did not place the PNG in the native bundle. Native tests10 and the actual panel14 screenshot exposed the missing image. The resource is now declared in target `sources` with `buildPhase: resources`; native tests11 through13 and the real panel17 verify it. The artwork file itself was not replaced or duplicated for the status item.

### Render-harness observations

Wide OCR uses unbiased overlapping two-dimensional tiles over the original pixels, with no recognition correction. The tall fixture uses the actual display scale to exceed 7000 physical pixels on both 2x and 3x displays. The current renderer tests pass on the real iPad fixture.

## Local artifacts

All paths below are relative to `$JCODE_SCRATCH_DIR`:

- `hashfleet-native-mac-build-18-20261025.log`
- `hashfleet-native-mac-tests-13-20261025.xcresult` and `.log`
- `hashfleet-ipad-workspace-9-20261025.xcresult` and `.log`
- `hashfleet-ipad-workspace-9-attachments/manifest.json`
- `hashfleet-phone-native-regression-1-20261025.xcresult` and `.log`
- `hashfleet-core-native-final2-20261025.log`
- `hashfleet-packaging-native-final2-20261025.log`
- `hashfleet-native-status-panel-17.png`
- `hashfleet-native-review18/Hash Fleet.app`
- `hashfleet-native-package18-20261025.log`

Important passing iPad attachments in `hashfleet-ipad-workspace-9-attachments`:

- Settings inside the persistent workspace: `321FD32F-0CC2-483E-B1CE-631B7D98C1F3.png`
- Nested guide: `5CF1601B-8C99-466A-95C7-AEE76CCA283D.png`
- Expanded ASIC grid: `17E8927E-0DCA-41BD-AE04-086F9B4E5D50.png`
- Collapsed ASIC grid: `D38F81E8-BF55-4725-ACCB-EB92A9EE00C4.png`
- In-app PDF: `E04CB8C4-7BB6-4B87-B21E-EBB93E071073.png`

Earlier failed result bundles and screenshots were retained. They were not replaced by the passing runs.
