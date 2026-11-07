# Rendering acceptance repairs, October 31, 2026

## Delivered

Repair commit: `9369a70a2e35ce8f200676a5a4503745ae6a1251`.

Hash Fleet **0.1.0 (9)** was clean-archived, distribution-exported, installed and launched on the same connected iPhone at approximately **13:08 UTC on October 31, 2026**. Installed metadata confirms bundle `app.hashfleet`, version `0.1.0`, build `9`.

**All nine previously failing test identities now explicitly pass.** The final complete iOS unit/render result contains **1,440 passed, 0 failed, 0 skipped, 0 expected failures**. This supersedes the unresolved rendering-test status in `2026-10-31-easy-tuning-delivery.md`, without erasing that earlier failed run.

No uninstall, App Store upload, miner write, firmware update, pool change, tuning change or power-wiring action was performed. Existing app data was preserved by an in-place installation.

## The nine failures and their repairs

| Original failing identity | Observed problem | Repair and final evidence |
| --- | --- | --- |
| `FleetViewRenderHarnessTests/concurrentRendersKeepTheirOwnActualPixelsAndCopy()` | OCR read the captured `MHz` as `MHZ`. | Independent uncorrected OCR observations retain exact casing. Concurrent captures still require their own value, reject the other captures' values, and have distinct PNGs. Passed. |
| `MinerToolsRenderingCoverageTests/endpointFormsDescribeTheirExactOperationWithoutExecuting(_:)` | A long endpoint wrapped physically after `/api/system/`, breaking a contiguous-string assertion. | Explicit wrap-aware observation joins only adjacent, aligned, single-column lines. Internal whitespace is not removed. The exact method and complete path remain required. Passed. |
| `PoolLookupSourceRenderingCoverageTests/explicitLookupRendersParsedAccountOrHonestFailure(_:)` | OCR misread lowercase hashrate units in the account metrics. | Exact value/unit recognition with same-row geometry and a visible gap. No case substitution or expected words are supplied to OCR. Passed. |
| `FleetGlancePresentationConsistencyTests/realPreviewPixelsKeepSpacedPowerAndProtectAllReadingDetails(scheme:)` | OCR placed the separately styled `2.40` and `TH/s` in different positions in its reading order. | Word bounds check the exact numeric value and case-sensitive unit together on the actual visual row. Light/dark cases and stronger numeric privacy negatives pass. |
| `WidgetActivityComponentCoverageTests/rendersActualLargeWidgetContentWithPrivacyPair()` | The test expected obsolete `38W`, while production correctly draws `38 W`. | Require spaced `38 W` by exact word/geometry observation. Also restore the exact `TH/s` unit check that the old test had avoided. Regular and privacy-redacted captures pass. |
| `WidgetActivityComponentCoverageTests/rendersActualSmallWidgetContentWithPrivacyPair()` | OCR collapsed the gap between differently sized value/unit text into `2.40TH/s`. | Measure the real value/unit word bounds instead of trusting OCR's synthesized space. Correct unit, visible gap and hidden private number remain mandatory. Passed. |
| `WidgetActivityComponentCoverageTests/rendersActualStandardLockScreenActivityContentWithPrivacyPair()` | OCR read `TH/s` as `TH/S`. | Independent raw recognition plus exact metric geometry preserves the lowercase-unit contract and privacy negatives. Passed. |
| `PreferencesRenderingCoverageTests/sessionRecordRendersTheExistingIllustratedCelebration()` | Bright animation particles could cross readable copy. The captured headline was recognized as `Worksbop Gamma`. | Production confetti is now clipped to the mascot artwork and hidden from accessibility. Text and actions remain outside the particle area. The original exact headline assertion passes. Native animated popup, dismissal and accessibility-size checks also pass. |
| `MinerSettingsRenderingCoverageTests/testCoolingPageRenderingAndLayouts()` | OCR separated reported cooling values from their units. | Exact word/row/gap checks require `56 °C` and `75 %`. Auto/manual, accessibility-size and missing-reading cases pass. |

The medium widget had the same obsolete `38W` expectation even though OCR happened to make it pass previously. Its assertion now also tests the actual spaced-power contract.

## Measurement safeguards

- Captures still come from mounted production SwiftUI views, not accessibility-label substitutions.
- Both OCR modes use uncorrected recognition. No custom expected vocabulary, case folding, character correction or unit substitution is used.
- Short numeric-line refinement reads cropped original pixels without resampling or supplying expected text.
- Ordinary copy preserves Vision's paragraph ordering. Geometry is reserved for explicit metric and wrapped-token checks.
- Actual-pixel negative controls reject uppercase `TH/S`, wrong `GH/s`, fused `38W`, incorrect values, hidden text and accessibility-only numeric metadata.
- Geometry controls reject different rows, reversed order, remote columns, zero gap and mismatched values. Wrap controls reject nonadjacent or multicolumn lines and preserve internal whitespace.
- Existing concurrent-host, tall-image boundary, repeated-copy, key-window, readiness-timeout and blocked-network checks remain in the passing full suite.

The initial scoped repair run exposed a regression: globally sorting OCR rows inserted centered icons inside two wrapped tool labels. That failed run is retained. The final implementation preserves the recognizer's paragraph order, adds a regression control, and passes the original assertions in the full run. No assertion was deleted to conceal that failure.

## Final acceptance

| Check | Result |
| --- | --- |
| Complete iOS unit/render suite | **1,440 passed, 0 failed, 0 skipped, 0 expected failures** |
| Original nine failing identities | **9/9 explicitly `Passed`** in the final xcresult test tree |
| Native Mac suite | **118 passed, 0 failed, 0 skipped** |
| Native phone celebration UI | **4 passed**: popup over sheet and dismissal, session opt-out persistence/re-enabling, largest-text reachability, all three record previews with retained settings |
| Native phone Easy workflow UI | **5 passed**: standard and large-text layout, exactly one frequency-only loopback write, frequency/custom/Advanced draft flow, voltage/custom/Advanced draft flow |
| Strict SwiftLint | **0 violations** |
| Shared page-shell source guard | Passed, not a substitute for runtime layout checks |
| Clean Release archive/export | Passed |
| Distribution signing | Main app and both extensions have build 9, shared app group, and debugger entitlement false. Main app APNs environment is production |
| Installation and launch | Both receipts report success. Installed metadata confirms 0.1.0 (9) |

The final full run used unchanged committed source. Closing source comparison matches commit `9369a70` with no changed source paths. Source digest: `f6f40cdb30c6a6de3419bed073374b3798b9410aa4a0b956475c4eee820d2483`.

The outer tool unexpectedly capped its waiting launcher at 600 seconds. Its separately sessioned Xcode child continued running normally. A process-exit watcher observed that same child finish, then read the finalized successful xcresult. No duplicate full test run was launched, and no timed-out run was relabeled as a passing test. Xcode's final test execution took approximately 944 seconds.

## Sonar

Fresh scan of repair commit `9369a70` passed the unchanged quality gate:

- New-code coverage: **88.0%**, threshold **80%**.
- Overall measured coverage: **80.0%**.
- New duplication: **0.0%**.
- New issues: **0**.
- Reported bugs, vulnerabilities and security hotspots: **0**.

Coverage imports use the final full iOS run, final Mac run and both disjoint final phone UI runs. The existing genuine Core and Python coverage reports were reused because those source areas did not change. No source exclusion, quality threshold or new-code baseline was changed.

Sonar plugin parsing/mapping warnings remain a measurement limitation. This is not an exhaustive security audit or a claim that every system-managed WidgetKit lifecycle, OS version or device size has been exercised. The pixel harness does not establish accessibility semantics by itself. Independent worker reviews failed at their providers and are not counted as approvals. Existing broader App Store readiness requirements remain applicable.

## Retained evidence

- Original failing full run: `build/easy-full-units-20261031-1119.xcresult`.
- Initial repair run, including the paragraph-order regression: `build/render-fixes-scoped-20261031-1240.xcresult`.
- Final complete iOS run: `build/render-fixes-full-20261031-1249.xcresult`.
- Final Mac: `build/render-fixes-mac-20261031-1250.xcresult`.
- Final celebration UI: `build/render-fixes-phone-ui-20261031-1251.xcresult`.
- Final Easy UI: `build/render-fixes-easy-ui-20261031-1254.xcresult`.
- Merged Sonar import: `build/render-fixes-sonar-20261031.xcresult`.
- Original-nine identity receipts: `build/sonar/render-original-nine-verified.json`.
- Full summary, lint and Sonar receipts: `build/sonar/render-fixes-{full-summary,swiftlint,gate,measures}.json`.
- Clean archive: `build/HashFleet-render-20261031.xcarchive`.
- IPA: `build/render-distribution-20261031/Hash Fleet.ipa`.
- IPA SHA256: `427be13f0d27e2c719a293e1e34f8777ce8c9ef457dbefdb235fd8058d36fa1c`.
- Install, launch and installed identity receipts: `build/render-phone-{install,launch,installed-app}.json`.
- Source/process receipt: `/Users/USER/.jcode/scratch/hashfleet-render-full-receipt.json`.
- Mounted celebration PNG: `/Users/USER/.jcode/scratch/hashfleet-celebration-fixed/781B822D-E6C4-4879-ADF5-9AD572F00D66.png`.
- Native animated overlay PNG: `/Users/USER/.jcode/scratch/hashfleet-celebration-ui-fixed/E8526901-9A6E-4A9A-A3AF-7A8C749E6070.png`.
