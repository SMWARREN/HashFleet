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
        let freqMHz = MinerDriverParse.optFloat(combined["frequency_mhz"])
            ?? MinerDriverParse.optFloat(combined["target_frequency_mhz"])
            ?? MinerDriverParse.optFloat(combined["active_pll_mhz"])
            ?? MinerDriverParse.optFloat(combined["frequency"])
            ?? MinerDriverParse.optFloat(profile["stock_frequency_mhz"])
            ?? 525.0
        let targetCoreMV = MinerDriverParse.optFloat(combined["target_core_mv"])
            ?? MinerDriverParse.optFloat(combined["core_voltage_mv"])
            ?? MinerDriverParse.optFloat(combined["core_mv"])
            ?? MinerDriverParse.optFloat(profile["stock_core_mv"])
            ?? 1150.0
        let actualCoreMV = MinerDriverParse.optFloat(combined["core_voltage_mv"])
            ?? MinerDriverParse.optFloat(combined["core_mv"])
            ?? targetCoreMV
        let inputVoltageMV = MinerDriverParse.optFloat(combined["input_voltage_v"]).map {
            $0 < 100 ? MinerDriverParse.roundTo($0 * 1_000.0, places: 1) : $0
        }
        let currentA = MinerDriverParse.optFloat(combined["asic_regulator_input_current_a"])
            ?? MinerDriverParse.optFloat(combined["asic_core_current_a"])

        let fanResult = parseHarloOSFans(combined["fans"]?.arrayValue ?? [], combined: combined)
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

    private static func parseHarloOSFans(_ fansArray: [JSONValue], combined: [String: JSONValue] = [:]) -> HarloFanParseResult {
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
        if res.fan1Pct == nil {
            res.fan1Pct = MinerDriverParse.optFloat(combined["fan_duty_pct"] ?? combined["fanspeed"])
        }
        if res.isAuto == nil {
            res.isAuto = false
        }
        if res.manualPct == nil {
            res.manualPct = res.fan1Pct.map { Int($0.rounded()) } ?? 100
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
        let isAuto = fanResult.isAuto ?? false
        out["autofanspeed"] = .integer(isAuto ? 1 : 0)
        if let targetC = fanResult.targetC {
            out["temptarget"] = .integer(Int64(targetC))
        }
        let manual = fanResult.manualPct ?? fanResult.fan1Pct.map { Int($0.rounded()) } ?? 100
        out["manualFanSpeed"] = .integer(Int64(manual))
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
