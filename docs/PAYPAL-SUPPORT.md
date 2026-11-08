# Optional developer support

## Current decision, November 8, 2026

The owner authorized native StoreKit 2 consumable tips for App Store builds and
preservation of external support only for direct-distribution Mac and CLI. This
supersedes the November 1 US-only external-support presentation described in the
historical audit below. It is a conservative product decision, not a claim that
Apple prohibits US external links. No App Review submission or real purchase is
authorized. TestFlight preparation and distribution are authorized.

The three intended products and remote setup checklist are recorded in
`docs/app-store/developer-tips-catalog.json`. They are **local preparation**, not
evidence that App Store Connect products exist. The cached App Store Connect
session returned HTTP 401. Remote catalog creation, agreements and TestFlight
upload remain unperformed pending authenticated access.

## Historical PayPal setup, November 1, 2026

Checked November 1, 2026. This is a voluntary developer tip, not a charitable donation,
subscription, purchase of app features, or requirement to use Hash Fleet.

## Activation status

**Checkout is configured** with the link created in the owner's open PayPal Business
account on November 1, 2026:

`https://www.paypal.com/ncp/payment/6NAMWWPAKSFV2`

Merchant account details are omitted from this public source snapshot. The checkout link above is intentionally public.
**Support Hash Fleet**, customer-set price in USD, with the amount label
**Enter your tip amount**. Saved details confirm **Collect shipping address: No**.
The initial saved link still collected shipping despite an attempted toggle, so it
was edited and the persisted **No** value was explicitly rechecked.

The actual public checkout was opened in a Chrome Incognito window. Its title,
description, amount entry and USD currency matched the intended support flow.
PayPal, Venmo, Pay Later and debit/credit card controls were visible. Expanding
**See more options** exposed Apple Pay on that checkout. This verifies presentation,
not payment completion or universal device/region eligibility. No payment method
was authorized, no money was sent, and no account-wide settings were changed.

`DeveloperSupport.current` in `Sources/HashFleetCore/DeveloperSupport.swift` is the
single external checkout configuration used by direct-distribution Mac and CLI.
Unconfigured external-support builds hide that section, and `hashfleet support` returns exit 69 with
an explanation. Do not replace the reviewed link with a guessed PayPal username,
email address, wallet, test merchant, or placeholder destination.

## Setup and future replacement checklist

1. Sign into the intended PayPal **Business** account.
2. Open **Pay & Get Paid > Create Payment Links and Buttons**.
3. Create a customer-set-price link named **Support Hash Fleet** in USD. Suggested
   description: “Optional developer tip supporting the free, open-source Hash Fleet
   app. No features or services are purchased or unlocked.” Do not enable recurring
   billing, shipping, required invoice IDs, inventory, or product variants for tips.
4. Inspect which eligible payment methods PayPal actually offers. Its documentation
   lists cards, PayPal, Apple Pay and Venmo, but availability depends on merchant,
   region, browser/device, and checkout eligibility. An existing PayPal Business
   account alone does not prove Apple Pay is enabled for this particular checkout.
5. Confirm the public merchant identity, tip description, currency, amount entry, and
   absence of unnecessary shipping fields. The owner should approve any public
   business identity before the link is distributed. Do not accept new legal terms
   or submit KYC on the owner's behalf.
6. Set the exact reviewed `https://www.paypal.com/ncp/payment/<identifier>` link in
   `DeveloperSupport.current`. Other URL formats are deliberately rejected. If PayPal
   returns a different canonical format, review it and add explicit tests before
   changing the validator. Never add API credentials to the application or repository.
7. Run the checks below. Inspect Apple Pay on a supported real device/browser without
   completing a payment. Live charging is a separate owner-authorized step.

## Platform behavior

- **Native direct-distribution Mac app:** About contains the optional support section
  once a link is configured. The explicit `HASHFLEET_DIRECT_DISTRIBUTION` compilation
  condition is set only on the current `HashFleetMac` target.
- **iPhone/iPad App Store app:** About presents native StoreKit consumable tips.
  External PayPal checkout and crypto-copy rows are hidden on every storefront,
  including USA. Product availability and localized prices come from StoreKit.
- **Future Mac App Store target:** Do not inherit the direct-distribution flag.
  Without it, the shared view uses native StoreKit tips, not external support.
- **CLI:** **Shift+S** opens a read-only **Support Hash Fleet** page inside the dashboard,
  miner details, or logo view. It includes the reviewed PayPal checkout and the existing
  shared BTC/ETH/SOL mainnet receiving destinations. Long values wrap and the page scrolls.
  **S**, **b**, or **Escape** returns to the prior view; **q** or **Ctrl+C** quits normally.
  Viewing Support suppresses new dashboard polls and never opens a browser or wallet,
  copies to the clipboard, or sends payment. Destinations remain real in demo mode.
  `hashfleet support` prints the same checkout, crypto destinations, network labels, and explanatory text.
  It runs before loading the fleet or starting discovery, never launches a browser,
  never sends a payment, and rejects miner arguments and options with exit 64.
- **External-support platforms:** Checkout uses the external browser, no embedded payment SDK,
  tracking, purchase callback, or feature unlock. No miner/wallet/network information
  is appended to the URL. PayPal controls payment processing and donor verification.

This is not a guarantee of App Review approval. Recheck Apple rules for the intended
storefronts before submission. App Store builds never expose a PayPal button.
Crypto is not integrated or promised by the PayPal checkout.

## App Review rejection checkpoint, November 8, 2026

This section preserves the 15:23 UTC pre-remediation audit. The later owner-approved
IAP decision above supersedes its hold on changing the presentation.

The owner supplied a rejection concerning developer donations and requested an agent
to investigate. At 15:23 UTC, a bounded independent source audit confirmed that the
inspected core policy requires the current StoreKit `USA` storefront or explicit
direct-distribution Mac eligibility. The availability layer rechecks before activation.
PayPal opens external checkout; native crypto rows copy addresses rather than opening
a browser or sending a transaction. This was a source audit, not a submitted-build
inspection, configured UI test, or general compliance certification.

Apple guideline 3.1.1(a) was rechecked on November 8. It expressly exempts US-storefront
buttons, external links, and other purchase calls to action from the stated entitlement
requirement. That does not establish why this particular submission was rejected or
resolve the treatment of the native crypto-copy controls. No missing basic storefront
gate was found in the inspected files. The rejected version/build and any review
screenshot are still unknown and have been requested from the owner.

At that checkpoint no payment destination, support availability, IAP product,
entitlement, App Store Connect record, or submitted build had been changed. The
audit did not identify the rejected build or prove which control triggered review.
The subsequent IAP implementation is a separately authorized product decision,
not a conclusion from that audit. No App Review approval is claimed.

## StoreKit 2 developer tipping implementation, November 8, 2026

Under user authorization, an in-app developer tip jar was implemented using StoreKit 2 consumables for App Store distributions:

- **Product IDs:** `app.hashfleet.tip.small` ($1.99, "Small Tip"), `app.hashfleet.tip.medium` ($4.99, "Medium Tip"), and `app.hashfleet.tip.large` ($9.99, "Generous Tip").
- **No digital feature unlock:** Pure voluntary developer support; Hash Fleet remains entirely free and open source.
- **Transaction verification:** Every transaction is cryptographically verified before calling `transaction.finish()`. Unverified or revoked transactions are rejected.
- **Strict product filtering:** Updates and unfinished transaction processing strictly filter to `approvedProductIDs` before calling `finish()`, preventing accidental completion of unrelated products.
- **Conservative App Store presentation:** App Store builds display native StoreKit 2 tipping exclusively, suppressing external PayPal and crypto clipboard options across all storefronts. Direct-distribution Mac (`HASHFLEET_DIRECT_DISTRIBUTION`) and CLI external support options remain intact.

### Direct-distribution Mac build, November 8 at 16:38 UTC

The full `HashFleetMac` Debug app build completed with raw exit 0 in 80.8 seconds.
Root checked the closed log's `BUILD SUCCEEDED` footer and the
`HASHFLEET_DIRECT_DISTRIBUTION` compilation flag. The build used isolated
`iap-mac-build` DerivedData, the existing pinned package checkout, disabled package
updates and automatic resolution, two jobs, and `CODE_SIGNING_ALLOWED=NO`.
Logs are retained in `tipjar-lab/mac-app-build1.{stdout,stderr,raw-exit}` under the
session scratch directory. This verifies full-app compilation for direct Mac,
not app launch, visible UI, signed distribution, or a payment. Remote App Store
Connect setup and TestFlight delivery remain pending authenticated access.

### Validation checkpoint, November 8 at 16:29 UTC

- The integrated iOS Simulator app built successfully with the actual App/Core
  changes (181.6 seconds, raw exit 0). This was not a signed archive or upload.
- Ten deterministic service tests passed in both Mac App Store and direct-Mac
  configurations. The same ten also passed in the isolated iOS host. They cover
  purchase locking, reset and callback races, shared finish completion, product-ID
  parity and distribution gating without real purchase calls.
- An isolated iOS StoreKitTest run passed one real-framework local transaction test
  (raw exit 0, 0.035 seconds reported test time). It loaded all three consumables,
  created a simulated transaction, required a verified `.xcode` environment before
  invoking the production purchase method, repeated the same consumable purchase,
  checked two transactions and verified no approved unfinished transactions remained.
  The production transaction listener was enabled. No real money was charged.
- Failed setup attempts are retained: SwiftPM lacked a working local StoreKit
  context, the first iOS host omitted the configuration resource, and a listener-
  disabled attempt timed out. The successful run fixed resource packaging and used
  the production listener; no purchase assertions were removed. Local purchase
  dialog/UI presentation was not tested (`disableDialogs` was enabled), and the
  successful log contains UI-anchor warnings. This is not App Store sandbox,
  TestFlight, receipt-server or review acceptance.
- Logs and the isolated fixture are retained under the November 8 stability
  scratch directory's `tipjar-lab/`: `appstore1`, `direct1`, `ios-app-build1`,
  `ios-local1`, `ios-local2`, and `ios-local3`. Independent review covered the
  root-authored service concurrency changes and the stopped Mac pure-test results.
  A separate bounded read-only audit confirmed the local StoreKit test assertions
  and raw-zero result. Its initial prior-run exit-code and causal claims were
  corrected against the retained raw-65 timeout evidence; no cause was established.
- The native tip jar is neither instantiated nor rendered in direct-distribution
  Mac. Completed-transaction deduplication is process-local. StoreKit unfinished
  transaction processing handles relaunch recovery; no durable deduplication store
  or cross-relaunch test is claimed.

### Remote catalog setup, November 8 at 17:40 UTC

The usual Blitz MCP route reconnected at 17:33. A subsequent authenticated Apple
catalog GET returned HTTP 200, and the previously used `~/.blitz/bin/asc` CLI also
successfully read the catalog. Earlier cached-session 401 and browser-bridge
failures were real failed attempts, not proof that all ASC access was unavailable.
The web-auth MCP request timed out; its timeout alone does not establish whether
session refresh failed. No credentials were logged or new API keys created.

Three approved **consumable drafts** now exist under app `6812623943`, bundle
`app.hashfleet`. A separate CLI pricing-summary readback confirmed the USD prices:

| Product | Apple IAP ID | en-US display name | USD price |
| --- | --- | --- | --- |
| `app.hashfleet.tip.small` | `6832315570` | Small Tip | 1.99 |
| `app.hashfleet.tip.medium` | `6832314110` | Medium Tip | 4.99 |
| `app.hashfleet.tip.large` | `6832315156` | Generous Tip | 9.99 |

All localizations use: `Optional support for development. No feature unlocks.`
The first Small Tip setup created the product but failed localization because the
initial description exceeded Apple's 55-character limit. The existing product was
repaired in place, not recreated. Medium and Generous setup passed their default
post-create metadata and price verification. All three currently report
`MISSING_METADATA`; screenshots and remaining availability/review metadata are
not complete. No purchase, review submission or new build upload occurred.

An authenticated version read confirmed that the rejected version
`605fc5ac-0228-4c30-8263-e8b2666f7768` is **MAC_OS 1.0**, with build 19 attached.
A separate fresh native-Mac build-list read found valid builds 19 and 21. This is
not an iOS-only remediation. Follow the existing native Mac Store-only archive
workflow in `MAC-APP-STORE-DELIVERY-2026-11-03.md`: bundle `app.hashfleet`, no
`HASHFLEET_DIRECT_DISTRIBUTION`, sandbox enabled, without altering the installed
`app.hashfleet.mac` direct-distribution app. Build 19 predates the new tip jar.
A future archive must use the repaired source; the old binary cannot be credited
with today's StoreKit behavior. TestFlight is authorized, App Review submission
and real purchases are not.

## Verification

```sh
swift test --filter DeveloperSupportTests
swift build -c release --product hashfleet
# Activated build must print the exact reviewed public URL:
python3.12 Scripts/tests/test_cli_support.py --binary .build/release/hashfleet \
  --expected-url 'https://www.paypal.com/ncp/payment/6NAMWWPAKSFV2'
# For intentionally unconfigured builds, omit --expected-url to require exit 69.
python3.12 Scripts/tests/test_cli_dashboard.py --binary .build/release/hashfleet
python3.12 Scripts/tests/test_cli_settings.py --binary .build/release/hashfleet
python3.12 Scripts/tests/test_cli_firmware_activity.py --binary .build/release/hashfleet
python3.12 Scripts/tests/test_cli_interactive_support.py --binary .build/release/hashfleet
```

Core tests cover valid URLs, absent configuration, 19 malformed/unsafe URL cases,
unknown/non-US storefront denial, and explicit direct-distribution eligibility.
CLI tests check help, unavailable/configured checkout, and rejected hosts/options.
GUI build logs and CLI results are under `build/paypal-integration/` (not committed).
Observed on November 1: native Mac Release and iOS Simulator DebugNoAppPush builds
succeeded. All 5 core test functions (including 19 invalid-URL cases) passed. The
release CLI passed 4 support, 18 dashboard, 21 settings, and 11 firmware/activity
acceptance tests. `git diff --check` passed. No real miners were contacted by these
acceptance fixtures. Existing unrelated release blockers are not cleared by this work.
Those results describe the pre-activation build. The hosted checkout has now been
inspected as described above. Configured GUI interaction and payment completion
are separate acceptance checks, not implied by successful builds. No
payment-completion test has been performed. App Store and public binary releases
remain separate from configuring this support link.

Post-activation verification on November 1, 2026 at 16:41 UTC:

- Six core test functions passed, including 19 unsafe-URL cases and the new exact
  production-destination/storefront regression check.
- Release CLI build passed. All 54 CLI acceptance checks passed: 4 support,
  18 dashboard, 21 settings, and 11 firmware/activity tests.
- `hashfleet support` printed the exact reviewed payment URL with exit 0, without
  opening a browser, sending a payment, or contacting miners.
- Native Mac Release and iOS Simulator DebugNoAppPush builds both succeeded.
- Logs are retained in `build/paypal-activation/`. `git diff --check` passed.
- Apple's external-purchase-link guidelines were rechecked. The existing US-only
  StoreKit gate and unknown-storefront denial were preserved, not broadened.
- These are local build and checkout-presentation checks, not installation on the
  owner's devices, configured GUI interaction tests, payment-completion tests,
  App Review approval, or a public app release. Prior unrelated UI blockers remain.

## Primary references

- PayPal creation and customer-set tips: https://developer.paypal.com/payment-links-buttons/create-payment-link/
- Hosted checkout and processing: https://developer.paypal.com/payment-links-buttons/overview
- Available checkout settings: https://developer.paypal.com/payment-links-buttons/customize/
- Apple App Review, sections 3.1.1 and 3.1.1(a): https://developer.apple.com/app-store/review/guidelines/
- StoreKit current storefront and change notifications: https://developer.apple.com/documentation/storekit/storefront

Earlier research in `docs/reports/2026-11-01-developer-support-options.md` is retained
as history. The owner's selection of PayPal Business supersedes its shortlist.
