# App, widget and Live Activity consistency, 2026-10-28

## Request and safe scope

The operator asked whether the recent widget work is consistent with the app and authorized fixing inconsistencies. This follow-up checks saved-reading presentation, not a redesign of the app or a change to mining controls. It follows `f222c37`.

No real miner requests, SSH sessions, hardware writes, production installation, account changes, deployment or push were performed. Renders and UI checks use synthetic data and only the existing owned disposable iOS simulator. File-backed refresh tests use private disposable storage and injected readings.

## Findings and fixes

| Finding | Previous behavior | Fixed behavior |
| --- | --- | --- |
| Demo identity | The settings preview said `SAMPLE`; widgets and Live Activities said `DEMO`. The preview's spoken summary also described simulated counts as online. | One `FleetGlancePresentation` compiled into app, native app, widget and widget-test-support targets supplies `DEMO` / `DEMO · STALE` and `Sample data · no connection`. |
| Historical readings | The preview badge said `STALE`, but its spoken summary still described counts as online and its visible body omitted the historical-reading warning. | The preview uses the same `Last known · open app to refresh` status as the widget and displays the original saved observation time. |
| Absent measurements | An empty preview could attach `GH/s` and `W` to missing values. | The shared presentation suppresses rate units for absent/invalid readings. The preview does not show a power field without a valid nonempty aggregate. A genuine reported zero remains `0 GH/s` / `0 W`. |
| Refresh outcome accessibility | System widgets displayed a failed/stopped/timed-out/setup message, but the custom summary that replaces child accessibility labels omitted it. | The widget entry supplies that same fixed message to the shared summary. Redacted summaries do not expose the reading, time or outcome. Demo and empty summaries retain their safe existing behavior. |
| Preview privacy | The app preview constructed its custom summary without consulting privacy redaction. | It now uses the same safe redacted summary policy and marks nonempty reading content privacy-sensitive. |
| Accessible preview typography | The rate unit stayed at a fixed 15-point size while the surrounding accessible text grew. | The unit now uses the app's scalable rounded subheadline style. The saved timestamp uses the existing scalable monospaced caption style. |

The original widget presentation was moved out of `Widgets/FleetWidgetTheme.swift`, not copied into another divergent formatter. The timeline provider, refresh engine, consent, local-device authentication declaration, target preparation, transport, timestamps and `FleetGlance` storage schema are unchanged.

## What was already consistent

- Number and unit strings use a separating space, including `38 W`, `2.40 TH/s` and `15.9 J/TH`.
- The app's diagnostics and reports intentionally keep additional numeric precision. A compact widget's rounded `38 W` and a detail/report's `38.2 W` are not different unit conventions or fabricated readings.
- Hashrate consumers use the existing shared Core scaling policy. No global formatter, CLI, raw CSV or database changes are required by the observed preview defects.
- Saved widget aggregates and the live in-app per-miner readings remain deliberately different data paths. This change does not relabel a cache as a live connection or invent missing per-miner readings from the widget aggregate.
- The app's contrasting charcoal preview panel is an existing, intentional theme token, not a pixel-identical Home Screen widget host. Live Activities also intentionally use a fixed dark inset. This change unifies saved-reading semantics, not every host's background, typography or geometry.

## Requirement-to-check ledger

| Requirement | Check |
| --- | --- |
| Demo and historical status match | Real mounted preview pixels in light/dark, with both compact and detailed previews |
| No units on missing readings; real zero remains valid | Empty-preview pixels and independently compiled app/widget policy cases including NaN, infinity and negatives |
| The exact same saved-reading semantics compile into app and extension | Policy parity at 59.999/60-second freshness and -5/-5.001-second future-clock boundaries, including Demo |
| Refresh failures are included in accessibility labels without refreshing observation time | Exact fixed-message assertions through the actual widget entry presentation, saved-time invariant and redacted-summary assertions; physical speech is not claimed |
| Correct power-unit spacing and privacy | Actual preview pixels assert `38 W`, reject `38W`, and hide rate, power and counts under privacy redaction |
| Larger text and compact/wide layouts retain warnings and time | Actual rendered accessibility-size previews at 320 and 520 points |
| Actual settings previews expose the same safe Demo summary | Installed disposable-simulator navigation to Widgets and Live Activity in light and dark appearances, using the existing `--ui-testing --demo` synthetic fixture |
| Existing behavior stays intact | Existing refresh, branding, reports, telemetry completeness, settings rendering, diagnostics, formatting, widget/activity and strict native tests |
| No unrelated edits or acceptance weakening | Original tracked binary-diff hash, all 24 original untracked-file hashes and six protected source/test hashes |

## Validation receipts

Artifacts: `~/.jcode/scratch/hashfleet-consistency-20261028-2252/`.

- `consistency-red.xcresult` / `.log`: all four added consistency test definitions failed against the unchanged `f222c37` production sources, with 26 observed issues. The fixtures captured the actual mismatches rather than adding test-supplied OCR text.
- `consistency-green.xcresult` / `.log`: the same four definitions passed unchanged after the production fix. The complete focused run passed 35 definitions in four suites, including all 25 existing refresh definitions and six existing modernization definitions.
- `native-build.log`: the native app and test targets build with `SWIFT_STRICT_CONCURRENCY=complete` and signing disabled, using the same new shared presentation source.
- `native-final-build.log` / `native-final-tests.log`: after the last production typography change, the strict native app/test build succeeds and all 37 definitions in six isolated native suites pass. The isolated loader does not launch a production app or read its stores.
- `mobile-final.xcresult` / `.log`: the first expanded run executed 238 definitions, with 232 passed, six failed and none skipped. Alongside the two retained original widget definitions, failures included two new exact OCR checks, an existing refresh-render timestamp OCR check and an existing illustrated-session renderer timeout. The timeout and timestamp OCR check passed on the next unchanged run. This receipt remains retained, not replaced by later results.
- `mobile-final2.xcresult` / `.log`: 240 definitions, 236 passed, four failed, none skipped. The failures were the two original widget definitions, one new exact OCR case reading `TH/s` as `TH/S`, and the newly added installed Demo test incorrectly launched without the existing `--demo` fixture. The installed refresh-off/private-mode test passed. Only that new test's launch setup was corrected; all its content assertions remain intact and its failing receipt is retained.
- Directly reviewed `rendered-final2/60F6C6F1-D242-4371-954F-31A4D42E7FB7.png`, `44CFF111-0804-4501-AD3C-976386617586.png` and `2D78D54D-3821-423A-A431-18C9EF73D946.png`. The regular preview visibly has lowercase `TH/s` and spaced `38 W`. The 320-point accessibility preview retains the warning and original date/time without clipping. Privacy redaction hides rate, power, counts and time. These observations do not turn the strict failing OCR assertion into a passing test.
- `mobile-final3.xcresult` / `.log`: final complete selection after the last source/test edit, 240 definitions, **237 passed, three failed, none skipped**. Both installed UI methods pass, including navigation to Widgets and Live Activity in both appearances with the same exact Demo/no-connection accessibility summary. All 25 existing local-refresh definitions and all freshness/clock-boundary parity cases pass. The only failed definitions remain the two original literal-`38W` component tests and the new exact `TH/s` OCR check. The overall command still exits 65 and is not an all-green acceptance result.
- `installed-previews-final3/manifest.json`: six exported screenshots, including all four Demo preview states and the unchanged light/dark refresh-off UI check. Directly reviewed the installed light Widget preview (`378F9754-859F-41E9-B42B-6EF866C899C9.png`) and dark Live Activity preview (`B5CD5F8D-07B9-4091-922B-352EE5895AA1.png`). Both clearly label the values as Demo/sample data with no connection and retain the observation time. No activity was started and neither sharing toggle was enabled.
- `git diff --check` and project `plutil -lint` pass. The preservation verifier passes after the final run: the original unrelated tracked binary diff, all 24 original untracked files and six frozen source/test files remain byte-for-byte unchanged. The staged delivery is restricted to the eight files for this follow-up, with no push or deployment.

The original `WidgetActivityComponentCoverageTests.swift` and `FleetViewRenderHarness.swift` are unchanged. In particular, their three literal `38W` expectations are not rewritten, nor is correct app-wide `38 W` spacing removed to obtain a green acceptance run. Any retained failures are reported as failures, not skipped or reclassified as passing.

The requested read-only secondary review did not complete: its configured automatic route resolved to NVIDIA NIM / `deepseek-ai/deepseek-v4.1-flash` and failed its chat request before inspecting any files. No model/account override or pool changes were attempted. The source review, requirement mapping and validation receipts here are the coordinator's work, not an independent-review endorsement.

## Accessibility reference and limits

Apple's `AccessibilityChildBehavior.ignore` documentation states that ignored child properties must be replaced using modifiers such as `accessibilityLabel`. Apple's widget/privacy documentation describes privacy-sensitive content redaction. Those contracts motivated preserving an explicit privacy-safe summary and adding the missing visible fixed outcome, not exposing ignored child data.

Primary references checked on October 28, 2026:
- `https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/ignore`
- `https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension`
- `https://developer.apple.com/documentation/swiftui/view/privacysensitive(_:)`

Pure summary assertions and simulator accessibility checks do not prove spoken VoiceOver behavior on physical devices. Signed App Group access, real Local Network permission states, lock/unlock authentication, actual new AppIntent dispatch, mirrored widgets, physical tinted/clear/StandBy surfaces and discretionary background cadence remain outside this safe local validation loop.
