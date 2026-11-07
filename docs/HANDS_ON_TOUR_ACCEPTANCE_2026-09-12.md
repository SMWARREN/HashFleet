# Hands-on guided demo acceptance

This supersedes the text-slide tour interpretation in FEATURE_TOUR_ACCEPTANCE_2026-09-12.md. The user's clarified request is an actual-screen sample walkthrough with cues showing what to look at and tap.

## Requirement-to-check map

| Requirement | Check | Current evidence |
|---|---|---|
| Actual app screens, not illustrated slides | `testGuidedDemoWalksRealScreensWithHighlightedTapsAndKeepsSavedFleet`, 14 lesson screenshots | Production dashboard and miner target visually observed. Full route still being repaired. |
| Highlight actual controls and guide taps | Same test checks nonzero measured targets and taps seven `tour.tapTarget` controls | Lazy miner target now materializes and highlights. Tap transition under investigation. |
| Show a sample fleet without replacing saved miners | Same test compares saved IDs and loopback GET/write journal after completion | Full completion pending. Six native sandbox tests passed. |
| Isolate requests and temporary settings | `FleetGuidedDemoSandboxTests` | Six functions passed in native iOS host. Denied session requests counted independently, demo refresh attempted no request, cleanup preserved the other sandbox. |
| First launch after preserved splash | `testFeatureTourFirstLaunchAfterSplashAndPersistentOptOut` and splash startup test | Current actual-screen revision pending rerun. Previous slide revision is not acceptance evidence for this revision. |
| Persistent Don't show again, early exit, replay | First-launch test plus dismissal/reopen and Settings tests in `HashFleetUITests+Tour.swift` | Current revision pending rerun. |
| Back, Next, Done and topic chooser | Existing navigation and chooser tests plus full highlighted route | Current revision pending rerun. |
| Large Dynamic Type usable | `testFeatureTourFitsAtAccessibilityTextSize` plus screenshot inspection | Current revision pending rerun. |
| Production screens unchanged outside demo | Existing Settings/coin flow regression, target environment defaults false | Current revision pending rerun. |
| Existing artwork and splash preserved | Scoped diff review | No artwork/splash edits. |
| Phone delivery | Signed device build, codesign verification, devicectl install | Pending for this revision. |

## Safety design

Real production views render with a fresh sample FleetStore and MiningInsightsStore. Guided actions are controlled proxy taps over measured real control bounds. They navigate between the actual view types and modify only temporary sample preferences. They intentionally do not invoke hardware commands, permission prompts, sharing, or scans.

Underlying screen touches/accessibility actions are disabled. Action-bearing production toolbars are omitted in guided mode. The explicit tour suppression toggle remains bound to the real tour preference. A scoped defaults suite and deny-all URLSession back the sample stores. Miner notice snooze reads now use the supplied store's defaults rather than implicit shared defaults.

Normal OS background alert delivery is not part of this demo and is not claimed verified here.
