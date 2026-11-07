import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Fleet numeric motion tests")
@MainActor
struct FleetNumericMotionTests {

    @Test func fleetNumericUpdateModifierRendersWithoutCrashing() {
        // Verifies view evaluation with reduceMotion true and false
        let text = Text("12.34 TH/s")
        let viewWithMotion = text.fleetNumericUpdate("12.34 TH/s", reduceMotion: false)
        let viewReducedMotion = text.fleetNumericUpdate("12.34 TH/s", reduceMotion: true)
        let viewEnvironment = text.fleetNumericUpdate("12.34 TH/s")

        _ = viewWithMotion
        _ = viewReducedMotion
        _ = viewEnvironment
    }

    @Test func numericMotionPolicyRollsHeadlinesEverywhere() {
        #expect(FleetNumericMotionPolicy.updatesInPlace(isNativeMac: true))
        #expect(!FleetNumericMotionPolicy.updatesInPlace(isNativeMac: true, isHeadline: true))
        #expect(!FleetNumericMotionPolicy.updatesInPlace(isNativeMac: false))
        // AppTests host on iOS, which keeps the rolling digits.
        #expect(!FleetNumericMotionPolicy.updatesInPlace)
    }

    @Test func fleetNumericUpdatePreservesFormattingSemantics() {
        // Ensure numeric formats for changing telemetry match expected string forms
        let hashrate = 5420.0  // GH/s
        let formattedHashrate = FleetFormat.hashrate(hashrate)
        let unit = FleetFormat.hashrateUnit(hashrate)
        #expect(formattedHashrate == "5.42")
        #expect(unit == "TH/s")

        let powerWatts = 14.8
        let formattedPower = "\(FleetFormat.number(powerWatts, decimals: 1)) W"
        #expect(formattedPower == "14.8 W")

        // Missing / stale / negative / sentinel values
        #expect(FleetFormat.hashrate(-1) == "—")
        #expect(FleetFormat.hashrate(.nan) == "—")
        #expect(FleetFormat.hashrate(.infinity) == "—")
        #expect(FleetFormat.measurement(nil, unit: "W") == "Not reported")
    }

    @Test func minerShareSummaryNumericTransitionsPreserveEdgeCases() {
        // Verify share counts and percentages for telemetry transitions
        let summaryZero = MinerShareSummary(raw: [
            "sharesAccepted": .integer(0),
            "sharesRejected": .integer(0)
        ])
        #expect(summaryZero.acceptedDisplay == "0")
        #expect(summaryZero.rejectedDisplay == "0")
        #expect(summaryZero.rejectedSharePercentageDisplay == "No shares yet")

        let summaryActive = MinerShareSummary(raw: [
            "sharesAccepted": .integer(1000),
            "sharesRejected": .integer(5)
        ])
        #expect(summaryActive.acceptedDisplay == "1,000")
        #expect(summaryActive.rejectedDisplay == "5")
        #expect(summaryActive.rejectedSharePercentageDisplay == "0.50%")

        let summaryMissing = MinerShareSummary(raw: [:])
        #expect(summaryMissing.acceptedDisplay == "Not reported")
        #expect(summaryMissing.rejectedDisplay == "Not reported")
        #expect(summaryMissing.rejectedSharePercentageDisplay == "Not reported")
    }

    @Test func minerDiagnosticsFormattingRetainsMonospacedValues() {
        let freq = MinerDiagnosticsModel.formatFrequency(600.0)
        #expect(freq == "600 MHz")
        #expect(MinerDiagnosticsModel.formatFrequency(nil) == "Not reported")

        let mv = MinerDiagnosticsModel.formatMillivolts(1200.0)
        #expect(mv == "1,200 mV")

        let temp = MinerDiagnosticsModel.formatTemperature(58.5)
        #expect(temp == "58.5 °C")

        let rpm = MinerDiagnosticsModel.formatFanRPM(4500.0)
        #expect(rpm == "4,500 RPM")

        let hash = MinerDiagnosticsModel.formatHashrate(1250.0)
        #expect(hash == "1.25 TH/s")
    }

    @Test func insightsFormattingRetainsConsistencyForNumericTransitions() {
        #expect(InsightsFormat.compact(1.25e12) == "1.25T")
        #expect(InsightsFormat.compact(999_600) == "999.60K")
        #expect(FleetFormat.difficulty("392000000") == "392.00M")
        #expect(FleetFormat.difficulty(1.25e12) == "1.25T")
        #expect(FleetFormat.integer(1_234_567) == "1,234,567")
        #expect(FleetFormat.integer(Int64(9_876_543_210)) == "9,876,543,210")
        #expect(FleetFormat.blockHeight(1_234_567) == "1234567")
        #expect(InsightsFormat.hashrate(1.25e12) == "1.25 TH/s")
        #expect(InsightsFormat.hashrate(nil) == "Not reported")
        #expect(InsightsFormat.compact(-1) == "Not reported")
        #expect(InsightsFormat.fee(12.5) == "12.50 sat/vB")
        #expect(InsightsFormat.fee(nil) == "Not reported")
    }

    @Test func insightsRowAndDiagnosticViewsInstantiate() {
        let row = InsightsRow("Difficulty", value: "85.2T")
        #expect(row.title == "Difficulty")
        #expect(row.value == "85.2T")

        let diag = MinerDiagnosticsView(model: MinerDiagnosticsModel(info: MinerInfo(raw: [:])))
        #expect(diag.model.electrical.nominalVoltageV == nil)
    }

    @Test func fleetFormatMeasurementFormattingBoundaries() {
        #expect(FleetFormat.measurement(42.5, unit: "W") == "42 W")
        #expect(FleetFormat.measurement(-5.0, unit: "W") == "-5 W")
        #expect(FleetFormat.measurement(.nan, unit: "W") == "— W")
        #expect(FleetFormat.measurement(.infinity, unit: "W") == "— W")
    }

    @Test func insightsFormatCompactValuesFormattingBoundaries() {
        #expect(InsightsFormat.compact(0) == "0")
        #expect(InsightsFormat.compact(999) == "999")
        #expect(InsightsFormat.compact(1_000) == "1.00K")
        #expect(InsightsFormat.compact(1_500_000) == "1.50M")
        #expect(InsightsFormat.compact(2_000_000_000) == "2.00G")
    }
}
