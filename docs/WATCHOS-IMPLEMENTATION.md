# Independent Hash Fleet for Apple Watch

## Goal and safety boundary

The Watch app must remain useful with its paired iPhone powered off. This is a native, independently runnable watchOS app within the Hash Fleet product, not a mirrored notification. The Watch retains its own miner list and last successful readings and directly issues bounded `GET /api/system/info` requests over reachable local Wi-Fi. Empty Watch inventories can run bounded foreground/frontmost local discovery, with a retry after a true background interruption, as requested on November 3, 2026. Discovery and readings use GET only. There are no miner writes, restarts, OTA, tuning, pool edits, background subnet scans, or mining-Mac service operations.

This does not provide remote access to private miner addresses over cellular. Away from the miner network, readings remain cached with their real observation time. No new cloud service, public miner exposure, continuous background monitor, or guaranteed complication refresh is included. A physical Watch phone-off networking test is a separate acceptance gate, not implied by a simulator pass.

## Latest Smart Stack shortcut, November 4, 2026, 00:46 UTC

The operator requested a quick way to open Hash Fleet from the Watch swipe-up view. Commit **`a4e295c`** adds an embedded static WidgetKit launcher with a gold **Hash Fleet / Open miners** Smart Stack card. Default widget taps open the independent Watch app. The extension has no miner data, network work, shared container, new permission or background monitor. Existing Watch app/core source and core tests are unchanged. Circular and inline watch-face families are also declared and compiled, but were not separately runtime-tested on a face.

Final actual system-gallery add, warm tap and cold tap acceptance passed on **44 mm watchOS 26.5 in 26.377 s** and **40 mm watchOS 27.0 in 30.472 s**, without demo/fixture app arguments or app activation satisfying the launch assertions. Complete result bundles and real card/pre-cold-tap/app screenshots were inspected. **159 unchanged core tests** and **12 unchanged 40 mm fixture cases** also passed. Earlier system navigation, repeat-setup and clipped-tap failures are retained, not counted as passes.

Signed Watch-only **build 15** installed on the original verified physical Watch at **00:44:35 UTC**, after one transport-disconnected install and an independently checked build-14 inventory. Independent installed metadata confirmed build 15 at **00:45:15 UTC**. A successful read-only postinstall cache copy at **00:46:37 UTC** verified the four saved miner identities are identical to the fresh preinstall backup and four readings remain. One normal production launch timed out after 25 seconds. Physical widget tapping, current lock state, post-fix wrist-down behavior and phone-off networking were not established. No iPhone, pairing, security, radio, miner or mining-Mac changes occurred. Open the updated app once, then use **swipe up → Edit → Add widget → Hash Fleet**, add its launcher, pin if desired, and tap **Done**. See [the Smart Stack delivery receipt](WATCHOS-SMART-STACK-2026-11-03.md).

## Latest lifecycle, recurring-refresh and layout correction, November 3, 2026, 23:53 UTC

The operator's scan-interruption and one-shot-update report exposed root-view cancellation on inactivity/onDisappear. Commits **`f28c7ad`** and **`db8a7a8`** move work to app-owned lifecycle coordination, preserve work during brief frontmost inactivity, save validated discoveries on true background entry and retry the interrupted search on return. Readings continue with ten seconds between completed passes and refresh immediately after return or inventory changes. Explicit Stop/demo isolation, cancelled-pass serialization and existing read-only HTTP limits remain. A visible Updated time and its real observation value distinguish repeated reads from a static current badge.

The Refresh button now uses a fixed icon slot and single-line body text. The initial small-Watch geometry failure is preserved; its exact one-point assertions were not relaxed. Final **159 core tests passed in 20.101 s**, **12/12 fixture UI cases passed on 40 mm watchOS 27.0 in 106.117 s**, and **2/2 UI cases passed on 44 mm watchOS 26.5 in 128.798 s**. The latter includes genuine empty-inventory discovery, the actual Scan button, duplicate-safe rescan, three automatically advancing four-miner observation cycles, immediate return refresh, and the same busy-text assertions. No demo/fixture data was used for the genuine-LAN case.

Signed Watch-only **build 14** was installed and its installed metadata confirmed at **23:53 UTC**, with minimum watchOS 26.5. A normal production launch was denied as **Locked**. Four older real readings were backed up before installation, and the 23:54 UTC postinstall cache read verified the four saved miner identities are unchanged. This does not prove recurring post-fix hardware behavior. Actual Watch foreground/wrist-down behavior and phone-off networking remain unpassed. No iPhone replacement, security/radio/pairing change, miner write or mining-Mac service action occurred. See [the lifecycle and refresh receipt](WATCHOS-LIFECYCLE-REFRESH-2026-11-03.md) for preserved failures and acceptance limits.

## Earlier field correction and acceptance, November 3, 2026, 23:18 UTC

The original discovery UI suites used fixtures and missed two production failures: compact Darwin netmasks were rejected, and genuine Naja `BM1372/BM1373` model identifiers were rejected. Commit **`4d117c6`** fixes both. A dedicated empty Watch simulator, launched without fixture/demo arguments, then automatically discovered all four real ASICs and fetched their readings. **150 core tests**, the **strengthened real-LAN UI case (83.852 s)**, and the **ten existing 40 mm fixture UI cases (77.355 s)** passed. The real case now also taps Scan for miners, observes bounded production progress/completion, requires four found without duplicate additions, and confirms four current again. Final progress/result/summary screenshots are fully visible and inspected. Test-only commits `c8b1ee6` and `945afa4` do not change physical build 13. See [the production-network scan receipt](WATCHOS-REAL-NETWORK-SCAN-FIX-2026-11-03.md).

Corrected Watch-only **build 13** was installed and its installed metadata independently confirmed. The first physical launch was denied as locked. A later normal launch succeeded at 22:55 UTC, but its copied cache at 22:56 UTC still had zero miners/readings, and the 22:58 UTC lock-state query reported passcode required. A bounded read-only LLDB attempt at 23:04 UTC explicitly returned Device needs to be unlocked before attaching, so no physical interface or scene state was observed. This blocks diagnosis, not proof that locking caused the empty inventory. Physical scanning, phone-off operation and on-device file protection remain separate, unpassed gates. No iPhone replacement, pairing/security change or miner write was performed.

## Ownership during implementation

- Coordinator: `Package.swift`, `project.yml`, generated Xcode project, Watch resources, optional configuration-only iPhone transfer, integration tests, documentation and final validation.
- Data worker: only `Sources/HashFleetWatchCore/**` and `Tests/HashFleetWatchCoreTests/**`.
- UI worker: only `WatchApp/*.swift` and `WatchApp/Views/**`.
- Do not touch unrelated dirty files, saved production preferences or the installed Mac app.

## Shared API contract

Module `HashFleetWatchCore` uses Foundation and Observation, plus conditional Darwin access only for read-only `getifaddrs` interface metadata. It must not depend on the database-backed `HashFleetCore`, GRDB, SwiftUI or WatchConnectivity, or perform low-level/WebSocket network I/O. Discovery does not use sockets, Bonjour or `NWPathMonitor`. Interface names are not assumed. Existing iOS/macOS deployment versions remain unchanged. Watch minimum: watchOS 26.5, as explicitly requested on November 3, 2026. The initial implementation and earlier acceptance runs used watchOS 10 as their minimum. Swift language mode: 6.0.

- `WatchMiner: Identifiable, Codable, Equatable, Sendable`: public `id: UUID`, `name: String`, `address: String`; public throwing `init(id: UUID = UUID(), name: String, address: String)`. Validate and normalize credential-free HTTP(S) endpoints. Only private IPv4, unqualified hostnames and `.local` hosts are allowed. Reject credentials, non-root paths, queries, fragments, invalid ports, public Internet addresses, loopback and obfuscated IP forms. A root slash and default ports may normalize away.
- `WatchMinerReading: Codable, Equatable, Sendable`: public `minerID: UUID`, `observedAt: Date`; optional `Double` fields `hashrateGHs`, `powerWatts`, `chipTemperatureC`, `vrTemperatureC`, `uptimeSeconds`; optional `Int` fields `acceptedShares`, `rejectedShares`; optional `Bool` `isMiningPaused`; `isStale(at: Date) -> Bool` with a 60-second boundary and invalid/future-date guard. Public construction is needed for UI fixtures/tests. Maximum valid `temp` and `temp2` is the chip temperature.
- `WatchMinerReadingClient: Sendable`: `func fetch(_ miner: WatchMiner) async throws -> WatchMinerReading`.
- `WatchMinerHTTPClient`: default and injectable `URLSession` construction. Default ephemeral session, no cookies/cache/credentials, bounded timeout and response size, fixed read-only path, rejected redirects, safe generic errors and response validation. Do not persist raw response data or private pool/Wi-Fi fields.
- `@MainActor @Observable public final class WatchFleetStore`: read-only public `miners: [WatchMiner]`, `readings: [UUID: WatchMinerReading]`, `failures: [UUID: String]`, `isRefreshing: Bool`, `storageError: String?`, `isDemo: Bool`. Public `init(storageURL: URL? = default-own-Application-Support-file, client: any WatchMinerReadingClient = default-HTTP-client)` where explicit nil disables disk. `addMiner(name: String, address: String) throws`, `removeMiner(id: UUID) throws`, `refresh() async`. `static func demo() -> WatchFleetStore` is fixture-only and never contacts miners or production storage.

Store requirements: maximum 16 unique endpoints, validated versioned atomic JSON persistence, original successful reading times preserved across failures and relaunch, no zero substitution for missing fields, bounded structured polling, refresh coalescing, cancellation without fabricated failures, no late reintroduction of removed devices, and configuration persistence failure must not silently accept a mutation.

## Watch presentation

- Native SwiftUI NavigationStack, compact readable black/gold presentation, no decorative hero.
- Fleet summary labels partial totals honestly. Only fresh reachable readings count as current.
- Miner list and details show reported hashrate, power, chip/VR temperature, shares, uptime, pause state and observation time. Missing readings say Not reported. Unreachable means the Watch could not fetch, not proof the hardware is offline.
- Manual Add miner form works on the Watch without an iPhone. Removing requires confirmation and only removes the local Watch entry.
- Refresh on foreground/open, explicit button, and ten seconds after each completed pass while active or still frontmost/inactive. App-owned work survives view disappearance and brief inactivity, stops on actual background entry, and refreshes immediately on return. Passes are coalesced and never overlap, with no suspended/background live-feed promise. Passive age/staleness rendering advances without changing real observation timestamps.
- An empty real fleet gets one automatic local discovery attempt per app session, with a bounded retry after a background-interrupted search. Brief inactivity does not cancel the search. True background entry saves validated discoveries; explicit Stop does not accept partial discoveries and stays stopped. Explicit retry, progress and manual setup remain. Discovery never runs from the readings timer or demo mode, and preserves names/readings, deduplicates endpoints and respects the 16-miner capacity.
- Explicit demo is isolated from real inventory and never requests real miners. Exiting demo restores local real configuration.
- VoiceOver labels, Dynamic Type, natural wrapping, and readable native action targets.

## Requirement-to-check ledger

| Requirement | Acceptance check | State |
| --- | --- | --- |
| Phone-independent data | Watch-local config/cache and HTTP fixture tests, standalone unpaired Watch simulator launch | Passed in code and simulator. Physical networking remains open. |
| Read-only safety | HTTP method/path assertions and source/target audit, no destructive API calls | Passed |
| Missing/invalid fields | Decoder tests including negative sentinel, wrong JSON, strings, booleans and nonfinite values | Passed |
| Connection loss | Failed-read preservation of cached timestamp, stale UI and restart persistence | Passed |
| Safe setup | Address validation, duplicate/maximum inventory, corruption and save-failure tests | Passed, including append-only import and failed-quarantine protection |
| Concurrent lifecycle | Coalescing, cancellation, late-response removal tests | Passed, including stalled/slow-drip deadline teardown |
| Native Watch experience | Normal/small-screen and accessibility-size screenshots, list/detail/setup/error interactions and stable busy Refresh geometry | Final 12 fixture cases passed on 40 mm, and genuine recurring-network plus identical busy-text assertions passed on 44 mm. Exact ready/busy text/button frames and readable screenshots accepted on both sizes. Earlier accessibility setup coverage remains, not a new all-fonts certification. |
| Automatic discovery | Private-subnet planning, strict identity, bounded HTTP, lifecycle/checkpoint safety and genuine Scan UI | Final 159-test core suite and genuine four-ASIC auto/Scan/rescan plus repeated real refresh passed. Earlier fixture-only gaps and failures are preserved in the dated receipts. Actual post-fix physical runtime and phone-off networking remain open. |
| Frequent foreground readings | Real ten-second loop, app-owned inactive/background lifecycle, no overlap, immediate return refresh and real repeated UI observation timestamps | Passed within 159 core tests and final genuine-LAN 44 mm case: three automatically advancing four-miner cycles plus immediate refresh after return. Physical post-fix runtime remains unpassed. |
| Smart Stack quick launch | Actual system gallery add plus warm and cold widget taps on 44 mm watchOS 26.5 and 40 mm watchOS 27.0 | Passed on both sizes. Static launcher only, no background data promise. Physical tapping remains unverified. |
| Existing apps preserved | iOS integration build and scoped native Mac compile without installing/restarting it | Both compiled. Four iOS export tests and two settings UI tests on each of phone/tablet passed. Landscape visual capture remains inconclusive. |
| Device delivery | Check physical Watch availability and signing; report actual installation separately | Signed build 15, minimum 26.5, installed on the original physical Watch at November 4 00:44:35 UTC and independently confirmed. Four saved miners verified identical after update. Normal launch timed out, not a new confirmed lock state or physical-runtime pass. See [the Smart Stack receipt](WATCHOS-SMART-STACK-2026-11-03.md). |
| Phone-off real networking | Physical Watch on miner Wi-Fi, phone disconnected/powered off, fresh observation advances | Not yet tested |

## Evidence

Checked November 3, 2026, with Xcode 27.1 and the official watchOS 27.0 simulator runtime.

- Root final rerun of `swift test --filter HashFleetWatchCoreTests`: **72 tests passed in 15.040 seconds**, including a fully stalled request, a slow-drip response reaching the 10-second overall deadline, cancellation teardown, GET-only/path assertions, rejected redirects, bounded response/cache, validated addresses, missing metrics, corruption backups, atomic save failure, import collisions/capacity, bounded concurrency and demo isolation. Core committed as `79b3aad`.
- A preceding final rerun recorded **71/72**, failing the immediate `stopCount` assertion after cancellation. That failure is preserved in `watch-core-final-2.log`. The test-only fixture now awaits a bounded observable stop and isolates late teardown events by test generation. The load-start barrier, `CancellationError`, under-five-second cancellation bound and mandatory teardown assertion remain. No production core change was made. The scoped verifier ran 40 isolated cancellations and five full suites successfully, followed by the root final rerun after source freeze. In that root run the cancellation result arrived at 0.105 ms and `stopLoading` at 0.118 ms, directly demonstrating that teardown delivery can trail the task result.
- `HashFleetWatch` simulator SDK build: passed for arm64 and x86_64. Actual signed `generic/platform=watchOS` Debug build: passed using the existing local development signing team.
- `HashFleetWatchUITests`: **5/5 passed on a standalone unpaired 44 mm simulator**, then **5/5 passed on 40 mm**. Tests cover independent empty launch, accessible manual-setup controls, demo list/details, stale totals, and unreachable navigation. These do not claim that text entry, WatchConnectivity delivery, real socket connectivity or file-protection behavior passed on hardware.
- Initial Watch runs preserved as failures. Empty setup now prioritizes Add miner, error guidance follows the miner list, and tests use precise native-content drags rather than flinging past virtualized rows. A semantic case-sensitive string mismatch was corrected without dropping its stale-data assertion. All acceptance cases were rerun.
- iOS app with embedded Watch app compiled and **4/4 `FleetWatchSetupSelectionTests` passed**, verifying credential-free local ASIC allowlisting, demo exclusion, normalized deduplication, and configuration-only encoding.
- **2/2 `FleetWatchSettingsUITests` passed on iPhone 17 Pro and 2/2 passed on iPad Air 11-inch** after the final test-only edit. Portrait, lower guidance, empty transfer protection, accessibility text and post-rotation navigation were exercised. The earlier phone runs remain recorded as failures. Blind downward swipes were dismissing the settings sheet, so the test now scrolls within content and asserts that the page remains presented.
- Root inspected small-Watch normal/large-text and tablet portrait/large-text screenshots. Phone portrait/lower/large-text screenshots were inspected by the scoped verifier. Landscape screenshots on phone and tablet are cropped with a black band, so they are not accepted as visual proof. Rotation geometry and reachable lower guidance passed accessibility assertions, but landscape visual acceptance remains open.
- Native `HashFleetMac` compiled successfully without launching, reinstalling or restarting the canonical Mac app. The generated app was archived to a ZIP, unregistered and removed from hidden nonindexed staging. `/Applications/Hash Fleet.app` remained the sole Applications installation and the running process path.

Private build/test artifacts are under `$JCODE_SCRATCH_DIR/hashfleet-watch-20261103/`: `watch-core-final-1.log`, `watch-core-final-2.log`, `watch-core-final-3.log`, `watch-build-2.log`, `WatchUI-3.xcresult`, `WatchUI-3-attachments/`, `WatchUI-40mm.xcresult`, `iPhone-WatchSetup-1.xcresult`, `iPhone-WatchSetup-3.xcresult`, `iPad-WatchSetup-1.xcresult`, `watch-device-build-1.log`, `watch-device-install-2.log`, and `mac-build-1.log`. No raw fleet telemetry was collected or committed during that initial build/test phase. The later production-network checks are recorded separately above, with raw responses kept only in owner-private evidence.

### Physical installation boundary

At 08:04 UTC, the companion iPhone was verified connected over a trusted wired transport with Developer Mode enabled. Non-destructive pairing commands reported success for both devices, but did not restore Watch connectivity. A real install attempt at 08:06 UTC failed before transfer with CoreDevice error 4000 and RemotePairing error 1035, indicating the Watch rejected the Bluetooth development connection and suggesting renewal through the companion phone. Watch Developer Mode was then requested as the next user-visible check. A second authorized install attempt at 08:17 UTC returned the same errors before transfer. The existing iPhone app was inspected read-only and was not overwritten or downgraded. At 08:21 UTC the operator reported a platform mismatch and an operator-initiated Watch software update. At that point, further installation attempts were paused until the operator confirmed that update was finished. See the follow-up below for the later live check and requested deployment minimum.

The separately reported App Intents deprecation was fixed and committed as `9ddcfb5`, with iOS/Mac builds and all 15 control-safety tests passing. This changes existing phone/Mac controls, not the read-only Watch target. See [confirmation compatibility evidence](APPINTENT-CONFIRMATION-2026-11-03.md).

**At the initial delivery checkpoint above, physical installation was not verified and phone-off real Wi-Fi acceptance had not passed.** Later state and attempts are recorded in the resumed completion receipt below. No device was erased, unpaired, reset or rebooted by Jcode, no security settings were toggled automatically, and no miner or mining-Mac operation was performed. Do not convert simulator success or a signed build into a claim of physical delivery.

### Requested watchOS 26.5 minimum, November 3, 2026

At 10:51 UTC, fresh CoreDevice discovery finally returned the physical Series 7 Watch running **watchOS 26.6**, paired with a connected development tunnel. It also reported **Developer Mode disabled** and DDI services unavailable. The companion iPhone was connected with Developer Mode enabled. These are timestamped observations, not a claim that the Watch remains in that state after subsequent operator actions.

The operator explicitly requested a **26.5 minimum**. The initial minimum had been 10.0, so this is an intentional increase in the supported minimum, not an installation of an older SDK or a Watch software downgrade. `project.yml`, all four generated project configuration defaults, and `Package.swift` now agree on watchOS 26.5. The Watch app and UI-test targets inherit that value for Debug, Release, DebugNoAppPush and ReleaseNoAppPush. iOS 17 and macOS 14 minimums are unchanged.

After the final version-setting edits:

- A fresh signed `generic/platform=watchOS` build passed. Its Info.plist `MinimumOSVersion` is **26.5** and `vtool -show-build` reports **26.5 for both arm64 and arm64_32**. The SDK remains 27.0. Strict code-signature verification passed.
- `swift test --filter HashFleetWatchCoreTests` passed **72 tests in 7 suites**, in 15.048 seconds.
- The standalone 44 mm Watch simulator UI suite passed **5/5 tests**, with zero failures. This rerun does not assert physical networking or a 26.6 simulator runtime test.
- Package manifest and all four effective configurations for both Watch targets were checked. The pre-existing, user-edited iOS and Watch shared schemes were preserved byte for byte instead of regenerating over them.
- Existing duplicate `MacMenuBar/Resources` group and no-AppIntents metadata-extraction warnings appeared, but did not fail either build. They are unrelated to this version-only change.

Private artifacts are `watch-min265-device-build.log`, `WatchMin265-Device-DerivedData.noindex/`, `watch-min265-core-tests.log`, `watch-min265-ui-tests.log`, `WatchMin265-UI.xcresult`, `watch-min265-package.json`, and `watch-min265-project.json` under the same scratch root.

At 10:55 UTC the operator reported that the connection was almost working in Xcode. Jcode left that connection alone and did not toggle Developer Mode, restart a device, retry installation or overwrite the installed iPhone/Mac apps at that checkpoint. Physical delivery and the real phone-off test remained separate acceptance gates.

## Resumed discovery and foreground refresh completion, November 3, 2026

Feature commit **`a4a4f2e`** adds one automatic empty-fleet discovery attempt per app session, explicit bounded scan/retry/stop, strict compatible-API identification and append-only Watch-local setup. Search uses one eligible private IPv4 interface, at most one local `/24`, eight concurrent GET requests, a one-second request timeout, a 1.5-second per-host deadline and a 60-second overall budget. Cancellation, leaving the active scene or entering demo saves no discovery additions. Manual setup remains available.

Saved-miner readings refresh immediately on foreground and ten seconds after each completed pass. The timer never repeats discovery, never overlaps passes and stops outside an active real scene. The existing reader's five-second request timeout and ten-second whole-read deadline are retained by the shared secure transport.

After the final source edit, the resumed root independently ran:

- **143/143 core tests in 13 suites**, passing in **15.036 seconds**. This includes 72 existing regressions, 53 discovery tests and 18 controller/polling tests. The real polling timer published its second reading after **10.055 seconds**.
- **10/10 standalone 44 mm Watch UI tests**, zero failures, **73.536 seconds**.
- **10/10 standalone 40 mm Watch UI tests**, zero failures, **77.335 seconds**.
- A fresh signed physical Watch build, strict signature verification, independent-app flags and **minimum watchOS 26.5 for both arm64 and arm64_32**. The SDK is 27.0. Both user-edited shared schemes remain byte-for-byte unchanged.

Normal automatic-result and accessibility-text screenshots were inspected on both sizes, plus 40 mm scan-progress controls. Fixtures contact no real miners. The earlier failed discovery UI run is retained: its rescan result was outside the List viewport, so the test now reveals that row while keeping all existence, duplicate and current-summary assertions. No acceptance requirement was removed.

See **[the sanitized resumed completion receipt](WATCHOS-RESUME-2026-11-03.md)** for exact artifact identity, private evidence names, commits, fresh physical Watch state, actual install outcome and remaining gates. Real Watch discovery/connectivity, phone-off operation and on-device file protection are not established by these software checks.
