# Phone tuner and ASIC chart changes, October 29, 2026

## Additional Easy tuner validation, 08:39 UTC

Further validation found **no production defect** in `MinerTuningControlMode`, `MinerTuningEasyControls`, `MinerTuningEasyField` or the Easy/Advanced integration in `MinerTuningSessionView`. Their exact pre-validation worktree bytes, including the existing unstaged snapshot-access changes, were preserved. This follow-up adds tests, not another tuning implementation or hardware operation.

Six added Easy unit/render test definitions bring that suite to **15 definitions**. They cover stable mode tags/labels, malformed reference arrays, exact adjacent-representable frequency round-trips, voltage-only drafts surviving telemetry, absent firmware choices for both fields and device-limit badge priority. The new installed voltage workflow rejects a fractional voltage without rounding, corrects it, switches to Advanced and uses the existing +25 mV control, switches back, selects the native miner-value dropdown item, checks exact voltage-only JSON and the Demo write lock, then restores the draft. The original frequency workflow and every original UI acceptance method remain unchanged. The native Select All/exact-input helper is shared by both fields without removing its assertions.

Closed follow-up receipts under `/Users/USER/.jcode/scratch/hashfleet-easy-validation-20261029-0821/`:

| Receipt | Observed result |
| --- | --- |
| `unit-final.xcresult` | **107/107 definitions in six suites**, zero failures/skips/expected failures. Includes Easy controls, tuning payloads, draft boundaries, apply coverage, operation authorization and miner safety. The 21 parameterized definitions account for 152 parameterized runs, not 152 extra definitions. |
| `native-regression.xcresult` | **112/112 definitions in 23 suites**, zero failures/skips/expected failures, with complete strict concurrency. Its 16 existing offscreen chart-test Environment warnings match the prior native receipt and remain uncorrected and visible. |
| `ui-repeat-final.xcresult` | **2/2 installed phone test definitions, each passed twice**, four successful executions with zero failures/skips/expected failures. Covers the original frequency flow and new voltage flow on the isolated iOS 27 simulator. |
| `verification-first.log` | **41/41 read-only checks passed** for actual result trees/repetitions, new regressions, source preservation, original UI-method preservation, project registration, unchanged unrelated tracked patches and worktree/index `git diff --check`. |

Eight final phone screenshots were exported to `ui-final-attachments/`. Easy controls, Advanced shared-draft state and the exact voltage-only review/Demo lock were visually inspected. These are simulator pixels, not physical-phone acceptance.

The initial `ui-repeat.xcresult` is intentionally retained as **failed**. Both frequency repetitions passed, while both new voltage repetitions reached Advanced and failed on the new test's guessed `tuningSession.voltage.plus25` selector. The actual source and exported accessibility hierarchy expose `tuningSession.voltage.plusCoarse`, labeled `Increase Core voltage by 25 mV`. Only the new selector was corrected, and an exact label assertion was added. No production identifier or original acceptance assertion was changed. All 107 unit definitions and both repeated phone workflows were rerun after that last test-code edit.

An optional reviewer route failed before inspecting files. A replacement read-only report needed corrections to its count and hardware-enforcement claims, so it is not counted as independent runtime acceptance. The closed Xcode receipts and coordinator's source/result/pixel checks are the evidence above.

No real miner or mining Mac was queried or changed, and no physical phone, production preference domain, recovery policy, service, credential or deployment was modified. The 601a software voltage gate does not certify physical power wiring, and Swift cannot enforce the 602's external **5 V only** supply requirement. Actual firmware menus and real-device operation remain outside this isolated follow-up.

## Requested behavior

- The tuner opens in **Easy** mode with a common-values menu and custom numeric input. Frequency and core voltage share the existing setpoint state with **Advanced**, which retains the car-style gauges, step controls and rim gestures.
- Choices come from the firmware's reported references plus the exact configured and staged values. They are not advertised as recommended or safe presets. When firmware reports no choices, the UI says so instead of inventing profiles.
- Custom input uses the existing strict frequency/integer-voltage parsers. An error leaves the draft unchanged and the correction action usable. Missing current telemetry remains **Not reported**, not a zero setpoint.
- Both modes retain the same changed-fields-only review payload, risk acknowledgement, freshness checks, hardware policy, Demo lock and final operation authorization. Selecting a menu item, entering a value or changing modes performs no write.
- Feature tour is removed only from the dashboard's right-hand preferences menu. The existing onboarding, Fleet tools and App settings tour routes remain.
- The actual **ASIC hashrate** domain graph is larger, has plot/grid context, draws the first observed reading as a marker and insets constant/zero readings. The nominal reference stays dashed and visually distinct. Sample counts explain when the trend is still building.
- This is observed screen-local history, not invented or backfilled history. Existing timestamp, stale/cache exclusion, session/topology reset and capacity policies are unchanged.

## Requirement-to-check map

| Requirement | Check |
| --- | --- |
| Common and custom values | Production-policy tests cover exact options, duplicates, malformed input and wire endpoints. Installed UI exercises the native dropdown and corrected custom input. |
| Shared Easy/Advanced state | Installed UI stages a fractional frequency in Easy, changes it with Advanced +10, switches back and checks the exact review payload. |
| Advanced controls retained | Existing installed cockpit workflows explicitly select Advanced. Original step, restore, gesture, payload and Demo-lock assertions are retained. |
| Unknown remains unknown | Mounted Easy controls with missing current telemetry must show Not reported and no fabricated zero draft. |
| Right-menu tour removal | Installed UI opens the real menu, checks Settings/About remain and tour is absent, then navigates to Settings. |
| Tour remains available elsewhere | The existing skip/reopen/reset acceptance uses the public Fleet tools/onboarding route, not the removed menu item. |
| Visible ASIC series | Real mounted-pixel tests check singleton, constant, zero, varying, invalid and very large observations. Existing 16-domain render tests remain unchanged, including narrow/wide and accessibility layout. Installed demo shows the real ASIC component. |
| No hidden write bypass | Existing production tuning payload tests plus exact installed review and disabled Demo Apply checks. Native operation-authorization tests also exercise revoked permission and board-policy boundaries using isolated fixtures. |

## Verification record

Final closed acceptance: **79 mobile unit/render tests, 112 native tests and 12 installed phone UI tests passed, with zero failures or skips**. These are the selected requirement-aligned suites, not a claim that every test in the repository was run. Results were recorded after the last source edit. Build and runtime artifacts are under `/Users/USER/.jcode/scratch/hashfleet-ui-20261029-0547/`.

- `asic-red2.xcresult`: original drawing reproduced missing singleton data and invisible/edge-bound constant-series cases. The first attempted red run did not compile because new tuner sources were not registered yet, so it is not counted as runtime evidence.
- `ui-green1.xcresult`: an intermediate attempt failed. Captured pixels exposed an isolated tiny-window safe-area fixture error, and the unchanged accessibility test caught an overly tall 16-domain layout. The plot fixture now explicitly excludes screen safe areas. Production wide tiles use horizontal header/reference arrangements when they fit and keep stacked phone layouts. No original chart/history/render-harness assertions were changed.
- `unit-green2.xcresult`: 78 mobile test definitions across five suites passed before the additional missing-telemetry render case.
- `native-green1.xcresult`: 112 native test definitions across 23 suites passed before the final Easy missing-value adjustment. Shared views compiled under complete strict concurrency.
- `ui-acceptance1.xcresult`: installed ASIC-chart and right-menu-removal tests passed. Tuner entry checks failed before reaching the tuner. The recording and AX export proved that the native Controls menu was visible, but its Section action lacked the SwiftUI identifier on this iOS 27 runtime. Test navigation now matches that same exact public button label as well as the identifier. No hidden route or retry tap was added. An unsuccessful explicit-Label production hypothesis was reverted.
- `ui-entry2.xcresult`: retained tour skip/reopen/reset passed after bounding Fleet tools' accessibility children and using safe scrolling. Tuner entry still exposed the native menu identifier issue, which was preserved and addressed in the navigation selector only.
- `ui-easy3.xcresult`: both workflows reached the actual tuner. The newly added section identifiers propagated onto every child, hiding the original value/step identifiers. Explicit `.accessibilityElement(children: .contain)` boundaries now preserve individually accessible controls. The original selectors and assertions were retained.
- `ui-easy4.xcresult`: the original Advanced numbered-rail/dial/payload/Demo-lock workflow passed. The Easy workflow then caught an actual 34.33-point common-values button despite an outer 44-point frame. The Easy dropdown now uses a native selection-bound Picker inside a Menu whose full-width label owns the minimum 44-point content shape. The minimum-target assertion was not reduced or removed.
- `ui-easy5.xcresult`: real dropdown sizing, invalid-input correction, fractional Easy/Advanced state and native miner-option selection passed. Review jump exposed a target nested inside an unrealized lazy TimelineView. Its single scroll ID now belongs to the direct TimelineView child. The exported hierarchy also showed the test's midpoint deletion had entered `612.52`, not the intended `612.5`, so the new test now uses native Select All and checks exact input before staging.
- `ui-easy6.xcresult`: an attempted trailing-edge caret fix still left a digit, caught by the new exact-entry assertion. `ui-easy7.xcresult`: native Select All correctly cleared the field, but UIKit exposed its `Enter MHz` placeholder as the empty accessibility value. `ui-easy8.xcresult` then proved that the simulator's keyboard Select All shortcut was not reliably delivered. The helper now uses the actual long-press **Select All** editing-menu action, explicitly accepts empty or that exact placeholder before typing, and still requires the exact entered number. These are retained failed runs, not production parser failures.
- `ui-easy9.xcresult`: the complete installed Easy workflow passed, including both real minimum-44-point targets, invalid-input correction, exact fractional input, Advanced increment and shared-state return, native miner-value dropdown selection, direct review jump, exact frequency-only JSON and the disabled Demo Apply action. Exported Easy, Advanced and review pixels were inspected.
- `unit-final.xcresult`: **79/79 mobile test definitions in five suites passed**, zero failures or skips, after the last production edit. This includes the unchanged original chart/history/render-harness acceptance, missing-value render, strict parser/boundary cases and observed-series pixel checks. The 24 parameterized definitions account for 157 parameterized runs, not 157 extra definitions.
- `native-final2.xcresult`: **112/112 native test definitions in 23 suites passed**, zero failures or skips, after the last production edit. The real shared views rebuilt with complete strict concurrency. Existing offscreen native-chart environment warnings remain in the receipt, so this does not establish a mounted parent accessibility environment or physical native interaction.
- `ui-final.log`: the combined 12-test UI command reached the runner's hard 600-second limit. Eight tests had individually passed, with no assertion failure, before the ninth was interrupted. The incomplete run is preserved, not reported as a successful suite. The unchanged acceptance tests were subsequently run in two smaller commands, each with a finalized result bundle.
- `ui-final-split-a.xcresult`: **6/6 installed phone UI tests passed**, zero failures or skips. This covers exact custom input and correction, native dropdown selection, shared Easy/Advanced draft and exact review, the expanded ASIC chart's first observed marker, right-menu cleanup, retained tour skip/reopen/reset and collapsed miner-detail entry. The final Easy, exact JSON/Demo lock, ASIC chart and menu screenshots were exported and inspected.
- `ui-final-split-b.xcresult`: **6/6 retained Advanced cockpit UI tests passed**, zero failures or skips. Checks cover numbered rails, both dial gestures/step controls and restore without writes, combined staged state, largest text with review still reachable, missing voltage without fabricated payload fields, Controls menu survival after a real fixture HTTP refresh, and one confirmed localhost PATCH plus honest readback-mismatch reporting. That PATCH went only to the isolated test server, never a real miner.

A separate read-only final verifier checks all four closed result summaries, implementation commit scope, original acceptance hashes, byte-identical unrelated patches, all original untracked hashes and the four deliberately unstaged snapshot-access changes. No production code changed during or after these final runs.

Apple's `AccessibilityChildBehavior.contain` documentation describes preserving child accessibility elements inside a group: https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/contain . This is the production containment behavior used above, not a hidden UI-testing route. Easy editing and mode selection are also disabled during confirmation/apply, matching the existing Advanced editing lock. The shared header now gives Easy-specific instructions while retaining the exact Advanced dial help.

## Independent source review

A fresh configured-auto reviewer completed a bounded read-only source review. The actual route was native Claude Opus 4.8. It performed no edits, builds, runtime tests, device interaction or miner requests. The coordinator independently checked its findings rather than treating the review as runtime certification.

The review found no blocking code defect and confirmed the shared draft, strict parsing, 601a voltage ceiling, final fresh authorization, Demo lock, non-overflowing plot scaling and singleton marker. Its two low-severity observations are intentional presentation boundaries: accessibility exposes a combined **domain row**, not a separate independently targetable decorative graph, and charts remain inside the existing user-expandable ASIC disclosure. This change fixes the plot after expansion, not the disclosure's default state. Its stated positive-tour-coverage gap is covered by the separate retained skip/reopen/reset installed test, which already passed and remains in final acceptance.

## Preservation and limits

Implementation commit: `d12cd75` (`Add Easy tuning and visible ASIC charts on phones`), scoped to 19 implementation, project and acceptance-test files. The separate widget/Live Activity research is in commit `2fd3b2c`.

The repository already contained unrelated layout, runtime, dashboard-history, CLI, website and skill changes. The initial binary diff, untracked-file hashes and overlapping tuner baseline were preserved before edits. The 73 unrelated tracked-file patch sections remain byte-identical and all 24 original untracked-file hashes still match. Four pre-existing snapshot-access changes in `MinerTuningSessionView.swift` remain unstaged and are deliberately excluded from the scoped commit. Original chart/history/render-harness acceptance files and both unrelated dashboard history files retain their recorded baseline hashes.

A worker authentication failure and a provider HTTP error occurred before implementation. A subsequent worker candidate was reviewed and rejected in part, with its view, parsing policy and tests corrected by the coordinator. Its original files remain in the scratch evidence directory. Worker output is not counted as independent verification, and no routing/account configuration was changed.

These are local builds, mounted renders and installed simulator interactions using Demo or isolated fixture data. No real miner was queried, restarted, retuned or flashed. No physical-phone installation/reset, data migration, backend/APNs activation, new credential, deployment or paid build was performed. Physical-phone rendering, actual firmware choices and live observation cadence still require acceptance on the user's device.

For the separate widget/Live Activity freshness investigation and the optional Uber-style collector/relay architecture, see `WIDGET-LIVE-UPDATES-2026-10-29.md`. This UI work does not implement continuous background monitoring.
