# Branded startup pause and restored Solo card · 2026-09-09

## Graphite correction at 23:34 UTC

The user rejected the slate-blue surface below as off-brand and requested the established graphite color. Solo now aliases the existing `FleetTheme.charcoal` token, #111111 in both modes, exactly matching the Solo fill at `e70d681` and the comparison-panel role in `docs/research/neutral-palette-2026/`. No new hue or gradient is introduced. Rounded corners, inset layout, gold accents, the branded splash, and every other section remain unchanged. The earlier blue delivery below is retained as history, not the current design.

## Earlier user correction (blue subsequently rejected)

This supersedes the full-bleed Solo strip in `fb14ae2`. Only Solo's layout is restored to the earlier `e70d681` shape: 16-point page gutters, 12-point card padding, 24-point continuous corners and its subtle border. No orange gradient returns. The user also wants Solo to stand apart from the other cards in both appearances, so a dedicated slate-blue surface is used: light #21384B, dark #142B3B. Existing neutral hashrate/miner surfaces and all mining calculations remain unchanged.

## Visible branded splash

The user clarified that the native launch screen does appear, but wants it to pause with the HashFleet name. `FleetStartupSplash` continues the native launch presentation inside the app for about two seconds, displaying the existing single-miner artwork and **HashFleet** wordmark. It follows the app's selected light/dark theme. Tapping anywhere skips it. It fades out over 0.25 seconds, or immediately with Reduce Motion.

- Once per process launch, never replayed merely by returning from the background.
- Underlying data loading and app initialization continue normally. This is a branding pause, not a fake network-loading state.
- Underlying controls are inaccessible while the cover is visible. The accessible Open HashFleet button skips it.
- Sleep task is cancellation-aware. No continuous animation, shimmer, polling or new network client.
- Native storyboard remains for the OS launch stage. The subsequent app-owned pause is not dependent on how long iOS shows its cached launch screen.
- Ordinary UI regressions skip the pause. Explicit splash acceptance enables it, with a deterministic hold mode restricted to the isolated UI-testing launch arguments.

## Acceptance plan

Full native regression includes actual production palette resolution and contrast checks for Solo white/gray/gold/sage content in both themes. UI tests check restored side gutters, rounded-corner canvas pixels, distinct blue surface, unchanged other card surfaces, centered wordmark, light/dark backgrounds, tap-to-skip, automatic continuation and no replay on warm activation. Screenshot review and signed iPhone delivery follow those checks.

## Acceptance results

- Final full native suite: **322 tests across 29 suites passed**.
- Three focused UI tests passed: appearance/navigation in both modes, branded light/dark splash with tap-to-skip and warm resume, and automatic continuation with the normal two-second timer.
- Initial warm-resume test exposed a pre-existing UI-test lifecycle crash: test startup intentionally skipped BGTask registration, but backgrounding still submitted a task. Crash backtrace identifies `BGTaskScheduler._handleSubmissionWithoutRegistrationForTaskRequest`. Scheduling now requires a successful registration, including checking the registration API's Boolean result. The same unchanged Home Screen/resume assertions then passed in both modes.
- Final result: scratch `HashFleetBrandedSplashSoloFinal.xcresult`. Log: `hashfleet-branded-splash-final-tests.log`.
- Screenshots: scratch `HashFleetBrandedSplashFinalScreens`. Both palettes, rounded gutters, wordmark placement and continuation checked. No other card colors or mining behavior changed.
- Signed iPhone build and `codesign --verify --deep --strict` passed. Device delivery recorded separately below.

## iPhone delivery

Executable source `c31f960` installed successfully on the paired iPhone 14 Pro Max at 23:16 UTC. The installation receipt `hashfleet-branded-splash-install.json` reports bundle `app.hashfleet` and database sequence 2352. Automatic launch was denied because the phone was locked, not because installation failed (`hashfleet-branded-splash-launch.json`). On-device visual observation remains unverified until the user opens the app. No hardware settings were changed. Unrelated legacy artwork changes were left untouched.

## Graphite correction validation and delivery

Executable `eb07420`: all 322 native tests across 29 suites passed, including the original graphite role and panel-text contrast in both appearances. The both-theme appearance/navigation UI test passed with exact neutral RGB, rounded gutters, no gradient, and unchanged surrounding card assertions. Result: scratch `HashFleetSoloGraphiteRestored.xcresult`. Screens: `HashFleetSoloGraphiteScreens`.

Signed build and strict code-signature verification passed. First transfer timed out. A single retry installed successfully at 23:40 UTC, receipt `hashfleet-solo-graphite-install-retry.json`, sequence 2360. Automatic launch was denied because the iPhone was locked. No miner settings changed. This delivery supersedes the earlier blue build.
