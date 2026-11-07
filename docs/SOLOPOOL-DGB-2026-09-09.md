# SoloPool DigiByte source verification · 2026-09-09

## Why the coin was missing

SoloPool shares regional stratum hosts across coins. `us1.solopool.org` alone is not proof of DigiByte. The previous app recognized only CKPool and SoloFury hosts and did not use SoloPool's port-to-chain mapping.

## Official sources

- DGB SHA-256 setup: https://dgb-sha.solopool.org/help
- BTC setup for cross-chain comparison: https://btc.solopool.org/help

Both pages serve their connection configuration in the URL-encoded `dashboard/config/environment` meta tag. Decoding the official page configuration on 2026-09-09 yielded:

| Chain and algorithm | Verified regional hosts | Low-end port | Mid-range port | High-end / rental port |
| --- | --- | --- | --- | --- |
| DigiByte SHA-256 | `us1.solopool.org`, `eu2.solopool.org` | 8004 | 7004 | 9004 |
| Bitcoin SHA-256 | `us1.solopool.org`, `eu3.solopool.org` | 8005 | 7005 | 9005 |

DGB configuration: `APP.id=dgb-sha`, `TEMPLATE.prefix=DGB`, `algoSha256=true`, pool fee `2.0%`. Listed share difficulties are 250K, 1000K (1M), and 10000K (10M). At small-miner hashrates these targets can produce infrequent submitted shares. The app does not claim these ports are optimized for Bitaxe, does not promise rewards, and does not change difficulty or connect the miner automatically.

DigiByte uses multiple proof-of-work algorithms. A Bitaxe's SHA-256d chip must use a compatible SHA-256 endpoint, not DigiByte's Scrypt, Skein, Qubit or Odocrypt endpoints. Compatibility still depends on firmware and pool behavior.

## Implementation limits

- Exact verified host plus port determines coin identity. Missing, malformed, conflicting or unknown port metadata remains unknown. Both embedded URL ports and separate firmware port fields are supported.
- SoloPool display identity is distinct from the enum used to authorize public-data adapters. **No SoloPool account/statistics adapter was added.** DGB wallet addresses are not validated or transmitted to such an API.
- SoloFury explicitly rejects DGB and never sends DGB requests to a guessed `/api-dgb` path or another coin's path.
- A user-reviewed `us1.solopool.org:8004` DGB SHA-256 draft preset and a seventh mock miner are provided. Real miner settings remain unchanged until the user goes through the existing write confirmation flow.
- Advanced configured pool rows, active-slot pickers and the editable server/port draft now show coin identity. Unknown endpoints stay explicitly unknown.

## Icon and market identity

CoinGecko's public DigiByte metadata confirms `id=digibyte`, `symbol=dgb`, `name=DigiByte`:
https://api.coingecko.com/api/v3/coins/digibyte?localization=false&tickers=false&market_data=false&community_data=false&developer_data=false

The checked-in PNG is the image linked by that metadata:
https://coin-images.coingecko.com/coins/images/63/large/digibyte.png?1696501454

Its PNG signature and 250×250 dimensions were checked, and the blue/white DigiByte mark was visually reviewed. Runtime icon rendering uses the bundled file without an image request. Existing opt-out-controlled aggregate CoinGecko market requests now include `digibyte`.

## Marquee correction and acceptance

The moving text no longer uses a spring numeric transition and now uses monospaced digits. Initial measurement and transitions into scrolling reset the clock at the visible origin. Later text and viewport geometry changes preserve the physical offset, including while paused. Reduce Motion and accessibility static summaries remain available.

Validation on 2026-09-09:
- Core: 146 tests in 17 suites passed (`hashfleet-dgb-core.log`).
- Native: 272 tests in 24 suites completed successfully with two pre-existing known appearance contrast issues. Those issues concern user-selected white text on orange and are not waived by this change.
- Four UI acceptance tests passed: DGB detail and advanced configured/draft coin identity, seven-miner pool switching, marquee pause/resume, and static accessibility summaries.
- Signed device build succeeded and strict code-sign verification passed.
- Exported advanced pool editor screenshot visually confirms `us1.solopool.org`, port `8004`, `Slot 6 · DGB`, and the bundled blue DigiByte icon beside `Coin · DGB`.

Evidence lives under `/Users/USER/.jcode/scratch/`: `HashFleetDGBAndTicker.xcresult`, `HashFleetDGBAndTickerScreens/`, `hashfleet-dgb-ticker-native.log`, and `hashfleet-dgb-ticker-device.log`.

The signed update was installed successfully on the paired iPhone at 20:15 UTC. Automatic launch with `--pool-icon-demo` was denied because the device was locked. Installation is verified, but physical-device foreground behavior has not been independently observed for this update. Open HashFleet after unlocking and use Settings > Pool icon demo to preview all seven entries. No real miner settings were written.
