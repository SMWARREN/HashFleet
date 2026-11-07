# Side-by-side Easy tuning, October 31, 2026

Superseded at16:05 UTC by build11: the user rejected side-by-side placement and requested Frequency above Core voltage, both always visible. See `2026-10-31-stacked-tuning-delivery.md`. The checks below are historical build10 evidence.

## Delivered

Production iPhone build **0.1.0 (10)** was installed and launched successfully at approximately **15:52 UTC**. Installed-app metadata independently confirms build 10. Existing app data was retained. No miner settings, firmware, services, pools, fans, wiring, recovery limits or lockouts were changed by this work.

- Frequency and core voltage appear together in one row in Easy mode, with direct numeric entry.
- Neither input requires a dropdown, technical-details disclosure or a separate Use value button.
- Finishing a field, including moving directly to the other field, stages the draft only. Risk acknowledgement and final Apply confirmation remain mandatory.
- Invalid or unfinished input blocks Apply and mode switching. Reset clears pending text and errors. Untouched fields are not added to a settings payload.
- Accessibility text sizes stack the two controls without hiding either behind a disclosure. Native field hit areas and the initial standard-size viewport passed geometry checks.
- Advanced controls retain the same draft. The 601a voltage ceiling, Demo/offline/stale locks, preflight identity checks and post-write readback remain intact.

Production commits: `834e82b` (visible widget power-unit spacing regression repair) and `6e4efc3` (direct inputs and build 10). Test-only follow-up: `4e1a88f` (deterministic native text replacement rather than relying on iOS's inconsistent edit-menu presentation). Production source is identical between the archive and that follow-up.

## Acceptance

| Check | Observed result |
| --- | --- |
| Complete enumerated iOS unit/render suite | **1,446 distinct tests passed** across 141 classes, with no overlap, skips or expected failures in the accepted groups |
| Group 1 | 466 passed |
| Group 2, primary-runtime recheck | 491 passed |
| Group 3 | 489 passed |
| Native Mac suite | **118 passed**, no failures or skips |
| Native phone UI | **7 passed**, no failures or skips |
| Strict SwiftLint | **0 violations** |
| Sonar quality gate | **Passed**, analysis `303d81b9-f6d9-4b60-8f96-cd2214d47cf9` |
| Sonar new-code coverage | **89.3%** |
| Sonar overall measured coverage | **79.6%** |
| Sonar new issues / new duplication | **0 / 0.0%** |
| Signed archive/export | Passed. App and both extensions are build 10, debugger entitlement false and expected shared app group present. Main app APNs environment is production |
| Physical iPhone delivery | Installation, launch and installed-version receipts passed |

The seven native UI cases verify standard same-row layout and touch targets, largest-text reachability, a frequency-only single loopback write, a combined single loopback write with invalid-voltage rejection, frequency/Advanced draft continuity, voltage-only/Advanced draft continuity, and direct focus-change/reset behavior. Confirmation cancellation sends no settings. Successful confirmation sends exactly one PATCH followed by a fresh info read. Test writes use a loopback fixture, not tracked miners.

## Failures retained and limits

- The initial task exited before compilation because strict lint caught the session view's file length. Shared telemetry-card reuse removed duplicated view code. A subsequent test compilation error from a mutating call inside `#require` was fixed by evaluating the mutation first.
- Native rounded text fields were initially only 34 points high despite an outer 48-point frame. The actual control typography was enlarged, retaining Dynamic Type. An intermediate 43.33-point result was also rejected. The final unchanged minimum-44-point assertions passed, with a 45.7-point native field observed in the hierarchy.
- The full regression exposed insufficient visible separation in widget power copy. The production medium/large widget number-to-unit gap was enlarged, without changing the spacing or privacy assertions.
- The first UI invocation executed stale test-runner code. Fresh explicit test-bundle execution exposed the real layout issue. Later edit-menu-dependent replacement failed on two voltage paths. Only the input gesture was changed. Assertions still verify complete clearing, exact replacement, invalid-input rejection, guarded payloads and write counts.
- The outer execution tool enforces a 600-second ceiling even when a longer timeout is requested. The interrupted whole-suite runs are **not** reported as passed. The entire current suite was enumerated and divided into three disjoint groups. Every executed passing test identity was checked against that enumeration, not just summed from logs.
- **Remaining OCR sensitivity:** the first group-2 run on a 2x secondary simulator failed one pre-existing raw Vision text assertion. Its actual pixels show correctly spaced `2.40 TH/s`, but Vision returned `2.40TH/S`. That failed bundle and both images are retained. All 491 unchanged group-2 tests passed on the original 3x unit-test runtime. This is not a claim that cross-resolution OCR sensitivity was fixed or that every simulator run passed.
- The optional read-only worker exceeded its bounded review budget and was stopped without an accepted review. It is not counted as independent approval.
- Sonar plugin mapping/parsing warnings and system-managed WidgetKit behavior remain measurement limitations. This work is not an exhaustive security audit or a live fleet-health certification.

## Evidence

- Enumeration and disjoint identity receipt: `build/sonar/inline-full-summary.json`.
- Final units: `build/inline-build10-units-group1-20261031-1535.xcresult`, `build/inline-build10-units-group2-20261031-1535-primary-recheck.xcresult`, `build/inline-build10-units-group3-20261031-1535.xcresult`.
- Retained secondary-runtime failure: `build/inline-build10-units-group2-20261031-1535.xcresult`.
- Final UI: `build/inline-build10-ui-stable-20261031-1529.xcresult`.
- Final Mac: `build/inline-tuning-final-mac-20261031-1523.xcresult`.
- Sonar input: `build/inline-build10-sonar-20261031.xcresult`. Only the complete accepted unit groups, final UI and final Mac bundles were merged. Unchanged Core/Python coverage reports were reused. No exclusions, gate thresholds or baseline were changed.
- Gate, measures, task, lint and summaries: `build/sonar/inline-*.json`.
- Archive: `build/HashFleet-inline-20261031.xcarchive`.
- Distribution: `build/inline-distribution-20261031/Hash Fleet.ipa`.
- IPA SHA256: `5f7b7c5cdbcc149c69efcb9b363a3dc971e447aac74f94277e18313f7fab2c52`.
- Installation, launch and identity: `build/inline-phone-{install,launch,installed-app}.json`.
- Standard layout screenshot: `~/.jcode/scratch/hashfleet-inline-layout/5F0D2298-EF56-401D-AED3-39E970E6EDCF.png`.
- Retained OCR images: `~/.jcode/scratch/hashfleet-inline-ocr-runtime/`.
