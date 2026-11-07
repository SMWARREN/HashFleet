# Verified 80% overall coverage

Date: October 8, 2026. This records the completed coverage work before the separately authorized native chart and organization improvements.

## Exact server outcome

| Check | Observed result |
| --- | --- |
| Analysis | `fbad2cbc-1f27-44f0-b56b-d0e6146b8502` |
| Processed | October 8, 2026, 17:32:44 UTC |
| Overall coverage | **80.1%**, 26434 / 33009 covered lines |
| New-code coverage | **81.9%**, server-reported coverage metric |
| New-code covered lines | 947 / 1162 |
| Quality gate | **OK** |
| Unresolved issues | **0** |
| Test failures | **0** |
| Duplication | 0.0% |
| Baseline | PREVIOUS_VERSION, October 8, 2026, 03:20:07 UTC |

The percentages above are the exact server-reported coverage metrics. Covered-line counts are shown separately and their unrounded fractions also exceed 80%. No rounding-only threshold acceptance is used. Gate thresholds remain new-code coverage 80%, new duplication maximum 3%, and new violations maximum 0. Source scope, exclusions and scan configuration were not changed to obtain this result. Physical component paths match the preceding measured analysis.

The preceding analysis at 17:19:58 UTC reported 79.8% overall, 77.8% new-code and two Python exception-test issues. It was explicitly rejected. The final result adds real execution of five existing demo-only tuning workflows and removes ambiguous exception checks, rather than reducing thresholds or excluding difficult code.

## Accepted executed evidence

Artifacts below are retained under the agent scratch directory `coverage-80-20261008`.

| Evidence | Complete passing result |
| --- | --- |
| `frozen-unit-2.xcresult` | 1083 app unit tests, zero failures |
| `frozen-ui-tuning-2.xcresult` | Complete affected tuning suite: 54 tests. Six read-only native feature workflows. Zero failures |
| `tuning-safe-ui-3.xcresult` | Five existing demo-only tuning UI workflows, zero failures |
| `frozen-green-merged-3.xcresult` | Complete merged native result: 1094 distinct tests, zero failures |
| `core-final-1.log/xml` | 46 XCTest and 246 Swift Testing cases passed. Physical Core coverage 3718 / 4091 lines |
| `python-final-5.log/xml` | All 65 tooling tests passed with a fresh coverage export |
| Strict SwiftLint | Full repository strict lint passed |

Sonar reports 1505 test executions. That aggregate includes reruns and is not claimed as 1505 distinct tests. Native acceptance counts come from the complete local xcresult summaries.

The eleven native workflows include all 17 guided lessons, feature navigation, pool/network sample copy, energy/missing-cost states, achievement filters, PDF preview without sharing, actual tuning dial/rim interactions, individual and combined payloads, restoration, remembered acknowledgement, numbered ASIC rails, and large Dynamic Type. Tuning workflows use the app's explicit demo entry point and never confirm a device write.

## Composite source provenance

Each native run has identical before/after full source and configuration fingerprints. Every production-source, native UI source, project and scan-configuration hash matches across imported bundles.

Two test-only follow-through changes were made between successful epochs:

1. `AppTests/MinerTuningTests.swift`: exact JSON expectations now require valid UTF-8 instead of lossy decoding. The entire 54-test suite was rerun successfully. Commit `c07a11f`.
2. `Tools/test_art_tooling_coverage.py`: image construction moved outside two expected-error contexts, so each test proves the LED mask operation throws. All 65 tooling tests were rerun successfully. Commit `d977def`.

The archived source manifests distinguish these epochs. This is composite full-suite plus affected-suite acceptance, not a claim that all tests ran after the final test-only edit in one invocation. The only production visibility seams expose seven existing widget/Activity component types internally for direct production-body rendering. No substitute production implementation was introduced.

The result bundle was merged only from the three complete passing native bundles listed above. Core and Python imports use exports from passing runs. Failed checkpoints, the earlier worker-contaminated run, and the combined run interrupted by a 600-second timeout were not imported.

## Implementation and validation boundaries

- Added production-body coverage spans dashboard, miner details/settings/tools, preferences, network/lookup source states, miner/XMRig read-only states, widgets and Activity components.
- Visible-copy checks process the exact returned native PNG in exhaustive physical-pixel strips. No expected-word lexicon, fuzzy matching, case folding, punctuation repair, numerical correction, image enhancement, or accessibility/model fallback is used.
- OCR proves visible pixels, not VoiceOver exposure, focus or ordering. Native XCUI assertions establish the tested labels, values and control-protection contracts separately.
- Exact zero-glyph OCR and large-widget unit-case recognition remain explicitly unclaimed. Paired actual images, a positive missing-value control and independent model/unit checks cover the narrower contracts.
- Renderer readiness is a nominal bounded observation loop, not a strict wall-clock guarantee. Raster/OCR work can extend elapsed time.
- Direct widget/Activity component rendering does not validate installed-extension delivery, timeline lifecycle, family routing, Activity requests or permissions.
- Opt-in Core live-network tests remain skipped. Fixture traffic is local and fail-closed. No live-miner settings, firmware, wiring, recovery policy, services or installed user app were changed for this work.
- Existing scanner diagnostics include optional Periphery/MobSF sensors not running and nonfatal Xcode test/warning parsing diagnostics. This green gate is not a comprehensive security or dead-code attestation.
- Unrelated website edits are excluded from the coverage commits. The approved native UI handoff is a separate subsequent goal.

## Committed evidence

- `2026-10-08-overall-coverage-80-sonar-receipt.json`
- `2026-10-08-overall-coverage-80-sonar-components.json`
- `2026-10-08-coverage-80-full-units.sha256`
- `2026-10-08-coverage-80-native-suite.sha256`
- `2026-10-08-coverage-80-demo-tuning.sha256`

The receipt verifies the exact latest analysis and unchanged gate/baseline. The component receipt preserves file-level metrics for later regression comparisons.
