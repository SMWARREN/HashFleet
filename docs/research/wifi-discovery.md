# Wi-Fi Discovery for "Find miners on Wi-Fi"

Status: implementation and verification record. The current implementation uses the bounded
same-subnet HTTP tier below. Bonjour remains intentionally unimplemented until an ESP-Miner
service type is verified on hardware.
Scope: replace "type the address by hand" in `AddMinerView` with a one-tap local discovery flow.

## 1. Current state (verified in repo)

- `App/Features/Dashboard/AddMinerView.swift` offers an explicit "Scan nearby miners" action above the manual name + address form. Manual entry remains available before, during and after a scan.
- `App/Features/Dashboard/MinerDiscovery.swift` performs the bounded, read-only scan and validates candidates before offering them as add actions.
- Address validation/normalization lives in `Sources/HashFleetCore/MinerAPIClient.swift` (`validatedURL()`): host or IP, optional http/https scheme, optional port; no paths/credentials. Errors reject anything outside that shape.
- `MinerAPIClient.info()` performs `GET /api/system/info` and then validates the payload with `MinerShapeValidator.isValidInfoShape`, throwing `unrecognizedInfo` otherwise. It already refuses captive-portal HTML (see comment at MinerAPIClient.swift:189). This is the correct "is this really a miner" check and should be reused as the identity proof for discovery results.
- `MinerInfo` (HashFleetCore) exposes identity-ish fields from the raw firmware payload (hostname/model fields via `raw`).
- Entitlements (`App/Resources/HashFleet.entitlements`) currently contain only the app group. No `com.apple.developer.networking.multicast` and no Bonjour capability yet.
- `Info.plist` already has `NSLocalNetworkUsageDescription` (line 16) and ATS `NSAllowsLocalNetworking`. There is **no** `NSBonjourServices` entry, which iOS 14+ requires before any Bonjour browse/resolve can succeed.

## 2. Sources

- Apple: Local Network privacy (iOS 14+): https://support.apple.com/en-us/102229 and "Privacy – local network" (TN + dev docs): https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy — `NSLocalNetworkUsageDescription` + `NSBonjourServices` required; multicast/Broadcast needs the `com.apple.developer.networking.multicast` entitlement.
- Apple Network framework `NWBrowser`: https://developer.apple.com/documentation/network/nwbrowser — Bonjour browsing API with state/failed handling (incl. waiting-for-permission states).
- esp-miner (Bitaxe firmware) API: in-repo `docs/esp-miner-openapi.yaml` (GET /api/system/info). Firmware repo: https://github.com/bitaxeorg/ESP-Miner.
- Apple forums/dev notes: a failed/denied local-network browse surfaces via `NWBrowser` state `.failed` / `.waiting` errors of type `kDNSServiceErr_PolicyDenied` — must be mapped to a "permission denied" UI, not treated as "no miners".

### Verified vs. design

- **Verified (repo):** the current Add Miner flow, strict identity validation, scan bounds, cancellation path and local-network usage declaration in section 1.
- **Verified (source):** Apple requirements above are documented Apple behavior.
- **Not verified here (hardware):** whether ESP-Miner flasher images actually *advertise* a Bonjour service such as `_http._tcp`. Bitaxe units resolve as `<hostname>.local` via mDNS responder, but a browsable service type is not documented in the firmware OpenAPI and a GitHub code search returned no results in this session. The shipped implementation does not depend on Bonjour and uses the bounded same-subnet HTTP probe instead.

## 3. Design

### UX
Add a primary "Find miners on Wi-Fi" button in `AddMinerView` above the manual fields. Tapping it opens an inline discovery section (not a push) with states: scanning / results list / permission denied / no results / error. Manual entry stays as fallback.

### Discovery engine (new, read-only app service)
The shipped `MinerDiscoveryService` is a Sendable, cancellation-aware local-only service:

1. **Same-subnet probe tier (shipped):**
   - Derive the device's own IPv4 address/subnet (esp. Wi-Fi interface en0) with `getifaddrs`; **opt-in only**: the scan runs only after the user taps the button (no background scanning ever).
   - Bounds: probe at most one /24, capped at 32 in-flight requests, per-host timeout 1.0s, and a resource timeout of 8s. It skips the phone's own address, cancels on dismiss/Cancel, and never probes outside RFC1918/link-local addresses derived from the local interface.
   - Probe = `GET http://<host>/api/system/info` only. No other endpoints. **No writes, no PATCH, no auth, no passwords anywhere in the flow.**
2. **Bonjour tier (not shipped):** remains a possible future optimization only after the firmware service type is verified and the required `NSBonjourServices` declaration is added.

### Identity validation
A responder is a candidate miner **only if**: HTTP 200, `Content-Type` JSON, and `MinerShapeValidator.isValidInfoShape` passes on the decoded payload (reuse the exact `info()` path with a per-candidate `MinerDevice`). Arbitrary HTTP responders (routers, printers) are silently dropped. Display name from validated payload fields (e.g. `hostname`/`boardModel`), not from the probe target.

### Error/empty states
- No local private/link-local interface: dedicated unavailable state with "Open Local Network Settings" (`UIApplication.openSettingsURLString`) and copy explaining same-Wi-Fi requirements.
- An empty HTTP result is not treated as proof of permission denial. It is presented as no compatible miner found, with manual entry still visible.
- All probes unreachable alone does **not** prove permission denial. Report no reachable miners or an unknown connectivity problem unless the OS returns an explicit policy-denial error.
- No results: friendly empty state with tips (miner powered on, same Wi-Fi, client isolation on guest networks blocks discovery) and pointer to manual entry.
- Cancellation: tapping Cancel or dismissing cancels the task immediately; no lingering sockets.

### Config/surface changes deferred
- Info.plist should add `NSBonjourServices` only when a real ESP-Miner Bonjour service type is verified and the Bonjour tier is implemented.
- No new entitlements are needed for the shipped bounded HTTP probe.

## 4. Open questions for implementer
- Does shipping ESP-Miner firmware advertise `_http._tcp` (or a custom service)? Verify on hardware before weighting the Bonjour tier. If yes, prefer the most specific service type.
- iPadOS/macOS target scope for the scan bounds.
