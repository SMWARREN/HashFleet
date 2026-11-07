# Hash Fleet on Apple Watch

Hash Fleet includes a native watchOS 26.5+ app. It is independently runnable, not a notification mirror. The paired iPhone is optional after installation and setup.

## What works without the phone

- The Watch stores its own list of up to 16 local ESP-Miner / AxeOS miners.
- While active, it uses high-level `URLSession` HTTP to read each miner's `/api/system/info` directly. It refreshes on open, on request, and every 10 seconds after the previous pass completes while the scene stays active. Passes never overlap. Leaving the active scene cancels the polling task.
- The fleet list shows current reported hashrate and power, with per-metric subtotals when some readings are missing. Details include chip/VR temperature, accepted/rejected shares, uptime and reported pause state.
- Last successful readings and their actual observation times survive app relaunch. Failed reads never replace the cache with zeroes or advance its timestamp. Readings older than 60 seconds are stale and excluded from current totals.
- An empty fleet automatically searches once per app session for compatible local miners and saves those it finds, without typing addresses. **Scan for miners** runs another search on request. Discovery is not repeated by the readings timer.
- Add and remove miners on the Watch itself. Removing only deletes the Watch entry. It does not change the miner or the phone's inventory.

The Watch must be connected to Wi-Fi with a route to those local miner addresses. **Cellular alone cannot reach private home-network addresses.** Away from that network, the app remains usable with explicitly dated cached information. Do not expose a miner API publicly to make this work.

There is no cloud relay, account, continuous background monitoring, guaranteed background refresh, push alert service, or complication in this first Watch implementation. No tuning, pool edits, restart, self-test, firmware upload, or other device write is available on the Watch. XMRig/CPU miners and credential-protected endpoints are not supported by the Watch reader.

## Setup

### Directly on the Watch

1. Connect the Watch itself to the miners’ Wi-Fi and open **Hash Fleet**. watchOS does not have the iPhone's Local Network privacy permission.
2. If its saved list is empty, **Finding miners** starts automatically. It shows checked-address progress and saves compatible miners after the scan finishes. The phone is not required.
3. **Stop search** cancels without changing the saved list. Leaving the app or entering demo also stops discovery. An empty result or interrupted attempt does not automatically restart on every refresh.
4. Use **Scan for miners** to retry or find newly connected miners. Existing saved names, identifiers and cached readings are kept. The Watch holds at most 16 miners and explains when some cannot be added.
5. **Add miner** remains a fallback for a name and local address, for example `192.168.1.50` or `bitaxe.local`. A failed search/read means the Watch could not find/reach it, not proof the hardware is offline.

Discovery uses high-level HTTP only. It derives a private IPv4 address and actual netmask from a single eligible active, broadcast-capable LAN interface, without assuming an interface name, then probes at most one local `/24` (fewer hosts on smaller subnets), excluding the Watch, network and broadcast addresses. Larger LANs are explicitly marked partial. It checks standard HTTP port 80 using only `GET /api/system/info`, with at most 8 concurrent probes and a 60-second overall budget. Redirects, credentials, cookies, oversized responses, HTML and unrelated JSON are refused. Auto-add requires a BM-series ASIC identity plus valid supported telemetry, not merely a responding web page.

A direct LAN interface may be unavailable while the Watch is using only its companion connection. Missing or ambiguous eligible interfaces fail safely with connection guidance instead of a guessed address block. IPv6-only networks, other subnets, custom ports, protected endpoints and XMRig are not automatically discovered. Use manual setup or optional phone import where appropriate. Search results remain an indication of responding compatible APIs, not an authenticated device identity.

Private IPv4 addresses, unqualified local names, and `.local` names are supported. HTTP is the default. HTTPS and explicit valid ports are allowed. Embedded credentials, public addresses, loopback, encoded/obfuscated addresses, paths other than `/`, queries and fragments are rejected. Local HTTP does not encrypt telemetry in transit.

### Optional import from iPhone

1. Install the updated iPhone app and its embedded Watch app.
2. On iPhone, open **App settings → Apple Watch**.
3. Review the eligible miners and tap **Send miners to Watch**.
4. On Watch, review the incoming names/addresses and tap **Import**. **Not now** dismisses that transfer.

Only the allowlisted name, local address and opaque ID are sent through WatchConnectivity. Demo data, XMRig entries, credential-protected entries, raw responses, pool credentials, wallet addresses and Wi-Fi secrets are not exported. Sending queues configuration, not live telemetry. The Watch independently validates the envelope and requires confirmation. Import appends missing endpoints, keeps existing Watch entries and readings, and fails atomically if the combined inventory exceeds 16. Editing the phone's list later does not silently overwrite the Watch's list.

WatchConnectivity is only a setup convenience. Its availability is never required to launch the Watch app, add miners, read its cache, or fetch data. A Watch-local cache uses its own Application Support file and does not depend on the iPhone App Group.

## Demo and privacy

**Try demo** creates a separate fixture-only store with no network or production-cache access. Exit demo to return to the saved Watch fleet. Demo readings must not be mistaken for real miner health.

The cache stores names, local addresses and allowlisted telemetry, not raw device responses. Its iOS/watchOS file protection permits access after the first unlock. No telemetry is uploaded to a service. You can remove saved miners locally on the Watch.

## Build and installation

Use Xcode with a watchOS SDK and an installed compatible Watch simulator runtime. Regenerate `HashFleet.xcodeproj` with `xcodegen generate` after adding sources.

- The **HashFleetWatch** scheme builds/runs the single-target Watch app.
- The **HashFleet** iOS target embeds that app. Its deployment target remains iOS 17.
- Use the existing local signing configuration or select your own team. If changing the iOS bundle ID, also change the Watch bundle ID prefix and `WKCompanionAppBundleIdentifier` in `WatchApp/Resources/Info.plist` to match it. All embedded products must be signed consistently.
- `WKApplication = YES` and `WKRunsIndependentlyOfCompanionApp = YES` identify the independently runnable modern Watch app. A simulator build does not install it on physical hardware.
- For a physical Watch, keep it unlocked and paired with a trusted iPhone. Connect the companion iPhone to the development Mac if Xcode reports stale pairing. Do not erase or unpair the Watch as a build workaround.

```sh
swift test --filter HashFleetWatchCoreTests
xcodebuild -project HashFleet.xcodeproj -scheme HashFleetWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath .build-watch.noindex CODE_SIGNING_ALLOWED=NO build
```

`HashFleetWatchUITests` covers a standalone unpaired Watch simulator, automatic fixture discovery, duplicate-free retries, stopping/backgrounding a scan, unavailable Wi-Fi with manual fallback, demo isolation, manual setup, large text, stale data and unreachable navigation. Core tests use URLProtocol/reading stubs rather than a live subnet scan, including an actual 10-second polling-timer check. `FleetWatchSetupSelectionTests` covers the phone's export boundary. `FleetWatchSettingsUITests` covers phone/tablet settings and lower guidance. See [implementation evidence](WATCHOS-IMPLEMENTATION.md) for actual executed results and limitations.

## Physical phone-off acceptance

After a successful physical installation:

1. With an empty Watch inventory, verify automatic discovery finds and saves a compatible local miner without typing its address. Also verify explicit retry and a successful reading. If testing a nonstandard endpoint, add or explicitly import it instead.
2. Ensure the Watch itself knows and is connected to the miner Wi-Fi.
3. Disconnect/power off the phone. Reopen Hash Fleet on the Watch and tap Refresh.
4. Verify the actual observation timestamp advances and the reading is current. Do not infer this from a simulator or cached reading.
5. Disconnect the Watch from the miner network and verify its last successful time remains unchanged, the failed connection is explained, and current totals exclude it.

This is a test plan, not a claim that these physical steps have passed. Fleet operations remain subject to the canonical operating playbook. No hardware change is needed to test this app.

## Apple references

- [Building a watchOS app](https://developer.apple.com/documentation/watchos-apps/building-a-watchos-app)
- [Creating independent watchOS apps](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps)
- [TN3135: Low-level networking on watchOS](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)
- [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), including the platform table and interface-name guidance
- [WKRunsIndependentlyOfCompanionApp](https://developer.apple.com/documentation/bundleresources/information-property-list/wkrunsindependentlyofcompanionapp)

The client uses supported high-level HTTP, not low-level sockets or a WebSocket background workaround. Hardware networking and OS scheduling still need real-device validation.
