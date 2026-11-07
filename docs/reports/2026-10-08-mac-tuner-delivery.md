# Mac tuner delivery and current Sonar status

October 8, 2026. Times are UTC.

**Later observations:** this report preserves the 10:53 delivery state, not the latest Sonar or Mac acceptance result. Analysis processed at **12:15:32 UTC** passed the unchanged Sonar gate with **87.0% new-code coverage**, **55.6% overall** and **zero unresolved issues**. See `2026-10-08-unit-coverage-swarm.md` and its exact receipt. Real Mac public navigation, both-dial rendering, both ASIC rails, guarded review and Back were subsequently exercised at **12:43-12:46 UTC**, as mapped in `2026-10-08-tuner-real-mac-acceptance.md`. That supersedes the earlier Mac-window navigation limitation for those read-only paths. The physical phone remains passcode-required and its tuner UI acceptance is not verified.

## Request and observed result

The user asked whether the car-style tuner also reached the Mac app and requested current Sonar findings, noting that the Apple device was connected.

The full `/Applications/Hash Fleet.app` was still the older October 6 package at the start of this check. Its binary lacked the new voltage-value, staged-summary and Restore identifiers. It is the packaged iOS app running Designed for iPad on Mac and shares the `App` source with the phone. `/Applications/Hash Fleet Menu Bar.app` is a separate native target and does not include `MinerTuningSessionView` or `MinerTuningGauges`.

## Mac update performed

- Built the current source using the real `HashFleetNoAppPush` scheme, `ReleaseNoAppPush`, destination `platform=macOS,arch=arm64,variant=Designed for iPad`. Xcode reported **BUILD SUCCEEDED** at 10:34.
- Packaged the freshly built app and release CLI with the project's existing Mac packager into a new scratch directory. Packaging and CLI `--help` passed.
- Staged the new package in `/Applications`, validated its deep strict signature, and gracefully closed only the old full app.
- Replaced the installed app by moving the original intact bundle to `/Users/USER/.jcode/scratch/tuner-resume-20261008/mac-delivery/rollback/Hash Fleet.app`. No app container/preferences/history directory was deleted or replaced. The standalone menu-bar application and its process were not changed.
- The installed binary is byte-identical to the newly built Mac binary. The installed package contains the new `tuningSession.voltageValue`, `tuningSession.deltaStrip` and `tuningSession.reset` identifiers.
- The new process launched through the dedicated macOS app-control interface. Its running, system-translocated executable matches the installed new binary hash, so it is not the old cached executable.

| Executable observation | SHA-256 |
| --- | --- |
| Original Mac executable, preserved in rollback bundle | `b856274400003fa32afa70e44eeab495137a34c84b6a0029783191f036307e6b` |
| Newly built, installed and running Mac executable | `b49732186e2698a47f87adfcea062485c1365595f32ea4bc03667ace53240a38` |

**Mac visual/interaction acceptance remains unverified.** The generic file opener was suppressed by the host environment. Dedicated app control launched the new process, but both the AX helper and an exact-PID System Events query reported no accessible app windows. A single standard reopen attempt timed out. This does not prove the tuner window is usable, nor does an AppleEvent timeout alone establish an app crash. No permission/security changes, force termination or mining-control clicks were attempted to bypass this constraint. The installed code and actual running image are verified, not the full end-user Mac tuner interaction.

## Connected iPhone

A real filtered device query at 10:28 found **Hash Fleet, `app.hashfleet`, version 0.1.0, build 7**. Actual foreground launch attempts at 10:28 and again at **10:53:41** were denied by SBMainWorkspace with **Locked**. The connection is working, but physical launch, tuner navigation and crash regression remain unverified while the phone is locked. No reinstall, device restart or lock-screen bypass was performed.

## Sonar, freshly queried at 10:53:30

The existing real Sonar server is UP. The latest completed analysis is `f432f1bd-fb45-4432-a06a-99560c766ec2`, recorded at **07:19:25** and processed at 07:20:37. It was queried again, not replaced by a new scan for this delivery operation. Application source is unchanged, only the Mac package was rebuilt and installed.

- **Unresolved issues: 0.** Reported bugs, code smells, vulnerabilities and security hotspots are zero.
- **Quality gate: ERROR**, solely on its shown new-code coverage condition: **16.4% versus the unchanged 80% requirement**.
- New violations **0** and new duplicated-lines density **0.0%**, both passing.
- Overall line coverage **37.9%**.
- **Four imported test failures** remain from the last post-helper-packaging UI replay, which failed at launch with `kAXErrorAPIDisabled`. These are not four unresolved Sonar source issues. The earlier final application-source run with 857 units and eight UI workflows passed remains retained separately.

No quality threshold, source exclusion, coverage report or Sonar server data was altered. Zero unresolved issues is not a passed coverage gate or proof of exhaustive Swift/security analysis.

## Evidence

Owner-local artifacts under `/Users/USER/.jcode/scratch/tuner-resume-20261008/`:

- `mac-build-current.log`, `mac-package-current.log`, `mac-cli-help-current.log`.
- `mac-before-after-binary-hashes.txt` and `mac-delivery/rollback/Hash Fleet.app`.
- `mac-delivery/hashfleet-mac/Hash Fleet.app`, `mac-delivery/Hash Fleet Mac.zip`, `mac-delivery/Hash Fleet.pkg`.
- `phone-current-1028-apps.{json,log}`, `phone-current-1028-launch.{json,log}`, `phone-current-1053-launch.{json,log}`.
- `sonar-current-1030-preserved.json`, `sonar-current-1053.{json,log}`.

No miner tuning, OTA, restart, self-test, fan/pool, power wiring, mining-Mac service or recovery-policy command was issued. This report is app-delivery and analysis evidence, not a fresh fleet-health report. Full Mac UI acceptance, locked-phone acceptance and the Sonar coverage threshold remain explicit limitations.
