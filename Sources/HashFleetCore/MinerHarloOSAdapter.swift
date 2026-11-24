import Foundation

extension MinerFirmwareAdapter {
    internal func pollHarloOS(baseURL: URL, host: String) async throws -> MinerInfo {
        let telemetryData = try await fetchHTTPJSONData(baseURL: baseURL, path: "/api/telemetry", timeout: 15)
        let telemetryDecoded = try JSONDecoder().decode(MinerInfo.self, from: telemetryData)
        guard MinerHTTPDrivers.isHarloOSShape(telemetryDecoded.raw) else {
            throw MinerAPIError.unrecognizedInfo
        }
        var infoDict: [String: JSONValue] = [:]
        if let infoData = try? await fetchHTTPJSONData(baseURL: baseURL, path: "/api/info", timeout: 10),
           let decodedInfo = try? JSONDecoder().decode(MinerInfo.self, from: infoData) {
            infoDict = decodedInfo.raw
        }
        let sample = MinerHTTPDrivers.parseHarloOS(telemetry: telemetryDecoded.raw, info: infoDict, host: host)
        return sample.toMinerInfo(preservingFlatRaw: true)
    }

    internal static func identifyHarloOSViaTelemetry(
        host: String,
        timeout: TimeInterval,
        transport: HTTPTransport
    ) async -> MinerDetectedIdentity? {
        let infoDict = await fetchJSONObject(host: host, path: "/api/info", timeout: timeout, transport: transport)
        let telemetryDict = await fetchJSONObject(
            host: host, path: "/api/telemetry", timeout: timeout, transport: transport
        )
        guard let primary = telemetryDict ?? infoDict,
              MinerHTTPDrivers.isHarloOSShape(primary) else {
            return nil
        }
        let sample = MinerHTTPDrivers.parseHarloOS(
            telemetry: telemetryDict ?? [:],
            info: infoDict ?? [:],
            host: host
        )
        let model = sample.model ?? "Harlo-OS"
        return MinerDetectedIdentity(
            family: "harloOS",
            host: host,
            port: portHTTP,
            mac: sample.mac,
            model: model,
            name: sample.hostname ?? model,
            info: sample.toMinerInfo(preservingFlatRaw: true)
        )
    }

    // MARK: - Harlo-OS Write Helpers

    /// Harlo-OS `PUT /api/tuning` requires both `frequency_mhz` and `core_mv` together.
    /// When only one is supplied, reads the current counterpart from `/api/telemetry` (or profile stock).
    internal func setHarloOSTuning(frequencyMHz: Double?, coreMV: Int?) async throws -> Bool {
        var resolvedFreq = frequencyMHz.map { Int($0.rounded()) }
        var resolvedCore = coreMV
        if resolvedFreq == nil || resolvedCore == nil {
            if let current = try? await info() {
                if resolvedFreq == nil {
                    resolvedFreq = MinerDriverParse.optInt(
                        current.raw["target_frequency_mhz"] ?? current.raw["frequency"]
                    )
                }
                if resolvedCore == nil {
                    resolvedCore = MinerDriverParse.optInt(
                        current.raw["target_core_mv"] ?? current.raw["coreVoltage"]
                    )
                }
            }
        }
        let payload: JSONValue = .object([
            "frequency_mhz": .integer(Int64(resolvedFreq ?? 500)),
            "core_mv": .integer(Int64(resolvedCore ?? 1150))
        ])
        return try await sendCustomHTTP(method: "PUT", path: "/api/tuning", json: payload)
    }

    internal func setHarloOSFanSpeed(_ percent: Int, channel: Int = 1) async throws -> Bool {
        let clamped = max(20, min(100, percent))
        let payload: JSONValue = .object([
            "mode": .string("manual"),
            "percent": .integer(Int64(clamped))
        ])
        return try await sendCustomHTTP(method: "PUT", path: "/api/fans/\(channel)", json: payload)
    }

    internal func setHarloOSAutoFan(
        _ enabled: Bool,
        targetC: Int = 55,
        sensor: String = "asic",
        channel: Int = 1
    ) async throws -> Bool {
        if !enabled {
            return try await setHarloOSFanSpeed(70, channel: channel)
        }
        let clampedTarget = max(30, min(70, targetC))
        let payload: JSONValue = .object([
            "mode": .string("auto"),
            "sensor": .string(sensor),
            "target_c": .integer(Int64(clampedTarget))
        ])
        return try await sendCustomHTTP(method: "PUT", path: "/api/fans/\(channel)", json: payload)
    }

    internal func readHarloOSPoolConfig() async throws -> MinerPoolConfig {
        let data = try await sendCustomHTTPData(method: "GET", path: "/api/pools", body: nil, query: [])
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let dict) = json,
              let pools = dict["pools"]?.arrayValue else {
            throw MinerAPIError.unrecognizedInfo
        }
        let p1 = pools.first(where: { MinerDriverParse.optInt($0.objectValue?["slot"]) == 1 })?.objectValue
            ?? pools.first?.objectValue ?? [:]
        let b1 = p1["backup"]?.objectValue
        let p2 = pools.first(where: { MinerDriverParse.optInt($0.objectValue?["slot"]) == 2 })?.objectValue ?? [:]
        let fbSource = (b1?["host"]?.stringValue?.isEmpty == false) ? b1! : p2

        return MinerPoolConfig(
            url: MinerDriverParse.stripScheme(p1["host"]?.stringValue) ?? (p1["host"]?.stringValue ?? ""),
            port: MinerDriverParse.optInt(p1["port"]) ?? 3333,
            user: p1["user"]?.stringValue ?? "",
            password: "x",
            fbURL: MinerDriverParse.stripScheme(fbSource["host"]?.stringValue) ?? (fbSource["host"]?.stringValue ?? ""),
            fbPort: MinerDriverParse.optInt(fbSource["port"]) ?? 3333,
            fbUser: fbSource["user"]?.stringValue ?? "",
            fbPassword: "x"
        )
    }

    internal func writeHarloOSPoolConfig(_ config: MinerPoolConfig) async throws -> Bool {
        let primaryPayload: JSONValue = .object([
            "host": .string(MinerDriverParse.stripScheme(config.url) ?? config.url),
            "port": .integer(Int64(config.port)),
            "user": .string(config.user),
            "password": .string(config.password),
            "protocol": .string("v1")
        ])
        let ok = try await sendCustomHTTP(method: "PUT", path: "/api/pools/1", json: primaryPayload)
        guard ok else { return false }
        if !config.fbURL.isEmpty {
            let backupPayload: JSONValue = .object([
                "host": .string(MinerDriverParse.stripScheme(config.fbURL) ?? config.fbURL),
                "port": .integer(Int64(config.fbPort)),
                "user": .string(config.fbUser),
                "password": .string(config.fbPassword),
                "protocol": .string("v1")
            ])
            _ = try await sendCustomHTTP(method: "PUT", path: "/api/pools/1/backup", json: backupPayload)
        }
        return true
    }

    // MARK: - Harlo-OS Endpoint Execution

    internal func executeHarloOSEndpoint(
        _ endpoint: MinerEndpoint,
        body: Data?,
        query: [URLQueryItem]
    ) async throws -> Data {
        guard !endpoint.isWebSocket else { throw MinerAPIError.webSocketRequired }
        if endpoint.isBinaryUpload && (body == nil || body?.isEmpty == true) {
            throw MinerAPIError.binaryBodyRequired
        }
        switch endpoint {
        case .info, .options:
            let current = try await info()
            return try JSONEncoder().encode(JSONValue.object(current.raw))
        case .asic, .statistics, .dashboardStatistics, .wifiScan, .logs:
            return try await executeHarloOSReadEndpoint(endpoint, query: query)
        case .restart:
            return try await sendCustomHTTPData(method: "POST", path: "/api/reboot", body: nil, query: query)
        case .pause:
            return try await sendCustomHTTPData(method: "POST", path: "/api/asic/stop", body: nil, query: query)
        case .resume:
            return try await sendCustomHTTPData(method: "POST", path: "/api/asic/start", body: nil, query: query)
        case .dismissBlockFound:
            return try await sendCustomHTTPData(
                method: "POST", path: "/api/block/acknowledge", body: body ?? Data(#"{"id":1}"#.utf8), query: query
            )
        case .otaFirmware:
            return try await sendCustomHTTPData(
                method: "POST", path: "/api/ota", body: body, query: query,
                contentType: "application/octet-stream", timeout: 300
            )
        case .updatePool(let index):
            return try await sendCustomHTTPData(
                method: "PUT", path: "/api/pools/\(max(1, min(4, index + 1)))",
                body: Self.translateHarloOSPoolBody(body), query: query
            )
        case .deletePool(let index):
            return try await sendCustomHTTPData(
                method: "DELETE", path: "/api/pools/\(max(1, min(4, index + 1)))", body: nil, query: query
            )
        case .settings:
            return try await executeHarloOSSettingsBody(body)
        default:
            throw MinerAPIError.http(
                statusCode: 405, message: "Endpoint \(endpoint.path) is not supported by Harlo-OS", body: Data()
            )
        }
    }

    private func executeHarloOSReadEndpoint(
        _ endpoint: MinerEndpoint,
        query: [URLQueryItem]
    ) async throws -> Data {
        switch endpoint {
        case .asic:
            return try await sendCustomHTTPData(method: "GET", path: "/api/info", body: nil, query: query)
        case .statistics, .dashboardStatistics:
            return try await sendCustomHTTPData(method: "GET", path: "/api/history", body: nil, query: query)
        case .wifiScan:
            return try await sendCustomHTTPData(
                method: "GET", path: "/api/wifi/scan", body: nil, query: query, timeout: 30
            )
        default:
            return try await sendCustomHTTPData(method: "GET", path: "/api/logs", body: nil, query: query)
        }
    }

    private func executeHarloOSSettingsBody(_ body: Data?) async throws -> Data {
        guard let body,
              let json = try? JSONDecoder().decode(JSONValue.self, from: body),
              case .object(let dict) = json,
              !dict.isEmpty else {
            throw MinerAPIError.http(statusCode: 400, message: "Invalid Harlo-OS settings payload", body: Data())
        }
        var applied = false

        let freq = MinerDriverParse.optFloat(dict["frequency"] ?? dict["frequency_mhz"])
        let core = MinerDriverParse.optInt(dict["coreVoltage"] ?? dict["core_mv"])
        if freq != nil || core != nil {
            guard try await setHarloOSTuning(frequencyMHz: freq, coreMV: core) else {
                throw MinerAPIError.http(statusCode: 400, message: "Harlo-OS tuning failed", body: Data())
            }
            applied = true
        }

        if try await applyHarloOSFanAndNameSettings(dict) {
            applied = true
        }

        if let sURL = MinerDriverParse.nonEmptyString(dict["stratumURL"]) {
            let cfg = MinerPoolConfig(
                url: sURL,
                port: MinerDriverParse.optInt(dict["stratumPort"]) ?? 3333,
                user: dict["stratumUser"]?.stringValue ?? "",
                password: dict["stratumPassword"]?.stringValue ?? "x",
                fbURL: dict["fallbackStratumURL"]?.stringValue ?? "",
                fbPort: MinerDriverParse.optInt(dict["fallbackStratumPort"]) ?? 3333,
                fbUser: dict["fallbackStratumUser"]?.stringValue ?? "",
                fbPassword: dict["fallbackStratumPassword"]?.stringValue ?? "x"
            )
            guard try await writeHarloOSPoolConfig(cfg) else {
                throw MinerAPIError.http(statusCode: 400, message: "Harlo-OS pool update failed", body: Data())
            }
            applied = true
        }

        guard applied else {
            throw MinerAPIError.http(
                statusCode: 405, message: "No supported Harlo-OS settings keys in payload", body: Data()
            )
        }
        return Data(#"{"ok":true}"#.utf8)
    }

    private func applyHarloOSFanAndNameSettings(_ dict: [String: JSONValue]) async throws -> Bool {
        var applied = false
        let fanPct = MinerDriverParse.optInt(
            dict["manualFanSpeed"] ?? dict["fanspeed"] ?? dict["fanSpeed"] ?? dict["percent"]
        )
        let hasAutoKey = dict["autofanspeed"] != nil
        let autoFlag = MinerDriverParse.coerceFlag(dict["autofanspeed"])
        let targetC = MinerDriverParse.optInt(dict["temptarget"] ?? dict["target_c"])

        if let fanPct, !(hasAutoKey && autoFlag) {
            _ = try await setHarloOSFanSpeed(fanPct)
            applied = true
        } else if hasAutoKey || targetC != nil {
            let isAuto = hasAutoKey ? autoFlag : true
            _ = try await setHarloOSAutoFan(isAuto, targetC: targetC ?? 55)
            applied = true
        }

        if let hostname = MinerDriverParse.nonEmptyString(dict["hostname"] ?? dict["name"]) {
            let payload: JSONValue = .object(["name": .string(hostname)])
            _ = try await sendCustomHTTP(method: "PUT", path: "/api/miner-name", json: payload)
            applied = true
        }
        return applied
    }

    private static func translateHarloOSPoolBody(_ body: Data?) -> Data? {
        guard let body,
              let json = try? JSONDecoder().decode(JSONValue.self, from: body),
              case .object(let dict) = json else {
            return body
        }
        if dict["host"] != nil { return body }
        let proto = (dict["stratumProtocol"]?.stringValue ?? "SV1").lowercased().contains("2") ? "v2" : "v1"
        let translated: JSONValue = .object([
            "host": .string(MinerDriverParse.stripScheme(dict["stratumURL"]?.stringValue) ?? ""),
            "port": .integer(Int64(MinerDriverParse.optInt(dict["stratumPort"]) ?? 3333)),
            "user": .string(dict["stratumUser"]?.stringValue ?? ""),
            "password": .string(dict["stratumPassword"]?.stringValue ?? "x"),
            "protocol": .string(proto)
        ])
        return (try? JSONEncoder().encode(translated)) ?? body
    }
}
