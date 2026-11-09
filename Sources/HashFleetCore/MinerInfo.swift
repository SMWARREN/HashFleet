import Foundation

public struct MinerInfo: Codable, Hashable, Sendable {
    /// Complete firmware object, including unknown keys, arrays and nested objects.
    public var raw: [String: JSONValue]

    public init(raw: [String: JSONValue]) { self.raw = raw }

    public init(from decoder: any Decoder) throws {
        raw = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public func value(for key: String) -> JSONValue? { raw[key] }
    public subscript(key: String) -> JSONValue? { raw[key] }

    private func number(_ keys: String...) -> Double {
        keys.lazy.compactMap { raw[$0]?.doubleValue }.first ?? 0
    }
    private func integer(_ keys: String...) -> Int {
        keys.lazy.compactMap { raw[$0]?.intValue }.first ?? 0
    }
    private func text(_ keys: String...) -> String {
        keys.lazy.compactMap { raw[$0]?.stringValue }.first ?? ""
    }
    private func difficulty(_ keys: String...) -> String {
        for key in keys {
            guard let val = raw[key] else {
                continue
            }
            switch val {
            case .string(let str):
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed
            case .integer(let intVal):
                return String(intVal)
            case .unsignedInteger(let uintVal):
                return String(uintVal)
            case .number(let num):
                guard num.isFinite else { continue }
                if let exact = Int64(exactly: num) {
                    return String(exact)
                }
                return String(num)
            case .bool, .null, .object, .array:
                continue
            }
        }
        return ""
    }

    /// GH/s. Firmware voltage/current values remain in their original units (typically mV/mA).
    public var hashRate: Double { number("hashRate", "hashrate") }
    public var hashRate1m: Double { number("hashRate_1m") }
    public var hashRate10m: Double { number("hashRate_10m") }
    public var hashRate1h: Double { number("hashRate_1h") }
    public var expectedHashrate: Double { number("expectedHashrate") }
    public var power: Double { number("power") }
    public var temp: Double { number("temp") }
    public var temp2: Double { number("temp2") }
    public var vrTemp: Double { number("vrTemp") }
    public var fanSpeed: Double { number("fanspeed", "fanSpeed") }
    public var fanRpm: Double { number("fanrpm", "fanRpm") }
    public var fan2Rpm: Double { number("fan2rpm", "fan2Rpm") }
    public var voltage: Double { number("voltage") }
    public var current: Double { number("current") }
    public var frequency: Double { number("frequency") }
    public var actualFrequency: Double { number("actualFrequency", "frequency") }
    public var coreVoltage: Double { number("coreVoltage") }
    public var coreVoltageActual: Double { number("coreVoltageActual") }
    public var wifiRSSI: Double { number("wifiRSSI", "wifiRssi") }
    public var sharesAccepted: Int { integer("sharesAccepted") }
    public var sharesRejected: Int { integer("sharesRejected") }
    public var sharesPending: Int { integer("sharesPending") }
    public var uptimeSeconds: Int { integer("uptimeSeconds") }
    public var hostname: String { text("hostname", "fullHostname", "mdnsHostname") }
    /// Hardware MAC address, the miner's stable identity across IP and mDNS-hostname changes.
    /// Normalized to uppercase without separators so "dc:b4:.." and "DC-B4-.." compare equal.
    public var macAddress: String {
        let raw = text("macAddr", "macAddress", "mac")
        let cleaned = raw.uppercased().filter { $0.isHexDigit }
        return cleaned.count == 12 ? cleaned : ""
    }
    public var version: String { text("version") }
    public var axeOSVersion: String { text("axeOSVersion") }
    public var asicModel: String { text("ASICModel", "asicModel") }
    public var bestDiff: String { difficulty("bestDiff") }
    public var bestSessionDiff: String { difficulty("bestSessionDiff") }
    public var poolURL: String { text("stratumURL", "poolURL") }
    public var boardVersion: String { text("boardVersion") }
    public var miningPaused: Bool { raw["miningPaused"]?.boolValue ?? false }
    public var pools: [JSONValue] { raw["pools"]?.arrayValue ?? [] }
    public var partitions: [JSONValue] { raw["partitions"]?.arrayValue ?? [] }
    public var efficiencyJoulesPerTerahash: Double? {
        guard hashRate > 0, power > 0 else { return nil }
        return power / (hashRate / 1_000)
    }
    public var rejectedSharePercentage: Double? {
        let total = Double(sharesAccepted) + Double(sharesRejected)
        guard total > 0 else { return nil }
        return Double(sharesRejected) / total * 100
    }
    public var blockFound: Int { integer("blockFound") }
    public var showNewBlock: Bool { raw["showNewBlock"]?.boolValue ?? false }
    public var blockHeight: Int? { raw["blockHeight"]?.intValue }
}
