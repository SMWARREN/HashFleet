# App Review submission acceptance, November 4, 2026

## Authorized outcome

The owner requested at `2026-11-04T01:35:02.874Z`: validate everything and submit both platform versions.
Both final submission commands were accepted by Apple. Fresh API readbacks and the server-rendered App Review page confirmed both submissions and both versions as `WAITING_FOR_REVIEW`.
This is review submission, not approval or public release.

| Platform | Version | Build | Selected build ID | Review submission ID |
| --- | --- | --- | --- | --- |
| iOS, including the Apple Watch app | 1.0 | 20 | `10cc616e-b9b0-42a2-bd66-9e0e92b82b96` | `60ddc9db-3af7-4c6e-8007-f8f5d00f9cf6` |
| Native macOS | 1.0 | 19 | `444fc87d-9fa5-4457-8eb1-e344f05454f7` | `ce8e7cd8-2cec-4b98-aaea-f52972ce0ca6` |

App ID: `6812623943`. Store bundle ID: `app.hashfleet`.
iOS version ID: `6e59d0e4-7087-4f1f-a39a-faeab0ab1778`.
macOS version ID: `605fc5ac-0228-4c30-8263-e8b2666f7768`.
Apple's successful final readbacks completed at `01:52:43 UTC` for iOS and `01:52:33 UTC` for macOS on November 4, 2026.

## Release and account safety

- Both release modes were changed from `AFTER_APPROVAL` to `MANUAL`, preserving all unrelated returned version fields. Approval will not automatically publish either app.
- No public release, new build upload, replacement asset upload, payment, or legal agreement acceptance was performed in this task.
- The Apps page still showed an updated Apple Developer Program agreement notice. The account API cannot establish its acceptance state. Despite that notice, Apple accepted both review submissions. The notice was preserved and no terms were accepted on the owner's behalf.
- Exactly one review submission with one version item was created per platform. Final submission was invoked once per platform.

## Validation and preserved contents

- Fresh strict App Store validation and Review Doctor checks reported zero errors, zero warnings and zero blockers for both exact selected versions. The informational API limitation on privacy publication was resolved with a fresh visible Apple App Privacy page showing the privacy declaration published.
- Both selected builds remained `VALID`, with `usesNonExemptEncryption=false`.
- All 20 screenshots remained complete and unchanged in identity, order within each set, checksum, file size and dimensions: six iPhone, six iPad, six Mac and two Watch screenshots.
- Both native simulated-data reviewer video attachments remained `COMPLETE`, with their original IDs, file names, sizes and checksums. Existing notes retain their original native recording provenance. They are not represented as newly recorded build-20 footage.
- Both platform descriptions, keywords, marketing/support URLs, promotional text, reviewer notes and private review contacts were preserved. Shared app identity, content-rights declaration, localized information, age-rating responses, primary category, free pricing and returned availability settings were rechecked.
- Public contact details remain `support@hashfleet.app`, with no public telephone number. Private review contacts were not published by this task.
- The signed iOS/Watch IPA, all five archived bundle signatures and binary hashes, signed Mac package, universal Mac architectures and sandbox/network-client entitlements were verified without installing or launching either release artifact.
- Previously completed Watch core tests (159) and native fixture UI tests (2) were checked against the unchanged source. They were not rerun in this submission task. Physical phone/Watch behavior was not recertified.
- Original tracked input bytes and symlink targets were preserved except allowed Blitz selection metadata. Unrelated owner worktree changes were not staged or reverted. The canonical installed Mac build-13 binary and Info.plist remained unchanged and were not launched or restarted.

## Retained diagnostics, not hidden passes

- The unchanged public support/contact browser suite passed all 85 assertions, including real privacy navigation, HTTPS support availability, the correct public email and absence of a public telephone number.
- Three unchanged privacy-suite attempts stopped at the final no-failed-requests assertion because navigation aborted a favicon request (`net::ERR_ABORTED`). Earlier functional checks reached that final assertion. Those runs are retained as failures, not reported as 49-test passes. No website code or assertion was weakened to obtain a pass.
- The first submission helper stopped after successfully creating each exact version item because it expected item relationships that Apple's list response omits. Apple's item resource also rejects `GET_INSTANCE`. The correction resumed the original items, using the successful exact CREATE requests and returned IDs, sole fresh item IDs, expected selected builds/platforms, and the visible Apple Ready-for-Review drafts. It did not recreate submissions or re-add items.
- Apple's iOS version briefly remained `READY_FOR_REVIEW` after its submission became `WAITING_FOR_REVIEW`. Bounded read-only checks reconciled both to `WAITING_FOR_REVIEW` without repeating submission.
- The first final read-only verifier omitted `screenshots` from its read-command allowlist and stopped before acceptance. Its script and raw run are retained. The corrected verifier includes that read-only command and does not relax content or state acceptance checks.

## Artifact identity

- iOS/Watch source revision: `a10fec115ba3f74ceed100f023eb235d4a009cd1`.
- iOS/Watch IPA SHA-256: `4813e8625bb59eb5286dc9fff6483472784fd11921c1a07434a11ded546b04cb`.
- Mac source revision: `320510d645a7e5849d13deff73d312b25ef42781`.
- Mac package SHA-256: `ab6b6fad522de7b1eccc116932142604d1ba604f07b762139f7d40c7131d070d`.
- Complete signed archives and source backups from the prior platform deliveries remain preserved. No signing private keys were exported for this task.

## Private evidence and restoration

Working evidence root: `/Users/USER/.jcode/scratch/hashfleet-submit-both-20261104T0135.noindex`.
The per-platform `*-final-submit.noindex/submission-receipt.json` files retain successful command results and exact review identities.
`independent-final-precommit-v2.noindex/acceptance.json` and `independent-final-postcommit.noindex/acceptance.json` contain the separate final all-platform readbacks.
`apple-submitted-visible-private.json` retains the fresh Apple App Review screen with both Waiting-for-Review entries.
Durable preservation target: `/Users/USER/Library/Application Support/HashFleetBackups/2026-11-04-review-submissions.noindex`.
Its manifest and verification receipt record copied evidence, original browser artifacts, exact IPA/package, this document and a verified local Git-history bundle. Existing earlier backups are not overwritten.
Raw evidence includes private review/account data and signed asset links. Keep it local and private. This document does not reproduce those values.
