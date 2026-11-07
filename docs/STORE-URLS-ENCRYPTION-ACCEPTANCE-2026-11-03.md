# Store URLs, contact, encryption and privacy acceptance

Date: 2026-11-03 UTC. Scope: the existing iOS and macOS Hash Fleet 1.0 drafts in app 6812623943, not a new app or a review submission.

## Saved on both platforms

| Field | Verified saved value |
| --- | --- |
| Marketing URL | `https://hashfleet.app/` |
| Support URL | `https://hashfleet.app/support/` |
| Shared Privacy Policy URL | `https://hashfleet.app/#privacy` |
| Shared Privacy Choices URL | `https://hashfleet.app/support/` |
| Copyright | `2026 Sean Warren` |
| Review contact | Exact supplied developer name, email and normalized phone, independently read back |
| Encryption | `usesNonExemptEncryption = false`, explicitly present on each original uploaded build |

The owner explicitly authorized public publication of their name, email and phone at 07:04:24 UTC. The real static support page now provides those details and privacy/data-removal contact instructions. No contact form, tracking scripts, account signup or unsolicited email/call was added. The technical-support page is separate from the existing optional-tipping section.

Blitz MCP performed the platform-specific metadata saves and exact-version app-information readbacks. Supported bundled ASC commands completed the exact-build encryption attribute and shared optional privacy-choice field, which were not exposed by the available MCP form tools. Apple readbacks independently confirm the saved values. Native Apple UI completed the privacy questionnaire where MCP had no supported tool.

## Original uploaded builds retained

- iOS 1.0 (18), build ID `1d98e89c-1e6f-4c8d-929f-42330e8ed314`, version ID `6e59d0e4-7087-4f1f-a39a-faeab0ab1778`.
- macOS 1.0 (19), build ID `444fc87d-9fa5-4457-8eb1-e344f05454f7`, version ID `605fc5ac-0228-4c30-8263-e8b2666f7768`.
- Both builds remain `VALID`, attached to their original `PREPARE_FOR_SUBMISSION` drafts. The review-submission list is empty.
- All 18 saved screenshots retain their original IDs, order, checksums, dimensions and `COMPLETE` delivery state. Existing descriptions, keywords, promotional text, category, age answers, free pricing and availability were retained.
- The original immutable 1,212-file accepted checkout remains revision `320510d645a7e5849d13deff73d312b25ef42781`, digest `2e9265de05ccff014771637b132d8fe50554e829249eecb04ebed7158de0655d`. Original signed artifact archive hashes were rechecked. No new native build or upload was performed for this task.

The encryption determination audited original native source, pinned dependency manifests and original iOS/Mac executables. Platform HTTPS, Keychain, secure random generation and checksum-only SHA-256 are not described as “no encryption.” No CCATS, French approval or other legal certificate was fabricated.

## Shared privacy labels published

At approximately 07:42:25 UTC the shared privacy responses were published, not the app itself. A cold page load and a second read through both data-type editors independently confirmed:

| Collected data type | Purpose | Linked to identity | Used for tracking |
| --- | --- | --- | --- |
| Device ID | App Functionality only | Yes, via installation/device | No |
| Other Data Types | App Functionality only | Yes, via installation/device | No |

These disclose the optional notification service's persistent installation identifier/APNs token and opaque miner IDs, schedule switches and intervals. The original wire schema omits miner display names, LAN addresses and readings. Collection is not incorrectly declared absent merely because it is opt-in. Developer contact details are not represented as collected user contact information.

Primary definitions: Apple's App Privacy Details and Manage App Privacy documentation. The private source-backed classification, checked UI control IDs and cold-load publication readback are retained with the evidence. Future data-practice changes require reassessment.

## Website checks and safety boundary

- Website unit checks: 163 passed. Production build passed.
- Local real-browser checks: contact 85, privacy 49, unchanged tipping 64 and native parity 207 passed.
- Actual public HTTPS checks: contact 85, privacy 49, unchanged tipping 64 and native parity 208 passed, without response interception or live miner/pool/notification API requests.
- All five published frontend asset hashes match the tested build and actual HTTPS responses. Only those five frontend files were published. Old hashed assets were retained for existing visitors.
- Before/after protected-state hashes confirm no publication changes to backend code, configuration, database, permissions, APNs configuration, cron or unrelated public files. No payment, phone action, miner operation, app reinstall or app-data reset was performed.

A pre-existing 320px footer overflow was fixed in production CSS and the unchanged tipping tests then passed. A public-test navigation timing failure was retained, then fixed by waiting for real asset loading without weakening the zero-failed-request condition. Other failed test attempts and original logs remain preserved.

## Explicit limitations and follow-ups

1. **Content Rights remains unset.** Both final MCP app-information readbacks show this. Permission to publish the developer's contact details does not prove ownership or permission for all third-party content. No answer was invented. Neither draft is claimed review-ready.
2. **Scheduled-push delivery is not accepted by this metadata work.** A fresh read-only backend code audit found legacy `org.axefleet` outgoing notification keys and APNs topic strings. Apart from those exact strings, the complete received-data/storage implementation matches the repository. The privacy classification still applies, but the deployed topic/namespace does not match the uploaded app identity. No server or APNs changes were made.
3. **Concurrent native development is not covered.** WatchOS-related working-tree changes appeared during final checks and were left untouched. Original-build acceptance is bound to immutable original artifacts, not a claim that all current repository files remain unchanged.
4. **The broader original physical-bundle census did not satisfy its unchanged-environment guard.** The failure was retained, not converted to a pass. The installed Mac app's bytes, identity, PID 70602 and sole Mac registration are unchanged. The broader discovery now also finds five simulator app/test products under a separate concurrent watchOS scratch folder. They are not additional installed Mac apps and were not stopped, unregistered or removed. The diagnostic receipt preserves their exact paths.
5. The final MCP overview refresh timed out. Previous good overviews are preserved as historical, not presented as fresh. Fresh exact-version app-information reads and independent Apple resource reads succeeded. The original aggregate verifier also had a runner-summary versus richer native-parity-artifact `cspSource` adapter error. Its failed recipe/log remain unchanged, and the scoped metadata checker validates both original artifacts at their actual serialization boundary.

## Evidence and durable preservation

Private evidence folder: `/Users/USER/.jcode/scratch/hashfleet-urls-encryption-20261103T0611.noindex`.

Durable backup folder: `/Users/USER/Library/Application Support/HashFleetBackups/2026-11-03-urls-encryption.noindex`.

The durable manifest binds the metadata snapshots, privacy/encryption determinations, all retained failures, original browser acceptance artifacts, current owned website/documentation files and Git history bundle. It contains no duplicate installable application. Earlier full-project and signed-artifact backups remain intact. The final diagnostic receipt distinguishes successful saved-metadata checks from the still-failed broader environment guard.
