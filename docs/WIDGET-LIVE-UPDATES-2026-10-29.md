# Lock Screen update investigation, October 29, 2026

## Current resolution: Wi-Fi-only updates, October 29, 2026

The operator clarified at 14:28 UTC that this dashboard should update on the miner Wi-Fi without requiring a new remote service. The local-only fix below supersedes the manual-refresh gap described in the historical investigation. It does not turn Wi-Fi connectivity into continuous background execution.

- The explicit, device-authenticated widget refresh now adopts `LiveActivityIntent`, which Apple documents as running in the app process without requiring the app UI to open. A completed read can therefore update an existing matching app-owned Live Activity.
- Publication occurs only after the bounded read-only refresh engine has persisted a successful, complete real-fleet observation. The receipt must match the current enabled refresh-permission generation and exact saved reading. Failed, partial, cancelled, expired or revoked refreshes do not publish an activity update or replace the last observation time.
- New real activities bind to the current local-refresh permission generation when that permission is enabled. The handoff only targets the same named activity, generation, real-fleet mode and miner count, and only replaces a strictly older observation. It never starts an activity or enables/renews network permission. Permission is checked again after the ActivityKit suspension, ending only that old activity if permission was revoked.
- Existing activities from before this change have no generation binding. Enable widget sharing and local widget refresh in **Widgets**, then explicitly end/start the Live Activity to bind it. Disabling/re-enabling local refresh also requires a new activity. Do not silently bind an old session to newly granted permission.
- Foreground activity updates also reject equal or older timestamps. The one-minute stale date still derives from the original observation, not the refresh completion or render time. Stale means old evidence, not confirmation that a miner is offline.
- The missing **Updates on your Wi-Fi** section is now present in Live Activity settings. It explains foreground LAN access, manual widget refresh and setup, system-controlled background execution, and failed/stale readings. Its light and dark simulator screenshots were inspected.
- No optional collector, new ActivityKit relay, push registration or remote-enrollment UI ships in this change. Partially authored remote work was paused, archived outside the repository and excluded from the shipping patch. Existing unrelated notification functionality and all pre-existing work remain untouched.

### Why remote delivery is not required, and what remains different

An open app can continue its existing LAN monitoring, and a user-triggered widget refresh can request a fresh local read. Neither needs an outbound cloud relay. The phone must still have Local Network permission and be able to reach the selected miners.

When the app is suspended, being connected to Wi-Fi does not itself schedule continuous local polling. Apple controls background-refresh timing. A hands-off Lock Screen update stream while the app sleeps would need a separate approved delivery design, such as an always-on LAN reader plus ActivityKit push delivery. That optional design adds infrastructure, authorization, expiry and privacy responsibilities, and still cannot promise an exact delivery cadence. It was not requested or activated here.

### Validation after the last production/test edit

All receipts below are isolated local builds on October 29, 2026. Artifact root: `/Users/USER/.jcode/scratch/hashfleet-stale-fix-20261029-1408/`.

| Receipt | Observed result | Boundary of the evidence |
| --- | --- | --- |
| `local-functional-final.xcresult` | Passed: 57 definitions in four suites, 198 concrete executions with both requested repetitions, zero failures/skips/expected failures/runtime warnings | `FleetActivityRefreshHandoffTests`, `FleetWidgetRefreshTests`, `FleetGlanceTests`, `FleetBackgroundPublicationTests`, using injected clocks/storage/readers |
| `local-ui-final.xcresult` | Passed: both UI methods, zero failures/skips/runtime warnings | New explanation in light/dark plus the existing sample ActivityKit start/end workflow on the installed iOS 27 simulator |
| `local-native-final.xcresult` | Passed: four definitions, zero failures/skips/runtime warnings | Mac compilation and the existing background-publication suite, with iOS ActivityKit paths excluded |
| `verify-local-only.py --acceptance` | 61/61 preservation and acceptance checks passed | Actual xcresult repetition nodes, all nine new regression definitions, exact unrelated tracked patches, all 24 prior untracked hashes, 14 prior tuner-validation hashes, additive-only project membership, remote-path exclusion and whitespace checks |

The new handoff suite covers persistence-before-publication, failed reads retaining their saved timestamp, permission revocation/replacement during a read, partial/cancelled reads, freshness boundaries, exact generation/real-fleet/monotonic matching, later receipts retaining the same permission, legacy attribute decoding, the existing Swift Date content-state representation, and authenticated app-process intent conformance. It contains nine definitions, ten concrete cases per iteration, repeated twice in the final receipt.

### Retained failures and unverified limits

- The first build (`local-first.xcresult`) failed because the new attributes field needed a Foundation import. That import was corrected before subsequent builds.
- A broader intermediate run (`local-second.xcresult`) compiled and passed the handoff tests, but retained two unrelated existing OCR test-definition failures, three failed concrete executions: `realPreviewPixelsKeepSpacedPowerAndProtectAllReadingDetails(scheme:)` recognized `2.40 TH/S` rather than the literal `2.40 TH/s` in both appearances, and `failureKeepsTheVisibleSavedReadingAndExpiryRemovesTheAction()` recognized a truncated `Refresh faile....` label from its default-family preview at a small fixed width. Those tests and their expectations were not weakened or edited. The final focused run does not claim the broader visual suite is green.
- The final receipt verifier initially assumed that repeated Swift Testing suites would produce two suite-pass log lines. Actual xcresult nodes contain both repetitions while the log prints one suite summary. Only the verifier was corrected to inspect those nodes. No application/test behavior was changed to obtain that check.
- The existing MacMenuBar resource-membership build warning remains a build warning, distinct from the zero runtime warnings in the result summaries.
- No physical-phone install, real Home Screen widget-tap execution, real-fleet LAN read, production APNs call or remote deployment was performed. The simulator sample lifecycle and protocol/policy tests do not certify those device-specific paths. The final source is ready for signed-device acceptance, not claimed already installed on the operator's phone.

### Follow-up: connect the remaining local path, 15:50 UTC

The production app, widget intent, shared storage and generation-bound handoff are already connected by `5f50c12`. The remaining executable check was whether a completed widget-refresh read could update an existing activity through the real ActivityKit SDK, rather than only reach an injected receipt sink. `persistedWidgetReadUpdatesExistingLocalActivityThroughSDK()` now exercises that boundary on the isolated iOS simulator.

- The test creates private preferences and refresh storage, injects its reader, and starts a uniquely named local activity through the production coordinator. It verifies the current permission generation and absence of a push token.
- The production refresh runner persists the exact complete real-mode fixture reading before calling the production ActivityKit handoff. The existing activity receives that exact observation and its original observation-plus-60-seconds stale date. No replacement activity is created.
- A subsequent failed read retains the same activity content and stale date. Cleanup ends only that test's uniquely named activity. This is synthetic reading data delivered through the real SDK, not a connection to actual mining hardware.
- `sdk-repeat.xcresult` passed 24 test definitions and 105 concrete executions across three iterations of the handoff and transactional-refresh suites. The new SDK method appears in the result tree with three passing repetitions. There were no failures, skips, expected failures or result-summary runtime warnings. Artifact root: `/Users/USER/.jcode/scratch/hashfleet-connect-local-20261029-1535/`.
- The first method-filtered command selected zero tests despite exiting successfully. It is not acceptance evidence. The subsequent full-suite attempt exposed asynchronous SDK visibility: `update()` returned before a previously fetched activity handle reflected the new content. The test now waits at most five seconds for the exact expected reading, retaining all value, timestamp and identity assertions. Both earlier receipts are retained as `sdk-first.xcresult` and `sdk-suite.xcresult`, not relabeled as passes.
- Existing app-host diagnostics about the unsigned App Group lookup, SceneStorage, duplicate menu shortcuts and the Xcode SDK build-number record remain visible in the logs. A passing focused result does not mean the whole app is warning-free or the broader existing visual suite is green.

The connected physical iPhone was inspected read-only and already has Hash Fleet installed, but this updated build was **not installed or launched on it**. The user's installed app, data and settings are unchanged. Actual authenticated Home Screen widget-tap routing and real-fleet Wi-Fi acceptance remain separate device checks. No new relay, collector, push registration, hardware write or continuous-background-monitoring promise was added. Existing unbound activities still require the explicit Widgets setup and end/start sequence described above.

## Scope and observations

The operator reported that saved widgets/Live Activities become stale after a few minutes even though an explicit widget refresh works, then requested Easy/Advanced tuning, right-menu tour removal and visible iPhone ASIC graphs. This report separates source-confirmed behavior from real-device acceptance. No miner was contacted or changed, no physical-phone reinstall/reset was performed, and no push service or new credentials were enabled during this work.

### Historical findings before the local-only fix

- `Shared/FleetGlance.swift` intentionally declares a reading stale at 60 seconds, using the observation timestamp, not the render time. Increasing that threshold would hide age rather than obtain readings.
- `App/Store/FleetGlanceCoordinator.swift` starts activities with `pushType: nil`. It updates existing activities when the app publishes a complete aggregate and sets ActivityKit's stale date from the original reading plus 60 seconds. This is a local-only activity, not a server-updated one.
- Before this fix, `Shared/FleetWidgetRefreshIntent.swift` only awaited the bounded local refresh engine and did not hand the observation to ActivityKit. A successful manual widget refresh therefore was not evidence that the separate Live Activity had received that reading. The current generation-bound handoff above closes that gap without adding remote delivery.
- The app's Live Activity settings already disclose foreground updates, the one-minute freshness rule and absence of continuous background monitoring. The optional scheduled-check notification path is a separate feature and is not equivalent to an ActivityKit update channel.

These findings explain the architecture, not the exact iOS scheduling decisions behind every supplied screenshot. An activity being stale does not prove a miner is offline. This investigation did not independently reproduce every screenshot's layout geometry on the user's physical phone.

## How Uber handles the same problem

Uber's first-party engineering article, **Pickup in 3 minutes: Uber's implementation of Live Activity on iOS**, published July 25, 2024, describes an initial design that depended on the app running in the background. Beta users saw stalled updates or activities left behind when the app stopped running. Uber moved to backend-driven push updates through its Out Of App (OOA) service, which evaluates changes and debounces rapid updates before sending to APNs. The article establishes that architecture, not a guaranteed delivery cadence or Uber-specific use of Apple's token-rotation and stale-date APIs. Those implementation requirements below come from Apple's documentation.

Apple distinguishes the Live Activity's sandboxed presentation from application execution. Its activity UI cannot independently access the network. ActivityKit APNs updates can update an already-running activity without waiting for the foreground app to fetch. Those pushes are distinct from ordinary alerts, silent background notifications and WidgetKit pushes. Activities are bounded sessions, not permanent monitoring daemons.

WidgetKit pushes are also a real option on supported OS versions, but Apple explicitly describes them as budgeted and opportunistic. They complement timelines rather than turn a Home Screen widget into a guaranteed continuously updating view. Background task earliest-start dates likewise are not execution appointments.

## Optional remote architecture, not part of the Wi-Fi-only fix

1. Keep the existing local-first path: foreground read-only polling, user-triggered consented refresh, original observation timestamps, and honest stale state. Never manufacture freshness, repeatedly duplicate a sample or extend timers to imply continuous monitoring.
2. For remote/locked-phone updates, offer separate explicit consent for an always-on LAN collector, a remote relay and Lock Screen exposure. A remote server cannot directly read private LAN miners. A collector on an operator-selected local host could make bounded read-only reads and send outbound HTTPS aggregate summaries. No port forwarding, public miner endpoint or hardware write is needed.
3. Minimize upload data to agreed aggregate readings, counts, observation time and expiry. Exclude raw firmware, pool/wallet fields, addresses, credentials and private keys. Do not assume any collector/service is running from saved configuration alone.
4. Add a real ActivityKit token channel with per-session authorization, rotation/revocation, real/Demo separation, monotonic source timestamps and stale/end events. Use the appropriate ActivityKit APNs topic and push type, not the existing standard-alert token by assumption. Stop or mark stale when collector data stops.
5. If Home Screen server-driven updates are also wanted, add the separate WidgetKit push-token/handler path behind availability checks. Keep timeline fallback, privacy redaction and system delivery limits. Notification service configuration alone does not implement either push path.
6. Verify on a signed physical phone: foreground/background/terminated app, locked/unlocked state, permission denied/revoked, LAN unavailable, collector stopped, expired/replaced tokens, Demo changes and out-of-order payloads. Server acknowledgement is not proof of displayed delivery.

This work does not silently add the cloud path or promise Uber-like cadence from local background scheduling. The privacy and infrastructure decision remains explicit operator approval.

## Primary sources checked October 29, 2026

- Uber Engineering, Pickup in 3 minutes: Uber's implementation of Live Activity on iOS: https://www.uber.com/gb/en/blog/live-activity-on-ios/
- Apple, Displaying live data with Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Apple, Starting and updating Live Activities with ActivityKit push notifications: https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications
- Apple, Keeping a widget up to date: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- Apple, Updating widgets with WidgetKit push notifications: https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications
- Apple, BGTaskRequest.earliestBeginDate: https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate
- Apple, Adding interactivity to widgets and Live Activities: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- Apple, Choosing Background Strategies for Your App: https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app

Fetch date is not a claim that these pages or every underlying API were first published today. The current installed Xcode is 27.1. The app retains its existing iOS 17/macOS 14 deployment targets, without assuming newer push APIs are available on every supported device.
