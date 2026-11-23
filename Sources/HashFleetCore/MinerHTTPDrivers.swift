import Foundation

/// Port of MinerWatch's HTTP REST drivers (`BitaxeDriver`, `NerdOctaxeDriver`, `BitForgeDriver`,
/// `NmaxeDriver`) plus AxeForge's `/api/status` driver.
public enum MinerHTTPDrivers {
    public static let hashrateSanityFactor: Double = 3.0

    // MARK: - 1. Bitaxe Driver

    public static func parseBitaxe(data: [String: JSONValue], host: String = "") -> MinerWatchSample {
        var hashrateTHs = (MinerDriverParse.optFloat(data["hashRate"]) ?? MinerDriverParse.optFloat(data["hashrate"]))
            .map { MinerDriverParse.roundTo($0 / 1_000.0, places: 4) }
        let powerW = MinerDriverParse.optFloat(data["power"])

        let tempS1 = MinerDriverParse.validTemp(MinerDriverParse.optFloat(data["temp"]))
        let tempS2 = MinerDriverParse.validTemp(MinerDriverParse.optFloat(data["temp2"]))
        let tempChip = [tempS1, tempS2].compactMap { $0 }.max().map { MinerDriverParse.roundTo($0, places: 1) }

        let freqMHz = MinerDriverParse.optFloat(data["frequency"])
        let voltageMV = MinerDriverParse.optFloat(data["coreVoltageActual"])
            ?? MinerDriverParse.optFloat(data["coreVoltage"])
        let asicCount = MinerDriverParse.optInt(data["asicCount"]) ?? asicsFromMonitor(data)
        let smallCoreCount = MinerDriverParse.optInt(data["smallCoreCount"])

        if let currentTHs = hashrateTHs, let freq = freqMHz, freq > 0,
           let cores = smallCoreCount, cores > 0, let asics = asicCount, asics > 0 {
            let theoreticalTHs = freq * Double(cores) * Double(asics) / 1_000_000.0
            if currentTHs > theoreticalTHs * hashrateSanityFactor { hashrateTHs = nil }
        }

        let eff = (hashrateTHs != nil && powerW != nil && (hashrateTHs ?? 0) > 0)
            ? MinerDriverParse.roundTo(powerW! / hashrateTHs!, places: 2) : nil

        let expectedGHs = MinerDriverParse.optFloat(data["expectedHashrate"])
        let expectedTHs = expectedGHs.flatMap { $0 > 0 ? MinerDriverParse.roundTo($0 / 1_000.0, places: 4) : nil }
        let accepted = MinerDriverParse.optInt(data["sharesAccepted"])
        let rejected = MinerDriverParse.optInt(data["sharesRejected"])

        let bsdVal = data["bestSessionDiff"]
        let bdVal = data["bestDiff"]
        let hasSession = bsdVal != nil && bsdVal != .null && bsdVal?.stringValue != ""
        let bestDiffSession = MinerDriverParse.parseSIDifficulty(hasSession ? bsdVal : bdVal)
        let bestDiffAllTime = MinerDriverParse.parseSIDifficulty(bdVal)

        let poolInfo = parseBitaxePools(data: data, accepted: accepted, rejected: rejected)
        let miningPaused: Bool? = (data["miningPaused"] != nil && data["miningPaused"] != .null)
            ? MinerDriverParse.coerceFlag(data["miningPaused"]) : nil

        let macRaw = (MinerDriverParse.nonEmptyString(data["macAddr"])
            ?? MinerDriverParse.nonEmptyString(data["macAddress"]) ?? "").uppercased()

        return MinerWatchSample(
            family: "bitaxe",
            host: host,
            online: true,
            miningPaused: miningPaused,
            mac: macRaw.isEmpty ? nil : macRaw,
            model: MinerDriverParse.nonEmptyString(data["deviceModel"])
                ?? MinerDriverParse.nonEmptyString(data["boardName"])
                ?? MinerDriverParse.nonEmptyString(data["ASICModel"])
                ?? MinerDriverParse.nonEmptyString(data["boardVersion"]),
            chipModel: MinerDriverParse.nonEmptyString(data["ASICModel"]),
            hostname: MinerDriverParse.nonEmptyString(data["hostname"]),
            firmwareVersion: MinerDriverParse.nonEmptyString(data["version"])
                ?? MinerDriverParse.nonEmptyString(data["firmwareVersion"]),
            hashrateTHs: hashrateTHs,
            powerW: powerW,
            efficiencyWPerTHs: eff,
            expectedHashrateTHs: expectedTHs,
            errorPct: MinerDriverParse.optFloat(data["errorPercentage"]),
            inputVoltageMV: MinerDriverParse.optFloat(data["voltage"]),
            maxPowerW: MinerDriverParse.optFloat(data["maxPower"]),
            tempChipC: tempChip,
            tempChip2C: tempS2,
            tempVRC: MinerDriverParse.optFloat(data["vrTemp"]),
            fanRPM: MinerDriverParse.optInt(data["fanrpm"]) ?? MinerDriverParse.optInt(data["fanRpm"]),
            fanPct: MinerDriverParse.optFloat(data["fanspeed"]) ?? MinerDriverParse.optFloat(data["fanSpeed"]),
            frequencyMHz: freqMHz,
            voltageMV: voltageMV,
            voltageSetMV: MinerDriverParse.optFloat(data["coreVoltage"]),
            asicCount: asicCount,
            smallCoreCount: smallCoreCount,
            hwErrors: hwErrorsFromMonitor(data),
            hwTotal: hwTotalFromMonitor(data),
            uptimeS: MinerDriverParse.optInt(data["uptimeSeconds"]),
            accepted: accepted,
            rejected: rejected,
            bestDifficulty: bestDiffSession,
            bestDifficultyAllTime: bestDiffAllTime,
            networkDifficulty: MinerDriverParse.parseSIDifficulty(data["networkDifficulty"]),
            poolURL: poolInfo.poolURL,
            worker: poolInfo.worker,
            poolURLFallback: poolInfo.fallbackURL,
            workerFallback: poolInfo.workerFallback,
            poolActive: poolInfo.poolActive,
            pools: poolInfo.pools,
            raw: data
        )
    }

    private struct BitaxePoolResult {
        let poolURL: String?
        let worker: String?
        let fallbackURL: String?
        let workerFallback: String?
        let poolActive: String?
        let pools: [MinerPoolSnapshot]
    }

    private static func parseBitaxePools(
        data: [String: JSONValue],
        accepted: Int?,
        rejected: Int?
    ) -> BitaxePoolResult {
        var poolURL = MinerDriverParse.nonEmptyString(data["stratumURL"])
            ?? MinerDriverParse.nonEmptyString(data["stratumUrl"])
        if let url = poolURL, let port = MinerDriverParse.optInt(data["stratumPort"]), port > 0 {
            poolURL = "\(url):\(port)"
        }
        let worker = MinerDriverParse.nonEmptyString(data["stratumUser"])

        var fallbackURL = MinerDriverParse.nonEmptyString(data["fallbackStratumURL"])
            ?? MinerDriverParse.nonEmptyString(data["fallbackStratumUrl"])
        if let url = fallbackURL, let port = MinerDriverParse.optInt(data["fallbackStratumPort"]), port > 0 {
            fallbackURL = "\(url):\(port)"
        }
        let workerFallback = MinerDriverParse.nonEmptyString(data["fallbackStratumUser"])
        let usingFallback = MinerDriverParse.coerceFlag(data["isUsingFallbackStratum"]) && (fallbackURL != nil)
        let pingMs = MinerDriverParse.optFloat(data["responseTime"])

        var pools: [MinerPoolSnapshot] = []
        if let poolURL {
            let primaryActive = !usingFallback
            pools.append(
                MinerPoolSnapshot(
                    url: poolURL,
                    user: worker,
                    accepted: primaryActive ? accepted : nil,
                    rejected: primaryActive ? rejected : nil,
                    active: primaryActive,
                    slot: "primary",
                    pingMs: primaryActive ? pingMs : nil
                )
            )
        }
        if let fallbackURL {
            pools.append(
                MinerPoolSnapshot(
                    url: fallbackURL,
                    user: workerFallback,
                    accepted: usingFallback ? accepted : nil,
                    rejected: usingFallback ? rejected : nil,
                    active: usingFallback,
                    slot: "fallback",
                    pingMs: usingFallback ? pingMs : nil
                )
            )
        }
        let poolActive = (poolURL != nil || fallbackURL != nil) ? (usingFallback ? "fallback" : "primary") : nil
        return BitaxePoolResult(
            poolURL: poolURL,
            worker: worker,
            fallbackURL: fallbackURL,
            workerFallback: workerFallback,
            poolActive: poolActive,
            pools: pools
        )
    }

    // MARK: - 2. NerdOctaxe / NerdQAxe Driver

    public static func parseNerdOctaxe(data: [String: JSONValue], host: String = "") -> MinerWatchSample {
        var sample = parseBitaxe(data: data, host: host)
        sample.family = "nerdqaxe"

        if let sd = data["shutdown"], sd != .null {
            sample.miningPaused = MinerDriverParse.coerceFlag(sd)
        }

        var currentA = MinerDriverParse.optFloat(data["currentA"])
        if currentA == nil, let currentMA = MinerDriverParse.optFloat(data["current"]) {
            currentA = MinerDriverParse.roundTo(currentMA / 1_000.0, places: 3)
        }
        sample.currentA = currentA

        if let fanCount = MinerDriverParse.optInt(data["fanCount"]), fanCount > 1 {
            sample.fanRPM2 = MinerDriverParse.optInt(data["fanrpm2"]) ?? MinerDriverParse.optInt(data["fan2rpm"])
            sample.fanPct2 = MinerDriverParse.optFloat(data["fanspeed2"])
        }

        if let dh = MinerDriverParse.optInt(data["duplicateHWNonces"]) {
            sample.hwErrors = dh
            sample.hwTotal = nil
        }

        if let fbURL = MinerDriverParse.nonEmptyString(data["fallbackStratumURL"]) {
            if let fbPort = MinerDriverParse.optInt(data["fallbackStratumPort"]), fbPort > 0 {
                sample.poolURLFallback = "\(fbURL):\(fbPort)"
            } else {
                sample.poolURLFallback = fbURL
            }
        }
        sample.workerFallback = MinerDriverParse.nonEmptyString(data["fallbackStratumUser"])
        applyNerdOctaxePools(&sample, data: data)
        return sample
    }

    private static func applyNerdOctaxePools(_ sample: inout MinerWatchSample, data: [String: JSONValue]) {
        let stratum = data["stratum"]?.objectValue
        let stratumPools = stratum?["pools"]?.arrayValue
        if let stratum {
            if let mode = MinerDriverParse.nonEmptyString(stratum["activePoolMode"]), Int(mode) == nil {
                sample.poolActive = mode.lowercased()
            } else if case .bool(let usingFb) = stratum["usingFallback"] {
                sample.poolActive = usingFb ? "fallback" : "primary"
            } else if let stratumPools {
                let p0 = stratumPools.first?.objectValue
                let p1 = stratumPools.count >= 2 ? stratumPools[1].objectValue : nil
                if MinerDriverParse.coerceFlag(p0?["connected"]) {
                    sample.poolActive = "primary"
                } else if MinerDriverParse.coerceFlag(p1?["connected"]) {
                    sample.poolActive = "fallback"
                }
            }
        }

        let topPing = MinerDriverParse.optFloat(data["lastpingrtt"])
        let topPingLoss = MinerDriverParse.optFloat(data["recentpingloss"])

        func buildSlot(url: String?, user: String?, slotName: String, idx: Int) -> MinerPoolSnapshot? {
            guard let url, !url.isEmpty else { return nil }
            let entry = (stratumPools != nil && idx < stratumPools!.count) ? stratumPools![idx].objectValue : nil
            if let entry {
                return MinerPoolSnapshot(
                    url: url,
                    user: user,
                    accepted: MinerDriverParse.optInt(entry["accepted"]),
                    rejected: MinerDriverParse.optInt(entry["rejected"]),
                    active: MinerDriverParse.coerceFlag(entry["connected"]),
                    slot: slotName,
                    pingMs: MinerDriverParse.optFloat(entry["pingRtt"]),
                    pingLoss: MinerDriverParse.optFloat(entry["pingLoss"])
                )
            }
            let isActive = slotName == "primary"
                ? (sample.poolActive != "fallback")
                : (sample.poolActive == "fallback")
            return MinerPoolSnapshot(
                url: url,
                user: user,
                accepted: isActive ? sample.accepted : nil,
                rejected: isActive ? sample.rejected : nil,
                active: isActive,
                slot: slotName,
                pingMs: isActive ? topPing : nil,
                pingLoss: isActive ? topPingLoss : nil
            )
        }

        var poolsList: [MinerPoolSnapshot] = []
        if let primary = buildSlot(url: sample.poolURL, user: sample.worker, slotName: "primary", idx: 0) {
            poolsList.append(primary)
        }
        if let fallback = buildSlot(
            url: sample.poolURLFallback,
            user: sample.workerFallback,
            slotName: "fallback",
            idx: 1
        ) {
            poolsList.append(fallback)
        }
        sample.pools = poolsList
    }

    // MARK: - 3. BitForge Driver

    public static func parseBitForge(data: [String: JSONValue], host: String = "") -> MinerWatchSample {
        var sample = parseBitaxe(data: data, host: host)
        sample.family = "bitforge"

        let tempS1 = MinerDriverParse.validTemp(MinerDriverParse.optFloat(data["chiptemp1"]))
        let tempS2 = MinerDriverParse.validTemp(MinerDriverParse.optFloat(data["chiptemp2"]))
        let chipTemps = [tempS1, tempS2].compactMap { $0 }
        if !chipTemps.isEmpty {
            let avg = MinerDriverParse.validTemp(MinerDriverParse.optFloat(data["temp"]))
            sample.tempChipC = chipTemps.max().map { MinerDriverParse.roundTo($0, places: 1) }
            sample.tempChip2C = tempS2
            if let avg, chipTemps.count > 1 {
                sample.tempAvgC = MinerDriverParse.roundTo(avg, places: 1)
            }
        }
        if let fanPct = MinerDriverParse.optFloat(data["fanSpeed"]) {
            sample.fanPct = fanPct
        }
        if let currentMA = MinerDriverParse.optFloat(data["current"]), currentMA > 0 {
            sample.currentA = MinerDriverParse.roundTo(currentMA / 1_000.0, places: 3)
        }
        return sample
    }

    // MARK: - 4. NMAxe Driver

    public static func parseNmaxe(data: [String: JSONValue], host: String = "") -> MinerWatchSample {
        let power = data["power"]?.objectValue ?? [:]
        let temps = data["temps"]?.objectValue ?? [:]
        let asic = data["asic"]?.objectValue ?? [:]
        let miner = data["miner"]?.objectValue ?? [:]
        let identity = data["identity"]?.objectValue ?? [:]
        let stratum = data["stratum"]?.objectValue ?? [:]
        let fans = data["fans"]?.arrayValue ?? []

        let hashrateTHs = MinerDriverParse.optFloat(miner["hashRate"]).map {
            MinerDriverParse.roundTo($0 / 1_000.0, places: 4)
        }
        let powerW = MinerDriverParse.optFloat(power["power"])
        let eff = (hashrateTHs != nil && powerW != nil && (hashrateTHs ?? 0) > 0)
            ? MinerDriverParse.roundTo(powerW! / hashrateTHs!, places: 2) : nil

        let currentA = MinerDriverParse.optFloat(power["ibus"]).map {
            MinerDriverParse.roundTo($0 / 1_000.0, places: 3)
        }
        let fan0 = fans.first?.objectValue ?? [:]
        let fan1 = fans.count >= 2 ? fans[1].objectValue : nil
        let poolURL = MinerDriverParse.stripScheme(stratum["url"]?.stringValue)
        let worker = MinerDriverParse.nonEmptyString(stratum["user"])

        let miningPaused: Bool?
        if case .bool(let p) = miner["paused"] {
            miningPaused = p
        } else {
            miningPaused = nil
        }

        var sample = MinerWatchSample(
            family: "nmaxe",
            host: host,
            online: true,
            miningPaused: miningPaused,
            mac: nil,
            model: MinerDriverParse.nonEmptyString(identity["hwModel"])
                ?? MinerDriverParse.nonEmptyString(identity["displayName"]),
            chipModel: MinerDriverParse.nonEmptyString(asic["model"]),
            hostname: MinerDriverParse.nonEmptyString(identity["hostName"]),
            firmwareVersion: MinerDriverParse.nonEmptyString(identity["fwVersion"]),
            hashrateTHs: hashrateTHs,
            powerW: powerW,
            efficiencyWPerTHs: eff,
            inputVoltageMV: MinerDriverParse.optFloat(power["vbus"]),
            tempChipC: MinerDriverParse.optFloat(temps["asic"]),
            tempVRC: MinerDriverParse.optFloat(temps["vcore"]),
            fanRPM: MinerDriverParse.optInt(fan0["rpm"]),
            fanPct: MinerDriverParse.optFloat(fan0["speed"]),
            frequencyMHz: MinerDriverParse.optFloat(asic["freqReq"]),
            voltageMV: MinerDriverParse.optFloat(asic["vcoreReal"]) ?? MinerDriverParse.optFloat(asic["vcoreReq"]),
            voltageSetMV: MinerDriverParse.optFloat(asic["vcoreReq"]),
            asicCount: MinerDriverParse.optInt(asic["count"]),
            smallCoreCount: MinerDriverParse.optInt(asic["smallCoreCnt"]),
            currentA: currentA,
            uptimeS: MinerDriverParse.optInt(miner["uptimeSeconds"]),
            accepted: MinerDriverParse.optInt(miner["sAccepted"]),
            rejected: MinerDriverParse.optInt(miner["sRejected"]),
            bestDifficulty: MinerDriverParse.parseSIDifficulty(miner["bestDiffSession"]),
            bestDifficultyAllTime: MinerDriverParse.parseSIDifficulty(miner["bestDiffEver"]),
            networkDifficulty: MinerDriverParse.parseSIDifficulty(miner["networkDiff"]),
            lastShareDiff: MinerDriverParse.parseSIDifficulty(miner["lastDiff"]),
            poolURL: poolURL,
            worker: worker,
            raw: data
        )

        if let fan1 {
            sample.fanRPM2 = MinerDriverParse.optInt(fan1["rpm"])
            sample.fanPct2 = MinerDriverParse.optFloat(fan1["speed"])
        }
        if sample.raw["autofanspeed"] == nil {
            let isAuto = fan0["auto"] != nil ? MinerDriverParse.coerceFlag(fan0["auto"]) : false
            sample.raw["autofanspeed"] = .integer(isAuto ? 1 : 0)
        }
        if sample.raw["manualFanSpeed"] == nil, let speed = MinerDriverParse.optInt(fan0["speed"]) {
            sample.raw["manualFanSpeed"] = .integer(Int64(speed))
        }
        if let poolURL {
            sample.pools = [
                MinerPoolSnapshot(
                    url: poolURL,
                    user: worker,
                    accepted: sample.accepted,
                    rejected: sample.rejected,
                    active: true,
                    slot: "primary"
                )
            ]
        }
        return sample
    }

    // MARK: - Private helpers

    private static func asicsFromMonitor(_ data: [String: JSONValue]) -> Int? {
        guard let monitor = data["hashrateMonitor"]?.objectValue,
              let asics = monitor["asics"]?.arrayValue,
              !asics.isEmpty else {
            return nil
        }
        return asics.count
    }

    private static func hwErrorsFromMonitor(_ data: [String: JSONValue]) -> Int? {
        sumMonitorField(data, field: "errorCount")
    }

    private static func hwTotalFromMonitor(_ data: [String: JSONValue]) -> Int? {
        sumMonitorField(data, field: "total")
    }

    private static func sumMonitorField(_ data: [String: JSONValue], field: String) -> Int? {
        guard let monitor = data["hashrateMonitor"]?.objectValue,
              let asics = monitor["asics"]?.arrayValue,
              !asics.isEmpty else {
            return nil
        }
        var total = 0
        var found = false
        for entry in asics {
            if let dict = entry.objectValue, let count = MinerDriverParse.optInt(dict[field]) {
                total += count
                found = true
            }
        }
        return found ? total : nil
    }

    // MARK: - 4b. WarpAxe (dvb-WarpAxe) Driver

    /// Returns `true` when the `/api/system/info` payload originates from WarpAxe (`dvb-projekt/dvb-WarpAxe`).
    public static func isWarpAxeShape(_ data: [String: JSONValue]) -> Bool {
        if let version = data["version"]?.stringValue,
           version.localizedCaseInsensitiveContains("warpaxe") {
            return true
        }
        if let axeVersion = data["axeOSVersion"]?.stringValue,
           axeVersion.localizedCaseInsensitiveContains("warpaxe") {
            return true
        }
        if data["boardModels"]?.arrayValue != nil && data["cockpitBig"]?.stringValue != nil {
            return true
        }
        if data["vrProbe"]?.stringValue != nil || data["selfHeals"]?.arrayValue != nil {
            return true
        }
        return false
    }

    public static func parseWarpAxe(data: [String: JSONValue], host: String = "") -> MinerWatchSample {
        var sample = parseBitaxe(data: data, host: host)
        sample.family = "warpAxe"
        if let boardName = MinerDriverParse.nonEmptyString(data["boardName"]) {
            sample.model = boardName
        }
        if let coreCurrentA = MinerDriverParse.optFloat(data["coreCurrentA"]) {
            sample.currentA = coreCurrentA
        } else if let currentMA = MinerDriverParse.optFloat(data["current"]) {
            sample.currentA = MinerDriverParse.roundTo(currentMA / 1_000.0, places: 3)
        }
        if let sd = data["shutdown"], sd != .null {
            sample.miningPaused = MinerDriverParse.coerceFlag(sd)
        }
        if let blocks = MinerDriverParse.optInt(data["blocksFoundTotal"]) ?? MinerDriverParse.optInt(data["blockFound"]) {
            sample.blocksFound = blocks
        }
        if let height = MinerDriverParse.optInt(data["blockHeight"]), height > 0 {
            sample.blockHeight = height
        }
        return sample
    }
}

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
