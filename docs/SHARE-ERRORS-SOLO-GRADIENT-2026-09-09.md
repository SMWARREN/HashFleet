# Share statistics, full-width Solo and local fleet management · 2026-09-09

## Latest scope

The user superseded the orange-gradient proposal at 22:13 UTC: restore the original flat Solo color and make only that section full width. No gradient is retained. The user further specified no padding, margin, radius or border at 22:37 UTC. Solo now spans the available width as a square, flat strip with none of those card decorations. All other cards retain their existing colors and margins.

## Share statistics (committed e8b06e4)

The individual hashrate panel shows accepted/rejected counts, rejected / (accepted + rejected) × 100, and separately reported firmware `errorPercentage` when valid. Missing counts remain “Not reported”, two explicit zero counters show “No shares yet”, tiny nonzero rates show “<0.01%”. No hardware error count is invented. Cached errors retain their original observation time and offline read-only protections.

`HashFleetSoloGradientFinal.xcresult` passed 312 native tests in 28 suites and three UI tests covering both-theme share statistics, appearance navigation, and zero/wide hash-row layout. That appearance evidence predates the latest flat full-width change and does not validate the final Solo geometry.

The earlier intermittent row-height test was comparing the HTTP-only fixture before and after its asynchronous live-stream warning row appeared. It now waits for the same fallback state and reads all geometry from one immutable accessibility snapshot. The strict Best-below-hashrate and equal-height assertions remain and passed the combined rerun.

## Local fleet management

- Blank name on manual add or Wi-Fi discovery requests an automatic name.
- Verified board + ASIC combinations use the pinned model matrix (Gamma, Supra, Duo, Hex, etc.). ASIC alone is not enough to guess a board family. Unknown models retain honest ASIC or hostname/address fallback.
- `MinerDevice.usesAutomaticName` is optional for backward-compatible decoding. Explicit names, including an explicitly chosen “Bitaxe”, are never replaced by refresh. Legacy generic/address defaults are upgraded when model information is available.
- Local rename works offline, persists across relaunch and does not change the firmware hostname or observation timestamp. Blank rename restores automatic naming.
- Detail's Manage miner menu and Fleet management section expose rename and confirmed removal. Removing from the app does not reset hardware. Demo management is disabled.
- Local names are trimmed, limited to 64 characters and reject embedded control characters.

## Refresh and splash

Dashboard pull-to-refresh now awaits miner reads and a forced public-data refresh concurrently. Force bypasses the 60-second cooldown and 15-minute coin-market TTL, cancels superseded public requests including the separately owned market task, and retries all eight public dashboard endpoints. External-data opt-out and demo no-network behavior remain. Existing miner reads are joined rather than letting the spinner end early. Failed or stale providers retain honest failure/source timestamps. Individual scoped pool-account cards still own their separate view-lifecycle requests; this dashboard refresh does not fan out to hidden miner settings or arbitrary firmware endpoints.

The committed native launch storyboard is centered and follows iOS system light/dark appearance. It is a static native launch screen, not an animated splash or a delay on every foreground activation. The new white artwork and launch storyboard were not yet installed on the phone when the user reported not seeing them. Native LaunchBrandTests verify both appearances and portrait/landscape centering. Phone cold-launch observation remains pending.

## Validation and delivery

Core regression after optional naming metadata: 146 tests in 17 suites passed. Full native and management/full-width UI acceptance are running. Final source commit, signed package verification and iPhone install results will be recorded below. No real miner setting writes have been performed.

Final native checkpoint: `HashFleetFinalManagementRefresh.xcresult` passed **322 tests in 29 suites**, including force-refresh/cancellation/error tests, all verified model mappings, cache/rename persistence, and native launch-brand checks. Signed device build and deep signature verification passed. Final UI checks are still running.

## Final acceptance and phone delivery

Executable source commit: `fb14ae2` (with earlier `e8b06e4` share statistics and `e70d681` integrated cache/appearance work).

- Final native suite: **322 tests / 29 suites**, zero failures.
- Final UI suite: **3 tests**, zero failures. Pixel samples verify flat near-black Solo spans the screen with square edge pixels in both appearances. Other card surfaces retain their prior palette. Real-mode loopback acceptance verifies automatic Gamma naming, offline rename, relaunch persistence, safe keep/cancel behavior, confirmed removal and persisted deletion. Custom add names override model defaults and demo management is disabled.
- Core suite: **146 tests / 17 suites**, zero failures.
- Screenshots: `/Users/USER/.jcode/scratch/HashFleetFinalFullBleedScreens/`. Light dashboard `7402D3CF-0E89-49AE-8792-024643FD4154.png` visually reviewed.
- Signed device build passed, deep strict signature verification passed, and the compiled adaptive `LaunchScreen.storyboardc` is present with the matching Info.plist setting.
- First transfer attempt failed with a transient CoreDevice tunnel timeout. Retry **installed successfully at 22:44 UTC**, bundle `app.hashfleet`, database sequence 2344. Installation receipt: `hashfleet-management-final-install-retry.json` in scratch.
- Automatic launch was denied because the iPhone was locked. This is an install success, not a launch success. Unlock and open Hash Fleet to use the update. Phone cold-launch splash observation and physical-device frame cadence remain unverified. Frame diagnostics can be enabled in Settings if the denied launch's `--frame-pacing` argument was not applied.

All real hardware interactions in this batch were read-only. No real miners were renamed, removed, reset or reconfigured by the agent. Local-management mutation checks used only isolated loopback fixtures.
