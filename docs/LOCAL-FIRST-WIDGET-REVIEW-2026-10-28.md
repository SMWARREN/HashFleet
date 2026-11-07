# Hash Fleet: local-first widgets and background refresh

Reviewed October 28, 2026. Implementation base: `bf61f6f`, with the operator's existing working-tree changes preserved. This is source inspection and isolated validation, not a live-fleet or physical-phone report.

## Recommendation

Keep Hash Fleet a local-first miner dashboard. APNs is not required for the dashboard, local notifications, widgets, or locally started Live Activities. APNs is also not inherently a sales feature: it can support remote operational alerts when there is a trusted source of remote events. The present server-triggered notification check is optional, and this patch does not remove, activate, or reconfigure it.

Do not promise continuous background monitoring on iPhone. A local alert can describe a condition only after permitted app or extension execution actually observes it. A notification alone does not create an always-running LAN monitor. Apple's background execution is discretionary [4, 7].

## Why the widget could look old

In this implementation, `FleetWidgetProvider` reads the shared aggregate cache. A timeline reload is not a fresh miner read. The foreground app already publishes through `FleetGlanceCoordinator`, but the final grace-period refresh on leaving the app previously processed alerts without publishing its completed snapshot. That missed handoff is fixed.

There are two different limits:

1. **Our code:** finish a valid local read, persist its original observation time, and request a widget timeline update without spending the reload budget on every live frame.
2. **iOS:** decides when background work and widget display updates occur. `earliestBeginDate` is not an execution deadline or polling interval [2, 4].

Apple explicitly supports networking from an active widget extension. Claims that widgets categorically cannot fetch local data are incorrect. Extension execution and resources remain bounded [1].

## Changes in this patch

- Added widget-specific transparent color and monochrome derivatives of the existing Hash Fleet miner artwork to resources shared by the app, widget extension, and widget test framework. Actual pixel review rejected initial copies that produced a white box and a solid tinted block. New resource tests require transparent corners and interior fan cutouts. Home Screen, accessory, Live Activity, and Control branding no longer uses a CPU or grid as the app's identity. Hardware and functional icons remain appropriate.
- Changed the visible PDF header and suggested backup/report filenames to Hash Fleet. Kept bundle IDs, module names, App Group keys, widget kinds, Live Activity identity, storage roots, and legacy links compatible.
- A follow-up source audit found two missed app-opening grid symbols in Shortcuts and the in-app Controls description. The Controls description now uses the existing approved app artwork, and the intent, shortcut and visible launcher labels consistently say Open Hash Fleet. App Shortcut registration accepts a system-image name rather than arbitrary artwork, so its icon describes the opening action instead of pretending to be the app logo [9]. Hardware and other functional action symbols remain unchanged.
- The actual rendered Controls page then revealed a system-derived `HashFleet shortcuts` label that a spaced-name source check missed. The app and extension `CFBundleName` display metadata now say Hash Fleet. Executable/module names, bundle identifiers, App Group keys and stored-data paths remain unchanged. A strengthened regression reproduced the old metadata and the visible unspaced name as two real failures before this fix. The native Mac artifact already resolves both name fields to Hash Fleet through its existing product name, so it requires no metadata change. No APNs delivery setting, entitlement or scheduling field was changed.
- Published the completed final background reading through the existing coordinator. Both local background paths reject incomplete, invalid, expired, cancelled, empty, and cross-Demo snapshots. No timestamp is invented to make old data look recent.
- Kept widget sharing opt-in and the existing reload throttle. This does not make the notification-service extension a shared-cache writer.
- Added bounded, private scheduling diagnostics in notification settings: requested time, scheduling result, and latest local run outcome. Scheduler acceptance is explicitly separate from execution. No miner identifiers, addresses, readings, or raw errors are stored there.
- Stale widget copy now says to open the app to refresh instead of claiming an unobserved refresh is pending. Small accessory/activity labels use semantic text styles rather than several 7–9 point fixed labels.
- Added eight-point clearance between native Mac settings controls and their separators, outside hit regions. Preserved minimum 44-point targets, no last-row separator gap, full-width charts/hashrate, and the approved restrained layout. iOS native Form separators were not replaced or globally restyled.

## Best next features, in order

### 1. Explicit local widget refresh

Add a read-only App Intent refresh button, then consider a bounded LAN read when the provider is granted execution. This is a proposed next feature, not implemented in this patch.

Use a complete, versioned local target configuration, strict fixed-endpoint GETs, identity checks, cancellation, timeouts, size limits, and an atomic aggregate cache update. Recheck opt-in, fleet generation, and Demo identity after every await. Keep the last valid observation when off-LAN or incomplete, rather than publishing fabricated zeros or calling a denied read an offline miner.

An App Intent can do asynchronous work in the extension process and must finish persisting before returning, after which WidgetKit reloads the timeline. Interactive widgets are supported from iOS 17 [3]. This provides a useful explicit refresh action, not an always-running process.

The app already has a read-only Shortcuts action for its last saved aggregate. That existing action does not fetch current LAN readings. A live local-refresh intent would be a distinct, future capability, with the same consent and bounded-read requirements above.

### 2. Foreground Local Network setup

Guide the person through a successful read in the main app before relying on widget or background LAN reads. Extensions generally share the containing app's Local Network permission. An undetermined permission in the background is denied without a prompt. Simulator tests cannot establish this permission behavior [5]. Do not infer permission merely from a Wi-Fi connection or ATS settings.

### 3. Useful configurations and system styling

Offer a selected-miner widget and a small choice of overview/hashrate/power presentations. A selected-miner widget needs its own consented, timestamped per-miner cache, not a misleading relabel of the existing fleet aggregate. Keep defaults simple. Test tinted/clear appearances, accessibility sizes, privacy redaction, and all supported families. Apple's WWDC26 guidance emphasizes clear, glanceable content, useful configuration, and proper container backgrounds [8].

Keep the existing read-only saved-summary Shortcut; any future live-refresh action can reuse the same App Intent architecture. Do not expose restart, voltage, frequency, or pool writes as casual widget actions.

An optional newer presentation is `systemExtraLargePortrait`, available on iOS, iPadOS and macOS 27, and previously available on visionOS 26. Both WWDC26 and the installed 27.1 SDK confirm this family [8]. It could accommodate a clearly timestamped aggregate or, after building the separately consented cache, selected-miner detail. Keep the existing simpler families first, gate availability for older supported systems, and validate real sizes and Dynamic Type before adoption. No additional family is enabled in this patch.

### 4. Defer server-dependent features until useful

WidgetKit push updates are a separate API and token/capability path, available from iOS 26 in the installed SDK. They require server and provisioning work and remain budgeted. A push-triggered reload of a cache-only provider still does not create fresh LAN data [6]. They are not necessary for the local-first baseline.

`BGContinuedProcessingTaskRequest`, also iOS 26+, is intended to finish foreground-initiated bounded work. A future user-requested large export may fit. It is not an appropriate loophole for permanent miner polling [7]. Do not misuse audio, navigation, background modes, or a Live Activity to keep the app alive.

## Validation and honest limits

The original counts below describe the initial and 06:39 UTC follow-ups, not the latest retry. The 09:52 UTC retry is recorded in `WIDGET-RETRY-2026-10-28.md`: one configured research worker completed both feature and LAN-refresh reviews, and the supplemental measurement's original privacy/readability case now passes after a production typography fix. The medium/large `38W` expectations remain unchanged and red.

Subsequent representative workflow validation is recorded in `WIDGET-WORKFLOW-VALIDATION-2026-10-28.md`. It reproduced and fixed retained-publisher consent revocation, corrected stale VoiceOver copy, and established an actual oversized-image WidgetKit archive failure that resource-alpha tests alone had missed. Fresh installed gallery/Home Screen pixels and return-link acceptance now pass with display-resolution artwork. The original component/OCR assertion failures remain explicitly reported rather than normalized away.

Implementation commit `84afbf8` contains the initial scoped fixes. The bounded follow-up corrects the missed system-launch branding paths and system-facing name metadata without changing networking, hardware-command intents, APNs delivery, storage identity or approved Mac layout. The source/resources audit and selected rendered views are not proof that every installed app, system or tinted surface has been visually accepted.

- Native macOS and shared iOS app/widget/notification-extension/test targets built with complete strict concurrency.
- Final follow-up native validation: **37 tests in six suites passed** after the last source/metadata change, including actual ImageRenderer separator geometry, native report rendering, and full-width/sparse-page layout. The strict-concurrency rebuild also passed. The isolated test runner loads the debug library and test bundle, not the production app entry point. Its first follow-up launch lacked Xcode's XCTest support library path and failed before executing tests. Supplying that loader path resolved the harness issue without a source or assertion change; the initial log is retained.
- Final follow-up isolated iOS validation: **103 of 106 test definitions passed**, across thirteen suites, with no skipped tests. All three new system-launch branding tests and all seventeen existing system-integration tests passed. The final exported production Controls page visibly says `Hash Fleet shortcuts` and shows the approved miner artwork beside Open Hash Fleet. Compiled app/extension names and extracted App Intent metadata agree, while bundle identifiers, executable/module names and the legacy URL remain compatible.
- Resource alpha/cutout checks, branding, refresh, diagnostics, notification settings, backup/report boundaries, PDF, and widget-state/redaction suites passed. The same three component tests retain five exact OCR failures: medium/large widgets expect `38W` while Vision observes `38 W`, and a supplemental activity's visible `TH/s` is omitted by OCR. The earlier initial-patch receipt was 83 of 86 tests across eleven suites. Another earlier run read lowercase `s` as uppercase `S` in an activity. Actual exported pixels show the units and measurements without clipping. These failures were not normalized away, removed, or reclassified as passes. The final selected iOS command therefore exits 65, and full automated visual acceptance is **not** claimed.
- Source comparison with `bf61f6f` confirms that both medium/large power views already used `Text("\(presentation.power) W")`, while the exact OCR assertions already expected `38W`. This is source provenance, not a rerun of the old binary. Correct unit spacing and the existing acceptance assertions remain unchanged rather than being modified solely to produce a pass. The supplemental unit remains a retained recognition/acceptance limitation, not a claimed missing production measurement.
- Final follow-up artifacts: task scratch `hashfleet-local-first-20261028-0639`, `mobile-final2.xcresult`, `mobile-final2-tests.log`, `native-final2-build.log`, and `native-final2-tests.log`. The corrected Controls screenshot is in `system-launch-final-render`. The real pre-fix name failures are retained in `system-name-red.xcresult` and `system-name-red-tests.log`, and the initial native loader failure in `native-tests.log`.
- Initial-patch artifacts remain in `hashfleet-local-first-20261028-0540`: `mobile-final3.xcresult`, `mobile-final3-tests.log`, `native-final3-build.log`, and `native-final3-tests.log`. Brand and small-activity pixel records are in `final-brand-render` and `final-small-render`. Initial Xcode coverage merging stalled after test execution. Only the owned test task was cancelled; final runs disabled optional coverage/verbose failure-diagnostics collection, not test assertions.
- At the initial stage, five configured swarm attempts did not produce completed reviews: saved-account restoration failures, upstream HTTP 400 failures, and one stopped stalled worker. The coordinator completed that stage's source changes and official Apple research directly. In the 09:52 UTC retry, the configured-auto native Claude worker completed a source-backed feature review and a separate local-refresh/privacy follow-up. The other retry failed upstream HTTP 400 before useful work. These are source-only research results, not independent runtime certification. The coordinator re-retrieved the networking, timeline, Local Network privacy and `earliestBeginDate` primary documents.
- No real phone install, push send, server/cron/key change, App Store submission, miner/SSH access, production app activation, or production database mutation was performed for this task.

Physical acceptance still required: Local Network allowed/denied/undetermined, on/off-LAN, locked/unlocked, foreground/background/terminated, Background App Refresh disabled, Low Power Mode, Demo transitions, opt-out, all widget sizes and tinted appearances. A simulator render or successful build is not proof of real background cadence, extension delivery, or current miner reachability.

## Official primary sources

Checked October 28, 2026, and re-read by the coordinator during the 06:39 UTC follow-up. All eight original URLs resolved. Read the full Apple Markdown documentation where the HTML page required JavaScript, and the official WWDC25/26 transcripts. API availability and App Shortcut icon initializers were also checked against the installed iPhoneOS 27.1 SDK interfaces. The retry independently rechecked sources 1, 2, 4 and 5 at about 10:06-10:12 UTC, using full Markdown when the JSON tool response was truncated. The documentation check date does not change an API's introduction version.

1. Apple, Making network requests in a widget extension: `https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension`
2. Apple, Keeping a widget up to date: `https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date`
3. Apple, Adding interactivity to widgets and Live Activities: `https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities`
4. Apple, BGTaskRequest.earliestBeginDate: `https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate`
5. Apple, TN3179 Understanding local network privacy: `https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy`
6. Apple, Updating widgets with WidgetKit push notifications: `https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications`
7. Apple, WWDC25 Finish tasks in the background: `https://developer.apple.com/videos/play/wwdc2025/227/`
8. Apple, WWDC26 WidgetKit foundations: `https://developer.apple.com/videos/play/wwdc2026/277/`
9. Apple, AppShortcut: `https://developer.apple.com/documentation/appintents/appshortcut`
