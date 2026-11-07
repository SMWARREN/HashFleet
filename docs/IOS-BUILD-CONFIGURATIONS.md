# iOS build configurations

All default configurations now use **standard APNs**, not Local Push Connectivity. The rejected provider implementation, target, Network Extension entitlement and SSID/location setup UI have been removed following Apple's October 19, 2026 decision. Ordinary local notifications, widgets, App Groups and existing shared data remain.

| Configuration | `APS_ENVIRONMENT` | Registration environment |
| --- | --- | --- |
| `Debug` | `development` | APNs sandbox |
| `DebugNoAppPush` | `development` | APNs sandbox |
| `Release` | `production` | APNs production |
| `ReleaseNoAppPush` | `production` | APNs production |

Both app entitlement templates use `aps-environment = $(APS_ENVIRONMENT)`. No shipping configuration defines `APP_PUSH_PROVIDER_ENABLED` or embeds the rejected extension. `HashFleetNoAppPush`, `DebugNoAppPush` and `ReleaseNoAppPush` are retained as legacy scheme/configuration names for existing build scripts. Their names mean no **Local App Push Provider**, not no standard APNs.

Generate the project after changing `project.yml` with `xcodegen generate`. For an unsigned compile and packaging check:

```sh
xcodebuild \
  -project HashFleet.xcodeproj \
  -scheme HashFleetNoAppPush \
  -configuration DebugNoAppPush \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DebugNoAppPush \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For a signed iPhone build, use either app scheme with the matching debug/release configuration. The main provisioning profile must include standard Push Notifications and the existing app group. The new standard `HashFleetNotificationService` extension (`app.hashfleet.notification-service`) needs its own matching profile with `group.app.hashfleet.shared`. Neither target needs Wi-Fi Information, location, Network Extension or Local Push entitlements. Enable Push Notifications for `app.hashfleet` in the Apple Developer account and regenerate the appropriate profile when needed. No App Push Provider approval is required. Unsigned simulator/compatibility builds do not verify provisioning, real device registration, the server's APNs key, or delivery.

Scheduled summaries are off until explicit opt-in and are disabled in demo/test processes. A signed device must grant notification permission and return a current APNs token before the first cloud enrollment. Native iOS and primary Mac settings manage schedules. The original website is retained, and its private API only schedules generic APNs check alerts. A standard notification service extension bundled inside the app attempts GET `/api/system/info` against locally selected, private-IPv4 targets with pinned miner identity. There is no separate LAN companion or browser settings dashboard. See `Server/README.md` and `docs/APNS-REPLACEMENT-CONTRACT.md`. Background summaries do not imply continuous iPhone LAN execution, instant block alerts or exact-hour delivery. Live activation status and acceptance receipts are in `docs/APNS-REPLACEMENT-ACCEPTANCE.md`. The physical iPhone push-to-LAN path and primary Mac notification-extension runtime still require signed device acceptance. Compatibility compilation alone does not establish either.

## Running on a Mac (Apple Silicon)

The iOS target runs unmodified on Apple Silicon Macs as "Designed for iPad". No Catalyst or separate macOS target is needed. Verified October 2, 2026 on macOS 26.6.2 with build 0.1.0 (4): it compiled, signed, launched, and rendered the dashboard and feature tour.

```sh
xcodebuild -project HashFleet.xcodeproj -scheme HashFleetNoAppPush -configuration DebugNoAppPush \
  -destination 'platform=macOS,arch=arm64,variant=Designed for iPad' \
  -derivedDataPath build/MacDesignedForiPad \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

The Mac must be registered in the developer account (`-allowProvisioningDeviceRegistration` does this). The output is an `iphoneos` bundle, so Finder cannot open it directly. Run it from Xcode with the "My Mac (Designed for iPad)" destination, or place it inside a wrapper bundle as `Hash Fleet.app/Wrapper/HashFleet.app` with a `WrappedBundle` symlink pointing to it. A Mac App Store release requires enabling Mac availability for the app in App Store Connect.

`Scripts/package-hashfleet-mac.sh` creates that primary `Hash Fleet.app`
wrapper and includes the shared `hashfleet` executable at
`Hash Fleet.app/CLI/hashfleet`. `Scripts/install-hashfleet-mac.sh` installs the
app and links its bundled CLI into `~/bin`; it does not install the separate
menu-bar companion. The packaging script also emits `dist/Hash Fleet.pkg`,
which installs the primary app and `/usr/local/bin/hashfleet` together. Release
builds can sign that package by setting `HASH_FLEET_INSTALLER_IDENTITY`.
