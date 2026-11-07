# Optional feature tour acceptance

## Request and interpretation

User requested a swarm-built walkthrough/demo, then clarified at18:49 UTC: show on first load and provide Don’t show again. The tour now automatically opens once after the existing splash. Closing or finishing marks it seen, so later launches do not repeat it. Don’t show again persists immediately, including if the app is killed before closing. Manual replay remains available from the dashboard menu and Settings. The tour does not switch to a simulated fleet, rename the app, ask notification permission, issue hardware commands, or mutate miners. Existing splash view and artwork remain unchanged. Only the two app-local tour display flags are new.

## Ownership

- Root: dashboard menu, empty-fleet invitation, Settings replay entry, integration and native acceptance.
- Content worker stalled without producing a file and was stopped. Root supplied standalone Foundation content and tests to unblock integration.
- UI worker: standalone SwiftUI tour with local navigation state, committed b4abd72.
- Acceptance worker: real native UI regressions using existing demo and loopback transport, committed 9b4db00. Root added the empty-fleet invitation/direct-chooser path.

## Requirement-to-check map

| Requirement/output | Concrete check | Observed result |
|---|---|---|
| Automatic first load after splash | testFeatureTourFirstLaunchAfterSplashAndPersistentOptOut | Tour appeared without a menu tap, splash absent when tour visible |
| First dismissal does not repeat | testFeatureTourFirstDismissalDoesNotRepeatOnLaterLaunch | Close, terminate, relaunch same storage: dashboard, no tour |
| Don’t show again survives abrupt exit | testFeatureTourFirstLaunchAfterSplashAndPersistentOptOut | Switch 0→1, kill before closing, relaunch: no automatic tour. Manual replay switch still1 |
| Discoverability and replay | testFeatureTourCanBeReopenedFromSettings; testFeatureTourEmptyFleetInvitationAndDirectStepChooser | Settings opens/closes tour back to Settings. Empty-fleet invitation opens tour, chooser jumps to final page, Done returns to empty fleet |
| Back, Next, every page, Done | testFeatureTourSupportsNextBackAndDoneDismissal | Next changed visible step, Back restored first step, traversal reached Done and dismissed |
| Close and reset | testFeatureTourIsOptionalAndDashboardSkipReopenResets | Explicit menu presentation in deterministic manual test mode, Close and replay returns first page |
| Feature accuracy and content contract | FleetTourContentTests two functions | Nine unique nonempty three-bullet pages. Guardrails for compatibility, freshness, odds, background alerts, estimates, backup privacy included |
| Durable display policy | FleetTourPresentationTests.firstLaunchDismissalAndSuppressionPersistIndependently | Defaults round-trip shows seen and suppressed independently prevent auto presentation, notification opt-ins remain false |
| Fleet preservation/no commands | testFeatureTourDoesNotMutateDemoFleetOrRealSavedFixture | Demo miner IDs unchanged. Real-mode loopback saved miner ID/name unchanged, GET transport observed, zero miner writes |
| Largest Dynamic Type | testFeatureTourFitsAtAccessibilityTextSize | Close/Next/Back usable, stacked control width >75% viewport, frames do not overlap. Actual screenshot reviewed: Next no longer wraps between letters |
| Existing splash | testSplashAutomaticallyContinuesWithoutHoldingUpStartup | Existing splash completion regression passed. Splash implementation/assets unchanged |
| Integration | Full native units plus nine UI workflows | 579 unit functions/60 suites and nine UI workflows passed, no UI failures |
| Signed package/phone delivery | Device build, signature verification, install and launch | Build and deep/strict signature verification passed. Installed on iPhone at19:01 UTC, sequence2144. Remote launch denied because phone locked |

Native simulator tests and any device installation will be recorded separately. Never infer physical notification delivery or real miner changes from a read-only tour test.

## Iteration evidence

- Initial full native suite passed578 functions, but real tour UI exposed inherited Group accessibility identifiers overwriting Back/Next, plus a test menu-index requery issue. Fixed with a real contained root VStack and stable menu ID targeting. Did not remove the native navigation checks.
- Six native tour workflows then passed. Screenshot inspection at maximum Dynamic Type revealed Next wrapping between letters despite being tappable. Changed footer to stacked full-width controls at accessibility sizes and strengthened frame checks. All six flows and578 unit functions passed again at18:53 UTC.
- First-load/opt-out requirements arrived while that run was active. Added persisted tour policy and two native relaunch tests, plus retained the existing splash regression. Expanded final validation passed at18:59 UTC:579 unit functions and all nine native UI workflows.
- Test-only --show-feature-tour opts existing isolated UI tests into the automatic presentation path. Normal production launches do not need this flag. This keeps unrelated legacy deterministic tests from being interrupted while exercising the real startup path explicitly.

## Final evidence

- Final source native result: `Test-HashFleet-2026.09.12_14-55-11--0400.xcresult` under the project DerivedData Logs/Test directory.
- Log: `/Users/USER/dev/hashfleet-tour-startup-tests.log`.
- Nine actual UI workflows finished in209.688s, zero failures. This is the real SwiftUI app with its native sheets, switch, menu and startup flow. The safety test uses a local loopback miner, not a physical hardware write.
- Normal and AX5 screenshots exported to `/Users/USER/dev/hashfleet-tour-startup-passed/`. Visual review confirmed full-width AX5 controls and no split Next label. Longer educational content remains scrollable.
- No artwork, splash source, entitlements, hardware settings, notification permission, or mining configuration changed. App startup merely passes its existing completion boolean to the dashboard.

## Delivery

Executable commit `0007ee0` built successfully for generic iOS in77s. `codesign --verify --deep --strict` passed. CoreDevice installed `app.hashfleet` on the user's iPhone at19:01 UTC, database sequence2144. Remote launch was denied with explicit device-locked error. Installation succeeded, but no physical tour interaction is claimed. Unlock and open Hash Fleet to see the new first-load walkthrough. No storage reset was used for device installation.
