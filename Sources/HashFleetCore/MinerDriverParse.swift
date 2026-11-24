import Foundation

/// Parsing utilities shared across MinerWatch drivers.
public enum MinerDriverParse {
    private static let siSuffixes: [Character: Double] = [
        "k": 1e3,
        "m": 1e6,
        "g": 1e9,
        "t": 1e12,
        "p": 1e15,
        "e": 1e18,
        "z": 1e21,
        "y": 1e24
    ]

    /// Parses a difficulty value as either a number or an SI-suffixed string (e.g., "4.29G", "2.15 M").
    public static func parseSIDifficulty(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .integer(let i):
            return Double(i)
        case .unsignedInteger(let u):
            return Double(u)
        case .number(let d):
            return d.isFinite ? d : nil
        case .string(let s):
            return parseSIDifficultyString(s)
        case .bool, .null, .array, .object:
            return nil
        }
    }

    public static func parseSIDifficultyString(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let lastChar = Character(s.last!.lowercased())
        let numPart: String
        let mult: Double
        if lastChar.isLetter, let factor = siSuffixes[lastChar] {
            numPart = String(s.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            mult = factor
        } else {
            numPart = s
            mult = 1.0
        }
        guard let val = Double(numPart), val.isFinite else { return nil }
        let result = val * mult
        return result.isFinite ? result : nil
    }

    public static func optFloat(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .bool, .null, .array, .object:
            return nil
        case .integer(let i):
            return Double(i)
        case .unsignedInteger(let u):
            return Double(u)
        case .number(let d):
            return d.isFinite ? d : nil
        case .string(let str):
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let firstWord = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
            let cleaned = firstWord.hasSuffix("%") ? String(firstWord.dropLast()) : firstWord
            guard let d = Double(cleaned), d.isFinite else { return nil }
            return d
        }
    }

    public static func optInt(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .bool, .null, .array, .object:
            return nil
        case .integer(let i):
            return Int(exactly: i)
        case .unsignedInteger(let u):
            return Int(exactly: u)
        case .number(let d):
            guard d.isFinite else { return nil }
            return Int(d)
        case .string(let str):
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let i = Int(trimmed) { return i }
            if let d = optFloat(value) { return Int(d) }
            return nil
        }
    }

    public static func coerceFlag(_ value: JSONValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .bool(let b):
            return b
        case .integer(let i):
            return i != 0
        case .unsignedInteger(let u):
            return u != 0
        case .number(let d):
            return d != 0
        case .string(let s):
            let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes", "on"].contains(lower)
        case .null, .array, .object:
            return false
        }
    }

    /// Drops the firmware's `-1` / `<= 0` "sensor absent" sentinel.
    public static func validTemp(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    public static func roundTo(_ value: Double, places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }

    public static func formatMAC(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        guard cleaned.count == 12, cleaned.allSatisfy(\.isHexDigit) else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        var parts: [String] = []
        var idx = cleaned.startIndex
        for _ in 0..<6 {
            let next = cleaned.index(idx, offsetBy: 2)
            parts.append(String(cleaned[idx..<next]))
            idx = next
        }
        return parts.joined(separator: ":")
    }

    public static func splitHostPort(url: String, port: Int?) -> (String, Int?) {
        var host = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = host.range(of: "://") {
            host = String(host[range.upperBound...])
        }
        if port == nil {
            let colons = host.filter { $0 == ":" }.count
            if colons == 1, let idx = host.firstIndex(of: ":") {
                let h = String(host[..<idx])
                let pStr = String(host[host.index(after: idx)...])
                if let p = Int(pStr) {
                    return (h, p)
                }
                return (h, nil)
            }
        }
        return (host, port)
    }

    public static func stripScheme(_ url: String?) -> String? {
        guard var url = url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            return nil
        }
        if let range = url.range(of: "://") {
            url = String(url[range.upperBound...])
        }
        return url.isEmpty ? nil : url
    }

    public static func parseCgminerPoolEntry(_ entry: [String: JSONValue]) -> MinerPoolSnapshot {
        let url = (entry["Stratum URL"]?.stringValue ?? entry["URL"]?.stringValue ?? entry["url"]?.stringValue)
            .flatMap { $0.isEmpty ? nil : $0 }
        let user = (entry["User"]?.stringValue ?? entry["user"]?.stringValue)
            .flatMap { $0.isEmpty ? nil : $0 }
        let priority = optInt(entry["Priority"])

        let statusRaw = entry["Status"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = (statusRaw?.isEmpty == false) ? statusRaw?.lowercased() : nil

        let accepted = optInt(entry["Accepted"])
        let rejected = optInt(entry["Rejected"])
        let stale = optInt(entry["Stale"])

        var lastShare = optInt(entry["Last Share Time"] ?? entry["LastShareTime"])
        if lastShare == 0 { lastShare = nil }

        var active: Bool?
        if let sa = entry["Stratum Active"] {
            if case .bool(let b) = sa {
                active = b
            } else if let str = sa.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                active = str.lowercased() == "true"
            }
        } else if case .bool(let conn) = entry["connected"] {
            active = conn
        }

        return MinerPoolSnapshot(
            url: url,
            user: user,
            status: status,
            priority: priority,
            accepted: accepted,
            rejected: rejected,
            stale: stale,
            lastShareTimestamp: lastShare,
            active: active
        )
    }

    public static func assignCgminerPoolSlots(_ pools: inout [MinerPoolSnapshot]) {
        for index in pools.indices {
            pools[index].slot = index == 0 ? "primary" : "fallback"
        }
    }

    public static func sectionArray(_ data: [String: JSONValue], key: String) -> [[String: JSONValue]] {
        guard let val = data[key] else { return [] }
        switch val {
        case .array(let arr):
            return arr.compactMap(\.objectValue)
        case .object(let dict):
            return [dict]
        default:
            return []
        }
    }

    public static func nonEmptyString(_ value: JSONValue?) -> String? {
        guard let str = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else {
            return nil
        }
        return str
    }

    public static func firstNonZeroFloat(_ values: JSONValue?...) -> Double? {
        for val in values {
            if let f = optFloat(val), f != 0 {
                return f
            }
        }
        for val in values {
            if let f = optFloat(val) {
                return f
            }
        }
        return nil
    }
}
