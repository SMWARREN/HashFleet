import Foundation

/// Per-hashboard snapshot reported by multi-board firmwares (e.g. LuxOS).
public struct MinerBoardSnapshot: Codable, Equatable, Hashable, Sendable {
    public var id: Int
    public var status: String?
    public var enabled: Bool?
    public var connector: String?
    public var frequencyMHz: Double?
    public var voltageV: Double?
    public var hashrateTHs: Double?
    public var hashrate5sTHs: Double?
    public var nominalTHs: Double?
    public var hwErrorRate: Double?
    public var tempChipC: Double?
    public var tempsExtra: [String: Double]
    public var tempsLabels: [String: String]
    public var chipsTotal: Int?
    public var chipsHealthy: Int?
    public var chipsUnhealthy: Int?
    public var chipsUnknown: Int?
    public var chips: [[String: JSONValue]]

    public init(
        id: Int,
        status: String? = nil,
        enabled: Bool? = nil,
        connector: String? = nil,
        frequencyMHz: Double? = nil,
        voltageV: Double? = nil,
        hashrateTHs: Double? = nil,
        hashrate5sTHs: Double? = nil,
        nominalTHs: Double? = nil,
        hwErrorRate: Double? = nil,
        tempChipC: Double? = nil,
        tempsExtra: [String: Double] = [:],
        tempsLabels: [String: String] = [:],
        chipsTotal: Int? = nil,
        chipsHealthy: Int? = nil,
        chipsUnhealthy: Int? = nil,
        chipsUnknown: Int? = nil,
        chips: [[String: JSONValue]] = []
    ) {
        self.id = id
        self.status = status
        self.enabled = enabled
        self.connector = connector
        self.frequencyMHz = frequencyMHz
        self.voltageV = voltageV
        self.hashrateTHs = hashrateTHs
        self.hashrate5sTHs = hashrate5sTHs
        self.nominalTHs = nominalTHs
        self.hwErrorRate = hwErrorRate
        self.tempChipC = tempChipC
        self.tempsExtra = tempsExtra
        self.tempsLabels = tempsLabels
        self.chipsTotal = chipsTotal
        self.chipsHealthy = chipsHealthy
        self.chipsUnhealthy = chipsUnhealthy
        self.chipsUnknown = chipsUnknown
        self.chips = chips
    }
}

/// Per-fan snapshot reported by multi-fan firmwares.
public struct MinerFanSnapshot: Codable, Equatable, Hashable, Sendable {
    public var id: Int
    public var rpm: Int?
    public var speedPct: Double?
    public var connector: String?

    public init(id: Int, rpm: Int? = nil, speedPct: Double? = nil, connector: String? = nil) {
        self.id = id
        self.rpm = rpm
        self.speedPct = speedPct
        self.connector = connector
    }
}

/// Per-pool snapshot for one configured pool slot.
public struct MinerPoolSnapshot: Codable, Equatable, Hashable, Sendable {
    public var url: String?
    public var user: String?
    public var status: String?
    public var priority: Int?
    public var accepted: Int?
    public var rejected: Int?
    public var stale: Int?
    public var lastShareTimestamp: Int?
    public var active: Bool?
    public var slot: String?
    public var pingMs: Double?
    public var pingLoss: Double?

    public init(
        url: String? = nil,
        user: String? = nil,
        status: String? = nil,
        priority: Int? = nil,
        accepted: Int? = nil,
        rejected: Int? = nil,
        stale: Int? = nil,
        lastShareTimestamp: Int? = nil,
        active: Bool? = nil,
        slot: String? = nil,
        pingMs: Double? = nil,
        pingLoss: Double? = nil
    ) {
        self.url = url
        self.user = user
        self.status = status
        self.priority = priority
        self.accepted = accepted
        self.rejected = rejected
        self.stale = stale
        self.lastShareTimestamp = lastShareTimestamp
        self.active = active
        self.slot = slot
        self.pingMs = pingMs
        self.pingLoss = pingLoss
    }
}

/// Unified telemetry sample ported from MinerWatch's `MinerSample`, extended to translate cleanly
/// into `MinerInfo` so all existing HashFleet views, alerts, diagnostics, and database writers work.
public struct MinerWatchSample: Equatable, Sendable {
    public var family: String
    public var host: String
    public var online: Bool
    public var error: String?
    /// Active hardware power-supply fault (for example an Avalon `PS[...]` error code). Nil when OK or unknown.
    public var powerFault: String?
    public var miningPaused: Bool?

    // Identity
    public var mac: String?
    public var model: String?
    public var chipModel: String?
    public var hostname: String?
    public var firmwareVersion: String?

    // Performance
    public var hashrateTHs: Double?
    public var powerW: Double?
    public var efficiencyWPerTHs: Double?
    public var expectedHashrateTHs: Double?
    public var errorPct: Double?
    public var inputVoltageMV: Double?
    public var maxPowerW: Double?

    // Thermal & Fans
    public var tempChipC: Double?
    public var tempChip2C: Double?
    public var tempVRC: Double?
    public var tempOutletC: Double?
    public var tempInletC: Double?
    public var tempAvgC: Double?
    public var fanRPM: Int?
    public var fanPct: Double?
    public var fansExtra: [String: Int]
    public var fans: [MinerFanSnapshot]
    public var fanRPM2: Int?
    public var fanPct2: Double?

    // ASIC & Boards
    public var frequencyMHz: Double?
    public var voltageMV: Double?
    public var voltageSetMV: Double?
    public var asicCount: Int?
    public var smallCoreCount: Int?
    public var workmode: Int?
    public var boardCount: Int?
    public var chipCount: Int?
    public var boards: [MinerBoardSnapshot]

    // Electrical & HW errors
    public var currentA: Double?
    public var hwErrors: Int?
    public var hwTotal: Int?
    public var hwErrorRate: Double?

    // Mining & Pools
    public var uptimeS: Int?
    public var accepted: Int?
    public var rejected: Int?
    public var bestDifficulty: Double?
    public var bestDifficultyAllTime: Double?
    public var networkDifficulty: Double?
    public var lastShareDiff: Double?
    public var poolURL: String?
    public var worker: String?
    public var poolURLFallback: String?
    public var workerFallback: String?
    public var poolActive: String?
    public var pools: [MinerPoolSnapshot]
    public var blocksFound: Int?
    public var blockHeight: Int?

    public var raw: [String: JSONValue]

    public init(
        family: String,
        host: String,
        online: Bool = true,
        error: String? = nil,
        miningPaused: Bool? = nil,
        mac: String? = nil,
        model: String? = nil,
        chipModel: String? = nil,
        hostname: String? = nil,
        firmwareVersion: String? = nil,
        hashrateTHs: Double? = nil,
        powerW: Double? = nil,
        efficiencyWPerTHs: Double? = nil,
        expectedHashrateTHs: Double? = nil,
        errorPct: Double? = nil,
        inputVoltageMV: Double? = nil,
        maxPowerW: Double? = nil,
        tempChipC: Double? = nil,
        tempChip2C: Double? = nil,
        tempVRC: Double? = nil,
        tempOutletC: Double? = nil,
        tempInletC: Double? = nil,
        tempAvgC: Double? = nil,
        fanRPM: Int? = nil,
        fanPct: Double? = nil,
        fansExtra: [String: Int] = [:],
        fans: [MinerFanSnapshot] = [],
        fanRPM2: Int? = nil,
        fanPct2: Double? = nil,
        frequencyMHz: Double? = nil,
        voltageMV: Double? = nil,
        voltageSetMV: Double? = nil,
        asicCount: Int? = nil,
        smallCoreCount: Int? = nil,
        workmode: Int? = nil,
        boardCount: Int? = nil,
        chipCount: Int? = nil,
        boards: [MinerBoardSnapshot] = [],
        currentA: Double? = nil,
        hwErrors: Int? = nil,
        hwTotal: Int? = nil,
        hwErrorRate: Double? = nil,
        uptimeS: Int? = nil,
        accepted: Int? = nil,
        rejected: Int? = nil,
        bestDifficulty: Double? = nil,
        bestDifficultyAllTime: Double? = nil,
        networkDifficulty: Double? = nil,
        lastShareDiff: Double? = nil,
        poolURL: String? = nil,
        worker: String? = nil,
        poolURLFallback: String? = nil,
        workerFallback: String? = nil,
        poolActive: String? = nil,
        pools: [MinerPoolSnapshot] = [],
        blocksFound: Int? = nil,
        blockHeight: Int? = nil,
        raw: [String: JSONValue] = [:]
    ) {
        self.family = family
        self.host = host
        self.online = online
        self.error = error
        self.miningPaused = miningPaused
        self.mac = mac
        self.model = model
        self.chipModel = chipModel
        self.hostname = hostname
        self.firmwareVersion = firmwareVersion
        self.hashrateTHs = hashrateTHs
        self.powerW = powerW
        self.efficiencyWPerTHs = efficiencyWPerTHs
        self.expectedHashrateTHs = expectedHashrateTHs
        self.errorPct = errorPct
        self.inputVoltageMV = inputVoltageMV
        self.maxPowerW = maxPowerW
        self.tempChipC = tempChipC
        self.tempChip2C = tempChip2C
        self.tempVRC = tempVRC
        self.tempOutletC = tempOutletC
        self.tempInletC = tempInletC
        self.tempAvgC = tempAvgC
        self.fanRPM = fanRPM
        self.fanPct = fanPct
        self.fansExtra = fansExtra
        self.fans = fans
        self.fanRPM2 = fanRPM2
        self.fanPct2 = fanPct2
        self.frequencyMHz = frequencyMHz
        self.voltageMV = voltageMV
        self.voltageSetMV = voltageSetMV
        self.asicCount = asicCount
        self.smallCoreCount = smallCoreCount
        self.workmode = workmode
        self.boardCount = boardCount
        self.chipCount = chipCount
        self.boards = boards
        self.currentA = currentA
        self.hwErrors = hwErrors
        self.hwTotal = hwTotal
        self.hwErrorRate = hwErrorRate
        self.uptimeS = uptimeS
        self.accepted = accepted
        self.rejected = rejected
        self.bestDifficulty = bestDifficulty
        self.bestDifficultyAllTime = bestDifficultyAllTime
        self.networkDifficulty = networkDifficulty
        self.lastShareDiff = lastShareDiff
        self.poolURL = poolURL
        self.worker = worker
        self.poolURLFallback = poolURLFallback
        self.workerFallback = workerFallback
        self.poolActive = poolActive
        self.pools = pools
        self.blocksFound = blocksFound
        self.blockHeight = blockHeight
        self.raw = raw
    }

    /// Converts the parsed driver sample into a canonical `MinerInfo`, preserving any original raw
    /// fields while normalizing key telemetry fields (`hashRate` in GH/s, `temp`, `power`, etc.)
    /// so every HashFleet consumer works seamlessly across all firmware families.
    public func toMinerInfo(preservingFlatRaw: Bool = false) -> MinerInfo {
        var out: [String: JSONValue] = preservingFlatRaw ? raw : [:]
        out["firmwareFamily"] = .string(family)
        applyIdentityFields(&out, preservingFlatRaw: preservingFlatRaw)
        applyPerformanceAndThermalFields(&out, preservingFlatRaw: preservingFlatRaw)
        applyClockAndMiningFields(&out)
        applyPoolFields(&out)
        return MinerInfo(raw: out)
    }

    private func applyIdentityFields(_ out: inout [String: JSONValue], preservingFlatRaw: Bool) {
        setIfMissingString(&out, key: "hostname", value: hostname)
        setIfMissingString(&out, key: "macAddr", value: mac)
        if !preservingFlatRaw || ["nmaxe", "axeForge", "harloOS", "thorOS", "canaan", "canaannano3", "braiins", "luxos"].contains(family) {
            setIfMissingString(&out, key: "deviceModel", value: model)
        }
        if let chipModel, !chipModel.isEmpty {
            setIfMissingString(&out, key: "ASICModel", value: chipModel)
        } else if out["ASICModel"] == nil, out["asicModel"] == nil {
            setIfMissingString(&out, key: "ASICModel", value: model)
        }
        setIfMissingString(&out, key: "version", value: firmwareVersion)
        if let miningPaused { out["miningPaused"] = .bool(miningPaused) }
    }

    private func applyPerformanceAndThermalFields(_ out: inout [String: JSONValue], preservingFlatRaw: Bool) {
        if let hashrateTHs {
            if !preservingFlatRaw || out["hashRate"]?.doubleValue == nil {
                out["hashRate"] = .number(MinerDriverParse.roundTo(hashrateTHs * 1_000.0, places: 2))
            }
        } else if preservingFlatRaw {
            out.removeValue(forKey: "hashRate")
            out.removeValue(forKey: "hashrate")
        }
        setIfMissingNumber(&out, key: "expectedHashrate", value: expectedHashrateTHs.map {
            MinerDriverParse.roundTo($0 * 1_000.0, places: 2)
        })
        setIfMissingNumber(&out, key: "power", value: powerW)
        setIfMissingNumber(&out, key: "errorPercentage", value: errorPct)
        setIfMissingNumber(&out, key: "voltage", value: inputVoltageMV)
        setIfMissingNumber(&out, key: "maxPower", value: maxPowerW)

        if let tempChipC { out["temp"] = .number(tempChipC) }
        if let tempChip2C { out["temp2"] = .number(tempChip2C) }
        setIfMissingNumber(&out, key: "vrTemp", value: tempVRC)
        if let tempAvgC { out["tempAvg"] = .number(tempAvgC) }
        if let tempInletC { out["tempInlet"] = .number(tempInletC) }
        if let tempOutletC { out["tempOutlet"] = .number(tempOutletC) }

        setIfMissingInt(&out, key: "fanrpm", value: fanRPM)
        setIfMissingNumber(&out, key: "fanspeed", value: fanPct)
        if let fanRPM2 {
            out["fan2rpm"] = .integer(Int64(fanRPM2))
            setIfMissingInt(&out, key: "fanrpm2", value: fanRPM2)
        }
        setIfMissingNumber(&out, key: "fanspeed2", value: fanPct2)
    }

    private func applyClockAndMiningFields(_ out: inout [String: JSONValue]) {
        setIfMissingNumber(&out, key: "frequency", value: frequencyMHz)
        setIfMissingNumber(&out, key: "coreVoltage", value: voltageSetMV ?? voltageMV)
        setIfMissingNumber(&out, key: "coreVoltageActual", value: voltageMV)
        setIfMissingInt(&out, key: "asicCount", value: asicCount)
        setIfMissingInt(&out, key: "smallCoreCount", value: smallCoreCount)
        if let currentA {
            out["currentA"] = .number(currentA)
            setIfMissingNumber(&out, key: "current", value: MinerDriverParse.roundTo(currentA * 1_000.0, places: 1))
        }
        if let workmode { out["workmode"] = .integer(Int64(workmode)) }
        if let powerFault, !powerFault.isEmpty { out["power_fault"] = .string(powerFault) }
        if let hwErrors { out["hwErrors"] = .integer(Int64(hwErrors)) }
        if let hwErrorRate { out["hwErrorRate"] = .number(hwErrorRate) }

        setIfMissingInt(&out, key: "uptimeSeconds", value: uptimeS)
        setIfMissingInt(&out, key: "sharesAccepted", value: accepted)
        setIfMissingInt(&out, key: "sharesRejected", value: rejected)
        if let best = bestDifficultyAllTime ?? bestDifficulty, out["bestDiff"] == nil {
            out["bestDiff"] = Self.numberOrInteger(best)
        }
        if let bestDifficulty, out["bestSessionDiff"] == nil {
            out["bestSessionDiff"] = Self.numberOrInteger(bestDifficulty)
        }
        if let networkDifficulty, out["networkDifficulty"] == nil {
            out["networkDifficulty"] = Self.numberOrInteger(networkDifficulty)
        }
        if let lastShareDiff { out["lastShareDiff"] = Self.numberOrInteger(lastShareDiff) }
        setIfMissingInt(&out, key: "blockFound", value: blocksFound)
        setIfMissingInt(&out, key: "blockHeight", value: blockHeight)
    }

    private func applyPoolFields(_ out: inout [String: JSONValue]) {
        if let poolURL, !poolURL.isEmpty, out["stratumURL"] == nil {
            let (hostPart, portPart) = MinerDriverParse.splitHostPort(url: poolURL, port: nil)
            out["stratumURL"] = .string(hostPart)
            setIfMissingInt(&out, key: "stratumPort", value: portPart)
        }
        setIfMissingString(&out, key: "stratumUser", value: worker)
        if let poolURLFallback, !poolURLFallback.isEmpty, out["fallbackStratumURL"] == nil {
            let (hostPart, portPart) = MinerDriverParse.splitHostPort(url: poolURLFallback, port: nil)
            out["fallbackStratumURL"] = .string(hostPart)
            setIfMissingInt(&out, key: "fallbackStratumPort", value: portPart)
        }
        setIfMissingString(&out, key: "fallbackStratumUser", value: workerFallback)
        if let poolActive {
            out["poolActive"] = .string(poolActive)
            if out["isUsingFallbackStratum"] == nil {
                out["isUsingFallbackStratum"] = .bool(poolActive == "fallback")
            }
        }
        let activePing = pools.first(where: { $0.active == true })?.pingMs ?? pools.first?.pingMs
        setIfMissingNumber(&out, key: "responseTime", value: activePing)
    }

    private func setIfMissingString(_ out: inout [String: JSONValue], key: String, value: String?) {
        guard let value, !value.isEmpty, out[key]?.stringValue?.isEmpty != false else { return }
        out[key] = .string(value)
    }

    private func setIfMissingNumber(_ out: inout [String: JSONValue], key: String, value: Double?) {
        guard let value, out[key]?.doubleValue == nil else { return }
        out[key] = .number(value)
    }

    private func setIfMissingInt(_ out: inout [String: JSONValue], key: String, value: Int?) {
        guard let value, out[key]?.intValue == nil else { return }
        out[key] = .integer(Int64(value))
    }

    private static func numberOrInteger(_ value: Double) -> JSONValue {
        if value.isFinite, value.rounded(.towardZero) == value, let exact = Int64(exactly: value) {
            return .integer(exact)
        }
        return .number(value)
    }
}
