# Native App Review demos, November 3, 2026

## Delivery

Both private reviewer videos are attached to the existing Hash Fleet app, Apple ID `6812623943`, version 1.0. Independent Apple readbacks at **2026-11-03 10:28:29 UTC** confirmed `COMPLETE`, exact file sizes and source MD5 checksums, one matching attachment per platform, unchanged review contacts and saved notes, and the original attached store builds. Neither draft was submitted or released.

| Platform | Existing store build | Private App Review attachment | Video | Duration | Bytes |
| --- | --- | --- | --- | --- | --- |
| iOS | 18 | `f4085650-d9a2-4cd2-860d-5586eb534fc0` | `HashFleet-iOS-Native-Simulated-Demo.mp4` | 45 seconds | 798166 |
| macOS | 19 | `5128e290-0cd9-452f-9df0-dd5be4bdacf3` | `HashFleet-Mac-Native-Simulated-Demo.mp4` | 30 seconds | 417089 |

Find these in **App Store Connect > Hash Fleet > iOS or macOS 1.0 > App Review > Attachments**. These are private reviewer demonstrations, not public App Store app previews. Both version states remain `PREPARE_FOR_SUBMISSION`.

- iOS SHA-256: `3272e53c4c88eb7727d3ad8a6592cd579036b9848e8cd9f901e7cd207f13db8c`
- iOS source MD5: `a6578b37c5848141efc71a4adb9a2019`
- macOS SHA-256: `5736d1b4bc1aa9c3a6d8a819f89c3a88cece40f0d7e28942c53465992947e229`
- macOS source MD5: `f34d430a0d579eda968aedde4af79877`

## Truthful native capture provenance

The iPhone video records the original native simulator build **12**. The Mac video captures only the original installed native build **13** window. Both use accepted source revision `320510d645a7e5849d13deff73d312b25ef42781`. They are **not recordings of the uploaded iOS 18 or Mac Store 19 binaries**, and the appended review notes explicitly disclose that distinction.

Three explicitly named simulated local ASIC inputs feed the iPhone overview. One explicitly named simulated local ASIC input feeds the Mac overview. Normal native rendering shows changing readings and charts. A persistent video banner states **SIMULATED LOCAL ASIC DATA / NO HARDWARE CONNECTED**. Neither video claims actual miner performance or a miner-detail walkthrough. No mining hardware was changed to produce these videos.

Every final video frame decoded successfully. Contact sheets were visually inspected, and independent per-second frame samples change. Final formats are H.264 without audio, iPhone 804 x 1840 and Mac 1440 x 1068. The original simulator artifact had 59 entries verified, and the local input fixture had 3261 assertions before recording.

## Original app and data safety

The sole installed Mac bundle remains `/Applications/Hash Fleet.app`, bundle ID `app.hashfleet.mac`, build 13, with its original native binary hash and App Sandbox intact. No new installed app, signing bypass, or production native-code change was used.

Native Mac capture required a temporary, protected test session. Six original current and legacy preference/history files were backed up while the normal app was quiescent. One changed original file was restored from that backup after recording. All six original file hashes, complete preference values, the four-device inventory bytes, history integrity and history table counts were verified before the normal app relaunched at 10:14:06 UTC. The final independent check also found the original inventory unchanged and a read-only database `quick_check` of `ok`. Normal background history can legitimately advance after relaunch and is not claimed to remain frozen.

All owned input fixtures and Mac test processes stopped. Only the task-created review simulator was shut down, without deleting its data. The physical owner phone was not launched, reinstalled, reset, enrolled, or written by this task. No phone Keychain material was read.

## Phone push is not complete

The fresh **2026-11-03 10:23:52 UTC** read-only owner-phone check found four original saved miners, `remote_enabled: false`, and `registration_confirmed: false`. **No test push was sent.** App installation is distinct from APNs enrollment. The native Mac is intentionally restricted from enrolling or overwriting the iPhone scheduled-check configuration.

The phone opt-in is **Hash Fleet > Settings > Notifications > Scheduled miner summaries**. It starts registration and requests notification permission, subject to prepared local miner identities. It also enables recurring scheduled requests, hourly by default, rather than only a one-off test message. That additional behavior was not silently enabled. A matching, confirmed owner-phone registration is still required before sending the authorized test push. The local-test notification control is not a substitute for an APNs delivery test.

The separate APNs topic/payload mismatch was repaired and independently verified, documented in `docs/PUSH-IDENTITY-REPAIR-2026-11-03.md`, commit `053b880`. The user-authorized public phone removal and support email change are recorded in `docs/PUBLIC-CONTACT-RIGHTS-2026-11-03.md`, commit `b0ad2d9`. Those completed changes do not imply that the phone opted in.

## Verification limits and retained diagnostics

Original note text was preserved exactly, with truthful native-demo supplements appended. All review fields returned by the installed read CLI, including private contacts, were compared with original snapshots. This CLI omits `demoAccountRequired` from both original and final reads. The final independent verifier therefore records that flag as **not exposed**, not an independently observed false value. No account credentials were invented.

Earlier local CLI argument/schema failures, the first bounded iPhone processing observation, the failed extra-sandbox Mac attempt, and unsuccessful native form-input attempts remain in private evidence. None was silently reclassified as success or concealed with duplicate uploads. The original iPhone upload was observed until `COMPLETE`, not uploaded again. A final-verifier diagnostic caused by treating an omitted boolean as false was retained, and only that schema assumption was corrected.

Private task evidence: `~/.jcode/scratch/hashfleet-rights-push-demos-20261103T0825.noindex/`. The independent read-only verifier is `verify_native_review_delivery_readonly.py`. Final delivery backup target: `~/Library/Application Support/HashFleetBackups/2026-11-03-native-review-demos.noindex/`. Its `verified.json` is written only after post-commit Apple/native checks, a new committed-history Git bundle, and independent rehashing of every copied artifact. Earlier durable backups remain unchanged. This preservation scope does not claim acceptance or a fresh snapshot of unrelated dirty worktree changes.
