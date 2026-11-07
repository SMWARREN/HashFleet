# Hash Fleet store metadata acceptance, 2026-11-03 UTC

## Scope and saved fields

The owner requested that Blitz MCP fill all verifiable information for the iOS and native macOS listings. These are two platform drafts under the existing **Hash Fleet** App Store Connect application **6812623943**, bundle **`app.hashfleet`**, not two new applications. This follow-up saves metadata only, without submitting for review or publishing a release.

| Existing platform | Version | Original attached build | State |
| --- | --- | --- | --- |
| iOS, including iPad | 1.0 | 18 | PREPARE_FOR_SUBMISSION |
| Native macOS | 1.0 | 19 | PREPARE_FOR_SUBMISSION |

- Both en-US drafts now have independently verified, platform-specific descriptions and promotional text, the shared keywords, and the working marketing homepage `https://hashfleet.app/`.
- The existing title **Hash Fleet** is retained. The shared subtitle is **Your miners. One clear view.** The primary category is **Utilities**.
- Both descriptions distinguish direct local hardware monitoring from on-device cryptocurrency mining. They describe sample-fleet review, firmware-dependent readings, confirmation-gated controls and optional support without inventing locked features or continuous background monitoring.
- iOS copy explains opt-in aggregate widget snapshots, foreground Live Activity updates and default-off, best-effort scheduled push checks. Mac copy describes the single native application, workspace and menu-bar lifecycle, not an iPad wrapper or separate companion.
- Blitz MCP saved the listing copy and a **free** price schedule. The pricing operation also configured territory availability, including availability in new territories. Apple's independent current-price readback reports `0.0 USD` and `isFree: true`.
- No first-version What's New text was fabricated.

## Completed age rating

The shared age questionnaire is saved, and Apple computed **4+**, with no Kids-category selection or age-rating override.

Blitz's current MCP and bundled CLI model only the older 22 answers. Apple rejected the initial MCP save because its current questionnaire also requires `socialMedia` and `socialMediaAgeRestricted`. After preserving those diagnostics, the current 24-field questionnaire was completed through the existing authenticated App Store Connect browser page. All applicable feature answers are No and all content-frequency answers are None, based on the inspected hardware-monitoring application.

Independent Apple reads verify the 22 modeled answers and `FOUR_PLUS`. A fresh browser navigation and read-only inspection verify both additional social-media answers as No. The inspection was canceled without changes. Fully loaded MCP review states for both exact platform versions also report the shared age declaration saved, with no missing age answers.

An earlier iOS MCP capture had `isLoading: true` and was not a completed readback. The later fully loaded result is retained separately. The unsupported local `socialMedia` draft flag remains in Blitz and is not a claim that Apple's saved declaration is missing. No local cache or staged artwork was deleted to clear cosmetic flags.

## Reviewer instructions and genuine limits

- **Mac reviewer notes are saved on Apple**, exactly matching the prepared platform-specific instructions. They explain how to enter and exit the sample fleet without hardware or credentials, direct-network requirements, lifecycle and confirmation boundaries.
- **iOS reviewer notes are prepared and backed up but are not saved on Apple.** Both MCP's validation and the narrow existing-resource Apple update require a review contact before accepting that save. The iOS resource remains unchanged and empty. A local pending Blitz draft is not claimed after refresh.
- Both platforms still need the owner's verified review contact first name, last name, email and international phone number. No account email was borrowed from another browser tab and no contact was invented.
- MCP was used for the main work. A narrow supported CLI fallback created the previously absent Mac review-notes resource. Its response omitted the false/default login-requirement attribute, which caused an initial over-strict verification assertion. Exact notes persistence and the no-login requirement were then independently verified. The initial failure and actual iOS contact-validation failure remain retained, not relabeled as successful writes.

## Information deliberately not guessed

1. **Support URL:** `https://hashfleet.app/support` returned 404. The homepage's support section is optional tipping, not a verified technical-support contact page.
2. **Privacy policy URL:** `https://hashfleet.app/privacy` returned 404. The working homepage privacy modal does not establish a direct policy permalink. A broken route or unrelated homepage was not entered as a policy URL.
3. **Copyright and content rights:** the exclusive-rights legal person or entity and the all-content rights attestation have not been confirmed. The public brand footer is not proof of legal ownership.
4. **Privacy nutrition labels:** not published. Older repository privacy prose is incomplete for optional scheduled push, which can send an APNs token, installation credential hash and opaque scheduling data. Retention, linkage and applicable disclosures need owner confirmation rather than an unsupported no-data-collected claim.
5. **Export compliance:** no legal encryption declaration or exemption was changed without verified applicable evidence.
6. **Account-holder action:** Apple's Apps page displays an updated Apple Developer Program License Agreement notice requiring Account Holder review and acceptance. The agreement was not accepted on the owner's behalf.

The existing standard EULA and other legal declarations are not changed. These remaining requirements mean the drafts are **not claimed submission-ready**.

## Preservation, checks and backup

- Original iOS build 18 and native Mac build 19 remain VALID and attached to their original version identities. The review-submission list remains empty.
- All 18 original screenshots are checked by existing remote identity, order, checksum, byte size, dimensions and COMPLETE delivery state. No screenshot is replaced or redundantly uploaded in this task. Historical iOS-local duplicate screenshot flags remain outside this metadata save.
- Accepted application code remains revision `320510d645a7e5849d13deff73d312b25ef42781`. The original 1,212-file verification checkout retains digest `2e9265de05ccff014771637b132d8fe50554e829249eecb04ebed7158de0655d`. Production and test files are compared with that checkout.
- Existing owner documentation, screenshot and marketing files remain intact. The intentionally updated local `.blitz/project.json` is preserved separately and is not indiscriminately committed. Only this owned acceptance document is committed.
- The canonical installed `/Applications/Hash Fleet.app`, bundle `app.hashfleet.mac`, build 13, is neither changed nor restarted. Checks compare its full bundle bytes, original process and one-app inventory. No phone, app-data or mining-hardware operation is part of this work.
- Exact payloads, Apple before/after reads, MCP outcomes, prepared iOS reviewer text, browser-only age evidence and retained failures are kept privately at `/Users/USER/.jcode/scratch/hashfleet-store-metadata-20261103T0227.noindex`.
- Durable local evidence, the final document, updated local Blitz metadata and an incremental Git history bundle are saved under `/Users/USER/Library/Application Support/HashFleetBackups/2026-11-03-store-metadata.noindex`, with a manifest and rehashed archive members. This is a local backup on this Mac, not an off-machine backup. Existing signed-artifact and source backups are not replaced.
- The final read-only verifier runs after the documentation commit and binds its observed results to that exact commit. Earlier failures and ambiguous intermediate observations remain available, with explicit clarifications rather than replacement results.

No review submission, release, rebuild, binary upload, tester action, privacy-label publication, website deployment, installed-app restart or legal-agreement acceptance is authorized or performed by this metadata task.
