import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@MainActor
@Suite("Recorded fleet aggregation")
struct FleetHistoryAggregationTests {
    private let base = Date(timeIntervalSince1970: 10_000)

    private func history(_ id: UUID, _ readings: [(TimeInterval, Double)]) -> MinerHistorySeries {
        MinerHistorySeries(id: id, name: "Fixture", points: readings.map {
            HashratePoint(date: base.addingTimeInterval($0.0), value: $0.1)
        })
    }

    @Test("Empty inputs, duplicate identities and invalid tolerance produce no invented totals")
    func edgeCases() {
        let id = UUID()
        let histories = [history(id, [(0, 1_000)])]
        #expect(FleetHistoryAggregation.segments(histories: [], expectedIDs: [id]).isEmpty)
        #expect(FleetHistoryAggregation.segments(histories: histories, expectedIDs: []).isEmpty)
        #expect(FleetHistoryAggregation.segments(histories: histories, expectedIDs: [id, id]).isEmpty)
        for tolerance in [-1.0, Double.infinity, Double.nan] {
            #expect(FleetHistoryAggregation.segments(histories: histories, expectedIDs: [id], tolerance: tolerance).isEmpty)
        }
    }

    @Test("A missing miner is not substituted with zero")
    func missingMinersNotZero() {
        let first = UUID()
        let missing = UUID()
        let unrelated = UUID()
        let histories = [history(first, [(0, 1_000)]), history(unrelated, [(0, 500)])]
        #expect(FleetHistoryAggregation.segments(histories: histories, expectedIDs: [first, missing]).isEmpty)
    }

    @Test("Unsorted finite readings are summed, not averaged, at an actual matched timestamp")
    func alignmentAndFiltering() throws {
        let first = UUID()
        let second = UUID()
        let histories = [history(first, [(0, 500), (-20, 0), (5, -100), (6, .infinity), (7, .nan)]),
                         history(second, [(10, 2)])]
        let segments = FleetHistoryAggregation.segments(histories: histories, expectedIDs: [first, second])
        #expect(segments.count == 1)
        let segment = try #require(segments.first)
        #expect(segment.points.count == 1)
        let point = try #require(segment.points.first)
        #expect(point.value == 502)
        #expect(point.date == base.addingTimeInterval(10))
    }

    @Test("A genuine reported zero is retained at an inclusive alignment boundary")
    func realZeroAndBoundary() throws {
        let first = UUID()
        let second = UUID()
        let histories = [history(first, [(0, 0)]), history(second, [(30, 50)])]
        let segments = FleetHistoryAggregation.segments(histories: histories, expectedIDs: [first, second])
        let point = try #require(segments.first?.points.first)
        #expect(point.value == 50)
        #expect(point.date == base.addingTimeInterval(30))
        #expect(FleetHistoryAggregation.segments(histories: histories, expectedIDs: [first, second], tolerance: 29.999).isEmpty)
    }

    @Test("Alignment bounds the whole fleet, not twice the anchor tolerance")
    func totalAlignmentSpreadIsBounded() {
        let anchor = UUID()
        let earlier = UUID()
        let later = UUID()
        let histories = [history(anchor, [(0, 100)]), history(earlier, [(-30, 100)]), history(later, [(30, 100)])]
        #expect(FleetHistoryAggregation.segments(histories: histories, expectedIDs: [anchor, earlier, later]).isEmpty)
    }

    @Test("Any source gap over five minutes creates separate line segments")
    func sourceGaps() throws {
        let first = UUID()
        let second = UUID()
        let histories = [history(first, [(0, 100), (301, 100)]), history(second, [(5, 100), (305, 100)])]
        let segments = FleetHistoryAggregation.segments(histories: histories, expectedIDs: [first, second])
        #expect(segments.count == 2)
        let earlier = try #require(segments.first)
        let later = try #require(segments.last)
        #expect(earlier.points.count == 1)
        #expect(later.points.count == 1)
        #expect(earlier.points.first?.date == base.addingTimeInterval(5))
        #expect(later.points.first?.date == base.addingTimeInterval(305))
    }

    @Test("A rejected intermediate alignment interrupts the chart even with short source gaps")
    func rejectedIntermediateAlignment() throws {
        let first = UUID()
        let second = UUID()
        let histories = [history(first, [(0, 100), (150, 100), (300, 100)]), history(second, [(5, 50), (295, 50)])]
        let segments = FleetHistoryAggregation.segments(histories: histories, expectedIDs: [first, second])
        #expect(segments.count == 2)
        let earlier = try #require(segments.first)
        let later = try #require(segments.last)
        #expect(earlier.points.count == 1)
        #expect(later.points.count == 1)
        #expect(earlier.points.first?.date == base.addingTimeInterval(5))
        #expect(later.points.first?.date == base.addingTimeInterval(300))
    }

    @Test("Repeated aggregate timestamps keep the latest actual reference sample without duplicate marks")
    func repeatedTimestampsCollapse() throws {
        let first = UUID()
        let second = UUID()
        let segments = FleetHistoryAggregation.segments(
            histories: [history(first, [(0, 100), (5, 200)]), history(second, [(10, 50)])], expectedIDs: [first, second]
        )
        #expect(segments.count == 1)
        let segment = try #require(segments.first)
        #expect(segment.points.count == 1)
        let point = try #require(segment.points.first)
        #expect(point.date == base.addingTimeInterval(10))
        #expect(point.value == 250)
    }

    @Test("Equidistant readings choose the earlier actual reading deterministically")
    func nearestTiePicksEarlier() throws {
        let first = UUID()
        let second = UUID()
        let segments = FleetHistoryAggregation.segments(
            histories: [history(first, [(10, 100)]), history(second, [(0, 50), (20, 25)])], expectedIDs: [first, second]
        )
        let point = try #require(segments.first?.points.first)
        #expect(point.value == 150)
        #expect(point.date == base.addingTimeInterval(10))
    }

    @Test("Overflow is rejected rather than plotted as an infinite fleet rate")
    func overflowSumsRejected() {
        let first = UUID()
        let second = UUID()
        let histories = [history(first, [(0, .greatestFiniteMagnitude)]), history(second, [(0, .greatestFiniteMagnitude)])]
        #expect(FleetHistoryAggregation.segments(histories: histories, expectedIDs: [first, second]).isEmpty)
    }

    @Test("Only expected ASIC identities contribute, with CPU data excluded")
    func exclusionUsingExpectedIDs() throws {
        let first = UUID()
        let second = UUID()
        let cpu = UUID()
        let histories = [history(first, [(0, 600)]), history(second, [(0, 650)]), history(cpu, [(0, 0.0000015)])]
        let segments = FleetHistoryAggregation.segments(histories: histories, expectedIDs: [first, second])
        let point = try #require(segments.first?.points.first)
        #expect(point.value == 1_250)
    }
}
