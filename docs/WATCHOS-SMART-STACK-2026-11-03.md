# Watch Smart Stack quick launch, November 3, 2026

## Request and scope

The operator asked for a quick way to open Hash Fleet after scrolling up on the Watch. Implementation started November 3 local time, November 4 at 00:07 UTC. This adds a native WidgetKit quick launcher to the Watch Smart Stack. The same extension declares circular and inline watch-face launcher families. It is not a mining-status widget or a background monitor.

Implementation commit: `a4e295c`. Delivered Watch app and embedded extension: version 0.1.0, build 15, minimum watchOS 26.5. Final simulator acceptance completed November 4 at 00:45 UTC, November 3 at 19:45 local time.

## Design and safety

- `WatchWidgets/HashFleetWatchWidget.swift` supplies a standard static widget and rectangular, circular and inline accessory families.
- The rectangular Smart Stack card says **Hash Fleet / Open miners**, with the app's gold accent, a chip symbol and a chevron. Its accessible name is **Open Hash Fleet**, identifier `watch.widget.launch`.
- WidgetKit's default tap opens the containing independent Watch app. No custom URL, App Intent, iPhone handoff or app-navigation change is necessary.
- A single static timeline uses the never-reload policy. There is no miner data, cached hashrate, network request, shared container, app group, sensitive field, new permission or background entitlement in this extension. Its date is timeline infrastructure, not a claimed mining observation.
- Existing Watch app/core source and core tests are unchanged from the pre-widget commit. Opening the app uses its existing immediate refresh, recurring foreground/frontmost polling and background-interrupted scan retry behavior.
- `project.yml` is authoritative. The generated project embeds the extension under the Watch app's `PlugIns` directory, not as a direct iPhone or Mac extension. Watch and widget default versions are both 15. Other product versions are unchanged.
- No physical Smart Stack pinning or watch-face configuration was changed automatically. Those are user-controlled system preferences.

## Final requirement-to-check ledger

| Requirement | Observation | Result |
| --- | --- | --- |
| Existing scan/data/lifecycle logic | Unchanged `swift test --filter HashFleetWatchCoreTests` | 159 tests passed |
| Small-Watch regression | Twelve unchanged fixture cases, 40 mm watchOS 27.0, build 15 with embedded widget | 12/12 passed, 106.174 s, zero skips |
| Actual system gallery, warm tap and cold tap | Real ClockFace Smart Stack on dedicated 44 mm watchOS 26.5 simulator, no demo/fixture app arguments | 1/1 passed, 26.377 s, zero skips |
| Same actual system workflow on small Watch | Real ClockFace Smart Stack on isolated 40 mm watchOS 27.0 simulator, no demo/fixture app arguments | 1/1 passed, 30.472 s, zero skips |
| Readable rendered card and actual app after cold launch | Exported gallery, installed card, framed pre-cold-tap and resulting app screenshots | Visually inspected on both sizes |
| Watch/widget packaging | Simulator and signed generic-watchOS builds | Passed |
| Platform minimum and CPU architectures | Info.plist and device-widget Mach-O load commands | Both arm64 and arm64_32 require watchOS 26.5, built with SDK 27.0 |
| Signature and capabilities | Strict codesign for app and embedded widget, extension entitlements retained privately | Passed, no new app-group/sensor/network/background capabilities |
| Original Watch data backup | Explicit original verified UDID only, successful fresh read-only cache copy at 00:36 UTC | Four saved miners and four readings backed up |
| Physical installation | Watch-only installer succeeded at 00:44:35 UTC | Build 15 installed on original verified Watch |
| Independent installed metadata | Original Watch installed-app inventory at 00:45:15 UTC | Bundle `app.hashfleet.watchkitapp`, build 15, version 0.1.0 confirmed |
| Saved miner preservation after update | Read-only cache copy at 00:46:37 UTC, full saved-miner array compared with fresh preinstall backup | Identical four saved miners, four retained readings, persistence version 1 |
| Physical runtime and widget tap | One normal no-fixture production launch exceeded its 25-second command timeout | Not accepted. Timeout is not a confirmed lock state or a successful physical launch |
| Circular/inline watch-face launchers | Declared families compile and ship in the verified extension | Not separately configured or runtime-tested on a watch face |

The final opt-in UI test actually adds the installed extension from the system gallery, exits editing, taps its real system-hosted card, verifies the app is foreground and shows its real fleet view, terminates the simulator app, and taps the retained card to prove cold launch. No `app.activate()` satisfies either launch assertion. A defer activates the app only for cleanup after failed assertions. Repeated runs replace only this test widget on the explicitly authorized isolated simulator.

## Preserved failures and test-navigation corrections

Early system-UI exploration used the underlying Carousel host, then assumed a long press and an Add Widget button. Actual watchOS 26.5 exposes the foreground ClockFace host, a bottom **Edit** button and an **Add widget** cell. Fast gallery flicks skipped the H section. Small measured drags revealed the real Hash Fleet app row and rendered card. The remote SwiftUI accessibility subtree reports local coordinates, so the test taps the actual containing system cell instead of that untransformed remote element.

The first 40 mm cold-tap run failed because an unnecessary flick left the card beneath the translucent clock header, despite the cell reporting hittable. The test now requires clear framing before tapping and retains a pre-cold-tap screenshot. The cold-launch requirement and timeout were not relaxed. Older-runtime repeated-test setup also exposed a native edit-control lookup issue. Target-specific native remove controls are resolved beside the exact test card without dragging a card in edit mode. All final tests were rerun after the final test-only edit. These are test navigation corrections, not changes to the production widget or app.

Failed logs and complete failed result bundles are retained. Some early older-runtime failed runs did not finalize their result bundles within their bounded timeout or were cancelled after the failure was recorded. None is counted as a pass or a complete result bundle. The successful final `Stack-Verified-44mm.xcresult` and `Stack-Verified-40mm.xcresult` both finalized and report one passed test with zero failures/skips.

The first physical install lost its connection and failed. A fresh read-only installed-app inventory then confirmed build 14. One bounded retry after that verified reconnection succeeded, followed by an independent build-15 inventory. The normal production launch later timed out and its first subsequent data copy lost the tunnel. A separate bounded read-only copy succeeded and verified the preserved saved miners. No device reconnection, pairing or security settings were altered to obtain these results.

## Setup on the physical Watch

Open the updated Hash Fleet app at least once. From the Watch face, swipe up or turn the Crown up to open the Smart Stack. Scroll to **Edit**, choose **Add widget (+)**, select **Hash Fleet**, and tap the **Open Hash Fleet** preview. Pin the card if you want it in a fixed position, then tap **Done**. Tapping the card opens the app. Compatible watch faces also offer the declared circular and inline Hash Fleet families, which have not separately undergone runtime acceptance.

The launcher does not show supposedly live readings while the app is suspended. Actual physical widget tapping, foreground/wrist-down behavior and phone-off miner networking remain separate, unpassed hardware gates. The physical remote-launch timeout does not establish their outcome or cause.

## Preserved boundaries and evidence

The canonical fleet playbook was read before work. Read-only preflight at 00:13 UTC returned HTTP 200 for all eight ASIC info/log GETs. Documented M1 SSH/process/LaunchAgent reads completed, but its loopback XMRig API refused the connection. No fresh M1 mining rate or health claim is inferred from process presence. These are dated checks, not ongoing fleet telemetry.

No ASIC POST/PATCH, reboot, self-test, OTA, voltage/frequency/fan/pool/wiring/protection or recovery-policy change occurred. No mining-Mac service, installed Mac app, iPhone app, pairing, security, passcode or radio setting was changed. No physical app reset or saved-data seeding occurred.

Unrelated pending project, scheme, dependency and other source changes were preserved and excluded from the feature commit. Exact scheme bytes were restored after XcodeGen regeneration. Product source and signed executable hashes remained identical throughout runtime acceptance and physical installation.

Owner-private evidence: `~/.jcode/scratch/hashfleet-smart-stack-20261103T1907/`. This includes raw device receipts, before/after data backups, build/test logs, failed system exploration, complete final result bundles and exported screenshots, and source/binary hashes. Do not publish raw device identities or mining data.

## Primary platform references read

- Apple Developer, **Creating a widget extension**: static configuration, extension packaging and opening the app once before gallery availability.
- Apple Developer, **Creating accessory widgets and watch complications**: watchOS accessory families and Smart Stack support.
- Apple Developer, **Linking to specific app scenes from your widget or Live Activity**: default widget tap opens the containing app.
- Apple Support, **See timely widgets in the Smart Stack on Apple Watch**: swipe-up/Crown access and user-controlled add, pin and Done controls.

The implementation uses Apple's standard pinnable timeline configuration, not relevance-only widgets that people cannot add or pin. No automatic top-of-stack promotion or system preference override is promised.
