# Native Mac IAP repair and internal TestFlight delivery, November 8, 2026

## Authorized scope

The operator authorized creating the IAP configuration, accepting necessary agreements if needed, and delivering a test build. App Review submission, external beta review submission, real purchases and production release remain prohibited. No agreement acceptance was performed during this delivery. Internal TestFlight delivery did not require an additional acceptance step. Paid-app agreement, banking and tax readiness for live IAP sales is not certified by these results. No banking or tax information was invented or changed.

## Recovered access

The earlier cached-session HTTP 401 and failed bridge/MCP attempt were route-specific failures, not proof that App Store Connect was unavailable. Blitz reconnected, the Apple web API returned HTTP 200, and the existing `/Users/USER/.blitz/bin/asc` authenticated CLI worked. No new API key or signing certificate was created. The app is the existing native `MAC_OS` app `6812623943`, bundle `app.hashfleet`, not an iOS-only release or a proposed Catalyst conversion.

## Three consumable drafts

| Product ID | Apple ID | en-US name | US base price |
| --- | --- | --- | --- |
| `app.hashfleet.tip.small` | `6832315570` | Small Tip | USD 1.99 |
| `app.hashfleet.tip.medium` | `6832314110` | Medium Tip | USD 4.99 |
| `app.hashfleet.tip.large` | `6832315156` | Generous Tip | USD 9.99 |

All three have the localized description `Optional support for development. No feature unlocks.` Prices and localization were read back independently. The initial small-tip setup partially succeeded, then rejected a description longer than 55 characters. Its existing product was repaired without creating a duplicate.

Availability was configured to exactly the app's existing 175 territories, with `availableInNewTerritories=true` matching the existing app. Separate authenticated relationship GETs verified all 175 IDs for each product. The app's own territory selection was not changed.

Reviewer notes describe About Hash Fleet > Support Hash Fleet, optional native StoreKit tips, no feature unlocks, no purchase requirement, and removal of external payment controls from the new Store build. Each note was read back exactly. After the screenshot work below, separate product queries at 18:13 UTC returned `READY_TO_SUBMIT` for all three consumables. These drafts have not been submitted, approved, or demonstrated to load through Apple's live sandbox catalog.

## Native Mac build 22

- Source: clean `d3ea64ca9885f5639e7d1569f5657ad3433af65d`, containing the StoreKit implementation committed in `18d8f21` and telemetry clear/flush ordering fix `8a79e3a`.
- Native scheme: `HashFleetMac`, Release, generic macOS destination.
- External Store-only configuration: bundle `app.hashfleet`, version `1.0`, build `22`, `arm64 x86_64`, manual existing Store provisioning profile, sandbox and hardened runtime enabled.
- `HASHFLEET_DIRECT_DISTRIBUTION` absent from effective settings and compile invocations. The installed direct-distribution application was not launched, replaced or reconfigured.
- Archive completed with raw exit 0 in 121.4 seconds. The new tip-jar Swift sources appear in the compile log.
- Strict archive and extracted-package app signatures passed. The exact existing Apple Distribution certificate and Store installer certificate were verified. Profile identity, platform and expiration were checked.
- A new scratch staging copy corrected readability without changing signed file bytes. All 17 packaged regular files match the original archive and are world-readable. The extracted app passes deep strict codesign verification.
- Two verifier failures are retained: incorrect optional-argument syntax for certificate extraction, then an inappropriate Developer ID trust-status string expectation. The final verifier instead checks the exact Mac App Store installer certificate fingerprint and Apple certificate chain. Neither failure required a source or binary change.

Package: `HashFleet-MacStore-1.0-22.pkg`, 33,657,580 bytes.

SHA-256: `050afe379fafd736943a297c508f012491d972154926e00c5730fa14a1f95acd`.

Binary SHA-256: `eaa249a436b06b63d9bd718e237064a2f7050fb17f06c51d0e50257d19b77c6e`.

Apple upload/build ID: `6cf8c034-2c25-4999-8e30-7371077644d0`. Upload completed with raw exit 0, and a separate build query returned `VALID`, version `22`, prerelease `1.0`, platform `MAC_OS`.

## Internal TestFlight only

Build 22 was added to the existing **Owner Mac Testing** internal group `88a67a69-21fd-4992-80e9-cf931d7de92c`, without the CLI's `--submit` option. No new testers or external groups were added.

The pre-existing Mac builds 19 and 21 both declare `usesNonExemptEncryption=false`. Current source checks found platform StoreKit/Security/CryptoKit usage and no change to the existing cryptographic source or package dependency list relative to preserved baseline `6140a1b`. The same declaration was applied to build 22. This does not mean the app uses no cryptography. A historical source comparison using `320510d` was unavailable in this checkout and was not credited as a successful comparison.

Apple's build-beta detail readback at 17:58 UTC reports `internalBuildState=IN_BETA_TESTING` and `externalBuildState=READY_FOR_BETA_SUBMISSION`. The beta-review query reports no submission. Initial test notes identified incomplete product metadata. At 18:18 UTC the notes were updated and read back exactly to reflect all three drafts being Ready to Submit, while retaining the unverified live sandbox/TestFlight UI warning, no-real-purchase instruction, and unresolved Charts, long-running reconnect and startup investigations. Internal testing availability is not proof that the owner downloaded or ran the build.

## Genuine native review screenshot, 18:13 UTC

An isolated native Mac XCTest host rendered the unchanged production `DeveloperSupportView`, using real StoreKit `Product` objects from a local Xcode catalog matching the saved product IDs, names, descriptions and US prices. It did not construct the normal application or FleetStore, launch the installed app, or invoke a purchase. The test asserted zero local transactions before and after rendering. Root visually inspected all three visible tiers and the no-feature-unlock copy. This is a native production-view capture with local catalog data, not a capture of the distributed TestFlight binary or proof of live catalog availability.

The final JPEG is 2560 x 1600, SHA-256 `188a99539df7d07c8e7ad21ebc353dd1d318a535adafadb362579c43354419f1`. It was rendered at the required Mac aspect ratio, not stretched from the earlier image. Separate Apple readbacks report `COMPLETE`, width 2560, height 1600 for:

| Tip | Review screenshot ID |
| --- | --- |
| Small | `ee66de86-565b-4448-80b4-681c1f2c1be9` |
| Medium | `1dd87b85-b7d6-4002-a6a0-3af9bc5d2297` |
| Generous | `2774f504-ac31-4ffd-9f7b-600703354dc5` |

The initial standalone host aborted inside StoreKitTest's XCTestLibrary lookup. A proper hosted XCTest recovered, running one capture test with zero failures. Its first 1800 x 2000 screenshot was rejected by Apple with `IMAGE_INCORRECT_DIMENSIONS`. A re-upload of that failed asset returned HTTP 400. All failures are retained. Only the newly created failed asset was deleted and replaced with a fresh reservation for the supported Mac image. No pre-existing user asset or product was removed. Final hosted capture passed, all three uploads/readbacks succeeded, and a fresh process check confirmed the owned capture host had stopped. Independent read-only review verified the exact hosted test, local catalog/type/zero-transaction checks, one-test raw exit 0, JPEG hash and stopped Apple readback receipts. It did not independently execute the workflow or establish live sandbox availability.

## Evidence and remaining work

Private operational artifacts are retained under `~/.jcode/scratch/hashfleet-stability-20261108T0110.noindex/mac-store-iap-22/`, including settings, archive/package logs, `package-verified.json`, upload result, availability configuration, IAP reviewer-note receipts and TestFlight verification. No credentials are included in this document.

Screenshot inputs, stopped test logs, original failed attempts and final upload/readback receipts are retained in the sibling `tip-review-capture/` directory. The prior deterministic tip-jar tests, local Xcode simulated purchase test and iOS/direct-Mac builds remain documented in `PAYPAL-SUPPORT.md`. Actual TestFlight UI acceptance and live catalog verification remain unobserved. The public CLI cannot expose paid-account agreement status, and the existing Chrome session redirected to login at 18:11 UTC. Authenticated web-session GETs still loaded the business shell and legal-entity JavaScript. Root traced the exact account-lookup route from that client, but its GET returned HTTP 403, including a retry with normal Apple request headers. Agreement state remains unknown. This is not an App Store API outage or proof that every authenticated route is unavailable. The broader stability todos remain open. Do not submit this app or its IAPs until the operator explicitly authorizes submission.
