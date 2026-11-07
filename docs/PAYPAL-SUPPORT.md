# Optional PayPal developer support

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
single public checkout configuration used by the native apps and CLI. Unconfigured
builds still hide the support section, and `hashfleet support` returns exit 69 with
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
- **iPhone/iPad App Store app:** The section appears only for a current StoreKit
  `USA` storefront. Unknown and all other storefronts are hidden. Device locale,
  language, SIM region, IP, or a user preference are never eligibility substitutes.
  The view refreshes on foregrounding, listens for StoreKit storefront updates, and
  checks again immediately before opening checkout. No storefront value is persisted.
- **Future Mac App Store target:** Do not inherit the direct-distribution flag.
  Without it, the shared view uses the same conservative StoreKit storefront gate.
- **CLI:** **Shift+S** opens a read-only **Support Hash Fleet** page inside the dashboard,
  miner details, or logo view. It includes the reviewed PayPal checkout and the existing
  shared BTC/ETH/SOL mainnet receiving destinations. Long values wrap and the page scrolls.
  **S**, **b**, or **Escape** returns to the prior view; **q** or **Ctrl+C** quits normally.
  Viewing Support suppresses new dashboard polls and never opens a browser or wallet,
  copies to the clipboard, or sends payment. Destinations remain real in demo mode.
  `hashfleet support` prints the same checkout, crypto destinations, network labels, and explanatory text.
  It runs before loading the fleet or starting discovery, never launches a browser,
  never sends a payment, and rejects miner arguments and options with exit 64.
- **All platforms:** Checkout uses the external browser, no embedded payment SDK,
  tracking, purchase callback, or feature unlock. No miner/wallet/network information
  is appended to the URL. PayPal controls payment processing and donor verification.

This is not a guarantee of App Review approval. Recheck Apple rules for the intended
storefronts before submission. There is no global PayPal button and no non-US IAP tip
jar in this implementation. Crypto is not integrated or promised by this checkout.

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
