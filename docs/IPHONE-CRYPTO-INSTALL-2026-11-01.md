# Physical iPhone crypto-support installation, November 1, 2026

## Delivered

The operator requested installation on their phone at 20:53 UTC. The connected, paired physical iPhone received an in-place update of the existing `app.hashfleet` installation from **0.1.0 build 12 to build 13**, at approximately **21:07 UTC**. Source commit: `fde1603`, including the shared native BTC/ETH/SOL support implementation `a32c39c`. Only external build metadata changes the build number.

The normal app launch succeeded at approximately 21:09 UTC. A subsequent live device process query at 21:11 UTC confirmed the main application still running, alongside its existing widget extension. No demo/test arguments, UI test runner, uninstall, data reset, TestFlight upload or App Store submission was used. The phone's older pre-existing UI test runner was not changed.

## Signing and artifact acceptance

- Physical-device Release compilation passed, using the existing resolved package versions and owner-private nonindexed staging.
- Xcode rejected its existing managed ad hoc profiles when requested through manual Xcode signing. This failure is retained. The exact compiled artifact was instead sealed locally with the existing profile-authorized Apple Distribution certificate and existing target-specific profiles. No developer account, certificate, profile, device registration or capability was created or altered.
- The main app, widget and notification-service extension all independently passed strict signature validation, exact bundle/version checks, authorized-device and profile-expiry checks, and unchanged App Group validation. The main app retains production APNs, and no rejected Local Push/Network Extension capability was added.
- All three owner-approved receiving destinations are present in this exact shipping executable. Native/website destination parity tests passed again. This does not claim physical-phone Support-screen interaction or storefront eligibility was independently exercised.

## Data preservation

Accessible Application Support, main app Preferences and shared Library files were copied read-only before and after installation, before the first new-app launch. **All four files, totaling 12,545,919 bytes, were byte-identical.** All **29 main preference keys and values** were unchanged. The shared App Group identity and container path were unchanged, and the same existing app identity was updated without another production app being added.

The OS selected a different main app data-container UUID during installation. The initial path-stability assertion failed and remains preserved in the private evidence. That assertion is not presented as a pass. Separate content-based preservation checks proved the stronger user-facing requirement: the existing preferences, telemetry database, tour-sandbox preferences and shared preferences were retained byte-for-byte. No data was restored or rewritten to produce this result. Inaccessible keychain material and root App Group files were not independently copied or verified.

## Mac app hygiene

The build used `~/.jcode/scratch/hashfleet-phone-20261101.noindex/`. The signed phone artifact is archived as a ZIP, its raw `.app` is unregistered and reversibly retired, and no new Mac app was launched, installed or restarted. Final checks inspect physical generated bundles, existing-path LaunchServices registrations and Dock entries, rather than Applications alone.

Private receipts include `signed-validation.json`, `install-result.json`, `apps-before.json`, `apps-after.json`, `installed-preservation.json`, `launch-result.json`, `processes-after-launch.json` and `final-cleanup.json` under the private staging root. No receiving addresses or user device identifiers are reproduced in this report.
