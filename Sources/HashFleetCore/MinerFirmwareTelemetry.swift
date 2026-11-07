import Foundation

/// One measured firmware hashrate domain, in GH/s. Indices are zero-based wire positions.
public struct MinerHashrateDomain: Identifiable, Equatable, Sendable {
    public let chipIndex: Int
    public let domainIndex: Int
    public let hashrateGHs: Double
    public let nominalHashrateGHs: Double?
    public var id: String { "\(chipIndex):\(domainIndex)" }

    public init(chipIndex: Int, domainIndex: Int, hashrateGHs: Double, nominalHashrateGHs: Double?) {
        self.chipIndex = chipIndex
        self.domainIndex = domainIndex
        self.hashrateGHs = hashrateGHs
        self.nominalHashrateGHs = nominalHashrateGHs
    }
}

extension MinerInfo {
    /// Geometry must be complete and bounded before an aggregate nominal reference is divided.
    /// Missing, unsupported or malformed geometry is not a set of fabricated zero-rate domains.
    public var hashrateDomains: [MinerHashrateDomain] {
        guard let chips = raw["hashrateMonitor"]?.objectValue?["asics"]?.arrayValue,
              (1...64).contains(chips.count) else { return [] }
        var rates: [[Double]] = []
        for chip in chips {
            guard let domains = chip.objectValue?["domains"]?.arrayValue,
                  (1...64).contains(domains.count) else { return [] }
            let values = domains.compactMap(telemetryNonnegativeNumber)
            guard values.count == domains.count else { return [] }
            rates.append(values)
        }
        let count = rates.reduce(0) { $0 + $1.count }
        guard count <= 1024 else { return [] }
        let nominal = telemetryNonnegativeNumber(raw["expectedHashrate"]).flatMap {
            $0 > 0 ? $0 / Double(count) : nil
        }
        return rates.enumerated().flatMap { chip, domains in
            domains.enumerated().map { domain, rate in
                MinerHashrateDomain(chipIndex: chip, domainIndex: domain,
                    hashrateGHs: rate, nominalHashrateGHs: nominal)
            }
        }
    }
}

/// Read-only pool diagnostics. Transport is a reported configuration, never proof of a handshake.
public struct MinerPoolDiagnostics: Equatable, Sendable {
    public let primaryError: String?
    public let banner: String?
    public let usingFallback: Bool?
    public let transportLabel: String

    public init(info: MinerInfo) {
        primaryError = safePoolText(info.raw["primaryPoolError"], info: info)
        banner = safePoolText(info.raw["poolBanner"], info: info)
        usingFallback = explicitTelemetryFlag(info.raw["isUsingFallbackStratum"])
        transportLabel = Self.transport(info: info, fallback: usingFallback)
    }

    private static func transport(info: MinerInfo, fallback: Bool?) -> String {
        guard let selected = selectedPool(info: info, fallback: fallback) else { return "Transport not reported" }
        if let protocolValue = selected["stratumProtocol"], protocolValue != .null {
            guard case .string(let protocolName) = protocolValue else { return "Transport not reported" }
            switch protocolName.lowercased() {
            case "sv2", "stratumv2", "stratum v2", "v2": return "Stratum V2 configured (transport unverified)"
            case "sv1", "stratumv1", "stratum v1", "v1", "": break
            default: return "Transport not reported"
            }
        }
        switch exactTelemetryInteger(selected["stratumTLS"]) {
        case 0: return "TLS disabled in active-pool configuration"
        case 1: return "TLS configured (bundled certificates)"
        case 2: return "TLS configured (custom certificate)"
        default: return "Transport not reported"
        }
    }

    private static func selectedPool(info: MinerInfo, fallback: Bool?) -> [String: JSONValue]? {
        guard let pools = info.raw["pools"] else {
            // A slot identity without its table cannot safely authorize legacy TLS metadata.
            guard info.raw["activePoolIndex"] == nil, let fallback else { return nil }
            return ["stratumTLS": info.raw[fallback ? "fallbackStratumTLS" : "stratumTLS"] ?? .null,
                "stratumProtocol": info.raw[fallback ? "fallbackStratumProtocol" : "stratumProtocol"] ?? .null]
        }
        guard let rows = pools.arrayValue, (1...8).contains(rows.count) else { return nil }
        var slots: [Int: [String: JSONValue]] = [:]
        for row in rows {
            guard let values = row.objectValue, let id = exactTelemetryInteger(values["id"]),
                  (0...7).contains(id), slots[id] == nil else { return nil }
            slots[id] = values
        }
        let active: Int?
        if let reported = info.raw["activePoolIndex"] {
            active = exactTelemetryInteger(reported)
        } else if let fallback {
            active = exactTelemetryInteger(info.raw[fallback ? "secondaryPoolIndex" : "primaryPoolIndex"])
        } else {
            active = nil
        }
        guard let active else { return nil }
        return slots[active]
    }
}

private func telemetryNonnegativeNumber(_ value: JSONValue?) -> Double? {
    let number: Double?
    switch value {
    case .integer(let value): number = Double(value)
    case .unsignedInteger(let value): number = Double(value)
    case .number(let value): number = value
    case .string(let value): number = Double(value)
    default: number = nil
    }
    guard let number, number.isFinite, number >= 0 else { return nil }
    return number
}

private func exactTelemetryInteger(_ value: JSONValue?) -> Int? {
    // Wire slot IDs and TLS modes are JSON numbers, not strings or Boolean coercions.
    switch value {
    case .integer(let value): return Int(exactly: value)
    case .unsignedInteger(let value): return Int(exactly: value)
    case .number(let value): return Int(exactly: value)
    default: return nil
    }
}

private func explicitTelemetryFlag(_ value: JSONValue?) -> Bool? {
    if case .bool(let flag) = value { return flag }
    switch exactTelemetryInteger(value) {
    case 0: return false
    case 1: return true
    default: return nil
    }
}

private func safePoolText(_ value: JSONValue?, info: MinerInfo) -> String? {
    guard case .string(var text) = value else { return nil }
    guard text.utf8.count <= 4096 else { return "Message omitted (too long)" }
    let secretKeys = ["stratumUser", "stratumPassword", "fallbackStratumUser", "fallbackStratumPassword",
        "stratumCert", "fallbackStratumCert", "ssid", "wifiPassword", "stratumV2AuthorityPubkey",
        "fallbackStratumV2AuthorityPubkey", "user", "password", "cert"]
    var dictionaries = [info.raw]
    if let pools = info.raw["pools"]?.arrayValue {
        dictionaries += pools.prefix(8).compactMap(\.objectValue)
    }
    let secrets = dictionaries.flatMap { values in
        secretKeys.compactMap { key -> String? in
            guard case .string(let secret) = values[key], !secret.isEmpty else { return nil }
            return secret
        }
    }.sorted { $0.count > $1.count }
    for secret in secrets { text = text.replacingOccurrences(of: secret, with: "[redacted]") }
    // Unknown URLs may embed credentials, and long opaque tokens may be wallets or keys.
    text = text.replacingOccurrences(of: #"[A-Za-z][A-Za-z0-9+.-]*://\S+"#,
        with: "[URL redacted]", options: .regularExpression)
    text = text.replacingOccurrences(of: #"[A-Za-z0-9_:+/=-]{26,}"#,
        with: "[token redacted]", options: .regularExpression)
    let printable = text.unicodeScalars.map { scalar -> String in
        CharacterSet.controlCharacters.contains(scalar) || scalar.properties.generalCategory == .format
            ? " " : String(scalar)
    }.joined()
    let collapsed = printable.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return collapsed.isEmpty ? nil : String(collapsed.prefix(240))
}
