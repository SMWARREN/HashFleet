# Third firmware and public-data audit

Audited 2026-09-06/07 against ESP-Miner master `2943d206f6c8a4b249bc74c820fb56c874ac316d`. This is a bounded route inventory and feature comparison, not a claim of support on every firmware fork.

## Firmware route result

- `main/http_server/http_server.c` SHA256 `3511fb32cb75a444ab7c7ae64988652630c71e952193276dca9f233ee413d63c`.
- `main/http_server/theme_api.c` SHA256 `1bd3077f226e5b00ee382e5870a10ff6a71af12cd4fb52152a683cba813e8348`.
- 23 HTTP-server registrations minus two fallback/static handlers = 21 API operations, including two WebSockets. Add two theme operations = **23 current operations (21 HTTP + two WebSockets)**. One separately labeled legacy dashboard-statistics entry makes 24 catalog entries.
- Existing typed HashFleet catalog covers this method/path inventory, including pool PUT/DELETE slots 0...7, settings, theme, firmware upload and socket transports. No new upstream route gap found. Coverage does not prove every control is supported on a connected firmware or that every write was exercised on hardware.
- Regular valid Info polling now initiates one read-only ASIC compatibility probe per device/firmware identity. Failures back off until manual retry or identity change. Other endpoint support remains unverified. Names and version strings are not permission to perform mutations.

## HashWatcher comparison

Sources: https://hashwatcher.app/ and official App Store listing `id6753040236`, reviewed 2026-09-06. Public feature descriptions are not evidence of the competitor's complete endpoint implementation. Its route coverage is unknown.

| Feature | HashFleet state in this update | Boundary |
|---|---|---|
| Fleet metrics, search, sorting, compact cards, charts | Existing | Missing/offline values are not zeros |
| Best-ever and session share on home | Added | Maximum reported difficulty, never summed or treated as a block reward |
| Mempool, network difficulty, price, block odds | Added | BTC from mempool.space; BCH from Blockchair; separate chains and source ages |
| Configured pool recognition and public statistics | Added | Exact CKPool hosts and 45 documented SoloFury region/coin hosts; other pools displayed without invented adapters |
| Fan/manual tuning/general/display/pool controls | Existing, pool presets expanded | Reviewed firmware API actions, no firmware replacement required; full-slot replacement remains explicit |
| Automatic firmware/device compatibility | Added | Valid Info plus safe ASIC read only; no write-support inference |
| iOS widgets and local Live Activities | Existing | Explicit widget-sharing preference; no Apple Watch app or Mac menu bar |
| Read-only electrical/thermal/pool diagnostics | Expanded | DC rail current is not mains current; kWh/day is an estimate, not metered energy |
| Multi-vendor firmware, solar automation, remote hub, Watch, scheduled reports, push alerts | Not implemented | These are distinct product integrations, not missing ESP-Miner endpoint registrations |

## Public pool scope and privacy

- Configured primary/fallback/other slots are read from Info by persistent slot ID. Unknown activity is labeled unknown.
- Accounts are read only for recognized providers and checksum-validated public payout addresses. Worker suffixes and miner secrets are not sent. Providers see the public address and internet IP. External data can be disabled in Preferences.
- SoloFury supports BCH `/api`, BTC `/api-btc`, BC2 `/api-bc2`, BCH2 `/api-bch2`, XEC `/api-xec`. Coin comes from the verified pool host, not the ASIC or Wi-Fi network. Official sources: https://solofury.com/api-docs/ and https://raw.githubusercontent.com/solofurypool-code/solofury-public-docs/main/reference/stratum-endpoints.md.
- BTC and BCH home odds are independent **what-if** estimates using the whole online fleet at unchanged difficulty. They do not claim that the same hashrate mines both chains simultaneously. Other coins have pool recognition/statistics, not invented market prices.
- Solo pool shares are proof of submitted work, not a share in another miner's block reward. Switching pools does not carry reward credit or make a block due. A best share is not independently verified block/reward attribution.
- No actual miner mutation, reboot, firmware update, tuning change or pool switch was performed during this audit. Public aggregate live checks do not transmit a personal wallet. See expansion acceptance evidence for the tested user paths and remaining constraints.

## Swarm routing evidence

OpenAI and Antigravity workers delivered implementation/reviews. NVIDIA NIM delivered an initial route comparison, whose unsupported competitor claims and count arithmetic were corrected by the coordinator. Its follow-up inference failed. Two Claude workers failed OAuth refresh before doing the assigned audit. No authentication reset or silent replacement claim was made.
