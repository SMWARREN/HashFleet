# Native crypto support, November 1, 2026

## Behavior and placement

The shared native Support section now displays the owner's existing website BTC, ETH and SOL public receiving destinations. Each row shows the currency, explicit mainnet label and full wrapping address, plus a **Copy [symbol] address** button with successful-copy feedback. Copying never opens a wallet, constructs a transaction, submits payment, unlocks features or sends miner data. No receiving addresses are reproduced in this report.

Existing Support entrances are unchanged: native Mac sidebar, app menu, status popup More menu, Overview menu, About section and eligible celebration screens. No additional Support entrance or separate application was added. PayPal remains available alongside the crypto rows. The CLI's existing PayPal support command is unchanged.

The same shared SwiftUI implementation compiles for native Mac and iPhone/iPad. The Mac update is installed at `/Applications/Hash Fleet.app`. At completion of the initial shared-UI task, the iPhone/iPad source change was compiled but not installed or released. The subsequent owner-requested preserving physical iPhone build13 installation is recorded in `IPHONE-CRYPTO-INSTALL-2026-11-01.md`. No TestFlight/App Store release was made.

## Safety and eligibility

- The existing policy remains unchanged: explicit direct Mac distribution, or actual USA StoreKit storefront. Unknown/non-USA store-distributed clients fail closed.
- Both PayPal activation and explicit crypto copying revalidate the storefront. Cancellation/inactive scenes cannot copy. A cryptocurrency destination can only be one of three immutable owner-approved enum cases, never an address read from a miner, server or preference.
- The UI warns to use only the named network and verify the full address before sending. Copying does not initiate a transaction.
- iOS copying is local-only with a two-minute clipboard expiry. Mac uses the normal pasteboard and reports a write failure instead of claiming success.

## Validation

- Nine core support tests passed, including parameterized invalid PayPal URL and storefront cases, all three exact receiving destinations, unique IDs and rejection of unrecognized crypto identifiers.
- Two cross-source checks passed, including exact native/website destination parity.
- Seventeen offline packaging/installer tests passed, retaining rollback and single-visible-app protections.
- Native Mac Release build, packaging, embedded CLI and signature validation passed. The iPhone/iPad simulator target compiled successfully without installing or launching an additional application.
- Installed-app-only accessibility acceptance passed for all three currencies twice: full displayed destination, network label, exact clipboard contents, successful-copy label, repeated Support navigation and About integration. The probe never launches/terminates an application or invokes PayPal/wallet actions. It restored the user's original multi-type clipboard from memory.
- Preferences and a consistent SQLite telemetry backup were saved privately before the canonical app's graceful update. Saved miner configuration is checked byte-for-byte by a normalized plist digest after update.
- Six generated/rollback bundles were reversibly retired after testing, including two older inactive simulator harness aliases discovered by physical bundle-ID scanning. Final verification at approximately 20:40 UTC found no generated Fleet apps remaining, only the canonical existing LaunchServices application and Dock entry, unchanged saved devices, canonical PID 6438 and a valid native signature.

The optional independent reviewer failed before inference with a provider HTTP 400, so no independent review approval is claimed. The initial cleanup stopped before moving anything because LaunchServices correctly did not recognize the hidden non-`.app` rollback directory (`-10814`). That precise no-application result was handled and final identity-based verification remained required.

Private build/test/install logs, backup receipt, reversible-move manifest and final verification: `~/.jcode/scratch/hashfleet-crypto-20261101.noindex/`. Implementation commit: `a32c39c`.
