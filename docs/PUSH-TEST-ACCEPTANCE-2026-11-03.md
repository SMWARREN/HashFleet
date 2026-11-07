# Confirmed phone registration and accepted APNs test, November 3, 2026

## Result

The owner completed the iPhone opt-in. Read-only app-preference checks at **10:32:03 UTC** and **10:49:51 UTC** confirmed remote summaries enabled, push registration confirmed, and the original four-device inventory unchanged. The server independently had exactly one eligible, enabled, token-valid production registration matching all four original phone miner IDs.

The corrected visible test notification was **accepted by Apple APNs, HTTP 200, at 2026-11-03 10:49:55 UTC**. Its title is **Hash Fleet test**, and its body is **This is the test notification you requested.** There was no mutable-content flag or miner-check payload. The test did not invoke a local hardware check, change any miner, or alter schedules.

Apple acceptance is verified. At **2026-11-03 10:56:24.911 UTC**, the owner replied **“ok it worked”**, confirming the test notification worked on the phone. This is user confirmation, not independent agent observation of the handset display or sound. The original provider receipts remain unchanged, and no additional test messages are scheduled by this work.

## Rejection retained and minimal key-permission correction

The first actual test attempt at **10:36:28 UTC** returned **HTTP 400, TopicDisallowed**, and was not accepted. The original attempt claim and response remain preserved. No failed request was silently classified as delivered.

Authenticated Apple Developer inspection showed the existing production, topic-specific key `YG486K3JBC`, named **Hash Fleet Production APNs 20261027**, permitted only `org.axefleet.app`. Independent App Store Connect API readback confirmed the current `app.hashfleet` App ID has `PUSH_NOTIFICATIONS` enabled.

Only `app.hashfleet` was added to that same existing key. The legacy `org.axefleet.app` topic, key name, production environment, topic-specific restriction, enabled APNs service, and private key were preserved. No key was created, downloaded, rotated, revoked, or substituted from another app. Apple displayed **Your Key is Updated**, and a fresh reload at **10:48:56 UTC** independently showed exactly both expected topics.

After that specific cause was corrected, one separately guarded corrective request was sent. **Two outbound APNs requests occurred in total: one rejected request and one accepted test notification.** Exclusive per-attempt claim files were never reset, and no further sends occurred after HTTP 200.

## Safety and verification

- The sender selected exactly one production `device_check_v1` registration matching the confirmed phone inventory. Wrong inventory, disabled registration, invalid token flag, sandbox environment, wrong mode, odd token length, and duplicate eligible recipient cases were rejected in offline tests. All eight cases passed locally and on the provider host.
- The unchanged, previously verified production `FleetAPNs` transport was used. `APNs.php` and `Service.php` source hashes were guarded, and all production sender/service/config file hashes remained unchanged during both attempts.
- The registration database was opened read-only with query-only enforcement. No `FleetService` constructor, database mutation, enrollment write, schedule change, dispatch loop, or token extraction to the local machine was used. The existing private provider JWT cache may refresh normally.
- Both attempt scripts and receipts are outside the public webroot. Tokens, private keys, JWT contents, credentials, and private contact details were not printed or added to this document.
- The phone was not launched, reinstalled, reset, or written by the agent. The owner performed the opt-in. The native Mac and mining hardware were not changed for the test.

## Preservation and historical status

Private evidence is under `~/.jcode/scratch/hashfleet-rights-push-demos-20261103T0825.noindex/phone-registration-readonly-1032.noindex/`, including the rejected response, independently verified Apple key correction, confirmed phone snapshots, and `corrected-topic-attempt-1049.noindex/one-shot-result.json`. The follow-up receipt backup target is `~/Library/Application Support/HashFleetBackups/2026-11-03-confirmed-phone-test.noindex/`.

This result supersedes the **phone-registration blocker only** in `docs/NATIVE-REVIEW-DEMOS-2026-11-03.md`, commit `3ae26fe`. Its historical off-state observations and completed native-demo backup remain unchanged and accurate for their observation times. Both reviewer videos were already independently verified `COMPLETE` in App Store Connect. No App Store review submission or release was performed in this follow-up.
