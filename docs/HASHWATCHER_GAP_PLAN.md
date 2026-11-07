# HashWatcher-inspired improvements

Sources inspected 2026-09-12: https://hashwatcher.app/ and https://hashwatcher.app/changelog.html. These are vendor claims, not independent verification. Borrow useful capabilities, not branding or artwork.

## Already present, do not rebuild

- Fleet hashrate, power, efficiency, thermal metrics, status and history.
- Miner fan/tuning/settings controls with supported-field checks and confirmation.
- Block and personal-best event detection and best-effort local notification infrastructure.
- Network difficulty/coin-aware insights, pool details, widgets and Live Activities.
- Local persistence and raw endpoint export. Raw endpoint export is not a readable fleet report or safe fleet configuration backup.

## Current scoped swarm

| Gap | Bounded implementation | Safety boundary |
| --- | --- | --- |
| Per-device temperature alerts | Opt-in thresholds, fresh-reading policy, hysteresis/cooldown and honest iOS delivery guidance | No shutdown/tuning commands; no guaranteed background cadence |
| Readable reports | On-demand fleet snapshot PDF/CSV, capture time, freshness and missing metrics | No fictional daily history; private identifiers excluded by default |
| Privacy-safe display | Tap-to-reveal local sensitive identifier component and scoped read-only integration | Not screenshot prevention; no network/data mutation |
| Electricity estimates | Locally saved tariff and instantaneous-power daily/monthly projections with coverage | Estimates, not metered bills or profitability claims |
| Portable fleet backup | Explicit local versioned configuration export/import preview, additive confirmed restore | Private local addresses disclosed; no credentials, cloud, deletion or overwrite |

Workers must confirm each gap in repository before implementing. Coordinator owns shared Settings, app/store integration and Xcode project generation. Workers own separate new feature files and tests.

## Not included without further engineering

Solar integrations, scheduled hardware changes, renting hashpower, remote on/off, and arbitrary Braiins/LuxOS/VNish/Canaan protocol support are separate high-risk or major integrations. A competitor's supported-device list is not evidence our protocol works with those devices. No app rename, asset changes or splash work in this scope.

## Acceptance gates

Every shipped page must be reachable through the real app. Run existing and new unit tests, real UI navigation, PDF/CSV/import boundary checks, signed device build and explicit iPhone install if available. Distinguish fixture results from live hardware and OS notification delivery. No feature is complete merely because a worker wrote files.
