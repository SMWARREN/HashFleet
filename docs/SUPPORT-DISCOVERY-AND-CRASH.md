# Support discovery and browser callback fix

## Report, November 1, 2026

The direct-distribution Mac app 0.1.0 (12) trapped after opening the optional support checkout. The faulting thread was LaunchServices' open queue, with a Swift executor assertion in the completion closure in DeveloperSupportSection. The main-thread FleetSettingsSection layout stack was not the crashing thread.

## Fix

FleetExternalURL bridges OpenURLAction through an explicitly Sendable completion that only resumes a checked continuation. Callers await the Boolean result before touching main-actor UI state. Putting a MainActor task inside the original actor-inferred callback is not sufficient because the outer callback itself can trap on entry.

The same completion-style pattern in notification settings and companion launch was migrated. No concurrency checks were disabled and no unchecked Sendable annotations were added. Opening a browser does not complete a payment.

## Product behavior

- A dedicated internal Support Hash Fleet page is reachable from native menus on Mac and iPhone, as well as About.
- The support page explains that the app stays free and tips unlock nothing.
- App Store checkout continues to require the current StoreKit USA storefront. Unknown or non-USA storefronts fail closed. Direct Mac distribution uses its existing build flag. No website or crypto fallback bypasses this gate.
- Eligible session-best, all-time-best and block celebrations may offer a secondary Support link after miner and dismissal controls. It opens the internal page, not checkout. Pending miner celebrations take priority over this optional action.
- Celebration content scrolls when it cannot fit, including smaller phones and large text.
- Miner status cards precede activity/history in menu-bar and shared activity dropdowns. The initial change preserved display filtering. The follow-up below removes that filter without changing notification delivery.

## Validation record

- Production FleetExternalURL helper: Swift 6 typecheck and standalone runtime pass for background, synchronous and OpenURLAction accepted/rejected completions (six cases). No browser opened by these tests.
- Core DeveloperSupportTests: six tests passed, including 19 rejected URL cases and actual-storefront policy coverage.
- Final native Mac acceptance: 19 tests in six suites passed, covering background/synchronous URL completion, close-before-open menu navigation (including Support), workspace routing, runtime, layout and demo isolation.
- Final iPhone acceptance: 18 tests in two suites passed, including an actual rendered pixel-order assertion that current per-miner records precede notification history. Four UI tests passed: Support menu/open/close/reopen, session and block primary actions, and an all-time celebration above an open Add Miner sheet that returns to the same sheet.
- HashFleetMac, HashFleetNoAppPush and HashFleetMenuBar all built successfully. Final logs and result bundles are under `build/support-discovery-20261101/`, with the `verified` suffix. This was targeted acceptance, not the entire repository test suite.
- Real browser acceptance at 17:51 UTC: isolated native demo session celebration -> Support Hash Fleet -> internal Support page -> PayPal. Chrome opened the configured checkout, and the same demo process remained alive and responsive. No payment controls were used. Native sidebar and app-menu Support entries were also observed via PID-scoped accessibility inspection.
- The simulator had no eligible StoreKit storefront, so the neutral Support page and fail-closed behavior were exercised there. Eligible celebration-to-Support UI was exercised in the direct Mac demo. No device locale, account region or storefront override was used to bypass eligibility.
- Independent read-only review found no blocking callback-isolation, eligibility, queued-alert, navigation or adaptive-layout defects. `git diff --check` passed.

### Regression found during acceptance

An intermediate unconditional scroll wrapper made the iPhone celebration dismissal button visible but non-hittable above a presented sheet. The existing test was retained unchanged. Restoring the direct layout passed that test, then the final fit-first `ViewThatFits` layout passed the complete targeted run. Content that does not fit still has a scroll fallback, and accessibility text sizes retain their existing scroll layout. The failed run is preserved as `iphone-final.xcresult`; the passing final run is `iphone-verified.xcresult`.

All interactive validation used isolated demo/test preferences. No real miner operations, payment, account-region change or notification-permission change occurred. The original live-fleet Release app process was not restarted or replaced. The rebuilt Debug app is available in `build/release-readiness-20261101/mac-derived/Build/Products/Debug/Hash Fleet.app`; publishing or replacing the running Release app was not part of this change.

## Follow-up: one activity view, November 1, 2026

The user clarified that the three-way Notifications / Session best / Both selector itself was confusing and could hide block history. Native Mac, the separate companion and the shared activity popup now have one layout: current miner/session information first, followed by recent notifications of all enabled event types, including miner-reported blocks. The obsolete Popup content setting was removed too.

Old mode values remain decodable for compatibility, but no current view reads or applies them. Native Mac no longer applies an additional five-row truncation to the already bounded eight-entry shared notification snapshot. Existing freshness checks, name sanitization, miner routing, notification opt-outs, system permission requirements and block-detection semantics are unchanged. This is recent history, not an unbounded block archive.

A display-filter change does not enable disabled block alerts or grant notification permission. The block-found celebration remains separate from session-best records.

Follow-up acceptance passed: 19 native Mac tests, 35 iPhone unit/render tests and four iPhone UI tests, plus the companion build. Pixel-based regressions inject a block-found event under every legacy display mode and require the actual “reported a block” row as well as miner-first section geometry. The UI test now explicitly requires the BLOCK FOUND eyebrow. Existing delivery, queue and preference tests passed unchanged. Logs/results are in `build/unified-activity-20261101/`.

The actual rebuilt native demo popup was opened by its process-scoped accessibility identifier and visually checked: no three-way selector, miner cards first, session readings within those cards. Evidence: `native-demo-dropdown.png` in that directory. Only the temporary demo was closed afterward. The original real-fleet app process remained running unchanged. Independent review approved the production diff and confirmed no remaining mode reads in the three views.
