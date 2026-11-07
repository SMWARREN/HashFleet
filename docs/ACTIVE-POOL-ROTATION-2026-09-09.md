# Active pool rotation fix · 2026-09-09

## Cause and correction

The locally saved miner telemetry includes `activePoolIndex` and enabled pool rotation. The app previously inferred the active connection solely from `primaryPoolIndex`, `secondaryPoolIndex` and `isUsingFallbackStratum`. Rotation can change the active slot without changing that fallback flag, leaving the primary pool and its coin on screen.

Explicit `activePoolIndex` now takes precedence, matched by persistent slot ID rather than array order. This updates dashboard and detail coin/provider labels, pool activity badges, diagnostics, setup inventory and the active CKPool account lookup. Firmware without the new field retains its existing primary/fallback behavior. Invalid explicit active indices remain unknown rather than selecting a primary URL or querying its account.

## Validation

- Complete Swift core suite: 143 tests in 17 suites passed.
- Focused native suites: 54 tests in 4 suites passed.
- UI acceptance: `testRotatingPoolShowsCurrentCoinAndProviderInsteadOfPrimary` passed. The screenshot confirms BCH/SoloFury while primary remains CKPool and fallback remains false.
- Model regressions cover repeated BCH/BTC switches, a third noncontiguous XEC slot, shuffled slot order, absent and conflicting fallback flags, invalid/missing active IDs, safe account lookup, diagnostics and setup labels.
- Signed generic-iOS build and `codesign --verify --deep --strict` passed.
- Evidence in local scratch: `hashfleet-active-pool-core.log`, `HashFleetActivePoolAcceptance.xcresult`, `hashfleet-active-pool-device.log`.
- The first native invocation referenced a retired simulator and was cancelled. Acceptance was rerun successfully on the currently booted iPhone 17 Pro simulator.

## iPhone delivery

Initial installation attempts were blocked by `kAMDMobileImageMounterDeviceLocked`. After the user unlocked the paired iPhone, installation and normal launch of `app.hashfleet` succeeded at 19:36 UTC. Evidence: `hashfleet-active-pool-install-ready.json` and `hashfleet-active-pool-launch-ready.json` in local scratch. Physical on-screen pool rotation was not independently verified. No uninstall, app-data reset or miner configuration writes were performed.
