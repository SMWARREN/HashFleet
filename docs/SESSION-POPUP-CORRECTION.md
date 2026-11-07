# Inline notification settings and illustrated session records

Local correction, October 24, 2026. This extends the activity workflow documented in `FIRMWARE-TELEMETRY-ACTIVITY.md`. It is not a release or production installation.

**Historical checkpoint:** the later user-requested correction removes the added primary-app activity menus and list picker, restores the original dashboard header, and adds a quiet session-only opt-out on the illustrated session popup. See `NAVIGATION-AND-SESSION-OPTOUT.md`. The counts and screenshots below are retained evidence for this earlier checkpoint, not a fresh verification of the later change.

## Requested behavior

- Keep the alert controls in the existing App settings screen. **Notifications and banners** expands inline rather than pushing a Notifications destination.
- Use the existing illustrated miner popup for session-best records, just as for all-time records and found blocks. A session-best share is not proof of a solved block.
- Remove the session record's transient toast route. Keep ordinary status/safety banners and background system notifications.
- Preview each record above Settings without dismissing the settings sheet or losing its scroll position.
- At this checkpoint, the optional bell activity-list display preference was grouped with notification controls. The later navigation correction removes it and the added primary-app activity entry entirely.

## Implementation boundaries

`FleetNotificationDelivery` is the single event-delivery owner. The app routes record events to `FleetCelebrationQueue` and non-record events to the existing alert center. The former latest-record observers and dashboard session-banner claimant no longer compete with that owner. Alert preferences and one-channel foreground/background delivery still apply.

The queue preserves the current popup until dismissal and retains other records in FIFO order during the running app session. It deduplicates current and pending event IDs. Hydrating the persisted notification inbox no longer silently claims older undelivered records as already shown. This does not promise a durable unacknowledged popup queue across force-quitting the app.

The shared settings controls preserve existing preference keys, permission handling and automation identifiers. The session-preview value comes from the session field, not the all-time field. Tour previews still intentionally finish their lesson before presenting their preview. Settings previews do not close Settings.

## Requirement-to-check receipts

Evidence is retained under `$JCODE_SCRATCH_DIR/hashfleet-session-popup-20261024`.

| Requirement | Observed check |
| --- | --- |
| Notification controls stay inside App settings | Mounted render and UI check the App settings title, expanded state, inline controls, and absence of a Notifications navigation bar |
| Session, all-time and block records reuse the existing illustration | UI previews inspect each record label, mascot, headline and view-miner action |
| Session records do not use the brief toast | Delivery/window tests require an empty toast queue and the session popup. Actual preview UI requires no `inAppAlert.banner` and keeps the session popup visible for 12 seconds |
| Dismissing a preview restores Settings | UI requires the same settings page and preview button to remain hittable at the preserved position after each dismissal |
| Records are not overwritten or replayed twice | Queue tests cover FIFO acknowledgement, current/pending duplicate IDs and empty dismissal. Isolated persisted-inbox tests cover restoration of multiple unseen records and delivery deduplication |
| Existing independent alert choices remain | Model, persistence, menu propagation and UI checks cover the master/session gates, explicit opt-outs, saved activity-list choice and relaunch persistence |
| Accessible activity controls remain usable | Actual desktop-style and largest-text UI checks pass |
| Other settings and lessons remain usable | Fresh-runner checks pass background-alert settings availability and both guided-tour navigation/PDF flows |
| Primary Mac app still compiles | `mac-compatibility.log` records a successful Designed-for-iPad compatibility build, not a native macOS primary-app runtime check |

### Completed verification

- `scoped-units-verified.xcresult` and its log: **127 tests in 12 suites passed**. This includes delivery, lifecycle, persistence, queue, settings and mounted-render checks. The separate real Notification Center suite is not included in that count.
- `settings-popup-ui.xcresult` and its log: **seven UI scenarios passed**. These include the three-kind illustrated preview/return flow, the activity list and menu choices, largest-text reachability, and real simulator permission provisioning.
- `settings-navigation-final.xcresult` and its log: the background-alert availability test and both guided-tour tests passed. The preference/search scenario recorded the retained toggle failure described below.
- `preference-geometry.xcresult`: the original preference on/off, search and persistence assertions passed in a diagnostic repeat with added geometry/screenshot capture.
- `preference-and-popup-final.xcresult`: both illustrated-popup repetitions passed. The preference/search scenario passed once, then failed a compact-card switch assertion in its second repetition. This combined bundle is **not a passing result**.
- `native-switches-final.xcresult` and its log: the complete preference/search scenario **passed twice after the final test edit**, with all original on/off, search and persistence assertions retained.
- `real-system-final.xcresult` and its log: **all 10 real `UNUserNotificationCenter` delivery tests passed**, with no authorization failure or skipped test, on the same provisioned isolated simulator. These are additional to the 127 focused tests.

Across these receipts, all **137 native tests and 11 distinct UI scenarios** have passing current-correction results. The preference/search and illustrated-popup scenarios were also repeated as described above. This is a combined scoped result, not a single fully green whole-app run. The earlier failed attempts remain retained.

## Retained failures and limits

The early unit attempts `initial-units` and `scoped-units` recorded test-only compile failures involving an unavailable environment-key override and a macro/key-path expression. Their raw logs are retained. Mounted-render readiness and an explicit closure corrected those test expressions before the passing 127-test run.

The earlier `settings-navigation-regressions` and `settings-navigation-clean` logs are retained rather than replaced. A fresh isolated derived directory and disposable simulator runner were used to establish the current-source navigation results. The final fresh run recorded one failed realtime-monitoring toggle assertion. All four tests had finished before Xcode stalled collecting optional simulator diagnostics. Only that owned diagnostic subprocess was stopped, allowing Xcode to finalize the failure with exit 65.

The diagnostic-only repeat passed without changing the on/off assertions and captured a fully visible switch row. This does not establish the cause of the earlier missed toggle. A stable-frame wait alone did not resolve the intermittent failure: the next combined run passed the complete preference/search scenario once and both popup repetitions, but failed its second compact-card tap. That failed bundle is retained, and only its optional diagnostic collector was stopped after all tests had finished.

The captured accessibility hierarchy shows that SwiftUI exposes each preference as both a 402-point-wide wrapper row and a separate 63-point-wide native switch. The final test targets that actual child control and waits for its frame to settle rather than tapping a hard-coded normalized coordinate in the wrapper. It retains all original value/search/persistence assertions and makes no production monitoring or compact-card behavior changes. The final two passing repetitions validate this more precise test input, not the root cause of every earlier missed tap.

The earlier whole-native audit remains **1,194 passed and one failed**, as documented in `FIRMWARE-TELEMETRY-ACTIVITY.md`. That earlier receipt is not a rerun of this correction. Its unresolved phone-inset design/test conflict was not changed to manufacture a green full-suite result. Xcode/runtime warnings remain in the raw logs.

Actual simulator screenshots are exported in `ui-review`. The two-page `Notifications-and-record-popups.pdf` walkthrough uses those screenshots and is displayed in the existing review panel. The earlier seven-page overview was also corrected so it no longer describes a separate Notifications destination.

This correction changes no miner settings, power wiring, firmware, mining-host services, production app installation or store release. Simulator authorization/request processing and compatibility builds do not certify physical-device banners, sound, Focus behavior or background execution guarantees.
