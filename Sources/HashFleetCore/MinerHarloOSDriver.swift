import Foundation

// MARK: - Harlo-OS (Harlo-OS-V2) Read & Write Driver

extension MinerHTTPDrivers {
    /// Checks whether a JSON object matches Harlo-OS's `/api/info` or `/api/telemetry` schema.
    public static func isHarloOSShape(_ data: [String: JSONValue]) -> Bool {
        if let fw = data["firmware"]?.stringValue?.lowercased(), fw.hasPrefix("harlo-os") {
            return true
        }
        guard data["hashrate_ghs"] != nil || data["target_frequency_mhz"] != nil else {
            return false
        }
        return data["asic_temp_c"] != nil
            || data["device_power_w"] != nil
            || data["asic_paused"] != nil
            || data["miner_name"] != nil
            || data["target_core_mv"] != nil
    }

    /// Parses Harlo-OS `/api/telemetry` (+ optional `/api/info`) into a normalized `MinerWatchSample`.
    public static func parseHarloOS(
        telemetry: [String: JSONValue],
        info: [String: JSONValue] = [:],
        host: String = ""
    ) -> MinerWatchSample {
        let combined = info.merging(telemetry) { _, new in new }
        let profile = combined["profile"]?.objectValue ?? [:]

        let hashrateTHs = MinerDriverParse.optFloat(combined["hashrate_ghs"]).map {
            MinerDriverParse.roundTo($0 / 1_000.0, places: 4)
        }
        let powerW = MinerDriverParse.optFloat(combined["device_power_w"])
            ?? MinerDriverParse.optFloat(combined["asic_rail_power_w"])
        let eff = (hashrateTHs != nil && powerW != nil && (hashrateTHs ?? 0) > 0)
            ? MinerDriverParse.roundTo(powerW! / hashrateTHs!, places: 2) : nil

        let tempChip = MinerDriverParse.validTemp(MinerDriverParse.optFloat(combined["asic_temp_c"]))
        let tempVR = MinerDriverParse.validTemp(MinerDriverParse.optFloat(combined["vr_temp_c"]))
        let freqMHz = MinerDriverParse.optFloat(combined["target_frequency_mhz"])
            ?? MinerDriverParse.optFloat(combined["active_pll_mhz"])
            ?? MinerDriverParse.optFloat(profile["stock_frequency_mhz"])
        let targetCoreMV = MinerDriverParse.optFloat(combined["target_core_mv"])
            ?? MinerDriverParse.optFloat(profile["stock_core_mv"])
        let actualCoreMV = MinerDriverParse.optFloat(combined["core_voltage_mv"]) ?? targetCoreMV
        let inputVoltageMV = MinerDriverParse.optFloat(combined["input_voltage_v"]).map {
            $0 < 100 ? MinerDriverParse.roundTo($0 * 1_000.0, places: 1) : $0
        }
        let currentA = MinerDriverParse.optFloat(combined["asic_regulator_input_current_a"])
            ?? MinerDriverParse.optFloat(combined["asic_core_current_a"])

        let fanResult = parseHarloOSFans(combined["fans"]?.arrayValue ?? [])
        let poolResult = parseHarloOSPools(combined: combined)

        let mac = MinerDriverParse.nonEmptyString(combined["macAddr"] ?? combined["wifi_mac"])
            .map(MinerDriverParse.formatMAC)
        let model = MinerDriverParse.nonEmptyString(profile["name"])
            ?? MinerDriverParse.nonEmptyString(combined["device_model"])
            ?? MinerDriverParse.nonEmptyString(profile["id"])
            ?? "Harlo-OS"
        let hostname = MinerDriverParse.nonEmptyString(combined["miner_name"])
            ?? MinerDriverParse.nonEmptyString(profile["name"])
        let fwVersion = MinerDriverParse.nonEmptyString(combined["firmware_version"])
            ?? MinerDriverParse.nonEmptyString(combined["firmware"])

        let bestSession = MinerDriverParse.parseSIDifficulty(combined["best_share_session"])
        let bestAllTime = MinerDriverParse.parseSIDifficulty(combined["best_share_all_time"])
            ?? poolResult.bestAllTime

        var sample = MinerWatchSample(
            family: "harloOS",
            host: host,
            online: true,
            miningPaused: combined["asic_paused"] != nil
                ? MinerDriverParse.coerceFlag(combined["asic_paused"]) : nil,
            mac: mac,
            model: model,
            chipModel: inferHarloOSChipModel(profile: profile, combined: combined),
            hostname: hostname,
            firmwareVersion: fwVersion,
            hashrateTHs: hashrateTHs,
            powerW: powerW,
            efficiencyWPerTHs: eff,
            inputVoltageMV: inputVoltageMV,
            maxPowerW: MinerDriverParse.optFloat(combined["power_supply_rating_w"])
                ?? MinerDriverParse.optFloat(profile["power_supply_default_w"]),
            tempChipC: tempChip,
            tempVRC: tempVR,
            fanRPM: fanResult.fan1RPM,
            fanPct: fanResult.fan1Pct,
            fanRPM2: fanResult.fan2RPM,
            fanPct2: fanResult.fan2Pct,
            frequencyMHz: freqMHz,
            voltageMV: actualCoreMV,
            voltageSetMV: targetCoreMV,
            asicCount: MinerDriverParse.optInt(profile["asic_count"]),
            currentA: currentA,
            uptimeS: MinerDriverParse.optInt(combined["uptime_seconds"]),
            accepted: poolResult.accepted,
            rejected: poolResult.rejected,
            bestDifficulty: bestSession ?? bestAllTime,
            bestDifficultyAllTime: bestAllTime,
            poolURL: poolResult.primaryURL,
            worker: poolResult.primaryUser,
            poolURLFallback: poolResult.fallbackURL,
            workerFallback: poolResult.fallbackUser,
            poolActive: poolResult.poolActive,
            pools: poolResult.pools,
            blocksFound: poolResult.blocksMined,
            raw: enrichHarloOSRaw(combined: combined, profile: profile, fanResult: fanResult)
        )
        sample.fans = fanResult.snapshots
        sample.fansExtra = fanResult.extra
        // Harlo raises a pending fault notice (title + reason) when a protection trips.
        if MinerDriverParse.coerceFlag(combined["fault_notice_pending"]),
           let title = MinerDriverParse.nonEmptyString(combined["fault_notice_title"]) {
            let reason = MinerDriverParse.nonEmptyString(combined["fault_notice_reason"])
            sample.powerFault = reason.map { "\(title): \($0)" } ?? title
        }
        return sample
    }

    private struct HarloFanParseResult {
        var fan1RPM: Int?
        var fan1Pct: Double?
        var fan2RPM: Int?
        var fan2Pct: Double?
        var isAuto: Bool?
        var targetC: Int?
        var manualPct: Int?
        var snapshots: [MinerFanSnapshot] = []
        var extra: [String: Int] = [:]
    }

    private static func parseHarloOSFans(_ fansArray: [JSONValue]) -> HarloFanParseResult {
        var res = HarloFanParseResult()
        for (idx, item) in fansArray.enumerated() {
            guard let f = item.objectValue else { continue }
            let ch = MinerDriverParse.optInt(f["channel"]) ?? (idx + 1)
            let rpm = MinerDriverParse.optInt(f["rpm"])
            let pct = MinerDriverParse.optFloat(f["percent"] ?? f["manual_percent"] ?? f["applied_percent"])
            if ch == 1 || (idx == 0 && res.fan1Pct == nil && res.fan1RPM == nil) {
                res.fan1RPM = rpm
                res.fan1Pct = pct
                if let mode = f["mode"]?.stringValue?.lowercased() {
                    res.isAuto = (mode == "auto")
                }
                res.targetC = MinerDriverParse.optInt(f["target_c"])
                res.manualPct = MinerDriverParse.optInt(f["manual_percent"] ?? f["percent"])
            } else if ch == 2 || idx == 1 {
                res.fan2RPM = rpm
                res.fan2Pct = pct
            }
            if let rpm { res.extra["fan\(ch)"] = rpm }
            res.snapshots.append(MinerFanSnapshot(id: ch, rpm: rpm, speedPct: pct))
        }
        return res
    }

    private struct HarloPoolParseResult {
        var primaryURL: String?
        var primaryUser: String?
        var fallbackURL: String?
        var fallbackUser: String?
        var poolActive: String?
        var accepted: Int?
        var rejected: Int?
        var blocksMined: Int?
        var bestAllTime: Double?
        var pools: [MinerPoolSnapshot] = []
    }

    private static func parseHarloOSPools(combined: [String: JSONValue]) -> HarloPoolParseResult {
        var res = HarloPoolParseResult()
        let rawPools = combined["pools"]?.arrayValue ?? []
        var totalAccepted = 0
        var totalRejected = 0
        var totalBlocks = 0
        var hasShares = false
        var hasBlocks = false
        let topPing = MinerDriverParse.optFloat(combined["pool_latency_ms"])

        for (idx, item) in rawPools.enumerated() {
            guard let p = item.objectValue else { continue }
            let slotNum = MinerDriverParse.optInt(p["slot"]) ?? (idx + 1)
            let hostStr = MinerDriverParse.nonEmptyString(p["host"])
            let port = MinerDriverParse.optInt(p["port"])
            let url: String? = hostStr.map { h in
                if let port, port > 0, !h.contains(":") { return "\(h):\(port)" }
                return h
            }
            let user = MinerDriverParse.nonEmptyString(p["user"])
            let acc = MinerDriverParse.optInt(p["accepted_shares"])
            let rej = MinerDriverParse.optInt(p["rejected_shares"])
            let blk = MinerDriverParse.optInt(p["blocks_mined"])
            if let acc { totalAccepted += acc; hasShares = true }
            if let rej { totalRejected += rej; hasShares = true }
            if let blk { totalBlocks += blk; hasBlocks = true }
            if let best = MinerDriverParse.parseSIDifficulty(p["best_share_all_time"]) {
                res.bestAllTime = max(res.bestAllTime ?? 0, best)
            }
            let activeEndpoint = p["active_endpoint"]?.stringValue?.lowercased()
            let connected = (p["connected"]?.boolValue == true)
                || (activeEndpoint != nil && activeEndpoint != "offline")
            let ping = MinerDriverParse.optFloat(p["latency_ms"]) ?? (connected ? topPing : nil)
            let slotLabel = slotNum == 1 ? "primary" : (slotNum == 2 ? "fallback" : "pool_\(slotNum)")

            if slotNum == 1, let url {
                res.primaryURL = url
                res.primaryUser = user
                if activeEndpoint == "backup",
                   let bObj = p["backup"]?.objectValue,
                   let bHost = MinerDriverParse.nonEmptyString(bObj["host"]) {
                    let bPort = MinerDriverParse.optInt(bObj["port"])
                    res.fallbackURL = (bPort != nil && bPort! > 0) ? "\(bHost):\(bPort!)" : bHost
                    res.fallbackUser = MinerDriverParse.nonEmptyString(bObj["user"])
                    res.poolActive = "fallback"
                } else if connected {
                    res.poolActive = "primary"
                }
            } else if slotNum == 2, let url, res.fallbackURL == nil {
                res.fallbackURL = url
                res.fallbackUser = user
                if connected && res.poolActive == nil { res.poolActive = "fallback" }
            }

            if let url {
                res.pools.append(MinerPoolSnapshot(
                    url: url, user: user, status: connected ? "alive" : "dead",
                    priority: slotNum - 1, accepted: acc, rejected: rej,
                    active: connected, slot: slotLabel, pingMs: ping
                ))
            }
        }

        res.accepted = hasShares ? totalAccepted : MinerDriverParse.optInt(combined["accepted_shares"])
        res.rejected = hasShares ? totalRejected : MinerDriverParse.optInt(combined["rejected_shares"])
        res.blocksMined = hasBlocks ? totalBlocks : nil
        if res.poolActive == nil && res.primaryURL != nil { res.poolActive = "primary" }
        return res
    }

    private static func inferHarloOSChipModel(
        profile: [String: JSONValue],
        combined: [String: JSONValue]
    ) -> String? {
        if let explicit = MinerDriverParse.nonEmptyString(profile["asic_model"] ?? combined["ASICModel"]) {
            return explicit
        }
        if combined["bm1373_counters"] != nil { return "BM1373" }
        if combined["bm1370_counters"] != nil { return "BM1370" }
        let pid = (profile["id"]?.stringValue ?? "").lowercased()
        if pid.contains("b30") || pid.contains("thor") || pid.contains("nexus-s1") { return "BM1373" }
        if pid.contains("gamma") || pid.contains("nerdqaxe") || pid.contains("nerdoctaxe")
            || pid.contains("bitfortun") || pid.contains("naja") {
            return "BM1370"
        }
        return nil
    }

    private static func enrichHarloOSRaw(
        combined: [String: JSONValue],
        profile: [String: JSONValue],
        fanResult: HarloFanParseResult
    ) -> [String: JSONValue] {
        var out = combined
        if let modelName = MinerDriverParse.nonEmptyString(profile["name"] ?? profile["id"]),
           out["boardVersion"] == nil {
            out["boardVersion"] = .string(modelName)
        }
        if let isAuto = fanResult.isAuto {
            out["autofanspeed"] = .integer(isAuto ? 1 : 0)
        }
        if let targetC = fanResult.targetC {
            out["temptarget"] = .integer(Int64(targetC))
        }
        if let manualPct = fanResult.manualPct {
            out["manualFanSpeed"] = .integer(Int64(manualPct))
        }
        if let poolDiff = combined["pool_difficulty"], out["poolDifficulty"] == nil {
            out["poolDifficulty"] = poolDiff
        }
        if let freeHeap = combined["internal_heap_free_bytes"], out["freeHeap"] == nil {
            out["freeHeap"] = freeHeap
        }
        if let actualPLL = MinerDriverParse.optFloat(combined["active_pll_mhz"]) {
            out["actualFrequency"] = .number(actualPLL)
        }
        return out
    }
}

// MARK: - MinerFirmwareAdapter Harlo-OS Read & Write Implementation

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
