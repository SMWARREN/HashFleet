import Foundation
import HashFleetCore

enum FleetHistoryDisplay: String, CaseIterable {
    case fleet
    case miners

    var title: String { self == .fleet ? "Fleet total" : "Individual miners" }
}

/// Presentation-only scoping. Stored rates remain GH/s, including normalized XMRig H/s.
/// CPU host rates are never added to SHA-256 readings or plotted on their axis.
enum FleetHistoryKind: String, CaseIterable, Identifiable {
    case sha256
    case cpu

    var id: String { rawValue }
    var title: String { self == .sha256 ? "SHA-256" : "CPU · XMRig" }
    var deviceKind: MinerDevice.Kind { self == .sha256 ? .espMiner : .xmrig }

    static func available(in devices: [MinerDevice]) -> [Self] {
        allCases.filter { kind in devices.contains { $0.kind == kind.deviceKind } }
    }

    func devices(in devices: [MinerDevice]) -> [MinerDevice] {
        devices.filter { $0.kind == deviceKind }
    }

    func totals(devices: [MinerDevice], snapshots: [UUID: MinerSnapshot]) -> FleetTotals {
        let online = self.devices(in: devices).compactMap { snapshots[$0.id] }
            .filter { $0.info != nil && $0.error == nil && !$0.isReconnecting }
        return FleetTotals(snapshots: online)
    }
}

struct FleetHistorySegment: Identifiable {
    let id: Int
    let points: [HashratePoint]
}

/// One bounded rendering payload. Full-resolution histories remain the source for inspection
/// and storage. Segment before sampling so downsampling never invents a recording gap.
struct FleetHistoryChartSeries: Identifiable {
    let history: MinerHistorySeries
    let segments: [FleetHistorySegment]
    var id: UUID { history.id }

    init(history: MinerHistorySeries, segments: [FleetHistorySegment]? = nil, maximumCount: Int) {
        self.segments = FleetHistoryPresentation.sampledSegments(
            segments ?? FleetHistoryPresentation.segments(history.points), maximumCount: maximumCount
        )
        self.history = MinerHistorySeries(
            id: history.id, name: history.name, points: self.segments.flatMap(\.points)
        )
    }
}

enum FleetHistoryPresentation {
    /// Keep the dashboard trend responsive while retaining the full-resolution series for detail
    /// screens, selection validation, and stored-history calculations.
    static let dashboardChartPointBudget = 48
    static let detailChartPointBudget = 180

    /// A conservative rendering boundary, not a promise of continuous sampling below this gap.
    static let maximumConnectedGap: TimeInterval = 5 * 60

    static func boundedPoints(_ points: [HashratePoint], since: Date, until: Date) -> [HashratePoint] {
        points.filter { $0.value.isFinite && $0.value >= 0 && $0.date >= since && $0.date <= until }
            .sorted { $0.date < $1.date }
    }

    /// Separate mark series prevent lines (and area fills) spanning missing recording intervals.
    static func segments(_ points: [HashratePoint]) -> [FleetHistorySegment] {
        var groups: [[HashratePoint]] = []
        for point in points.sorted(by: { $0.date < $1.date }) {
            guard point.value.isFinite, point.value >= 0 else { continue }
            if let last = groups.last?.last,
               point.date.timeIntervalSince(last.date) <= maximumConnectedGap {
                groups[groups.count - 1].append(point)
            } else {
                groups.append([point])
            }
        }
        return groups.enumerated().map { FleetHistorySegment(id: $0.offset, points: $0.element) }
    }

    /// Samples an already sorted series for a compact chart while retaining local extrema. The
    /// first and last points are retained when the budget allows both, so the trend stays anchored to the same
    /// time window. Keeping the minimum and maximum in each bucket prevents a short-lived recorded
    /// jump from disappearing when the dashboard budget is smaller than the source history. The
    /// source series is never mutated, and short series are returned unchanged.
    static func sampledPoints(_ points: [HashratePoint], maximumCount: Int) -> [HashratePoint] {
        guard maximumCount > 0 else { return [] }
        guard points.count > maximumCount else { return points }
        if maximumCount == 1 { return [points[points.count - 1]] }
        if maximumCount == 2 { return [points[0], points[points.count - 1]] }

        // With only three slots, preserve the established evenly spaced contract. The extrema
        // envelope needs at least one interior bucket plus both endpoints.
        if maximumCount == 3 {
            let lastIndex = points.count - 1
            return (0..<maximumCount).map { index in
                let position = Double(index) / Double(maximumCount - 1)
                let sourceIndex = Int((position * Double(lastIndex)).rounded())
                return points[sourceIndex]
            }
        }

        let interiorCount = points.count - 2
        let bucketCount = max(1, (maximumCount - 2) / 2)
        var sampled = [points[0]]
        sampled.reserveCapacity(maximumCount)

        for bucket in 0..<bucketCount {
            let start = 1 + (bucket * interiorCount / bucketCount)
            let end = 1 + ((bucket + 1) * interiorCount / bucketCount)
            guard start < end else { continue }

            var minimumIndex = start
            var maximumIndex = start
            if start + 1 < end {
                for index in (start + 1)..<end {
                    if points[index].value < points[minimumIndex].value {
                        minimumIndex = index
                    }
                    if points[index].value > points[maximumIndex].value {
                        maximumIndex = index
                    }
                }
            }

            if minimumIndex == maximumIndex {
                sampled.append(points[minimumIndex])
            } else if minimumIndex < maximumIndex {
                sampled.append(points[minimumIndex])
                sampled.append(points[maximumIndex])
            } else {
                sampled.append(points[maximumIndex])
                sampled.append(points[minimumIndex])
            }
        }

        sampled.append(points[points.count - 1])
        return sampled
    }

    /// Apply one budget across all chronological recording segments, not a new budget for each
    /// segment. Match the sampled subsequence back to its original segments, retaining their IDs
    /// and never connecting points across a real recording interruption. Sparse segments can
    /// disappear at compact resolution, but full-resolution selection and stored data are intact.
    static func sampledSegments(
        _ segments: [FleetHistorySegment], maximumCount: Int
    ) -> [FleetHistorySegment] {
        let sampled = sampledPoints(segments.flatMap(\.points), maximumCount: maximumCount)
        guard !sampled.isEmpty else { return [] }
        var cursor = 0
        return segments.compactMap { segment in
            var points: [HashratePoint] = []
            for point in segment.points {
                if cursor < sampled.count, point.date == sampled[cursor].date,
                   point.value == sampled[cursor].value {
                    points.append(point)
                    cursor += 1
                }
            }
            return points.isEmpty ? nil : FleetHistorySegment(id: segment.id, points: points)
        }
    }

    /// Returns a nonnegative, padded domain around values that are actually plotted. A focused
    /// domain keeps small recorded changes visible without altering the values or inventing a zero
    /// baseline for a positive-rate trend.
    static func focusedYDomain(for values: [Double]) -> ClosedRange<Double>? {
        let validValues = values.filter { $0.isFinite && $0 >= 0 }
        guard let minimum = validValues.min(), let maximum = validValues.max() else { return nil }

        let spread = maximum - minimum
        let padding = spread > 0
            ? max(spread * 0.06, max(abs(minimum), abs(maximum), 1) * 0.002)
            : max(abs(maximum) * 0.02, 0.01)
        let lower = max(0, minimum - padding)
        let upper = maximum + padding
        return lower...upper
    }

    /// Keeps the recent-range picker honest while a new miner is accumulating history. The one
    /// minute view is always available as the first-reading view. Longer windows appear only after
    /// the recorded points span the requested duration. Coverage is anchored to the newest saved
    /// reading instead of wall-clock now, so a short monitoring gap does not turn a useful saved
    /// chart into an empty one-minute view.
    static func availableRecentRanges(
        for points: [HashratePoint], now: Date, minimumCoverage: TimeInterval = 0
    ) -> [FleetRecentRange] {
        let validDates = points.lazy
            .filter { $0.value.isFinite && $0.value >= 0 && $0.date <= now }
            .map(\.date)
        guard let latestDate = validDates.max() else { return [.oneMinute] }

        var ranges: [FleetRecentRange] = [.oneMinute]
        for range in FleetRecentRange.allCases.dropFirst() {
            let cutoff = latestDate.addingTimeInterval(-range.interval)
            guard let first = validDates.filter({ $0 >= cutoff }).min(),
                  latestDate.timeIntervalSince(first) >= max(range.interval, minimumCoverage) else {
                break
            }
            ranges.append(range)
        }
        return ranges
    }

    /// This is a mean of individual recorded samples, not a fleet-total or time-weighted average.
    static func meanReading(in histories: [MinerHistorySeries]) -> Double? {
        var total = 0.0
        var count = 0
        for value in histories.lazy.flatMap(\.points).map(\.value)
            where value.isFinite && value >= 0 {
            total += value
            count += 1
        }
        guard count > 0 else { return nil }
        return total / Double(count)
    }
}
