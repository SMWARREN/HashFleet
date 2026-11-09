import Foundation
import HashFleetCore

extension MinerDiagnosticsModel {
    // MARK: - Sanitization Helpers

    /// Sanitizes pool URLs to ensure all userinfo (user & password) as well as query/fragment are completely removed.
    /// Handles cases like `stratum+tcp://user:password@pool.com:3333` -> `stratum+tcp://pool.com:3333`
    /// as well as bare `user:password@host` or invalid URL schemes.
    public static func sanitizeStratumURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "Not reported" { return trimmed }

        var sanitized = trimmed
        // Remove query and fragment if present
        if let questionIndex = sanitized.firstIndex(of: "?") {
            sanitized = String(sanitized[..<questionIndex])
        }
        if let hashIndex = sanitized.firstIndex(of: "#") {
            sanitized = String(sanitized[..<hashIndex])
        }

        // Remove userinfo (user:pass@ or user@)
        if let atIndex = sanitized.firstIndex(of: "@") {
            if let schemeRange = sanitized.range(of: "://") {
                if schemeRange.upperBound < atIndex {
                    let scheme = sanitized[..<schemeRange.upperBound]
                    let hostAndPort = sanitized[sanitized.index(after: atIndex)...]
                    return "\(scheme)\(hostAndPort)"
                }
            } else {
                // Bare user:pass@host
                let hostAndPort = sanitized[sanitized.index(after: atIndex)...]
                return String(hostAndPort)
            }
        }
        return sanitized
    }

    /// Sanitizes poolConnectionInfo to prevent leaking raw server internals or sensitive text.
    public static func sanitizeConnectionInfo(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Only allow safe, known network descriptors (IPv4, IPv6, TLS, SV1, SV2, DNS, etc.)
        let safeWords = ["ipv4", "ipv6", "tls", "sv1", "sv2", "tcp", "ssl", "direct", "fallback"]
        let lower = trimmed.lowercased()
        if safeWords.contains(where: { lower.contains($0) }) && trimmed.count <= 32 {
            return trimmed
        }
        return nil
    }

    // MARK: - Section Builders

    static func parseElectrical(
        raw: [String: JSONValue],
        currentHashrateGHs currentHash: Double?
    ) -> ElectricalAndClocks {
        // --- Electrical & Clocks ---
        let configuredFreq = Self.parsePositiveDouble(raw, keys: "frequency")
        let actualFreq = Self.parsePositiveDouble(raw, keys: "actualFrequency")
        let configuredVolt = Self.parsePositiveDouble(raw, keys: "coreVoltage")
        let actualVolt = Self.parsePositiveDouble(raw, keys: "coreVoltageActual")
        let inputVolt = Self.parsePositiveDouble(raw, keys: "voltage")
        let nominalVolt = Self.parsePositiveDouble(raw, keys: "nominalVoltage")
        let currentMA = Self.parsePositiveDouble(raw, keys: "current")
        let powerW = Self.parsePositiveDouble(raw, keys: "power")
        let dailyEnergy = Self.computeDailyEnergyKWh(powerWatts: powerW)

        // Efficiency (J/TH) = W / (TH/s) = power / (hashrate / 1000)
        // Per review: allow real 0W + positive hashrate gives 0.0 J/TH, finite-check result.
        let efficiency: Double? = {
            guard let powerW, powerW >= 0, let currentHash, currentHash > 0 else { return nil }
            let th = currentHash / 1_000.0
            guard th > 0 else { return nil }
            let val = powerW / th
            return val.isFinite ? val : nil
        }()

        return ElectricalAndClocks(
            configuredFrequencyMHz: configuredFreq,
            actualFrequencyMHz: actualFreq,
            configuredCoreVoltageMV: configuredVolt,
            actualCoreVoltageMV: actualVolt,
            inputVoltageMV: inputVolt,
            nominalVoltageV: nominalVolt,
            currentMilliamps: currentMA,
            powerWatts: powerW,
            dailyEnergyEstimateKWh: dailyEnergy,
            efficiencyJoulesPerTerahash: efficiency
        )
    }

    static func parseThermal(raw: [String: JSONValue]) -> ThermalAndCooling {
        // --- Thermal & Cooling ---
        // Pinned audit: U6 returns -1 for unavailable temp/before init.
        let primaryTemp = Self.parseTemperature(raw, keys: "temp")
        let secondaryTemp = Self.parseTemperature(raw, keys: "temp2")
        let isSecondaryAvailable = secondaryTemp != nil
        let vrTemp = Self.parseTemperature(raw, keys: "vrTemp")
        let isVRAvailable = vrTemp != nil

        let fanSpeed = Self.parsePercentage(raw, keys: "fanspeed", "fanSpeed")
        let fan1 = Self.parsePositiveDouble(raw, keys: "fanrpm", "fanRpm")
        // Fan 2: EMC2302 returns 0 without sensor or when stopped. Negative is sentinel.
        let (fan2, isFan2Reported) = Self.parseFan2RPM(raw)
        let targetTemp = Self.parsePositiveDouble(raw, keys: "temptarget")
        let minFan = Self.parsePercentage(raw, keys: "minFanSpeed")

        return ThermalAndCooling(
            primaryChipTempCelsius: primaryTemp,
            secondaryChipTempCelsius: secondaryTemp,
            isSecondaryTempAvailable: isSecondaryAvailable,
            vrTempCelsius: vrTemp,
            isVRTempAvailable: isVRAvailable,
            fanSpeedPercent: fanSpeed,
            fan1RPM: fan1,
            fan2RPM: fan2,
            isFan2Available: isFan2Reported,
            targetTempCelsius: targetTemp,
            minFanSpeedPercent: minFan
        )
    }

    static func parseHashrate(
        raw: [String: JSONValue],
        currentHashrateGHs currentHash: Double?
    ) -> HashrateAndPerformance {
        // --- Hashrate & Performance ---
        let hr1m = Self.parsePositiveDouble(raw, keys: "hashRate_1m")
        let hr10m = Self.parsePositiveDouble(raw, keys: "hashRate_10m")
        let hr1h = Self.parsePositiveDouble(raw, keys: "hashRate_1h")
        let expectedHr = Self.parsePositiveDouble(raw, keys: "expectedHashrate")
        let errorPct = Self.parsePercentage(raw, keys: "errorPercentage")

        let acceptedShares = Self.parseNonNegativeInt(raw, keys: "sharesAccepted")
        let rejectedShares = Self.parseNonNegativeInt(raw, keys: "sharesRejected")
        let pendingShares = Self.parseNonNegativeInt(raw, keys: "sharesPending")

        let rejectedPct: Double? = {
            guard let accepted = acceptedShares, let rejected = rejectedShares else { return nil }
            let total = Double(accepted) + Double(rejected)
            guard total > 0 else { return 0.0 }
            let pct = (Double(rejected) / total) * 100.0
            return (pct.isFinite && pct >= 0 && pct <= 100) ? pct : nil
        }()

        return HashrateAndPerformance(
            currentHashrateGHs: currentHash,
            hashrate1mGHs: hr1m,
            hashrate10mGHs: hr10m,
            hashrate1hGHs: hr1h,
            expectedHashrateGHs: expectedHr,
            asicErrorPercentage: errorPct,
            rejectedSharePercentage: rejectedPct,
            sharesAccepted: acceptedShares,
            sharesRejected: rejectedShares,
            sharesPending: pendingShares
        )
    }

    /// Slot-level connection facts resolved against raw fallbacks.
    private struct SlotDetails {
        let url, protocolLabel: String?
        let port: Int?
        let tls: Bool?
    }

    private static func firstString(_ dict: [String: JSONValue], keys: [String]) -> String? {
        keys.compactMap { Self.parseNonEmptyString(dict, keys: $0) }.first
    }

    private static func firstPositiveInt(_ dict: [String: JSONValue], keys: [String]) -> Int? {
        keys.compactMap { Self.parsePositiveInt(dict, keys: $0) }.first
    }

    /// Slot fields win over top-level fields; `isFallback` selects the fallback key families.
    private static func slotDetails(
        _ slot: [String: JSONValue]?,
        raw: [String: JSONValue],
        isFallback: Bool
    ) -> SlotDetails {
        let slot = slot ?? [:]
        let urlKeys = isFallback ? ["url", "stratumURL", "fallbackStratumURL"] : ["url", "stratumURL"]
        let rawURLKeys = isFallback ? ["fallbackStratumURL"] : ["stratumURL", "poolURL"]
        let portKeys = isFallback ? ["port", "stratumPort", "fallbackStratumPort"] : ["port", "stratumPort"]
        let rawPortKeys = isFallback ? ["fallbackStratumPort"] : ["stratumPort"]
        let protoKeys =
            isFallback
            ? ["protocol", "stratumProtocol", "fallbackStratumProtocol"]
            : ["protocol", "stratumProtocol"]
        let rawProtoKeys = isFallback ? ["fallbackStratumProtocol"] : ["stratumProtocol"]
        let tlsKeys = isFallback ? ["tls", "stratumTLS", "fallbackStratumTLS"] : ["tls", "stratumTLS"]
        let rawTLSKey = isFallback ? "fallbackStratumTLS" : "stratumTLS"
        let url = Self.sanitizeStratumURL(
            Self.firstString(slot, keys: urlKeys)
                ?? Self.firstString(raw, keys: rawURLKeys)
        )
        let tls = tlsKeys.compactMap { slot[$0]?.boolValue }.first ?? raw[rawTLSKey]?.boolValue
        return SlotDetails(
            url: url,
            protocolLabel: Self.firstString(slot, keys: protoKeys)
                ?? Self.firstString(raw, keys: rawProtoKeys),
            port: Self.firstPositiveInt(slot, keys: portKeys)
                ?? Self.firstPositiveInt(raw, keys: rawPortKeys),
            tls: tls
        )
    }

    static func parsePool(raw: [String: JSONValue]) -> PoolAndConnection {
        // Pool and connection fields. MinerActivePool resolves the active slot naming.
        let activePool = MinerActivePool(info: MinerInfo(raw: raw))
        let activeTitle = activePool.title
        let activeURL = Self.sanitizeStratumURL(activePool.value) ?? activePool.value
        let fallbackFlag = raw["isUsingFallbackStratum"]?.boolValue

        let poolsArray = raw["pools"]?.arrayValue?.compactMap(\.objectValue)

        func slotObj(for slotId: Int?) -> [String: JSONValue]? {
            guard let slotId, let pools = poolsArray else { return nil }
            return pools.first(where: { $0["id"]?.intValue == slotId })
        }

        let primary = slotDetails(slotObj(for: raw["primaryPoolIndex"]?.intValue), raw: raw, isFallback: false)
        let fallback = slotDetails(slotObj(for: raw["secondaryPoolIndex"]?.intValue), raw: raw, isFallback: true)

        let respTime = Self.parsePositiveDouble(raw, keys: "responseTime")
        let batchSize = Self.parsePositiveInt(raw, keys: "responseShareBatch")
        let poolDiff = Self.parsePositiveDouble(raw, keys: "poolDifficulty")
        let bestD = Self.parseNonEmptyString(raw, keys: "bestDiff")
        let bestSessD = Self.parseNonEmptyString(raw, keys: "bestSessionDiff")
        // poolConnectionInfo sanitization: only allow short standard family labels like IPv4, IPv6, TLS
        let connInfo = Self.sanitizeConnectionInfo(Self.parseNonEmptyString(raw, keys: "poolConnectionInfo"))
        let reasons = Self.parseRejectionReasons(raw["sharesRejectedReasons"])

        return PoolAndConnection(
            activeConnectionTitle: activeTitle,
            activeConnectionURL: activeURL,
            isUsingFallback: fallbackFlag,
            primaryURL: primary.url,
            primaryPort: primary.port,
            primaryProtocol: primary.protocolLabel,
            primaryTLS: primary.tls,
            fallbackURL: fallback.url,
            fallbackPort: fallback.port,
            fallbackProtocol: fallback.protocolLabel,
            fallbackTLS: fallback.tls,
            responseTimeMs: respTime,
            responseShareBatch: batchSize,
            poolDifficulty: poolDiff,
            bestDiff: bestD,
            bestSessionDiff: bestSessD,
            poolConnectionInfo: connInfo,
            rejectionReasons: reasons
        )
    }

    static func parseSystem(raw: [String: JSONValue]) -> SystemAndFirmware {
        // --- System & Firmware ---
        let uptime = Self.parseNonNegativeInt(raw, keys: "uptimeSeconds")
        let totalUptime = Self.parseNonNegativeInt(raw, keys: "totalUptimeSeconds")
        let heap = Self.parsePositiveInt(raw, keys: "freeHeap")
        let cpu = Self.parsePercentage(raw, keys: "cpuUsage")
        let wifi = Self.parseDouble(raw, keys: ["wifiRSSI", "wifiRssi"], allowNegative: true)
        let ssid = Self.parseNonEmptyString(raw, keys: "ssid")
        let reset = Self.parseNonEmptyString(raw, keys: "resetReason")
        let partition = Self.parseNonEmptyString(raw, keys: "runningPartition")
        let fwVersion = Self.parseNonEmptyString(raw, keys: "version", "firmwareVersion")
        let axeOS = Self.parseNonEmptyString(raw, keys: "axeOSVersion")
        let board = Self.parseNonEmptyString(raw, keys: "boardVersion")

        return SystemAndFirmware(
            sessionUptimeSeconds: uptime,
            totalUptimeSeconds: totalUptime,
            freeHeapBytes: heap,
            cpuUsagePercent: cpu,
            wifiRSSI: wifi,
            wifiSSID: ssid,
            resetReason: reset,
            runningPartition: partition,
            firmwareVersion: fwVersion,
            axeOSVersion: axeOS,
            boardVersion: board
        )
    }

    // MARK: - Parsing Helpers

    static func parseDouble(
        _ raw: [String: JSONValue], keys: [String], allowNegative: Bool = false
    ) -> Double? {
        for key in keys {
            guard let val = raw[key], let num = val.doubleValue, num.isFinite else {
                continue
            }
            if !allowNegative && num < 0 { continue }
            return num
        }
        return nil
    }

    static func parsePositiveDouble(_ raw: [String: JSONValue], keys: String...) -> Double? {
        for key in keys {
            guard let val = raw[key], let num = val.doubleValue, num.isFinite, num >= 0 else { continue }
            return num
        }
        return nil
    }

    /// Temperatures use -1 as an upstream initialization/unavailability sentinel.
    /// Values < 0 are strictly unavailable sentinels and must not be treated as real temperatures.
    static func parseTemperature(_ raw: [String: JSONValue], keys: String...) -> Double? {
        for key in keys {
            guard let val = raw[key], let num = val.doubleValue, num.isFinite else { continue }
            guard num >= 0 else { continue }
            return num
        }
        return nil
    }

    /// Parses fan 2 RPM, returning `(rpm: Double?, isReported: Bool)`.
    /// Upstream audit: EMC2302 returns 0 when fan 2 is stopped or channel absent.
    /// Negative values are sentinels. A 0 reading is honest 0 RPM, not fabricated unsupported.
    static func parseFan2RPM(_ raw: [String: JSONValue]) -> (Double?, Bool) {
        let keys = ["fan2rpm", "fan2Rpm"]
        for key in keys {
            guard let val = raw[key] else { continue }
            guard let num = val.doubleValue, num.isFinite else { continue }
            guard num >= 0 else { return (nil, false) }
            return (num, true)
        }
        return (nil, false)
    }

    /// Parses percentage values, strictly bounded in 0...100.
    static func parsePercentage(_ raw: [String: JSONValue], keys: String...) -> Double? {
        for key in keys {
            guard let val = raw[key], let num = val.doubleValue, num.isFinite, num >= 0, num <= 100 else { continue }
            return num
        }
        return nil
    }

    static func parseNonNegativeInt(_ raw: [String: JSONValue], keys: String...) -> Int? {
        for key in keys {
            guard let val = raw[key], let intVal = val.intValue, intVal >= 0 else { continue }
            return intVal
        }
        return nil
    }

    static func parsePositiveInt(_ raw: [String: JSONValue], keys: String...) -> Int? {
        for key in keys {
            guard let val = raw[key], let intVal = val.intValue, intVal > 0 else { continue }
            return intVal
        }
        return nil
    }

    static func parseNonEmptyString(_ raw: [String: JSONValue], keys: String...) -> String? {
        for key in keys {
            guard let val = raw[key] else { continue }
            switch val {
            case .string(let stringValue):
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            case .integer(let integerValue):
                return String(integerValue)
            case .unsignedInteger(let unsignedValue):
                return String(unsignedValue)
            case .number(let numberValue):
                if numberValue.isFinite {
                    if let exact = Int64(exactly: numberValue) { return String(exact) }
                    return String(numberValue)
                }
            default:
                continue
            }
        }
        return nil
    }
}
