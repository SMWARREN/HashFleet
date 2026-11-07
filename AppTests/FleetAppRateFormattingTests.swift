import Foundation
import Testing
@testable import HashFleet
import HashFleetCore

@Suite("Fleet App Rate Formatting & Scaling Acceptance Tests")
struct FleetAppRateFormattingTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Diagnostics Formatting Consistency

    @Test
    func diagnosticsUsesSharedFormatterConsistently() {
        // Missing and invalid states remain "Not reported"
        #expect(MinerDiagnosticsModel.formatHashrate(nil) == "Not reported")
        #expect(MinerDiagnosticsModel.formatHashrate(-1.0) == "Not reported")
        #expect(MinerDiagnosticsModel.formatHashrate(.nan) == "Not reported")
        #expect(MinerDiagnosticsModel.formatHashrate(.infinity) == "Not reported")

        // Sub-TH rates use GH/s without decimals
        #expect(MinerDiagnosticsModel.formatHashrate(750.0) == "750 GH/s")
        #expect(MinerDiagnosticsModel.formatHashrate(999.0) == "999 GH/s")

        // TH rates scale to TH/s with 2 decimals
        #expect(MinerDiagnosticsModel.formatHashrate(1_000.0) == "1.00 TH/s")
        #expect(MinerDiagnosticsModel.formatHashrate(1_250.0) == "1.25 TH/s")
        #expect(MinerDiagnosticsModel.formatHashrate(2_500.0) == "2.50 TH/s")
    }

    // MARK: - Insights H/s Rate Formatting

    @Test
    func insightsFormatUsesHashesPerSecondSharedAPI() {
        // Missing and invalid states remain "Not reported"
        #expect(InsightsFormat.hashrate(nil) == "Not reported")
        #expect(InsightsFormat.hashrate(-50.0) == "Not reported")
        #expect(InsightsFormat.hashrate(.nan) == "Not reported")
        #expect(InsightsFormat.hashrate(.infinity) == "Not reported")

        // CPU rates in H/s and kH/s
        #expect(InsightsFormat.hashrate(500.0) == "500.00 H/s")
        #expect(InsightsFormat.hashrate(1_250.0) == "1.25 kH/s")
        #expect(InsightsFormat.hashrate(25_000.0) == "25.00 kH/s")

        // Network rates in TH/s
        #expect(InsightsFormat.hashrate(1.25e12) == "1.25 TH/s")
        #expect(InsightsFormat.hashrate(3.45e12) == "3.45 TH/s")
    }

    // MARK: - Report Auto-scaling Consistency

    @Test
    func reportSnapshotFormattedHashrateTruthfulPolicy() {
        #expect(FleetReportSnapshot.formattedHashrate(nil) == "Not reported")
        #expect(FleetReportSnapshot.formattedHashrate(-10.0) == "Not reported")
        #expect(FleetReportSnapshot.formattedHashrate(.nan) == "Not reported")
        #expect(FleetReportSnapshot.formattedHashrate(.infinity) == "Not reported")

        #expect(FleetReportSnapshot.formattedHashrate(450.0) == "450 GH/s")
        #expect(FleetReportSnapshot.formattedHashrate(750.0) == "750 GH/s")
        #expect(FleetReportSnapshot.formattedHashrate(1_250.0) == "1.25 TH/s")
        #expect(FleetReportSnapshot.formattedHashrate(2_500.0) == "2.50 TH/s")
    }

    // MARK: - Chart Scale Selection & Consistency

    @Test
    func chartDescriptorMatchesSeriesMaxScale() throws {
        // High-rate series (2.5 TH/s max) -> TH/s scale
        let pt1 = HashratePoint(date: baseDate, value: 500.0)
        let pt2 = HashratePoint(date: baseDate.addingTimeInterval(30), value: 2_500.0)
        let seriesHigh = MinerHistorySeries(name: "Naja Duo", points: [pt1, pt2])

        let providerHigh = FleetAXChartDescriptorProvider(
            series: [seriesHigh],
            windowHeading: "24h",
            isDemo: false
        )
        let descriptorHigh = providerHigh.makeChartDescriptor()
        #expect(descriptorHigh.yAxis?.title == "Hashrate in TH/s")
        let pointsHigh = descriptorHigh.series.first?.dataPoints ?? []
        try #require(pointsHigh.count == 2)
        #expect(pointsHigh[0].yValue?.__number == 0.5)
        #expect(pointsHigh[1].yValue?.__number == 2.5)

        // Low-rate series (750 GH/s max) -> GH/s scale
        let ptLow1 = HashratePoint(date: baseDate, value: 450.0)
        let ptLow2 = HashratePoint(date: baseDate.addingTimeInterval(30), value: 750.0)
        let seriesLow = MinerHistorySeries(name: "Gamma 601a", points: [ptLow1, ptLow2])

        let providerLow = FleetAXChartDescriptorProvider(
            series: [seriesLow],
            windowHeading: "24h",
            isDemo: false
        )
        let descriptorLow = providerLow.makeChartDescriptor()
        #expect(descriptorLow.yAxis?.title == "Hashrate in GH/s")
        let pointsLow = descriptorLow.series.first?.dataPoints ?? []
        try #require(pointsLow.count == 2)
        #expect(pointsLow[0].yValue?.__number == 450.0)
        #expect(pointsLow[1].yValue?.__number == 750.0)
    }

    @Test
    func chartTooltipsPreserveIndependentAutoScaling() {
        let ptGamma = HashratePoint(date: baseDate, value: 650.0) // 650 GH/s
        let ptNaja = HashratePoint(date: baseDate, value: 2_400.0) // 2.40 TH/s
        let sGamma = MinerHistorySeries(name: "Gamma", points: [ptGamma])
        let sNaja = MinerHistorySeries(name: "Naja", points: [ptNaja])

        let selection = FleetChartSelection.resolve(at: baseDate, in: [sGamma, sNaja], tolerance: 60)
        #expect(selection != nil)

        // Tooltip for Gamma is independently in GH/s
        #expect(selection?.seriesValues[0].formattedRate == "650 GH/s")
        // Tooltip for Naja is independently in TH/s
        #expect(selection?.seriesValues[1].formattedRate == "2.40 TH/s")
        // Total (650 + 2400 = 3050 GH/s) is 3.05 TH/s
        #expect(selection?.formattedTotalRate == "3.05 TH/s")
    }

    @Test
    func chartMissingSeriesValuesReportDashesAndAccessibilityText() {
        let pt = HashratePoint(date: baseDate, value: 800.0)
        let sOnline = MinerHistorySeries(name: "OnlineMiner", points: [pt])
        let sOffline = MinerHistorySeries(name: "OfflineMiner", points: [])

        let selection = FleetChartSelection.resolve(at: baseDate, in: [sOnline, sOffline], tolerance: 60)
        #expect(selection != nil)

        #expect(selection?.seriesValues[0].isMissing == false)
        #expect(selection?.seriesValues[0].formattedRate == "800 GH/s")

        #expect(selection?.seriesValues[1].isMissing == true)
        #expect(selection?.seriesValues[1].formattedRate == "—")
        #expect(selection?.seriesValues[1].accessibilityText == "OfflineMiner: offline or no reading")
    }

    @Test
    func diagnosticsFormatHashrateBoundaryScales() {
        #expect(MinerDiagnosticsModel.formatHashrate(0.0) == "0 GH/s")
        #expect(MinerDiagnosticsModel.formatHashrate(999.9) == "999.9 GH/s")
        #expect(MinerDiagnosticsModel.formatHashrate(1_000.0) == "1.00 TH/s")
        #expect(MinerDiagnosticsModel.formatHashrate(1_000_000.0) == "1.00 PH/s")
    }

    @Test
    func insightsFormatHashrateHpsRanges() {
        #expect(InsightsFormat.hashrate(0) == "0.00 H/s")
        #expect(InsightsFormat.hashrate(999) == "999.00 H/s")
        #expect(InsightsFormat.hashrate(1_000) == "1.00 kH/s")
        #expect(InsightsFormat.hashrate(1_000_000) == "1 MH/s")
        #expect(InsightsFormat.hashrate(1_000_000_000) == "1 GH/s")
    }

    // MARK: - Insights Fee Rate Formatting

    @Test
    func insightsFeeAndFeeRateFormatting() {
        #expect(InsightsFormat.fee(nil) == "Not reported")
        #expect(InsightsFormat.fee(15.2) == "15.20 sat/vB")
        #expect(InsightsFormat.fee(0.0) == "0.00 sat/vB")
        #expect(InsightsFormat.fee(-1.0) == "-1.00 sat/vB")

        #expect(InsightsFormat.feeRate(nil) == "Not reported")
        #expect(InsightsFormat.feeRate(15.2) == "15.20")
        #expect(InsightsFormat.feeRate(0.0) == "0.00")

        #expect(InsightsFormat.feeUnit(nil) == nil)
        #expect(InsightsFormat.feeUnit(15.2) == "sat/vB")
        #expect(InsightsFormat.feeUnit(0.0) == "sat/vB")
    }

    @Test
    func insightsFormatHashrateExtremeBoundaries() {
        #expect(InsightsFormat.hashrate(-0.001) == "Not reported")
        #expect(InsightsFormat.hashrate(-.infinity) == "Not reported")
        #expect(InsightsFormat.hashrate(.nan) == "Not reported")
        #expect(InsightsFormat.hashrate(.infinity) == "Not reported")
        #expect(InsightsFormat.hashrate(0.0) == "0.00 H/s")
        #expect(InsightsFormat.hashrate(0.5) == "0.50 H/s")
    }
}
