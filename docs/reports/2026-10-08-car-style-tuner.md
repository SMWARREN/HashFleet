# Car-style tuner delivery evidence

Date: October 8, 2026. All times below are UTC.

## Delivered scope and boundaries

The phone-first tuning workspace now has car-style frequency and core-voltage dials, independent staged changes, numbered shared-board ASIC context, exact JSON review, explicit confirmation, and fresh post-write readback. The final application was signed and installed on the connected iPhone.

This is not an all-green final quality-gate claim. The production acceptance run passed all 865 logical tests. The later test-file packaging compiled and passed all 857 unit tests, but its four UI replays were blocked at startup by recurring simulator accessibility infrastructure errors. Final Sonar publication succeeded with zero unresolved issues, but its coverage condition failed. Physical iPhone launch was blocked by the locked device.

No physical mining operation was authorized or performed for this tuner work. All acceptance writes were confined to a fixture bound exclusively to `127.0.0.1`. No real tuning, restart, OTA, self-test, fan/pool, wiring, Mac service, recovery-policy or lockout change was issued. Screenshot setpoints are demo or fixture values, not live fleet telemetry or recommended physical settings.

## Source commits

- `5557d66`: independent dirty-field staging and preservation of untouched configured settings.
- `60ce86c`: one Controls Menu and NavigationLink owned by `AnyLayout`, with layout selected using card width and Dynamic Type. The old content-fit alternatives duplicated the presenting Menu, allowing telemetry/error content changes to change presentation ownership.
- `69f2d72`: tachometer artwork, configured/measured markers, independent step controls, board-specific restriction and post-PATCH one-shot verification.
- `96c78db`: accessibility-only vertical staged summaries, keeping FREQ/VCORE headings intact and baseline captions readable.
- `be64c7d`: finalized loopback acceptance coverage, strict first-tap menu regression, diagnostic wrapping, local variable rename and extraction of unchanged dashboard control tests/helpers into a registered test extension.

Application and unit-test source is unchanged between `96c78db` and `be64c7d`. The project change in the latter commit registers only `DashboardCardInteractionUITests+Controls.swift` in the UI-test target. No assertions, retry limits or quality thresholds were weakened during the packaging cleanup.

## Requirement-to-observation map

| Requirement | Observed check |
| --- | --- |
| Car-style instruments | Actual simulator renders show amber needles, calibrated ticks, configured-value dashed markers, independent steps, staged deltas and numbered board context. |
| Independent frequency and voltage | Real-app tests review frequency-only, voltage-only and combined JSON. Untouched keys remain absent. Unit tests cover telemetry drift, frozen dirty baselines, invalid values, defaults and Restore. |
| Real rim dragging | The integrated run staged frequency from 525 to 675 MHz using actual touch coordinates. Dial frame `(32, 130, 338, 338)`, start `(201, 163.8)`, end `(336.2, 299)`. The gesture itself sent no write. |
| Restore and demo write lock | Real-app workflows restore clean values and keep Apply disabled in demo mode even when both dials are staged. |
| Persistent acknowledgement | The detail-route workflow remembers the per-miner risk acknowledgement while reopening a clean session without silently staging previously configured settings. |
| Exactly one confirmed write | Adjusting, reviewing and cancelling send no PATCH. Explicit confirmation sends exactly one loopback PATCH with frequency 510 and coreVoltage 1175. A subsequent Info GET starts after the PATCH. |
| Honest fresh verification | Matching readback reports Verified and clears the draft. Mismatched readback retains the draft and reports that values do not match, without claiming Tuning applied. Verification does not reuse a refresh begun before the write. |
| Board-specific restriction | Unit tests cover the known Gamma 601a 1150 mV ceiling, missing/conflicting identity and address normalization. Wire-format bounds and firmware references are not physical safety certification. |
| Partial telemetry | Missing voltage leaves frequency usable, voltage disabled and coreVoltage absent from the payload. |
| Stable Controls entry | Strict first-tap regression passed in 29.886 seconds. It observed both a newer HTTP Info request and a displayed hashrate change while the same menu remained hittable, then opened the tuner with zero writes. No repeated menu tap or test-only entry bypass is used in this regression. Loopback write tests separately use the public detail quick link. |
| Largest Dynamic Type | Both dials' step controls, review and Restore passed at Accessibility XXXL. The settled final screenshot visibly contains intact FREQ/VCORE headings, 535 MHz with +10 from 525, and 1155 mV with +5 from 1150. The compact in-dial delta caption may truncate at this size, but the full external staged summary is readable. |
| Lint and project packaging | Strict SwiftLint found zero violations in all four changed UI-test/fixture files. Project plist validation and Git whitespace checks passed. The extension compiled and both moved test selectors were discovered by XCTest. Four scanner-script regression tests also passed. |
| iPhone installation | Signed DebugNoAppPush build and installation of `app.hashfleet` succeeded at 06:36. Automatic launch was denied by SBMainWorkspace with Locked. No lock-screen bypass was attempted. On-phone launch and manual interaction remain unverified. |

## Passing integrated acceptance on the final application source

`cockpit-integrated-recovered-final.xcresult` completed at 06:58:04 with xcodebuild exit 0 and TEST SUCCEEDED. Independent xcresult inspection found:

- **852 Swift Testing tests in 76 suites**, plus **5 XCTest unit tests**.
- **8 real-app UI workflows** passed.
- **865 logical tests passed**, zero failed, zero skipped and no runtime warnings.
- The device summary contains 1,149 parameter-expanded executions. These are not 1,149 distinct tests. There were 59 dynamic-parameter tests with 343 runs.

| UI workflow | Duration, seconds |
| --- | ---: |
| Unified workspace, combined staging and remembered acknowledgement | 50.045 |
| One confirmed loopback write, matching and mismatched readback | 78.232 |
| First-tap Controls menu survives changed HTTP refresh | 29.886 |
| Largest text, both dials, staged summary, review and Restore | 68.673 |
| Missing voltage preserves frequency-only payload | 23.584 |
| Independent/combined staging, Restore and actual rim drag | 83.527 |
| Controls entry and numbered ASIC rails | 38.351 |
| Collapsed-card entry and demo write lock | 44.708 |

The exact invocation is retained at the start of `cockpit-integrated-recovered-final.log`. It used `HashFleetNoAppPush`, `DebugNoAppPush`, the owned iPhone 17 Pro simulator `5AE0257A-7733-4411-9611-25C576DA2B7E`, disabled automatic package resolution/updates, disabled parallel testing, and selected all `HashFleetTests` plus these eight workflows. Both app navigation and loopback HTTP journals were exercised, not just test-double state.

## Post-packaging validation and retained failures

The `be64c7d` test organization compiled. `cockpit-packaging-final.xcresult`, completed at 07:15:56, contains **857 unit passes and four UI failures**, zero skips. All four failed with `Failed to get matching snapshots: Error getting main window kAXErrorAPIDisabled` before useful navigation:

1. `testCockpitControlsMenuSurvivesHTTPRefreshAndOpensTuner`
2. `testCockpitLargestTextKeepsBothDialsAndReviewReachable`
3. `testCollapsedCardKeepsMissingHashrateAndReportedFaultVisible`
4. `testLargestTextKeepsExpansionAndSettingsReachable`

This is a failed replay, not a pass. It does not replace or invalidate the earlier passing production-source observations, but the final helper packaging lacks a successful post-extraction UI replay. No further simulator restart/retry was performed after recurrence.

Earlier evidence remains intact:

- `cockpit-stable-layout-final`: first 865/865 all-green run before the final accessibility reflow.
- `cockpit-accessible-summary-final`: all units and 7/8 UI passed. The largest-text driver repeatedly touched a dead dial-adjacent region. A test-only driver fix added 32-point artwork clearance and another safe start when the frame did not move.
- `cockpit-accessible-summary-driver`: focused largest-text pass with a settled, visually inspected readable summary.
- `cockpit-integrated-verified-final`: all units passed, eight UI workflows failed at launch with the same AX infrastructure error.
- One bounded non-destructive shutdown/boot/bootstatus of only the owned simulator recovered that earlier failure. The unchanged integrated run then passed all eight workflows. No erase, permission/security change or physical-device restart occurred.
- Earlier menu disappearance, lazy-element diagnostics, scrolling overshoot and initialization failures are retained in their original logs and bundles. Production menu ownership was repaired rather than hidden by repeated taps.

## Final Sonar result

Final committed-source analysis was processed at **07:20:37**:

- Compute task: `31b776e1-7289-4a61-9fc2-32f927f43e00`, SUCCESS.
- Analysis: `f432f1bd-fb45-4432-a06a-99560c766ec2`.
- **Zero unresolved issues**, zero reported bugs, code smells, vulnerabilities and security hotspots.
- **Quality gate: ERROR**. New-code coverage **16.4%**, below the unchanged **80%** requirement.
- New duplication **0.0%** and new violations **0**, both passing their gate conditions.
- Overall reported line coverage **37.9%**, duplication **0.0%**.
- Imported test failures **4**, matching the retained post-packaging simulator failures. Sonar's imported test metric is 1,132, not the canonical xcresult logical-test count. Use xcresult for executed unit/workflow counts.

The scan imported `cockpit-packaging-final.xcresult`, which matches the final test-file line structure. The first attempted scan used the earlier all-green bundle and failed before publication because extracted test source no longer matched its coverage line numbers (`Line 453 is out of range ... lines: 452`). Its log remains `sonar-final.log`; the successful publication log is `sonar-final-packaging.log`.

No gate limit, source/test exclusion or coverage report was altered to turn this failure into a pass. No server/container data was removed or reset. This Community Edition Swift setup imports SwiftLint issues and Xcode coverage through the sonar-apple plugin. Zero reported issues is not an exhaustive Swift/security audit, 100% source coverage, or proof that the coverage gate passed.

## Evidence locations and remaining constraints

Owner-local artifacts are under `/Users/USER/.jcode/scratch/tuner-resume-20261008/`:

- `cockpit-integrated-recovered-final.{log,xcresult}` and its attachments manifest with 19 PNGs.
- Settled largest-text screenshot: `cockpit-integrated-recovered-final-attachments/87FFE104-5C2D-4228-954A-BC1A27F1AB39.png`.
- Normal pre-drag dial: `cockpit-integrated-recovered-final-attachments/C0A54B63-FF77-45E8-AC98-65A743124B95.png`.
- Actual coordinate attachment: `cockpit-integrated-recovered-final-attachments/A33B38EF-BC42-4851-A068-D7C50B865A90.txt`.
- `cockpit-packaging-final.{log,xcresult}` with all units passing and four AX-blocked UI failures.
- `sonar-final.log`, `sonar-final-packaging.log`, `sonar-final-receipt.json` and the published `.scannerwork/report-task.txt`.
- `phone-build-accessible-summary.log`, `phone-install-accessible-summary.log`, `phone-launch-accessible-summary.log` for signed build, successful installation and exact Locked denial.

The app is installed. The user must unlock the iPhone and open HashFleet for physical launch. A successful final helper-packaging UI replay and the 80% new-code coverage gate remain unverified/unmet respectively. No claim is made that these constraints have been resolved.

## Acceptance closure audit, 07:28-07:36 UTC

The original user requirements were recovered from the current session, rather than inferred from aggregate counts: the October 7, 09:18 request for one tuning workspace without difficult numeric inputs and all unit tests passing, the October 8, 03:30 request for independent core/frequency adjustments with car-style visuals using Astra or Opus, and the October 7, 07:49 request for Sonar status. The earlier report that the tuner crashed on the physical phone is retained as a physical regression requirement, not declared fixed by simulator tests.

A fresh filtered query of the **actual connected iPhone** at 07:28 returned **Hash Fleet, `app.hashfleet`, version 0.1.0, build 7**, matching the signed local package identity. Deep strict signature verification passed and both `HashFleetWidgets.appex` and `PushProvider.appex` were present. A real foreground-launch attempt finished at **07:28:15**, denied by **SBMainWorkspace Locked**. This exercises the real delivery boundary. Physical tuner navigation, gestures and the original phone-crash regression remain externally blocked, not replaced by a fixture or simulator claim. No reinstall, app termination, device restart, security change or miner write was performed for this audit.

The individual native-app workflow nodes were re-read from the real xcresult tree. The following maps changed public outputs to their actual observed acceptance paths:

| Requirement or changed output | Actual app workflow and observation |
| --- | --- |
| Independent frequency-only and voltage-only edits | `testCockpitStagesEachDialTogetherAndRestoresWithoutWriting` passed. A frequency step reviews only `frequency`; a voltage step reviews only `coreVoltage`; combined staging contains both keys. |
| Unified tuner, no difficult numeric fields, no duplicated mode/Send path | `testUnifiedTuningWorkspaceShowsLiveContextStagesCombinedChangesAndRemembersAcknowledgment` passed through the public miner-detail quick link. Numeric frequency, voltage and temperature inputs, the settings mode selector, raw JSON input and endpoint Send are absent. Configured/Measured/ASIC errors and the one reviewed Apply are present. |
| Responsive car-style dial | The same staging workflow performed a real rim gesture, with the log recording **525 -> 675 MHz**, not merely changing a test model or binding. |
| Restore and persistent risk acknowledgement | Staging and unified workflows passed Restore, back navigation and reopening. Clean values have no payload; the risk acknowledgement remains on without silently staging old configured settings. |
| Confirmation, exact production HTTP payload and truthful verification | `testCockpitConfirmsOneLoopbackWriteAndReportsReadbackMismatchHonestly` passed both branches. Native Cancel writes nothing; native Apply writes exactly once; a subsequent Info GET yields either Verified/cleared draft or mismatch/retained draft. Only the external server is loopback, the app navigation and production networking/parser are real. This is not a physical miner write test. |
| Missing telemetry | `testCockpitMissingVoltageKeepsFrequencyUsableWithoutInventingPayloadFields` passed. Frequency is enabled, voltage disabled, JSON contains frequency 510 without an invented voltage, and no PATCH occurs. |
| Stable public Controls Menu | `testCockpitControlsMenuSurvivesHTTPRefreshAndOpensTuner` passed the first tap and a newer Info GET with displayed 1.20 while the same menu stayed hittable. No repeated-tap workaround is used. |
| Three public entry routes and numbered context | Unified, `testTuningSessionOpensFromControlsMenuAndShowsNumberedRails`, and `testCollapsedTuningCardOpensUnifiedSessionAndDemoWriteLock` each passed. Detail, dashboard Controls and collapsed-card controls open the same tuner; ASIC 1/2 navigation and voltage/temperature context are reachable. |
| Largest text and staged comparison readability | `testCockpitLargestTextKeepsBothDialsAndReviewReachable` passed both 44-point steps, summary, review and Restore. The retained settled native screenshot shows both full baseline comparisons, not only an accessibility label. |
| Demo and 601a boundaries | Actual demo Apply stays disabled. The identity-bound `tuningPolicyIsIdentityBoundAndCannotBeRemovedByConflictingFirmwareMetadata` unit contract passed. This unit contract does not certify physical power transients or hardware tuning. |
| Requested worker | Actual session metadata identifies the gauge implementer `monkey` as `claude-opus-5-5`; its implementation handoff is message 45 at 03:47:18. Astra `camel` executed real-app acceptance. Availability alone was not used as evidence of delegation. |
| All units passing | The real `HashFleetTests` target passed 852 Swift Testing plus 5 XCTest tests both before and after the helper extraction. This satisfies the executed-unit pass-rate request, not a source-coverage target. |
| Current Sonar publication and existing gate | The exact real server task and analysis were queried again at 07:30. Task SUCCESS and zero unresolved issues were unchanged; coverage gate ERROR at 16.4% versus 80% and four imported UI failures remain recorded. |

**Concrete observed improvements, with limits:** the earlier `cockpit-focused-final.log` records a presented menu disappearing before selection at line 434; the final first-tap/changed-HTTP regression stays usable and opens the tuner. The earlier largest-text two-column screenshot `accessibility-screenshots/870D647B-0875-4784-A079-A22D3905D9A5.png` splits FREQ/VCORE and truncates baseline comparisons; final screenshot `87FFE104-5C2D-4228-954A-BC1A27F1AB39.png` shows intact headings and full comparisons in the external summary. The compact in-dial caption still truncates at this size. The final Sonar scan now publishes an exact-source receipt instead of failing with stale coverage line numbers, but **its coverage quality is not proved better and its gate has not passed**. Physical-phone crash/gesture behavior cannot be called improved while foreground launch is locked.

A checksum-backed ledger, `requirement-outcomes.json`, maps **19 acceptance criteria: 16 observed passes, two externally blocked paths and one unmet criterion**, with `overall_fully_accepted: false`. It is a recount of real xcresult application nodes, the actual phone query/launch and the actual server receipt, **not a replacement test harness or 19 new test executions**. `audit_requirement_outcomes.py` rechecks the named workflow results, exact assertions, unchanged application source, signed package identity, blocked launch and unchanged coverage failure. The audit ran successfully at 07:36, preserving all original failures and evidence fingerprints. Owner-local audit artifacts also include `phone-delivery-audit-apps.{json,log}`, `phone-delivery-audit-launch.{json,log}`, `integrated-test-tree.json` and `sonar-audit-recheck.log`.
