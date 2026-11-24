import Foundation

// MARK: - 2. Braiins OS+ / BMM101 Driver

extension MinerCgminerDrivers {

    public static func pollBraiins(client: CgminerClient) async throws -> MinerWatchSample {
        let version = try await client.call("version")
        let summary = (try? await client.call("summary")) ?? [:]
        let devs = (try? await client.call("devs")) ?? [:]
        let stats = (try? await client.call("stats")) ?? [:]
        let temps = (try? await client.call("temps")) ?? [:]
        let fans = (try? await client.call("fans")) ?? [:]
        let tuner = (try? await client.call("tunerstatus")) ?? [:]
        let pools = (try? await client.call("pools")) ?? [:]
        return parseBraiins(
            version: version, summary: summary, devs: devs, stats: stats,
            temps: temps, fans: fans, tunerstatus: tuner, pools: pools, host: client.host
        )
    }

    public static func parseBraiins(
        version: [String: JSONValue],
        summary: [String: JSONValue] = [:],
        devs: [String: JSONValue] = [:],
        stats: [String: JSONValue] = [:],
        temps: [String: JSONValue] = [:],
        fans: [String: JSONValue] = [:],
        tunerstatus: [String: JSONValue] = [:],
        pools: [String: JSONValue] = [:],
        host: String = ""
    ) -> MinerWatchSample {
        var sample = MinerWatchSample(family: "braiins", host: host, online: true)

        if let v = MinerDriverParse.sectionArray(version, key: "VERSION").first {
            sample.firmwareVersion = MinerDriverParse.nonEmptyString(
                v["BOSminer+"] ?? v["BOSminer"] ?? v["CGMiner"] ?? v["API"]
            )
            sample.model = MinerDriverParse.nonEmptyString(v["Type"] ?? v["PROD"])
        }

        applyCgminerSummary(&sample, summary: summary)
        applyBraiinsDevsAndStats(&sample, devs: devs, stats: stats)
        applyBraiinsTempsAndFans(&sample, temps: temps, fans: fans, includeStructuredFans: false)
        applyBraiinsTunerStatus(&sample, tunerstatus: tunerstatus)
        enrichFromCgminerPools(&sample, pools: pools, assignSlots: true)

        if let pw = sample.powerW, let ths = sample.hashrateTHs, ths > 0 {
            sample.efficiencyWPerTHs = MinerDriverParse.roundTo(pw / ths, places: 2)
        }

        sample.raw = [
            "version": .object(version),
            "summary": .object(summary),
            "devs": .object(devs),
            "stats": .object(stats),
            "pools": .object(pools),
            "temps": .object(temps),
            "fans": .object(fans),
            "tunerstatus": .object(tunerstatus)
        ]
        return sample
    }

    // MARK: - Shared cgminer parsing blocks

    internal static func applyCgminerSummary(_ sample: inout MinerWatchSample, summary: [String: JSONValue]) {
        guard let s = MinerDriverParse.sectionArray(summary, key: "SUMMARY").first else { return }
        let ghs = MinerDriverParse.optFloat(s["GHS 1m"])
            ?? MinerDriverParse.optFloat(s["GHS 5m"])
            ?? MinerDriverParse.optFloat(s["GHS av"])
            ?? MinerDriverParse.optFloat(s["GHS 5s"])
        let mhs = MinerDriverParse.optFloat(s["MHS 5m"])
            ?? MinerDriverParse.optFloat(s["MHS 1m"])
            ?? MinerDriverParse.optFloat(s["MHS av"])
        if let ghs {
            sample.hashrateTHs = MinerDriverParse.roundTo(ghs / 1_000.0, places: 4)
        } else if let mhs {
            sample.hashrateTHs = MinerDriverParse.roundTo(mhs / 1_000_000.0, places: 4)
        }
        sample.uptimeS = MinerDriverParse.optInt(s["Elapsed"])
        sample.accepted = MinerDriverParse.optInt(s["Accepted"])
        sample.rejected = MinerDriverParse.optInt(s["Rejected"])
        sample.bestDifficulty = MinerDriverParse.parseSIDifficulty(s["Best Share"])
    }

    internal static func applyBraiinsDevsAndStats(
        _ sample: inout MinerWatchSample,
        devs: [String: JSONValue],
        stats: [String: JSONValue]
    ) {
        let dList = !MinerDriverParse.sectionArray(devs, key: "DEVS").isEmpty
            ? MinerDriverParse.sectionArray(devs, key: "DEVS")
            : MinerDriverParse.sectionArray(devs, key: "DEVICES")
        if !dList.isEmpty {
            let tempsChip = dList.compactMap {
                MinerDriverParse.firstNonZeroFloat($0["Chip Temp Avg"], $0["Temperature"], $0["Chip Temp"])
            }.filter { $0 > 0 }
            let tempsVR = dList.compactMap { MinerDriverParse.optFloat($0["PCB Temperature"]) }.filter { $0 > 0 }
            let freqs = dList.compactMap {
                MinerDriverParse.firstNonZeroFloat($0["Frequency"], $0["Nominal chip frequency"])
            }
            if let maxChip = tempsChip.max() { sample.tempChipC = MinerDriverParse.roundTo(maxChip, places: 1) }
            if let maxVR = tempsVR.max() { sample.tempVRC = MinerDriverParse.roundTo(maxVR, places: 1) }
            if !freqs.isEmpty {
                sample.frequencyMHz = MinerDriverParse.roundTo(freqs.reduce(0, +) / Double(freqs.count), places: 1)
            }
            sample.asicCount = dList.count
        }
        applyStatsFallback(&sample, stats: stats, overwriteExisting: true)
    }

    internal static func applyStatsFallback(
        _ sample: inout MinerWatchSample,
        stats: [String: JSONValue],
        overwriteExisting: Bool
    ) {
        let stList = MinerDriverParse.sectionArray(stats, key: "STATS")
        guard !stList.isEmpty else { return }
        var statFans: [String: Int] = [:]
        var powerVals: [Double] = []
        for entry in stList {
            for (k, v) in entry {
                let kl = k.lowercased()
                if kl.hasPrefix("fan") && !kl.contains("speed"), let rpm = MinerDriverParse.optInt(v) {
                    statFans[k] = rpm
                }
                if kl.contains("power") || kl.contains("watt"), let p = MinerDriverParse.optFloat(v) {
                    powerVals.append(p)
                }
            }
        }
        let shouldSetFans = overwriteExisting || sample.fanRPM == nil
        if shouldSetFans && !statFans.isEmpty {
            if sample.fansExtra.isEmpty || overwriteExisting { sample.fansExtra = statFans }
            let rpmVals = overwriteExisting ? Array(statFans.values) : statFans.values.filter { $0 > 0 }
            if !rpmVals.isEmpty { sample.fanRPM = rpmVals.reduce(0, +) / rpmVals.count }
        }
        let shouldSetPower = overwriteExisting || sample.powerW == nil
        if shouldSetPower, let maxP = powerVals.max() {
            sample.powerW = MinerDriverParse.roundTo(maxP, places: 1)
        }
    }

    internal static func applyBraiinsTempsAndFans(
        _ sample: inout MinerWatchSample,
        temps: [String: JSONValue],
        fans: [String: JSONValue],
        includeStructuredFans: Bool
    ) {
        let tList = MinerDriverParse.sectionArray(temps, key: "TEMPS")
        if !tList.isEmpty {
            let chipVals = tList.compactMap { MinerDriverParse.optFloat($0["Chip"]) }.filter { $0 > 0 }
            let boardVals = tList.compactMap { MinerDriverParse.optFloat($0["Board"]) }.filter { $0 > 0 }
            if let maxChip = chipVals.max() { sample.tempChipC = MinerDriverParse.roundTo(maxChip, places: 1) }
            if let maxBoard = boardVals.max() { sample.tempVRC = MinerDriverParse.roundTo(maxBoard, places: 1) }
        }

        let fList = MinerDriverParse.sectionArray(fans, key: "FANS")
        guard !fList.isEmpty else { return }
        var fansDict: [String: Int] = [:]
        var speeds: [Double] = []
        for fdef in fList {
            if let rpm = MinerDriverParse.optInt(fdef["RPM"]) {
                let fid = MinerDriverParse.optInt(fdef["ID"]) ?? fansDict.count
                fansDict["fan\(fid)"] = rpm
            }
            if let speed = MinerDriverParse.optFloat(fdef["Speed"]) { speeds.append(speed) }
            if includeStructuredFans {
                let fid = MinerDriverParse.optInt(fdef["ID"]) ?? sample.fans.count
                sample.fans.append(
                    MinerFanSnapshot(
                        id: fid,
                        rpm: MinerDriverParse.optInt(fdef["RPM"]),
                        speedPct: MinerDriverParse.optFloat(fdef["Speed"]),
                        connector: MinerDriverParse.nonEmptyString(fdef["FAN"])
                    )
                )
            }
        }
        if !fansDict.isEmpty {
            sample.fansExtra = fansDict
            let rpmVals = fansDict.values.filter { $0 > 0 }
            if !rpmVals.isEmpty { sample.fanRPM = rpmVals.reduce(0, +) / rpmVals.count }
        }
        if !speeds.isEmpty {
            sample.fanPct = MinerDriverParse.roundTo(speeds.reduce(0, +) / Double(speeds.count), places: 1)
        }
    }

    private static func applyBraiinsTunerStatus(_ sample: inout MinerWatchSample, tunerstatus: [String: JSONValue]) {
        guard let t = MinerDriverParse.sectionArray(tunerstatus, key: "TUNERSTATUS").first else { return }
        let pEff = MinerDriverParse.firstNonZeroFloat(
            t["ApproximateChainPowerConsumption"],
            t["ApproximateMinerPowerConsumption"],
            t["ApproximateChainPower"]
        )
        if let pEff, pEff > 0 {
            sample.powerW = MinerDriverParse.roundTo(pEff, places: 1)
            return
        }
        if let chains = t["TunerChainStatus"]?.arrayValue {
            let chainPowers = chains.compactMap(\.objectValue).compactMap {
                MinerDriverParse.optFloat($0["ApproximatePowerConsumptionWatt"])
            }.filter { $0 > 0 }
            if !chainPowers.isEmpty {
                sample.powerW = MinerDriverParse.roundTo(chainPowers.reduce(0, +), places: 1)
            }
        }
        if sample.powerW == nil, let pLim = MinerDriverParse.optFloat(t["PowerLimit"]), pLim > 0 {
            sample.powerW = MinerDriverParse.roundTo(pLim, places: 1)
        }
    }

    internal static func enrichFromCgminerPools(
        _ sample: inout MinerWatchSample,
        pools: [String: JSONValue],
        assignSlots: Bool
    ) {
        let pList = MinerDriverParse.sectionArray(pools, key: "POOLS")
        var entries = pList.map { MinerDriverParse.parseCgminerPoolEntry($0) }
        entries.sort { lhs, rhs in
            let lPri = lhs.priority ?? 999
            let rPri = rhs.priority ?? 999
            if lPri != rPri { return lPri < rPri }
            return (lhs.url ?? "") < (rhs.url ?? "")
        }
        if assignSlots {
            MinerDriverParse.assignCgminerPoolSlots(&entries)
        }
        sample.pools = entries

        let chosen = entries.first(where: { $0.active == true })
            ?? entries.first(where: { $0.status == "alive" })
            ?? entries.first
        if let chosen {
            sample.poolURL = chosen.url
            sample.worker = chosen.user
        }
    }
}
