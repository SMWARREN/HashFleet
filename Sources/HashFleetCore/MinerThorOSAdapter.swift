import Foundation

// MARK: - ThorOS polling, identification and writes

extension MinerFirmwareAdapter {
    /// Reads `/v2/miner/status` (required) plus `/v2/device/info` and `/v2/device/status` (best effort).
    internal func pollThorOS(baseURL: URL, host: String) async throws -> MinerInfo {
        let minerData = try await fetchHTTPJSONData(
            baseURL: baseURL, path: MinerHTTPDrivers.thorOSMinerStatusPath, timeout: 15
        )
        let miner = try JSONDecoder().decode(MinerInfo.self, from: minerData).raw
        let info = await thorOSOptionalObject(baseURL: baseURL, path: MinerHTTPDrivers.thorOSInfoPath)
        let status = await thorOSOptionalObject(baseURL: baseURL, path: MinerHTTPDrivers.thorOSStatusPath)
        guard MinerHTTPDrivers.isThorOSShape(miner) || MinerHTTPDrivers.isThorOSShape(info) else {
            throw MinerAPIError.unrecognizedInfo
        }
        let sample = MinerHTTPDrivers.parseThorOS(info: info, deviceStatus: status, miner: miner, host: host)
        return sample.toMinerInfo(preservingFlatRaw: true)
    }

    private func thorOSOptionalObject(baseURL: URL, path: String) async -> [String: JSONValue] {
        guard let data = try? await fetchHTTPJSONData(baseURL: baseURL, path: path, timeout: 10),
              let decoded = try? JSONDecoder().decode(MinerInfo.self, from: data) else { return [:] }
        return decoded.raw
    }

    internal static func identifyThorOS(
        host: String,
        timeout: TimeInterval,
        transport: HTTPTransport
    ) async -> MinerDetectedIdentity? {
        let info = await fetchJSONObject(
            host: host, path: MinerHTTPDrivers.thorOSInfoPath, timeout: timeout, transport: transport
        ) ?? [:]
        let miner = await fetchJSONObject(
            host: host, path: MinerHTTPDrivers.thorOSMinerStatusPath, timeout: timeout, transport: transport
        ) ?? [:]
        guard MinerHTTPDrivers.isThorOSShape(info) || MinerHTTPDrivers.isThorOSShape(miner) else { return nil }
        let sample = MinerHTTPDrivers.parseThorOS(info: info, miner: miner, host: host)
        let model = sample.model ?? "ThorOS"
        return MinerDetectedIdentity(
            family: "thorOS",
            host: host,
            port: portHTTP,
            mac: sample.mac,
            model: model,
            name: sample.hostname ?? model,
            info: sample.toMinerInfo(preservingFlatRaw: true)
        )
    }

    // MARK: Writes (`PUT /v2/miner/config`, keys taken from the ThorOS web console)

    internal func putThorOSConfig(_ fields: [String: JSONValue]) async throws -> Bool {
        try await sendCustomHTTP(method: "PUT", path: MinerHTTPDrivers.thorOSConfigPath, json: .object(fields))
    }

    internal func setThorOSFanSpeed(_ percent: Int) async throws -> Bool {
        try await putThorOSConfig([
            "fan_mode": .integer(1),
            "fan_target_speed": .integer(Int64(max(20, min(100, percent))))
        ])
    }

    internal func setThorOSAutoFan(_ enabled: Bool) async throws -> Bool {
        try await putThorOSConfig(["fan_mode": .integer(enabled ? 0 : 1)])
    }

    /// Frequency takes effect after the next reboot, matching the vendor console.
    internal func setThorOSFrequency(_ mhz: Double) async throws -> Bool {
        try await putThorOSConfig(["core_frequency": .integer(Int64(mhz.rounded()))])
    }

    internal func readThorOSPoolConfig() async throws -> MinerPoolConfig {
        let raw = try await info().raw
        return MinerPoolConfig(
            url: raw["pool_url"]?.stringValue ?? raw["stratumURL"]?.stringValue ?? "",
            port: MinerDriverParse.optInt(raw["pool_port"]) ?? 3333,
            user: raw["pool_worker"]?.stringValue ?? "",
            password: "x",
            fbURL: raw["fallback_pool_url"]?.stringValue ?? "",
            fbPort: MinerDriverParse.optInt(raw["fallback_pool_port"]) ?? 3333,
            fbUser: raw["fallback_pool_worker"]?.stringValue ?? "",
            fbPassword: "x"
        )
    }

    internal func writeThorOSPoolConfig(_ config: MinerPoolConfig) async throws -> Bool {
        var fields: [String: JSONValue] = [
            "pool_url": .string(MinerDriverParse.stripScheme(config.url) ?? config.url),
            "pool_port": .integer(Int64(config.port)),
            "worker_name": .string(config.user),
            "worker_password": .string(config.password)
        ]
        if !config.fbURL.isEmpty {
            fields["fallback_pool_url"] = .string(MinerDriverParse.stripScheme(config.fbURL) ?? config.fbURL)
            fields["fallback_pool_port"] = .integer(Int64(config.fbPort))
            fields["fallback_pool_worker"] = .string(config.fbUser)
            fields["fallback_pool_password"] = .string(config.fbPassword)
        }
        return try await putThorOSConfig(fields)
    }

    internal func executeThorOSEndpoint(
        _ endpoint: MinerEndpoint,
        body: Data?,
        query: [URLQueryItem]
    ) async throws -> Data {
        switch endpoint {
        case .info, .options:
            let current = try await info()
            return try JSONEncoder().encode(JSONValue.object(current.raw))
        case .asic:
            return try await sendCustomHTTPData(
                method: "GET", path: MinerHTTPDrivers.thorOSInfoPath, body: nil, query: query
            )
        case .statistics, .dashboardStatistics:
            return try await sendCustomHTTPData(method: "GET", path: "/v2/miner/hashrate", body: nil, query: query)
        case .logs:
            return try await sendCustomHTTPData(method: "GET", path: "/v2/logs/history", body: nil, query: query)
        case .wifiScan:
            return try await sendCustomHTTPData(
                method: "GET", path: "/v2/network/wifi/list", body: nil, query: query, timeout: 30
            )
        case .restart:
            return try await sendCustomHTTPData(
                method: "POST", path: MinerHTTPDrivers.thorOSRebootPath, body: nil, query: query
            )
        case .settings:
            return try await executeThorOSSettingsBody(body)
        default:
            throw MinerAPIError.http(
                statusCode: 405, message: "Endpoint \(endpoint.path) is not supported by ThorOS", body: Data()
            )
        }
    }

    /// The official API reference documents `core_voltage` as volts but its examples use `120`
    /// (centivolts), so the unit is ambiguous and voltage writes stay disabled until verified.
    /// Translates an AxeOS-style settings PATCH into ThorOS config keys. Core voltage is never
    /// forwarded: ThorOS uses board-specific series-string units that HashFleet has not verified.
    private func executeThorOSSettingsBody(_ body: Data?) async throws -> Data {
        guard let body,
              let json = try? JSONDecoder().decode(JSONValue.self, from: body),
              case .object(let dict) = json else {
            throw MinerAPIError.http(statusCode: 400, message: "Invalid ThorOS settings payload", body: Data())
        }
        var fields: [String: JSONValue] = [:]
        if let freq = MinerDriverParse.optInt(dict["frequency"]) { fields["core_frequency"] = .integer(Int64(freq)) }
        if dict["autofanspeed"] != nil {
            fields["fan_mode"] = .integer(MinerDriverParse.coerceFlag(dict["autofanspeed"]) ? 0 : 1)
        }
        if let fan = MinerDriverParse.optInt(dict["manualFanSpeed"] ?? dict["fanspeed"]) {
            fields["fan_target_speed"] = .integer(Int64(max(20, min(100, fan))))
        }
        let mapping = [
            "stratumURL": "pool_url", "stratumPort": "pool_port", "stratumUser": "worker_name",
            "stratumPassword": "worker_password", "fallbackStratumURL": "fallback_pool_url",
            "fallbackStratumPort": "fallback_pool_port", "fallbackStratumUser": "fallback_pool_worker",
            "fallbackStratumPassword": "fallback_pool_password"
        ]
        for (source, target) in mapping { if let value = dict[source] { fields[target] = value } }
        guard !fields.isEmpty else {
            throw MinerAPIError.http(statusCode: 405, message: "No supported ThorOS settings keys", body: Data())
        }
        return try await sendCustomHTTPData(
            method: "PUT", path: MinerHTTPDrivers.thorOSConfigPath,
            body: try JSONEncoder().encode(JSONValue.object(fields)), query: []
        )
    }
}
