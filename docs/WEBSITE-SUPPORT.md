# Website developer support

Published November 1, 2026 at 17:13:14 UTC. Implementation commit: 98b878d.

## Experience

- Homepage section: `https://hashfleet.app/#support`. Header and footer both link to Support.
- The verified PayPal custom-amount tip checkout is shared with the native/CLI configuration. Checkout payment-method availability remains device/location dependent.
- BTC, ETH and SOL public receiving destinations are the exact owner-supplied values in `website/src/lib/support.ts`. Independently pinned fixtures test their rendered and copied values.
- Networks are explicitly Bitcoin mainnet, Ethereum mainnet and Solana mainnet. Bitcoin checksum and base58 version/length passed local validation. Ethereum passed 20-byte hexadecimal syntax. Solana decoded to 32 bytes. These are format checks, not independent proof of ownership.
- Each address has an accessible copy button and live status. Denied/unavailable clipboard access selects and focuses the full address for manual copying. No wallet connections, signing, transaction requests, third-party scripts, or automatic PayPal requests.
- Tips are optional and unlock nothing. Crypto transfers are separate from PayPal. This change adds crypto destinations to the website only, not the native apps or CLI.

## Verification

- `npm run check`: 151 tests passed, including 7 support cases. TypeScript and production build passed.
- `node Tools/run-support-acceptance.mjs http://127.0.0.1:4174`: 64 checks passed.
- Same support suite against `https://hashfleet.app`: 64 checks passed. Exact displayed destinations, real clipboard contents, denied/unavailable clipboard fallback, header/footer navigation, mobile menu, direct fragment navigation, light/dark at 320/390/768/1024/1440 px, and no unsolicited external requests. No payment attempted.
- Existing native parity: local 207 checks and public 208 checks passed across 18 native captures, with no browser errors or failed requests.
- Existing strict route suite: 125 assertions passed, but its final zero-failed-request assertion failed. A diagnostics-only rerun retaining every assertion identified `net::ERR_ABORTED` image/favicon requests during rapid route navigation, not runtime errors. This is recorded as a failed strict suite, not silently converted to a pass. No acceptance assertions were weakened.
- Public index and all three generated JS/CSS files match the tested build SHA-256 values byte-for-byte.
- Desktop and 320px screenshots visually reviewed. Public browser artifacts: `website/output/playwright/20261101T171328370Z-support-public` and `website/output/playwright/native-parity-20261101T171409169Z-native-parity-public`.

## Deployment boundaries and rollback

The full bundle preflight stopped before promotion because local Service.php, APNs.php and config.example.php differ from the live backend. Do not use the full bundle to overwrite these differences without a separate backend review.

A one-shot, exact-digest frontend-only publication promoted these four files, with assets first and index last:

- `assets/DashboardPreview-91imi-zL.js` (dependent chunk imports the new index module)
- `assets/index-BAfNzDCy.css`
- `assets/index-jnWiE3Wm.js`
- `index.html`

All other manifest-listed public files were verified unchanged. The previous index is saved in the private hosting backup directory `hashfleet-private/backups/20261101-171313-support-static/index.html`. Previous hashed assets were retained. Restoring the saved index atomically restores the earlier frontend. The one-shot publisher also rolls back index on promotion/digest failure.

Before/after hashes verified that private configuration, database, backend source, API, Apache policy, retirement files, permissions, and crontab stayed unchanged. No restart, cron job, APNs activation, miner operation, payment, or wallet transaction occurred.

Local release receipts and one-shot publisher are in `~/.jcode/scratch/hashfleet-support-publish-20261101T1708Z`. The full archive is retained for evidence, but was not installed.
