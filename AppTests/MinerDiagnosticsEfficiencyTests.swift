import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension MinerDiagnosticsTests {
    @Test func efficiencyCalculatesZeroJTHForZeroWattsWithPositiveHashrate() {
        let raw: [String: JSONValue] = [
            "power": .number(0),
            "hashRate": .number(500)
        ]
        let model = MinerDiagnosticsModel(raw: raw)
        #expect(model.electrical.efficiencyJoulesPerTerahash == 0.0)
    }

    @Test func percentageParsingEnforcesUpperBoundOf100() {
        let raw: [String: JSONValue] = [
            "fanspeed": .number(150),  // invalid > 100
            "minFanSpeed": .number(25),
            "errorPercentage": .number(105)
        ]
        let model = MinerDiagnosticsModel(raw: raw)
        #expect(model.thermal.fanSpeedPercent == nil)
        #expect(model.thermal.minFanSpeedPercent == 25)
        #expect(model.hashrate.asicErrorPercentage == nil)
    }

    @Test func emptyAndMissingFieldsDefaultHonestlyToNilWithoutTrapping() {
        let emptyRaw: [String: JSONValue] = [:]
        let model = MinerDiagnosticsModel(raw: emptyRaw)

        #expect(model.electrical.configuredFrequencyMHz == nil)
        #expect(model.electrical.actualFrequencyMHz == nil)
        #expect(model.electrical.powerWatts == nil)
        #expect(model.electrical.dailyEnergyEstimateKWh == nil)
        #expect(model.thermal.primaryChipTempCelsius == nil)
        #expect(model.thermal.secondaryChipTempCelsius == nil)
        #expect(model.thermal.isSecondaryTempAvailable == false)
        #expect(model.thermal.fan2RPM == nil)
        #expect(model.thermal.isFan2Available == false)
        #expect(model.hashrate.currentHashrateGHs == nil)
        #expect(model.hashrate.rejectedSharePercentage == nil)
        #expect(model.pool.activeConnectionURL == "Not reported")
        #expect(model.pool.rejectionReasons.isEmpty)
        #expect(model.system.sessionUptimeSeconds == nil)
    }

    // MARK: - Formatting Unit Tests

    @Test func formattersProduceTruthfulHumanReadableStrings() {
        #expect(MinerDiagnosticsModel.formatHashrate(nil) == "Not reported")
        #expect(MinerDiagnosticsModel.formatHashrate(450.0) == "450 GH/s")
        #expect(MinerDiagnosticsModel.formatHashrate(1250.0) == "1.25 TH/s")

        #expect(MinerDiagnosticsModel.formatFrequency(nil) == "Not reported")
        #expect(MinerDiagnosticsModel.formatFrequency(525.0) == "525 MHz")

        #expect(MinerDiagnosticsModel.formatMillivolts(nil) == "Not reported")
        #expect(
            MinerDiagnosticsModel.formatMillivolts(1180.0) == "1,180 mV"
                || MinerDiagnosticsModel.formatMillivolts(1180.0) == "1180 mV"
        )

        #expect(MinerDiagnosticsModel.formatWatts(nil) == "Not reported")
        #expect(MinerDiagnosticsModel.formatWatts(15.2) == "15.2 W")

        #expect(MinerDiagnosticsModel.formatEnergyKWhPerDay(nil) == "Not reported")
        #expect(MinerDiagnosticsModel.formatEnergyKWhPerDay(0.36) == "0.36 kWh/day")

        #expect(MinerDiagnosticsModel.formatDuration(nil) == "Not reported")
        #expect(
            MinerDiagnosticsModel.formatDuration(3665) == "1:01:05"
                || MinerDiagnosticsModel.formatDuration(3665) == "01:01:05"
        )
    }
}
