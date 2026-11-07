# Native iOS modernization acceptance · 2026-09-10

## Delivered scope

- iOS 17+: two App Shortcuts, Open Fleet and Get Last Saved Fleet Summary. The summary returns reusable text plus a Siri dialog, requires local device authentication and the existing explicit widget-sharing opt-in, reads aggregate cache only, includes observation time and honest stale/demo labels, and never connects to or writes a miner.
- iOS 18+: registered Control Center / supported Lock Screen launcher using `OpenIntent`, not an unsupported custom-scheme `OpenURLIntent`. Cold and warm navigation use a consumed-once pending destination. Ordinary widget deep links remain unchanged.
- iOS 18+: accented/tinted widget treatment, plus a large Home Screen widget. Small supplemental Live Activity presentation supports system mirroring on compatible devices. No background persistence or Apple Watch app is implied.
- Native chart selection with timestamp, rule/point marks, per-miner readings, explicit missing values, clear action and a VoiceOver audio graph descriptor. Existing bounded session history and four history windows remain.
- iOS 18+ miner-card navigation zoom and iOS 17+ appearance-symbol bounce, disabled under Reduce Motion. Adds Command-N for the existing Add Miner action.
- iOS 18+ sidebar-adaptable tabs for iPad, preserving Fleet/Settings/About on iPhone. Settings → Shortcuts & Controls explains opt-in and system setup. Its actual intent button adopts iOS 26 glass with Reduce Transparency and older-system fallback.
- Added `CFBundleDevelopmentRegion = en`. Verified that this fixes App Intents natural-language archive generation, which otherwise emitted a nonfatal SSU archive error despite a successful build.

## Safety and compatibility

The deployment minimum remains iOS 17, Swift 6 strict concurrency. Controls/zoom/tabs and glass use separately verified iOS 18 and iOS 26 availability. Existing graphite/orange surfaces, Solo graphite, black logo-only launch, explicit miner-write review and default-disabled FPS monitoring are unchanged. No real miner settings were modified. Unrelated in-progress AppIcon.png and HashFleetBrand.imageset artwork changes were preserved and excluded from the modernization commit.

Apple Intelligence / local Foundation Models were not added because the paired iPhone 14 Pro Max uses A16 and cannot run those local models. No cloud relay, remote tuning shortcuts or continuous background sockets were introduced.

## Verified acceptance

- Core regression: 146 tests in 17 suites passed (`axe-modernization-core.log`).
- Native regression: 357 tests in 32 suites passed again on final source (`axe-modernization-hit-target-ui.log`). Covers sharing opt-in, auth policy, stale/invalid/demo summaries, one-shot navigation, base locale, chart model/audio descriptors, widget accent/privacy policy and existing miner safety, cache, launch and palette regressions.
- System UI: Settings discovery, sharing remains Off, and actual `Button(intent: OpenFleetIntent())` returns from Settings to Fleet in both light and dark appearances. Screens exported to scratch `axe-modernization-system-screens` and visually reviewed.
- Existing independent card collapse/expand UI regression passed, retaining separate navigation and reviewed-settings targets.
- Signed physical-device build passed. English App Intents phrases archived successfully. A clean delivery build was required because the incremental build regenerated intent metadata without retaining its prior NLU folder. The installed package includes `Metadata.appintents/nlu` and passes strict deep signature verification. App and widget retain only the existing `group.app.hashfleet.shared` App Group.

## UI iteration and remaining system checks

Initial chart UI tests exposed parent accessibility identifiers overwriting child chart identifiers and the default scrub gesture not updating while nested in a disabled pager. Added explicit page accessibility containers, a dedicated selected-state drag recognizer, intrinsic height measurement that can shrink, and valid-selection-only paging suppression. Visual inspection then caught truncated legend values and overlapping page dots. Selected values now have full-width rows and page buttons sit outside the chart page. Hit-target assertions caught the distinction between a padded image and a hittable area, fixed with explicit content shapes.

- All three chart UI behaviors passed: unselected swipe paging, selected timestamp changes during drag without changing the daily window, and tap/clear lifecycle. Final targeted UI acceptance additionally verifies the actual 44-point clear target and that page controls do not overlap the legend. Evidence: `axe-modernization-final-ui.log` for passing paging/scrubbing and `axe-modernization-hit-target-ui.log` for the corrected final tap/geometry test.
- Five focused UI tests passed across the final iteration sequence: three charts, both-appearance system-feature navigation in one test, and existing independent card expansion. This is not a full UI-suite run.
- Final selected chart screenshot exported to `axe-modernization-final-screens` and visually reviewed. Miner names and selected rates are no longer truncated in the tested phone layout.

## Physical delivery

Executable source `e10d12b` installed and launched successfully on the paired iPhone 14 Pro Max at 00:40 UTC on September 10. Installation receipt `axe-modernization-install.json` records sequence 2376. `axe-modernization-launch.json` confirms activated launch with no app arguments, leaving default-disabled FPS diagnostics off. No real miner settings were modified. On-device Siri voice/gallery/watch interactions were not exercised.

Actual Siri voice invocation, Control Center gallery placement, tinted SpringBoard widget rendering, Apple Watch mirroring, VoiceOver audio playback and iPad sidebar interaction require separate system-surface acceptance. Compilation and policy tests alone are not reported as visual/device verification of those surfaces. iOS 17 fallback code is deployment-target compiled, not runtime-tested on an iOS 17 simulator.
