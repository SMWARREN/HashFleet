# Hash Fleet Watch update completion, November 3, 2026

## Outcome

**Software completed and the updated Watch app installed successfully at 22:06:09 UTC.** Automatic bounded local discovery and ten-second foreground refresh are implemented. The minimum remains **watchOS 26.5**, as requested. The physical Watch reports watchOS 26.6.

The first resumed install failed with an RSD allocation error. One bounded retry succeeded without resetting pairing, restarting devices, changing Developer Mode, replacing the iPhone app, or changing any miner. Real Watch discovery/readings with the phone off are **not verified** and remain a separate operator-assisted acceptance gate.

## Scoped commits

| Commit | Scope |
| --- | --- |
| `79b3aad` | Independent read-only Watch core and safety tests |
| `f97fe35` | Native independently runnable Watch app and optional phone setup |
| `6ab6df8` | Test-only synchronization for asynchronous request teardown |
| `057fc03` | Explicitly requested watchOS 26.5 minimum |
| `a4a4f2e6e77d982b404b10b1e82f63a9a80640f0` | Automatic local discovery, cancellation/retry UI, ten-second foreground polling, regression tests and setup guidance |

This completion receipt and the updated implementation ledger are committed separately after the feature commit. The file's Git history identifies that documentation-only commit. No remote Git push, App Store change, TestFlight distribution or external message was performed.

## Delivered behavior

- A real empty Watch inventory gets one automatic search per app session, without typing an address or requiring phone setup. Explicit **Scan for miners**, progress, **Stop search** and manual fallback remain available.
- Discovery derives one eligible active private IPv4 interface and actual contiguous mask. It never assumes an interface name, guesses a network from fixed fleet IPs, or scans from demo mode. Missing or ambiguous interfaces fail closed with Wi-Fi guidance.
- At most one local `/24` is searched, with at most 254 candidates, excluding the Watch, network and broadcast addresses. Smaller subnets are respected, `/31` and `/32` have no candidates, and wider networks are explicitly partial.
- Only high-level URLSession HTTP `GET /api/system/info` on port 80 is used. Limits are eight concurrent probes, one-second request timeout, 1.5-second per-host deadline, 60-second whole-scan budget and 256 KiB maximum response. There are no low-level socket, Bonjour or NWPathMonitor calls.
- Auto-add requires HTTP 200, an acceptable JSON content type or absent header, a typed BM-series ASIC identity and valid supported telemetry. Redirects, credentials, cookies and unrelated responses are rejected. This is compatible-API identification, not authenticated hardware identity.
- Completed scans append missing endpoints to the Watch's own inventory. Existing names, IDs, readings and removals are preserved. Capacity is 16. Persistence failure rejects additions. Cancelled, backgrounded or demo-transition scans save no additions and ignore late progress.
- Saved-miner readings refresh on foreground, on manual request, and **ten seconds after each completed pass** while active. Passes never overlap. Leaving the active scene stops polling. The reading timer does not repeat subnet scans.
- The existing reader retains its five-second request timeout, ten-second overall deadline, safe errors, allowlisted telemetry and original cached observation times after failed reads.

Local Wi-Fi must reach the miners. Cellular alone cannot reach private home-network addresses. Other subnets, custom ports, IPv6-only networks and protected endpoints can require manual setup. XMRig/CPU monitoring, a cloud relay, complications and continuous background polling are not added by this update.

## Final independently executed checks

All production and test-source changes were frozen before these resumed runs. Only documentation changed afterward.

| Gate | Exact observed result |
| --- | --- |
| `swift test --filter HashFleetWatchCoreTests` | **143 tests in 13 suites passed**, zero failures, **15.036 s** |
| Existing core regressions within that run | 72 tests retained |
| New discovery tests within that run | 53 tests across plan, identity, interface-selection and scanner suites |
| New controller/polling tests within that run | 18 tests, including real timer behavior |
| Actual default ten-second polling loop | Second published reading after **10.055 s**, no overlapping reads |
| Standalone unpaired 44 mm Watch simulator | **10/10 UI tests passed**, zero failures, **73.536 s** |
| Standalone unpaired 40 mm Watch simulator | **10/10 UI tests passed**, zero failures, **77.335 s** |
| Signed `generic/platform=watchOS` Debug build | **BUILD SUCCEEDED** |
| Strict code-signature verification | Passed |
| Artifact deployment minimum | **26.5 for both arm64 and arm64_32**, SDK 27.0 |
| Independent app flags | `WKApplication=true`, `WKRunsIndependentlyOfCompanionApp=true` |
| Project/Info.plist syntax and scoped whitespace | Passed |
| User-edited iOS and Watch shared schemes | Original SHA-256 fingerprints preserved byte for byte |
| Final read-only source/artifact/delivery consistency verifier | **36/36 checks passed** after the final documentation edit, separate from the runtime test totals above |

The core checks cover subnet boundaries and malformed inputs, model/name filtering, fixed GET shape, redirect refusal, response limits, bounded concurrency, monotonic unique progress, prompt normal completion, whole-scan budget, cancellation with in-flight teardown and no late callback, atomic append/import behavior, demo isolation, cache corruption/save failures and stale-reading preservation. Fixtures use injected URLProtocol/reading clients, not live network scans.

UI acceptance covers automatic fixture discovery and immediate readings without phone setup, duplicate-free retry, stopping and backgrounding scans, unavailable Wi-Fi with manual fallback, demo exclusion, setup controls, accessible text, list/details, stale totals and unreachable navigation. Actual automatic-result and large-text screenshots were inspected on both sizes, plus the 40 mm scan-progress/stop controls. These are simulator screenshots, not physical Watch telemetry.

### Preserved failures and limitations

The initial discovery 44 mm UI run failed because its result row was outside the virtualized List viewport. The test was corrected to reveal that row without dropping the existence, no-duplicate or current-summary assertions. That failed xcresult/log remains preserved alongside subsequent passing runs. Earlier cancellation fixture failures and their bounded teardown synchronization remain documented in `WATCHOS-IMPLEMENTATION.md`.

The final signed build emitted the pre-existing duplicate `MacMenuBar/Resources` group warning and the no-AppIntents metadata-extraction warning. Both are recorded, not counted as failures or silently called fixed. Device file-protection behavior, real sockets, physical WatchConnectivity import and phone-off Wi-Fi operation are not established by these tests.

## Signed artifact

Owner-private artifact:

```text
$JCODE_SCRATCH_DIR/hashfleet-watch-20261103/Resume-Device-DerivedData.noindex/Build/Products/Debug-watchos/Hash Fleet Watch.app
```

- Bundle identifier: `app.hashfleet.watchkitapp`.
- Version: `0.1.0`, build `12`.
- Executable SHA-256: `975c38ca4b9becad9afdc9c4862c71dd703095306b77a1044534efec363e927d`.
- Both device architectures have minimum OS 26.5. The existing local signing configuration was used. No signing key or profile content is included here.

## Fresh physical checks and actual installation

1. **21:57 UTC discovery:** the physical Series 7 Watch was paired but its tunnel was initially disconnected; Developer Mode was reported unknown. This was not treated as a permanent state.
2. **21:58 UTC direct read-only details:** watchOS **26.6**, paired, tunnel connected, Developer Mode **enabled**, DDI services **available**. This superseded the earlier 10:51 UTC disabled-mode observation without any Jcode mode change.
3. **22:03:09 UTC fresh preinstall check:** the same physical Watch identity and readiness conditions were verified again. The signed artifact passed strict signature verification before the authorized Watch-only install command.
4. **22:03:56 UTC first resumed attempt:** exit 1, `com.apple.dt.CoreDeviceError -1`, underlying `com.apple.mobiledevice -402653181 (0xE8000003)`, **Failed to allocate RSD device**, function `_AMDeviceCreateWithRemoteDeviceUUIDAndTypeWithError`. No successful delivery was claimed from that attempt.
5. **22:04 UTC read-only app queries:** the existing Watch app was visible as version 0.1.0 build 12. That version alone was not treated as proof that this update had installed. The physical iPhone still contained version 0.1.0 build **17**.
6. **22:05:50 to 22:06:09 UTC one bounded retry:** the same signed artifact was selected by the verified Watch UDID. `devicectl device install app` returned **exit 0, App installed**, for `app.hashfleet.watchkitapp`, with a new installation container. No reset, unpair, restart, security change, iPhone install or app launch was used.
7. **22:07 UTC postinstall read-only queries:** verified `app.hashfleet.watchkitapp` version 0.1.0 build 12 in a different installation container from the failed attempt. The physical iPhone remained version 0.1.0 build **17**, at the same installed bundle location. Detailed private results remain outside Git.

The exact cause of the first RSD allocation failure is unknown. A bounded official-Apple search did not produce an authoritative explanation of that exact error. The later successful retry establishes actual delivery, not a proven permanent pairing repair or proof that selecting a UDID alone caused recovery.

## Remaining operator-assisted gates

- Open the installed app on the Watch while it is connected to the miner Wi-Fi. With an empty inventory, observe real automatic discovery and advancing current readings.
- With explicit operator cooperation, disconnect/power off the phone and verify the **actual Watch observation timestamp advances**. Do not infer phone-off success from installation, fixture tests or cached readings.
- Verify real connection-loss/cache behavior and on-device file protection if those hardware acceptance requirements are to be closed.

Jcode did not launch the physical app in real mode or issue live miner requests during this resumed completion. No live fleet status is claimed. Before reporting such status, follow the canonical playbook and check all four ASIC info/log pairs and the mining Mac. No miner setting, firmware, service, power wiring, recovery policy or lockout was changed.

## Private evidence index and preservation

Under `$JCODE_SCRATCH_DIR/hashfleet-watch-20261103/`:

- `resume-watch-core-final.log`.
- `Resume-WatchUI-44mm.xcresult`, `resume-watch-ui-44mm.log`, `Resume-WatchUI-44mm-attachments/`.
- `Resume-WatchUI-40mm.xcresult`, `resume-watch-ui-40mm.log`, `Resume-WatchUI-40mm-attachments/`.
- `resume-watch-signed-build.log`, `Resume-Device-DerivedData.noindex/`.
- `resume-device-list.json`, `resume-watch-details.json`, `resume-watch-preinstall.json` and associated logs.
- `resume-watch-install.json` / `.log` for the preserved failure; `resume-watch-install-retry.json` / `.log` for successful delivery.
- `resume-watch-apps.json`, `resume-watch-apps-after-install.json`, `resume-iphone-apps.json`, `resume-iphone-apps-after-install.json` and associated logs.
- `verify-watch-resume.py`, `resume-final-verifier.json` and the postcommit verifier output.

Unrelated dirty `.blitz` files/screenshots, shared schemes, `Package.resolved`, the information-page stability document and `marketing/` were preserved and excluded from scoped commits. The canonical installed Mac app was not replaced or restarted. No raw fleet responses, wallet addresses, pool/Wi-Fi credentials, device identifiers, private keys or signing material are included in this receipt.
