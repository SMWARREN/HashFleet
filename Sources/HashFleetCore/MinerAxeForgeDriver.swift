import Foundation

// MARK: - 5. AxeForge (/api/status) Driver

extension MinerHTTPDrivers {
    public static func isAxeForgeStatusShape(_ data: [String: JSONValue]) -> Bool {
        guard data["board"]?.stringValue?.isEmpty == false else { return false }
        return data["hashrate"]?.doubleValue != nil
            || data["chipTemp"]?.doubleValue != nil
            || data["pool"]?.objectValue != nil
    }

    public static func parseAxeForge(data: [String: JSONValue], host: String = "") -> MinerWatchSample {
        let hashrateTHs = MinerDriverParse.optFloat(data["hashrate"]).map {
            MinerDriverParse.roundTo($0 / 1_000.0, places: 4)
        }
        let expectedTHs = MinerDriverParse.optFloat(data["expected"]).flatMap {
            $0 > 0 ? MinerDriverParse.roundTo($0 / 1_000.0, places: 4) : nil
        }
        let powerW = MinerDriverParse.optFloat(data["power"])
        let eff = (hashrateTHs != nil && powerW != nil && (hashrateTHs ?? 0) > 0)
            ? MinerDriverParse.roundTo(powerW! / hashrateTHs!, places: 2) : nil

        let tempChip = MinerDriverParse.validTemp(MinerDriverParse.optFloat(data["chipTemp"]))
        let tempChip2 = parseAxeForgeSecondChipTemp(data)
        let vrSensor = data["vrSensor"]?.boolValue ?? true
        let tempVR = vrSensor ? MinerDriverParse.validTemp(MinerDriverParse.optFloat(data["vrTemp"])) : nil

        let inputVoltageMV = MinerDriverParse.optFloat(data["vin"]).map {
            $0 < 100 ? MinerDriverParse.roundTo($0 * 1_000.0, places: 1) : $0
        }
        let coreMv = MinerDriverParse.optFloat(data["coreMv"])
        let actualVoltageMV = MinerDriverParse.optFloat(data["vout"]).flatMap {
            $0 > 0 && $0 < 50 ? MinerDriverParse.roundTo($0 * 1_000.0, places: 0) : nil
        } ?? coreMv

        let fanCount = MinerDriverParse.optInt(data["fanCount"]) ?? 0
        let statusStr = data["status"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let poolObj = data["pool"]?.objectValue ?? [:]
        let bestAllTime = MinerDriverParse.parseSIDifficulty(poolObj["bestDiff"])
        let worker = MinerDriverParse.nonEmptyString(data["worker"])
        let poolResult = parseAxeForgePools(data: data, poolObj: poolObj, worker: worker)

        return MinerWatchSample(
            family: "axeForge",
            host: host,
            online: true,
            miningPaused: statusStr.map { $0 == "paused" },
            mac: nil,
            model: MinerDriverParse.nonEmptyString(data["board"]),
            chipModel: MinerDriverParse.nonEmptyString(data["asicModel"]),
            hostname: MinerDriverParse.nonEmptyString(data["hostname"]),
            firmwareVersion: MinerDriverParse.nonEmptyString(data["version"]),
            hashrateTHs: hashrateTHs,
            powerW: powerW,
            efficiencyWPerTHs: eff,
            expectedHashrateTHs: expectedTHs,
            errorPct: MinerDriverParse.optFloat(data["errorPct"]),
            inputVoltageMV: inputVoltageMV,
            tempChipC: tempChip,
            tempChip2C: tempChip2,
            tempVRC: tempVR,
            fanRPM: MinerDriverParse.optInt(data["fanRpm"]),
            fanPct: MinerDriverParse.optFloat(data["fanPct"]),
            fanRPM2: fanCount > 1 ? MinerDriverParse.optInt(data["fan2Rpm"]) : nil,
            frequencyMHz: MinerDriverParse.optFloat(data["freq"]),
            voltageMV: actualVoltageMV,
            voltageSetMV: coreMv,
            asicCount: MinerDriverParse.optInt(data["asicCount"]),
            smallCoreCount: MinerDriverParse.optInt(data["smallCores"]),
            currentA: MinerDriverParse.optFloat(data["iout"]),
            hwErrors: MinerDriverParse.optInt(data["dupResults"]),
            uptimeS: MinerDriverParse.optInt(data["uptime"]),
            accepted: MinerDriverParse.optInt(poolObj["accepted"]),
            rejected: MinerDriverParse.optInt(poolObj["rejected"]),
            bestDifficulty: MinerDriverParse.parseSIDifficulty(poolObj["sessionBest"]) ?? bestAllTime,
            bestDifficultyAllTime: bestAllTime,
            networkDifficulty: MinerDriverParse.parseSIDifficulty(poolObj["networkDiff"]),
            lastShareDiff: MinerDriverParse.parseSIDifficulty(data["lastHashDiff"]),
            poolURL: poolResult.poolURL,
            worker: worker,
            poolURLFallback: poolResult.fallbackURL,
            workerFallback: poolResult.fallbackURL != nil ? worker : nil,
            poolActive: poolResult.poolActive,
            pools: poolResult.pools,
            blocksFound: MinerDriverParse.optInt(poolObj["blocks"]),
            blockHeight: MinerDriverParse.optInt(poolObj["height"])
                ?? MinerDriverParse.optInt(data["template"]?.objectValue?["height"]),
            raw: enrichAxeForgeRaw(data: data, poolObj: poolObj)
        )
    }

    private static func parseAxeForgeSecondChipTemp(_ data: [String: JSONValue]) -> Double? {
        guard let chips = data["chips"]?.arrayValue, chips.count >= 2,
              let second = chips[1].objectValue,
              second["ownSensor"]?.boolValue == true else {
            return nil
        }
        return MinerDriverParse.validTemp(MinerDriverParse.optFloat(second["temp"]))
    }

    private static func parseAxeForgePools(
        data: [String: JSONValue],
        poolObj: [String: JSONValue],
        worker: String?
    ) -> (poolURL: String?, fallbackURL: String?, poolActive: String?, pools: [MinerPoolSnapshot]) {
        var poolURL = MinerDriverParse.nonEmptyString(poolObj["host"])
        var fallbackURL: String?
        var poolActive: String?
        var poolsList: [MinerPoolSnapshot] = []

        if let rawPools = data["pools"]?.arrayValue {
            for (idx, item) in rawPools.enumerated() {
                guard let obj = item.objectValue,
                      let hostStr = MinerDriverParse.nonEmptyString(obj["host"]),
                      obj["enabled"]?.boolValue ?? true else {
                    continue
                }
                let connected = obj["connected"]?.boolValue ?? false
                let slot = idx == 0 ? "primary" : "fallback"
                if idx == 0 && poolURL == nil { poolURL = hostStr }
                if idx == 1 && fallbackURL == nil { fallbackURL = hostStr }
                if connected && poolActive == nil { poolActive = slot }
                poolsList.append(
                    MinerPoolSnapshot(
                        url: hostStr,
                        user: worker,
                        status: MinerDriverParse.nonEmptyString(obj["status"])?.lowercased(),
                        priority: idx,
                        accepted: MinerDriverParse.optInt(obj["accepted"]),
                        rejected: MinerDriverParse.optInt(obj["rejected"]),
                        active: connected,
                        slot: slot,
                        pingMs: MinerDriverParse.optFloat(obj["pingMs"])
                    )
                )
            }
        }
        if poolActive == nil && poolURL != nil { poolActive = "primary" }
        if let netPing = MinerDriverParse.optFloat(data["net"]?.objectValue?["rttMs"]),
           !poolsList.isEmpty, poolsList[0].pingMs == nil {
            poolsList[0].pingMs = netPing
        }
        return (poolURL, fallbackURL, poolActive, poolsList)
    }

    private static func enrichAxeForgeRaw(
        data: [String: JSONValue],
        poolObj: [String: JSONValue]
    ) -> [String: JSONValue] {
        var enriched = data
        if let rssi = data["rssi"], enriched["wifiRSSI"] == nil { enriched["wifiRSSI"] = rssi }
        if let board = data["board"], enriched["boardVersion"] == nil { enriched["boardVersion"] = board }
        if let poolDiff = poolObj["diff"], enriched["poolDifficulty"] == nil { enriched["poolDifficulty"] = poolDiff }
        if enriched["autofanspeed"] == nil, let fanPct = MinerDriverParse.optInt(data["fanPct"]) {
            enriched["autofanspeed"] = .integer(0)
            if enriched["manualFanSpeed"] == nil {
                enriched["manualFanSpeed"] = .integer(Int64(fanPct))
            }
        }
        return enriched
    }
}
