import Foundation
import HashFleetCore

/// Device list sorting machinery extracted from FleetPreferences so the store file stays
/// within size limits. Ordering rules are unchanged: missing or invalid readings sort last
/// regardless of direction, ties fall back to original order, then to a stable device id.
extension FleetPreferences {
    /// A metric value participating in a sort. `.number` covers both integer and double
    /// telemetry because only ordering matters here; display formatting happens elsewhere.
    enum SortMetric {
        case number(Double)
        /// Counters (shares, uptime) compare as exact 64-bit integers. Routing them through
        /// Double silently collapses neighbouring values above 2^53.
        case integer(Int64)
        case string(String)
        case missing
    }

    private struct SortEntry {
        let index: Int
        let device: MinerDevice
        let metric: SortMetric
    }

    func sorted(_ devices: [MinerDevice], snapshots: [UUID: MinerSnapshot]) -> [MinerDevice] {
        guard devices.count > 1 else { return devices }
        let entries = devices.enumerated().map { offset, device in
            SortEntry(index: offset, device: device, metric: metric(of: sort, device: device, snapshots: snapshots))
        }
        return entries.sorted(by: compareEntries).map(\.device)
    }

    private func metric(of sort: SortOption, device: MinerDevice, snapshots: [UUID: MinerSnapshot]) -> SortMetric {
        switch sort {
        case .name: return .string(device.name)
        case .address: return .string(device.address)
        case .hashrate:
            return numberMetric(device: device, snapshots: snapshots, keys: ["hashRate", "hashrate"])
        case .power:
            return numberMetric(device: device, snapshots: snapshots, keys: ["power"])
        case .temperature:
            return numberMetric(device: device, snapshots: snapshots, keys: ["temp"])
        case .acceptedShares:
            return counterMetric(device: device, snapshots: snapshots, keys: ["sharesAccepted"])
        case .uptime:
            return counterMetric(device: device, snapshots: snapshots, keys: ["uptimeSeconds"])
        case .firmware:
            guard let version = firmwareVersion(for: device, in: snapshots) else { return .missing }
            return .string(version)
        }
    }

    private func compareEntries(_ lhs: SortEntry, _ rhs: SortEntry) -> Bool {
        if case .missing = lhs.metric, case .missing = rhs.metric {
            return tieBreak(lhs, rhs)
        }
        // Missing or offline readings always sort after real readings, regardless of direction.
        if case .missing = rhs.metric { return true }
        if case .missing = lhs.metric { return false }

        switch (lhs.metric, rhs.metric) {
        case let (.number(a), .number(b)):
            return compareValues(a, b, lhs: lhs, rhs: rhs)
        case let (.integer(a), .integer(b)):
            if a != b { return ascending ? a < b : a > b }
            return tieBreak(lhs, rhs)
        case let (.integer(a), .number(b)):
            return compareValues(Double(a), b, lhs: lhs, rhs: rhs)
        case let (.number(a), .integer(b)):
            return compareValues(a, Double(b), lhs: lhs, rhs: rhs)
        case let (.string(a), .string(b)):
            return compareStrings(a, b, lhs: lhs, rhs: rhs)
        default:
            // Mismatched non-missing metric kinds (number vs string, etc.) never occur for a
            // single sort option, but fall back to a stable tie-break rather than crashing.
            return tieBreak(lhs, rhs)
        }
    }

    private func compareStrings(_ a: String, _ b: String, lhs: SortEntry, rhs: SortEntry) -> Bool {
        let comp = a.localizedStandardCompare(b)
        if comp != .orderedSame {
            return ascending ? (comp == .orderedAscending) : (comp == .orderedDescending)
        }
        return tieBreak(lhs, rhs)
    }

    private func compareValues(_ a: Double, _ b: Double, lhs: SortEntry, rhs: SortEntry) -> Bool {
        if a != b {
            return ascending ? a < b : a > b
        }
        return tieBreak(lhs, rhs)
    }

    private func tieBreak(_ lhs: SortEntry, _ rhs: SortEntry) -> Bool {
        lhs.index != rhs.index
            ? (lhs.index < rhs.index)
            : (lhs.device.id.uuidString < rhs.device.id.uuidString)
    }

    /// Raw validated numeric extraction. Distinguishes missing keys, nonfinite values,
    /// negative telemetry, and stale snapshots (error set) from genuine zero values,
    /// so only real measurements participate in ordering.
    private func validatedInfo(for device: MinerDevice, in snapshots: [UUID: MinerSnapshot]) -> MinerInfo? {
        guard let snapshot = snapshots[device.id],
            snapshot.error == nil
        else { return nil }
        return snapshot.info
    }

    private func numberMetric(device: MinerDevice, snapshots: [UUID: MinerSnapshot], keys: [String]) -> SortMetric {
        guard let info = validatedInfo(for: device, in: snapshots) else { return .missing }
        for key in keys {
            guard let raw = info.raw[key] else { continue }
            guard let value = exactNumber(raw), value.isFinite, value >= 0 else { return .missing }
            return .number(value)
        }
        return .missing
    }

    /// Exact counter extraction. Values must be whole and non-negative: a fractional share
    /// or uptime reading is malformed telemetry, not a small value, so it sorts as missing.
    private func counterMetric(device: MinerDevice, snapshots: [UUID: MinerSnapshot], keys: [String]) -> SortMetric {
        guard let info = validatedInfo(for: device, in: snapshots) else { return .missing }
        for key in keys {
            guard let raw = info.raw[key] else { continue }
            guard let value = exactInteger(raw), value >= 0 else { return .missing }
            return .integer(value)
        }
        return .missing
    }

    private func exactInteger(_ raw: JSONValue) -> Int64? {
        switch raw {
        case .integer(let value): return Int64(exactly: value)
        case .unsignedInteger(let value): return Int64(exactly: value)
        case .number(let value):
            guard value.isFinite, value.rounded() == value else { return nil }
            return Int64(exactly: value)
        case .string(let value):
            return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    /// Exact extraction, avoiding Double's 53-bit precision loss for large counters like
    /// shares accepted and uptime before the value is compared.
    private func exactNumber(_ raw: JSONValue) -> Double? {
        switch raw {
        case .integer(let value): return Double(exactly: value)
        case .unsignedInteger(let value): return Double(exactly: value)
        case .number(let value): return value.isFinite ? value : nil
        case .string(let value):
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    private func firmwareVersion(for device: MinerDevice, in snapshots: [UUID: MinerSnapshot]) -> String? {
        guard let info = validatedInfo(for: device, in: snapshots) else { return nil }
        let version = !info.version.isEmpty ? info.version : info.axeOSVersion
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
