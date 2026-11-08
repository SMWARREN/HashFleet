# Six-tier iPhone and native Mac tip jar, November 8, 2026

## Operator request and scope

At 18:26 UTC the operator requested additional USD 20, 50 and 100 tips, then explicitly required the iPhone and Mac apps to contain the same options. These extend, rather than replace, the existing USD 1.99, 4.99 and 9.99 tiers. All are optional consumables with no feature unlocks or recurring billing. Prices shown by the application continue to come from StoreKit's localized `displayPrice`.

Both existing platform records belong to App Store Connect app `6812623943`, bundle `app.hashfleet`: iOS version `6e59d0e4-7087-4f1f-a39a-faeab0ab1778` and native macOS version `605fc5ac-0228-4c30-8263-e8b2666f7768`. Current readback confirmed both, rather than inferring platform support from listing copy. The separately distributed Mac application's external-support behavior is preserved.

## Added products

| Product ID | Name | Apple ID | Exact US base price |
| --- | --- | --- | --- |
| `app.hashfleet.tip.supporter` | Supporter Tip | `6832323147` | USD 20.00 |
| `app.hashfleet.tip.champion` | Champion Tip | `6832323181` | USD 50.00 |
| `app.hashfleet.tip.patron` | Patron Tip | `6832323269` | USD 100.00 |

Apple returned the exact requested price points. Creation, en-US localization and price readback succeeded for all three. No substitution with 19.99, 49.99 or 99.99 was made. The original three products remain intact. All six use the shared production enum and Core approved-ID set.

## Code validation checkpoint

The four-file source/test change adds the three enum cases, titles, symbols and IDs. Transaction signature/revocation/type validation, purchase serialization, shared finishing, pending callbacks and App Store versus direct-distribution gating are unchanged. New deterministic coverage exercises the real purchase gate with a synthetic closure for every tier, without invoking StoreKit purchases or listeners.

Exact production source/test copies passed 21 tests in two suites for each of the App Store Mac and direct-distribution Mac variants, raw exit zero. This verifies shared logic and gating, not a live catalog, native iPhone layout or TestFlight purchase UI. Native UI and archive checks subsequently passed as recorded below. Live catalog and physical installation remain unverified.

## Delivery boundary

Build 22 contains only the earlier three-tier implementation. The six-tier changes require new binaries on both iPhone and native Mac. Build 23 is reserved for this paired internal testing delivery, subject to successful validation and fresh Apple build-number checks. No App Review submission, external beta review submission, real purchase or production release is authorized or performed. Paid-account agreement status and live sandbox behavior remain unverified.

Private evidence is retained in `~/.jcode/scratch/hashfleet-stability-20261108T0110.noindex/six-tier-iap/`. Original stability investigations remain open.

## Native UI and artifact checkpoint, 18:49 UTC

Mac hosted XCTest passed one test with all six local StoreKit consumables and exact Decimal prices, zero transactions. Root inspected the genuine 2560x1600 JPEG and all six tier prices. iPhone `iphone-capture4` passed one hosted XCTest plus 21 Swift Testing methods. Root inspected the actual `native-tip-jar-iphone-bottom-v2.png` (1179x2556) showing all six tiers. No purchases occurred. These are isolated production-view/local StoreKit tests, not live TestFlight catalog acceptance.

Earlier iPhone harness failures are retained: an incorrect worker-authored App type copy failed compilation, then the inert legacy UIKit host failed the SDK scene-lifecycle requirement. Root replaced the scratch App copy with exact production source minus its entry annotation and adopted an inert scene-based host. Production app code was unchanged. The first successful capture did not show the complete last tier. The final successful capture scrolls again after lazy list layout, preserving unedited production UI.

All six ASC products now read back `READY_TO_SUBMIT`, not submitted. New review assets are `COMPLETE`, 2560x1600: Supporter `e8be9981-e814-446c-b880-0be828095070`, Champion `fa1193e5-31ed-40d1-9d16-5b98d280607d`, Patron `fa08f828-4942-4033-a2e1-834161bf7592`. The first upload command timed out during Apple processing. Readback showed its existing asset completed, so it was reused without deletion or duplicate upload. Original three review assets remain unchanged.

Both signed build23 artifacts use source `6cd62c04e7f13ac340b037a61ad1448c331893b3`. The isolated iOS snapshot adds only the established parent export encryption declaration. All other 1,294 tracked files and the live repository inputs remained unchanged.

- iOS/Watch: archive/export succeeded, all five signed bundles at1.0/23 with expected App Store profiles, architectures, app groups and no debug entitlement. Parent remains iPhone/iPad universal with production APNs. Watch and complications retained. IPA54,857,294bytes, SHA256 `07fbc8a1dae1bec9016f900e23f16c8ee00c4056abd885de4259fa9eb8021c40`.
- Native Mac: archive succeeded, Store bundle `app.hashfleet`, arm64/x86_64, sandbox, direct-distribution flag absent. Exact app/installer certificates and strict signatures verified. All17 extracted payload files match archive bytes and are world-readable with executable bits preserved. PKG33,658,482bytes, SHA256 `b57a6415883cc855fea884889671e40d739d41510fc1a3259869461a5a5cfeb1`.

Both uploads completed. Independent authenticated readbacks verified native Mac build `20eaa96f-e242-4b4c-a43e-99ef76ff3ee1` at18:51:50 UTC and iOS build `808a61ee-43c8-40b1-8670-c7f7385142eb` at18:56:03 UTC. Both are version1.0/build23, `VALID`, `IN_BETA_TESTING`, with actual relationships to existing internal group `88a67a69-21fd-4992-80e9-cf931d7de92c` (Owner Mac Testing). No beta-review submission exists. Both rejected public version records and their attached builds remain unchanged. Exact test notes warn that live catalog and physical acceptance remain unverified and no real purchases should be made.

## Installation preference and local app removal

At18:54-55 UTC the operator clarified that they will install both apps themselves from TestFlight and requested removal of the existing Mac app. No physical-phone installation or launch occurred. A read-only device listing was the only physical-device operation. No direct installation on either platform is authorized by this delivery.

The only installed Hash Fleet bundle found in standard Applications locations was `/Applications/Hash Fleet.app`, bundle `app.hashfleet`, version1.0/build21, not running. A shell move was denied by permissions. The standard Finder Trash operation subsequently moved it to `~/.Trash/Hash Fleet.app`; root readback at18:56:22 UTC confirmed the Applications copy absent and Trash copy present. Only the application bundle was removed. Saved application data and preferences were not touched. The user will install build23 from TestFlight.

Owned iPhone/Mac capture hosts were absent at18:51:59 UTC. Diagnostic failures and artifacts remain preserved. The six-tier implementation, metadata and internal delivery are complete. Live StoreKit catalog, paid-account readiness and physical-device behavior remain separate unverified acceptance items.

## Superseding App Review authorization and submission, 19:24 UTC

At19:00:53 UTC the operator reported that the iPhone app was working well and authorized resubmission with the changes. At19:03:31 UTC they requested automatic completion. The coordinator explicitly confirmed submission when ready and automatic release after Apple approval. This supersedes the earlier no-submission boundary above, but does not authorize physical-device installation or real purchases.

Both version1.0/build23 binaries were submitted on November8,2026 and independently read back by the coordinator as `WAITING_FOR_REVIEW`, with `releaseType: AFTER_APPROVAL`:

| Platform | Selected build ID | Review submission | Submitted UTC |
| --- | --- | --- | --- |
| iOS | `808a61ee-43c8-40b1-8670-c7f7385142eb` | `296b8952-8b88-4f3d-9890-d888cbf0d2ae` | 19:23:26.503 |
| Native macOS | `20eaa96f-e242-4b4c-a43e-99ef76ff3ee1` | `ce8e7cd8-2cec-4b98-aaea-f52972ce0ca6` | 19:24:03.830 |

The iOS submission contains exactly seven items: the iOS app version and all six shared consumable IAP versions. The native Mac submission contains its app version, with those same shared products submitted concurrently in the iOS package. Neither platform is approved or publicly released by these receipts. The operator's positive iPhone report is user-reported acceptance, not a verified purchase-flow test.

Updated reviewer notes identify build23, all six optional non-recurring tips, suppression of external PayPal and crypto controls on Store builds, hardware-free demo steps, VPN clarification and genuine local-StoreKit screenshot provenance. Existing listing localizations and historical demo-video attachments were preserved. The historical videos are explicitly not build23 footage.

Apple's legacy product-root states disagreed: public API `READY_TO_SUBMIT` versus Iris `MISSING_METADATA`. No causal explanation or paid-agreement inference was established. The actual current portal uses versioned IAP review items. All six exact `inAppPurchaseVersion` relationships were verified before submission. The old rejected iOS submission would not accept additional items (HTTP409), so it was canceled to consolidate the app and six tips in a new draft. Apple returned submission `COMPLETE` with its sole item `REMOVED`, not literal `CANCELED`; the first strict assertion failure is retained. A separate guarded recovery verified that precise state before attaching the app. The old review history remains intact. Mac reused its existing submission after Update Review.

Private receipts and scripts are in `~/.jcode/scratch/hashfleet-stability-20261108T0110.noindex/resubmit23/`, particularly `IOS-submitted-readback.json`, `MAC_OS-submitted-readback.json`, `ios-consolidated-review.json`, and the preserved validation, failure and note records. Automatic release is configured, not a promise of approval. Paid-account readiness, live purchase acceptance and the remaining stability investigations are not certified by submission.

Elephant's independent fresh authenticated readback at19:25:25 UTC confirmed both app versions and submissions `WAITING_FOR_REVIEW`, both exact build23 IDs, `AFTER_APPROVAL`, and item counts7/1. All six IAP **version resources** also report `WAITING_FOR_REVIEW`; their submission-item wrapper resources still report `READY_FOR_REVIEW`, so those two fields must not be conflated. Root inspected the actual saved audit, SHA256 `2654a7429baf824e8bb3216ffb1ddbc771d6d73e07b4f98af0ed779fd073cf3e`, at `final-independent-readback.json`. Root submission receipt hashes are `e42d67ab3c88d8b730a07311fd5f7d958e2feca7061d4a1bb9da5f527201456a` (iOS) and `bf6df1693d3469d30cffcbc3f7f26be67b95463684753b70f6602dee36e5c873` (Mac).
