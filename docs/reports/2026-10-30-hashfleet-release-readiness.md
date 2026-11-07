# HashFleet release readiness, October 30, 2026

## Decision

**Production-signed device build delivered. Not ready to submit to App Review yet.** Strict SwiftLint passes and Sonar's quality gate passes with measured coverage, but the iOS acceptance suite is not fully green. A fresh App Store Connect record and submission materials are still needed.

This report distinguishes build success, measured tests, and release readiness. A passing Sonar gate is not a substitute for passing acceptance tests. No App Store upload, review submission, or public release was performed.

## Source and rebrand

Validated application source revision: `b7243350b18d06d2def4199c0cfe3e87dda3f217`.

- `803be32`: renamed product paths, modules, targets, assets and identifiers.
- `36a37b3`, `e9561e1`: lint and tooling repairs, including the fixture secret finding.
- `155f279`: repaired the structural refactors, PDF interpolation, dashboard visibility, push identity synchronization, layout call sites and split test access. Expanded analysis to native Mac and the notification extension.
- `b724335`: restored the split shared test file to the Mac target and selected canonical Release entitlements.
- Tracked paths contain no retired product name. Remaining old product text is confined to negative branding assertions. Third-party vendor/protocol identifiers remain intact.
- No data migration or backup was created. Old external service records were not deleted. No miner settings, pools, firmware or wiring were changed during this validation.

## Delivered production build

| Item | Verified result |
| --- | --- |
| Main app | `app.hashfleet`, version `0.1.0`, build `7` |
| Widgets | `app.hashfleet.widgets`, version `0.1.0`, build `7` |
| Notification service | `app.hashfleet.notification-service`, version `0.1.0`, build `7` |
| Shared App Group | `group.app.hashfleet.shared`, present in all three signed products |
| Distribution | Apple distribution signing, `release-testing` export |
| Main app APNs entitlement | `production` |
| Debugger entitlement | `get-task-allow = false` |
| Signature verification | `codesign --verify --deep --strict` passed |
| Phone | Distribution app installed and launched, installed identifier/version checked again at 10:19 UTC |

Artifacts, relative to the repository:

- Archive: `build/HashFleet-20261030.xcarchive`
- Distribution IPA: `build/distribution-20261030/Hash Fleet.ipa`
- Installed app source: `build/distribution-20261030/unpacked/Payload/HashFleet.app`
- IPA SHA-256: `2b9ff518f108f5ea701281766988f5b2c3e4316786d63661d4f0b6c8298e0b6b`

The IPA is a production-signed device-testing export, **not an App Store upload**. The archive can be used for the App Store distribution workflow when the outstanding work is complete. The earlier development-signed installation was replaced by this distribution export.

Native Mac Release and menu-bar Release builds also succeeded. Both launched in smoke checks. The native Mac overview was visually inspected with isolated demo data, then both smoke-check processes were closed. Mac Store distribution/signing/notarization was not established by these local builds.

## Validation matrix

| Check | Observed outcome |
| --- | --- |
| Full expanded strict SwiftLint | Exit 0, no violations, final run 10:17 UTC |
| SwiftPM | 284 tests in 31 suites passed |
| Native Mac tests | 118 passed, zero failed |
| CLI Release dashboard | 18 passed on unchanged rerun and coverage run |
| CLI firmware activity | 11 passed |
| CLI settings | 21 passed |
| Python tooling | 82 passed |
| Python packaging | 16 passed |
| iOS app and extensions | Simulator compilation and signed Release build/archive/export passed |
| Full iOS unit/render run | Xcode summary: 1,409 passed, 18 failed, 1,427 total test identities |
| Notification prerequisite UI | 1 passed, real simulator permission granted through the public app flow |
| Notification delivery rerun | All 10 tests passed after the prerequisite, no assertions changed |
| Representative iPad UI | Final xcresult: 14 selected tests, 9 passed and 5 failed |
| Targeted iPhone UI follow-up | Test log: 5 executed, 3 passed and 2 failed. Command timed out during diagnostic collection, result bundle incomplete |

The Swift Testing console uses a different aggregation: 1,422 tests in 136 suites and 24 issues. Parameterized test cases, XCTest, and Swift Testing aggregation must not be added together as if they were independent tests. After the successful notification rerun, eight failing identities from the full run remain unresolved. A new fully green full-suite result has not been obtained.

The CLI is a macOS executable, not an iOS simulator app. It was tested on macOS using actual terminal/PTY behavior and loopback fixture servers. The initial dashboard run had an intermittent narrow-details footer failure. The same unchanged test passed five individual reruns, then the unchanged full dashboard suite and coverage run passed. This remains a recorded flake, not evidence that the initial failure never occurred.

### Remaining iOS acceptance failures

1. `MinerSettingsRenderingCoverageTests.testCoolingPageRenderingAndLayouts`: pixel OCR recognized temperature/percent without the expected spaces.
2. `MinerToolsRenderingCoverageTests.endpointFormsDescribeTheirExactOperationWithoutExecuting`: wrapped endpoint paths introduce OCR spaces; a slashed zero is recognized incorrectly in pool paths.
3. `MinerToolsRenderingCoverageTests.collapsedDiagnosticsShowMissingReadingsWithoutClaimingExpandedSections`: OCR recognized “firmware” incorrectly.
4. `PoolLookupSourceRenderingCoverageTests.explicitLookupRendersParsedAccountOrHonestFailure`: OCR recognized the unit's lowercase `s` as uppercase `S`.
5. `FleetGlancePresentationConsistencyTests.realPreviewPixelsKeepSpacedPowerAndProtectAllReadingDetails`: OCR separated the rate value and unit into nonadjacent text.
6. Three `WidgetActivityComponentCoverageTests` small/large/lock-screen privacy-pair tests: spacing or unit-case OCR mismatches. These failures do not establish a privacy leak, but their assertions did not pass.

The pixel observations strongly suggest OCR sensitivity for several failures. That is not permission to rewrite expected output, normalize away distinctions, skip tests, or declare them passing. Investigate the rendered attachments and validate a robust visual contract before accepting a replacement check.

The iPad UI log has five failures: three tuning workflows cannot find a safe scroll start outside dial artwork, the scheduled-summary demo notice is absent from the queried accessibility tree, and the widget artwork workflow cannot find the system “Edit Home Screen” control. These need device-aware diagnosis. No hardware tuning occurred: write-path checks use a loopback server.

### Result bundles

- Full iOS units: `build/validation-units-20261030-0955.xcresult`
- Mac: `build/validation-mac-20261030-0944.xcresult`
- Notification permission: `build/validation-notification-auth-20261030-1014b.xcresult`
- Notification delivery: `build/validation-notification-system-20261030-1015.xcresult`
- iPad UI: `build/validation-ui-20261030-1001.xcresult`
- Targeted iPhone UI: `build/validation-phone-ui-20261030-1016.xcresult` is incomplete after timeout. Use the test log described below, not this bundle as finalized evidence.
- Sonar coverage input: `build/validation-combined-20261030-1015.xcresult`, merged from completed full iOS units and Mac tests

The initial all-tests command timed out at the tool's ten-minute ceiling. Its partial result is not counted as completed validation. The first secondary UI launch was stopped after a simulator launch stall, then retried on a booted device. The full UI suite was not run: these were representative public-interface acceptance selections, not exhaustive UI coverage.

## Sonar analysis

At 10:16 UTC, the latest analysis of the validated source revision reported:

| Metric | Value |
| --- | --- |
| Quality gate | **OK** |
| New-code coverage | **81.0%**, gate requires at least 80% |
| Overall measured coverage | **77.8%** |
| Bugs | 0 |
| Vulnerabilities | 0 |
| Security hotspots | 0 |
| Code smells | 1 minor compiler deprecation note |
| Duplication | 0.0% |
| New violations | 0 |

The remaining minor note is `FleetMinerControlIntents.swift:122`, the result-based confirmation API used only in the older-OS fallback. The modern API is already used on iOS 18/macOS 15 and later. iOS 17/macOS 14 remain supported. Removing confirmation or raising the deployment target merely to hide this note would be inappropriate. The note remains visible, not marked falsely resolved.

Coverage came from real execution:

- Merged Xcode results imported coverage for 445 files.
- SwiftPM coverage: 4,469 of 4,914 observed lines across 48 source files.
- Generic SwiftPM report: `build/sonar/core-coverage.xml`.
- Python coverage: `build/sonar/python-coverage.xml`.

No quality-gate threshold, new-code period or coverage exclusion was relaxed. The earlier scan without Xcode coverage failed its coverage gate and was superseded by this measured scan.

Plugin limitations remain visible: the sonar-apple test importer could not map every result group, so its test totals are not authoritative. Optional Periphery/MobSF tool execution/parsing did not succeed. Zero reported vulnerabilities is not an exhaustive security audit. Use the native xcresult summaries and test logs for acceptance results.

## Work required before App Store release

1. **Close acceptance gaps.** Resolve the remaining render/UI failures and obtain a fresh green test run. Finish actual widget installation/artwork verification and native menu-bar interaction acceptance. Repeat signed-device smoke checks if source changes.
2. **Create the fresh App Store Connect app record.** Read-only lookup at 10:17 UTC returned no app for `app.hashfleet`. The registered signing identifier and working App Group do not create a store app record. Choose the final product name, SKU, primary locale, category and availability.
3. **Choose the first store version.** The delivered binary is `0.1.0 (7)`. Either create a matching version or choose a marketing release such as `1.0` and rebuild. A version bump is not inherently required simply because this is a new bundle with no uploaded builds.
4. **Prepare metadata and screenshots.** Description, keywords, subtitle as desired, support URL, copyright, category, age rating/content-rights answers, pricing/availability and screenshots for supported device families. The app targets iPhone and iPad. Screenshots must represent the final app, with simulated readings honestly labeled.
5. **Complete App Privacy and publish the privacy policy.** The shipped privacy manifests parse successfully, but they do not replace store disclosure. Audit optional push registration, server logging/retention and any third-party data access before selecting “Data Not Collected.” Confirm a working in-app privacy-policy link and public support/privacy pages.
6. **Complete export compliance.** The app uses cryptographic/system networking facilities. `ITSAppUsesNonExemptEncryption` is not currently declared in the main Info.plist. Determine the appropriate answers and documentation first, then add an accurate declaration if appropriate. No exemption was guessed.
7. **Verify production APNs end to end.** The installed app has a production APNs entitlement, and the example provider topic is `app.hashfleet`. Actual deployed provider configuration and locked-phone delivery were not validated. Confirm the real provider key/topic, registration, opt-out, expiration, and LAN/off-LAN delivery before advertising scheduled summaries. An ASC API key is not an APNs provider key.
8. **Prepare review access.** Provide contact details and clear demo-mode instructions so a reviewer can inspect the app without a miner. Explain local-network permission, hardware confirmation boundaries and truthful background limitations. If Apple requires hardware evidence, prepare a real-device video showing pairing/interaction with the external hardware, not just a screen recording.
9. **Distribute through the App Store workflow.** Validate and upload an App Store distribution build, wait for processing, answer compliance questions, select the build on the version and complete the review submission. Upload/submission/public release still require explicit authorization.
10. **Treat Mac release separately.** `app.hashfleet.mac` and `app.hashfleet.menubar` build and launch locally. Decide Mac App Store versus direct distribution, then complete the relevant signing, sandbox, notarization/store record, privacy and release validation. The CLI is not uploaded as an iOS app.

## Apple references checked October 30, 2026

Primary Apple documentation was consulted for the release checklist:

- Submit an app: `https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/`
- Manage app privacy: `https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/`
- Export compliance overview: `https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/`
- Provide information for a complete review: `https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review`
- App Review Guidelines: `https://developer.apple.com/app-store/review/guidelines/`

## Final targeted UI follow-up

The iPad command finished with exit 65 and a finalized xcresult: nine passed, five failed. Its long post-test delay was simulator diagnostic collection, not additional test execution.

The five unchanged iPhone follow-up tests all executed. The two dashboard/tuning-entry workflows and the restricted demo-summary workflow passed on the requested iPhone 17 Pro simulator. Two assertions still failed:

- `FleetWidgetWorkflowUITests.swift:91`: the installed widget was found, but its separately queried artwork image was not available in the accessibility tree. The artwork transparency check therefore did not complete. This is not proof of an opaque image background.
- `HashFleetUITests.swift:357`: after reopening tuning, the risk acknowledgment was retained, but `tuningSession.payloadUnavailable` was not found. This does not by itself prove a payload was silently staged, but the clean-reopen safety acceptance remains unverified.

The test log records five executed tests with two failures in 485.4 seconds. The shell task then hit its ten-minute limit during diagnostic collection. The incomplete result bundle was not imported into Sonar or represented as a successful run. The orphaned diagnostic collector belonging to that exact task was stopped.

Local iPhone log: `/Users/USER/.jcode/scratch/hashfleet-final-validation/phone-ui.log`. Tests were not skipped, assertions were not weakened, and these failures remain release blockers. No further test or diagnostic process from this validation was intentionally left running.
