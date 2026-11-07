# Pool icon mock demo · 2026-09-09

## User-visible demo

Settings → Pool icon demo opens a clearly labeled gallery of six synthetic miners:

1. Demo Gamma 1: CKPool · BTC
2. Demo Supra 2: SoloFury · BTC
3. Demo Gamma 3: SoloFury · BCH
4. Demo Supra 4: SoloFury · BC2
5. Demo Gamma 5: SoloFury · BCH2
6. Demo Supra 6: SoloFury · XEC

Each miner has all six supported preset slots. Tap a gallery tile, then **Change mock pool** to update only that miner's simulated active slot, coin icon and provider name. Pools & accounts starts expanded in this preview. The gallery uses the same bundled coin assets and active-pool resolver as the real fleet.

**Exit demo** restores the saved real fleet. The preview is session-only and can also be opened with `--pool-icon-demo`. Normal demo mode remains unchanged. These are in-app coin icons, not alternate iOS Home Screen icons.

## Safety and acceptance

- No real miner settings, credentials or addresses are copied into the demo.
- Six synthetic `.invalid` miner hosts and credential-free pool fixtures.
- Mock switching refuses real mode, the ordinary demo, unknown device IDs and invalid slots.
- Unit coverage exercises all 36 miner/pool combinations, initial six-pool coverage, per-miner isolation, idempotent entry, zero miner polling, unchanged saved fleet bytes and correct exit restoration.
- 41 native tests in FleetStoreTests, MinerReportedStateTests and ConnectedPoolsStoreTests passed.
- `testPoolIconDemoShowsAllMinersAndLetsEachChangePool` passed. It enters from Settings, checks all six gallery tiles, opens each miner, changes its mock pool, verifies updated detail and dashboard labels, and exits the demo.
- Seven simulator screenshots were exported. Visual inspection confirmed all six icons, providers and miner names fit together in the gallery.
- Signed generic-iOS build and strict deep signature verification passed.
- Installation and launch on the paired iPhone succeeded at 19:53 UTC with `--pool-icon-demo`, without uninstalling or resetting app data. Physical touch interactions were not independently exercised.

## Local evidence

All under `/Users/USER/.jcode/scratch/`:

- `HashFleetPoolIconDemo.xcresult`
- `HashFleetPoolIconDemoScreens/` (gallery and six detail screenshots)
- `hashfleet-pool-icon-demo-tests.log`
- `hashfleet-pool-icon-demo-device.log`
- `hashfleet-pool-icon-demo-install.json`
- `hashfleet-pool-icon-demo-launch.json`
