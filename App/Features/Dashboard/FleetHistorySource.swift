import Foundation
import HashFleetCore

/// Website-style recent windows use the same recorded data as the longer native history views.
enum FleetRecentRange: String, CaseIterable, Identifiable {
    case oneMinute = "1m"
    case fifteenMinutes = "15m"
    case hour = "1h"
    case day = "24h"

    var id: String { rawValue }
    var identifier: String {
        switch self {
        case .oneMinute: "oneMinute"
        case .fifteenMinutes: "fifteenMinutes"
        case .hour: "hour"
        case .day: "daily"
        }
    }
    var interval: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fifteenMinutes: 15 * 60
        case .hour: 60 * 60
        case .day: 24 * 60 * 60
        }
    }
    var summaryLabel: String {
        switch self {
        case .oneMinute: "1-minute average"
        case .fifteenMinutes: "15-minute average"
        case .hour: "Hourly average"
        case .day: "Daily average"
        }
    }
}

/// Reads existing local telemetry only. This component never contacts or changes a miner.
enum FleetHistorySource {
    static func mergedPoints(stored: [HashratePoint], current: [HashratePoint], since: Date, until: Date) -> [HashratePoint] {
        // Fast path: SQLite returns stored readings ORDER BY timestamp and current history is
        // appended chronologically, so both are normally already sorted. A linear two-way merge
        // then produces exactly the same result as the dictionary + sort below, without hashing
        // and sorting the whole stored window again on every live update of the chart.
        if let storedKeys = sortedCollapsed(stored, since: since, until: until),
           let currentKeys = sortedCollapsed(current, since: since, until: until) {
            return mergeSorted(stored: storedKeys, current: currentKeys)
        }
        var readings: [Int: (point: HashratePoint, source: Int)] = [:]
        // SQLite stores whole-second timestamps. A current observation replaces its saved
        // counterpart at that precision, while retaining the actual current timestamp.
        // Resolve collisions before sorting. Sorting both complete inputs first made every
        // range-picker update sort hundreds of thousands of readings that share second keys.
        for (priority, source) in [stored, current].enumerated() {
            for point in source {
                guard point.value.isFinite, point.value >= 0,
                      point.date >= since, point.date <= until else { continue }
                let seconds = point.date.timeIntervalSince1970
                guard seconds.isFinite, seconds >= Double(Int.min), seconds < Double(Int.max) else { continue }
                let key = Int(seconds)
                if let previous = readings[key], previous.source == priority,
                   previous.point.date > point.date { continue }
                // Within one source, the latest timestamp wins. Equal timestamps retain the
                // last input, matching the original stable sort. Current always beats stored,
                // even when its timestamp is earlier within the same whole second.
                readings[key] = (point, priority)
            }
        }
        // Truncation to whole seconds is monotonic, including before the Unix epoch.
        return readings.keys.sorted().compactMap { readings[$0]?.point }
    }

    /// Valid, bounded points of one source keyed by whole second, with each second collapsed to
    /// the reading the general path would keep (latest timestamp; on a tie, the last input).
    /// Returns nil when the source is not in chronological order, so the caller falls back.
    private static func sortedCollapsed(
        _ source: [HashratePoint], since: Date, until: Date
    ) -> [(key: Int, point: HashratePoint)]? {
        var result: [(key: Int, point: HashratePoint)] = []
        var previousDate: Date?
        for point in source {
            let seconds = point.date.timeIntervalSince1970
            if seconds.isFinite {
                if let previousDate, point.date < previousDate { return nil }
                previousDate = point.date
            }
            guard point.value.isFinite, point.value >= 0,
                  point.date >= since, point.date <= until,
                  seconds.isFinite, seconds >= Double(Int.min), seconds < Double(Int.max) else { continue }
            let key = Int(seconds)
            // Sorted input keeps equal whole-second keys adjacent. The later element has the
            // later (or equal, and later-input) timestamp, which is exactly the one to keep.
            if let last = result.last, last.key == key {
                result[result.count - 1] = (key, point)
            } else {
                result.append((key, point))
            }
        }
        return result
    }

    /// Two-way merge of key-sorted, key-unique sources. Current always wins a shared second.
    private static func mergeSorted(
        stored: [(key: Int, point: HashratePoint)], current: [(key: Int, point: HashratePoint)]
    ) -> [HashratePoint] {
        var merged: [HashratePoint] = []
        merged.reserveCapacity(stored.count + current.count)
        var i = 0, j = 0
        while i < stored.count, j < current.count {
            if stored[i].key < current[j].key {
                merged.append(stored[i].point); i += 1
            } else if current[j].key < stored[i].key {
                merged.append(current[j].point); j += 1
            } else {
                merged.append(current[j].point); i += 1; j += 1
            }
        }
        while i < stored.count { merged.append(stored[i].point); i += 1 }
        while j < current.count { merged.append(current[j].point); j += 1 }
        return merged
    }

    /// A cached range remains exact until an input enters the window or ages out of it.
    /// Include shadowed readings too, since an expiring current point can reveal a stored one.
    static func recentRangeExpiration(sources: [[HashratePoint]], now: Date) -> Date {
        let since = now.addingTimeInterval(-FleetRecentRange.day.interval)
        var expiration = Date.distantFuture
        for source in sources {
            for point in source {
                let seconds = point.date.timeIntervalSince1970
                guard point.value.isFinite, point.value >= 0,
                      seconds.isFinite, seconds >= Double(Int.min), seconds < Double(Int.max),
                      point.date >= since else { continue }
                let boundary = point.date > now
                    ? point.date
                    : point.date.addingTimeInterval(FleetRecentRange.day.interval)
                expiration = min(expiration, boundary)
            }
        }
        return expiration
    }

    static func load(
        devices: [MinerDevice], since: Date, until: Date, database: MinerTelemetryDatabase
    ) async -> [UUID: [HashratePoint]] {
        var result: [UUID: [HashratePoint]] = [:]
        for device in devices {
            guard !Task.isCancelled else { return [:] }
            let readings = await database.getHashrateReadings(minerId: device.id.uuidString, since: since, until: until)
            guard !Task.isCancelled else { return [:] }
            result[device.id] = readings.map { HashratePoint(date: $0.timestamp, value: $0.hashrate) }
        }
        return result
    }
}

struct FleetHistoryLoadIdentity: Equatable {
    let window: HistoryWindow
    let devices: [UUID]
}
