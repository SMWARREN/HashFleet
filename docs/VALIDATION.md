# Core validation and firmware compatibility

## Scope and result

Validated on **2026-09-06**, using Apple Swift **6.3.3**, Swift Testing **1902**, and macOS **26.6.2** on Apple silicon. The package declares Swift 6 language mode, iOS 17 and macOS 14 deployment minimums.

```sh
swift test
swift test -Xswiftc -warnings-as-errors
swift test -c release -Xswiftc -warnings-as-errors
```

The final warnings-as-errors run passed **41 test functions in 5 suites**, comprising **208 expanded test invocations**. No compiler warnings or test failures remained. SwiftPM also prints an XCTest runner summary of “Executed 0 tests”. That is not the Swift Testing result: use the subsequent “Test run with 41 tests in 5 suites passed” line.

The optimized release build also passed all 41 functions with warnings treated as errors. Three additional `swift test --skip-build` runs passed, checking that the parallel mock fixtures remain isolated across repeated runs.

These tests validate the exported `HashFleetCore` API, without `@testable` access, using the supplied `Package.swift`. They do not build or validate the SwiftUI application, persistence, app permissions, UI confirmation flows, signing, or App Store submission.

**No physical miner was contacted by these core automated tests. No real firmware, pool setting, boot partition, or device state was changed.** Unit HTTP traffic uses per-test ephemeral `URLSession` instances and `URLProtocol` mocks. Each fixture uses a unique reserved `.invalid` hostname. The protocol intercepts every request, including unexpected ones, rather than falling through to real DNS or networking. Shared fixture registration is protected by a lock, so parallel tests do not overwrite one global handler. The coordinator's later user-authorized real-device read-only follow-up is recorded separately in [APP-VALIDATION.md](APP-VALIDATION.md).

## Independent upstream audit

The route inventory was transcribed from the actual registered C handlers, not generated from the client's endpoint catalog. References were fetched on 2026-09-06 and verified against ESP-Miner commit [`2943d206f6c8a4b249bc74c820fb56c874ac316d`](https://github.com/bitaxeorg/ESP-Miner/tree/2943d206f6c8a4b249bc74c820fb56c874ac316d), which was `master` during this audit:

- [`main/http_server/http_server.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/http_server/http_server.c), especially registrations at lines 1866–2062 and their handler implementations.
- [`main/http_server/theme_api.c`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/http_server/theme_api.c), including both registered theme methods.
- [`main/http_server/openapi.yaml`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/main/http_server/openapi.yaml), byte-identical to `docs/esp-miner-openapi.yaml` at audit time.
- [`readme.md`](https://github.com/bitaxeorg/ESP-Miner/blob/2943d206f6c8a4b249bc74c820fb56c874ac316d/readme.md), which still lists a dashboard statistics route absent from the registered handlers.

Audit source SHA-256 checksums:

| Source | SHA-256 |
| --- | --- |
| `http_server.c` | `3511fb32cb75a444ab7c7ae64988652630c71e952193276dca9f233ee413d63c` |
| `theme_api.c` | `1bd3077f226e5b00ee382e5870a10ff6a71af12cd4fb52152a683cba813e8348` |
| `openapi.yaml` | `997ee850648fd8fdcf548760d6497fc1952bb404a93ac7140d6985232dddc7dd` |

### Operation inventory

There are **23 current meaningful operations**, plus **1 separately marked legacy/documentation-only operation** in the client catalog. The OpenAPI document describes only **15 operations** and is therefore not a complete coverage oracle.

| Method | Path | Request body / transport | Evidence |
| --- | --- | --- | --- |
| GET | `/api/system/info` | JSON response | C + OpenAPI |
| GET | `/api/system/asic` | JSON response | C + OpenAPI |
| GET | `/api/system/statistics` | Optional `columns` query | C + OpenAPI |
| GET | `/api/system/scoreboard` | JSON response | C + OpenAPI |
| GET | `/api/system/wifi/scan` | JSON response, 30-second timeout | C + OpenAPI |
| GET | `/api/system/logs` | Plain text download | C + OpenAPI |
| POST | `/api/system/identify` | No body required | C + OpenAPI |
| POST | `/api/system/restart` | No body required | C + OpenAPI |
| POST | `/api/system/pause` | No body required | C + OpenAPI |
| POST | `/api/system/resume` | No body required | C + OpenAPI |
| POST | `/api/system/blockFound/dismiss` | No body required | C + OpenAPI |
| PATCH | `/api/system` | JSON settings object | C + OpenAPI |
| POST | `/api/system/boot` | JSON object containing `partition` | C + OpenAPI |
| PUT | `/api/system/pools/{index}` | JSON pool object, slots 0–7 | C, absent from OpenAPI paths |
| DELETE | `/api/system/pools/{index}` | Slots 0–7 | C, absent from OpenAPI paths |
| POST | `/api/system/OTA` | Raw binary, not multipart or JSON | C + OpenAPI |
| POST | `/api/system/OTAWWW` | Raw binary, not multipart or JSON | C + OpenAPI |
| GET | `/api/theme` | JSON theme response | `theme_api.c`, absent from OpenAPI |
| POST | `/api/theme` | JSON `colorScheme` / `primaryColor` | `theme_api.c`, absent from OpenAPI |
| GET upgrade | `/api/ws` | Log WebSocket | C, absent from OpenAPI |
| GET upgrade | `/api/ws/live` | Live telemetry WebSocket | C, absent from OpenAPI |
| GET | `/recovery` | HTML recovery page | C, absent from OpenAPI |
| OPTIONS | `/api/*` wildcard | Client sends `/api/system/info` | C, absent from OpenAPI |
| GET | `/api/system/statistics/dashboard` | **Legacy/documentation-only** | README only, not registered by audited C |

The two additional C registrations are routing fallbacks, not omitted miner operations: `HTTP_ANY /api/*` returns an unknown-route JSON 404 after access checks, while `GET /*` serves the web UI/static content and related fallback behavior. A literal asterisk URL is not needed to exercise API preflight. Pool wildcard routes are represented by validated concrete slot indices, not arbitrary caller-controlled paths.

## Automated checks

| Area | Concrete checks |
| --- | --- |
| Address validation | IPv4, bare host, mDNS `.local`, HTTP(S), bracketed IPv6 including embedded IPv4, all valid port boundaries, surrounding whitespace/root-slash normalization, host case and default-port canonicalization |
| Address rejection | Empty host, unsupported schemes, user/password and empty-user credentials, paths, query and fragment including empty delimiters, invalid/empty/overflow ports, malformed IPv4/IPv6, unbracketed IPv6, percent escapes/scoped IPv6, embedded control characters, backslashes and invalid DNS labels |
| Identity | Codable device identity retained, equivalent normalized host spellings compare equally, nondefault ports/TLS remain distinct |
| Firmware models | String and number conversions, null/missing/malformed values, all documented facade fields, firmware's lowercase fan keys and uppercase ASIC key, unknown nested data retained, flat object encoding, absent versus zero retained |
| JSON | Structural round trips, nested arrays/objects/null/bools, exact signed/unsigned large integer preservation, pretty-print round trip, safe nonfinite/out-of-range numeric conversion |
| Endpoint coverage | Independent 23-operation current inventory and 1 legacy entry, exact catalog membership, unique IDs, exact methods/case-sensitive paths, WebSocket flags, destructive-operation flags |
| Requests | All 24 operation requests locally inspected, all 22 HTTP operations exercised through injected mocks, every pool slot and invalid index boundary, query encoding and forwarding |
| Headers/timeouts | JSON `Accept`, permissive `Accept` for text/HTML/binary, correct JSON/octet-stream body type, absent bodyless content type, no application-supplied Origin/Authorization, cookies disabled, cache bypass, normal 15-second / scan 30-second / OTA 300-second timeout values |
| HTTP outcomes | All 2xx accepted including empty 204, representative 3xx/4xx/5xx rejected, verbatim error bodies retained including binary/non-UTF-8 and empty bodies, common JSON error shapes, non-HTTP response rejected |
| Transport errors | Timeout, offline, host lookup and cancellation errors propagated, failed mutations not automatically retried |
| JSON mutations | Settings, boot, pool and theme objects encoded without an extra wrapper/stringification, field names/types retained, empty JSON response becomes `.null`, malformed successful JSON is not a fabricated empty snapshot |
| OTA safety | Exact raw binary bytes retained, 300-second timeout, `application/octet-stream`, nil/empty/JSON OTA submissions rejected before network traffic |
| WebSocket boundary | Correct ws/wss scheme/path/port, HTTP execution rejects WebSocket endpoints, stream creation rejects HTTP endpoints, local text/data frame decoding |

The expanded address tests discovered that `http://[192.168.1.1::]` was incorrectly accepted because the parser dropped trailing empty IPv6 components. The core owner fixed the IPv4-tail validation, and the regression test now passes. All changes to core implementation were coordinated with its owner rather than made by the test worker.

### Separate synthetic loopback smoke

The core implementation worker additionally reported a passing real-`URLSession` smoke harness on 2026-09-06. Its Python server and Swift assertions were independently source-reviewed by the test worker, but that separate harness was not rerun by the test worker or added to this package's test target. It bound only `127.0.0.1` on an ephemeral port and was stopped after execution. Reported checks were:

- A real HTTP 307 `Location` redirect remains a visible error with its original body rather than following the target.
- An octet-stream OTA request echoes exactly the synthetic bytes supplied.
- An HTTP/1.1 WebSocket handshake delivers one text frame and one binary frame, then finishes on normal close.
- Cancelling an idle log-stream consuming task completes in under two seconds.

This is supplemental synthetic evidence, not miner or iOS device validation. The scratch harness is not a durable regression test in the repository. Abnormal close, overflow, sustained streaming and real firmware snapshot/diff behavior remain unverified.

## Compatibility and untested boundaries

- **This is a source-level compatibility audit, not a hardware certification or release matrix.** A matching route in current `master` does not establish its first supported firmware release, availability in third-party forks, or behavior on every ASIC/board model. No minimum firmware version is asserted.
- **The legacy dashboard statistics route is not supported by the audited current server registrations.** Expect a 404 on that server rather than treating the README or its presence in the client catalog as proof of support. The current statistics endpoint is separate, and the app should not infer support solely from a version string.
- `SystemInfo`'s OpenAPI schema marks many fields required, but deployed versions can omit or change fields. Display defaults are deliberately tolerant. Zero is a presentation fallback, not proof that an absent/null sensor reading is an actual measured zero. Use `raw` / `value(for:)` when absence matters. Integer raw values remain exact, while a `Double` display conversion can lose precision above 2^53.
- Pool updates require a valid firmware payload, not merely valid JSON. The audited server requires the pool URL, port and user, validates limits and may reject unsupported protocol options. Deleting a slot selected as primary or fallback is explicitly rejected by firmware. Unit transport success does not prove that a supplied configuration is acceptable to a real miner.
- Theme responses use `colorScheme` and `primaryColor`. Statistics data logging may need enabling. Response structures and runtime sensor availability can differ by version and board.
- `is_network_allowed` in audited firmware performs its own network/origin checks, including RFC1918 IPv4 logic. A 401 can mean network access rejection, not missing username/password. The native client does not manufacture an Origin header or perform password authentication. HTTPS syntax support does not mean a miner serves HTTPS or that an untrusted/self-signed certificate will be accepted.
- Address parsing does not resolve DNS, discover mDNS devices, verify reachability, or guarantee IPv6 connectivity through firmware access checks. IPv6 literals require brackets. Scoped/link-local zone identifiers are currently rejected. Host-case/default-port canonicalization is not general DNS alias or full IPv6 textual equivalence resolution.
- These mocks validate **timeout configuration and propagation of a mocked timeout**, not actual elapsed 15/30/300-second network behavior. They validate representative 3xx status handling, not an actual Foundation redirect handshake. The redirect-blocking delegate was source-reviewed, but this unit suite does not prove on-wire redirect suppression.
- No actual `URLSessionWebSocketTask` handshake, live snapshot/diff merge, normal/abnormal close, cancellation cleanup, bounded-buffer overflow, reconnection or long-running stream lifecycle is exercised by the URLProtocol suite. Local frame helpers and protocol selection are tested. A synthetic loopback integration harness or consented hardware session is still required for those boundaries.
- OTA tests use deliberately tiny synthetic byte sequences and mock responses. They do not validate a real firmware image, board/partition compatibility, flash capacity, power-loss recovery, reboot completion, OTAWWW image layout, or preservation of user settings. Never interpret the mock success as approval to flash a device.
- macOS package tests do not validate iOS local-network prompts, ATS policy, Bonjour entitlements/services, background suspension, app lifecycle polling, confirmation dialogs, accessibility, or fleet persistence. Those require app/device integration testing.

## Suggested consented hardware follow-up

1. Record the exact firmware commit/release, board/ASIC, transport, and local-network topology. Start with explicit read-only info/ASIC requests, then statistics, scoreboard and logs. Report unsupported endpoints without retry storms.
2. Verify the iOS permission/ATS flow, host entry, mDNS and IPv4 connectivity, stale/missing sensor presentation, cancellation when leaving a screen, and no accidental automatic mutation.
3. Exercise WebSocket lifecycle and current firmware telemetry format. Do not claim diff-merging correctness from a raw frame stream alone.
4. Test safe reversible mutations only after clear user confirmation. Treat Wi-Fi/pool changes, boot selection, restarts and OTA as potentially connectivity-disrupting operations with an explicit recovery plan.
5. Validate OTA only with the user's chosen board-correct image and deliberate authorization. Keep hardware results separate from these reproducible offline tests.
