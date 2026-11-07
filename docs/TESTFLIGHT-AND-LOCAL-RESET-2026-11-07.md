# TestFlight 1.0 (21) and clean local state

## Current-state follow-up: no-backups clean install

At 16:43:39 UTC on November 7, the operator explicitly requested uninstalling HashFleet from the paired iPhone and this Mac, permanently deleting local HashFleet backups, and resetting Mac app permissions. This supersedes the backup retention and installed-binary preservation described in the historical receipt below. No app features were removed.

Completed and checked:

- Uninstalled the physical iPhone's `app.hashfleet` version 0.1.0 (12). Subsequent exact-bundle app inventory returned an empty list. No other phone app or phone-wide privacy setting was changed.
- Permanently removed `/Applications/Hash Fleet.app`, the local `app.hashfleet.mac` version 0.1.0 (12).
- Permanently removed the entire `~/Library/Application Support/HashFleetBackups` directory, including the initial app-state backup and preserved release copies. No replacement backup or Trash copy was created.
- Permanently removed the task-created `~/.jcode/scratch/hashfleet-testflight-20261107T1615.noindex` release workspace, including its temporary archives, exports, build products, and source snapshot. The primary source repository was preserved.
- Before uninstall, `tccutil reset All app.hashfleet.mac` succeeded. The store-bundle reset for `app.hashfleet` returned bundle-not-found and is not claimed successful.
- Accepted System Settings' app-specific **Reset notifications for Hash Fleet** confirmation, whose message states that the app must request notification permission again.
- Final filesystem checks confirmed the app, backup root, release workspace, and both app containers absent, with the primary repository still present.

### Remaining Local Network limitation

Local Network permission is separate from TCC and notifications. Apple's TN3179 states that macOS cannot reset an app's Local Network privilege to the undetermined state. It recommends testing in a new macOS user account or a restored VM snapshot instead. No new user or VM was created, and no shared network permission store, other app permission, or system networking configuration was changed.

The operator-reported 31 Local Network entries have **not** been removed or established to all belong to HashFleet. A first-ever Local Network prompt in the existing Mac user profile is **not verified**. Source inspection found Local Network usage descriptions, not a GPS location-permission request.

Both uploaded version 1.0 (21) builds remain the release handoff for operator testing. No TestFlight build was installed or launched during cleanup. Normal uninstall and app-state removal are not claims of forensic erasure, and no iPhone keychain wipe is claimed.

The backup paths and preservation statements in the following historical receipt describe the earlier stage only. Those local backups and temporary delivery artifacts have now been deleted.

## Historical release and initial reset receipt

Verified November 7, 2026, at 16:34:12 UTC. This receipt records the requested sequence: fix five remaining Python findings, upload iOS/Watch and macOS, then back up and reset this computer's HashFleet app-specific state for TestFlight testing.

## Five reported fixes

Fix commit: `c56b432`. It changes only:

- `Scripts/tests/native_mac_tour_smoke.py`
- `Tools/test_native_mac_tour_smoke.py`

Three reported complexity findings were addressed with cohesive helpers for CLI validation/action counting, failure-sampler classification, and AX tour-step polling. The two reported generic unittest assertions now use `assertGreater` and `assertIsNone`. Validation order/messages, finite and nonnegative bounds, action caps, PID identity and resource limits, partial-output classification, polling fallbacks, and frame checks were preserved.

Validation completed before release:

- 73 offline regression tests passed.
- A differential verifier matched 1,728 CLI combinations and 3,859 AX snapshots against the pre-fix implementation.
- Independent read-only review found no blockers.
- The separate real Swift serialization microtest was not run as part of this offline repair validation. No actual tour, app launch, or hardware probe was performed.
- Sonar was not rerun. These are code fixes, not evidence that the server has refreshed its five findings.

## Exact release identity

App Store Connect app: `6812623943`. Existing team: `SAXTXFFJ77`. Both platforms use store bundle `app.hashfleet`, version **1.0**, build **21**.

| Platform | Apple build ID | Upload verified UTC | Processing | Internal state at final readback |
| --- | --- | --- | --- | --- |
| iOS including Watch | `cc3e62bd-73e9-42a7-a82f-323710e63dfb` | 16:22:12 | VALID | IN_BETA_TESTING |
| macOS | `5a86c214-7340-440b-b04d-408f697590e7` | 16:21:22 | VALID | IN_BETA_TESTING |

Both uploads returned exit zero, and fresh Apple readback verified the exact version/build/platform and `usesNonExemptEncryption=false`. Each artifact was uploaded once. There was no App Store review submission or external beta review submission.

### Artifacts

- `HashFleet-iOS-Watch-1.0-21.ipa` SHA256: `9ede4154a8f42277fd855186b7e0bd2e0107fafaf9bc28b8844b9e7652316ffb`
- `HashFleet-MacStore-1.0-21.pkg` SHA256: `bc318f8c3598039df27f474bc7b1a70da3c4054c0f8ee279102947cabaf62757`

The iOS archive/export verified all five expected bundles, including Watch and extensions, their signing/profiles, build parity, and companion settings. The Mac archive is universal arm64/x86_64, sandboxed, and does not contain the direct-distribution compilation condition. Existing distribution and installer identities were reused. No signing identities, accounts, or profiles were created or revoked.

An initial Mac artifact verification failed because the verifier expected the word "trusted", whereas `pkgutil` reports the Apple Store installer certificate as "signed by a developer certificate issued by Apple (Development)". The existing archive and package were retained. Verification resumed with the exact installer identity and leaf/intermediate/root fingerprints, strict app signature checks, and unchanged package SHA256. No rebuild or repackaging was needed for that correction.

The release used an isolated snapshot of all 1,347 tracked worktree files at fix commit `c56b432`, including pre-existing uncommitted tracked app changes. Those owner changes were not staged or committed by this release task. Release-only version/signing settings and the encryption declarations were applied in the isolated copy, not the live project. Live and frozen source hashes were rechecked after release and reset.

## Actual TestFlight availability

Apple's initial `READY_FOR_BETA_TESTING` state did not prove assignment. Both new builds initially had empty beta-group relationships, and the existing internal group still contained only builds 19 and 20.

Both exact build-21 IDs were then linked to the existing **Owner Mac Testing** internal group (`88a67a69-21fd-4992-80e9-cf931d7de92c`). Final live readback verified both links and `IN_BETA_TESTING` for both platforms. Existing builds 19/20 remained linked. No tester was enrolled, removed, or otherwise changed. External state remains `READY_FOR_BETA_SUBMISSION`, not externally distributed.

## Backup-first local reset

Private durable backup:

`~/Library/Application Support/HashFleetBackups/2026-11-07-testflight-clean-state.noindex`

The backup root and credential directory are private. All 573 selected app-state paths were copied and verified against the originals by file bytes, modes, and symlink targets before active state changed. Source repositories, signed archives, and unrelated app data were not reset.

Scope:

- HashFleet's exact app containers, preferences, transient app test/tour suites, caches, HTTP storage, and saved-state paths.
- Direct-build `app.hashfleet.mac`, store `app.hashfleet`, shared `group.app.hashfleet.shared`, and source-history-confirmed legacy `org.axefleet.app` domains.
- The unnamespaced local `miner_telemetry.db` was included only after its exact table schema matched the app database. It was backed up before reset.
- Only the two exact non-synchronizing generic-password services `app.hashfleet.xmrig-api` and `app.hashfleet.remote-push` were queried for credential backup/reset. Both had zero matching records. Certificates, signing keys, other services, and synchronizing items were excluded.

The first credential-backup attempt failed with macOS `errSecParam -50` because a bulk `kSecMatchLimitAll` request included `kSecReturnData`. No active state had changed. The helper was corrected to enumerate attributes first and request payloads only for individual exact accounts. Existing file copies were reverified, and backup completion resumed without overwriting them. Initial failure evidence was retained.

Reset completed at **16:32:06 UTC**. Exact app preference domains were cleared, and remaining active app-state paths were moved into the backup's `retired/` subtree rather than recursively erased. The independent original backup copies remain in `files/`.

Final acceptance verified:

- Zero selected active app-state paths remained.
- Both exact keychain-service counts were zero.
- No HashFleet app process was running or launched.
- The existing `/Applications/Hash Fleet.app` files were unchanged.
- Live repository and isolated release source hashes were unchanged.
- No global preference daemon restart, macOS privacy-permission reset, phone/simulator reset, or mining-service operation occurred.

The cleanup is an app-state reset for a clean start, not a forensic erasure of every historical mention of the app. Source code, the existing app binary, signed artifacts, release records, and private backups are intentionally retained.

## Durable receipts and next check

The private backup's `release-evidence.noindex/` subtree contains the exact IPA/PKG, both archives, frozen source, and private release/reset receipts. Preservation verified 1,484 copied regular files and retained symlink targets. Original scratch artifacts were not removed.

The operator should now install **1.0 (21)** from TestFlight on the Mac and iOS device, then verify the fresh-start onboarding and absence of previously saved miners/settings. The direct-build app was not launched after reset. Runtime behavior of the installed TestFlight builds and a refreshed Sonar report remain user checks, not claimed outcomes of this receipt.
