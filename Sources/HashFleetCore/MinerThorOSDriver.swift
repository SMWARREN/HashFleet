import Foundation

// MARK: - ThorOS (Hammer Miner Thor X1 / Thor P2) Read Driver

/// Hammer Miner's closed-source ThorOS firmware does not speak the AxeOS `/api/system/*` API. Its
/// embedded web console (extracted from the published `thorx1-1.0.6` and `thorp2-1.1.0` update
/// images) reads three GET routes and merges them:
///
/// - `GET /v2/device/info`: `device_model`, `firmware_version`, `hardware_version`, `mac_address`,
///   `chip_type`, `detected_chips_count`, `serial_number`.
/// - `GET /v2/device/status`: `uptime_seconds`, `wifi_rssi`, `ip_address`, `free_heap_bytes`.
/// - `GET /v2/miner/status`: `current_hashrate` (H/s), `power_consumption` (W), `temp_board`,
///   `temp_vcore`, `input_voltage` (V), `core_voltage_actual` (V), `frequency` (MHz),
///   `fan_speed_rpm`, `fan_target_speed` (%), `fan_mode` (0 = auto), shares, `bestDiff`, pools.
///
/// Responses may be wrapped as `{"ok": true, "data": {...}}`; both shapes are accepted.
extension MinerHTTPDrivers {
    public static let thorOSInfoPath = "/v2/device/info"
    public static let thorOSStatusPath = "/v2/device/status"
    public static let thorOSMinerStatusPath = "/v2/miner/status"
    public static let thorOSConfigPath = "/v2/miner/config"
    public static let thorOSRebootPath = "/v2/device/reboot"

    /// Unwraps ThorOS's optional `{"ok": ..., "data": {...}}` envelope.
    public static func unwrapThorOSEnvelope(_ data: [String: JSONValue]) -> [String: JSONValue] {
        if let inner = data["data"]?.objectValue, data["ok"] != nil || data.count <= 3 {
            return inner
        }
        return data
    }

    /// Model names published by the ThorOS web console (`THOR X1`, `THOR P2`, ...).
    public static func isThorOSModel(_ value: String?) -> Bool {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !trimmed.isEmpty else { return false }
        return trimmed.hasPrefix("THOR")
    }

    /// Matches a ThorOS `/v2/device/info` or `/v2/miner/status` payload (or the merged form).
    public static func isThorOSShape(_ raw: [String: JSONValue]) -> Bool {
        let data = unwrapThorOSEnvelope(raw)
        if data["firmwareFamily"]?.stringValue == "thorOS" { return true }
        if isThorOSModel(data["device_model"]?.stringValue),
           data["firmware_version"] != nil || data["chip_type"] != nil || data["hardware_version"] != nil {
            return true
        }
        // Miner status: snake_case hashrate in H/s together with ThorOS-specific power/thermal keys.
        guard data["current_hashrate"] != nil else { return false }
        return data["power_consumption"] != nil
            && (data["temp_board"] != nil || data["core_voltage_actual"] != nil)
    }

    /// Parses merged ThorOS info/status/miner payloads into a normalized `MinerWatchSample`.
    public static func parseThorOS(
        info rawInfo: [String: JSONValue] = [:],
        deviceStatus rawStatus: [String: JSONValue] = [:],
        miner rawMiner: [String: JSONValue] = [:],
        host: String = ""
    ) -> MinerWatchSample {
        let info = unwrapThorOSEnvelope(rawInfo)
        let status = unwrapThorOSEnvelope(rawStatus)
        let miner = unwrapThorOSEnvelope(rawMiner)
        let combined = info.merging(status) { old, _ in old }.merging(miner) { _, new in new }

        let hashrateTHs = MinerDriverParse.optFloat(miner["current_hashrate"] ?? combined["current_hashrate"])
            .map { MinerDriverParse.roundTo($0 / 1e12, places: 4) }
        let powerW = MinerDriverParse.optFloat(combined["power_consumption"])
        let efficiency = MinerDriverParse.optFloat(combined["power_efficiency"]).flatMap { $0 > 0 ? $0 : nil }
            ?? {
                guard let hashrateTHs, let powerW, hashrateTHs > 0 else { return nil }
                return MinerDriverParse.roundTo(powerW / hashrateTHs, places: 2)
            }()
        let inputVoltageMV = MinerDriverParse.optFloat(combined["input_voltage"]).map {
            $0 < 100 ? MinerDriverParse.roundTo($0 * 1_000.0, places: 1) : $0
        }
        let coreMV = MinerDriverParse.optFloat(combined["core_voltage_actual"]).map {
            $0 < 50 ? MinerDriverParse.roundTo($0 * 1_000.0, places: 0) : $0
        }
        let fanMode = MinerDriverParse.optInt(combined["fan_mode"])
        let model = MinerDriverParse.nonEmptyString(combined["device_model"]) ?? "ThorOS"
        let poolURL = MinerDriverParse.nonEmptyString(combined["pool_url"])
        let fallbackURL = MinerDriverParse.nonEmptyString(combined["fallback_pool_url"])
        let usingFallback = MinerDriverParse.coerceFlag(combined["isUsingFallbackStratum"])
        let worker = MinerDriverParse.nonEmptyString(combined["pool_worker"] ?? combined["worker_name"])
        let fallbackWorker = MinerDriverParse.nonEmptyString(combined["fallback_pool_worker"])

        var pools: [MinerPoolSnapshot] = []
        if let poolURL {
            pools.append(MinerPoolSnapshot(
                url: poolURL, user: worker, priority: 0,
                accepted: MinerDriverParse.optInt(combined["shares_accepted"]),
                rejected: MinerDriverParse.optInt(combined["shares_rejected"]),
                active: !usingFallback, slot: "primary"
            ))
        }
        if let fallbackURL {
            pools.append(MinerPoolSnapshot(
                url: fallbackURL, user: fallbackWorker, priority: 1, active: usingFallback, slot: "fallback"
            ))
        }

        var raw = combined
        raw["boardVersion"] = combined["hardware_version"] ?? raw["boardVersion"]
        raw["wifiRSSI"] = combined["wifi_rssi"] ?? raw["wifiRSSI"]
        raw["freeHeap"] = combined["free_heap_bytes"] ?? raw["freeHeap"]
        raw["stratumPort"] = combined["pool_port"] ?? raw["stratumPort"]
        raw["fallbackStratumPort"] = combined["fallback_pool_port"] ?? raw["fallbackStratumPort"]
        raw["poolDifficulty"] = combined["stratumDiff"] ?? raw["poolDifficulty"]
        if let fanMode {
            raw["autofanspeed"] = .integer(fanMode == 0 ? 1 : 0)
        }
        if let target = MinerDriverParse.optInt(combined["fan_target_speed"]) {
            raw["manualFanSpeed"] = .integer(Int64(target))
        }
        // ThorOS also reports Wi-Fi credentials on some builds. Never carry them forward.
        for secret in ["wifi_password", "wifiPass", "worker_password", "fallback_pool_password", "pool_password"] {
            raw.removeValue(forKey: secret)
        }

        let bestAllTime = MinerDriverParse.parseSIDifficulty(combined["bestDiff"])
        return MinerWatchSample(
            family: "thorOS",
            host: host,
            online: true,
            miningPaused: MinerDriverParse.coerceFlag(combined["mining_blocked"]) ? true : nil,
            mac: MinerDriverParse.nonEmptyString(combined["mac_address"]).map(MinerDriverParse.formatMAC),
            model: model,
            chipModel: MinerDriverParse.nonEmptyString(combined["chip_type"] ?? combined["asicmodel"]),
            hostname: MinerDriverParse.nonEmptyString(combined["hostname"]) ?? model,
            firmwareVersion: MinerDriverParse.nonEmptyString(combined["firmware_version"]),
            hashrateTHs: hashrateTHs,
            powerW: powerW,
            efficiencyWPerTHs: efficiency,
            inputVoltageMV: inputVoltageMV,
            tempChipC: MinerDriverParse.validTemp(MinerDriverParse.optFloat(combined["temp_board"])),
            tempChip2C: MinerDriverParse.validTemp(MinerDriverParse.optFloat(combined["temp_board_1"])),
            tempVRC: MinerDriverParse.validTemp(MinerDriverParse.optFloat(combined["temp_vcore"])),
            fanRPM: MinerDriverParse.optInt(combined["fan_speed_rpm"]),
            fanPct: MinerDriverParse.optFloat(combined["fan_target_speed"]),
            fanRPM2: MinerDriverParse.optInt(combined["fan_speed_rpm_1"]).flatMap { $0 > 0 ? $0 : nil },
            frequencyMHz: MinerDriverParse.optFloat(combined["frequency"] ?? combined["core_frequency"]),
            voltageMV: coreMV,
            asicCount: MinerDriverParse.optInt(combined["detected_chips_count"]),
            hwErrors: MinerDriverParse.optInt(combined["hwNumber"]),
            uptimeS: MinerDriverParse.optInt(combined["uptime_seconds"]),
            accepted: MinerDriverParse.optInt(combined["shares_accepted"]),
            rejected: MinerDriverParse.optInt(combined["shares_rejected"]),
            bestDifficulty: MinerDriverParse.parseSIDifficulty(combined["bestSessionDiff"]) ?? bestAllTime,
            bestDifficultyAllTime: bestAllTime,
            poolURL: poolURL,
            worker: worker,
            poolURLFallback: fallbackURL,
            workerFallback: fallbackWorker,
            poolActive: poolURL == nil ? nil : (usingFallback ? "fallback" : "primary"),
            pools: pools,
            raw: raw
        )
    }
}

extension MinerHTTPDrivers {
    /// GET-only discovery fallbacks probed when `/api/system/info` is absent: AxeForge, Harlo-OS, ThorOS.
    public static let alternativeDiscoveryPaths = ["/api/status", "/api/telemetry", thorOSInfoPath]

    /// Whether a discovery response from `/api/system/info` should trigger the alternative probes.
    /// ThorOS answers unknown routes with its single-page console (HTML) or a redirect, not a 404.
    public static func shouldProbeAlternativeDiscovery(statusCode: Int, contentType: String?) -> Bool {
        if [404, 405, 501].contains(statusCode) { return true }
        if (300...399).contains(statusCode) { return true }
        guard statusCode == 200, let contentType else { return false }
        return contentType.lowercased().contains("html")
    }

    /// Normalizes a single ThorOS info or miner-status payload seen during discovery.
    public static func thorOSDiscoveryInfo(_ raw: [String: JSONValue], host: String) -> MinerInfo {
        let data = unwrapThorOSEnvelope(raw)
        let isMinerStatus = data["current_hashrate"] != nil
        return parseThorOS(info: isMinerStatus ? [:] : data, miner: isMinerStatus ? data : [:], host: host)
            .toMinerInfo(preservingFlatRaw: true)
    }
}
