# Firmware API coverage

## Evidence and scope

Audit date: **2026-09-06**. Compared the checked-in `docs/esp-miner-openapi.yaml` with upstream **master** registrations fetched using `curl`, not a miner:

- [main/http_server/http_server.c](https://github.com/bitaxeorg/ESP-Miner/blob/master/main/http_server/http_server.c), registrations at lines 1866–2062. Retrieved SHA-256: `3511fb32cb75a444ab7c7ae64988652630c71e952193276dca9f233ee413d63c`.
- [main/http_server/theme_api.c](https://github.com/bitaxeorg/ESP-Miner/blob/master/main/http_server/theme_api.c), GET/POST registration and payload handling. Retrieved SHA-256: `1bd3077f226e5b00ee382e5870a10ff6a71af12cd4fb52152a683cba813e8348`.
- [main/http_server/websocket.c](https://github.com/bitaxeorg/ESP-Miner/blob/master/main/http_server/websocket.c) and [websocket_api.c](https://github.com/bitaxeorg/ESP-Miner/blob/master/main/http_server/websocket_api.c), handshake, push format and connection lifecycle.

**23 current operations covered**, including 8 operations absent from OpenAPI. **24 catalog entries** include one explicitly marked legacy/version-dependent README route. All current HTTP operations are accessible through `execute`; all JSON-compatible operations through `executeJSON`; both sockets through `webSocketStream`. The catalog has no arbitrary URL or path constructor.

## Complete operation table

| Case | Method and path | OpenAPI | Behavior / body |
|---|---|---|---|
| `info` | GET `/api/system/info` | Yes | Full system/configuration object, including `pools` and `partitions`. `info()` exposes tolerant metrics and all raw fields. |
| `asic` | GET `/api/system/asic` | Yes | ASIC configuration/monitor data, preserved as raw JSON. |
| `statistics` | GET `/api/system/statistics` | Yes | History. Optional `columns` query is a comma-separated list, e.g. `hashrate,power,asicTemp`. |
| `dashboardStatistics` | GET `/api/system/statistics/dashboard` | **No, legacy only** | Requested README compatibility entry. **Not registered in audited master**, `isLegacy == true`; expect 404 on current firmware. |
| `scoreboard` | GET `/api/system/scoreboard` | Yes | Best-share scoreboard JSON. |
| `wifiScan` | GET `/api/system/wifi/scan` | Yes | Wi-Fi scan JSON, 30-second request timeout. |
| `logs` | GET `/api/system/logs` | Yes | Buffered log response. `execute` retains its exact bytes independent of response content type. |
| `identify` | POST `/api/system/identify` | Yes | Identify device. No body required. |
| `restart` | POST `/api/system/restart` | Yes | Reboot. No automatic retries. |
| `pause` | POST `/api/system/pause` | Yes | Pause mining. |
| `resume` | POST `/api/system/resume` | Yes | Resume mining. |
| `dismissBlockFound` | POST `/api/system/blockFound/dismiss` | Yes | Dismiss block-found notification. |
| `settings` | PATCH `/api/system` | Yes | Arbitrary JSON settings object, preserving firmware's extensible schema. Can include Wi-Fi, voltage/frequency, fan, display, pool-selection and other firmware settings. |
| `boot` | POST `/api/system/boot` | Yes | JSON `{"partition":"ota_0"}`; use an actual `info.partitions` label. |
| `updatePool(index)` | PUT `/api/system/pools/{index}` | **No** | JSON pool configuration. Validate integer index 0...7 locally. Fields include `stratumURL`, `stratumPort`, `stratumUser`, plus protocol/TLS/password/SV2 fields supported by firmware. |
| `deletePool(index)` | DELETE `/api/system/pools/{index}` | **No** | Clear slot 0...7. Firmware rejects deleting selected primary/fallback slots and its message is retained. |
| `otaFirmware` | POST `/api/system/OTA` | Yes | **Raw `application/octet-stream`**, never multipart/JSON. 300-second request timeout. Firmware validates partition/image then reboots. |
| `otaWWW` | POST `/api/system/OTAWWW` | Yes | **Raw `application/octet-stream`** web image. 300-second timeout. |
| `theme` | GET `/api/theme` | **No** | JSON `colorScheme` and `primaryColor`. |
| `updateTheme` | POST `/api/theme` | **No** | JSON strings `colorScheme` and/or `primaryColor`. This is POST, not PATCH. |
| `logWebSocket` | WS GET `/api/ws` | **No** | Push log frames. No subscription message required. |
| `liveWebSocket` | WS GET `/api/ws/live` | **No** | Push `{"event":"update","data":...}` envelopes. First envelope contains full state, subsequent envelopes contain differences. |
| `recovery` | GET `/recovery` | **No** | Recovery **HTML**, not JSON. Use `execute`. |
| `options` | OPTIONS `/api/system/info` | **No** | Exercises registered OPTIONS `/api/*` handler using one fixed safe path. `execute` returns body only, not response headers. |

The firmware also registers `HTTP_ANY /api/*`, which returns JSON 404 `{"error":"unknown route"}`, and GET `/*` for embedded/SPIFFS web files. Those are fallback/static-content routing, not additional API operations. They intentionally do not create an arbitrary-path escape hatch. Firmware 404/captive-portal redirects are not followed.

## Data fidelity and compatibility

- `MinerInfo` decodes directly from the flat API object. Missing/null/wrong-type known values do not fail the entire response. Nonoptional convenience values default to `0`, `false` or an empty string. Call `value(for:)` or inspect `raw` to distinguish missing/malformed data from a genuine zero. Stringified finite numeric metrics are accepted.
- Every unknown field, nested object, array and explicit null remains in `raw`. `JSONValue` preserves Int64/UInt64 counters without Double's 53-bit integer truncation. Nonintegral JSON numbers use Double, so lexical formatting and arbitrary-precision decimals are not preserved. `execute` always returns original bytes for exact archival/export, including successful plain-text responses.
- Firmware units are retained: hash rate GH/s, power W, temperature °C, frequency MHz, voltage/current as firmware exposes them (typically mV/mA). `efficiencyJoulesPerTerahash` explicitly converts GH/s to TH/s. Raw fields remain the source of truth for hardware-specific meaning.
- No settings whitelist discards future fields. Firmware validates body schemas and ranges. The core does not invent unsupported GET-pools routes, theme variants, filesystem paths or mutation retries.
- Firmware versions vary. Inclusion in this master catalog is not capability detection. Older devices can return 404, and the legacy dashboard endpoint can return 404 on newer devices. HTTP errors preserve status, extracted `message`/`error`/`detail`, and the entire original body.

## Network safety and lifecycle

- `MinerDevice.validatedURL()` permits DNS/mDNS names, canonical IPv4, bracketed IPv6, optional HTTP(S) scheme, port 1...65535 and optional root slash. Bare hosts default to LAN HTTP. Returned URLs lowercase hosts and omit default HTTP 80 / HTTPS 443 ports for fleet identity comparisons. No host is contacted during validation.
- Credentials, arbitrary paths, query/fragment in the device address, percent-encoded input, scoped IPv6 zone identifiers, whitespace/control characters, invalid schemes, malformed IPv4/IPv6 and invalid ports are rejected. Standard DNS labels and punycode are supported, underscore hostnames are not.
- Queries are constructed using `URLComponents.queryItems`, never appended as raw URL text. Pool slots are typed integers constrained to 0...7. OPTIONS has a fixed path.
- Explicit timeouts: 15 seconds normally, 30 for scanning, 300 for OTA. These are URLRequest timeouts, not a separate wall-clock deadline. The supplied session can impose stricter resource limits. No automatic retry, reconnection, polling, discovery, or actual miner access occurs.
- API responses bypass local URL cache. Cookies are disabled per request. The client adds no Origin or Authorization header. Normal platform TLS verification remains in place. Every HTTP redirect is refused by a per-task delegate to prevent captive-portal false successes or forwarding a mutation elsewhere. Injected sessions remain caller-owned and may have caller-configured headers/authentication behavior.
- OTA requires a nonempty raw Data body. `executeJSON` rejects OTA. The core does not validate image compatibility, signature or partition capacity, offer upload progress, impose an arbitrary universal firmware size, or spool to disk. Firmware is authoritative. Caller must select the correct image and explicitly confirm the mutation.
- WebSocket URLs map HTTP→WS and HTTPS→WSS. Text and binary frames remain intact. Buffer holds 512 pending frames; overflow explicitly throws `webSocketBufferOverflow` and closes rather than silently losing a state diff. Cancel the task consuming the sequence when leaving a screen, including when breaking iteration early. Normal close finishes, transport errors throw. No automatic merge/reconnect/heartbeat is hidden in the core.
- `/api/ws/live` sends a full initial state only when the firmware live module is initialized, then diffs at a 500ms rate limit when values change. Consumers wanting a derived model must merge according to firmware diff semantics or continue polling `info()` instead. Raw tools can display every envelope without interpreting it.
- A host-only address does not mean LAN-only restriction: an explicitly supplied valid public DNS host is accepted. Callers must only configure devices they intend to contact. App-level local-network permission descriptions and ATS settings are integration responsibilities outside this package.

## Validation and limitations

The core compiled with Swift 6 strict concurrency and warnings-as-errors for both macOS 14 and iOS 17 simulator deployment targets using Foundation only. The independent test worker's suite passes 41 Swift Testing functions across 5 suites, covering endpoint inventory, models, URL boundaries, raw OTA bodies, HTTP status/error behavior, and injected transport. An IPv6 embedded-IPv4 trailing-compression bug found by those tests was corrected and regressed.

Additional scratch-only integration fixtures exercised actual URLSession networking exclusively against a synthetic `127.0.0.1` server on an ephemeral port. Verified actual 307 redirect refusal and body preservation, unwrapped binary upload/echo with octet-stream Content-Type, WebSocket HTTP/1.1 upgrade, text and binary frames, normal close, and idle consumer-task cancellation completing within 2 seconds. The temporary server was terminated afterward. These are synthetic transport checks, not firmware or miner verification.

No real miner was contacted and no real-device OTA/mutation was executed. Live on-device WebSocket interoperability, firmware acceptance of settings, and OTA success cannot be proven by offline and synthetic checks. App integration and durable test ownership remain with the coordinator and other workers.
