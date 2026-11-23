import Foundation

extension MinerCgminerDrivers {
    /// Checks whether an Avalon `ascset` response succeeded (`STATUS[0].STATUS` is `"S"` or `"I"`).
    public static func isAscsetOK(_ response: [String: JSONValue]) -> Bool {
        if let statusArr = response["STATUS"]?.arrayValue,
           let first = statusArr.first?.objectValue,
           let code = first["STATUS"]?.stringValue {
            return code == "S" || code == "I"
        }
        if let statusObj = response["STATUS"]?.objectValue,
           let code = statusObj["STATUS"]?.stringValue {
            return code == "S" || code == "I"
        }
        return false
    }
}

extension MinerFirmwareAdapter {
    // MARK: - Per-Firmware Endpoint Execution Helpers

    internal func executeNerdQAxeEndpoint(
        _ endpoint: MinerEndpoint,
        body: Data?,
        query: [URLQueryItem]
    ) async throws -> Data {
        switch endpoint {
        case .pause:
            return try await sendCustomHTTPData(
                method: "POST", path: "/api/system/shutdown", body: nil, query: query
            )
        case .resume:
            return try await sendCustomHTTPData(
                method: "POST", path: "/api/system/restart", body: nil, query: query
            )
        case .settings:
            let translated = Self.translateNerdQAxeSettingsBody(body)
            return try await MinerAPIClient(device: device, session: session)
                .execute(endpoint, body: translated, query: query)
        default:
            return try await MinerAPIClient(device: device, session: session)
                .execute(endpoint, body: body, query: query)
        }
    }

    internal func executeWarpAxeEndpoint(
        _ endpoint: MinerEndpoint,
        body: Data?,
        query: [URLQueryItem]
    ) async throws -> Data {
        switch endpoint {
        case .pause:
            return try await sendCustomHTTPData(
                method: "POST", path: "/api/v1/chips/off", body: nil, query: query
            )
        case .resume:
            return try await sendCustomHTTPData(
                method: "POST", path: "/api/v1/chips/on", body: nil, query: query
            )
        case .logs:
            return try await sendCustomHTTPData(
                method: "GET", path: "/api/v1/log", body: nil, query: query
            )
        case .statistics, .dashboardStatistics:
            return try await sendCustomHTTPData(
                method: "GET", path: "/api/v1/history", body: nil, query: query
            )
        default:
            return try await MinerAPIClient(device: device, session: session)
                .execute(endpoint, body: body, query: query)
        }
    }

    internal func executeNmaxeEndpoint(
        _ endpoint: MinerEndpoint,
        body: Data?,
        query: [URLQueryItem]
    ) async throws -> Data {
        if endpoint == .settings {
            guard let translated = Self.translateNmaxePreferenceBody(body) else {
                throw MinerAPIError.http(
                    statusCode: 405,
                    message: "NMAxe only supports fan preference updates via /api/setting/preference",
                    body: Data()
                )
            }
            return try await sendCustomHTTPData(
                method: "PATCH",
                path: "/api/setting/preference",
                body: translated,
                query: query,
                contentType: "application/json"
            )
        }
        return try await MinerAPIClient(device: device, session: session)
            .execute(endpoint, body: body, query: query)
    }

    internal func executeAxeForgeEndpoint(
        _ endpoint: MinerEndpoint,
        body: Data?,
        query: [URLQueryItem]
    ) async throws -> Data {
        guard !endpoint.isWebSocket else { throw MinerAPIError.webSocketRequired }
        if endpoint.isBinaryUpload && (body == nil || body?.isEmpty == true) {
            throw MinerAPIError.binaryBodyRequired
        }
        let headers = ["X-AxeForge": "1"]
        switch endpoint {
        case .info, .options:
            return try await sendCustomHTTPData(method: "GET", path: "/api/status", body: nil, query: query)
        case .asic:
            return try await sendCustomHTTPData(method: "GET", path: "/api/settings", body: nil, query: query)
        case .statistics, .dashboardStatistics:
            return try await sendCustomHTTPData(method: "GET", path: "/api/history", body: nil, query: query)
        case .scoreboard:
            return try await sendCustomHTTPData(method: "GET", path: "/api/scoreboard", body: nil, query: query)
        case .wifiScan:
            return try await sendCustomHTTPData(
                method: "GET", path: "/api/wifi/scan", body: nil, query: query, timeout: 30
            )
        case .logs:
            return try await sendCustomHTTPData(method: "GET", path: "/api/logs", body: nil, query: query)
        case .identify:
            return try await sendCustomHTTPData(
                method: "POST", path: "/api/identify", body: body, query: query, headers: headers
            )
        case .restart:
            return try await sendCustomHTTPData(
                method: "POST", path: "/api/restart", body: nil, query: query, headers: headers
            )
        case .otaFirmware:
            return try await sendCustomHTTPData(
                method: "POST",
                path: "/api/ota",
                body: body,
                query: query,
                contentType: "application/octet-stream",
                headers: headers,
                timeout: 300
            )
        case .settings:
            let translated = Self.translateAxeForgeSettingsBody(body)
            return try await sendCustomHTTPData(
                method: "POST",
                path: "/api/settings",
                body: translated,
                query: query,
                contentType: "application/json",
                headers: headers
            )
        default:
            throw MinerAPIError.http(
                statusCode: 405,
                message: "Endpoint \(endpoint.path) is not supported by AxeForge firmware",
                body: Data()
            )
        }
    }

    internal func executeCanaanEndpoint(_ endpoint: MinerEndpoint, body: Data?) async throws -> Data {
        switch endpoint {
        case .info:
            let current = try await info()
            return try JSONEncoder().encode(JSONValue.object(current.raw))
        case .restart:
            let ok = try await restart()
            guard ok else {
                throw MinerAPIError.http(statusCode: 502, message: "Canaan reboot command failed", body: Data())
            }
            return Data(#"{"STATUS":"S"}"#.utf8)
        case .identify:
            guard try await identify() else {
                throw MinerAPIError.http(statusCode: 502, message: "Avalon LED command failed", body: Data())
            }
            return Data(#"{"STATUS":"S"}"#.utf8)
        case .pause:
            // Avalon hash-board power off (hashpower,0). Resume = reboot.
            guard try await shutdown() else {
                throw MinerAPIError.http(statusCode: 502, message: "Avalon hash power off failed", body: Data())
            }
            return Data(#"{"STATUS":"S"}"#.utf8)
        case .resume:
            guard try await restart() else {
                throw MinerAPIError.http(statusCode: 502, message: "Canaan reboot command failed", body: Data())
            }
            return Data(#"{"STATUS":"S"}"#.utf8)
        case .settings:
            guard let body,
                  let json = try? JSONDecoder().decode(JSONValue.self, from: body),
                  case .object(let dict) = json,
                  !dict.isEmpty else {
                throw MinerAPIError.http(statusCode: 400, message: "Invalid settings body", body: Data())
            }
            let ok = try await applyCanaanSettingsDict(dict)
            guard ok else {
                throw MinerAPIError.http(
                    statusCode: 405, message: "Canaan ascset rejected or unsupported settings", body: Data()
                )
            }
            return Data(#"{"STATUS":"S"}"#.utf8)
        default:
            throw MinerAPIError.http(
                statusCode: 405, message: "Endpoint not supported on Canaan cgminer", body: Data()
            )
        }
    }

    internal func executeReadOnlyCgminerEndpoint(_ endpoint: MinerEndpoint) async throws -> Data {
        if endpoint == .info {
            let current = try await info()
            return try JSONEncoder().encode(JSONValue.object(current.raw))
        }
        throw MinerAPIError.http(
            statusCode: 405,
            message: "Write operation not supported on read-only cgminer driver (\(resolvedFamilyName))",
            body: Data()
        )
    }

    private func applyCanaanSettingsDict(_ dict: [String: JSONValue]) async throws -> Bool {
        var appliedAny = false
        if let freq = MinerDriverParse.optFloat(dict["frequency"]) {
            guard try await setFrequency(freq) else { return false }
            appliedAny = true
        }
        if let mv = MinerDriverParse.optInt(dict["coreVoltage"]) {
            guard try await setVoltage(mv) else { return false }
            appliedAny = true
        }
        let fanPct = MinerDriverParse.optInt(
            dict["manualFanSpeed"] ?? dict["fanspeed"] ?? dict["fanSpeed"]
        )
        let hasAutoKey = dict["autofanspeed"] != nil
        let autoFlag = MinerDriverParse.coerceFlag(dict["autofanspeed"])
        if let fanPct, !(hasAutoKey && autoFlag) {
            guard try await setFanSpeed(fanPct) else { return false }
            appliedAny = true
        } else if hasAutoKey {
            guard try await setAutoFan(autoFlag) else { return false }
            appliedAny = true
        }
        if let wm = MinerDriverParse.optInt(dict["workmode"]) {
            guard try await setWorkmode(wm) else { return false }
            appliedAny = true
        }
        if dict["led"] != nil {
            guard try await setLocatorLED(MinerDriverParse.coerceFlag(dict["led"])) else { return false }
            appliedAny = true
        }
        if dict["hashpower"] != nil {
            // Only switching hash power OFF is a command (A10 `hashpower,0`). Turning it back on
            // requires a reboot, which the caller sends as the separate restart action.
            guard !MinerDriverParse.coerceFlag(dict["hashpower"]), try await powerOffHashBoards() else { return false }
            appliedAny = true
        }
        return appliedAny
    }

    // MARK: - Payload Translators

    public static func translateBitForgeSettingsBody(_ body: Data?) -> Data? {
        guard let body,
              let json = try? JSONDecoder().decode(JSONValue.self, from: body),
              case .object(var dict) = json else {
            return body
        }
        if let fanVal = dict["manualFanSpeed"] ?? dict["fanspeed"] ?? dict["fanSpeed"] {
            dict["fanspeed"] = fanVal
            dict["fanSpeed"] = fanVal
            dict["manualFanSpeed"] = fanVal
            return (try? JSONEncoder().encode(JSONValue.object(dict))) ?? body
        }
        return body
    }

    public static func translateNerdQAxeSettingsBody(_ body: Data?) -> Data? {
        guard let body,
              let json = try? JSONDecoder().decode(JSONValue.self, from: body),
              case .object(var dict) = json else {
            return body
        }
        if let fanVal = dict["manualFanSpeed"], dict["fanspeed"] == nil {
            dict["fanspeed"] = fanVal
            return (try? JSONEncoder().encode(JSONValue.object(dict))) ?? body
        }
        return body
    }

    public static func translateNmaxePreferenceBody(_ body: Data?) -> Data? {
        guard let body,
              let json = try? JSONDecoder().decode(JSONValue.self, from: body),
              case .object(let dict) = json else {
            return nil
        }
        if dict["fans"]?.arrayValue != nil {
            return body
        }
        let fanPct = MinerDriverParse.optInt(
            dict["manualFanSpeed"] ?? dict["fanspeed"] ?? dict["fanSpeed"]
        )
        let hasAutoKey = dict["autofanspeed"] != nil
        let autoFlag = MinerDriverParse.coerceFlag(dict["autofanspeed"])
        if let fanPct, !(hasAutoKey && autoFlag) {
            let clamped = max(0, min(100, fanPct))
            let translated: JSONValue = .object([
                "fans": .array([
                    .object(["id": .integer(0), "auto": .bool(false), "speed": .integer(Int64(clamped))])
                ])
            ])
            return try? JSONEncoder().encode(translated)
        }
        if hasAutoKey {
            let translated: JSONValue = .object([
                "fans": .array([
                    .object(["id": .integer(0), "auto": .bool(autoFlag)])
                ])
            ])
            return try? JSONEncoder().encode(translated)
        }
        return nil
    }

    public static func translateAxeForgeSettingsBody(_ body: Data?) -> Data? {
        guard let body,
              let json = try? JSONDecoder().decode(JSONValue.self, from: body),
              case .object(let dict) = json else {
            return body
        }
        var out: [String: JSONValue] = [:]
        for (key, value) in dict {
            applyAxeForgeSettingKey(key: key, value: value, to: &out)
        }
        return (try? JSONEncoder().encode(JSONValue.object(out))) ?? body
    }

    private static func applyAxeForgeSettingKey(
        key: String,
        value: JSONValue,
        to out: inout [String: JSONValue]
    ) {
        switch key {
        case "frequency":
            if let mhz = MinerDriverParse.optFloat(value) {
                out["freq"] = .integer(Int64(mhz.rounded()))
                out["atune"] = .bool(false)
            }
        case "coreVoltage":
            if let mv = MinerDriverParse.optInt(value) {
                out["mv"] = .integer(Int64(mv))
                out["atune"] = .bool(false)
            }
        case "autofanspeed":
            out["fmode0"] = .integer(MinerDriverParse.coerceFlag(value) ? 0 : 1)
        case "manualFanSpeed", "fanspeed", "fanSpeed":
            if let pct = MinerDriverParse.optInt(value) {
                out["fman0"] = .integer(Int64(max(20, min(100, pct))))
                out["fmode0"] = .integer(1)
            }
        default:
            applyAxeForgeSecondaryKey(key: key, value: value, to: &out)
        }
    }

    private static func applyAxeForgeSecondaryKey(
        key: String,
        value: JSONValue,
        to out: inout [String: JSONValue]
    ) {
        switch key {
        case "minFanSpeed":
            if let pct = MinerDriverParse.optInt(value) {
                out["fanmin"] = .integer(Int64(max(10, min(100, pct))))
            }
        case "temptarget":
            if let temp = MinerDriverParse.optInt(value) {
                out["fantgt"] = .integer(Int64(max(40, min(70, temp))))
            }
        case "rotation":
            if let deg = MinerDriverParse.optInt(value) {
                out["rot180"] = .bool(deg == 180)
            }
        case "displayTimeout":
            if let mins = MinerDriverParse.optInt(value) {
                out["scroff"] = .integer(Int64(max(0, mins)))
            }
        default:
            out[key] = value
        }
    }

    // MARK: - AxeForge Pools Helper

    internal func readAxeForgePoolConfig() async throws -> MinerPoolConfig {
        let data = try await sendCustomHTTPData(method: "GET", path: "/api/pools", body: nil, query: [])
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let dict) = json,
              let pools = dict["pools"]?.arrayValue else {
            throw MinerAPIError.unrecognizedInfo
        }
        let primary = pools.first?.objectValue ?? [:]
        let fallback = pools.dropFirst().first?.objectValue ?? [:]
        let (pHost, pPort) = extractAxeForgePoolHostPort(primary)
        let (fHost, fPort) = extractAxeForgePoolHostPort(fallback)
        return MinerPoolConfig(
            url: pHost,
            port: pPort,
            user: primary["user"]?.stringValue ?? "",
            password: primary["pass"]?.stringValue ?? "x",
            tls: MinerDriverParse.coerceFlag(primary["tls"]),
            fbURL: fHost,
            fbPort: fPort,
            fbUser: fallback["user"]?.stringValue ?? "",
            fbPassword: fallback["pass"]?.stringValue ?? "x",
            fbTLS: MinerDriverParse.coerceFlag(fallback["tls"])
        )
    }

    private func extractAxeForgePoolHostPort(_ pool: [String: JSONValue]) -> (String, Int) {
        let rawHost = pool["url"]?.stringValue ?? pool["host"]?.stringValue ?? ""
        if let explicitPort = MinerDriverParse.optInt(pool["port"]) {
            return (MinerDriverParse.stripScheme(rawHost) ?? rawHost, explicitPort)
        }
        let (host, port) = MinerDriverParse.splitHostPort(url: rawHost, port: nil)
        return (host, port ?? 3333)
    }

    internal func writeAxeForgePoolConfig(_ config: MinerPoolConfig) async throws -> Bool {
        var poolsArray: [JSONValue] = [
            .object([
                "enabled": .bool(!config.url.isEmpty),
                "url": .string(MinerDriverParse.stripScheme(config.url) ?? config.url),
                "port": .integer(Int64(config.port)),
                "user": .string(config.user),
                "pass": .string(config.password)
            ])
        ]
        if !config.fbURL.isEmpty {
            poolsArray.append(
                .object([
                    "enabled": .bool(true),
                    "url": .string(MinerDriverParse.stripScheme(config.fbURL) ?? config.fbURL),
                    "port": .integer(Int64(config.fbPort)),
                    "user": .string(config.fbUser),
                    "pass": .string(config.fbPassword)
                ])
            )
        }
        let payload: JSONValue = .object([
            "pools": .array(poolsArray),
            "mode": .string("failover")
        ])
        return try await sendCustomHTTP(
            method: "POST", path: "/api/pools", json: payload, headers: ["X-AxeForge": "1"]
        )
    }

    // MARK: - Low-Level Transport Helpers

    internal func makeCgminerClient() throws -> CgminerClient {
        let baseURL = try device.validatedURL()
        let host = baseURL.host ?? device.address
        let port = baseURL.port ?? Self.portCgminer
        return CgminerClient(host: host, port: port, timeout: 4.0, transport: cgminerTransport)
    }

    internal func callCanaanAscset(_ parameter: String) async throws -> Bool {
        let cli = try makeCgminerClient()
        let resp = try await cli.call("ascset", parameter: parameter)
        return MinerCgminerDrivers.isAscsetOK(resp)
    }

    internal func sendCustomHTTP(
        method: String,
        path: String,
        json: JSONValue?,
        headers: [String: String] = [:]
    ) async throws -> Bool {
        let encoded = try json.map { try JSONEncoder().encode($0) }
        _ = try await sendCustomHTTPData(
            method: method,
            path: path,
            body: encoded,
            query: [],
            contentType: encoded != nil ? "application/json" : nil,
            headers: headers
        )
        return true
    }

    internal func sendCustomHTTPData(
        method: String,
        path: String,
        body: Data?,
        query: [URLQueryItem],
        contentType: String? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval = 15
    ) async throws -> Data {
        let base = try device.validatedURL()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw MinerAPIError.invalidAddress(device.address)
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw MinerAPIError.invalidAddress(device.address)
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.httpBody = body
        request.setValue(path == "/api/logs" ? "*/*" : "application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        } else if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (headerKey, headerVal) in headers {
            request.setValue(headerVal, forHTTPHeaderField: headerKey)
        }
        let (data, response) = try await session.data(for: request, delegate: AdapterRedirectBlocker())
        guard let http = response as? HTTPURLResponse else {
            throw MinerAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let msg = text.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: http.statusCode) : text
            throw MinerAPIError.http(statusCode: http.statusCode, message: msg, body: data)
        }
        return data
    }
}

private final class AdapterRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
