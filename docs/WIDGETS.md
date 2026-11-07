# Widgets and Live Activities

HashFleet's glance surfaces show a **cached aggregate fleet snapshot**, not an always-running remote monitor. Widgets do not contact miners. Live Activities receive local updates from the foreground app and do not use APNs or a push server.

## What is shared

The shared `FleetGlance` payload has exactly six fields:

| Field | Meaning |
| --- | --- |
| `updatedAt` | When the aggregate snapshot was captured |
| `onlineCount` | Miners considered online in that snapshot |
| `minerCount` | Number of miners represented |
| `hashrateGHs` | Aggregate hashrate in GH/s |
| `powerWatts` | Aggregate power in watts |
| `isDemo` | Whether these are sample/demo readings |

No device names, IDs, IP addresses, hostnames, pool URLs, usernames, passwords, Wi-Fi credentials, or raw miner responses belong in this cache. Live Activity content wraps the same aggregate object. Its activity name is the generic `HashFleet`, not a miner identifier.

Aggregate hashrate, power and fleet size can still reveal private operational information on a Home Screen or Lock Screen. Sharing is therefore explicit opt-in. Privacy-sensitive rendering is not a promise that nobody can see a widget or an unlocked screen. Do not enable these surfaces if exposing aggregate readings would be inappropriate.

## Home Screen and Lock Screen widgets

The widget named **Fleet at a glance** supports small and medium Home Screen families and inline, circular and rectangular Lock Screen accessory families, subject to the device and iOS surface available.

1. Open HashFleet, connect to your fleet and refresh it in the foreground.
2. Open Settings → Widgets and enable widget sharing. This copies only the aggregate snapshot to the shared App Group container.
3. Add HashFleet from the system widget gallery or Lock Screen customization interface.
4. Tap a widget to open HashFleet when you need newer readings.

The extension reads cached data from shared `UserDefaults`. It does not resolve miner hostnames, discover mDNS devices, poll HTTP endpoints, open WebSockets, or mutate miner settings. It also has no tuning, restart, pool-management or OTA controls. Those remain deliberate in-app operations.

WidgetKit controls when timeline reloads and rendering occur. The app requests reloads after meaningful changes and rate-limits routine reload requests. These are requests, not guaranteed background execution. A widget can continue to show an older snapshot while the app is suspended, force-quit, offline, or not connected to the miners' local network. Open the app to refresh.

Disabling widget sharing clears the shared snapshot and requests a widget reload. The system may retain previously rendered content until it processes the reload. Disabling widget sharing and ending a Live Activity are separate controls. Remove widgets or end the activity as appropriate if you no longer want their cached values displayed.

## Freshness, missing data and demo mode

- The data model treats snapshots **60 seconds old or older** as stale. Exactly 60 seconds is stale.
- A capture time up to five seconds in the future is tolerated as minor clock skew. A time more than five seconds in the future is stale, rather than being trusted indefinitely as fresh.
- An empty fleet is stale even if its timestamp is recent. Missing, corrupt or semantically invalid cached data loads as the explicit empty snapshot.
- Impossible counts, negative or nonfinite readings and nonfinite timestamps are rejected by storage. An invalid save does not replace a previously valid cache entry.
- Reading a snapshot does not rewrite its timestamp. Cached values must never become “fresh” simply because the widget was opened.
- Online counts and hashrate describe the recorded snapshot. A stale snapshot does not prove that the same miners are online now.
- Demo snapshots keep `isDemo` through encoding and storage and must be presented as sample data, not as a live hardware connection.

Freshness is a data rule, not a claim that iOS redraws a widget at an exact wall-clock instant. Timeline entries and ActivityKit stale dates communicate expiration to the system, whose presentation timing remains under OS control.

## Live Activities

Live Activities are optional Lock Screen surfaces, with Dynamic Island presentation on compatible devices. They require a supported iOS device, permitted Live Activities, and a fresh, nonempty fleet snapshot.

- Start one deliberately using the in-app **start Live Activity** control. Merely opening the app, adding a widget, or enabling widget sharing must not silently start an activity.
- The app supplies updates while it is active in the foreground. Each `ActivityContent` uses `updatedAt + 60 seconds` as its `staleDate`.
- **There are no APNs updates, push tokens, push-to-start flow, background miner polling, or always-on monitoring service.** The request uses `pushType: nil`. Suspending or force-quitting the app is not a mechanism for continuing fresh telemetry.
- When updates stop, the previously supplied values become stale. The activity may remain visible with old content until the user or system removes it. Its presence is not proof of a current network connection.
- End the activity explicitly using the in-app **end Live Activity** control. iOS also permits users to dismiss Live Activities. HashFleet does not automatically restart an activity simply because the user dismissed it.
- Publishing an empty fleet or switching between real and demo data ends an existing activity rather than silently replacing its meaning. Starting a new activity after such a change requires explicit intent again.
- If iOS denies Live Activities, review HashFleet's Live Activities permission in Settings. Availability and presentation differ across devices and OS versions. No additional background mode or push entitlement is needed for this local-only implementation.

These surfaces are read-only. Guarded tuning and other miner mutations remain inside the foreground app and are not triggered by a widget refresh or Live Activity update.

## App Group signing setup

The repository's shared container identifier is:

```text
group.app.hashfleet.shared
```

It must agree in **all three** places:

1. `FleetGlanceStorage.appGroup` in `Shared/FleetGlance.swift`.
2. The app entitlement `com.apple.security.application-groups` in `App/Resources/HashFleet.entitlements`.
3. The same entitlement in `Widgets/Resources/HashFleetWidgets.entitlements`.

For your own signed build:

1. Select your Apple development team for both the `HashFleet` application and `HashFleetWidgets` extension targets. The checked-in project does not supply someone else's team or signing identity.
2. Choose bundle identifiers your team controls. The defaults are `app.hashfleet` and `app.hashfleet.widgets`. The extension's identifier should remain appropriately nested under the app identifier.
3. In Xcode **Signing & Capabilities**, add/verify **App Groups** for both targets and select the **same** registered group. If the default group cannot be registered to your team, create your own group and update all three locations above consistently.
4. Ensure the selected provisioning profiles authorize that group for both the app and extension. App Group availability depends on your team's capabilities. Do not assume a Personal Team or an unsigned build proves that production sharing will work.
5. Keep the widget extension embedded in the containing app. `project.yml` is the source of truth for targets, shared source membership and entitlement paths. Preserve any intentional signing changes there before regenerating the Xcode project.
6. Keep `NSSupportsLiveActivities` enabled in the application's `Info.plist` and the widget extension's WidgetKit configuration intact. APNs setup is not part of this feature.
7. Build and install the containing app with its embedded extension, launch the app, explicitly enable sharing, refresh a snapshot, and then add a widget.

The app checks access to the group container. If it is unavailable, storage fails closed: it is unavailable, loads `.empty`, and refuses writes. It does **not** fall back to standard app defaults and pretend the extension can read them. The app's sharing control reports the missing shared container. Fix signing/capability alignment rather than granting broad networking access or copying device credentials into the group.

Simulator behavior does not establish that a physical-device provisioning profile contains the right entitlements. Verify the signed app and extension on the intended device/team before distribution.

## Tests and validation status

`AppTests/FleetGlanceTests.swift` defines **19 Swift Testing functions with 49 expanded cases** for:

- Codable/Hashable round trips, including demo state and timestamp precision.
- Empty storage, save/reload through a new instance, replacement rather than history accumulation, and isolation of injected defaults suites.
- Malformed JSON, missing fields, wrong defaults value types, impossible decoded counts, and recovery after corruption.
- Freshness before and exactly at 60 seconds, tolerated future clock skew through five seconds, and stale future values beyond that allowance.
- Preservation of capture time, empty-fleet staleness, invalid/nonfinite aggregate rejection, unavailable App Group behavior, and clearing only the glance key.
- An exact encoded-field allowlist and scalar-only payload for both direct encoding and persisted data, preventing accidental addition of addresses, credentials or nested raw miner data.
- Coordinator test-mode isolation with widget sharing initially enabled and disabled. Initialization, enabling/disabling sharing, publishing, starting and stopping leave the pre-seeded cache bytes, preferences and existing ActivityKit content unchanged when `isTesting: true`. ActivityKit state is only read for comparison, not seeded or mutated by this test.

All fixtures use unique disposable `UserDefaults` suites. They do not read or write the production App Group, contact a miner, start a real Live Activity or perform a mutation.

Root integration executed all 19 glance test functions successfully in the full native run at 16:19 local time on September 6, 2026. The dedicated ActivityKit UI test also passed and captured the actual simulator Dynamic Island showing labeled sample data, then ended that test activity. See [native validation](APP-VALIDATION.md) for the result bundle and later regression evidence. The file belongs to the native `HashFleetTests` target, so `swift test` alone does not execute it.

Remaining device checks include cross-process App Group access with real signing, widget-gallery installation, all supported family layouts, privacy redaction, OS-controlled stale presentation, app foreground/background transitions, Live Activity permission/start/update/end behavior, Dynamic Island layouts, and behavior after user dismissal or app termination. Model tests do not validate these system UI and lifecycle boundaries.

### Dedicated Live Activity UI acceptance mode

Ordinary unit/UI testing keeps the glance coordinator in `isTesting: true` mode and suppresses widget publishing and ActivityKit mutations. That isolation is intentionally different from exercising the actual system Live Activity interface.

For the dedicated `LiveActivityUITests` acceptance flow, a **Debug-only** launch path permits real ActivityKit requests using these launch arguments together:

```text
--ui-testing --demo --live-activity-ui-test
```

This path uses demo readings, isolated test defaults, unavailable (`nil`) widget storage, and the separate activity name **`HashFleet UI Test`**. It does not publish into the real shared widget cache. The coordinator scopes activity lookup/update/end to its configured name, so this acceptance flow does not target ordinary activities named `HashFleet`.

The `--live-activity-ui-test` opt-in is compiled under `#if DEBUG` and requires testing mode. It is not a production background-monitoring or remote-control feature. Unlike ordinary tests, this dedicated acceptance mode deliberately creates real system-visible Live Activities when its UI actions request them. Use a disposable simulator or explicitly consented test device, end its test activity during cleanup, and keep its results separate from the no-side-effect model/isolation suite. Its existence does not itself establish a passing UI test result.
