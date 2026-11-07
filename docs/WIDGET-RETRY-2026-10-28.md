# Hash Fleet: visual and research retry

October 28, 2026. Follow-up to `62bdc08`, requested at 09:52 UTC: retry what failed and fix supported problems. This report supersedes only the remaining-failure and research-attempt status in the earlier reports. Their historical receipts remain unchanged.

## Scope

- Only the task-owned iOS simulator `D7A757FF-FEC1-4283-A046-0A3322D86DB7` and isolated native test runner were used.
- No miners, SSH hosts, APNs, production notification servers, App Store Connect, physical devices, installed Mac apps, LaunchAgents, production stores or hardware settings were accessed or changed.
- Keep the original component acceptance file and raw Vision harness byte-identical. No whitespace/case normalization, expected-text injection, accessibility substitution or skipped failing cases.
- Preserve unrelated tracked and untracked working-tree changes. No routing/account/pool changes and no push.

## Reproduction and production fix

The first unchanged component rerun, `components-red.xcresult`, reproduced all five issues in the same three methods. The small supplemental activity's units were visible in the actual captured pixels, not missing or clipped, but were much smaller and lower contrast than the number. Raw OCR omitted the complete measurement.

The new `smallSupplementalKeepsMeasurementLegibleAndPrivateAtCompactWidths` regression renders the actual production view at 184 and 320 points. Before the production edit, its exact `2.40 TH/s` assertion failed at 320 points in `compact-red.xcresult`. The 184-point case and both privacy negative controls already passed. That width-dependent result is retained rather than overstated as a universal missing-unit defect.

`FleetSmallSupplementalActivity` now renders its value and essential unit in one semantic, semibold title-style `Text`. Both use the same primary foreground style. The original single-line and privacy-sensitive behavior is preserved, with a minimum scale of 0.8 for compact space. This is a real measurement-legibility improvement, not an OCR transformation. Other activity families, correct power spacing, data, timestamps, networking and refresh behavior are unchanged.

The selected post-fix run, `components-green.xcresult`, executed 19 definitions: 17 passed and two failed with three issues. Despite the filename, the combined command still exited 65. The original supplemental privacy/readability test and the added two-width regression passed. Exported actual regular and redacted images were inspected directly: the value and unit fit, and neither remains readable in the privacy rendering.

### Retained failures

The two original medium/large widget methods still fail three assertions expecting `38W`. The actual UI, production source and raw OCR consistently show `38 W`. That correct spacing already existed at the earlier baseline. The actual medium regular image was also inspected directly. Removing the space to satisfy a stale expectation would degrade the measurement, so production formatting and the original assertions remain unchanged. These failures are not counted as passes.

## Final acceptance after the last source edit

| Check | Observed result | Receipt |
| --- | --- | --- |
| All 16 original mobile suites, including the new compact regression | 164 of 166 Swift Testing definitions passed; only the two original power-spacing methods failed, with three issues; no skipped definitions | `mobile-final.xcresult`, `mobile-final-tests.log` |
| Independent installed widget artwork pixel check in the same command | One XCTest UI test passed, including original corner comparisons | `mobile-final.xcresult` |
| Combined result-bundle accounting | 167 total definitions: 165 passed, two failed, zero skipped; dynamic-parameter executions are not counted as additional definitions | `mobile-final.xcresult` summary |
| Original supplemental activity privacy pair and added compact widths | Passed, including absence of the numeric reading and unit in private pixels | `components-green.xcresult` and final mobile run |
| Strict native build and isolated native tests | Build-for-testing succeeded; 37 definitions in six suites passed | `native-final-build.log`, `native-final-tests.log` |
| Installed Settings/Controls, gallery/Home Screen/return link and synthetic Live Activity lifecycle | Three XCTest UI tests passed, zero failed or skipped; both-appearance navigation, real gallery placement and isolated return link executed | `ui-final.xcresult`, `ui-final-tests.log` |
| Preservation | Original component/harness hashes, unrelated tracked diff hash and all existing untracked file hashes match the pre-edit baseline; index was empty before scoped staging | `worktree-baseline.json`, coordinator preservation verifier |

The complete mobile command remains red. Initial XCTest `Executed 0 tests` lines in the unit-test process are not used as evidence: Swift Testing actually executed all 166 definitions afterward. The separate installed-pixel XCTest also executed and passed. Existing cache/coordinator, opt-out, Demo provenance, original observation time, incomplete/cancelled publication, diagnostics, branding, resource-alpha, report, backup and notification suites were included, not replaced with only the new happy path.

## Research retry: actual routing and outcome

The live configuration was read as `agents.swarm_model = "auto"`, with medium default effort. The offline complex/high advisory was run and its recorded-readiness cautions retained. Two bounded high-effort read-only research workers were spawned without model or account overrides. Actual routes were inspected after spawning.

- The native Claude `claude-opus-4-8` worker completed the newer-widget feature review, then completed a separate bounded LAN/privacy/refresh follow-up. Its actual activity includes primary-source retrieval, SDK inspection and report delivery. Both source-only completion reports were collected with `await_members`.
- The Antigravity `gemini-3.8-flash-tiered` worker failed upstream with HTTP 400 invalid JSON payload before useful research. This is one observed provider failure, not a permanent model-readiness judgment.
- The coordinator independently retrieved the networking, timeline, earliest-date and Local Network privacy documents. Apple JSON responses for larger articles were truncated by the fetch wrapper, so full Markdown was retrieved and read instead. Truncated JSON is not treated as fully inspected evidence.
- No research worker ran tests or changed code. Their reports are not independent runtime certification. The follow-up's heading called the WidgetKit refresh budget “BG scheduling”; the coordinator explicitly distinguishes that widget budget from BGAppRefresh execution below.

### Source-backed recommendations, not newly implemented features

1. **Bounded read-only Refresh AppIntent first.** Apple supports networking while a widget extension has execution, not continual execution merely because the widget is visible [1, 2]. A tapped intent can await a consented, bounded read and finish persistence before returning for the timeline reload [3]. Our current provider is cache-only, and the existing saved-summary Shortcut is not a live LAN fetch. Keep fixed GET endpoints, identity checks, response limits, cancellation, last-valid observations, and opt-in/generation/Demo checks after suspension. Never add hardware-write actions casually.
2. **Foreground Local Network setup before background reads.** TN3179 says extensions generally inherit the container app's privilege. An undetermined background access is denied without a prompt or recorded decision. Establish the permission through a contextual main-app read and handle denial without labeling every miner offline [4]. Simulator execution cannot validate these permission states.
3. **Useful configuration before server infrastructure.** A selected-miner widget needs its own consented, timestamped per-miner cache rather than a relabeled aggregate. Test actual compact, tinted/clear and accessibility layouts before expanding families. The worker's feature review reconfirmed interactive-widget support, the availability-gated portrait family and that WidgetKit push needs additional server/provisioning work. The detailed sources and installed-SDK checks remain in `LOCAL-FIRST-WIDGET-REVIEW-2026-10-28.md`. No new family, live-refresh intent, server feature or continuous processing task is implemented here.

WidgetKit's published typical budget of 40–70 daily reloads for frequently viewed widgets is contextual guidance, not a polling guarantee. Apple identifies performed widget intents among the budget exemptions, but this does not promise unlimited LAN execution or bypass permission/lock restrictions [2, 3]. Separately, `BGTaskRequest.earliestBeginDate` specifies only a lower bound, not a guaranteed start time [5]. Do not present either mechanism as reliable continuous miner monitoring.

### Physical-device acceptance still required

These are planned checks, not executed claims:

| Scenario | Required observation |
| --- | --- |
| First foreground read, permission undetermined | Contextual permission prompt and correct allow/deny handling |
| First background/extension read, permission undetermined | No assumed prompt or fresh observation; preserve last valid cache |
| Allowed and denied containing-app permission | Verify real extension inheritance and no fabricated offline fleet |
| On-LAN, off-LAN and network transitions | Bounded completion/failure with honest observation age |
| Locked/unlocked and foreground/background/terminated | Actual supported interaction/delivery paths, no guaranteed cadence claim |
| Low Power Mode and Background App Refresh disabled | Honest stale state when no work is granted |
| Opt-out or Demo/fleet change during an awaited read | No cache restoration or cross-provenance publication |
| Signed App Group, real widget families and appearances | Actual cross-process delivery, redaction, units, Dynamic Type and tint/clear pixels |

No physical-device, watch mirroring, signed cross-process App Group delivery, remote push or OS scheduling cadence is claimed. The hosted compact render checks are not installed Watch acceptance. The installed synthetic Live Activity workflow does not establish the supplemental mirrored family's delivery.

## Primary sources rechecked by the coordinator

Checked October 28, 2026, about 10:06–10:12 UTC. Feature-specific WWDC/SDK references are in the main research report.

1. Apple, Making network requests in a widget extension: `https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension`
2. Apple, Keeping a widget up to date: `https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date`
3. Apple, Adding interactivity to widgets and Live Activities: `https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities`
4. Apple, TN3179 Understanding local network privacy: `https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy`
5. Apple, BGTaskRequest.earliestBeginDate: `https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate`

## Evidence location

`/Users/USER/.jcode/scratch/hashfleet-retry-20261028-0952`

Original red, added regression red, selected post-fix, full mobile, native and installed UI receipts are retained there. `components-red-all` and `components-green-all` contain exported attachments and manifests. The original fixed supplemental regular/private pair is `DBC15E87-AB84-45A2-880A-63ED1BA67945.png` / `C9AE48BC-2E43-4C90-817B-6475EA34277B.png`; the 184-point regular image is `61363DF3-AA5F-4697-AEFF-1BC43024E94D.png`. Raw research reports, retrieved primary documents and the pre-edit preservation baseline are retained alongside them.
