# Visible widget Refresh feedback

October 30, 2026.

## User-visible change

The Home Screen widget previously kept a static Refresh arrow while its authenticated read was running. A tap now has a distinct loading presentation: an activity-ring glyph, **Refreshing…** status, an accessible **Refreshing fleet** action label and a disabled repeat action.

The last observation and its timestamp remain unchanged until a complete successful read is persisted. Existing failure, cancellation and permission/setup messages remain truthful. No artificial percentage, timestamp advance, minimum fake delay or continuous background timer is introduced.

## Implementation

- `FleetWidgetView` marks invalidatable content with WidgetKit's supported `invalidatableContent()` modifier. `FleetWidgetContent` reads the system's `.invalidated` redaction reason to present immediate action feedback until the replacement timeline arrives. Archived widgets do not use local `@State`, an on-tap task or a fake debounce timer.
- A provider execution during an actual valid refresh lease also presents loading, without relying on a previous failure outcome. A future lease is not called in progress.
- The provider includes an entry for lease expiry. An expired lease no longer presents loading and instead preserves the saved reading with the existing timeout message. WidgetKit still controls delivery of timeline entries; this is not an exact UI scheduling guarantee.
- The existing transactional lease and cooldown still reject concurrent reads. No reader, endpoint, identity, consent, authentication, deadline or privacy behavior is broadened.
- A custom activity arc is intentional. Apple documents that a circular `ProgressView` in widgets becomes a capacity gauge, and an indeterminate one is empty. The loader therefore does not rely on an app-style spinning `ProgressView` or promise continuously running animation. The explicit text communicates the pending state even without animation.

## Requirement-to-check ledger

| Requirement | Check |
| --- | --- |
| Immediate visible action feedback | Actual production widget content rendered with system `.invalidated`; captured pixels must contain Refreshing. |
| Loading during a real read | Suspend the actual runner's injected read, inspect provider output from its real persisted lease, then release it. |
| No duplicate network requests | A second runner call while the first is suspended returns busy and the read count remains one. |
| Clear on success or failure | Release successful and throwing reads; provider loading must clear, and only success may advance observation time. |
| Clear on cancellation | Cancel a suspended real runner and verify the stopped message, no loading and the original observation time. |
| No indefinitely archived lease loader | Inspect the provider's exact lease-expiry timeline entry and the permission-expiry boundary. |
| No setup or permission bypass | Invalidating an unprepared action leaves it unprepared; existing consent/lifecycle/security regressions remain unchanged. |
| Layout, privacy and distinct pending appearance | Capture production small, medium and large content for lease-based and invalidated loading, include light/dark appearances, compare with idle captures and verify privacy redaction still hides measurements. |

These are host-side production rendering and integration tests, not proof of physical WidgetKit action delivery, actual VoiceOver traversal or an automatic scheduling cadence.

## Verification and delivery

The initial verification failed at compilation because a new dynamic Swift Testing assertion comment was supplied as `String` rather than `Comment`. The comment syntax was corrected without changing the assertion. The next run passed **14 tests in one suite**, including actual production loading render captures. Cancellation and an additional permission boundary were then added.

The final current-source run after the last source edit passed **73 tests in ten suites, with two iterations**, at **04:42:40 UTC**, exit 0. It includes the existing manual/automatic consent, lifecycle, handoff, background callback/diagnostic/publication and production-rendering tests, plus the new loading regressions. Code, tests and the initial report are committed as `71520fc`.

A fresh current-source device build succeeded at **04:45:00 UTC**. All **520** selected app/widget/core/test source and resource inputs matched the working tree, tested simulator snapshot and device snapshot. The same previously proven per-target local-only entitlement policy was applied only in the fresh scratch project; repository signing configuration was not changed and its default signing build is not claimed to pass.

Build **12** installed in place at **04:47:10 UTC**, without uninstalling or resetting app data. Independent device metadata at **04:49 UTC** confirmed build 12, and all three sharing/manual/automatic choices remained on and equal before/after installation. No app launch or Refresh tap was used for these checks.

The first scratch signing verifier incorrectly expected the team in the generated project instead of its included `Signing.local.xcconfig`; it failed before checking signatures. The original shell pipeline lacked `pipefail`, so installation continued. That failure is preserved, not counted as pre-install verification. The verifier was corrected to the actual included configuration, including exact current-source configuration equality and one expected team. A fail-closed rerun at **04:49:50 UTC** passed strict signatures for the app and both embedded extensions, build 12, current team, expected shared groups, retained background identifiers/modes, local-only ATS, no APNs and no additional local signing capabilities. No second installation, account switch or security change was needed.

No physical tap-to-loader observation or independent reviewer approval is claimed. The new loading presentation is verified by the production-rendering and real-runner tests above.

A bounded configured-auto reviewer read the source but returned unsupported guidance, including nonexistent file/environment paths and `@State` debouncing in archived widgets. That advice was rejected, not treated as independent approval. Routing and account settings were not changed.

## Automatic refresh is a separate question

The loading indicator does not make automatic refresh more frequent and does not prove it works continuously. At **04:34:19 UTC**, a read-only copy of the existing phone app preferences confirmed all three authoritative sharing/manual/automatic consent keys still on. The latest recorded background check started **04:05:47.727499 UTC** and finished **04:05:48.209384 UTC** with `completeSnapshot`, later than the agent's **03:58:09 UTC** normal Home transition, without an agent Refresh tap or app reopen.

That diagnostic records both scene-background grace work and system-scheduled app work without a trigger discriminator. It establishes a later recorded app-background check, not provider-only execution, scheduler-only causality, a successful widget cache write or a later displayed widget timestamp. The final bounded Mirroring capture at **04:23:59.816 UTC** was obscured, so visible later automatic refresh remains unverified. No indefinite watcher was started.

### Build 12 visible baseline and one finite follow-up

A direct native screenshot at **04:50:37.007 UTC** showed the existing large Home Screen widget displaying **October 30 at 12:47 AM EDT**, with the stale badge and `Auto refresh · waiting for iOS`. There had been no agent Refresh tap, app foreground, debug trigger or settings change since installation. This is a newer visible observation, but it coincides with the **04:47** installation, which can trigger reloads. It is therefore a new setup baseline, **not proof of a settled automatic refresh** and not an extension-only attribution.

Because the user again asked whether no-click updates work, one finite passive follow-up was scheduled for **05:47:30 UTC / 1:47:30 AM EDT on October 30**, task `sched_388e1f77`. Its single actual capture and blocked outcome are recorded below. That follow-up is now closed without rescheduling. The earlier build 11 observation remains closed and is not extended or relabeled a pass. There is no continuous watcher or exact refresh-cadence promise.

The subsequent test-only follow-through passed **76 tests in ten suites with two iterations** and **20 runs of 20 native process-boundary checks**. It covers later cold-provider reads, newest-cache merging, diagnostic limits and actual cross-process storage/lease/revocation behavior. Production code and the installed build 12 were not changed during those checks. These fixture results do not replace physical no-tap evidence; the scheduled final capture was blocked as recorded below. Details and evidence boundaries are in `automatic-widget-refresh.md`.

### Build 12 finite follow-up closed with blocked visibility

The scheduled task arrived at **05:47:59.528 UTC**. Exactly one direct native screenshot of the existing Mirroring window 12833 was taken at **05:51:10.277–05:51:10.380 UTC on October 30**, without clicking or reconnecting. At capture start this was **1 hour 0 minutes 33.270 seconds** after the **04:50:37.007 UTC** baseline, and **3 minutes 40.277 seconds** after the scheduled time. The actual capture time, not the scheduled time, is the observation time.

The image showed **iPhone in Use**, **iPhone Mirroring ended due to iPhone use**, and **Lock your iPhone to connect**, with a Connect control. No widget content or reading timestamp was visible. This is **blocked visibility**, not an unchanged widget, a newer automatic reading or proof of permanent failure. The banner also prevents assuming the phone itself remained untouched throughout the interval. No provider-only causality or recurring cadence is established.

No agent Refresh tap, app launch, navigation, debug action, force-quit, reconnect, authentication, setting/network change or miner action was used. No new preference copy was taken, so consent is not freshly reverified; its last verified state was on, and the agent did not change it. The accessibility hardening in `d17593c` remains source-only and was not installed over build 12. Sanitized evidence is retained in `~/.jcode/scratch/hashfleet-refresh-loader-20261030-0434/sanitized-final-no-tap-observation.json`. This finite follow-up is complete with automatic visible delivery **still unverified**. It was not rescheduled and no indefinite watcher was started.

### Further native accessibility validation, 05:32–05:41 UTC

An isolated simulator-only executable mounted the actual separately compiled production widget content, not a recreated button. It used fixture entries, declared no App Group and invoked no action or network reader. Native XCUI assertions inspected the real accessibility tree, labels, enabled state, exactly one Refresh action and its at-least-44-point frame. This is stronger than the earlier OCR checks, but is not physical WidgetKit archiving or VoiceOver traversal.

The initial **seven-case run had two failures**. Five cases passed across small, medium and large: idle action reachability, persisted busy label/disabled state, invalidation propagation/disabled state, failure returning to idle, and the unprepared Link. The unfiltered description/hit-region audit threw `com.apple.accessibilityAudit` code **-902**, `Invalid target app`. That is a blocked audit, not approval or a demonstrated production cause. After the seven tests ended, Xcode stalled collecting diagnostics; only that owned simulator test command was cancelled. The original failures and log are retained.

The privacy case found actual measurement labels in raw XCUI descendants despite the correct redacted summary. This does **not** establish what VoiceOver would traverse or prove a physical-widget privacy leak. Nevertheless, an explicit accessibility representation is a narrower and verifiable boundary than retaining ignored metric descendants. `FleetWidgetPrivacy` now supplies only the appropriate summary as its accessibility representation. It keeps the existing Open Hash Fleet hint and the separate Refresh sibling, without changing visible measurements, timestamps, consent or reads.

A scratch-only candidate passed the **six semantic cases across all three families**, **18 family/state combinations**, at **05:41:01 UTC**, exit 0. The unchanged privacy assertions now found no fixture hashrate/unit/power labels in raw descendants while the action remained reachable. Both invalidated and persisted-busy actions were labelled **Refreshing fleet**, disabled, unique and at least 44 points in each dimension. The original audit was not rewritten or filtered into a pass: it was excluded from this narrower semantic rerun and remains unverified.

A further real-intent regression holds the first production runner, submits **32 concurrent competing intent invocations**, then **32 additional attempts during completion cooldown**. None may invoke another reader. Contention can fail closed at the existing short file-lock deadline. This validates the existing lease/cooldown rather than adding ineffective archived-widget `@State` debouncing. Existing exact lease/permission expiry, success/failure/cancellation and rendering assertions remain unchanged.

After the last production/test edit, the final exact-current-source run passed **77 tests in ten suites with two iterations**, exit 0 at **05:44:49 UTC**. It includes the new real-intent pressure test and unchanged lease-expiry, permission, cancellation, privacy, appearance and manual/automatic refresh regressions.

Private evidence: `~/.jcode/scratch/hashfleet-loader-further-validation-20261030-0528/`, including exact harness sources, the original failed log/result bundle, the six-case semantic result bundle, and the final current-source regression log/result bundle. The accessibility hardening is **source-only, not installed on the phone**. Build 12 and the original no-tap observation window remain untouched. No physical loading, VoiceOver traversal, full accessibility-audit approval or recurring automatic-refresh cadence is inferred.

## Primary references

- Apple, Adding interactivity to widgets and Live Activities: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- Apple, `invalidatableContent(_:)`: https://developer.apple.com/documentation/swiftui/view/invalidatablecontent(_:)
- Apple, circular progress-view style: https://developer.apple.com/documentation/swiftui/progressviewstyle/circular
- Apple, Keeping a widget up to date: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
