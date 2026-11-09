import Foundation
import Testing
import Accessibility
@testable import HashFleet

extension FleetChartSelectionTests {
    @Test
    func formattingGHsAndTHsValues() {
        let ghPoint = HashratePoint(date: baseDate, value: 750.0)
        let ghSeries = MinerHistorySeries(name: "Solo", points: [ghPoint])
        let ghSelection = FleetChartSelection.resolve(at: baseDate, in: [ghSeries], tolerance: 60)
        #expect(ghSelection?.formattedTotalRate == "750 GH/s")
        #expect(ghSelection?.seriesValues.first?.formattedRate == "750 GH/s")

        let thPoint = HashratePoint(date: baseDate, value: 3450.0)
        let thSeries = MinerHistorySeries(name: "Fleet", points: [thPoint])
        let thSelection = FleetChartSelection.resolve(at: baseDate, in: [thSeries], tolerance: 60)
        #expect(thSelection?.formattedTotalRate == "3.45 TH/s")
        #expect(thSelection?.seriesValues.first?.formattedRate == "3.45 TH/s")
    }

    @Test
    func chartDescriptorConvertsNumericValuesToMatchUnitTitle() throws {
        // High rate fleet (TH/s scale)
        let thPt1 = HashratePoint(date: baseDate, value: 1200.0) // 1.2 TH/s
        let thPt2 = HashratePoint(date: baseDate.addingTimeInterval(60), value: 2400.0) // 2.4 TH/s
        let thSeries = MinerHistorySeries(name: "BigMiner", points: [thPt1, thPt2])

        let thProvider = FleetAXChartDescriptorProvider(
            series: [thSeries],
            windowHeading: "24h",
            isDemo: false
        )
        let thDescriptor = thProvider.makeChartDescriptor()
        #expect(thDescriptor.yAxis?.title == "Hashrate in TH/s")
        let thPoints = thDescriptor.series.first?.dataPoints ?? []
        try #require(thPoints.count == 2)
        #expect(thPoints[0].yValue?.__number == 1.2)
        #expect(thPoints[1].yValue?.__number == 2.4)
        #expect(thPoints[0].label?.contains("1.20 TH/s") == true)
        #expect(thPoints[1].label?.contains("2.40 TH/s") == true)

        // Low rate fleet (GH/s scale)
        let ghPt1 = HashratePoint(date: baseDate, value: 450.0)
        let ghPt2 = HashratePoint(date: baseDate.addingTimeInterval(60), value: 750.0)
        let ghSeries = MinerHistorySeries(name: "SmallMiner", points: [ghPt1, ghPt2])

        let ghProvider = FleetAXChartDescriptorProvider(
            series: [ghSeries],
            windowHeading: "24h",
            isDemo: false
        )
        let ghDescriptor = ghProvider.makeChartDescriptor()
        #expect(ghDescriptor.yAxis?.title == "Hashrate in GH/s")
        let ghPoints = ghDescriptor.series.first?.dataPoints ?? []
        try #require(ghPoints.count == 2)
        #expect(ghPoints[0].yValue?.__number == 450.0)
        #expect(ghPoints[1].yValue?.__number == 750.0)
        #expect(ghPoints[0].label?.contains("450 GH/s") == true)
        #expect(ghPoints[1].label?.contains("750 GH/s") == true)
    }

    @Test
    func tooltipsIndependentlyAutoScaleAcrossMixedFleet() {
        let pt1 = HashratePoint(date: baseDate, value: 750.0) // 750 GH/s
        let pt2 = HashratePoint(date: baseDate, value: 2500.0) // 2.50 TH/s
        let s1 = MinerHistorySeries(id: UUID(), name: "Gamma", points: [pt1])
        let s2 = MinerHistorySeries(id: UUID(), name: "Naja", points: [pt2])

        let selection = FleetChartSelection.resolve(at: baseDate, in: [s1, s2], tolerance: 60)
        #expect(selection != nil)
        // Gamma retains GH/s independently
        #expect(selection?.seriesValues[0].formattedRate == "750 GH/s")
        #expect(selection?.seriesValues[0].accessibilityText.contains("750 GH/s") == true)
        // Naja auto-scales to TH/s independently
        #expect(selection?.seriesValues[1].formattedRate == "2.50 TH/s")
        #expect(selection?.seriesValues[1].accessibilityText.contains("2.50 TH/s") == true)
        // Total auto-scales to TH/s: 750 + 2500 = 3250 GH/s = 3.25 TH/s
        #expect(selection?.formattedTotalRate == "3.25 TH/s")
        #expect(selection?.accessibleSummary.contains("3.25 TH/s") == true)
    }

    @Test
    func accessibilityDescriptorProducesValidStructure() {
        let pt1 = HashratePoint(date: baseDate, value: 1200.0)
        let pt2 = HashratePoint(date: baseDate.addingTimeInterval(60), value: 1350.0)
        let series = MinerHistorySeries(name: "Alpha", points: [pt1, pt2])

        let descriptorProvider = FleetAXChartDescriptorProvider(
            series: [series],
            windowHeading: "24h",
            isDemo: false
        )
        let descriptor = descriptorProvider.makeChartDescriptor()

        #expect(descriptor.title == "Fleet Hashrate History")
        #expect(descriptor.summary?.contains("1 miner(s)") == true)
        #expect(descriptor.summary?.contains("24h") == true)
        #expect(descriptor.series.count == 1)
        #expect(descriptor.series.first?.dataPoints.count == 2)
        #expect(descriptor.series.first?.name == "Alpha")
    }

    @Test
    func accessibilityDescriptorForDemoFleet() {
        let pt = HashratePoint(date: baseDate, value: 800.0)
        let series = MinerHistorySeries(name: "DemoMiner", points: [pt])

        let provider = FleetAXChartDescriptorProvider(
            series: [series],
            windowHeading: "7d",
            isDemo: true
        )
        let descriptor = provider.makeChartDescriptor()

        #expect(descriptor.title == "Simulated Hashrate History")
        #expect(descriptor.summary?.contains("Simulated") == true)
    }

    @Test
    func historyWindowConfigurations() {
        #expect(HistoryWindow.daily.heading == "24h")
        #expect(HistoryWindow.daily.summaryLabel == "Daily average")
        #expect(HistoryWindow.daily.interval == 86400)
        #expect(HistoryWindow.daily.selectionTolerance == 1800)

        #expect(HistoryWindow.weekly.heading == "7d")
        #expect(HistoryWindow.weekly.summaryLabel == "Weekly average")
        #expect(HistoryWindow.weekly.interval == 604800)
        #expect(HistoryWindow.weekly.selectionTolerance == 14400)

        #expect(HistoryWindow.monthly.heading == "30d")
        #expect(HistoryWindow.monthly.summaryLabel == "Monthly average")
        #expect(HistoryWindow.monthly.interval == 2592000)
        #expect(HistoryWindow.monthly.selectionTolerance == 86400)

        #expect(HistoryWindow.yearly.heading == "365d")
        #expect(HistoryWindow.yearly.summaryLabel == "Yearly average")
        #expect(HistoryWindow.yearly.interval == 31536000)
        #expect(HistoryWindow.yearly.selectionTolerance == 604800)
    }

    @Test
    func minerHistorySeriesEquatable() {
        let id = UUID()
        let pt1 = HashratePoint(date: baseDate, value: 500.0)
        let pt2 = HashratePoint(date: baseDate.addingTimeInterval(10), value: 600.0)

        let seriesA = MinerHistorySeries(id: id, name: "Miner", points: [pt1, pt2])
        let seriesB = MinerHistorySeries(id: id, name: "Miner", points: [pt1, pt2])
        let seriesC = MinerHistorySeries(id: UUID(), name: "Miner", points: [pt1, pt2])
        let seriesD = MinerHistorySeries(id: id, name: "Miner", points: [pt1])

        #expect(seriesA == seriesB)
        #expect(seriesA != seriesC)
        #expect(seriesA != seriesD)
    }

    @Test
    func cappedHistoryBufferRollChangesSignatureEvenWhenCountRemainsConstant() {
        let deviceID = UUID()
        // Fill a buffer with 360 points (10s intervals)
        let initialPoints = (0..<360).map {
            HashratePoint(date: baseDate.addingTimeInterval(Double($0) * 10), value: 1000.0 + Double($0))
        }
        let sig1 = MinerHistorySignature(
            id: deviceID,
            history: initialPoints,
            updatedAt: baseDate.addingTimeInterval(3590)
        )
        #expect(sig1.count == 360)
        #expect(sig1.firstDate == baseDate)
        #expect(sig1.lastDate == baseDate.addingTimeInterval(3590))

        // Simulate next poll appending point 361 and slicing suffix(360)
        let newPoint = HashratePoint(date: baseDate.addingTimeInterval(3600), value: 1360.0)
        let rolledPoints = Array((initialPoints + [newPoint]).suffix(360))
        let sig2 = MinerHistorySignature(
            id: deviceID,
            history: rolledPoints,
            updatedAt: baseDate.addingTimeInterval(3600)
        )

        #expect(rolledPoints.count == 360)
        #expect(sig2.count == 360)
        // Count did not change, but firstDate, lastDate, and updatedAt changed!
        #expect(sig1 != sig2)
        #expect(sig2.firstDate == baseDate.addingTimeInterval(10))
        #expect(sig2.lastDate == baseDate.addingTimeInterval(3600))
    }

    @Test
    func oldestPointPrunedFromCappedBufferTriggersDeselection() {
        let deviceID = UUID()
        let initialPoints = (0..<360).map {
            HashratePoint(date: baseDate.addingTimeInterval(Double($0) * 10), value: 1000.0)
        }
        let series = MinerHistorySeries(id: deviceID, name: "Rig 1", points: initialPoints)

        // User selects the oldest point (baseDate)
        let selection = FleetChartSelection.resolve(at: baseDate, in: [series], tolerance: 5)
        #expect(selection != nil)
        #expect(selection?.selectedDate == baseDate)
        #expect(FleetChartSelection.isSelectionValid(at: baseDate, in: [series], tolerance: 5))

        // Buffer rolls: point at baseDate is dropped, new point added at +3600s
        let newPoints = Array(
            (initialPoints + [HashratePoint(date: baseDate.addingTimeInterval(3600), value: 1000.0)]).suffix(360)
        )
        let rolledSeries = MinerHistorySeries(id: deviceID, name: "Rig 1", points: newPoints)

        // The old selected point (baseDate) is now gone from history
        #expect(!FleetChartSelection.isSelectionValid(at: baseDate, in: [rolledSeries], tolerance: 5))
        #expect(FleetChartSelection.validateOrDeselect(selection, in: [rolledSeries], tolerance: 5) == nil)
    }

    @Test
    func legendItemStateForMultiMinerFleet() {
        let id1 = UUID()
        let id2 = UUID()
        let sVal1 = FleetChartSelection.SeriesValue(
            id: id1,
            name: "Miner A",
            value: 1200.0,
            colorIndex: 0,
            isMissing: false
        )
        let sVal2 = FleetChartSelection.SeriesValue(
            id: id2,
            name: "Miner B",
            value: nil,
            colorIndex: 1,
            isMissing: true
        )

        let item1 = FleetChartLegendItem(
            id: id1,
            name: "Miner A",
            color: FleetChartPalette.color(for: 0),
            seriesValue: sVal1
        )
        let item2 = FleetChartLegendItem(
            id: id2,
            name: "Miner B",
            color: FleetChartPalette.color(for: 1),
            seriesValue: sVal2
        )
        let unselectedItem = FleetChartLegendItem(
            id: id1,
            name: "Miner A",
            color: FleetChartPalette.color(for: 0),
            seriesValue: nil
        )

        #expect(item1.formattedRate == "1.20 TH/s")
        #expect(item1.isMissing == false)
        #expect(item1.accessibleDescription.contains("1.20 TH/s"))

        #expect(item2.formattedRate == "—")
        #expect(item2.isMissing == true)
        #expect(item2.accessibleDescription.contains("offline or no reading"))

        #expect(unselectedItem.formattedRate == "")
        #expect(unselectedItem.isMissing == false)
        #expect(unselectedItem.accessibleDescription == "Miner A")
    }
}
