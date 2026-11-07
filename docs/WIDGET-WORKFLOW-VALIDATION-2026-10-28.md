# Widget and local-refresh workflow validation

October 28, 2026. Follow-through to `84afbf8` and `e858a5b`, scoped to code, private fixtures and the owned disposable simulator. This is not a live-fleet, APNs delivery, installed-Mac replacement or physical-phone report.

Historical workflow receipts below are retained as observed. The later 09:52 UTC retry, production supplemental-measurement readability fix, remaining two power-spacing tests and successful source-only research retry are documented in `WIDGET-RETRY-2026-10-28.md`.

## Scope and safety

- Preserve bundle IDs, widget kinds, URL routing, App Group/storage keys, original observation timestamps and Demo provenance.
- Do not contact miners, SSH hosts, notification servers or App Store Connect. Do not change hardware, APNs settings, entitlements, installed Mac apps, LaunchAgents or the operator's data.
- Use private preferences and intercepted HTTP fixtures for app/cache tests. Simulator UI launches use `--ui-testing`; widget links are tapped only while that isolated app remains alive.
- Preserve unrelated working-tree changes and all existing acceptance assertions. A successful source build or resource-alpha test is not evidence that installed WidgetKit pixels are correct.

## Observed regressions and fixes

### Revoked sharing during a retained publisher's read

Two coordinators can outlive one another. The background publisher previously retained its initialization-time sharing consent. An intervening foreground opt-out cleared the cache, but the retained publisher could restore the next reading.

The original new regression ran red with three consent/cache failures in `consent-red2.xcresult`. `FleetGlanceCoordinator.publish` now re-reads consent immediately before its synchronous aggregate cache write. There is no suspension between the check and that write. Cache completeness, observation time, reload throttling and existing Live Activity behavior remain separate.

`workflow-green1.xcresult` then passed 56 test definitions in three suites, including the same revocation assertions, intercepted HTTP polling, serialized cross-module cache decoding, the production provider's fresh/stale timeline, cancellation, incomplete telemetry, both Demo mismatch directions and privacy rendering. These are in-process private-cache tests, not signed App Group cross-process delivery.

### Oversized artwork blocked fresh WidgetKit archives

The actual widget gallery, Home Screen placement and return link passed in `ui-widget2.xcresult`. Visual inspection nevertheless showed a black square around the miner artwork on a white widget.

Source and compiled-extension alpha checks passed, including `Opaque=false` in the actual extension catalog and identical decoded artwork in the test framework and embedded production extension. The added installed-pixel assertion then failed in `widget-alpha-red.xcresult`: the artwork corner was `[0, 0, 0]` and the surrounding widget canvas was `[255, 255, 255]`. A full-size resolved `CGImage` candidate did not fix the installed assertion. It was reverted rather than retained as an unverified workaround.

Removing only the app on the owned disposable simulator forced a fresh instance. That instance could not become readable. Its actual system log, preserved in `widget-startup-system.log`, reported `WidgetArchiver.ArchivingError.imageTooLarge`: the 1254 by 1254 source totaled 1,572,516 pixels, exceeding the observed small-widget allowance of 1,069,415.6 pixels. This establishes an archive failure and explains why a passing compiled-alpha check could coexist with an older installed image. It does not establish a general named-image alpha defect.

`FleetWidgetBrandAssets.thumbnail` now rasterizes the unchanged approved artwork at its actual display resolution, capped at 256 pixels per dimension, with an explicitly nonopaque renderer and explicit appearance selection. A 52-point mark at 3x becomes 156 by 156 pixels. Tests cover both appearances and color/template variants, transparent corners, invalid sizing and the upper bound.

The final fresh-instance installed workflow passed in `ui-final.xcresult`, together with both-appearance Settings/Controls navigation and the synthetic sample Live Activity start/Home Screen/return/stop workflow: three UI tests, zero failures. The unchanged installed artwork assertion now passes all four corner comparisons. The actual 54-by-54 Home Screen crop has `[255, 255, 255]` at every checked corner and 1,273 distinct colors, and visual review of the full screenshot confirms the approved miner mark without a black tile. Gallery placement and the deep link back to the still-running isolated app also pass. This establishes the tested full-color Home Screen path, not every installed family or tinted/clear/Lock Screen appearance.

### Stale accessibility copy

The visible stale status already told the person to open the app to refresh. The shared accessibility policy still claimed that background refresh was pending. The added spoken-summary assertions actually ran in `branding-a11y-alpha-red.xcresult` and failed twice. The shared policy now says `Last known · open app to refresh`, and both original new assertions pass in the final full mobile run. A prior method-only Swift Testing filter ran zero tests and is explicitly not counted as a red reproduction.

## Acceptance matrix

| Requirement | Observed check | Evidence/state |
| --- | --- | --- |
| Revocation survives an in-flight background read | Two retained coordinators, opt-out, publication and provider read | Red with original assertions, then green |
| Complete local readings reach the real provider | Intercepted HTTP poll, coordinator persistence, separate-module decode and production timeline/view | 56 definitions in 3 suites passed |
| Partial, cancelled and cross-Demo readings cannot overwrite the cache | Actual private-cache/provider boundary tests | Passed in workflow run |
| Honest age, no invented timestamps and preserved reload policy | Freshness boundary, stale entry, exact 15-minute provider policy and original observation time | Passed in workflow/provider runs |
| Widget artwork alpha survives packaging and rasterization | Actual framework and embedded-extension assets, display-resolution/cap/alpha checks | Passed in the final mobile run |
| Installed gallery, placement and return link work | Actual SpringBoard/WidgetKit UI workflow | Passed after a fresh install in `ui-final.xcresult` |
| Installed artwork has no opaque background tile | Cropped artwork corners compared against actual widget canvas | Red reproduced, archive cause established, original pixel assertions now pass |
| Sharing remains opt-in and system labels say Hash Fleet | Installed Settings/Controls navigation in both appearances | Passed in `ui-final.xcresult` |
| Sample Live Activity lifecycle does not enable real widget sharing | Installed start/Home Screen/return/stop workflow and unchanged sharing switch | Passed in `ui-final.xcresult`, synthetic UI-test lifecycle only |
| Native shared layout, separator clearance, PDF and background helpers remain compatible | Strict native build and isolated runner after the final shared-source fix | Build passed, 37 definitions in 6 suites passed |
| Existing exact visual/OCR acceptance remains intact | Original component/rendering suites, unchanged assertions and recognition | 162 of 165 definitions passed in 16 suites, 3 component tests retain 5 exact OCR issues |

The five remaining assertions are exactly observed, not rewritten: the medium widget fails twice and the large widget once because they expect `38W` while actual text and OCR show `38 W`. The supplemental activity fails twice because OCR omits the visibly rendered `TH/s` beside `2.40`. Actual exported final pixels show both measurements and units without clipping. The original assertions and Vision recognition remain unchanged, so the full mobile command exits 65. Full automated visual acceptance is not claimed.

## Independent review claim audit

A further post-commit audit at `aab9a47` checked the reviewer’s findings, actual report tool call and corrected final response separately. The first claim that `142 of 142 assertions pass` was unobserved, rejected and explicitly retracted by the reviewer. Its eleven-call activity feed contains source reads, todo updates and one `swarm report` call, not test execution. The report call is recorded as delivered, and `await_members` returns the corrected source-inspection-only final response. Delivery is established, but it is not evidence for the withdrawn pass count.

The corrected report identifies the historical stale spoken-copy mismatch, but two details still require rejection. It annotates the visible-status assertion as failing, whereas `branding-a11y-alpha-red.log` records the actual failures at `FleetWidgetBrandingTests.swift:31` and `:32`, both for `presentation.accessibilitySummary`. Its proposed alternative of adding an unobserved pending claim to the visible copy would not be an acceptable fix. This was a real user-facing accessibility correctness bug, resolved by the shared policy’s honest `open app to refresh` copy in `aab9a47`, not a reason to weaken the visible-copy assertions.

The coordinator independently mapped the remaining static review claims to production behavior and actual checks:

| Review claim | Rechecked production boundary | Observed verification |
| --- | --- | --- |
| Retained consent is refreshed before writing | `FleetGlanceCoordinator.swift:113-118`, MainActor with no suspension between preference read and cache write | Original retained-publisher opt-out assertions pass |
| Fresh and stale entries retain observation time | `FleetWidget.swift:32-45`, same cached payload in both entries and unchanged 15-minute policy | Real-poll and incomplete-poll provider assertions pass |
| Injectable test storage preserves production behavior | Provider defaults to `.shared`; private fixture uses distinct preference/cache suites and a separately compiled reader | Serialized cache contract and provider tests pass |
| Partial, cancelled and cross-Demo readings fail closed | `FleetBackgroundRefreshDiagnostics.swift:114-117`, with coordinator cancellation checked before writing | Completeness, cancelled-publication and both Demo-direction assertions pass |

The fresh coordinator-run `reviewer-validation.xcresult` / `reviewer-validation-tests.log` passed **68 test definitions in five suites**, with zero failed and zero skipped in the result-bundle summary. All five selected suites actually executed: `FleetGlanceWorkflowTests`, `FleetGlanceTests`, `FleetTelemetryCompletenessTests`, `FleetBackgroundPublicationTests` and `FleetWidgetBrandingTests`. The tests include the original spoken-copy assertions, actual packaged artwork, both-appearance compositing and the production cache/provider path. The fixture’s URLProtocol accepts every request and fails unmatched requests locally, without a network fallback. The exact corrected reviewer response and machine-readable observed result summary are retained as `reviewer-corrected-completion-report.txt` and `reviewer-validation-summary.json` in the task artifact directory.

This audit changed no production source or acceptance assertion. These 68 definitions are a selected follow-up run, not a replacement for the full 165-definition mobile command, which remains red with the same five OCR issues described above. The installed-widget UI receipts remain those already recorded, not an additional installed-family acceptance claim. Physical-device, signed cross-process and OS-cadence limits remain unchanged.

## Evidence locations and limits

Task artifacts: `/Users/USER/.jcode/scratch/hashfleet-workflow-20261028-0714`. Build products remain in the pre-existing task-owned `hashfleet-audit-fixes-20261027-1941` scratch build directories. Earlier failure receipts remain available, including the initial consent harness compile issue and offscreen system-settings navigation failure.

Final receipts include `mobile-final.xcresult`, `mobile-final-tests.log`, `native-final-build.log`, `native-final-tests.log`, `ui-final.xcresult` and `ui-final-tests.log`. `ui-final-widget-render` contains the real gallery, full Home Screen, cropped artwork and return-link images. `mobile-final-component-render` contains the retained component/OCR failure captures. The last verifier, after correcting only the new tiny-canvas test's safe-area framing, is `mobile-final2.xcresult` / `mobile-final2-tests.log`: the same 165 mobile definitions ran with only the same five issues in three original component tests, and the independent installed-pixel recheck passed. No skipped or zero-test run is substituted for this final result.

The simulator cannot establish physical Local Network permission prompts/denials, lock-state behavior, discretionary background execution cadence, signed cross-process App Group sharing, remote notifications or APNs delivery. The installed widget intentionally shows its honest empty state because the unsigned UI-test app does not share aggregate data. Fresh cached rendering is covered by private, separately compiled module tests rather than misrepresented as a signed cross-process test.
