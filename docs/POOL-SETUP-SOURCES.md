# Shared Pool Setup Sources (verified 2026-09-07 UTC)

Read-only research catalog. Read this file for official-source facts before adding any
shared (non-solo) pool preset alongside the existing six verified `SoloPoolPreset`
choices (CKPool BTC; SoloFury BTC/BCH/BC2/BCH2/XEC).

## Verified shared Bitcoin pool endpoints (SV1)

### OCEAN (BTC, accountless)
- Host `mine.ocean.xyz`, port `3334`, SV1 over plain TCP (`stratum+tcp://mine.ocean.xyz:3334`).
- No TLS port is documented on the official get-started page; do not present one.
- Username: the payout **Bitcoin address** directly (no account registration). Optional
  `address.workername` appended with `.`; default worker is `default`. Password ignored ("x").
- Pool does not validate the address at connect time; shares under a bad address are lost.
  Wrong-address protection must be client-side.
- Payouts: transparent, on-chain or Lightning per their docs; named after their TIDES
  scheme. Do not hardcode fee/payout numerics; they change over time and are published
  at ocean.xyz.
- Bitaxe suitability: widely used with low-hashrate miners via VARDIFF; the official
  page publishes no minimum difficulty number, so do not invent one.
- Source (official): https://ocean.xyz/getstarted (fetched 2026-09-07)

### Braiins Pool (BTC, registered account)
- Host `stratum.braiins.com`; SV1 ports `3333` (primary) and `443` (backup), plain TCP
  over `stratum+tcp://`. No SV1 TLS endpoint is documented on the official setup page.
- Username: registered **account name**, `username.workername` (`userName.workerName`).
  Password ignored. `workername` optional (`[auto]` created if empty).
- SV2 also exists (`stratum2+tcp://stratum.braiins.com:3333/...authorityKey`) but a
  Bitaxe/ESP-Miner SV1 target should stay on the V1 URL.
- Payouts require registering a payout address in account settings (on-chain or
  Lightning); scoring/reward method and fees are published by Braiins and must not be
  hardcoded.
- Bitaxe suitability: standard SV1 VARDIFF; no official minimum-difficulty figure on
  the setup page.
- Source (official): https://academy.braiins.com/braiins-pool/btc-mining-setup
  (fetched 2026-09-07)

## Coin compatibility

- Bitaxe BM1370 is a SHA-256d ASIC. Only SHA-256d coins are mineable. Compatible set for
  this app's purposes: BTC, BCH, BC2/BCH2 (as already shipped via SoloFury), XEC. Do not
  infer compatibility from a ticker symbol alone; a coin must be SHA-256d and retain
  SV1-stratum-compatible getwork.
- Arbitrary mineable tokens are out of scope. No new coin was verified in this research;
  keep the five existing coin choices, six solo presets and shared BTC only.

## Price data

- BTC and BCH prices are already available via existing mempool/Blockchair integration.
  No new price provider is needed; no third-party price API was validated here and none
  should be added without a stated need.

## Suggested additions (max 3, step-reducing)

1. `OCEAN BTC` shared preset: host `mine.ocean.xyz`, port `3334`, SV1, username = BTC
   address (+optional `.worker`). Adds a credible non-solo default with zero signup.
2. `Braiins BTC` shared preset: host `stratum.braiins.com`, port `3333` (backup `443`),
   SV1, username = `account.worker`, password any. Requires account signup; mark preset
   as "account required".
3. UI hint that shared-pool usernames are validated differently (OCEAN: raw address;
   Braiins: registered username) so the guided flow can prompt correctly without
   guessing from the solo presets.

Everything above under "Verified" came from official first-party documentation on
2026-09-07. Anything else (TLS ports, difficulty numbers, fee figures) is unverified
and intentionally absent.
