# AxeOS Miner Capability Shapes & Recognition Rules

This document specifies the validation criteria, response shape recognition rules, and status classifications for Bitaxe/AxeOS capability probing implemented in `HashFleetCore/MinerCapabilities.swift`.

---

## 1. Probe Architecture Overview

Capability probing executes read-only inspection against a miner to establish what features and endpoints are active and supported:

- **Authorized Endpoints:**
  - `GET /api/system/info` via `MinerEndpoint.info`
  - `GET /api/system/asic` via `MinerEndpoint.asic`
- **Zero Side Effects:** No `POST`, `PUT`, `PATCH`, or `DELETE` requests are ever dispatched during probing.
- **Strict Single-Request Execution:** Exactly one request to `/api/system/info` and one request to `/api/system/asic`.
- **Injected Transport:** Uses the existing `MinerAPIClient` and its underlying injected `URLSession` (enabling isolated `URLProtocol` mocking for tests).
- **Graceful Partial Support:** Probing gathers results for both endpoints independently; if one succeeds while the other is unsupported or fails, the resulting `MinerCapabilityReport` accurately reflects the partial success.
- **Clean Cancellation:** If a task is cancelled, `MinerCapabilityProbe.check()` throws `CancellationError` directly instead of masking it into `.unsupported` or `.failed`.

---

## 2. Status Classification Rules

Each probed endpoint is mapped to `MinerProbeStatus`:

```swift
public enum MinerProbeStatus: Hashable, Sendable {
    case notChecked
    case supported
    case unsupported(statusCode: Int)
    case failed(message: String)
}
```

### HTTP & Transport Status Mapping

| Condition | Probe Status | Rationale |
| :--- | :--- | :--- |
| HTTP 200–299 with valid recognized shape | `.supported` | Endpoint returned expected data conforming to AxeOS schema. |
| HTTP 404 Not Found | `.unsupported(statusCode: 404)` | Firmware does not implement this endpoint route. |
| HTTP 405 Method Not Allowed | `.unsupported(statusCode: 405)` | Firmware does not allow GET on this endpoint route. |
| HTTP 501 Not Implemented | `.unsupported(statusCode: 501)` | Firmware explicitly signals the endpoint is not implemented. |
| HTTP 401 / 403 (Auth / Subnet) | `.failed(message:)` | Device exists but client network address is unauthorized. Never hardware non-support. |
| HTTP 429 Too Many Requests | `.failed(message:)` | Firmware rate-limiting or busy. Never hardware non-support. |
| HTTP 500 / 502 / 503 / 504 | `.failed(message:)` | Internal server or gateway error. Never hardware non-support. |
| Network / Transport Error | `.failed(message:)` | Connection refused, timeout, DNS failure, etc. |
| Malformed JSON (`data` not JSON) | `.failed(message:)` | Firmware returned invalid byte stream, HTML, or corrupted payload. |
| Non-object JSON (`[]`, `"..."`, `null`, `123`) | `.failed(message:)` | Endpoint contract requires a dictionary object. |
| Empty JSON object `{}` | `.failed(message:)` | Unrecognized device payload. |
| Unrecognized JSON object (no recognized keys with valid values) | `.failed(message:)` | Payload does not match known AxeOS shapes (e.g. random web server). |
| Task Cancellation (`CancellationError` / `URLError.cancelled`) | Thrown directly | Never masked into `.unsupported` or `.failed`. |

---

## 3. Object Shape Recognition Rules

To avoid falsely identifying foreign web servers, captive portals, router interfaces, or corrupted responses as miners, payloads must satisfy shape recognition checks.

**Strict Value Validation:** It is not sufficient for a recognized key to merely be present. The value must be meaningful and of expected type:
- Strings must be non-empty (e.g. `{"ASICModel": ""}` or `{"ASICModel": null}` is not accepted).
- Numbers/doubles/integers must be valid finite numbers (e.g. numeric string or JSON number).
- Arrays must be valid JSON arrays (even if empty, or populated with expected items).
- Unknown model strings (e.g. `"BM1397"`, `"BM1373"`, `"CUSTOM_ASIC"`) are completely valid as long as they are non-empty strings.

### Minimal Recognized Keys for `GET /api/system/info`

The JSON payload must be an object (`[String: JSONValue]`) containing at least one recognized field with a valid non-empty/finite value:

- **Hashrate & Performance:**
  - `hashRate`, `hashrate`, `expectedHashrate`, `hashRate_1m`, `hashRate_10m`, `hashRate_1h`: Valid finite Double / Int / numeric string.
  - `errorPercentage`: Valid finite Double / Int.
- **Electrical & Thermals:**
  - `power`, `voltage`, `nominalVoltage`, `current`, `frequency`, `actualFrequency`, `coreVoltage`, `coreVoltageActual`, `temp`, `temp2`, `vrTemp`, `fanspeed`, `fanSpeed`, `fanrpm`, `fanRpm`, `fan2rpm`, `temptarget`: Valid finite Double / Int / numeric string.
- **Shares & Mining:**
  - `sharesAccepted`, `sharesRejected`, `sharesPending`, `uptimeSeconds`: Valid Int / Int-string.
  - `bestDiff`, `bestSessionDiff`, `poolDifficulty`: Non-empty String or valid finite number.
- **Identity & Firmware:**
  - `hostname`, `fullHostname`, `mdnsHostname`, `version`, `axeOSVersion`, `boardVersion`, `deviceModel`, `idfVersion`, `macAddr`: Non-empty String.
  - `ASICModel`, `asicModel`: Non-empty String (any model name, known or unknown).
- **Networking & System:**
  - `stratumURL`, `poolURL`: Non-empty String.
  - `pools`: Array of pool entries.
  - `wifiRSSI`, `wifiRssi`, `freeHeap`: Valid finite Double / Int / numeric string.

An object without at least one recognizable key with a valid typed value is classified as `.failed(message: "Unrecognized /api/system/info response shape")`.

### Minimal Recognized Keys for `GET /api/system/asic`

The JSON payload must be an object (`[String: JSONValue]`) containing at least one recognized ASIC metadata or tuning option field with a valid typed value:

- `ASICModel` or `asicModel`: Non-empty String (any chip model name, known or unknown).
- `deviceModel`: Non-empty String (e.g. "Ultra", "Gamma", "Supra", or any custom name).
- `swarmColor`: Non-empty String.
- `frequencyOptions`: Array of numbers or JSON array.
- `voltageOptions`: Array of numbers or JSON array.
- `defaultFrequency`: Valid finite number.
- `defaultVoltage`: Valid finite number.
- `asicCount` or `chipCount`: Valid finite number.

An object lacking any recognizable key with a valid typed value is classified as `.failed(message: "Unrecognized /api/system/asic response shape")`.

### Non-prescriptive Hardware Rule
- **No specific ASIC model (e.g. BM1366, BM1370) or board version (e.g. Ultra, Gamma, Supra) is mandatory.**
- A miner with a novel ASIC model (e.g. BM1373, BM1397, or unreleased chip) is fully recognized as long as the object shape conforms to AxeOS conventions.
- Missing optional keys represent **Not reported**, never proof of unsupported hardware.
- The presence of fields does not imply safe tuning bounds; client UIs must display reported options as references rather than safe preset boundaries.

---

## 4. Privacy & Secret Sanitization

Error messages generated by `MinerCapabilityProbe` never include:
- Stratum credentials, passwords, or authentication tokens.
- Wi-Fi SSIDs or passphrases.
- Full raw response bodies which may leak internal memory or sensitive tokens.

Error summaries contain strictly sanitized descriptions, such as `"HTTP 401: Unauthorized"` or `"The miner returned an invalid response."`
