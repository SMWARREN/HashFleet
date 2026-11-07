# Watch scan lifecycle, recurring refresh and Refresh layout, November 3, 2026

## Request and acceptance boundary

At 23:29 UTC the operator reported that the Watch closes during scanning, stopping the search, and that readings should keep updating while the app runs. At 23:32 UTC they also reported that tapping Refresh breaks up its text. This follow-up supersedes the earlier scan-only receipt for lifecycle and recurring-update acceptance.

Source commits: `f28c7ad` and `db8a7a8`. Hardware artifact: independent Watch bundle `app.hashfleet.watchkitapp`, version 0.1.0, build 14, minimum watchOS 26.5. The tested build was installed and its installed metadata independently confirmed at 23:53 UTC. Installation alone is not physical runtime acceptance.

## Evidenced defects and corrections

### Inactive is not the same as background

The prior root view cancelled discovery both whenever `scenePhase != .active` and in `onDisappear`. Its SwiftUI `.task(id:)` also cancelled the readings loop on inactivity, miner-count changes or view lifetime changes. On watchOS, becoming inactive or disappearing does not by itself prove the app has actually entered the background. This code could discard an unfinished search and leave an empty real fleet with its one automatic attempt already consumed.

`WatchFleetActivity` now belongs to the app, rather than a navigation/view task. It distinguishes active, inactive/frontmost and actual background transitions:

- Brief inactivity does not cancel an ongoing scan or frontmost readings loop.
- Entering the actual background saves already validated scan discoveries using the existing atomic import rules, stops network work and marks the interrupted search for a bounded retry on the next activation.
- Reopening refreshes saved miners immediately. Newly added/imported entries also trigger a prompt read, without tying loop lifetime to miner count.
- The old cancelled refresh task finishes before its replacement starts. A rapid return therefore cannot merely join a cancelled pass and then sleep for ten seconds.
- Explicit Stop remains stopped across app switches. Demo still cancels real discovery/polling and never contacts the network.
- The timer waits ten seconds after each completed pass. Requests remain bounded and coalesced, with no overlapping reading passes.

A background-interrupted scan retries its bounded subnet search. It does not persist a per-host continuation cursor and does not claim uninterrupted work while suspended. Already discovered/saved miner entries survive the interruption. Explicit Stop still adds no in-progress discoveries.

The fleet summary now exposes the real oldest available observation timestamp and displays an Updated time including seconds. UI tests require that timestamp to advance repeatedly, rather than accepting a static current badge or a counter that could advance without fresh readings.

### Refresh must not change its text geometry

The original button conditionally added a trailing spinner and spacer beside a Label. That consumed text space on a small Watch. The first replacement still changed the accessible label height from 20.832 to 23.5 points when busy. The 40 mm acceptance failed and was kept as a failure.

The final correction uses a fixed 24 by 24 point leading icon slot, with the ready icon and busy spinner sharing that slot. Refresh is explicit, single-line body text with no new trailing column. Busy state is also announced through the button's accessibility value. The exact original one-point geometry tolerances were retained. No assertion was removed, widened or converted to a skip to get a pass.

The controlled layout case uses a deliberately five-second, network-free fixture read so it can inspect the real disabled/busy button before, during and after the fetch. This fixture result must not be confused with the separate genuine-LAN case.

## Validation ledger

| Requirement | Observed check | Result |
| --- | --- | --- |
| Core lifecycle, timer and safety regressions | Final post-layout `swift test --filter HashFleetWatchCoreTests` | 159 tests in 14 suites passed, 20.101 s |
| Repeated timer behavior across inactivity | Four published reads, including a ten-second inactive/frontmost interval, immediate activation read, another timer pass, and concurrency peak one | Passed in core suite |
| Fast return during cancelled HTTP pass | Immediate fresh read after background/active round trip, no cancellation failure and no overlap | Passed in core suite |
| Scan checkpoint safety | Persisted validated partial discoveries, retry deduplication, old callback rejection, removed-entry/manual-name protection, explicit Stop | Passed in core suite |
| Genuine discovery and ongoing readings | New empty 44 mm watchOS 26.5 simulator, no fixture/demo arguments, real Scan tap, four found without duplicates, three advancing automatic refresh cycles and immediate refresh after app switch | Final post-layout genuine case passed 108.656 s, no skip; all four observations advanced in three timer cycles and again after return |
| Small Watch and busy text | Twelve fixture UI cases on 40 mm watchOS 27.0, including exact busy geometry and app-switch behavior | Final 12/12 passed, 106.117 s; initial 11/12 retained as failure evidence |
| Larger Watch busy text | Same unchanged busy geometry assertions on 44 mm watchOS 26.5 | Passed 20.143 s; combined final 44 mm run 2/2 passed in 128.798 s |
| Hardware artifact | Signed generic-watchOS build, strict signature and deployment metadata, frozen source hashes | Final build passed |
| Actual installation | Original verified physical Watch only, installed-app metadata query | Build 14 installed and independently confirmed at 23:53 UTC |
| Physical continuous readings after this fix | Actual Watch snapshots with advancing real observation times after installation | Not yet accepted |
| Phone-off operation | Physical Watch on miner Wi-Fi with phone unavailable | Not tested |

The intermediate busy-geometry diagnostic retained the same failure and later timed out during result-bundle finalization. It is not counted as a successful test. The complete original 11/12 result bundle is preserved separately.

## Physical diagnostics and data preservation

A read-only crash-index query at 23:31 UTC succeeded. No Hash Fleet or Jetsam crash report was present in the exposed five-file index. A 23:33 UTC process read still found the original installed Watch process. These observations do not establish that no crash ever occurred and do not establish a hardware-specific failure cause. They are consistent with an app becoming inactive or backgrounded, but that causal interpretation remains an inference.

The 23:33 UTC lock-state query reported passcode required. No security, pairing or radio setting was changed and no passcode was entered or bypassed.

A successful owner-private preinstall cache backup at 23:42 UTC contains four miners and four readings dated 23:31:25-23:31:27 UTC. That is materially different from the zero-entry cache copied at 22:56 UTC in the earlier receipt. It does not prove how those entries were added, that they were still current at backup time, or that recurring post-fix readings work. No test data or miner addresses were injected into the physical Watch.

The Watch-only update succeeded at 23:53 UTC and an independent installed-app query confirmed version 0.1.0, build 14. A normal production launch immediately afterward was denied with `Locked` and `Can't launch when device is locked, passcode locked or blocked`. No fixture arguments or forced termination were used. The new build's physical foreground, wrist-down and repeated-refresh behavior is therefore not accepted. No further launch/unlock bypass was attempted. A successful postinstall cache read at 23:54 UTC independently confirmed that all four saved miner identities are identical to the preinstall backup and four cached readings remain. Those older timestamps are not presented as post-fix network activity.

Final controlled Refresh geometry was identical before and during the fetch: 40 mm text 58 by 19.5 points and button 158 by 44, 44 mm text approximately 60.980 by 20.493 and button 180 by 47. Both same-frame assertions passed, including the after-fetch check. Busy and completed screenshots were inspected, as were genuine advancing Updated timestamps.

## Fleet safety and platform limits

The canonical fleet operations playbook was read before work. Read-only preflight included all four ASIC info/log GET pairs and the documented M1 SSH/process/LaunchAgent/API checks. The 23:50 UTC follow-up again returned HTTP 200 for all eight ASIC GETs and completed the mining-Mac SSH reads. Its loopback XMRig summary API refused the connection, so fresh M1 hashrate, shares and paused state are unavailable and are not inferred from process presence.

No ASIC POST/PATCH, reboot, self-test, OTA, tuning, voltage, fan, pool, wiring, lockout or recovery-policy change occurred. No mining-Mac service was changed. The iPhone app was not replaced and no device was erased, unpaired or reset. Existing unrelated repository changes were excluded from these commits. Final comparison confirmed the tracked unrelated diffs are unchanged from this repair's baseline.

The app does not disable normal Watch screen sleep or request an unrelated workout, audio, location or extended-runtime entitlement. watchOS may suspend a genuinely backgrounded app. Continuous ten-second monitoring while suspended or after explicit dismissal is not promised. Supported foreground/frontmost work and a prompt return refresh are distinct from a background monitoring service.

Primary platform references read November 3: Apple, Handling Common State Transitions, and TN3135 Low-level networking on watchOS. Discovery continues to use high-level read-only HTTP, not unsupported socket/Bonjour networking. Simulator success is not a substitute for physical and phone-unavailable tests.

## Private evidence

Owner-private root: `~/.jcode/scratch/hashfleet-watch-lifecycle-20261103T2329/`.

- `core-after-layout.log`, `final-source.sha256`, `final-signed-executable.sha256`
- `sim-final-build.log`, `device-final-build.log`
- `Live-Continuous-44mm.xcresult`, its nine attachments and `live-summary.json`
- `Fixture-Lifecycle-40mm.xcresult` preserves the initial layout failure
- `refresh-geometry-40mm.log` preserves the repeated geometry observation and diagnostic timeout
- `Final-Live-And-Refresh-44mm.xcresult`, `Final-Fixture-40mm.xcresult` are the final acceptance runs
- Original-device metadata, process/lock/crash-index receipts, preinstall backup and raw fleet reads remain private

The optional automatic audit route failed before producing a review. The bounded layout worker returned no patch and was stopped before the root edited that file. Neither attempt is counted as independent approval or a general provider-readiness judgment.
