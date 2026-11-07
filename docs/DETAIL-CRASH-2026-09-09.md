# Physical iPhone miner-detail crash · 2026-09-09

## Evidence and cause

The user reported a crash specifically when opening miner details. Two app-only crash reports copied from the paired iPhone show the same failure, including an earlier build before the final gray-layer update:

- `HashFleet-2026-09-09-020529.ips`
- `HashFleet-2026-09-09-022854.ips`

Both report `EXC_BAD_ACCESS / SIGSEGV`, a stack guard protection fault, and `Thread stack size exceeded due to excessive recursion`. The faulting main-thread path is `___chkstk_darwin` → nested `MinerDetailView.collapsibleCard` closure → `metrics` → `telemetrySections` → `body`. There is no direct source-level self-recursive call on that path. The eager, nested generic SwiftUI value construction exhausts the physical-device stack. The installed debug dylib UUID `63E0C495-BCB4-3C3C-BE60-E6732EC353FC` matches the 02:28 report.

Raw device reports, the matching original binary and disassembly remain in local scratch `HashFleetPhoneCrash/`, not in the repository. They may contain device information. This was not a miner-data corruption issue. Simulator-only navigation acceptance did not detect it, so physical-device detail interaction is required for this fix.

## Source fix

`App/Features/Miner/MinerDetailView.swift` now introduces real, independently evaluated SwiftUI bodies:

- `MinerDetailSection` stores a deferred builder at the telemetry and metrics boundaries, rather than eagerly embedding their entire result in the parent's construction stack.
- `MinerDetailMetric` stores the four small metric inputs. Each styled metric tile is built in its own body.
- `MinerDetailCollapsibleCard` stores a content closure and builds it only when expanded, through another view boundary.
- `MinerDetailCardHeader` builds disclosure/settings sibling controls independently of the generic telemetry subtree.

No `AnyView` blanket erasure, optimizer setting change, larger stack, data reset or miner write is used. The existing expansion state, Reduce Motion handling, 44pt controls, settings routes, labels, identifiers, warning content and detail-only four-hour snooze behavior remain.

## Regression contract

`testEveryMinerDetailCanBeOpenedAndReopenedInBothModes` opens all three demo miners, reopens the first, repeats in light mode, toggles the cooling card, checks the app remains foregrounded, and returns to the dashboard after each visit. That is eight independent detail navigations intended for simulator and physical-phone acceptance with isolated test defaults. Physical execution remains blocked by the device lock, as recorded below. Existing telemetry card interaction and warning silencing tests also remain.

Tests use `--ui-testing --demo`, which clears only `app.hashfleet.ui-tests`, not the user's standard saved-miner defaults. The final delivery must launch normally without test flags.

## Validation and delivery

- `HashFleetDetailRefactorAndBlack.xcresult` passed 34 unit tests and 9 UI tests: exact theme/preferences, reported-state semantics, appearance navigation, detail-only silencing, all five miner-card interaction tests and both ticker tests. This is focused regression, not the full suite.
- The first additional repeated-navigation run passed all three dark-mode miner detail visits, then missed a link while scrolling back to the first miner. The app remained running on the dashboard. The test now waits for a hittable link with a stable frame for 0.5 seconds before tapping, without removing any navigation or disclosure assertions.
- Physical `HashFleetPhysicalDetailFix.xcresult` could build/sign the app and test runner but could not execute tests: Xcode reported “Unlock the test iPhone to Continue” and timed out. No physical detail navigation has been verified for this repair.
- The final generic-device build passed, including the later light-mode black-panel disclosure contrast correction. Strict deep code-signature verification passed.
- The final app installed on the paired iPhone 14 Pro Max at **07:01 UTC**. A normal launch without test flags was explicitly denied because the device was locked. Installation evidence is `hashfleet-blended-final-install.json`, and launch evidence is `hashfleet-blended-final-launch.json`, both in local scratch. No uninstall, app-data reset or miner setting write was used.
- Physical-device acceptance remains open until the unlocked phone can open and reopen miner details. Simulator results do not establish resolution of this physical-device-only crash.

- Final `HashFleetDetailBlendedFinal.xcresult` passed both appearance navigation and all eight repeated detail visits at **07:05 UTC**, with no failures. The final light-panel chevron is visible, and both dashboard screenshots were visually reviewed. This adds one unique repeated-navigation check to the earlier 43 passing checks, with appearance rerun on the final production revision.
