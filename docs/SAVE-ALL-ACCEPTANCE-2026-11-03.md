# Hash Fleet save-all acceptance, 2026-11-03 UTC

## Saved work

The owner requested that all current Hash Fleet work be saved after the iOS and native Mac uploads. This follow-up saves draft work and creates a durable local backup. It does not submit an application for review, publish a release or change the installed application.

- The existing App Store Connect application remains **6812623943**, **Hash Fleet**, bundle **`app.hashfleet`**.
- All **18 en-US screenshots** are saved on their correct existing Apple drafts: six iPhone 6.7-inch and six iPad Pro 12.9-inch screenshots on the iOS 1.0 draft, and six desktop screenshots on the native macOS 1.0 draft.
- The six iPhone and six Mac screenshots already matched the local artwork. Their remote asset identities were retained, with no redundant upload.
- Only the six changed iPad screenshots required a save. They were saved through Blitz's scoped screenshot-save tool and independently checked afterward.
- Verification compares each image's source checksum, order, byte size, dimensions and Apple asset delivery state. All 18 are **COMPLETE** and match the preserved local originals.
- Existing **iOS 1.0 (18)** and **native macOS 1.0 (19)** remain attached to their original drafts. Both drafts remain **PREPARE_FOR_SUBMISSION**. There is no App Review submission or release.

## Durable local backup

The private backup directory is:

```text
/Users/USER/Library/Application Support/HashFleetBackups/2026-11-03-save-all.noindex
```

The initial verified backup preserves **1,532 meaningful project, source and marketing files**, repository history, the additional ignored source stub, both accepted signed delivery artifacts and their signed archive ZIPs, and delivery receipts. Its 12 artifact entries total **732,893,727 bytes**, with every copied byte rehashed. Generated dependency/build/browser caches are excluded. No private signing key was exported and no additional active app bundle was created.

Original local screenshot artwork and the pre-save Apple screenshot originals were preserved before the scoped iPad save. The save receipts, originals, final verification evidence and this acceptance document are added separately to the durable backup. This is a local backup on this Mac, not an off-machine or cloud backup.

## Local UI cache boundary

All screenshot **contents** are saved on Apple. Blitz's old iOS-local cache still reports duplicate staged iPhone slots and desktop slots as changed, even though their image bytes already match the saved correct-platform assets. A standard refresh did not clear these local flags. They were preserved rather than deleting staged artwork, reuploading identical images, restarting Blitz or saving desktop images to the wrong iOS localization.

The existing native Mac draft is selected at the end of this task and shows six synced desktop images, no pending change and no image errors. Global clearance of all historical iOS-local cache flags is **not** claimed. The earlier failed local UI-state assertion remains retained as a diagnostic, not converted to a passing result. Apple-side content verification is the authority for the saved images.

## Preservation and verification

- Accepted application revision remains `320510d645a7e5849d13deff73d312b25ef42781`, with the unchanged 1,212-file verification checkout and digest `2e9265de05ccff014771637b132d8fe50554e829249eecb04ebed7158de0655d`.
- Existing owner changes and untracked marketing/screenshot sources are preserved and backed up, not reverted or indiscriminately committed. Only this owned acceptance document is committed for the save-all follow-up.
- Final checks re-read both Apple platform drafts, build processing and relationships, all 18 screenshot contents, review-submission absence, original local source bytes, backup hashes and repository history, and the canonical installed app's full bundle/process and one-app inventory.
- No Store package was installed or launched. The direct-distribution `/Applications/Hash Fleet.app`, bundle `app.hashfleet.mac`, build 13, is not restarted or modified. No phone, saved user data or mining hardware operation is part of this task.
- Saving does not make the drafts review-ready. Required metadata, privacy declarations and any applicable encryption confirmation remain separate work and must not be invented or submitted without authorization.

Private task evidence is retained in `/Users/USER/.jcode/scratch/hashfleet-save-all-20261103T0040.noindex`, with durable evidence also saved in the backup directory. Final receipts bind the actual documentation commit and explicitly retain the duplicate-cache limitation.
