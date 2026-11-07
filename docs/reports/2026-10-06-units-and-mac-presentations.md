# Units and Mac presentation acceptance, October 6, 2026

## Delivered state

- Production app changes are committed in `e31d669d1451185bf64bcd912dd7ddc6bff905a2`, with the unit/rate changes in its preceding commits.
- The responsive UI-test observation fix is committed in `260ba7a6557a0825327de720c6efd3e755f016d3`. It changes the test query, not production layout or a pass criterion.
- The extended seven-workflow desktop acceptance is committed in `b1da060ea15f21fa5d3662b752460f2c098610ee`. It adds About, Achievements and nested-guide checks without changing production source.
- The owning-screen capture correction is committed in `19bbf4ebedc4246d2dded285aa5bc32d354ab8df`. A fresh all-seven run passed with unchanged acceptance assertions, completing at **12:41:45 UTC**. This changes only UI-test evidence capture, not the installed production app.
- The coverage expansion follow-up is committed in `c1921c9cfc1ebfeca47545719cdba89419b8d86c`. It adds 834 lines of focused tests across 18 existing test files only. No production source, Sonar scope, rule profile or threshold was changed.
- Hash Fleet version `0.1.0`, build `7`, was installed as the primary Mac app at `/Applications/Hash Fleet.app` on October 6, 2026 at approximately **11:46 UTC**.
- The installed inner app reports `app.hashfleet`, build `7`, and passes `codesign --verify --deep --strict`. Its executable matches the signed final ReleaseNoAppPush Mac build by SHA-256.
- The previous build `6` is retained in the owner-private acceptance scratch directory for rollback. User databases, app preferences, app-group containers and the separate menu-bar companion were not replaced or removed.
- The bundled CLI is present and exposed by a new `~/bin/hashfleet` symlink. That path was absent before creation. No existing binary, symlink or shell profile was overwritten.
- A leftover demo acceptance process was closed by its verified exact PID/command. The new primary app was reopened in the background **without testing or demo arguments**. Process inspection confirms a normal main-app process. This is launch evidence, not native visual acceptance.
- The signed DebugNoAppPush iPhone build `7` is built and signature-verified. A fresh authorized-only `devicectl` check at **21:24:35 UTC** found the physical iPhone `YOUR_DEVICE_ID`. Read-only device-info inspection showed `app.hashfleet` version `0.1.0`, build `6`. The build 7 artifact was rechecked as `app.hashfleet`, version `0.1.0`, build `7`, passed `codesign --verify --deep --strict`, and had no production-source changes since `e31d669`. Build 7 was installed without uninstalling, deleting app data, launching, terminating, resetting pairing, or sending arguments. The first concurrent readback observed build 6 before installation completed and was discarded as a race. A sequential readback then confirmed `app.hashfleet`, version `0.1.0`, build `7`. No other phone, pairing, account or simulator was substituted for physical installation evidence.

## Requirements and observed checks

| Requirement | Implementation and validation |
| --- | --- |
| Consistent rate and hardware-unit APIs | Shared Core display/storage contracts, legacy preference migration and boundary/unit tests. User-facing rates use adaptive units. Machine CSV retains its raw numeric units rather than introducing display strings. |
| App-owned Mac pages must not be small centered popovers | Shared page presentation uses a full-window cover only for the desktop branch. Native mobile sheets remain unchanged. Existing system activity/export panels remain native panels. |
| Full-window Add Miner | The desktop-branch UI test opens the real page, verifies its navigation bar spans more than 90% of the app width, dismisses it and observes the Dashboard again. |
| Full-window Settings and usable dismissal | The UI test opens Settings through the real Dashboard settings-menu helper, verifies width, dismisses and confirms it does not immediately reopen. |
| Full-window report PDF | The UI test opens Reports, previews a real generated demo PDF, verifies full width, dismisses, observes the retained report and checks that no export error is present. |
| Full-window About and interactive return | The extended test opens the actual About route, verifies full width, dismisses with its real Done control and requires a hittable Dashboard settings menu afterward. |
| Full-window Achievements and interactive return | The extended test opens the milestone-card route, verifies full width, dismisses and requires the restored Dashboard to be interactive. |
| Nested full-window guide preserves Settings | The extended test opens the guide from Settings, verifies the owning tour occupies more than 90% of the app width and height, closes it, requires the retained Settings Done control to be hittable, then dismisses Settings and checks the Dashboard is interactive. |
| No empty final miner half-row | Immutable card-content snapshots verify paired first/second cards and a third card spanning both columns, with non-overlap and row spacing. |
| Narrow-window reflow | The same test rotates from a 1376-point-wide viewport to 1032 points and verifies all three miner cards share the same horizontal bounds in vertically ordered, non-overlapping rows. |
| Uneven section layering preserves source order | Geometry contracts cover odd counts and substantially unbalanced section heights. Spanning sections are remeasured at the assigned width, and following pairs retain source order. Dashboard, Diagnostics, Reports and Settings use the shared row geometry where applicable. |
| Mobile export behavior remains native | The focused phone-simulator report CSV share workflow passed after the presentation changes. |
| Authorized physical iPhone delivery | The validated signed build 7 was installed to the authorized UDID only, then read back through `devicectl` as `app.hashfleet`, version `0.1.0`, build `7`. |

## Final test and build evidence

| Check | Observed result |
| --- | --- |
| Earlier instrumented app contract run | **754 definitions passed**: 749 Swift Testing tests in 76 suites and five XCTest preference-checkpoint tests. This earlier run is retained as historical evidence, not the current complete-suite count. |
| Current complete app contract suite, 11:56 UTC | **759 definitions passed**: 754 Swift Testing tests in 76 suites and five XCTest preference-checkpoint tests. No failures or skipped definitions. |
| Fresh coverage-bearing app suite, completed 20:17 UTC | **803 native app tests in 76 suites passed** with code coverage enabled. |
| Fresh coverage-bearing Core suite, completed 20:18 UTC | **212 Core tests in 24 suites passed** with SwiftPM code coverage enabled. |
| First native acceptance consolidation | Apple's `xcresulttool merge` combines the fresh 759 app definitions with the original four passing desktop workflows and one passing mobile sharing workflow: **764 definitions / 1,004 parameterized executions**, no failures or skips. All three inputs contain actual Xcode execution coverage. |
| Extended native acceptance consolidation | The fresh seven-workflow desktop bundle replaces the original four-workflow bundle, alongside the same 759 app definitions and one mobile share workflow: **767 definitions / 1,007 parameterized executions**, no failures or skips. The earlier four workflows and the focused guide retry are not merged again or counted twice. |
| Mac-preference revalidation | Five additional focused preference-checkpoint tests passed. The accumulated result bundle reports **759 definitions / 999 executions**, not 759 additional tests. |
| Core full suite | **208 Swift Testing tests in 24 suites plus 23 XCTest tests passed**, both in the normal and coverage-instrumented runs. |
| Original desktop-branch acceptance | **Four UI workflows passed**, zero failures, zero skips. The separately rebuilt focused responsive workflow also passed. |
| Extended desktop-branch acceptance, completed 12:26 UTC | **Seven UI workflows passed**, zero failures, zero skips. A separately rebuilt focused nested-guide workflow also passed. |
| Final owning-screen capture acceptance, completed 12:41:45 UTC | **The same seven UI workflows passed again**, zero failures, zero skips. All original geometry and interaction assertions are retained. The clean capture helper reports screen-image sizes matching the observed app frames. |
| Mobile report-sharing regression | **One UI workflow passed**, zero failures, zero skips. |
| Signed iPhone DebugNoAppPush build 7 | Build succeeded; app signature verified. |
| Signed Mac ReleaseNoAppPush build 7, Designed for iPad | Build succeeded; packaged and installed inner-app signatures verified. |
| Final diff integrity | `git diff --check` and strict SwiftLint passed for the screenshot-helper-only follow-up. An exact diff check confirmed that no acceptance assertion or production source changed. |

The failed nested string predicate `frame.size.width < 1100` did not request usable fresh CGRect geometry in this XCTest run. The replacement reads `app.frame.width` directly, retains the same width bound and timeout, and then executes every original narrower card-frame assertion. No assertion was removed, weakened or replaced with an assumed pass.

Earlier failing result bundles and logs are retained. A simulator accessibility initialization failure is not counted as a source failure or as passing UI coverage.

The first extended run had six passing workflows and one guide-selector failure. Its retained UI hierarchy shows `tour.view` filling the 1032 by 1376 viewport, with the nested sandbox contributing the navigation-bar title `Hash Fleet` rather than the test's assumed `Guided demo`. The corrected test selects the observed stable owning-tour identifier, retains the full-width criterion, adds a full-height criterion and verifies both levels of interactive dismissal. The rebuilt focused guide and then all seven workflows passed. No production presentation change or weakened geometry check was used to resolve this selector mismatch.

## Native Mac validation limit

The attempted native Designed-for-iPad UI runner failed to initialize with `Timed out waiting for AX loaded notification`. Native notification-system tests in that mixed run also failed to obtain the expected host authorization; they are not represented as successful native tests. The later app/preference suites and all seven extended desktop-branch geometry/dismissal workflows passed on native iOS simulators using explicit desktop-layout selection and isolated demo state.

Read-only desktop observation found the main process, but no inspectable native AX window during this follow-up. Consequently **physical Mac WindowServer resize/dismissal, native save panels and OS notification-permission workflows remain unverified for build 7**. Simulator desktop-branch tests and a signed install are not substitutes for that claim.

The corrected independent source review reports no source-confirmed blockers. Its native-runtime concerns are explicitly unverified hypotheses, not confirmed defects or independent runtime acceptance.

## Screen-capture evidence

The landscape app-element captures were not accepted as clean visual proof. In this simulator fixture, `app.screenshot()` produced a rotated crop with a black band and missing right-side content, even though the fresh native frame was 1376 by 1032 points. The original images are retained rather than edited or passed off as unclipped captures.

A read-only capture comparison collected both the main-screen image and the app-element image from the same About and responsive-miner workflows. **Both workflows passed with every original assertion retained.** The independent screen capture showed the complete landscape About page, the two-column first miner row and full-width third miner, and the narrower three-row reflow. The recorded screen-image sizes match the native app frames: 1376 by 1032 landscape and 1032 by 1376 portrait. This isolates the observed padding/cropping to the app-element evidence path in this fixture, not to the rendered app screen.

The final capture helper uses the main-screen capture and records its image size. The diagnostic comparison bundle is preserved. The fresh `desktop-screen-evidence-final.xcresult` run completed at **12:41:45 UTC** with all seven workflows passing and no skips. Its original, unedited captures include complete landscape reading pages and the wide/narrow miner layouts. This is a test-evidence correction, not a production-layout modification or proof of physical Mac WindowServer acceptance.

The final rerun is a separate confirmation of the same seven definitions, not seven additional tests. It was not merged alongside the earlier seven-workflow bundle or counted twice. The authoritative extended-acceptance total remains **767 definitions / 1,007 executions**. The earlier capture-only scan remains tied to `b1da060`; the coverage follow-up below records the later test-only commit and analysis.

## Production-inclusive Sonar analyses

### Earlier production scan

The processed analysis of production revision `e31d669d1451185bf64bcd912dd7ddc6bff905a2` completed at **11:33:04 UTC**:

- Compute-engine task: `103d66c8-df75-4e9f-a8ae-38cffb356b23`, status `SUCCESS`.
- Analysis: `f652e2d9-b4b0-41e3-aba7-f0cf66179d25`.
- **Zero unresolved issues**, reported bugs, vulnerabilities, code smells and security hotspots.
- Reported whole-project and new-code duplication: **0.0%**.
- Production source measures: **255 files / 37,883 non-comment lines**.
- Overall coverage: **39.1%**, with **19,520 uncovered / 32,043 executable lines**.
- New-code coverage: **37.2%**, with **5,868 uncovered / 9,350 executable lines**.
- **The quality gate remains ERROR**, because new-code coverage is below the unchanged **80%** threshold. New-violation and duplication gate conditions pass.

### First consolidated acceptance scan

A follow-up scan of committed revision `ab468a724540512d49d713f62876cfc61b92b143` processed successfully at **12:00:11 UTC**, after the fresh complete app run and Apple's native result-bundle merge:

- Compute-engine task: `598c7d52-20a3-47eb-8f2e-ea7de71f064a`, status `SUCCESS`.
- Analysis: `1611b863-e90c-4359-9fc8-75c47ef23f36`.
- **Zero unresolved issues**, reported bugs, vulnerabilities, code smells or hotspots. Whole-project and new-code duplication remain **0.0%**.
- Overall coverage: **47.6%**, with **16,783 uncovered / 32,043 executable lines**.
- New-code coverage: **48.5%**, with **4,813 uncovered / 9,350 executable lines**.
- **The unchanged quality gate is still ERROR**, because 48.5% remains below the required 80%. No green-gate claim is made.
- The actual native merge combines three passing coverage-bearing bundles. Its owned App/Shared/Widgets/PushProvider report contains **18,474 covered / 51,766 executable target-instrumenter line instances across 198 target-file instances**, not 198 unique source files. The ownership review finds **195 unique owned source paths**, with **18,292 covered / 51,564 executable instrumenter lines** after counting identical complete Shared records once. These native instrumenter counts are not the same denominator as Sonar's project measure.
- The original generic Core coverage still imports **43 owned Sources files**. No covered line was invented for an unexecuted file, and duplicate parameterized executions were not represented as additional definitions.
- The scanner's test importer reports **991 imported executions**, while the authoritative merged Xcode summary reports **764 definitions / 1,004 executions**. Importer/resource mapping limits explain why its count is not used as the actual acceptance total.

The coverage increase comes from consolidating real passing unit and UI execution data, not from changes to scope or the gate. Production source trees are unchanged between `e31d669` and `ab468a7`; subsequent documentation-only corrections do not change those tested source trees. Original input result bundles, earlier scan artifacts and failures remain available.

### Extended seven-workflow acceptance scan

The scan of committed test revision `b1da060ea15f21fa5d3662b752460f2c098610ee` processed successfully at **12:31:03 UTC**. Its production source is unchanged from the signed and installed build 7 revision:

- Compute-engine task: `6009f360-9bee-4efd-8ae1-68459a47e044`, status `SUCCESS`.
- Analysis: `247d99c5-ea18-4bb8-bea7-db62e1b05f43`.
- **Zero unresolved issues**, reported bugs, vulnerabilities, code smells or hotspots. Whole-project and new-code duplication remain **0.0%**.
- Overall coverage: **49.2%**, with **16,271 uncovered / 32,043 executable lines**.
- New-code coverage: **49.3%**, with **4,738 uncovered / 9,350 executable lines**.
- **The unchanged quality gate remains ERROR**, because new-code coverage is still below **80%**. No passing-gate claim is made.
- The actual native merge has **767 definitions / 1,007 executions**, all passing with no skips. The scanner imports **994 executions**, which is not substituted for the authoritative Xcode total.
- The extended native report has **19,648 covered / 51,766 executable target-instrumenter line instances across 198 target-file instances**. These represent **195 unique owned source paths**, with **19,466 covered / 51,564 executable instrumenter lines** after counting the three identical complete Shared records once.
- `FleetGlance.swift`, `FleetSystemIntents.swift` and `FleetWidgetAppearancePolicy.swift` each appear in both app and widget targets with identical complete coverage records. No source-file or hit count is invented for these compiled-target copies. Original result bundles and `xccov` exports remain unchanged, and the unmodified merged bundle is the scanner input.
- The original generic Core coverage still imports **43 owned Sources files**. Parser warnings and unavailable optional analyses remain in the retained log rather than being treated as successful audits.

### Coverage expansion follow-up

The test-only coverage commit `c1921c9cfc1ebfeca47545719cdba89419b8d86c` was validated with the fresh app and Core suites listed above. The ten-agent pass was used to identify disjoint test gaps, then only reviewed, deterministic changes that compiled, passed tests and passed strict SwiftLint were retained. No test was used to weaken a production assertion, exclude a source tree or manufacture a coverage hit.

- A fresh native merge of the 803-test app bundle and the accepted extended native bundle was retained for inspection, but it is **not** used as a Sonar test-result input because the Xcode Tests sensor rejected the merged bundle with a duplicate-measure exception for a test file. The failed scanner attempt is retained as tooling evidence rather than reported as an analysis.
- One bounded fresh UI-only rerun on the coverage commit used the iPhone 17 Pro simulator destination `5AE0257A-7733-4411-9611-25C576DA2B7E`, not the iPad desktop destination used by the accepted run. It executed all seven desktop workflows but failed `testDesktopMinerRowsSpanOddCardAndReflowAtNarrowerWidth` and `testDesktopPDFPreviewFillsWindowAndPreservesReport` because the app remained in a 402 by 874 portrait frame. Its failed result bundle is not used as coverage or Sonar evidence.
- Independent reruns of both failed methods reproduced the same narrow-destination behavior on that iPhone simulator. The accepted result summary identifies the desktop destination as the iPad Pro 13-inch (M5), `991DDFEA-CCCD-4545-B684-F73CAD265E0D`. On that accepted destination, a direct rerun of the two methods passed **2/2**, and a fresh current-checkout rerun of all seven desktop workflows passed **7/7** at **21:05:22 UTC**, with the expected 1376 by 1032 landscape and 1032 by 1376 portrait frames. This correct-destination result is simulator acceptance only and was not merged into the Sonar input.
- The valid follow-up Sonar scan used the accepted `extended-native-acceptance-merged.xcresult` and the existing 43-file generic Core report. Production source is unchanged from the signed build 7 revision, and this input avoids duplicate test measures.
- The valid scan of `c1921c9cfc1ebfeca47545719cdba89419b8d86c` completed at **20:30:27 UTC** with compute-engine task `ab3e5350-f576-42f2-b9f1-6b96a2bfb096`, analysis `2f20efd3-329f-4821-9573-754158627b9d`, status `SUCCESS`.
- Sonar reports **49.2% overall coverage**, with **16,271 uncovered / 32,043 lines to cover**, and **49.3% new-code coverage**. Bugs, vulnerabilities, code smells, security hotspots, duplicated lines and test failures are all **0**. The unresolved issue search returns **0** findings.
- The quality gate remains **ERROR** only because new-code coverage at **49.3%** is below the unchanged **80%** threshold. No scope, gate, threshold or rule was weakened. Honest 100% coverage is not claimed: the current report still has 16,271 uncovered lines, which requires a substantially larger, feature-by-feature test campaign rather than another reporting adjustment.

Production UI remains in `sonar.sources`, together with Shared, Sources, Widgets, MacMenuBar, PushProvider and repository tooling. No source scope, rule, new-code baseline or coverage threshold was weakened. Real Xcode execution coverage and original LLVM physical-line records are used. The scanner's imported test count is not substituted for the authoritative Xcode suite summaries above.

Zero reported findings is not proof of bug-free behavior. The scanner log retains unavailable optional analyzer and parser warnings. In particular, optional Periphery/MobSF and a failed Xcode-warning parsing sensor are not claimed as successful independent audits. The coverage gap is a real remaining gate, not a reason to exclude unexecuted UI or invent line hits.

## Closure audit, October 6, 2026, 20:44 to 20:49 UTC

The follow-up audit exercised the real project interfaces and acceptance bundles instead of relying only on aggregate coverage numbers:

| Requirement or risk | Direct check | Observed result |
| --- | --- | --- |
| Rate and hardware-unit formatting | `FleetAppRateFormattingTests` and `FleetNumericMotionTests` through the `HashFleetNoAppPush` scheme | **16 tests in 2 Swift Testing suites passed**. This is a direct production-test path, not a copied formatter harness. |
| Core public contracts and edge cases | Full `swift test` package run, including API, URL allowlist, malformed/oversized body, cancellation, redaction, address and mining-math cases | **212 tests in 24 suites passed**. The log includes the boundary and rejection cases, with no failures. |
| App integration and changed test surface | Current `HashFleetTests` target through Xcode on the iOS simulator | Swift Testing reported **803 tests in 76 suites passed** and the XCTest harness reported **5 preference-checkpoint tests passed**. |
| Full-window reading pages and dismissal | Accepted seven-workflow native desktop bundle, independent wrong-destination reproduction, then current-checkout reruns on the accepted iPad destination | The iPhone 17 Pro rerun failed because its 402 by 874 portrait frame is not the desktop acceptance destination. The two methods then passed **2 of 2** on the iPad Pro 13-inch (M5), followed by **7 of 7** current desktop workflows passing with 1376 by 1032 and 1032 by 1376 frames. Physical Mac WindowServer behavior remains a separate unverified boundary. |
| Signed packaging and identity | Read-only `codesign --verify --deep --strict` and plist reads for the signed iPhone artifact and installed Mac wrapper's inner app | Both artifacts identify as `app.hashfleet`, version `0.1.0`, build `7`. The iPhone artifact and `/Applications/Hash Fleet.app` both pass signature verification. |
| Sonar quality and gate | Valid Sonar analysis `2f20efd3-329f-4821-9573-754158627b9d` from task `ab3e5350-f576-42f2-b9f1-6b96a2bfb096` | **0 bugs, 0 vulnerabilities, 0 code smells, 0 hotspots, 0 duplication and 0 unresolved findings**. The gate is still **ERROR** solely because new coverage is **49.3%**, below the unchanged 80% threshold. |

The first packaging audit invocation itself used the wrong outer-wrapper plist path and exited nonzero. It was corrected without changing any artifact, then the inner app plist was read successfully and the signature checks passed. This is recorded as a harness correction, not as a packaging pass from the failed invocation.

The audit closes the evidence loop for rate formatting, Core behavior, app integration, signed packaging, Sonar findings and the current seven-workflow simulator desktop acceptance. It does not close the 100% coverage goal or physical Mac WindowServer acceptance: the measured coverage remains **49.2% overall with 16,271 uncovered lines**, and the quality gate remains ERROR solely because new coverage is below the unchanged 80% threshold.

## Authorized iPhone delivery follow-up, October 6, 2026, 21:24 to 21:26 UTC

The user's new delivery request authorized one fresh bounded attempt against the already-authorized physical UDID only. The check at **21:24:35 UTC** found the device. The only installed app inspected was `app.hashfleet`, which reported version `0.1.0`, build `6` before installation.

The validated artifact at `/Users/USER/.jcode/scratch/axe-phone-deploy-20261004/Build/Products/DebugNoAppPush-iphoneos/HashFleet.app` identified as `app.hashfleet`, version `0.1.0`, build `7`. Strict deep code-signature verification passed, and the source-boundary check found no production paths changed since `e31d669`. Because the installed build was `6` and the checked artifact was `7`, installation was an upgrade rather than a downgrade or replacement of a newer build.

The install completed without uninstalling or deleting app data. A readback started in parallel with the install returned the old build `6`, so it was not accepted. The required sequential readback completed afterward and returned `app.hashfleet`, version `0.1.0`, build `7`. The app was not force-terminated or launched, and no demo or testing arguments were sent. The device-info JSON and credential-free command summaries remain under the owner-only scratch directory.

## Post-hardening coverage and bounded security loop, October 6, 2026, 21:50 to 22:05 UTC

The current checkout was revalidated after the ATS and thermal-write changes:

- The fresh `HashFleetNoAppPush` app-unit result bundle reports **825 tests in 76 suites passed**, zero failures and zero skips.
- Its `xccov` report is **36.6547852671% aggregate** because the app-unit run includes unexecuted UI targets. The `HashFleet.app` target is **25.4209263404%**, with **12,607 covered / 49,593 executable lines**. `HashFleetTests.xctest` is **98.6481942296%**, with **14,668 covered / 14,869 executable lines**. This is a real measurement, not a 100% result.
- The built simulator app was read back with `NSAllowsArbitraryLoads=false` and `NSAllowsLocalNetworking=true`. The source fix is committed in `8168cd3` as `security: restrict arbitrary transport loads`.
- The final current-checkout app-unit validation after the thermal change passed **821 tests in 76 suites**, zero failures and zero skips. The final Swift package validation passed **225 tests in 24 suites** across 24 suites.
- The focused thermal regression remains **5 tests in 1 suite passed**; the full app run confirms no broader app-unit regression.
- The SQL wildcard finding in achievement deduplication is fixed in `ca48948`: scoreboard metadata is decoded and compared as a JSON `jobId` value rather than interpolated into a `LIKE` pattern. The focused persistence suite passed **11 tests**, including `%` and `_` job IDs, and the full package suite passed **225 tests in 24 suites** afterward.
- The current app integration suite passed **821 tests in 76 suites** after the Core change. A fresh signed v3 artifact was rebuilt from this checkout and passed strict deep code-signature verification with `NSAllowsArbitraryLoads=false` and `NSAllowsLocalNetworking=true`.
- An attempted iOS 17 confirmation-dialog overload was rejected by the SDK because the dialog-aware overload is iOS 18-only. That change was reverted, leaving the compilable iOS 17 confirmation fallback in place. The detailed dialog behavior remains an iOS 18-only limitation and is not claimed as fixed.

The focused post-sanitization fixture rerun passed **18 tests in 1 suite**. Tracked-file scans found no remaining occurrences of the previously identified private LAN addresses or `squ_` authentication fragments. Documentation-only CLI/help and deterministic fixtures now use TEST-NET placeholders; runtime fleet identities were not changed.

A bounded ten-agent read-only security loop reviewed build settings, networking, input parsing, storage, dependencies, address validation, UI/deep links and authorization paths. The confirmed high-severity ATS issue, normal-mode thermal confirmation risk and SQL wildcard deduplication risk were addressed as above. Other reviewers found no confirmed exploitable issue in their scoped input, address/pool, UI/deep-link, notification or redaction paths. Remaining lower-risk recommendations are journaled for follow-up: validating destructive packaging-script environment overrides, pinning and verifying the Sonar plugin download, reviewing telemetry/backup persistence and diagnostic SSID disclosure. The audit was read-only except for the three validated remediations above.

A fresh Sonar publish was attempted against the post-hardening result bundle, but the scanner stopped before analysis because `SONAR_TOKEN` is absent from this session. The latest valid published analysis remains `2f20efd3-329f-4821-9573-754158627b9d`: zero bugs, vulnerabilities, code smells, hotspots, duplication and unresolved findings, with **49.2% overall / 49.3% new-code coverage** and an **ERROR** gate only for the unchanged 80% new-code threshold. The 100% coverage request therefore remains open, and no Sonar 100% or green-gate claim is made.

The current signed post-hardening phone artifact identified as `app.hashfleet`, version `0.1.0`, build `7`, passed strict deep code-signature verification, and retained local networking while disabling arbitrary loads. The later v3 rebuild also identifies as build `7` and includes the SQL hardening. The sequential install attempt at approximately **22:04 UTC** was blocked by CoreDevice error 4016 because the authorized physical iPhone was `unavailable`; a read-only `devicectl list devices` confirmed that state. No launch, erase, pairing reset, termination or argument injection was performed. The earlier sequentially verified build 7 installation remains the last accepted phone delivery, but neither post-hardening artifact was read back on the phone.

## Private evidence and safety boundary

Owner-only artifacts are in `hashfleet-units-mac-20261006`: Core logs and original coverage, app result bundles, `desktop-ui-final.xcresult`, final screenshot attachments, `mobile-share-final.xcresult`, signed build/package outputs, rollback app, and credential-free `sonar-final-summary.json` with API responses. Production signing artifacts reside in the existing dedicated phone/Mac build directories.

The consolidated follow-up additionally retains `app-units-current-coverage.xcresult`, `current-native-acceptance-merged.xcresult`, their test/coverage JSON exports, `sonar-current-merged.log` and credential-free `sonar-current-merged-summary.json` plus API responses. The scanner log also retains out-of-scope vendored Lucide/GRDB coverage-resource warnings instead of suppressing them.

The extended follow-up retains the failed `desktop-ui-extended.xcresult` and its guide hierarchy, the passing `desktop-guide-stable-selector.xcresult`, the all-seven `desktop-ui-extended-final.xcresult` with attachments, `extended-native-acceptance-merged.xcresult`, ownership/count JSON and `sonar-extended-merged-*` scanner manifest and API evidence. The ownership validator checks the exact three identical Shared target copies before producing unique-path summary totals, without rewriting any native coverage input. The passing `desktop-screen-capture-comparison.xcresult` retains both capture paths and the original landscape/portrait frame assertions. The final checkpoint additionally retains `desktop-screen-evidence-final.xcresult`, `desktop-screen-evidence-final-summary.json`, `desktop-screen-evidence-final.log` and eight unedited images in `desktop-screen-evidence-final-attachments/`, one for each reading-page workflow and both widths of the miner workflow.

This software validation/delivery follow-up did not issue miner configuration changes, restart miners, flash firmware, change wiring or alter fleet watchers. Displayed miner readings in acceptance captures are explicit demo fixtures, not fresh hardware status. No credentials, wallet addresses, raw telemetry exports or private database contents are included in this report.
