import Foundation

/// Luxor LuxOS cgminer driver extension (`LuxosDriver` from MinerWatch).
extension MinerCgminerDrivers {
    private static let tempPositions = ["BottomLeft", "BottomRight", "TopLeft", "TopRight"]

    public typealias PerBoardResponses = (
        freq: [String: JSONValue]?,
        volt: [String: JSONValue]?,
        health: [String: JSONValue]?
    )

    public static func pollLuxos(client: CgminerClient) async throws -> MinerWatchSample {
        let version = try await client.call("version")
        let summary = (try? await client.call("summary")) ?? [:]
        let devs = (try? await client.call("devs")) ?? [:]
        let temps = (try? await client.call("temps")) ?? [:]
        let fans = (try? await client.call("fans")) ?? [:]
        let power = (try? await client.call("power")) ?? [:]
        let pools = (try? await client.call("pools")) ?? [:]

        let dList = !MinerDriverParse.sectionArray(devs, key: "DEVS").isEmpty
            ? MinerDriverParse.sectionArray(devs, key: "DEVS")
            : MinerDriverParse.sectionArray(devs, key: "DEVICES")

        var perBoardResponses: [Int: PerBoardResponses] = [:]
        for (idx, dev) in dList.enumerated() {
            let bid = MinerDriverParse.optInt(dev["ID"]) ?? idx
            let freq = try? await client.call("frequencyget", parameter: String(bid))
            let volt = try? await client.call("voltageget", parameter: String(bid))
            let health = try? await client.call("healthchipget", parameter: String(bid))
            perBoardResponses[bid] = (freq, volt, health)
        }

        let needsStats = MinerDriverParse.sectionArray(power, key: "POWER").isEmpty
            || MinerDriverParse.sectionArray(fans, key: "FANS").isEmpty
        let stats = needsStats ? ((try? await client.call("stats")) ?? [:]) : [:]

        return parseLuxos(
            version: version, summary: summary, devs: devs, temps: temps,
            fans: fans, power: power, pools: pools, stats: stats,
            perBoardResponses: perBoardResponses, host: client.host
        )
    }

    public static func parseLuxos(
        version: [String: JSONValue],
        summary: [String: JSONValue] = [:],
        devs: [String: JSONValue] = [:],
        temps: [String: JSONValue] = [:],
        fans: [String: JSONValue] = [:],
        power: [String: JSONValue] = [:],
        pools: [String: JSONValue] = [:],
        stats: [String: JSONValue] = [:],
        perBoardResponses: [Int: PerBoardResponses] = [:],
        host: String = ""
    ) -> MinerWatchSample {
        var sample = MinerWatchSample(family: "luxos", host: host, online: true)
        applyLuxosVersion(&sample, version: version)
        applyCgminerSummary(&sample, summary: summary)
        applyBraiinsDevsAndStats(&sample, devs: devs, stats: [:])
        applyLuxosTemps(&sample, temps: temps)
        applyBraiinsTempsAndFans(&sample, temps: [:], fans: fans, includeStructuredFans: true)
        applyLuxosPower(&sample, power: power, stats: stats)
        enrichFromCgminerPools(&sample, pools: pools, assignSlots: false)
        applyLuxosBoards(&sample, devs: devs, temps: temps, perBoardResponses: perBoardResponses)

        if let pw = sample.powerW, let ths = sample.hashrateTHs, ths > 0 {
            sample.efficiencyWPerTHs = MinerDriverParse.roundTo(pw / ths, places: 2)
        }

        sample.raw = [
            "version": .object(version),
            "summary": .object(summary),
            "devs": .object(devs),
            "temps": .object(temps),
            "fans": .object(fans),
            "power": .object(power),
            "pools": .object(pools),
            "stats": .object(stats)
        ]
        return sample
    }

    private static func applyLuxosVersion(_ sample: inout MinerWatchSample, version: [String: JSONValue]) {
        guard let v = MinerDriverParse.sectionArray(version, key: "VERSION").first else { return }
        sample.firmwareVersion = MinerDriverParse.nonEmptyString(
            v["LUXminer"]
            ?? v["LUXminerVersion"]
            ?? v["LUXMinerVersion"]
            ?? v["CGMiner"]
            ?? v["CGminer"]
            ?? v["Miner"]
            ?? v["API"]
        )
        sample.model = MinerDriverParse.nonEmptyString(v["Type"] ?? v["PROD"] ?? v["MODEL"] ?? v["Model"])
        sample.chipModel = chipModel(for: sample.model)
        if let mac = MinerDriverParse.nonEmptyString(v["MAC"]) {
            sample.mac = MinerDriverParse.formatMAC(mac)
        }
    }

    private static func applyLuxosTemps(_ sample: inout MinerWatchSample, temps: [String: JSONValue]) {
        let tList = MinerDriverParse.sectionArray(temps, key: "TEMPS")
        guard !tList.isEmpty else { return }
        var allTemps: [Double] = []
        for t in tList {
            for pos in tempPositions + ["Chip", "Board", "PCB"] {
                if let v = MinerDriverParse.optFloat(t[pos]), v > 0 {
                    allTemps.append(v)
                }
            }
        }
        if let maxT = allTemps.max() {
            sample.tempChipC = MinerDriverParse.roundTo(maxT, places: 1)
        }
    }

    private static func applyLuxosPower(
        _ sample: inout MinerWatchSample,
        power: [String: JSONValue],
        stats: [String: JSONValue]
    ) {
        if let p = MinerDriverParse.sectionArray(power, key: "POWER").first {
            let watts = MinerDriverParse.firstNonZeroFloat(
                p["Watts"], p["Watt"], p["Power"], p["PowerEstimate"], p["Estimate"]
            )
            if let watts, watts > 0 {
                sample.powerW = MinerDriverParse.roundTo(watts, places: 1)
            }
        }
        if sample.powerW == nil || sample.fanRPM == nil {
            applyStatsFallback(&sample, stats: stats, overwriteExisting: false)
        }
    }

    private static func applyLuxosBoards(
        _ sample: inout MinerWatchSample,
        devs: [String: JSONValue],
        temps: [String: JSONValue],
        perBoardResponses: [Int: PerBoardResponses]
    ) {
        let dList = !MinerDriverParse.sectionArray(devs, key: "DEVS").isEmpty
            ? MinerDriverParse.sectionArray(devs, key: "DEVS")
            : MinerDriverParse.sectionArray(devs, key: "DEVICES")
        guard !dList.isEmpty else { return }

        let tList = MinerDriverParse.sectionArray(temps, key: "TEMPS")
        let metadataLabels = parseTempsMetadataLabels(temps)
        var totalHWErrors = 0.0
        var totalDiff1Work = 0.0
        var sawHWCounters = false

        for (idx, dev) in dList.enumerated() {
            let bid = MinerDriverParse.optInt(dev["ID"]) ?? idx
            let bs = buildBoardSnapshot(
                bid: bid,
                dev: dev,
                tList: tList,
                metadataLabels: metadataLabels,
                responses: perBoardResponses[bid]
            )
            if let hwErr = MinerDriverParse.optFloat(dev["Hardware Errors"]),
               let diff1 = MinerDriverParse.optFloat(dev["Diff1 Work"]) {
                sawHWCounters = true
                totalHWErrors += hwErr
                totalDiff1Work += diff1
            }
            sample.boards.append(bs)
        }

        sample.boardCount = sample.boards.count
        let chipTotals = sample.boards.compactMap(\.chipsTotal)
        if !chipTotals.isEmpty { sample.chipCount = chipTotals.reduce(0, +) }
        sample.asicCount = sample.chipCount ?? sample.boardCount

        if sawHWCounters {
            let denom = totalHWErrors + totalDiff1Work
            sample.hwErrorRate = denom > 0 ? MinerDriverParse.roundTo((totalHWErrors / denom) * 100.0, places: 2) : 0.0
        }
        if sample.frequencyMHz == nil {
            let frVals = sample.boards.compactMap(\.frequencyMHz).filter { $0 > 0 }
            if !frVals.isEmpty {
                sample.frequencyMHz = MinerDriverParse.roundTo(frVals.reduce(0, +) / Double(frVals.count), places: 1)
            }
        }
        if sample.voltageMV == nil {
            let vVals = sample.boards.compactMap(\.voltageV).filter { $0 > 0 }
            if !vVals.isEmpty {
                sample.voltageMV = MinerDriverParse.roundTo((vVals.reduce(0, +) / Double(vVals.count)) * 1_000.0, places: 0)
            }
        }
    }

    private static func buildBoardSnapshot(
        bid: Int,
        dev: [String: JSONValue],
        tList: [[String: JSONValue]],
        metadataLabels: [String: String],
        responses: PerBoardResponses?
    ) -> MinerBoardSnapshot {
        var bs = MinerBoardSnapshot(id: bid)
        bs.status = MinerDriverParse.nonEmptyString(dev["Status"])
        if let en = MinerDriverParse.nonEmptyString(dev["Enabled"]) { bs.enabled = en.uppercased() == "Y" }
        bs.connector = MinerDriverParse.nonEmptyString(dev["Connector"])
        bs.hashrateTHs = MinerDriverParse.optFloat(dev["MHS 1m"]).map {
            MinerDriverParse.roundTo($0 / 1_000_000.0, places: 4)
        }
        bs.hashrate5sTHs = MinerDriverParse.optFloat(dev["MHS 5s"]).map {
            MinerDriverParse.roundTo($0 / 1_000_000.0, places: 4)
        }
        bs.nominalTHs = MinerDriverParse.optFloat(dev["Nominal MHS"]).map {
            MinerDriverParse.roundTo($0 / 1_000_000.0, places: 4)
        }

        var boardTemps: [Double] = []
        for t in tList where MinerDriverParse.optInt(t["ID"]) == bid {
            for pos in tempPositions {
                if let v = MinerDriverParse.optFloat(t[pos]), v > 0 {
                    bs.tempsExtra[pos] = v
                    if let label = metadataLabels[pos] { bs.tempsLabels[pos] = label }
                    boardTemps.append(v)
                }
            }
        }
        if let devTemp = MinerDriverParse.firstNonZeroFloat(
            dev["Chip Temp Avg"], dev["Temperature"], dev["Chip Temp"]
        ), devTemp > 0 {
            boardTemps.append(devTemp)
        }
        if let maxBoardT = boardTemps.max() {
            bs.tempChipC = MinerDriverParse.roundTo(maxBoardT, places: 1)
        }

        bs.frequencyMHz = parseLuxosFrequency(responses?.freq, boardID: bid)
            ?? MinerDriverParse.firstNonZeroFloat(dev["Frequency"], dev["Nominal chip frequency"])
        bs.voltageV = parseLuxosVoltage(responses?.volt, boardID: bid)

        let (chipsInfo, counts) = parseLuxosHealthChip(responses?.health)
        bs.chips = chipsInfo
        if !counts.isEmpty {
            bs.chipsTotal = counts["total"]
            bs.chipsHealthy = counts["healthy"]
            bs.chipsUnhealthy = counts["unhealthy"]
            bs.chipsUnknown = counts["unknown"]
        }
        if bs.frequencyMHz == nil && !bs.chips.isEmpty {
            let chipFreqs = bs.chips.compactMap { MinerDriverParse.optFloat($0["frequency"]) }.filter { $0 > 0 }
            if !chipFreqs.isEmpty {
                bs.frequencyMHz = MinerDriverParse.roundTo(chipFreqs.reduce(0, +) / Double(chipFreqs.count), places: 1)
            }
        }
        if let hwErr = MinerDriverParse.optFloat(dev["Hardware Errors"]),
           let diff1 = MinerDriverParse.optFloat(dev["Diff1 Work"]) {
            let denom = hwErr + diff1
            bs.hwErrorRate = denom > 0 ? MinerDriverParse.roundTo((hwErr / denom) * 100.0, places: 2) : 0.0
        }
        return bs
    }

    private static func parseTempsMetadataLabels(_ temps: [String: JSONValue]) -> [String: String] {
        guard let meta = MinerDriverParse.sectionArray(temps, key: "METADATA").first else { return [:] }
        var out: [String: String] = [:]
        for pos in tempPositions {
            if let entry = meta[pos]?.objectValue, let label = MinerDriverParse.nonEmptyString(entry["Label"]) {
                out[pos] = label
            }
        }
        return out
    }

    private static func parseLuxosFrequency(_ resp: [String: JSONValue]?, boardID: Int) -> Double? {
        guard let resp else { return nil }
        let fList = ["FREQS", "FREQUENCY", "FREQ"].lazy
            .map { MinerDriverParse.sectionArray(resp, key: $0) }
            .first { !$0.isEmpty } ?? []
        guard !fList.isEmpty else { return nil }

        let chipVals = fList.flatMap { $0["Freqs"]?.arrayValue ?? [] }
            .compactMap(MinerDriverParse.optFloat)
            .filter { $0 > 0 }
        if !chipVals.isEmpty {
            return MinerDriverParse.roundTo(chipVals.reduce(0, +) / Double(chipVals.count), places: 1)
        }
        if fList.count == 1 {
            let only = fList[0]
            for key in ["Frequency", "AvgFrequency", "Avg Frequency", "Avg", "Value"] {
                if let v = MinerDriverParse.optFloat(only[key]) {
                    return MinerDriverParse.roundTo(v, places: 1)
                }
            }
        }
        let vals = fList.filter { MinerDriverParse.optInt($0["Board"]).map { $0 == boardID } ?? true }
            .compactMap { MinerDriverParse.optFloat($0["Frequency"]) }
            .filter { $0 > 0 }
        guard !vals.isEmpty else { return nil }
        return MinerDriverParse.roundTo(vals.reduce(0, +) / Double(vals.count), places: 1)
    }

    private static func parseLuxosVoltage(_ resp: [String: JSONValue]?, boardID: Int) -> Double? {
        guard let resp else { return nil }
        let vList = MinerDriverParse.sectionArray(resp, key: "VOLTAGE")
        guard !vList.isEmpty else { return nil }
        for entry in vList {
            if let b = MinerDriverParse.optInt(entry["Board"]), b != boardID { continue }
            if let v = MinerDriverParse.optFloat(entry["Voltage"]) {
                return MinerDriverParse.roundTo(v, places: 2)
            }
        }
        return MinerDriverParse.optFloat(vList[0]["Voltage"]).map { MinerDriverParse.roundTo($0, places: 2) }
    }

    private static func parseLuxosHealthChip(
        _ resp: [String: JSONValue]?
    ) -> ([[String: JSONValue]], [String: Int]) {
        guard let resp else { return ([], [:]) }
        let cList = MinerDriverParse.sectionArray(resp, key: "CHIPS")
        guard !cList.isEmpty else { return ([], [:]) }
        var chips: [[String: JSONValue]] = []
        var healthy = 0
        var unhealthy = 0
        var unknown = 0

        for entry in cList {
            let rawHealth = entry["Healthy"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
            let healthLabel: String
            switch rawHealth {
            case "Y":
                healthy += 1
                healthLabel = "Y"
            case "N":
                unhealthy += 1
                healthLabel = "N"
            default:
                unknown += 1
                healthLabel = "Unknown"
            }
            var chipDict: [String: JSONValue] = ["healthy": .string(healthLabel)]
            if let c = MinerDriverParse.optInt(entry["Chip"]) { chipDict["chip"] = .integer(Int64(c)) }
            if let f = MinerDriverParse.optFloat(entry["Frequency"]) { chipDict["frequency"] = .number(f) }
            if let t = MinerDriverParse.optFloat(entry["ChipTemp"]) { chipDict["chip_temp_c"] = .number(t) }
            chips.append(chipDict)
        }
        return (chips, ["total": chips.count, "healthy": healthy, "unhealthy": unhealthy, "unknown": unknown])
    }
}
