# Three-platform release preflight, November 1, 2026

## Status

Release preparation only. No App Store record, upload, review submission,
notarization submission, GitHub repository, tag, or public release was created
by this preflight. No production miner commands were sent.

Application source at the start of this preflight: `28af704`.
Current version: `0.1.0`, build `12`. Do not pick a new marketing version or
price implicitly. Earlier successful simulator and local Mac builds are not
store-distribution artifacts.

## iOS / iPadOS

Blitz's active `hashfleet` project points through
`~/.blitz/projects/hashfleet` to this checkout. Its project bundle identifier is
`app.hashfleet`. The November 1 live overview returned no matching App Store
record and zero versions. Submission readiness is incomplete, including the
name, description, keywords, support/privacy URLs, copyright, content rights,
category, age rating, pricing, review contact, iPhone/iPad screenshots and build.
The missing privacy nutrition labels must also be reviewed, even though Blitz's
readiness form does not mark that row required.

Apple Distribution signing identity is locally available. That does not prove
App Store provisioning, archive validity, upload processing or review approval.
The latest sidebar fix was tested in simulators, not installed on the user's
physical iPhone. Repeat signed physical-device smoke testing before shipment.

The previous complete configured audit passed unit, Mac, tuning UI and CLI
phases, but retained two broader UI failures:

- `CompactDashboardUITests/testAccessibilityTickerExposesStaticUntruncatedMinerSummaries()`
- `CompactDashboardUITests/testFleetToolsAndMinerControlsAreExplicitlyDiscoverable()`

The first targeted rerun hit its 600-second command deadline while verbose
simulator diagnostics were still running. Its incomplete bundle/log are retained
as `compact-blockers.xcresult` and `compact-blockers.log` under
`build/release-preflight-20261101`. The exact orphaned diagnostic process for that
bundle was terminated, without restarting or erasing a simulator.

The unchanged two-test retry disabled verbose diagnostic collection, retained
screenshots/accessibility evidence, and finalized in 62 seconds at 12:40 UTC.
`compact-blockers-retry.xcresult` reports **two failures, zero passes, zero skips**:

- Ticker assertion: zero elements versus three expected at
  `CompactDashboardUITests+Ticker.swift:165`. Git history identifies `9b9c99c`
  (October 3, 2026, "Keep Hash Fleet menu status persistent") as removing
  `FleetStatusTicker` from `populatedContent`. Thus the old ticker test references
  a deliberately removed dashboard component. This is a test/product-contract
  mismatch, not evidence that the new sidebar change broke a current ticker.
  Do not restore old UI or delete the check simply to obtain a green count.
- Fleet tools assertion: missing `Network insights` navigation bar after tapping
  the network button at `CompactDashboardUITests.swift:239`. The failure's AX
  hierarchy places that button at y=59.3, height=48, under the navigation bar at
  y=62, height=54. The test scrolls to Backup before tapping the earlier Network
  row. This supports an obscured-target interaction hypothesis, not proof of a
  broken destination. Validate a visible, unobstructed tap with the same final
  destination assertion before changing production navigation.

The prior configured run covered selected UI cases, not the full UI inventory.
No application source, test assertions or expected manifests changed during this
preflight. Both acceptance checks remain unresolved, not silently marked passed.

`PRIVACY.md` needs a source-backed freshness review before public adoption. It
still describes in-memory history and no hosted backend, while the source tree
now includes persistent telemetry and optional push-provider functionality.
Do not copy those claims into store disclosures without checking the actual
release configuration, data flow, retention and optional services.

## Native Mac

The current packaging script uses `HashFleetMac`, validates a native bundle, and
embeds the CLI. `docs/MAC-DISTRIBUTION.md` has been corrected to match that code
and `docs/MAC-NATIVE-INSTALL.md`, removing its obsolete iPad-wrapper description.

The current tested local native app is ad-hoc signed with hardened runtime.
A Developer ID Application identity is locally available, but a release signed
with it, secure timestamp, nested-code/entitlement checks, notarization and
Gatekeeper acceptance have not been established by this preflight.
The CLI re-signing path also needs explicit runtime/timestamp verification before
it is used for notarized direct distribution. Existing packaging tests are local
fixture acceptance, not a notarization test.

Choose Mac App Store, direct distribution, or both. A direct PKG is not a Mac App
Store artifact. The separate iOS Blitz project must not be used to upload a Mac
artifact to the wrong bundle record. Installer signing identity availability has
not been established by the code-signing identity listing.

## CLI

The CLI is a macOS terminal executable, not an iOS app. Its existing packaging
path embeds it in the native Mac app. A separately downloadable CLI needs its
own versioned archive, architecture/deployment-target description, signing policy,
checksums and install/uninstall instructions. Do not advertise Linux support or
Intel compatibility solely from an Apple Silicon test run.

The checkout currently has no Git remote or tags. Confirm the intended GitHub
owner/repository and visibility before uploading source or release assets. Public
source publication requires a sensitive-file review and a license decision.
The Swift Sonar Kit's license is not automatically HashFleet's license.

CLI dashboard/status operations read telemetry. The settings editor can write to
the selected miner after explicit review and confirmation, so the whole CLI must
not be described as read-only. The demo dashboard does not contact miners.

Fresh local acceptance completed at approximately 12:35 UTC: release CLI build
passed, dashboard 18/18, settings 21/21, firmware/activity 11/11. All 50 tests use
loopback fixtures, not real miners. Native packaging/installer fixtures also
passed 16/16, and packaging shell syntax checks passed. Evidence is under
`build/release-preflight-20261101/cli-*.log`.

## Decisions needed before publication

1. First marketing version and free/paid pricing.
2. Native Mac channel: Mac App Store, direct download, or both.
3. CLI hosting owner/repository and source visibility.
4. Public support/privacy locations and approved review contact information.

Signing secrets belong in the existing secure tooling, not this report or chat.
No signing certificates or accounts should be switched or revoked to bypass a
failed tool. A worker account initialization failed and failed again on retry,
so coordinator inspection, not an invented independent review, supports the
packaging observations above.
