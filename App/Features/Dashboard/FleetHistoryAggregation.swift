import Foundation
import HashFleetCore

/// Complete fleet totals formed only from recorded samples within one bounded alignment interval.
/// A missing miner or rejected alignment breaks the line, rather than inventing a zero or extrapolating across a missing interval.
enum FleetHistoryAggregation {
    static let alignmentTolerance: TimeInterval = 30

    static func segments(
        histories: [MinerHistorySeries], expectedIDs: [UUID], tolerance: TimeInterval = alignmentTolerance
    ) -> [FleetHistorySegment] {
        guard !expectedIDs.isEmpty, Set(expectedIDs).count == expectedIDs.count,
              tolerance.isFinite, tolerance >= 0 else { return [] }
        let grouped = Dictionary(grouping: histories, by: \.id)
        let points = grouped.mapValues { histories in
            histories.lazy.flatMap(\.points).filter { $0.value.isFinite && $0.value >= 0 }
                .sorted { $0.date < $1.date }
        }
        guard expectedIDs.allSatisfy({ !(points[$0] ?? []).isEmpty }),
              let reference = points[expectedIDs[0]] else { return [] }
        var groups: [[HashratePoint]] = []
        var previousDates: [UUID: Date] = [:]
        var interrupted = true
        for anchor in reference {
            var matched: [UUID: HashratePoint] = [:]
            for id in expectedIDs {
                if let reading = nearest(to: anchor.date, in: points[id] ?? [], tolerance: tolerance) {
                    matched[id] = reading
                }
            }
            let dates = matched.values.map(\.date)
            guard matched.count == expectedIDs.count, let first = dates.min(), let last = dates.max(),
                  last.timeIntervalSince(first) <= tolerance else {
                interrupted = true
                continue
            }
            let total = matched.values.reduce(0) { $0 + $1.value }
            guard total.isFinite else {
                interrupted = true
                continue
            }
            let sourceGap = matched.contains { id, reading in
                previousDates[id].map {
                    reading.date.timeIntervalSince($0) > FleetHistoryPresentation.maximumConnectedGap
                } ?? false
            }
            let reading = HashratePoint(date: last, value: total)
            if interrupted || sourceGap || groups.isEmpty {
                groups.append([reading])
            } else if groups[groups.count - 1].last?.date == last {
                // A repeated alignment timestamp uses the latest recorded reference sample, never duplicate marks.
                groups[groups.count - 1][groups[groups.count - 1].count - 1] = reading
            } else {
                groups[groups.count - 1].append(reading)
            }
            previousDates = matched.mapValues(\.date)
            interrupted = false
        }
        return groups.enumerated().map { FleetHistorySegment(id: $0.offset, points: $0.element) }
    }

    private static func nearest(to date: Date, in points: [HashratePoint], tolerance: TimeInterval) -> HashratePoint? {
        guard !points.isEmpty else { return nil }
        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if points[middle].date < date { lower = middle + 1 } else { upper = middle }
        }
        let candidates = [lower - 1, lower].filter { points.indices.contains($0) }.map { points[$0] }
        let closest = candidates.min {
            let left = abs($0.date.timeIntervalSince(date))
            let right = abs($1.date.timeIntervalSince(date))
            return left == right ? $0.date < $1.date : left < right
        }
        guard let closest, abs(closest.date.timeIntervalSince(date)) <= tolerance else { return nil }
        return closest
    }
}
