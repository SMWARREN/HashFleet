import Foundation
import Testing
import Accessibility
@testable import HashFleet

@MainActor
struct FleetChartSelectionTests {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func emptySeriesListReturnsNil() {
        let target = baseDate
        let result = FleetChartSelection.resolve(
            at: target,
            in: [],
            tolerance: 1800
        )
        #expect(result == nil)
    }

    @Test
    func seriesWithEmptyPointsReturnsNil() {
        let series = MinerHistorySeries(name: "Rig 1", points: [])
        let result = FleetChartSelection.resolve(
            at: baseDate,
            in: [series],
            tolerance: 1800
        )
        #expect(result == nil)
    }

    @Test
    func seriesWithOnlyInvalidPointsReturnsNil() {
        let points = [
            HashratePoint(date: baseDate, value: Double.nan),
            HashratePoint(date: baseDate.addingTimeInterval(10), value: -50.0),
            HashratePoint(date: baseDate.addingTimeInterval(20), value: Double.infinity)
        ]
        let series = MinerHistorySeries(name: "Invalid Miner", points: points)
        let result = FleetChartSelection.resolve(
            at: baseDate,
            in: [series],
            tolerance: 1800
        )
        #expect(result == nil)
    }

    @Test
    func boundedExplicitToleranceRejectsOutOfRange() {
        let point = HashratePoint(date: baseDate, value: 1200.0)
        let series = MinerHistorySeries(name: "Rig 1", points: [point])
        // Target is 40 minutes away, tolerance is 30 minutes (1800s)
        let distantTarget = baseDate.addingTimeInterval(2400)
        let result = FleetChartSelection.resolve(
            at: distantTarget,
            in: [series],
            tolerance: 1800
        )
        #expect(result == nil)
    }

    @Test
    func exactTimestampMatchResolvesPoint() {
        let point = HashratePoint(date: baseDate, value: 1200.0)
        let series = MinerHistorySeries(name: "Rig 1", points: [point])
        let result = FleetChartSelection.resolve(
            at: baseDate,
            in: [series],
            tolerance: 1800
        )
        #expect(result != nil)
        #expect(result?.selectedDate == baseDate)
        #expect(result?.totalRate == 1200.0)
        #expect(result?.seriesValues.count == 1)
        #expect(result?.seriesValues.first?.value == 1200.0)
        #expect(result?.seriesValues.first?.isMissing == false)
    }

    @Test
    func nearestValidPointResolvesToClosestSample() {
        let pt1 = HashratePoint(date: baseDate, value: 1000.0)
        let pt2 = HashratePoint(date: baseDate.addingTimeInterval(100), value: 1500.0)
        let series = MinerHistorySeries(name: "Rig 1", points: [pt1, pt2])

        // Closer to pt1 (20s away vs 80s away)
        let result1 = FleetChartSelection.resolve(
            at: baseDate.addingTimeInterval(20),
            in: [series],
            tolerance: 1800
        )
        #expect(result1?.selectedDate == baseDate)
        #expect(result1?.totalRate == 1000.0)

        // Closer to pt2 (20s away vs 80s away)
        let result2 = FleetChartSelection.resolve(
            at: baseDate.addingTimeInterval(80),
            in: [series],
            tolerance: 1800
        )
        #expect(result2?.selectedDate == baseDate.addingTimeInterval(100))
        #expect(result2?.totalRate == 1500.0)
    }

    @Test
    func unsortedInputPointsHandledDeterministically() {
        let pt1 = HashratePoint(date: baseDate.addingTimeInterval(30), value: 1300.0)
        let pt2 = HashratePoint(date: baseDate, value: 1000.0)
        let pt3 = HashratePoint(date: baseDate.addingTimeInterval(60), value: 1600.0)
        let pt4 = HashratePoint(date: baseDate.addingTimeInterval(15), value: 1150.0)
        // Intentionally unsorted order
        let series = MinerHistorySeries(name: "Rig 1", points: [pt1, pt2, pt3, pt4])

        let result = FleetChartSelection.resolve(
            at: baseDate.addingTimeInterval(16),
            in: [series],
            tolerance: 1800
        )
        #expect(result?.selectedDate == baseDate.addingTimeInterval(15))
        #expect(result?.totalRate == 1150.0)
    }

    @Test
    func multiSeriesClusteringAndAggregateRate() {
        let miner1 = MinerHistorySeries(
            id: UUID(),
            name: "Alpha",
            points: [HashratePoint(date: baseDate, value: 1200.0)]
        )
        let miner2 = MinerHistorySeries(
            id: UUID(),
            name: "Beta",
            // Reported 5 seconds later in same polling sweep
            points: [HashratePoint(date: baseDate.addingTimeInterval(5), value: 800.0)]
        )

        let result = FleetChartSelection.resolve(
            at: baseDate.addingTimeInterval(2),
            in: [miner1, miner2],
            tolerance: 1800,
            clusterTolerance: 30
        )

        #expect(result != nil)
        #expect(result?.selectedDate == baseDate)
        #expect(result?.seriesValues.count == 2)
        #expect(result?.seriesValues[0].value == 1200.0)
        #expect(result?.seriesValues[0].isMissing == false)
        #expect(result?.seriesValues[1].value == 800.0)
        #expect(result?.seriesValues[1].isMissing == false)
        #expect(result?.totalRate == 2000.0)
        #expect(result?.formattedTotalRate == "2.00 TH/s")
    }

    @Test
    func multiSeriesMissingValueDoesNotInventContinuity() {
        let miner1 = MinerHistorySeries(
            id: UUID(),
            name: "Alpha",
            points: [HashratePoint(date: baseDate, value: 1500.0)]
        )
        let miner2 = MinerHistorySeries(
            id: UUID(),
            name: "Beta",
            // Only reported 2 hours ago, was offline during this reading
            points: [HashratePoint(date: baseDate.addingTimeInterval(-7200), value: 900.0)]
        )

        let result = FleetChartSelection.resolve(
            at: baseDate,
            in: [miner1, miner2],
            tolerance: 1800,
            clusterTolerance: 60
        )

        #expect(result != nil)
        #expect(result?.seriesValues.count == 2)

        let val1 = result?.seriesValues.first(where: { $0.name == "Alpha" })
        #expect(val1?.value == 1500.0)
        #expect(val1?.isMissing == false)
        #expect(val1?.formattedRate == "1.50 TH/s")

        let val2 = result?.seriesValues.first(where: { $0.name == "Beta" })
        #expect(val2?.value == nil)
        #expect(val2?.isMissing == true)
        #expect(val2?.formattedRate == "—")
        #expect(val2?.accessibilityText.contains("offline or no reading") == true)

        // Total rate reflects only reporting miners
        #expect(result?.totalRate == 1500.0)
    }

    @Test
    func datasetUpdateRemovesPointDeselection() {
        let pt1 = HashratePoint(date: baseDate, value: 1000.0)
        let series = MinerHistorySeries(name: "Rig 1", points: [pt1])

        let selection = FleetChartSelection.resolve(
            at: baseDate,
            in: [series],
            tolerance: 1800
        )
        #expect(selection != nil)

        // Verify initial selection is valid
        #expect(FleetChartSelection.isSelectionValid(at: selection!.selectedDate, in: [series], tolerance: 30))
        #expect(FleetChartSelection.validateOrDeselect(selection, in: [series], tolerance: 30) != nil)

        // Dataset pruned: old point removed, only newer points remain
        let prunedSeries = MinerHistorySeries(
            name: "Rig 1",
            points: [HashratePoint(date: baseDate.addingTimeInterval(3600), value: 1100.0)]
        )

        #expect(!FleetChartSelection.isSelectionValid(at: selection!.selectedDate, in: [prunedSeries], tolerance: 30))
        #expect(FleetChartSelection.validateOrDeselect(selection, in: [prunedSeries], tolerance: 30) == nil)

        // Empty series also deselects
        #expect(!FleetChartSelection.isSelectionValid(at: selection!.selectedDate, in: [], tolerance: 30))
        #expect(FleetChartSelection.validateOrDeselect(selection, in: [], tolerance: 30) == nil)
    }
}
