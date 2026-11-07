# Hash Fleet App Store delivery, 2026-11-02

## Delivered, not published

- Existing App Store Connect app **6812623943**, name **Hash Fleet**, SKU **axefleet-app** was retained. No second store app was created and no listing was deleted.
- Its previously unused `org.axefleet.app` draft was aligned to **`app.hashfleet`** before the first upload. Independent reads confirmed exactly one matching store record and no store record remaining under the old bundle ID. Installed application identities, the shared app group and source identifiers were not changed.
- **Version 1.0, build 18** was uploaded once. Apple processed build **1d98e89c-1e6f-4c8d-929f-42330e8ed314** as **VALID**.
- At **23:49:27 UTC**, independent version and build-relationship reads confirmed that build 18 is attached to the existing draft **6e59d0e4-7087-4f1f-a39a-faeab0ab1778**. State remains **PREPARE_FOR_SUBMISSION**.
- No App Review submission, public release, beta review submission or tester-enrollment action was performed. This is not a published App Store release.

## The gray icon and duplicate entry

The former dashboard showed the old store identity as **Hash Fleet** with an `H` placeholder, alongside **hashfleet / Local only** for the working project. These were two entries, not two released versions. A linked local source directory alone did not constitute an App Store upload. The earlier source-link status should not be interpreted as one.

After the existing store record was aligned, a normal Blitz dashboard refresh reconciled it with the unchanged local project. The actual accessibility tree contained exactly one **Hash Fleet** card, no **Local only** card and no `H` placeholder. Deleting the repository, its Blitz symlink, or the store listing was unnecessary and was not done.

The refreshed Blitz overview reports **App Icon: Configured** and **Build: 18**, both saved to ASC. Apple returned two 1024-pixel App Store icon resources. Both downloaded 256-pixel images were visually inspected and show the correct orange miner and black fan, including the rounded masked icon. The masked resource's generic `Placeholder.mill` filename is not evidence of a gray placeholder image. Actual native Blitz pixels also show the real icon in the project sidebar.

The cached Builds-tab MCP response was still empty when queried without navigating to that tab. This does not supersede the independent Apple build lookup or the selected draft's build-18 relationship. Current owner screenshot drafts were left open and were not imported, saved, replaced or discarded by this delivery task. The prior application focus was restored after visual inspection.

## Source, signing and artifacts

- Audited source revision: `320510d645a7e5849d13deff73d312b25ef42781`.
- Clean verification checkout: 1,212 tracked files. Its source digest is `2e9265de05ccff014771637b132d8fe50554e829249eecb04ebed7158de0655d` using the store receipt's path/file-hash algorithm.
- Committed root `Package.resolved` SHA-256: `f97bd149ccd6810cc2833172c19b3a50b60c7f5217f0481cbaa8ddc4581d851d`. Package versions were not updated.
- Existing Apple Distribution certificate was reused. Three target-specific App Store profiles were prepared for the main app and both extensions. No certificate was created or revoked.
- Version/build, signing-profile selection and production APNs were provided through an external archive configuration. No application or test source was edited for this upload.
- Main app and both extensions passed strict signature, identity, version, arm64, App Store profile and shared-group checks. The iPhone/iPad universal icon assets were verified in the signed archive and exported IPA.
- Uploaded IPA SHA-256: `06a9b94c45d1952f606595808a5d0efe74d8dabd4c7eb68690c6611b76e44f9e`, size 51,910,950 bytes.
- The complete signed archive was preserved as a verified ZIP, SHA-256 `92ff5351df97749c4634befd398635c89bf890fd7ae74a42979bc14bda3a3973`. Every original file and symlink was checked. Only the generated store staging app was exactly unregistered and reversibly retired, with its signatures preserved.
- Post-build hygiene passed at **23:55:48 UTC**. The canonical `/Applications/Hash Fleet.app` bytes and process were unchanged. Global physical, existing-path LaunchServices, Dock and process checks found only the canonical Mac app. The phone was not reinstalled or reset.

## Retained refusals and measurement limits

1. The first archive helper stopped before building because its scratch lockfile path was wrong. The actual committed root lockfile was independently verified and only that scratch path was corrected.
2. The single store-identity write succeeded, but an immediate read still returned the old value and failed its guard. That failure was retained. Later independent read-only checks verified propagation without repeating the write.
3. Blitz's preferred MCP upload tool refused before transfer because the existing signed IPA lacks `ITSAppUsesNonExemptEncryption`. Its bundled ASC CLI then uploaded the same verified IPA, without inventing an encryption declaration or changing audited source. **Encryption compliance is not confirmed for distribution.**
4. A scratch draft-relationship check initially rejected the CLI's empty relationship representation, `{"type":"","id":""}`. The observed empty-ID shape was handled while preserving the requirement that any nonempty relationship match this exact draft. No build attachment had occurred before that check stopped.
5. Stage Manager thumbnail captures and a failed web image-viewer fetch were not counted as full-size visual evidence. Subsequent normal native-window pixels and both actual Apple CDN icon images were inspected.
6. The first post-documentation final check stopped at 00:00:33 UTC on November 3 because the legacy `appStoreVersionSubmission` relationship read returned resource-not-found. The failed script and its original exit were preserved. Supported independent reads then showed an empty, fully paginated review-submission census and this exact draft's submission status with an empty submission ID and PREPARE_FOR_SUBMISSION state. The final verifier uses both supported checks while retaining every source, artifact, build, icon and app-preservation predicate.

## Remaining release work

The draft still requires its review metadata, privacy declarations, applicable encryption confirmation and screenshots to be completed and verified before any separately authorized review submission or release. Existing owner marketing work is outside this task's edit boundary. No readiness claim is made for those remaining items.

Apple reference for the optional property-list key and later questionnaire: `https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption`.

Private, non-repository evidence is retained under the `store-handoff-20261102T2330.noindex` directory in the existing rollout scratch root. Relevant receipts include `store-identity-aligned.json`, `store-archive-verified.json`, `store-upload-command-finished.json`, `store-upload-processed-and-draft-linked.json`, `blitz-refreshed-state-private.json` and `store-post-build-hygiene.json`. These records contain the historical steps and do not turn prior refused or failed attempts into passes.
