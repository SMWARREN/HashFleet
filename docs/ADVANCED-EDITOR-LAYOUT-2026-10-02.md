# Advanced custom JSON editor layout diagnostic

Observation date: October 2, 2026. Source/UI commit: `2a50c5d`.

## Current scope

The minimal repository fix moves the existing Format/Done toolbar group from `.keyboard` to `.topBarTrailing`. Exact B/A/B controls, the strengthened actual-app regression, and complete native plus eight mapped UI acceptance validate the workaround on the tested simulator. The complete run finished at **15:31:47 UTC: 694 unique tests passed, zero failures and zero skips**, with **zero editor frame warnings**. One separate background-thread publishing warning remains, so this is not globally warning-free acceptance.

**The installed/frozen phone 0.1.0 build 3 does not contain this later fix.** No replacement phone build, installation, launch, physical-screen inspection, miner/M1 request, settings change, restart, OTA, self-test, recovery or wiring operation is part of this diagnostic. The fleet playbook remains the hardware safety reference, not telemetry.

## What changed, and what did not

The sole production delta in `App/Features/Miner/MinerCustomJSONView.swift:53` is:

```diff
- ToolbarItemGroup(placement: .keyboard) {
+ ToolbarItemGroup(placement: .topBarTrailing) {
```

The existing Spacer, Format and Done controls, focus state, multiline TextEditor with minimum height 220, Form/Section containers, title, formatting, validation, file import, request staging and confirmation policy are unchanged. No log suppression, networking change, payload merge, permission change or test-assertion weakening is retained.

Two existing UI files add checks to the same custom JSON case, rather than introducing a substitute app or a new test identity. The helper checks the actual navigation bar, hittable Format and Done actions before focus and after complete text entry, and finite positive editor geometry. It also captures screenshots. The case adds an explicit empty-write-journal assertion after layout and text entry. Its original exact raw-text replacement, formatting, staging, typed-review and cancellation assertions remain in place.

## Controlled hypothesis results

The original warning is `Invalid frame dimension (negative or non-finite)`, emitted on entry into the real Developer-only custom JSON editor before typing. The source inspection did not locate an arithmetic-derived frame, and the original issue metadata lacked a creating-workspace source location. These observations do not identify a SwiftUI internal root cause.

| Hypothesis or control | Actual observed result | Decision |
| --- | --- | --- |
| Earlier H1: minimum height changed to fixed height 220 | Two passing fresh-process repetitions, two frame warnings | Rejected and exactly reverted |
| Earlier H2: remove only the keyboard toolbar Spacer | Two passing fresh-process repetitions, two frame warnings | Rejected and exactly reverted |
| H3 candidate B: move the unchanged whole toolbar group to the top bar | Two passing fresh-process repetitions, zero runtime warnings and zero frame-warning log occurrences | Candidate supported |
| Exact restored A: original keyboard placement and unchanged test/helper | Two passing fresh-process repetitions, two frame warnings, one on each editor entry | Contemporaneous negative control reproduced the issue |
| Exact repeated B: same single production change and unchanged test/helper | Two passing fresh-process repetitions, zero runtime warnings and zero frame-warning log occurrences | Candidate reproduced |
| Strengthened actual-app layout regression | One passed case, zero failures/skips and zero runtime warnings | Targeted layout, staging and safety checks passed |
| Title/principal and Form/focus alternatives | Not executed after H3 met its controlled acceptance criteria | Deferred, not disproved |

The B/A/B sequence used the same actual app, simulator, test case, helper and two-repetition relaunch protocol. The original 21-file source diff was exact at restored A. Only toolbar placement differed between A and B. Thus there are **four warning-free candidate repetitions versus two warning-producing restored-baseline repetitions**, before strengthening the test. This supports the specific placement workaround under the observed execution conditions, not a universal device/OS guarantee or a proof of framework internals. These repetitions are not additional unique tests in the whole-result count.

### Finalized evidence timeline

All times are UTC on October 2, 2026. The finalized result bundles are retained, not reconstructed from log fragments.

- `H3TopBarToolbar.xcresult`: completed at 15:01:48, exit 0, two repetitions passed, `runtimeWarnings: []`.
- `H3RestoredKeyboardControl.xcresult`: completed at approximately 15:09:05, exit 0, two repetitions passed, two invalid-frame warnings.
- `H3TopBarToolbarRepeat.xcresult`: completed at 15:13:50, exit 0, two repetitions passed, `runtimeWarnings: []`.
- `H3ToolbarLayoutRegression.xcresult`: finalized before 15:18, exit 0, one passed case, zero failures/skips, `runtimeWarnings: []`.
- Commit `2a50c5d`: retained at 15:22:38, exactly the one-line production fix and stronger existing UI assertions in three files.

The unchanged control command selects `HashFleetUITests/RealModeControlUITests/testCustomJSONStagesUnknownFieldsButNeverBypassesTypedConfirmation` with `-test-iterations 2 -test-repetition-relaunch-enabled YES`. The strengthened regression uses the same named case after the B/A/B controls, without changing its original safety helper.

## Actual public output and safety observations

The regression screenshots were exported and visually inspected at 15:18:38 UTC. They show a noncollapsed editor and readable Format/Done actions before focus and while the software keyboard is visible after input. The inline title visibly truncates to **Custom JS...** because the navigation bar shares width with the two actions. This is an acknowledged visual tradeoff, not a claim that the full title fits or every layout is perfect.

The existing workflow then tapped Done, Format & Validate JSON, and Review in Endpoint Explorer. The actual staged review retained unknown `customFeature`, nested `enabled: true`, every digit of UInt64 max `18446744073709551615`, and `frequency: 500`. The input helper asserts the complete raw replacement. The existing review assertions check unknown-key and UInt64 preservation, staged navigation without duplicate authorization, the typed APPLY field despite an armed native power session, no native quick-confirm notice, and zero writes before and after cancellation. The screenshot corroborates the exact visible payload and disabled initial Send control. This observes the selected initial confirmation state, not every separately selectable Developer confirmation preference.

| Captured public output | Regression attachment under `regression-attachments/` |
| --- | --- |
| Actual editor before focus | `9B81A2CD-8B97-43BF-BAAF-D922D22439B8.png` |
| Actual editor after complete input, software keyboard visible | `7D3AA027-6E6D-4FAB-9587-D4BAF91DFBE7.png` |
| Exact typed review and initial disabled Send | `87924E9B-B5C1-4BEC-9AFC-A4F64C899160.png` |

The OS file-import dialog, physical phone layout, other simulator widths, other OS versions and actual ASIC behavior are not covered by these screenshots.

## Independent review

A separate read-only verifier inspected the three owned files and finalized controlled/regression evidence. It found no concrete blocker and recommended retaining the minimal change pending complete acceptance. The reviewer confirmed that existing payload, staging, typed-review and zero-write checks were not weakened, and retained the title-truncation and phone-artifact limitations. It did not independently execute tests or certify the then-running whole-result result. The reviewer was stopped after reporting. Root source inspection corroborated the cited unchanged staging assertions, and the subsequent complete run was finalized and audited by the coordinator.

## Complete integration acceptance

The actual Xcode app-hosted run started at 15:23:05 UTC and finished at 15:31:47 UTC, exit 0, on iPhone 17 Pro / iOS 26.4.1 build 23E254a using Xcode 27.0 build 27A266a. It rebuilt commit `2a50c5d` plus the unchanged original 21-file user-owned source baseline, not a clean-checkout substitute or copied-source harness.

```bash
xcodebuild test -project HashFleet.xcodeproj -scheme HashFleet \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=5AE0257A-7733-4411-9611-25C576DA2B7E' \
  -derivedDataPath /Users/USER/dev/hashfleet/build \
  -resultBundlePath /Users/USER/.jcode/scratch/hash-fleet-editor-next-20261002-1451/H3WholeResultAcceptance.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:HashFleetTests \
  -only-testing:HashFleetUITests/ExpertModeUITests \
  -only-testing:HashFleetUITests/RealModeControlUITests \
  -only-testing:HashFleetUITests/HashFleetUITests/testNormalAndDeveloperModesShowTheRightMinerTools \
  CODE_SIGNING_ALLOWED=NO
```

The finalized summary and extracted tree record **694 unique passed tests**: 681 Swift Testing cases in 69 suites, 5 native XCTest cases, and 8 UI cases. Failures and skips are zero. The per-device count of 912 includes parameterized execution and is not a unique-test count. Exact test-identity comparison against the earlier 13:58 UTC bundle found **zero missing identities, zero added identities and zero non-passed cases**, including all 11 native custom-JSON cases.

All eight mapped actual-app UI cases passed again:

1. `HashFleetUITests.testNormalAndDeveloperModesShowTheRightMinerTools`
2. `ExpertModeUITests.testNormalModeRequiresTypedApplyBeforeRestartReachesTheMiner`
3. `ExpertModeUITests.testDeveloperModeSendsRestartWithoutTypingApply`
4. `ExpertModeUITests.testEasyAndProPreserveDraftAndExposeReadOnlyDiagnosticsWithoutWrites`
5. `RealModeControlUITests.testCustomJSONStagesUnknownFieldsButNeverBypassesTypedConfirmation`
6. `RealModeControlUITests.testOfflineRelaunchShowsCachedSettingsButLocksChanges`
7. `RealModeControlUITests.testPowerUserModeToggleLifecycleWithDirectApplyHostnameWrite`
8. `RealModeControlUITests.testRealModeHostnameWriteAppliesDirectlyForSafeField`

### Updated D1–D6 observations

These update the historical map in the original whole-result audit. The earlier E1–E19 executable cases also all passed again. P1 physical delivery is unchanged historical evidence, not newly exercised phone acceptance.

| ID | Final actual observation | Status and boundary |
| --- | --- | --- |
| D1 | Actual editor entry, finite positive visible editor frame, reachable Format/Done before and after input, working Done and formatting; software keyboard visible in the captured after-input image | Passed on tested simulator, inline title truncation retained |
| D2 | Exact raw JSON replacement, staged unknown nested field and all UInt64 digits retained; all 11 native custom-JSON precision/validation/import-string/redaction cases passed | Passed for app and native boundaries, OS file-import dialog not exercised |
| D3 | Staging did not authorize or duplicate confirmation; initial typed APPLY remained despite armed native power mode; no native quick-confirm notice; zero writes before and after cancel | Passed for observed confirmation preference/state |
| D4 | Same whole run passed all eight mapped UI cases and complete native permission/classification/preflight/demo/offline/persistence boundaries | Passed within software/fixture scope, not physical hardware acceptance |
| D5 | Only owned production/UI files committed; original 21-file source diff preserved exactly; frozen signed build-3 artifact preserved | Passed, repo fix not shipped to phone |
| D6 | Zero invalid-frame warnings in both finalized summary/tree and complete log; restored control reproduced two warnings, candidate control reproduced zero | Satisfied for this workaround on tested path/device/runtime, not universal root-cause proof |

### Remaining runtime warning

The complete run contains **one** runtime warning, not zero: background-thread publishing during `FleetSystemIntegrationTests.pendingOpenIsConsumedExactlyOnceWithoutChangingOtherPreferences`. The modern test tree maps it to `AppTests/FleetSystemIntegrationTests.swift` line 23; legacy issue metadata maps it to line 22. The warning occurred at approximately 15:23:21 UTC. The metadata line difference is recorded without guessing an exact publisher. No invalid-frame warning appears in the summary, tree, legacy issues or log. The custom-editor case itself passed in 91.456 seconds.

This publishing warning remains a separate unresolved issue. The editor-only change neither fixes nor suppresses it, and its occurrence in this finalized complete run corroborates that distinction. The earlier bounded publishing probe remains incomplete and is not promoted into acceptance or added to unique-test totals.

### Final whole-result screenshot inspection

Six actual screenshots from the complete result were read and visually inspected at 15:35:16 UTC. The editor and typed review corroborate the targeted-regression observations, including software keyboard visibility, readable Format/Done, noncollapsed editor, exact UInt64/nested payload and disabled initial Send. Easy retains the exact hostname draft, one pending change, reported-before/proposed-after row and nonoverlapping history selection. Normal Pro shows distinct configured/measured values, honest `Not reported` omissions and reported/read-only wording. The cached General screen shows the retained hostname, stale/read-only wording and disabled review. These are loopback/simulator observations, not fleet readings or physical-phone images.

| Final captured output | Attachment under `whole-result-attachments/` |
| --- | --- |
| Editor before focus | `E088601B-7E50-4364-96B2-27D637870071.png` |
| Editor after exact input, software keyboard visible | `C6300BBC-8CC4-4FE2-A2ED-874166FE2805.png` |
| Exact typed review | `3E5C55C9-207E-482C-B39E-E7B7177C281A.png` |
| Easy before/after draft | `0036A0CC-4959-402A-B129-2A3E4B3CA905.png` |
| Normal Pro reported state | `9BF8CC65-C58E-4108-9B00-6D240973081D.png` |
| Cached offline read-only General | `F51A9BA1-023B-49ED-B554-2304E2905F77.png` |

The historical acceptance and delivered-phone records remain in [the controls record](EASY-PRO-CONTROLS-2026-10-02.md) and [the original whole-result audit](EASY-PRO-WHOLE-RESULT-AUDIT-2026-10-02.md). Their original warning results remain timestamped history, not the current repository editor outcome.

## Preservation and evidence provenance

At 15:27:16 UTC, the original 21-file source diff still matched SHA-256 `5ad2867a3502ba5d5e1941540aad86d90d68b91517c178791b56d4a7bc56abbf`. Those user-owned changes were not staged or committed. The frozen signed phone artifact remained `app.hashfleet` / 0.1.0 / build 3, passed strict deep codesign verification, and retained executable SHA-256 `185a21797e8650caebce9d11c7ad140f6e7e92d52cb2aff2b2d5e03b5296db08`. This is local artifact preservation, not a fresh phone inventory or current foreground-state observation.

Private evidence root: `/Users/USER/.jcode/scratch/hash-fleet-editor-next-20261002-1451/`. It contains the pre-experiment `PLAN.md`, timestamped `OBSERVATIONS.md`, all four finalized targeted result bundles and their log/summary pairs, regression screenshots and manifest, `INDEPENDENT-REVIEW.md`, and finalized `H3WholeResultAcceptance.xcresult`. Complete-run extracts are `h3-whole-result-acceptance-summary.json`, `h3-whole-result-acceptance-tests.json`, `h3-whole-result-identity-audit.json`, `h3-whole-result-legacy.json`, and `h3-whole-result-acceptance.log`, with exported screenshots/manifest under `whole-result-attachments/`. These are app/simulator results, never live fleet telemetry.

## Follow-up: deferred title and keyboard-dismissal candidates (16:00–16:41 UTC)

Two previously deferred alternatives were tested one at a time against the original keyboard-toolbar baseline (pre-`2a50c5d` blobs), each with the unchanged historical safety case `RealModeControlUITests.testCustomJSONStagesUnknownFieldsButNeverBypassesTypedConfirmation`, two fresh-process repetitions, same simulator/runtime. Neither change was retained.

| ID | Single change on original baseline | Result | Invalid-frame warnings |
| --- | --- | --- | --- |
| H4 | Add editor-owned `ToolbarItem(placement: .principal) { Text("Custom JSON") }` | Finalized xcresult: 1 unique case passed in both repetitions, 0 failures/skips | 2 (one per repetition, at editor entry before input) |
| H5 | Remove only `.scrollDismissesKeyboard(.interactively)` | Both repetitions passed per log (16:13:46 UTC). `xcodebuild` then hung and was killed at the 600 s cap, so the result bundle never finalized. Log-only evidence | 2 (one per repetition, immediately after the `settings.customJSON` tap) |
| H3 restored | Committed `2a50c5d` source and stronger tests, byte-identical to HEAD | Finalized xcresult (16:40:56 UTC, exit 0): 1 unique case passed in both repetitions (93.4 s, 94.0 s), 0 failures/skips, 0 runtime warnings | 0 |

Interpretation: on this runtime, neither an explicit principal title nor removing interactive scroll dismissal avoids the warning, while moving the keyboard toolbar group (H3) does, again. This strengthens the placement-specific workaround. It does not prove SwiftUI internals, other devices/runtimes, or physical-phone behavior. H5 lacks a finalized bundle. Phone build 3 is unchanged and still excludes the H3 fix. The original 21-file user diff hash `5ad2867a…6abbf` was re-verified before H5 and after restoration.

Evidence root: `/Users/USER/.jcode/scratch/hash-fleet-editor-remaining-20261002-1553/` (`h4-*`, `h5-*`, `h3-restored-*`, `H4ExplicitPrincipalTitle.xcresult`, `H3Restored.xcresult`, partial `H5NoExplicitScrollDismissal.xcresult`).
