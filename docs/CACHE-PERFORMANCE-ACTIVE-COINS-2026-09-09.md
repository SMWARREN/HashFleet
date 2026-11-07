# Active coins, cached settings, and frame pacing (2026-09-09)

## Data and safety

- The 30-day comparison groups only fresh miners whose firmware identifies exactly one active, recognized pool. Each coin uses its own miners' hashrate, including a genuine reported zero. Missing rates are not silently summed as zero.
- BTC and BCH retain the existing verified difficulty sources. BC2, BCH2, XEC, and DGB remain visible but state **Odds unavailable** until a suitable network difficulty source is integrated. Market price is not mining difficulty. DigiByte requires the appropriate algorithm-specific difficulty.
- Last-known settings are cached privately on device with the original observation timestamp. Relaunch restores an explicitly offline, read-only snapshot, not a live reading. First-load placeholders must never replace this cache.
- A strict scalar allowlist excludes passwords, worker/wallet strings, unknown nested values, and URL credentials/path/query/fragment. Host and port are retained. Cached settings are not a backup of every firmware field.
- Demo mode cannot modify the real cache. Removing a miner removes its cached reading. Corrupt cached data cannot destroy the saved fleet.
- Write controls require a recent successful reading. The execution boundary rejects unauthorized writes and performs a fresh read-only info preflight before a confirmed mutation. Cached state or partial WebSocket frames cannot authorize a write.

## Local frame pacing diagnostics

Settings → Diagnostics → Frame pacing enables a local CADisplayLink probe. It is off by default, has no network or disk export, and reports callback cadence by screen. The overlay and reports publish at most once per second during sampling. Each screen retains its own latest 600 gaps. The link is invalidated while disabled or inactive.

These are **callback FPS and callback gap measurements**, not compositor/GPU rendered FPS or proof that individual frames were presented. Diagnostics can themselves affect timing. Adaptive refresh is expected on ProMotion and in power/thermal-constrained conditions. Use Instruments for deeper rendering evidence.

The existing numeric transition remains enabled. Hashrate and Best have separate rows regardless of the number's width. No animation cap or new continuous shimmer is introduced by this batch.

Apple references:
- https://developer.apple.com/documentation/quartzcore/cadisplaylink
- https://developer.apple.com/documentation/quartzcore/cadisplaylink/targettimestamp
- https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange

## CoinMarketCap coverage verified September 9

Read-only checks used the official public keyless map endpoint. No runtime provider migration, account creation, key, or payment was added.

| Coin | CMC ID | Verified listing |
| --- | ---: | --- |
| BTC | 1 | https://coinmarketcap.com/currencies/bitcoin/ |
| BCH | 1831 | https://coinmarketcap.com/currencies/bitcoin-cash/ |
| BC2 | 39213 | https://coinmarketcap.com/currencies/bitcoinii/ |
| XEC | 10791 | https://coinmarketcap.com/currencies/ecash/ |
| DGB | 109 | https://coinmarketcap.com/currencies/digibyte/ |
| BCH2 | Not resolved | The map request returned HTTP 400: `Invalid value for "symbol": "BCH2"`. This is a current API observation, not a claim that no future listing can exist. |

Official documentation: https://pro.coinmarketcap.com/api/documentation/pro-api-reference/keyless-public-api.md

Map request: `https://pro-api.coinmarketcap.com/public-api/v1/cryptocurrency/map?symbol=BTC,BCH,BC2,XEC,DGB`

## Validation checkpoint

The first integrated run passed offline relaunch with cached settings and disabled controls, confirmed online loopback writes, per-screen diagnostic opt-in, all-six-active-coins display, ticker motion and accessibility. It exposed a native request-count assumption and a hash-row geometry acceptance failure. These are being investigated before delivery. Earlier appearance contrast waivers are not accepted as a successful new palette check. Final acceptance and phone delivery results will be appended after testing.

## Final integrated acceptance · 21:49 UTC

- Core: 146 tests in 17 suites passed (`hashfleet-core-final.log`).
- Complete native app suite: 301 tests in 27 suites passed with zero known issues or failures (`HashFleetFinalCachePaletteAcceptance.xcresult`).
- All 10 selected integrated UI tests passed: per-screen frame-pacing opt-in/disable, all active demo coins, consecutive ticker motion, pause/resume, accessible static ticker, zero/wide hashrate row placement, card expansion, demo network isolation, offline cached-settings relaunch and locked fields, and explicitly confirmed online loopback write. No physical miner writes.
- The request-count regression was the legitimate automatic ASIC probe after Info. The test now waits for the report and checks exactly two reads before and after demo transitions.
- The row geometry failure mixed frame coordinates during scroll deceleration. The final test measures both rows from one immutable accessibility snapshot, retaining strict Best-below and left-alignment assertions.
- Adaptive palette/loading run: 16 native tests and 3 UI tests passed (`HashFleetAdaptiveLoadingFirst.xcresult`). This includes compiled launch-screen centering in portrait/landscape and both appearances, exact theme roles and contrast, real loopback skeleton-to-reading transitions in both modes, full appearance navigation and row layout.
- Reproducible palette script: 26 roles, 66/66 required contrast pairs pass, no waivers.
- Signed iPhone app/widget build and strict signature verification passed. Compiled assets contain light/dark AppIcon, HashFleetHeader, LaunchBackground and LaunchScreen.storyboardc. App Group remains only `group.app.hashfleet.shared`.
- Visual inspection: current light/dark dashboard, individual detail and loading attachments in `HashFleetAdaptiveLoadingScreens`. These are simulator observations, not physical-phone FPS or whole-app accessibility certification.
- User subsequently requested per-miner share rejection/error percentages, which is a separately scoped follow-up before the next phone delivery.
