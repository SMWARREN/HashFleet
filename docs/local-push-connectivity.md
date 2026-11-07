# Local Push Connectivity: removed after Apple's decision

Apple declined Hash Fleet's Local Push Connectivity request on **October 19, 2026**, explaining that the API is intended for VoIP and communication apps in environments where APNs cannot function. The owner supplied that decision on October 24 and requested removal and standard APNs instead.

The rejected `NEAppPushProvider` implementation, target, resources, Network Extension entitlement and SSID/location setup are removed. No shipping configuration embeds that provider. Do not restore it as a workaround. Foreground monitoring, ordinary local notifications, widgets, App Groups and existing quiet record-popup controls remain.

## Corrected product design, October 25

- Controls stay inside the **existing iOS and primary Mac apps**, inline in Notifications. Default off. Per-miner hourly, 3, 6, 12 or 24-hour schedules.
- Preserve the original React marketing/demo website. No browser settings dashboard and no fourth always-on companion app.
- When explicitly activated, private server cron sends a standard APNs alert containing only an opaque miner ID and bounded check metadata. The bundled **notification service extension**, not a persistent process, attempts a short read-only local check before displaying the summary.
- Miner names, private addresses, pinned identity and readings stay on the user's device. The server retains push registration and schedule metadata only. Legacy uploaded-telemetry/relay registrations are not silently migrated into this mode.
- The device needs notification permission, prior Local Network permission, APNs connectivity and a route to the selected miner. Targets currently require canonical RFC1918 IPv4 addresses and a MAC identity prepared from a fresh foreground response. Unknown, unsupported or unreachable targets yield an unavailable message, not a false offline or block-found claim.
- Apple controls delivery and the approximately 30-second extension opportunity. The read itself is bounded below that window. No continuous iPhone monitoring, instant block guarantee or exact hourly execution is promised.

The extension is part of the existing app bundle, not a fourth application. It uses standard UserNotifications, not NetworkExtension, and does not require the declined Local Push entitlement.

## Acceptance and activation boundary

Read `docs/APNS-REPLACEMENT-CONTRACT.md`, `docs/IOS-BUILD-CONFIGURATIONS.md`, `Server/README.md` and `docs/APNS-REPLACEMENT-ACCEPTANCE.md`. No production key, sending cron, physical-app installation or real push is authorized merely by source/fixture tests. A signed, consenting iPhone must prove actual push delivery, Local Network access, identity matching, opt-out and unavailable fallback. Mac compatibility compilation is not Mac notification-extension runtime validation.

Apple references: UserNotifications “Modifying content in newly delivered notifications”, “UNNotificationServiceExtension” and TN3179 “Understanding local network privacy”. These document a bounded opportunity, not a guarantee that this particular device-to-miner path will succeed.
