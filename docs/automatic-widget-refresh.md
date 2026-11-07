# Automatic local widget refresh

Checked against Apple documentation on October 30, 2026.

## Contract

- Ordinary widget sharing still shares aggregates only.
- **Allow widget refresh** grants the existing authenticated Refresh-button action.
- **Refresh automatically** is a separate, default-off choice. Existing manual-only installations do not silently gain automatic network access.
- While valid prepared permission exists, WidgetKit's `getTimeline` awaits the same bounded, read-only, MAC-pinned reader before returning entries. Preview, snapshot and synchronous rendering stay cache-only.
- The automatic reload request is five minutes after a provider execution. This is an earliest requested opportunity, not a timer or delivery guarantee. iOS can defer updates substantially. The existing app background refresh is another system-scheduled opportunity.
- The one-minute freshness threshold is unchanged. A stale saved observation stays stale until a complete successful read. Waiting, failure, rendering and timeline dates never advance its observation time.
- Existing private-address validation, no-redirect/cookie/credential reader, four-request concurrency limit, ten-second runner deadline, fifteen-second lease/cooldown, all-or-nothing aggregate and permission expiry still apply.
- Automatic execution cannot create identity pins or renew their 24-hour lifetime. Only complete foreground observations can prepare or renew them.
- An optional automatic-consent nonce binds each automatic lease and publication. Opt-out or off/on invalidates old automatic results without rotating the base generation used by an existing Live Activity. An authenticated manual read is not invalidated just by automatic opt-out.
- The extension declares the same local-network ATS policy as the app. Arbitrary network loads remain disabled. This does not grant Local Network permission, discover devices or bypass first-unlock file protection.

## Live Activity boundary

A WidgetKit timeline is not a Live Activity update or permission to wake the containing app. The automatic provider does not call an AppIntent directly or claim app-process execution. Existing foreground and permitted app background work can update a running Live Activity through ActivityKit. The authenticated manual LiveActivityIntent path is retained. No remote server, APNs registration, audio/location workaround or continuous background loop is introduced.

## Expected behavior and permission boundary

Apple documents a typical budget of 40–70 reloads per day for frequently viewed widgets, roughly 15–60 minutes between reloads with substantial variation. Requesting a five-minute opportunity is not a guarantee of a five-minute update. With the existing one-minute freshness threshold, a working automatic widget can correctly say stale between scheduled reads. Neither enabling the option nor displaying a ready status proves that a later background network read succeeded.

Apple's TN3179 says app extensions generally share their containing app's Local Network privilege. A background extension cannot present the first Local Network prompt when that privilege is undetermined. Prepare permission with successful foreground app reads, and verify extension behavior on the physical device. The simulator does not exercise Local Network privacy. Do not reset privacy, delete the app or weaken device authentication to obtain a test pass.

## Acceptance checks

- A separately compiled widget provider fetches and persists new observations without invoking an intent, then returns the persisted read time.
- Manual-only legacy JSON, preview, fresh cache, expired permission, Demo, mismatched inventory and missing state start no automatic reads.
- Failure preserves the previous observation and cooldown prevents immediate repeated work.
- Automatic opt-out and off/on during an awaited read reject its late result. Manual reads retain their existing behavior.
- Automatic consent cannot prepare missing pins or extend expired pins. Disabling local refresh or sharing clears the additional consent.
- Existing manual, rendering/privacy, lifetime and ActivityKit handoff tests are retained unchanged.
- Physical acceptance must observe a new reading time with the app ordinarily backgrounded and no Refresh tap. An initial reload caused by enabling the setting is setup evidence, not proof of a later autonomous update. Simulator/helper tests alone do not establish iOS's physical-device scheduling or LAN access.

### Remaining physical procedure

1. Resume the already authorized Mirroring session using normal local authentication. Do not change the Mac or phone authentication policy, Auto-Lock, privacy state or network configuration.
2. Open the updated app normally. Confirm the existing fleet and widget-sharing/local-refresh settings are preserved, then enable **Refresh automatically**, as requested by the user. Wait for a complete foreground observation to prepare the existing identity pins. Record this as setup, not autonomous acceptance.
3. Return to the Home Screen normally without force-quitting Hash Fleet. Record the widget's displayed observation time and the UTC observation time. Do not tap Refresh, open the app again, trigger a debug refresh or alter relevant settings during the observation window.
4. Observe a later displayed observation time after the app's ordinary background grace period, without a foreground or manual trigger. Record the actual elapsed time. A one-minute stale transition alone is not a failed automatic refresh, and the requested five-minute opportunity is not a deadline for iOS.
5. A later no-tap reading establishes the visible outcome only. Without process-level evidence, do not attribute it exclusively to the widget provider rather than an allowed app background task. An observation window without an update establishes no update during that window, not a guaranteed permanent failure.
6. Keep the user's requested automatic choice enabled. Do not create or leave a temporary Live Activity running, change miner settings, upload local data or uninstall/reset the app. Record any blocked or unverified checks explicitly.

## Verification record, October 30, 2026

- The final iOS 26 regression run after the last code change passed 52 tests across six suites, with two iterations. This includes the original manual-refresh, rendering/privacy, lifetime and activity-handoff acceptance assertions. A native Mac compatibility build also passed.
- Earlier compile errors and a real medium-widget footer truncation failure were corrected in production code. The unchanged rendering assertion then passed. An earlier individual-test selection that ran zero tests is not counted as verification.
- A fresh snapshot of current source built as device build 10. Existing local provisioning required scratch-only per-target signing entitlements for this local test. The app and widget retain their shared app group, and no target has an APNs entitlement. Repository signing configuration was not altered and the default signing build is not claimed to pass.
- Signature verification and source-checksum verification passed. The current build was installed in place on the physical iPhone at 02:47 UTC, without uninstalling or resetting app data.
- At 02:49 UTC, iPhone Mirroring required normal Mac authentication. The new automatic option had not yet been enabled on the phone, and physical no-tap acceptance remained unverified. Installation and fixture tests are not a substitute for that check.
- The same normal Mirroring authentication gate was still visible at 02:53 UTC. Independent current-source verification continued instead: all 11 `FleetScheduledCheckTests` passed using intercepted URLProtocol fixtures, including bounded transport, identity, error, endpoint and privacy checks. These tests make no miner requests and are not physical-device LAN evidence.

### Physical follow-through

All observation times below are October 30, 2026, UTC. The phone displays the previous local date, October 29, in EDT.

| UTC | Observed evidence | What it establishes |
| --- | --- | --- |
| 03:04:16 | Mirroring again showed the actual Home Screen. | The earlier authentication blocker was no longer current. No authentication-policy change or bypass was performed. |
| 03:06:40 | Actual Widgets settings showed existing sharing and manual local refresh on, new automatic option off. | Current installation preserved those visible settings. |
| 03:06:53 / 03:07:12 | Enabled **Refresh automatically**, then visually confirmed it on with prepared status. | Explicit consent and readiness, not a later automatic network success. |
| 03:07:40 / 03:07:54 | Returned Home normally. Initial widget observation time was October 29 at 11:07 PM EDT. | Setup reading only. No Refresh tap or force-quit was used. |
| 03:14:22 | After 6 minutes 42 seconds backgrounded, the widget still showed 11:07 PM, stale, with `Auto refresh · waiting for iOS`. | No later displayed observation during this window. This is not proof of permanent failure or proof that the extension never ran. |
| 03:18:07 | Read-only inspection of existing app preferences confirmed all three choices on. App background diagnostics recorded a completed snapshot run at 03:07:41–03:07:46 and accepted subsequent requests at 03:07:46. | An initial app-background opportunity occurred, but no later app run was recorded in that diagnostic snapshot. Accepted requests are not scheduled-delivery guarantees. |

No manual refresh, foreground return, debug trigger or setting change occurred after the Home Screen transition during this observation window. Reading preferences did not launch the app. An attempted read-only transfer of the extension's current receipt was denied by the device's container-directory restriction, so no extension receipt or attempt time is claimed and no restriction bypass was attempted. The final bounded observation at **03:25:31 UTC**, **17 minutes 51 seconds** after backgrounding, still showed 11:07 PM EDT. That observation window is complete without a later update, not an automatic-refresh acceptance pass or proof of permanent scheduling failure.

The earlier source-only review did not establish a working physical update path. A later device report did reveal the launch-crash blocker below. An additional configured-auto worker did not deliver a usable checkpoint before its bounded attempt was stopped. That attempt is not independent review credit or evidence against a model or provider. No routing or account changes were made.

### Proven background launch crash and isolation repair

Read-only inspection of the single post-install build 10 app crash found a concrete failure at **03:15:44 UTC on October 30**, displayed as **11:15:44 PM EDT on October 29**. The faulting thread was the private `com.apple.BGTaskScheduler` queue for the widget-refresh identifier. Its stack entered the launch closure in `FleetBackgroundRefresh.register`, then failed Swift's executor-isolation check. This is direct evidence of a background-launch bug, not proof that every missing widget refresh has the same cause.

Apple's current `register(forTaskWithIdentifier:using:launchHandler:)` documentation and the installed iOS 27.1 SDK agree: `using: nil` selects a default background queue. Both launch closures were created in a `@MainActor` context. An inner `Task { @MainActor in ... }` cannot repair an isolation assertion that fails before that task is created.

- Both launch registrations now explicitly select `.main`, matching the closures' actor isolation. They validate the task type and install the worker and expiration handler synchronously, without a redundant task hop. Network operations remain asynchronous.
- Expiration is created by a `nonisolated` factory returning an explicitly `@Sendable` closure. It synchronously cancels only its sendable worker and explicitly hops to MainActor for diagnostics. `BGTask` is not made unchecked-sendable and actor checking is not disabled.
- A registrar injection seam checks the actual queue arguments for both identifiers without duplicate system registration. A separate regression invokes the actual production expiration closure on a private, non-main dispatch queue and verifies cancellation before it returns. These tests do not instantiate framework-owned task objects or claim an OS-scheduled launch.
- At **03:45 UTC**, the fresh current-source simulator run passed **69 tests in 10 suites, with two iterations**, including both new isolation regressions, background publication/diagnostics, unchanged manual and automatic widget acceptance, ActivityKit handoff and rendered-widget checks. This is code-level verification, not physical no-tap acceptance.
- A scoped configured-auto reviewer failed before reading source, with an HTTP 400 provider error. No independent review is claimed and no routing/account changes were made.
- A scratch-only negative control changed both actual registration arguments back to `nil`, with acceptance tests unchanged. At 04:13 UTC, the two-test suite finished with exactly two expected queue assertions, one for each registration, while the real expiration callback test passed. The CLI subsequently timed out with exit 124 during stalled post-test simulator diagnostic collection. Only that task's diagnostic process was stopped. This is observed test-level sensitivity evidence, not a clean command pass; the repository and installed phone were never mutated.
- The scratch source was then restored to the committed repair, all 15 selected source hashes matched again, and the **final verifier at 04:19 UTC passed all 69 tests in 10 suites with two iterations, exit 0**. No acceptance assertion was weakened to obtain this pass.

### Repaired build 11 physical follow-through

Repair commit: `18c96fa`. A new snapshot of current source was used, not a recovered build. Its first packaging attempt failed because the snapshot omitted the package test directory. The complete current directory was copied without changing production code or tests, and the subsequent build succeeded. Existing local-only signing was applied only in the new scratch copy. Repository signing configuration remains unchanged. All 15 selected app/widget/reader input hashes matched before installation.

The app and both embedded extensions passed strict signature verification, declared build 11, matched the existing team, and had no APNs entitlement. The app and widget retained their shared group and local-only ATS policy, with both background identifiers and modes present. The notification extension retained the same empty local-test entitlement policy used for build 10.

| UTC, October 30 | Observed evidence | What it establishes |
| --- | --- | --- |
| 03:53 | Verified build 11 installed in place, without uninstalling or resetting app data. Later device metadata independently confirmed bundle version 11. | The repaired app is on the actual phone, not just the simulator. |
| Before and after normal launch | Private read-only preference copies showed sharing, manual refresh and automatic refresh all still on. | Existing explicit choices survived the install. No new opt-in or settings change was needed. |
| 03:54:28 | Launched the app normally, without test/debug arguments. | Foreground permission preparation only, not autonomous acceptance. |
| 03:58:09 | Used Mirroring's normal Home Screen command, without force-quitting. | Start of the repaired app's background interval. |
| 03:58:10.206–03:58:10.517 | Private fixed-outcome/date-only app diagnostics recorded `completeSnapshot`, followed by accepted requests. | The repaired background launch path completed an initial real-device run. An immediate setup-adjacent run is not proof of a later settled update. |
| 04:07:53 | Located the pre-existing large widget on Home Screen page 7 using only ordinary navigation. It displayed `Oct 29 at 11:58 PM`, stale, with `Auto refresh · waiting for iOS`. | Initial visible baseline for the repaired app. No later displayed reading yet. The phone's current local date is now October 30, EDT. |
| 04:23:59.816 | The final direct native capture of the existing Mirroring window was obscured gray. No current widget content was visible. | **Blocked visibility**, not an unchanged widget, a later update, or proof of permanent failure. This was 25 minutes 50.816 seconds after backgrounding. |

No app reopening, manual Refresh, debug trigger, settings change, force-quit or temporary Live Activity occurred after the 03:58:09 background transition during this bounded observation. Home Screen navigation did not change the widget layout or activate another app. The single final observation had been scheduled for **04:20:15 UTC** and was actually captured at **04:23:59.816 UTC**. The observation window is now closed with later visible refresh **unverified because visibility was blocked**. No indefinite watcher was started, and automatic consent was left on. Build 10's setup read and failed 17-minute window do not establish acceptance of build 11.

### Later read-only diagnostic, 04:34 UTC

A supported read-only copy of the actual phone app preferences at **04:34:19 UTC** confirmed sharing, manual refresh and automatic refresh all still on, using the authoritative coordinator keys. The latest recorded background check started **04:05:47.727499 UTC** and finished **04:05:48.209384 UTC** with `completeSnapshot`, later than the 03:58:09 Home transition. No agent Refresh tap or app reopen occurred in between. Its request submissions were accepted just before that start.

The current diagnostic schema does not distinguish scene-background grace work from system-scheduled app work. This is a later recorded app-background check, not provider-only or scheduler-only attribution, a successful widget cache write, a recurring cadence guarantee, or a later displayed widget timestamp. The visible automatic-refresh outcome remains unverified because the final Mirroring capture was obscured. The user's subsequent manual-loading request and its separate validation are recorded in `widget-refresh-loading.md`.

### Remaining source and storage hypotheses, 05:07–05:15 UTC

The installed build 12 phone was left untouched during these checks. No additional installation, app launch, Refresh tap, setting change, debug wake or miner request was used. Production app/widget/core sources remain identical to build 12. Only tests and this evidence ledger changed.

| Hypothesis | Observed check | Conclusion and limit |
| --- | --- | --- |
| The first automatic success prevents a later cold provider from reading again. | The real separately compiled provider was invoked at three injected observation times, with a new provider instance each time. Each stale opportunity performed one read; another cold instance 30 seconds later performed none. The original aggregate cache intentionally stayed unchanged, and prepared permission was not renewed. | No one-shot blocker demonstrated. These are explicit fixture invocations, not system-delivered iOS wakes. |
| An older transactional receipt can hide a newer aggregate or fabricate freshness after a failure. | A newer aggregate prevented an unnecessary read. At its exact 60-second stale boundary, a failed read preserved that newer aggregate's original time rather than selecting the older receipt. | Newest-observation merging and failure preservation passed. No physical cache delivery inferred. |
| `completeSnapshot` proves that the widget cache was saved or displayed. | An actual coordinator with unavailable cache storage reported its save error, while the existing complete-snapshot gate and diagnostic still recorded `completeSnapshot`. | The diagnostic certifies snapshot availability only. It cannot establish persistence, a visible update or which background trigger ran. |
| An already-running second process cannot see later shared-storage changes. | Two live native processes used the exact current production storage types, a random disposable preferences suite and a private fixture directory. The second process observed an initial aggregate save, a later save and clearing without recreating its storage object. Transactional results propagated in both directions. | No propagation blocker demonstrated in this native fixture. It is not the physical iOS App Group or its privacy/file-protection environment. |
| Process boundaries defeat duplicate protection or allow a revoked automatic result to return. | A real cross-process lease blocked duplicate work before its reader started. Automatic off/on rejected the old held result without rotating the base grant. Revocation rejected a late result without recreating state, and preserved the exact lock inode. A third-process flock holder made reads fail closed promptly, and work succeeded after release. | Cross-process safety and recovery passed with injected responses. No network or scheduling evidence inferred. |

The final current-source simulator run after the test changes passed **76 tests in ten suites, with two iterations**, exit 0 at **05:07:50 UTC**. Existing assertions were retained. The native process checks then passed **20 named checks in each of 20 runs**, **400 named assertions** total, at **05:15:36–05:15:39 UTC**, exit 0. The native helper compiled the unchanged production Shared files against a fresh build of the current core. It never accessed `.shared` storage or invoked the network reader.

Evidence is retained privately under `~/.jcode/scratch/hashfleet-auto-hypotheses-20261030-0503/`: `recurrence-final-regressions.xcresult`, its log, the exact fixture sources, and `native-process-final-20runs.json`. A bounded configured-auto reviewer failed with HTTP 400 before accessing source, so no independent approval is claimed and no model/account route was overridden.

These checks did not demonstrate an additional production defect or establish recurring physical automatic updates. The newer **October 30, 12:47 AM EDT** widget reading seen at **04:50:37.007 UTC** remains an installation-adjacent baseline. The single **05:47:30 UTC** no-tap follow-up has now closed with blocked visibility, as recorded below. No freshness threshold, consent limit, phone state or observation deadline was changed to obtain a pass.

### Build 12 final no-tap observation, 05:51 UTC

Task `sched_388e1f77` was due **05:47:30 UTC** and delivered **05:47:59.528 UTC on October 30**. Its one actual direct native capture of existing Mirroring window 12833 started **05:51:10.277 UTC** and finished **05:51:10.380 UTC**, not at the scheduled time. At capture start the elapsed time from the **04:50:37.007 UTC** baseline was **1 hour 0 minutes 33.270 seconds**. The baseline displayed **October 30 at 12:47 AM EDT** following the **04:47:10 UTC** build 12 installation and remains setup evidence, not settled autonomous acceptance.

The final screenshot instead showed **iPhone in Use**, **iPhone Mirroring ended due to iPhone use**, and **Lock your iPhone to connect**, with a Connect control. No widget or displayed observation time was visible. The result is **blocked visibility**, not an unchanged widget, a later update, permanent failure, provider-only execution or a recurring cadence. The phone-in-use banner also means the full interval cannot be described as an untouched-phone experiment. Only the absence of agent Refresh/app/debug/settings actions is recorded.

No reconnect, navigation, app launch, Refresh tap, debug trigger, force-quit, authentication, settings/network change or miner action was performed for the final capture. No additional preference transfer was needed. The three consent choices were last verified on after installation and were left unchanged by the agent, not newly reverified at closure. Later accessibility hardening, commit `d17593c`, is tested source-only and was not installed on this phone. The original build 11 window remains separately closed.

The native image is retained in the session's tool result; sanitized dates and the fixed blocked outcome are recorded in `~/.jcode/scratch/hashfleet-refresh-loader-20261030-0434/sanitized-final-no-tap-observation.json`. **The finite follow-up is complete, but later visible automatic refresh remains unverified.** No replacement timer, repeated capture or indefinite watcher was started. Further source-level verification and its limits are in `widget-refresh-loading.md`.

## Primary sources

- Apple, Keeping a widget up to date: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- Apple, Making network requests in a widget extension: https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension
- Apple, Choosing Background Strategies for Your App: https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app
- Apple, Displaying live data with Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Apple, TN3179 Understanding local network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Apple, BGTaskScheduler registration and queue selection: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)
- Swift Evolution, SE-0423 dynamic actor isolation enforcement: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0423-dynamic-actor-isolation.md
