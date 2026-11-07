# Public Bitcoin and CKPool data

Verified on **2026-09-06 and 2026-09-07 UTC**. These features are entirely app-side. They neither contact mining hardware nor change a miner's pool, settings, firmware, or credentials.

## Sources and exact read-only endpoints

| Provider | HTTPS GET | Fields consumed | Units / freshness |
| --- | --- | --- | --- |
| mempool.space | `https://mempool.space/api/v1/fees/recommended` | `fastestFee`, `halfHourFee`, `hourFee`, `economyFee`, `minimumFee` | sat/vB recommendations, not confirmation guarantees. No source timestamp in this response. |
| mempool.space | `https://mempool.space/api/mempool` | `count`, `vsize`, `total_fee` | Transactions, virtual bytes, satoshis. This is the provider's observed mempool, not a consensus-wide queue. No source timestamp. |
| mempool.space | `https://mempool.space/api/blocks/tip/height` | Plain-text integer | Last block height, not the next candidate height. No source timestamp. |
| mempool.space | `https://mempool.space/api/v1/mining/hashrate/3d` | `currentHashrate`, `currentDifficulty`, historical `hashrates`, historical `difficulty` | H/s and dimensionless network difficulty. Hashrate is estimated, not hardware telemetry. |
| mempool.space | `https://mempool.space/api/v1/prices` | `USD`, `time` | Indicative USD/BTC. `time` is a Unix timestamp, not a trade execution quote. |
| CKPool | `https://raw.stats.ckpool.org/pool/pool.status` | `runtime`, `lastupdate`, `Users`, `Workers`, `Idle`, `Disconnected`, rolling hashrates, `bestshare` | Newline-delimited JSON objects. `lastupdate` is Unix seconds. Rolling rates use decimal SI suffixes, e.g. `196P` means 196 × 10^15 H/s. |
| CKPool, manual or authorized connected-pool lookup | `https://raw.stats.ckpool.org/users/{address}` | Rolling hashrates, `workers`, `shares`, `bestshare`, `bestever`, `lastshare` | Mainnet Bitcoin address only, locally checksum-validated before any request. Never automatically called by aggregate refresh. |
| Blockchair | `https://api.blockchair.com/bitcoin-cash/stats` | `difficulty`, `best_block_height`, `market_price_usd`, `hashrate_24h`, `mempool_transactions`, `context.code`, `context.cache.since` | Separate BCH difficulty, height, USD/BCH, 24-hour estimated H/s, and mempool transaction count. `cache.since` is parsed as UTC source freshness, not replaced by fetch time. |

### Official references

- [mempool.space REST API documentation](https://mempool.space/docs/api/rest). The documentation page is client-rendered, so its [official documentation source](https://github.com/mempool/mempool/blob/master/frontend/src/app/docs/api-docs/api-docs-data.ts) was also read to verify methods, paths, and examples.
- [CKPool official website](https://solo.ckpool.org/), “Pool & user statistics.” It currently links to `raw.stats.ckpool.org/pool` and the `/users/` directory.
- [CKPool raw pool page](https://raw.stats.ckpool.org/pool). This is an HTML wrapper linking to `pool.status`, not the statistics JSON itself.
- [CKPool official source](https://github.com/ckolivas/ckpool/blob/master/src/stratifier.c). The user-statistics JSON writer and pool-status writer were inspected without requesting any personal address. User fields and their units are verified against this source, not invented from an example wallet.
- [Blockchair BCH statistics](https://api.blockchair.com/bitcoin-cash/stats) was independently fetched and decoded through the production client. Its response self-links [official API documentation](https://blockchair.com/api/docs). The coordinator's docs request returned 401, so no unverified documentation content or free-tier limits are claimed. The exact live response fields, envelope status, and source cache timestamp are validated. No API key or paid request was used.
- [BIP 350](https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki) for Bech32m, witness constraints, and valid/invalid checksum vectors. Base58Check validation uses double SHA-256 via the platform CryptoKit implementation.

The legacy `https://solo.ckpool.org/pool/pool.status` also returned HTTP-success NDJSON during verification, but its aggregate values differed from the currently documented raw statistics host. The client deliberately uses only the documented `raw.stats.ckpool.org` provider. It does not merge aggregates, infer pool-wide coverage across different hosts, silently fall back, or follow redirects.

## Data interpretation and limitations

- Five independent network requests preserve successful results when another source returns 401, 429, 5xx, malformed JSON, a timeout, or another failure. Pool summary is independent of all five.
- Each `MiningDataResult` contains local `fetchedAt`, fixed `sourceURL`, optional `sourceTimestamp`, optional typed value, and an optional safe typed error. Missing, null, nonfinite, negative, or type-invalid metrics are never converted to fabricated zeros. Valid reported zero values remain zero where meaningful.
- Current hashrate and difficulty have no overall source timestamp in the selected mining response. `hashrateSampleAt` means the **latest historical daily sample**, not the freshness of `currentHashrate`. `difficultyChangedAt` is included only for a matching current difficulty. The official docs show historical `timestamp`, while the live response uses `time`, so both are supported.
- CKPool summary uses uppercase `Users` and `Workers`. User statistics use lowercase `workers`. These are distinct documented shapes.
- CKPool `lastshare` is an event time, not a generation timestamp for all user statistics. The client does not relabel it as source freshness. The currently documented user writer does not include `lastupdate`, so user result `sourceTimestamp` is ordinarily nil.
- CKPool's `diff` field is a progress percentage calculated from accounted difficulty shares, **not Bitcoin network difficulty**. It is not exposed as network difficulty. `bestshare` is a share difficulty, not a found-block count or proof of payout.
- CKPool user HTTP 404 maps to `.notFound(fetchedAt:)`. Other HTTP errors map to `.failed`. An empty/malformed successful body is `.invalidData`, not “user not found.” CKPool's official FAQ warns that low-rate miners can take time to appear in statistics.
- BCH uses `best_block_height`, never the different `blocks` index count. `context.code` must be 200 even if HTTP status is 200. `hashrate_24h` is reported as a numeric string and is converted to finite H/s. Invalid/missing fields remain nil independently. These values are never substituted with Bitcoin mainnet assumptions. BCH difficulty changes on a different schedule, so use its own fresh source data and keep coin labeling explicit.
- CKPool service fees, network difficulty, pool availability, transaction fees, exchange prices, and aggregate scope may change. There is no source uptime or quote guarantee. Authentication is not used, no paid integration is added, and no retries are implemented in the core client. The app refreshes public data in the foreground with a 60-second cooldown.

## Privacy and request restrictions

`MiningInsightsClient` creates no network traffic at initialization. Callers choose when to invoke aggregate refresh or account lookup. Following the user's revised authorization, app integration may refresh on Home for connected miners, with visible provider disclosure and a local Settings opt-out. The client itself implements no automatic polling. Demo values must remain visibly separate from live data.

The only constructed requests are allowlisted HTTPS GETs to the three public API hosts above. There is no public arbitrary-URL execution API, no configurable API host, no credential-bearing query, no body, no upload, or stratum access. The network client does not inspect miner configuration. `ConnectedPoolLookup` is a separate pure local resolver over an already supplied `MinerInfo`, not a hardware request. All redirects are blocked, including same-host redirects. A response URL mismatch is also rejected. Only ordinary system TLS server-trust handling is allowed. Other authentication challenges are cancelled.

An injected `URLSession` is supported by copying its configuration, including offline URLProtocol fixtures, into an owned session. Cookies, cookie acceptance, credential storage, URL caching, and additional headers are removed. The original injected session is not mutated. Requests also disable cookie handling, use a reload-ignoring-local-and-remote-cache policy and `Cache-Control: no-store`, and the task delegate rejects cache storage. This prevents the app from storing or replaying HTTP cache entries, but cannot promise that the provider has no upstream caching.

The default timeout is 15 seconds. Positive custom values are capped at 60 seconds. Nonfinite or nonpositive values fall back to 15 seconds. Requests do not wait indefinitely for connectivity. Parsing rejects bodies larger than 1 MiB after transfer. This is a parsing limit, not a streaming download-byte limit.

All returned error descriptions contain only fixed safe text or an HTTP status number. Raw bodies, underlying error descriptions, credentials, and wallet URLs are never included in errors or logged by the client. The client retains no raw payload or worker identifiers. A successful account lookup's source URL necessarily contains the supplied public address, so UI/analytics must not log that URL.

An account lookup sends its public address to CKPool, whose server also sees the requester's IP address. It is not anonymous merely because no account is needed. The revised user request authorizes connected-pool public statistics with app disclosure and a local opt-out. `ConnectedPoolLookup.resolve(info:)` extracts only a valid public address from the **explicitly reported active** CKPool account. It requires `isUsingFallbackStratum`, selects the corresponding `primaryPoolIndex` or `secondaryPoolIndex`, and matches `pools[].id` rather than array position. It accepts only exact `stratum.ckpool.org` and `solo.ckpool.org` configured hosts, optionally with a recognized stratum scheme and valid port. Missing/duplicate selected IDs, missing fields, unsupported hosts, embedded URL credentials, paths/queries/fragments, and unknown active-state flags fail closed. Existing legacy fields are used only when no `pools` representation is supplied. Primary and fallback fields are never mixed. Worker suffixes and passwords remain local and are not returned. Parent app code must gate lookup on a currently connected snapshot and the opt-out. The coordinator separately owns any broader all-configured-pools facade, coin mapping, or other pool adapter.

Manual lookup remains available. Accept only a mainnet Base58Check or SegWit Bech32/Bech32m address. URLs, traversal, queries, fragments, worker suffixes entered in the manual address field, mixed-case Bech32, invalid checksums, testnet addresses, and private keys are rejected locally. Surrounding whitespace is trimmed and valid all-uppercase Bech32 is normalized to lowercase.

Cancellation is typed as `.cancelled`, not a successful empty result. `NetworkSnapshot.isCancelled` allows the app to discard a cancelled refresh. Parent task cancellation marks the complete network snapshot cancelled rather than presenting its interim successes as a completed report.

## Solo mining estimate

With hashrate `H` in hashes/second, duration `t` in seconds, and network difficulty `D`:

```text
lambda = H × t / (D × 2^32)
P(at least one block) = -expm1(-lambda)
expected time to a block = D × 2^32 / H
```

`SoloMiningMath` uses stable `expm1` for tiny probabilities and a logarithmic fallback for intermediate overflow/underflow. Negative/nonfinite inputs or nonpositive difficulty are invalid. Zero hashrate means zero probability and no finite expected time. Zero duration means zero probability. Unrepresentable expected block counts return nil rather than infinity. The expected waiting time is a distribution mean, **not a countdown, deadline, guaranteed reward, or promise of ever finding a block**. Hashrate and difficulty are assumed constant throughout the chosen duration. Past shares do not make the next hash more likely to win.

`blockSubsidyBTC(atHeight:)` applies Bitcoin mainnet's 210,000-block halvings with integer-satoshi truncation. The argument is the **exact candidate block height**. To estimate the next block at a halving boundary, the app should safely use tip height + 1. The USD estimate exists only with a valid positive finite price and known valid height. It describes subsidy value only, before pool fees and excluding transaction fees, operating costs, uptime, stale work, and future price/difficulty changes.

## Validation and live evidence

All ordinary tests are offline. Injected URLProtocol fixtures intercept every request. Wallet tests use public checksum test vectors only inside this blocked transport and perform **no personal-wallet network requests**.

After the BCH/resolver extension on 2026-09-07 UTC, the full macOS Swift 6 package run reported **101 tests in 11 suites passed** (the earlier BTC/CKPool-only run reported 89 tests). Added coverage includes exact GET paths/methods, independent partial outcomes, cookies/credentials/cache stripping, fixed allowlists, blocked redirect delegates, mismatched response URL, malformed/oversized payloads, safe 401/429/5xx failures, timeouts, pre-cancellation and in-flight cancellation, NDJSON variants/conflicts, optional values and integer bounds, CKPool user 404 distinction, address checksum/path safety, subsidy boundaries, extreme finite math, and stable tiny probabilities. The live test is explicitly disabled by default.

The production URLSession client was then exercised with six aggregate-only GETs at **2026-09-06T23:53:29Z**. All six decoded successfully with no endpoint errors:

| Live observation | Value at verification time |
| --- | --- |
| Bitcoin tip | 965,851 |
| Recommended fastest fee | 1 sat/vB |
| Observed mempool transaction count | 75,747 |
| Network difficulty | 127,450,789,715,843.1 |
| Estimated network hashrate | 9.467034112702203 × 10^20 H/s |
| Indicative USD/BTC | $80,504 |
| CKPool users / workers | 32,206 / 53,304 |
| CKPool 1-minute hashrate | 2.01 × 10^17 H/s |
| CKPool source `lastupdate` | 2026-09-06T23:51:36Z |

These are historical verification observations, not constants or current values for display.

A separate production `bitcoinCash()` aggregate-only smoke passed at **2026-09-07T00:02:44Z**: tip 967,397, difficulty 428,672,956,037.77, indicative USD/BCH $260.83, source cache time **2026-09-07T00:02:32Z**. BCH tests also cover its exact HTTPS GET, provider-level non-200 envelopes, `best_block_height` rather than `blocks`, numeric-string hashrate, optional invalid values, UTC date validation, and safe 401/429/503 failures. Pure resolver tests cover ID ordering, active fallback selection, no inactive-primary fallback, duplicate/malformed/missing IDs, unsafe hosts, worker/path safety, and omission of passwords and worker identifiers.

Reproduce the offline suite with `swift test`. The deliberate live smoke is:

```sh
HASHFLEET_PUBLIC_DATA_SMOKE=1 swift test --filter MiningInsightsLiveTests
```

Those opt-in tests call only `bitcoinNetwork()`, `bitcoinCash()`, and `ckPoolSummary()`, for seven aggregate GETs. They never invoke account lookup, access hardware, or change any settings. The worker ran no iOS build and made no commits. Native UI integration and app tests are owned by the coordinating session.

## All configured SoloFury and CKPool slots

The app uses `ConfiguredMiningPool.resolve(info:)` for all configured slots, separately from the narrower active-only `ConnectedPoolLookup`. Explicit persistent IDs select primary/fallback roles, and unknown activity remains unknown. Both primary and fallback public accounts are authorized by the updated product request. All 45 SoloFury region/coin hosts are verified in the [official endpoint reference](https://raw.githubusercontent.com/solofurypool-code/solofury-public-docs/main/reference/stratum-endpoints.md). Only fixed HTTPS statistics APIs are contacted, never arbitrary reported hosts.

SoloFury pool `/pool` and account `/client/{address}` suffixes use `/api-btc` for BTC, `/api` for BCH, `/api-bc2`, `/api-bch2`, and `/api-xec`. Rolling rates are numeric H/s. Account lastShare and worker lastSeen are activity times, not response freshness. Current pool `blocksFound` is an event array, not an integer count. No event proves a reward belongs to the current app user. Server cache age may be unknown; fetch time is displayed separately.

BC2 uses Bitcoin-style addresses, BCH uses bitcoincash CashAddr or documented legacy Base58, BCH2 uses bitcoincashii, and XEC uses ecash. The [official FAQ](https://raw.githubusercontent.com/solofurypool-code/solofury-public-docs/main/reference/faq.md) documents these differences. Never send a wallet to a different coin endpoint based on a substring guess.

The connected-account store excludes offline/stale readings, deduplicates per provider/coin/address, cancels on configuration/privacy/lifecycle changes and rejects late results against newly resolved configuration. Demo and opt-out never dispatch public requests. Solo-mining shares are submitted work, not entitlement to another miner's solo reward.
