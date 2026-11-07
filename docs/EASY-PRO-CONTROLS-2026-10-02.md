# Hash Fleet Easy and Pro controls

Research observation date: October 2, 2026.

## Latest repository validation: October 2, 2026 at 15:31 UTC

**The custom-editor frame warning is eliminated on the tested repository/simulator path**, through the minimal toolbar-placement change in commit `2a50c5d`. Exact B/A/B controls recorded four warning-free candidate repetitions versus two warning-producing restored-baseline repetitions. The stronger actual-app layout regression and subsequent complete acceptance also had zero editor frame warnings.

The complete run finished at **15:31:47 UTC: the same 694 unique tests passed, zero failures and zero skips**, including all eight mapped UI cases and 11 native custom-JSON cases. **One separate background-thread publishing warning remains unresolved**, so this is not globally warning-free acceptance. Format/Done remain reachable with the software keyboard visible, exact UInt64/unknown-field staging and observed typed confirmation remain intact, and editor cancellation sends no writes. The inline title truncates to `Custom JS...`, an acknowledged visual tradeoff.

**This later fix is repository-only and is not in the installed/frozen phone build 3.** Original user-owned source changes and the signed phone artifact are preserved. No phone reinstall/launch, miner/M1 request, hardware operation or scheduled retry was issued by this diagnostic. See [the complete layout diagnostic and updated D1–D6 observations](ADVANCED-EDITOR-LAYOUT-2026-10-02.md) for exact controls, finalized results, actual screenshots and limitations. Earlier unresolved/no-retained-fix statements below are timestamped history, not the current repository result.

## Goal and safety boundary

Make everyday edits easier to understand, and expose detailed miner-reported information without making the user enable Developer tools just to inspect it. Easy and Pro are presentation choices, not permission levels. This task changes app UI only. It does not authorize writes to the physical fleet, recovery actions, power changes or firmware deployment.

The canonical fleet safety reference remains `/Users/USER/ESP-Miner-profit-switch/docs/FLEET-OPERATIONS-PLAYBOOK.md`. Its current-state notes are not live telemetry. In particular, no competitor control range establishes a safe range for the user's boards.

## Competitor findings

The research swarm inspected primary project pages, public source where available, and publisher screenshots. These are UI/source observations, not hands-on tests of the competitors or proof of their internal safety logic. Store listing dates varied across locales, so this document makes no latest-release claim.

| App | Observed presentation pattern | Hash Fleet decision |
| --- | --- | --- |
| HashMonitor, `vcazan/HashMonitor`, a HashRipper fork | Desktop list/detail/resizable inspector, mobile grouped metrics and settings sheets. Public iOS settings source has fixed frequency and voltage slider ranges. | Borrow progressive disclosure and grouped settings, not electrical ranges or automatic recovery. |
| Hashlink, WantClue Technologies | Publisher screenshots show a four-stat fleet overview, compact device cards and detailed electrical/cooling metrics. | Keep everyday controls compact, while allowing a fuller read-only inspection view. Closed-source control safety was not verified. |
| SoloDeck | Publisher pages/screenshots separate miner-estimated power from smart-plug measured power, offer deeper hardware details, and show address masking. | Label observed versus configured values honestly. Preserve privacy and do not imply wall measurements or supervisor state that Hash Fleet has not observed. |

A specific exclusion: HashMonitor's inspected iOS source defines a 1085–1350 mV voltage slider and a 495–1000 MHz frequency slider. These source constants are not a board-specific safety policy and must not be copied into Hash Fleet. The observation does not establish how every competitor operation behaves.

### Primary sources and screenshot provenance

- HashMonitor repository: `https://github.com/vcazan/HashMonitor`
- Desktop navigation/inspector source: `https://raw.githubusercontent.com/vcazan/HashMonitor/main/app/HashRipper/HashRipper/MainContentView.swift`
- iOS detail source: `https://raw.githubusercontent.com/vcazan/HashMonitor/main/app/HashRipper-iOS/HashRipper-iOS/Views/MinerDetailView.swift`
- iOS settings source: `https://raw.githubusercontent.com/vcazan/HashMonitor/main/app/HashRipper-iOS/HashRipper-iOS/Views/MinerSettingsSheet.swift`
- iOS detail screenshot: `https://raw.githubusercontent.com/vcazan/HashMonitor/main/screenshots/ios-miner-detail.png`
- iOS settings screenshot: `https://raw.githubusercontent.com/vcazan/HashMonitor/main/screenshots/ios-miner-settings.png`
- Hashlink US publisher listing: `https://apps.apple.com/us/app/hashlink/id6757280779`
- Hashlink project page: `https://hashlink.space`
- Hashlink dashboard screenshot: `https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/eb/a1/20/eba1206a-a734-3f2a-1539-4f6dcc1e6d15/6.3_iphone_-_2.jpg/600x1334bb-60.jpg`
- Hashlink device screenshot: `https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/a9/00/7b/a9007b1a-e075-16df-06c9-8df15e34d2ba/6.3_iphone_-_1.jpg/600x1334bb-60.jpg`
- SoloDeck publisher site: `https://solodeck.app`
- SoloDeck publisher listing: `https://apps.apple.com/app/id6777678140`
- SoloDeck hardware screenshot: `https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/94/a1/0c/94a10c72-2570-7608-32a7-49be977ed84d/01-fleet-grid.png/600x1300bb-60.jpg`
- SoloDeck detail screenshot: `https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/d7/ce/28/d7ce2868-9c8a-b253-6a0d-eb15d330483c/04-every-stat.png/600x1300bb-60.jpg`
- SoloDeck power screenshot: `https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/e3/d8/32/e3d83262-45db-9a2f-b933-9ef3c20c06cc/03-running-cost.png/600x1300bb-60.jpg`

No competitor assets or implementation code were copied into the app.

## Implementation contract

### Easy

- A visible Easy | Pro selector on the miner settings hub. Normal app mode starts in Easy. Developer users retain their existing detailed default, now called Pro.
- Existing device name, on-device history, automatic fan and temperature-target inputs stay together.
- A draft shows a singular/plural pending-change count and each reported previous value alongside its proposed replacement. Unknown previous values say `Not reported`.
- General, Pools and Display remain explicit routes to the existing forms. Restart remains a reviewed request, not a one-tap hardware action.
- Editing does not transmit anything. The unchanged changed-field builder emits the same exact JSON as before, through the existing endpoint review and confirmation machinery.

### Pro

- Detailed read-only identity/firmware, configured versus measured clocks/voltage, cooling, fan tachometer and hardware-error observations.
- Existing comprehensive diagnostics and compatibility inspection remain available without Developer tools.
- Missing measurements are not invented. Demo, cached and reconnecting observations are labeled, including reading age where available.
- The selector never changes `developerModeEnabled`, clears a draft or enables a power-user session.
- Manual tuning, raw/custom JSON, firmware and other advanced write entry points retain the existing Developer visibility and confirmation gates. Normal Pro hides those entries entirely.

### Deliberately excluded

No generic performance presets, automatic recovery, supervisor-state inference, one-tap pool failover, one-tap self-test/OTA/restart or multi-miner writes. No client, mutation preflight, payload allowlist or confirmation-policy changes.

## Requirement-to-check mapping

| Requirement | Check |
| --- | --- |
| Pending changes describe reported before/proposed after | Native `MinerEasySettingsTests`, including missing previous values and automatic-fan-only payloads |
| Payload stays changed-field-only | Native Easy, tuning, swarm settings and safety suites |
| Selector does not grant write permissions | Loopback `ExpertModeUITests` checks absent tuning/advanced/power-user entries and an empty write journal |
| Switching presentation keeps an unsent draft | Loopback Easy → Pro → Easy test |
| Pro exposes comprehensive read-only diagnostics | Loopback diagnostics disclosure and electrical-section assertion |
| Reviewed restart remains blocked before confirmation | Existing Normal typed-APPLY and Developer risk-acknowledgement acceptance tests |
| Stale/cached/offline data remains non-writable | `MinerSafetyTests` freshness/preflight cases and real-mode offline UI acceptance |
| Existing dashboard update remains integrated | Dashboard, monitoring, persistence and ticker regressions |
| New app is on the paired phone | Signed build verification, devicectl install receipt and installed-app inventory |

## Validation record

- Earlier targeted acceptance: all 155 tests passed with no failures or runtime warnings in `ControlsAcceptanceFinal.xcresult`: 154 native tests plus the Easy/Pro draft-preservation and read-only diagnostics UI case. Parameterized test invocations are not counted as additional tests here. The later whole-result audit below supersedes this targeted run as the broadest validation.
- The consolidated eight-case UI run passed all eight cases with zero failures in `ControlsUIConsolidated.xcresult`. It also reported one `Invalid frame dimension (negative or non-finite)` runtime warning while opening the custom JSON editor. The same warning appears in the earlier UI bundle. This is not represented as warning-free runtime acceptance.
- The finite-viewport experiment was rejected. Both fresh-process repetitions of the affected loopback case passed but each still reported the same invalid-frame warning in `CustomJSONFiniteViewport.xcresult`. The editor source was restored exactly, so no speculative layout fix or request/permission/dispatch change is retained. The warning has no creating-workspace source location in the result bundle, and its root cause remains unproven. The bounded triage conclusion below records the additional rejected toolbar hypothesis without claiming a fix.
- Iteration findings were corrected without altering mutation permissions or payload semantics. An unreported previous hostname now says `Not reported`. Explicit accessibility containers preserve segmented-control and nested diagnostics identifiers. The fixture now asserts exact replacement of `loopback-before` with `loopback-draft` instead of accidentally prepending text at the leading caret. The Easy history menu stays on one line rather than overlapping its divider.
- Final Easy and Pro screenshots from the passing UI case were exported and visually inspected. Easy shows the exact draft, one pending change and a before/after row. Normal Pro shows reported values, `Not reported` omissions and a read-only diagnostics route, without advanced write entries. Screenshot values come from the loopback fixture, not live fleet telemetry.
- Independent final diff review: approved with no write-permission blockers. This is source review, not a claim that the app enforces every physical board's electrical limits.
- The original 21-file uncommitted update has the same SHA-256 diff fingerprint as before this task: `5ad2867a3502ba5d5e1941540aad86d90d68b91517c178791b56d4a7bc56abbf`.

### Whole-result audit: October 2, 2026

The restored final project completed the entire native app test target and all eight mapped end-user UI cases at **13:58 UTC**: **694 unique tests passed, zero failures and zero skips**. The run reported **two runtime warnings**, not warning-free acceptance: the known custom-editor frame warning and a background-thread publishing warning attributed to the fleet navigation integration test. Neither root cause nor production harmlessness is claimed.

The audit expanded the actual Easy/Pro UI checks before running them: all reported value rows and missing-value omissions, 0/1/2 pending changes, exact previous/proposed values, a two-field draft retained through mode/navigation changes, exact combined staged JSON, diagnostics and compatibility without Developer permissions, and cached Pro → Easy read-only behavior. Their observed public outputs and wire journals passed, and the screenshots from this complete run were visually inspected. The map and outcomes for **P1, E1–E19 and D1–D6** are in [the whole-result acceptance audit](EASY-PRO-WHOLE-RESULT-AUDIT-2026-10-02.md), including the explicit unsatisfied warning-elimination requirement D6.

At **13:50 UTC**, fresh real-phone inventory again verified **0.1.0 build 3** and the exact signed artifact was reverified. A successful process query returned an empty process array, so no current foreground/running state is asserted. Physical-screen inspection was blocked by the existing iPhone Mirroring authentication screen, without bypass or credential entry. Real-miner mutations remain unauthorized and were not substituted with fixture claims. At **14:10 UTC**, the original 21-file diff fingerprint and exact restored editor/package integrity still matched. Only the stronger audit tests and records are retained, with no new app-code experiment or replacement phone package.

### Advanced editor warning: historical bounded triage at 13:26 UTC

**At that cutoff, the known issue remained unresolved.** Closing this initial bounded investigation was not a warning fix or a claim that the runtime was warning-free. The later repository-only placement fix and complete acceptance above supersede this historical editor conclusion. The issue is reproducible in the Developer-only custom JSON acceptance path on the iOS 26.4.1 simulator. It has not been visually or diagnostically reproduced on the physical iPhone.

The warning appears on entry into the custom JSON editor, before typing. Source inspection covered `MinerCustomJSONView.swift`, `MinerCustomJSONRoute.swift`, the settings navigation hosts, and `MinerNavigationTitle`. No arithmetic-derived frame was found in the editor or route. This narrows the inspection but does not attribute the warning to a particular framework or component, and the result metadata supplies no creating-workspace source location.

| Hypothesis | Fresh-process results | Decision |
| --- | --- | --- |
| Replace the editor's minimum height with fixed height 220 | 2 passing runs, 2 invalid-frame warnings in `CustomJSONFiniteViewport.xcresult` | Rejected and exactly reverted |
| Remove only the keyboard-toolbar `Spacer`, retaining Format/Done and all review behavior | 2 passing runs, 2 invalid-frame warnings in `CustomJSONToolbarSpacer.xcresult` | Rejected and exactly reverted |

The additional two-run experiment finished on October 2, 2026 at 13:25 UTC. Its unchanged safety assertions verified the Done control, formatting, exact unknown-key/UInt64 staging, typed APPLY despite an armed native power-user session, cancellation, and an empty loopback write journal. Passing those assertions does not prove the warning harmless.

At 13:26 UTC, `git diff --exit-code -- App/Features/Miner/MinerCustomJSONView.swift` verified exact source restoration, and the original 21-file diff still matched `5ad2867a3502ba5d5e1941540aad86d90d68b91517c178791b56d4a7bc56abbf`. No layout patch or new app artifact was retained. The installed build 3 remains the validated controls artifact. The overlong read-only worker was stopped without a usable causal report, so no independent warning diagnosis is represented as approved.

This initial investigation stopped at that evidence boundary rather than committing speculative changes. At that time, no causal fix was supported, so the issue was retained while the requested Easy/Pro implementation and phone delivery were complete. The later controlled toolbar-placement result is documented separately above, without erasing the rejected experiments or claiming a framework-internal diagnosis. The private experiment log and summary are `custom-json-toolbar-spacer.log` and `custom-json-toolbar-spacer-summary.json`.

### Publishing warning: bounded follow-up

On **October 2, 2026 at 14:28 UTC**, the unchanged app-hosted integration suite reproduced the background-thread publishing warning in two fresh app processes, with **four warning lines total**. Both logs contain an 11-test passing summary, but the overall command reached its **300-second timeout** and its result bundle was not finalized. This is diagnostic evidence only, not another successful acceptance run or an increase to the finalized **694 unique tests** above.

An independent read-only source review was checked against the actual code. The integration test uses private defaults, while the app guards on the standard pending marker before changing navigation state. Therefore the notification alone does not prove those state assignments caused the warning. The exact publisher, production callback thread, production impact and root cause remain unproven. No test or app-source fix, scheduler change or warning suppression was retained.

At **14:42 UTC**, the original 21-file source diff and the exact signed build-3 artifact still matched their recorded fingerprints. No phone reinstall, actual miner/M1 request, additional runtime probe or scheduled retry was performed by this follow-up. At that cutoff, both known runtime warnings remained unresolved. See the [whole-result acceptance audit](EASY-PRO-WHOLE-RESULT-AUDIT-2026-10-02.md) for exact counts, source references and the incomplete-result limitation. The delivered controls and the read-only phone checklist below are unchanged.

### Phone delivery

The initially requested update was installed and verified as version 0.1.0, build 2. Its launch attempt was denied because the phone was locked. No uninstall or reset was performed, and byte-for-byte preference preservation has not been independently verified.

The later Easy/Pro build-3 attempt using the explicit iPhone destination failed because Xcode could not reach the phone, not because of a compilation error. Retrying with the previously successful `generic/platform=iOS` destination succeeded. The resulting Hash Fleet 0.1.0 build 3 passed strict deep signature verification.

The initial build-3 installation attempt failed before installation with CoreDevice error 4016: trusted connectivity and device services were unavailable. Both CoreDevice and Xcode's read-only device inventories then reported the phone unavailable. CoreDevice's recorded details reported it already paired with Developer Mode enabled; USB discovery found no connected iPhone. No reset, unpairing, new trust grant or developer-setting changes were attempted.

Before successful delivery, build 3 was captured and strictly reverified in a fixed independent copy at `/Users/USER/.jcode/scratch/hash-fleet-controls-20261002-1128/phone-build3-ready/HashFleet.app`. The finite-height experiment was reverted, so this artifact still matches the validated controls implementation. The October 2, 2026 12:34 UTC read-only connection check reported the phone unavailable; the successful follow-through below supersedes that historical blocker.

The replacement bounded retry (`sched_8da98847`) ran on October 2, 2026. At 12:52 UTC, a fresh CoreDevice listing showed the iPhone **available and paired**, superseding the earlier unreachable state. At 12:53 UTC, the required pre-install app-inventory query was blocked: developer disk image mounting failed with CoreDevice error 12040, caused by error 10003 because the device was still locked.

Since current installed-app inventory could not be read on that scheduled retry, the no-downgrade guard could not be verified. No build-3 installation or launch was issued during that retry, no lock bypass or trust reset was attempted, and no further retry was scheduled. At that point, initial build 2 remained the last verified installed version. Delivery was correctly left pending until the user requested continued work.

### Successful follow-through: October 2, 2026

- At 13:11 UTC, the paired phone was available and a fresh app inventory succeeded, showing `app.hashfleet` version **0.1.0 build 2**. This established the no-downgrade precondition.
- At 13:13 UTC, the exact captured artifact passed `codesign --verify --deep --strict`, bundle/version checks, and executable SHA-256 verification: `185a21797e8650caebce9d11c7ad140f6e7e92d52cb2aff2b2d5e03b5296db08`. Standard devicectl installation succeeded without an uninstall or reset.
- At 13:14 UTC, a separate installed-app inventory verified **Hash Fleet 0.1.0 build 3** on the paired iPhone.
- At 13:15 UTC, devicectl successfully launched `app.hashfleet`. This proves installation and OS launch, not a visual inspection of the physical-phone dashboard or exact preference preservation.
- Unique receipts: `phone-connectivity-followthrough-20261002-1311.json`, `phone-inventory-followthrough-20261002-1312.json`, `phone-install3-followthrough-20261002-1313.json`, `phone-inventory-after3-followthrough-20261002-1314.json`, and `phone-launch3-followthrough-20261002-1315.json` in the private controls evidence directory. No protection bypass, pairing/trust/developer-setting change, actual miner mutation, or additional scheduling was performed.

## Phone acceptance checklist

These are read-only inspection and unsent-draft checks. Leave Developer tools off. Do not press Send/Apply or confirm a restart, self-test, firmware, pool, fan, voltage, or frequency change.

1. On the home Wi-Fi, open Hash Fleet and verify your saved miners appear. Open one miner and confirm readings show an age/source rather than assuming a cached reading is live.
2. Open **Settings & pools → Easy**. Edit only the device-name draft without sending it. Check **1 pending change** shows the reported previous name and proposed name. Switch **Pro → Easy** and verify the unsent draft survives.
3. In **Pro**, open **Miner Diagnostics** and inspect reported electrical, cooling, firmware, and pool-state information. Unavailable measurements should say **Not reported**. Pro alone must not reveal/unlock advanced write tools.
4. Return to Easy, inspect **Review common changes**, then back out without sending and discard the draft. Background/reopen the app and check that navigation remains responsive. Report unexpected layout, missing saved devices, or incorrect freshness wording without exposing wallet strings or passwords.

Private result bundles and build/install receipts are under `/Users/USER/.jcode/scratch/hash-fleet-controls-20261002-1128/`. All mutation UI tests target an in-process loopback fixture, never the physical ASICs or mining Mac.

## Normal mode saves everyday settings directly (October 2, 2026, 17:00 UTC)

Following the competitor findings above (HashMonitor's settings sheet edits values and sends them with a single Save, with no request preview), Normal mode no longer shows the JSON "Update settings" page for everyday settings. Tapping **Save** sends the change and shows "Saving…" then "Saved to <miner>" inline on the same form.

- **Direct save, Normal mode only:** device name, on-device statistics interval, automatic fan on/off, temperature target, screen rotation, screen colors and display timeout. This covers the Easy card ("Save changes"), General ("Save name", "Save interval") and Display ("Save rotation", "Save screen colors", "Save display timeout").
- **Unchanged reviewed flow:** pools and active slots, credentials, frequency, voltage, manual or minimum fan speed, custom JSON, firmware, restart and **every Developer-mode change**. Any payload with a field outside the allowlist, or any endpoint other than `PATCH /api/system`, falls back to review (`MinerEverydaySave.qualifies`).
- **Still enforced:** demo mode never writes. Offline, stale or reconnecting miners stay read only. Each save re-reads system info immediately before writing, and only changed fields are sent.

Validation: new `MinerEverydaySaveTests` (allowlist, Developer fallback, 11 risky or unknown keys, non-settings endpoints). Loopback UI tests assert exactly one PATCH with the exact body, no "Update settings" page and no Advanced sheet, and the inline Saved status, for both General hostname and the combined Easy save. The Developer power-user, custom JSON typed-APPLY and offline read-only flows are unchanged and still pass. These are simulator and loopback results, not a physical-phone install or live-miner write.

Regression check: all RealModeControl, ExpertMode and new unit tests passed on the direct-save build. Five other UI tests failed. `HashFleetUITests.testTuningReview…DemoWritesLocked`, two `CompatibilityUITests` cases and `MinerCardInteractionUITests` cooling-card and telemetry-card cases fail identically on a clean worktree containing only the pre-existing 21-file user diff (same assertion lines), so they predate this change. The pool/identity card test failed once in the dashboard toolbar menu helper and then passed on an isolated rerun. `testLargestDynamicTypeKeepsCardToggleAndSettingsSeparatelyReachable` also failed, on the miner-detail `detail.metric.Chip temp` reachability assertion before any settings screen. It was not rerun on the baseline, so its cause is unconfirmed.
