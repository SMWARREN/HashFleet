# Native Mac popup tabs, November 1, 2026

## Delivered

The operator requested two clear menu sections at 19:43:52 UTC. The integrated native Mac status popup now has a segmented **Miners / Notifications** control, initially showing Miners. Miners contains current device cards, session bests and device notices. Notifications contains the existing bounded recent inbox, including enabled block events, or an explicit empty state. Changing tabs resets scroll position without changing delivery preferences, deleting history or invoking hardware actions. Miner and notification navigation retain the existing close-before-open route.

Only the integrated Mac popup changed. The iPhone/iPad activity popup and legacy separate companion remain on their existing layouts. No old Notifications / Session best / Both display preference was restored.

## Support audit

There is one reusable internal Support page, with multiple entrances:

- Native Mac sidebar (`DashboardView+WideLayout.swift`).
- Native Mac application menu (`HashFleetMacApp.swift`).
- Native Mac status popup's secondary ellipsis menu (`FleetMacStatusItem.swift`).
- Overview's settings menu on Mac and phone/tablet (`DashboardView.swift`).
- About embeds the support payment section (`AboutView.swift`).
- Eligible celebration screens have a secondary internal Support action (`FleetCelebrationView.swift`).

At the 19:57 UTC popup audit, the shared native payment section and core configuration exposed **PayPal only**. BTC, ETH and SOL support options existed in website source, not native payment UI or CLI. The later owner-requested native crypto addition is recorded in `NATIVE-CRYPTO-SUPPORT-2026-11-01.md`. The CLI support command prints/opens the configured PayPal page. This change did not add cryptocurrency actions, modify storefront eligibility or initiate a payment. No wallet addresses are reproduced in this report.

## Validation and install

- Production Release build, packaging and native bundle/signature validation passed.
- Actual isolated demo popup: three miners, every card's session-best accessibility label, empty notification state, repeated round trips, mutually exclusive content, and miner detail navigation passed.
- Actual installed production popup at 19:57:18-19:57:20 UTC: four saved miner cards, eight existing recent notification rows, repeated tab switching and click-to-miner detail passed.
- Thirteen unchanged native tests across five suites passed in the scheme's Debug testing configuration: menu navigation, workspace navigation, lifecycle, demo isolation and browser callback handling.
- Static native navigation/shared page-shell guards and final `git diff --check` passed.
- Before replacement, preferences and a SQLite-consistent telemetry backup were saved owner-privately. Backup `PRAGMA quick_check` returned `ok`. The initial zero-wait backup encountered a normal lock, the bounded-timeout retry succeeded without changing SQLite policy. The four saved-device encodings were byte-identical after installation.
- The previous installed monitor was gracefully quit by exact PID and replaced at the canonical `/Applications/Hash Fleet.app`. Its rollback bundle was moved to a reversible `.retired` copy in Trash rather than left as another Applications entry. Final Applications inventory has only the canonical Hash Fleet app.

The first newly written UI test looked for session-best text only in AXValue. Native SwiftUI combines a miner button's text in AXDescription. The receipt preserves that failure; the corrected probe asserts session best on **every** actual miner button. The initial Release unit-test invocation could not import the production module with `@testable` because Release disables testing. No test assertions or production compiler safety flags were relaxed. The unchanged suites then passed using the scheme's normal Debug configuration. Optional audit workers produced no usable independent review and are not counted as approval.

## Fleet safety

All four tracked ASICs received only GET `/api/system/info` and `/api/system/logs`; all eight reads returned HTTP 200 in the 19:50:14 UTC receipt. Documented M1 SSH/process/LaunchAgent reads succeeded, while its loopback XMRig API remained unavailable. No ASIC write, restart, self-test, OTA, tuning, fan/pool/wiring change, mining-Mac service change or lockout clear occurred. Only the local monitoring app restarted for installation. Existing electrical and recovery limits remain unchanged.

Owner-private logs, AX captures, result bundle, packaged app and data backups: `~/.jcode/scratch/hashfleet-tabs-20261101/`. Implementation commit: `e3aa447`.
