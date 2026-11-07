# Easy tuning delivery, October 31, 2026

Follow-up at 13:08 UTC: all nine rendering failures below are resolved in production build 9. The final complete iOS suite passed 1,440/1,440 with zero failures or skips. See `2026-10-31-rendering-repairs.md` for causes, safeguards, final validation and installation receipts. The original build-8 results below remain historical evidence.

## Delivered

Implementation commit: `e8df32a`.

Hash Fleet **0.1.0 (8)** was clean-archived, distribution-exported, installed and launched on the connected iPhone on October 31, 2026 at approximately 11:37 UTC. Installed metadata confirms `app.hashfleet`, version `0.1.0`, build `8`. No uninstall, migration, backup, App Store upload or miner-settings change was performed.

- Easy mode starts with a compact frequency editor.
- Safety acknowledgment, the human-readable change summary and Apply are kept together in a bottom review area at standard portrait sizes.
- Accessibility text sizes and compact-height layouts use a short inline review before optional technical content instead of an oversized bottom area.
- Voltage, exact JSON, live context, references, ASIC information and journal are behind one disclosure. Advanced retains its full controls.
- Editing remains draft-only. The existing confirmation alert, frozen-payload comparison, write authorization, voltage restriction, service preflight and readback remain intact.
- Any explicitly staged voltage change remains visible in the review summary even when technical details are collapsed. Untouched voltage is not sent.
- Custom-value commit dismisses focus and restores the review area. Demo remains read-only.

## Acceptance evidence

| Check | Observed result |
| --- | --- |
| Final phone UI | 5 passed, 0 failed: initial no-scroll layout, large-text layout, one frequency-only loopback write, frequency mode switching/custom input, voltage mode switching/custom input |
| Final iPad UI | No-scroll and large-text checks passed. Loopback case initially timed out entering the tuner, then passed unchanged on a targeted rerun |
| Scoped tuning units | Initial 101 tests in 6 suites passed; final full run also recorded no tuning-test failure |
| Native Mac | 118 tests in 24 suites passed on final source |
| Full iOS unit/render suite | Xcode summary: **1,424 passed, 9 failed, 0 skipped**, 1,433 identities. Source digest unchanged during the 744-second run |
| Strict SwiftLint | **0 violations**, 0 serious, 555 files |
| Shared page-shell check | Passed, a source guard rather than runtime acceptance |
| Clean Release | Clean archive and distribution export succeeded |
| Signing | Main app has production APNs, shared group `group.app.hashfleet.shared`, debugger entitlement false. Both embedded extensions also have build 8, shared group and debugger entitlement false |
| Device delivery | Installation and launch succeeded, installed version/build verified |

The loopback acceptance test proves that editing and cancelling send nothing, acknowledgment is required, confirmation sends exactly one `{"frequency":510}` PATCH, a subsequent info GET occurs, and verified completion clears the pending change. No real miner was written to.

The iPad navigation-entry timeout is preserved, not erased by the successful unchanged rerun. Earlier mode-switch regressions found a fractional tap-target height and a DisclosureGroup identifier overriding child identifiers. Production controls were enlarged to 48 points and the disclosure identifier was scoped to its label. The original exact-payload assertions were not relaxed.

## Sonar

Final scan analyzed `e8df32a` and passed the unchanged quality gate:

- New-code coverage: **87.9%**, threshold 80%.
- Overall measured coverage: **79.7%**.
- New duplication: **0.0%**.
- New issues: **0**.
- Bugs: **0**, vulnerabilities: **0**, security hotspots: **0** as reported by the configured analyzers.
- One existing minor AppIntent confirmation-API deprecation remains in `FleetMinerControlIntents.swift`.

The first scan failed because sonar-apple attempted to add duplicate test metrics when several runs of the same UI class were merged. The successful retry imported one final full-unit run, one final phone UI run and one final Mac run. All iPad evidence remains separately retained. No source exclusion, coverage threshold, new-code baseline or assertion was weakened.

Fresh app coverage came from these final-source Xcode results. Existing genuine Core/Python coverage reports were reused because those sources were unchanged. Plugin limitations remain: some test-class mapping and optional analyzer parsing warnings, and no claim of an exhaustive security audit. A passing Sonar gate does not override failed acceptance tests.

## Remaining release limitations

The nine full-suite failing identities are in unchanged rendering/OCR checks:

1. `FleetViewRenderHarnessTests/concurrentRendersKeepTheirOwnActualPixelsAndCopy()`.
2. `MinerToolsRenderingCoverageTests/endpointFormsDescribeTheirExactOperationWithoutExecuting(_:)`.
3. `PoolLookupSourceRenderingCoverageTests/explicitLookupRendersParsedAccountOrHonestFailure(_:)`.
4. `FleetGlancePresentationConsistencyTests/realPreviewPixelsKeepSpacedPowerAndProtectAllReadingDetails(scheme:)`.
5. `WidgetActivityComponentCoverageTests/rendersActualLargeWidgetContentWithPrivacyPair()`.
6. `WidgetActivityComponentCoverageTests/rendersActualSmallWidgetContentWithPrivacyPair()`.
7. `WidgetActivityComponentCoverageTests/rendersActualStandardLockScreenActivityContentWithPrivacyPair()`.
8. `PreferencesRenderingCoverageTests/sessionRecordRendersTheExistingIllustratedCelebration()`.
9. `MinerSettingsRenderingCoverageTests/testCoolingPageRenderingAndLayouts()`.

Observed failures include OCR spacing, capitalization, text ordering and a misread character. They remain failed checks, not accepted exceptions. Swift Testing's console count of 1,428 tests and 15 issues uses different aggregation and is not added to the Xcode summary.

The independent read-only review found no blocking issue in the inspected UI/state code. It did not inspect service internals or execute tests. VoiceOver focus stability across periodic review refreshes, hardware-keyboard dismissal variants and exhaustive window-size coverage were not verified. The App Store setup and other release requirements in `2026-10-30-hashfleet-release-readiness.md` remain applicable. This delivery is not a claim that the whole app is ready for App Review.

## Local evidence

- Final phone: `build/easy-final-phone-20261031-1121.xcresult`.
- Final iPad: `build/easy-final-ipad-20261031-1121.xcresult`.
- Unchanged iPad rerun: `build/easy-ipad-loopback-repeat-20261031-1125.xcresult`.
- Final Mac: `build/easy-final-mac-20261031-1121.xcresult`.
- Full units: `build/easy-full-units-20261031-1119.xcresult`.
- Successful Sonar coverage import: `build/easy-sonar-unique-runs-20261031.xcresult`.
- Strict lint: `build/sonar/easy-final-swiftlint.json`.
- Full-unit summary: `build/sonar/easy-full-unit-summary.json`.
- Archive: `build/HashFleet-easy-20261031.xcarchive`.
- IPA: `build/easy-distribution-20261031/Hash Fleet.ipa`.
- Installed identity and launch receipts: `build/easy-phone-installed-app.json`, `build/easy-phone-launch.json`.
- Final phone screenshot: `/Users/USER/.jcode/scratch/hashfleet-easy-final-screenshots/68493C15-20BB-4A8A-B280-4E3F542191C6.png`.
