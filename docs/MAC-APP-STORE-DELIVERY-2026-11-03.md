# Hash Fleet native Mac App Store delivery, 2026-11-03 UTC

## Delivered, not published

- The existing App Store Connect app **6812623943**, **Hash Fleet**, bundle **`app.hashfleet`**, was retained. No additional store app was created and no listing was deleted.
- Native **MAC_OS version 1.0, build 19** was accepted and processed as **VALID** at **00:32:50 UTC**. Apple build ID: **444fc87d-9fa5-4457-8eb1-e344f05454f7**.
- Independent version and build-relationship reads confirmed attachment to the existing macOS draft **605fc5ac-0228-4c30-8263-e8b2666f7768**. The draft remains **PREPARE_FOR_SUBMISSION**.
- No App Review submission, release, beta review submission or tester-enrollment action was performed. This is an uploaded build, not a published Mac App Store release.
- The existing iOS version 1.0 build 18 was not replaced or reuploaded. Its separate iOS draft remains unsubmitted under the same store app.

## Source and native Store configuration

- Accepted code revision: `320510d645a7e5849d13deff73d312b25ef42781`. The clean verification checkout contains 1,212 tracked files, with path/file-hash digest `2e9265de05ccff014771637b132d8fe50554e829249eecb04ebed7158de0655d`.
- Root `Package.resolved` SHA-256 remains `f97bd149ccd6810cc2833172c19b3a50b60c7f5217f0481cbaa8ddc4581d851d`. Dependencies, application source, tests and project files were not edited for this delivery.
- The original native macOS archive was built once using Blitz's bundled ASC CLI. It contains both **arm64 and x86_64**, the native Mac icon, a Mac App Store profile, sandbox and network-client entitlements, and no debug entitlement.
- Version/build, manual signing, the shared Store identity `app.hashfleet`, both architectures and removal of `HASHFLEET_DIRECT_DISTRIBUTION` were supplied through an external Store-only archive configuration. The installed direct-distribution app's configuration was not changed.
- The installed `/Applications/Hash Fleet.app` retains bundle ID **`app.hashfleet.mac`**, build **13**. No Store package was installed or launched, and no saved-data migration between these two identities was performed or tested.

## Signing and retained failures

- The existing Apple Distribution app-signing certificate was reused. Exactly one missing **MAC_INSTALLER_DISTRIBUTION** certificate and one **MAC_APP_STORE** provisioning profile were created. No certificate was revoked.
- The installer certificate is resource **W848AFW8GH**, SHA-256 `efb3a876e071b70d44ef822f74288a5f38c95fed5ec46e23408d48c5e63d1560`. Its leaf fingerprint was independently matched to the signed package and its Apple chain was verified. The profile is **FYFD45KPCW**, **Hash Fleet Mac App Store 20261103**.
- Three local helper failures remain preserved: an incompatible private-key import format, an optional certificate-extraction argument form, and a signature-status wording check that expected the outside-Store Developer ID text. The original successful archive was resumed without rebuilding. Actual app signatures, profile, installer certificate type and chain were checked independently rather than waived.
- The **first package upload failed**. Apple upload **47efcd21-ed96-4f96-8f94-e9b6134ecb35** has state **FAILED**, error **90255**, and the command exited 1. The API supplied the numeric error, not a full diagnostic explanation.
- A local payload audit found `Contents/_CodeSignature/CodeResources` at mode **0600**. A new staged copy changed exactly that file's mode to **0644**, retaining every signed content byte. No code rebuild or main-app resigning occurred. Every payload file's read bits and directory/executable traversal bits were then verified, together with strict app signatures, exact installer identity and payload byte equality.
- Only after independently confirming the original failed state and absence of a Mac build was the corrected package uploaded through Blitz's bundled ASC CLI. That command exited 0 and Apple processed build 19 as VALID. There were **two native package upload attempts and one accepted Mac build**, not one uninterrupted successful attempt.
- Local SHA-256 values were checked throughout. The upload CLI reported that Apple supplied no transport checksums, so API checksum verification is not claimed.

## Preserved artifacts and single-app hygiene

| Artifact | SHA-256 |
| --- | --- |
| Accepted `HashFleet-MacStore-1.0-19-readable.pkg`, 33,190,125 bytes | `ab6b6fad522de7b1eccc116932142604d1ba604f07b762139f7d40c7131d070d` |
| Corrected signed app ZIP | `4ba5219fc2caaf68d41d726ecaadda2a8f24f5ede5b25648d2103f9bfce66f43` |
| Original rejected `HashFleet-MacStore-1.0-19.pkg` | `ab13ae88b1d967582d5f7a0363a09f8f89cdfe25ff2dfef4d97e415522930962` |
| Complete original signed archive ZIP | `04d31f72da630dce99f9d2c31ab68937fbbc326fcfd71c58d6dcaf3726665570` |

The original archive ZIP preserves all 22 original files and symlinks, including the original restrictive permission. It is historical build evidence, not the permission-corrected delivery artifact. The corrected signed app ZIP and accepted package are preserved separately.

Original and corrected generated app copies were exactly unregistered where registered and reversibly retired in nonindexed staging. No extra app was launched. Full canonical bundle hashes and the original running process were unchanged. Global physical bundle, existing-path LaunchServices, Dock and process checks found only the canonical installed Mac app. Cleanup did not restart or reinstall it, alter application settings/history, touch the phone, change other applications or operate miner hardware.

## Blitz drafts and verification boundary

Blitz's currently selected version remained the existing iOS draft. The selected MCP build/upload interface describes IPA operations, so the native archive and PKG upload used its bundled ASC CLI without changing project platform metadata or selecting another version. Server-side Apple build and relationship reads, not a cached Blitz Builds-tab response, establish delivery.

All **18 unsaved owner screenshot slots**, six each for iPhone 6.7-inch, iPad Pro 12.9-inch and desktop, were preserved. Read-only before/after state checks retained their selected version, slot IDs, paths, source and unsynced flags. No screenshots were saved, discarded, imported or replaced, and no marketing changes were staged for this delivery.

The post-documentation verifier rechecks the exact Apple build and draft, unsubmitted state, unchanged iOS build 18, accepted source and package hashes, rejected-upload evidence, signatures and payload permissions, preserved ZIPs, canonical bundle/process/global app census, and all pending screenshot slots. Its timestamped receipt is retained privately rather than treated as a new application test run.

This task verifies upload and processing, not Store-installed runtime behavior or cross-identity data migration. Review metadata, privacy declarations, applicable encryption confirmation and screenshots still require completion and verification before a separately authorized review submission or release. Encryption compliance is not asserted by successful upload.

Private evidence is retained under `/Users/USER/.jcode/scratch/hashfleet-blitz-rollout-20261102-1000.noindex/mac-store-handoff-20261103T0012.noindex`. Principal receipts include `mac-archive-verified.json`, `mac-post-build-hygiene.json`, `first-mac-upload-failed-apple-private.json`, `mac-corrected-package-verified.json`, `mac-upload-processed-and-draft-linked.json`, both screenshot draft snapshots, and the timestamped `mac-final-readonly-*.json` final result. Failed scripts, original package and original upload results remain preserved as failures.
