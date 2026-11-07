# Sidebar activation replaces the current page

Date: 2026-11-01

## User-facing contract

Selecting a left-sidebar destination closes the current workspace page and opens
that destination at its root. Selecting the already-selected destination also
returns to its root. Navigation never applies a tuning draft or sends a miner
command. This is shared by native Mac and iPad. The compact iPhone Fleet Menu
keeps its existing dismiss-then-present behavior.

## Implementation and evidence

`FleetSidebarView` now sends explicit activation events for button and keyboard
navigation when hosted in `FleetSplitView`. A repeated destination is an action,
not merely a change to the selected value. Compact-menu callers retain their
existing binding-based routing.

`FleetSplitView` clears the value path and Add Miner binding, updates the selected
destination, and renews the identity of the owning split navigation container.
Clearing `NavigationPath` alone does not remove all destination-closure pushes.
Renewing only the detail stack was also insufficient in the observed Mac and iPad
runs. Those intermediate failures are retained, not counted as passing evidence.

The final native acceptance covers the original six tuning open/back round trips,
reselecting the current miner twice while tuning is open, switching from tuning
to all eight non-miner sidebar destinations, reselecting App settings from nested
Preferences, and leaving/reopening Add Miner twice. The old app failed the new
same-miner check. The split-owner repair passes it without weakening assertions.

Run the native check explicitly on a logged-in desktop with Accessibility access:

```sh
python3.12 Scripts/tests/native_mac_navigation_smoke.py --sidebar \
  --app '/absolute/path/Hash Fleet.app' \
  --work-dir "$PWD/build/sidebar-acceptance"
```

Only an isolated `--ui-testing --demo` process is controlled and terminated. The
probe does not activate that window unnecessarily. AX calls are bounded. A lookup
may be retried only when no press occurred, not after an uncertain action result.

Cross-platform UI checks:

- `testRealIPadSidebarReplacesTuningAndReselectedRoots`: repeated direct tuning
  reselection, all sidebar destinations, Add Miner dismissal and reopening.
- `testRealIPadSidebarReturnsFromMinerRepeatedlyAndSwitchesRoots`: existing
  dashboard/miner and nested Preferences regression, unchanged.
- `testPhoneFleetMenuClosesBeforeOpeningRequestedDestination`: Reports, About,
  and Overview opened through the compact menu, with the old menu gone.

## Final validation

- Native Mac accessibility acceptance passed all six tuning round trips and the
  complete sidebar replacement/reselection scenarios described above.
- Native Mac regression suite: 118 passed, zero failed or skipped.
- iPad sidebar UI suite: both tests passed, zero failed or skipped.
- iPhone compact-menu UI test: passed, zero failed or skipped.
- Strict SwiftLint passed for both changed production Swift files and both changed
  UI-test files. The native Release app passed the packaging validator.
- Existing Xcode project-reference and deprecated-intent warnings remain. These
  results do not claim a warning-free build or complete release readiness.

Local evidence: `~/.jcode/scratch/hashfleet-sidebar/` and
`build/release-readiness-20261101/sidebar-*.xcresult`. These targeted navigation
checks do not constitute an overall App Store release approval.
