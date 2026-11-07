# Watch production-network discovery fix, November 3, 2026

## Outcome and acceptance boundary

The operator reported that **Scan for miners did not work** at **22:27 UTC**, then asked Jcode to control and test the simulator. The earlier ten-test UI suites used injected discovery/readings and did **not** prove production-network scanning. Their passing results must not be presented as real discovery acceptance.

The production app was then controlled on a dedicated, empty Watch simulator with **no demo or UI-testing launch arguments, no manually entered addresses and no seeded inventory**. After the fixes below, it automatically discovered all four tracked physical ASICs and fetched their real readings. The saved screenshot shows **4 of 4 current**. This is real-LAN simulator acceptance, not proof of physical Watch networking.

Corrected, signed Watch-only **version 0.1.0, build 13** was installed on the original verified physical Watch at **22:46 UTC**. A read-only installed-app query at **22:51 UTC** independently confirmed bundle `app.hashfleet.watchkitapp`, version `0.1.0`, build `13`. The production launch attempt at **22:47 UTC** was rejected because the Watch was **locked**. A subsequent read-only cache-copy attempt exceeded its 25-second bound. No successful physical scan or phone-off operation is claimed.

### Final real Scan-button acceptance, 23:18 UTC

Re-reading the reported failure exposed an additional coverage gap: the first genuine-LAN test proved automatic discovery, but explicit Scan-button/rescan behavior had only been tested with fixtures. Test commit **`c8b1ee6`** extends the same opt-in production case without removing any original assertion. Capture-only commit **`945afa4`** keeps evidence fully inside the Watch viewport.

On another fresh, independent 44 mm Watch simulator, the final case **passed in 83.852 seconds** with no skip or injected data. It starts empty, automatically discovers the four real ASICs, waits for four current readings, scrolls to and **taps the actual Scan for miners button**, observes real bounded progress/completion, requires **Found 4 compatible miners. No new entries added.**, and verifies **4 of 4 current** again. The copied final inventory contains exactly four tracked endpoints and four fresh readings, not duplicate entries.

The final unchanged 40 mm fixture UI suite also passed **10/10 in 77.355 seconds**, after the last capture-helper edit. The initial real rescan assertions had already passed in 81.607 seconds, but its progress/result screenshots were clipped. Those images were not accepted as visual proof. The final screenshots were inspected and clearly show **33 of 253 checked**, the completed **Found 4 / No new entries** result and the entire **4 of 4 current** summary. Screenshot framing changes only the test harness, not product behavior.

The final evidence/artifact consistency verifier passed **35/35 checks**, including unchanged production source, a frozen pre-execution test-source hash, preserved earlier failures, current-run inventory/readings and the still-unpassed physical gate. The signed physical build 13 executable remains byte-for-byte unchanged. No further Watch/iPhone installation or device-setting action was performed for this acceptance extension.

### Physical follow-up, 22:55-22:58 UTC

A fresh normal production launch on the original Watch **succeeded at 22:55 UTC**. However, a successful read-only copy of its own persisted cache at **22:56 UTC** still contained **zero miners and zero readings**. A launch success therefore does **not** establish scanner success or a continuously active foreground scene. The read-only lock-state query at **22:58 UTC** reported `passcodeRequired: true` and `unlockedSinceBoot: true`. The physical acceptance gate still needs the operator to unlock the Watch and keep Hash Fleet active on miner Wi-Fi. No passcode, security, pairing or radio setting was changed.

At **23:04 UTC**, a bounded read-only LLDB probe selected the original verified CoreDevice and received **Device needs to be unlocked** before attaching. No interface or application-scene expression ran. This directly establishes the diagnostic-access blocker, but does **not** establish why the earlier physical scan saved no miners. The two fixed defects were reproduced in production simulator/validator evidence, not observed inside the inaccessible Watch process. An earlier local LLDB-setting error is preserved separately and is not counted as a physical device observation.

The full read-only fleet preflight was also repeated at **22:56 UTC**, **23:07 UTC** and **23:16 UTC**: all eight ASIC info/log GETs returned HTTP 200, mining-Mac SSH/process/LaunchAgent reads succeeded, and its loopback summary API remained unavailable. No M1 rate or shares were inferred.

## Reproduced causes and scoped correction

Feature/source commit: **`4d117c6`** (`fix(watch): handle compact LAN masks and Naja ASIC model pairs`).

### 1. Valid compact Darwin netmasks were rejected

The original production app displayed the same Wi-Fi guidance as the operator's screenshot. A read-only local `getifaddrs` diagnostic showed the real private IPv4 interface with a 16-byte address but a **7-byte `/24` netmask**. The provider previously required the netmask to occupy all 16 bytes of `sockaddr_in`, discarding the usable LAN before issuing discovery requests.

`WatchSystemInterfaceProvider.decodeIPv4Netmask` now copies only the declared, bounded bytes into a zero-initialized `sockaddr_in`. It accepts the associated IPv4 mask's `AF_INET` or `AF_UNSPEC` family, rejects lengths outside 2...16 and other families, and preserves private-address, contiguous-mask, interface-flag and ambiguity checks. It does not assume an interface name or add a fixed fleet subnet fallback.

The new regression failed before the fix with **nine issues**. Tests cover compact `/0`, `/8`, `/16`, `/24`, `/32`, full-length masks, poison bytes after the declared length, unspecified family, malformed lengths and wrong families.

### 2. Genuine Naja composite ASIC models were rejected

After the mask correction, the production scan saved the two Gammas but not either Naja. Both real Naja responses report **`ASICModel: BM1372/BM1373`**, whereas the original strict identifier admitted only one `BM` plus digits.

The validator now accepts one or two slash-separated `BM` plus ASCII-digit identifiers, retaining the total length bound and the requirement for at least one valid typed telemetry metric. Empty components, unrelated models, trailing letters and more than two model identifiers remain rejected. A sanitized actual-response-shape regression failed before this correction and passed afterward. Raw responses and private miner credentials were not committed.

## Final validation after the source changes

| Requirement | Observed check | Result |
| --- | --- | --- |
| Core behavior and boundary safety | `swift test --filter HashFleetWatchCoreTests` | **150 tests, 13 suites, passed in 15.048 s** |
| Genuine automatic discovery and explicit Scan | Opt-in production UI test on an empty, dedicated standalone 44 mm Watch simulator, actual LAN GETs, no fixture arguments, actual Scan-button tap and duplicate-safe rescan | **Final 1/1 passed in 83.852 s**, four current before and after rescan |
| Real persisted inventory | Inspect the dedicated simulator's Watch-local `fleet.json` | Exactly the four tracked ASIC endpoints and four readings from this validation |
| Existing small-Watch UI behavior | Existing fixture UI cases on the standalone 40 mm Watch simulator after the final test-source edit | **10/10 passed in 77.355 s** |
| Simulator compilation | Final build-for-testing, after the final UI-test edit | Passed |
| Hardware compilation | Final signed generic watchOS Debug build | Passed |
| Requested deployment minimum | Info.plist and both device architecture load commands | **watchOS 26.5**, SDK 27.0 |
| Artifact integrity | Strict code-signature verification and independent-app flags | Passed |
| Actual delivery | Watch-only install plus independent installed-app metadata query | **Build 13 installed and confirmed** |
| Physical scan | Initial launch denied; later normal launch succeeded, but copied inventory stayed empty and lock-state reported passcode required | **Not passed. Operator unlock/active foreground needed.** |
| Physical phone-off networking | Actual Watch on miner Wi-Fi with paired phone unavailable, observing advancing readings | **Not tested** |

The initial read-only evidence/artifact consistency verifier passed **22/22 checks**. The follow-up verifier also checks the successful retry, still-empty physical cache and passcode-required evidence. This includes preserving the locked-launch failure as a failure, not claiming physical networking passed. Signed Watch executable SHA-256: `00c8fd4160b46473a1c1d387c5ca6a7316226cb00cef79865aa0b0a1dec1d859`.

The live-network UI case is intentionally opt-in using `HASHFLEET_LIVE_EXPECTED_MINERS=4` in the test-runner environment. It requires an empty initial inventory, launches without fixture/demo arguments, waits for the real fleet summary, and asserts all four miners are current. Ordinary CI runs skip this one case rather than silently contacting the LAN. The recorded real-LAN run did **not** skip it.

The initial real-network UI failure is preserved. Its wait for the Scan button became invalid once SwiftUI virtualized that offscreen control after discovery. The harness was corrected to observe the actual fleet summary while retaining the empty-start and **four-of-four current** requirements. The two-Gamma intermediate inventory and the separately failing real Naja model regression establish the second production defect independently of that UI-harness failure.

Screenshots inspected by the coordinator show real scan progress followed by the four-current summary. The simulator runtime used was watchOS 27.0, not a simulated 26.6 or 26.5 hardware acceptance run. The physical Watch was last verified as watchOS 26.6 before installation.

## Read-only fleet preflight and safety

The canonical fleet operations playbook was read first. At approximately **22:31 UTC**, all four tracked ASICs completed both `GET /api/system/info` and `GET /api/system/logs` with HTTP 200. The mining M1 host was also checked using its documented SSH/process/LaunchAgent reads. Those reads succeeded, but its loopback XMRig summary API refused connection, so no fresh M1 rate, shares or paused-state claim is made. The Watch scan covers the four compatible ASIC HTTP APIs, not the M1's loopback-only mining API.

No ASIC POST/PATCH, reboot, self-test, OTA, frequency/voltage/fan/pool/wiring change, lockout clear or recovery-policy expansion occurred. No mining-Mac service was restarted or reconfigured. The iPhone app was not replaced, and no device was erased, unpaired, reset or subjected to an automatic security-setting change. All code/device actions for delivery targeted the original verified Watch. Unrelated dirty repository files were not staged or committed.

The optional independent source reviewer did not return a usable report and was stopped. Its attempted review is **not** counted as approval or verification. The coordinator reviewed the scoped diff and observed the checks above directly.

## Remaining physical acceptance

1. Unlock the physical Watch and open Hash Fleet on the miner Wi-Fi network. Keep the app active while the bounded scan runs.
2. Confirm all four ASICs appear and their observation times advance during foreground refresh.
3. Separately verify that advancing readings continue with the paired phone unavailable. Do not infer phone-independent networking from installation or simulator success.

No Bluetooth/Wi-Fi setting or pairing change has been made to force this acceptance gate.

## Private evidence

Owner-private root: `~/.jcode/scratch/hashfleet-real-scan-20261103T2228/`.

- `production-before.png`, `production-after.png`, `inspect-interfaces.swift`
- `compact-mask-before.log`, `composite-model-before.log`
- `Live-MaskOnly.xcresult`, `live-mask-only.log`
- `core-both-fixes.log`, `sim-build-final.log`, `device-build-final.log`
- `Live-Final-44mm.xcresult`, `live-final-44mm.log`, `Live-Final-44mm-attachments/`
- `Fixture-Final-40mm.xcresult`, `fixture-final-40mm.log`
- `watch-fix-install.json`, `watch-fix-install.log`
- `watch-installed-build13.json`, `watch-installed-build13.log`
- `watch-production-launch.json`, `watch-production-launch.log`
- `physical-cache-before-copy.json`, `physical-cache-after-copy.log`
- `watch-production-launch-retry2255.json`, `watch-production-launch-retry2255.log`
- `physical-cache-launch-success2256.json`, `physical-fleet-launch-success2256.private.json`
- `watch-lock-state2258.json`, `watch-lock-state2258.log`
- `asic-*-followup2256.private`, `m1-readonly-followup2256.private`
- `watch-readonly-lldb2303.private.log`, `watch-readonly-lldb2304.private.log`, `watch_readonly_probe.py`
- `Live-Explicit-Scan-44mm.xcresult`, `live-explicit-scan-44mm.log`, `Live-Explicit-Scan-44mm-attachments/`
- `sim-build-framed-scan.log`, `Live-Framed-Scan-44mm.xcresult`, `live-framed-scan-44mm.log`
- `Live-Framed-Scan-44mm-attachments/`, `framed-scan-cache.private.json`, `framed-ui-source.sha256`
- `Fixture-Framed-40mm.xcresult`, `fixture-framed-40mm.log`
- `asic-*-followup2316.private`, `m1-readonly-followup2316.private`
- `verify-real-scan.py`, `final-verifier-strengthened.json`

Raw ASIC responses, Watch container copies, physical device identifiers and signing details stay private. Do not publish those artifacts wholesale.
