import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension FleetTickerCursorTests {
    // MARK: - Previous sample cooling context

    @Test func coolingComparisonUsesOnlyFieldsReportedInBothSamples() {
        let previous = MinerInfo(raw: [
            "temp": .number(62), "vrTemp": .number(64), "fanspeed": .number(60)
        ])
        let current = MinerInfo(raw: [
            "temp": .number(59), "fanspeed": .number(65)
        ])

        let readings = MinerCoolingComparison.readings(current: current, previous: previous)
        #expect(readings.map(\.id) == ["chipTemp", "fanSpeed"])
        #expect(readings.first?.direction == .decreased)
        #expect(readings.first?.delta == -3)
        #expect(readings.last?.direction == .increased)
    }

    @Test func coolingComparisonIsEmptyWithoutAPreviousSuccessfulSample() {
        let current = MinerInfo(raw: ["temp": .number(59), "fanspeed": .number(65)])
        #expect(MinerCoolingComparison.readings(current: current, previous: nil).isEmpty)
    }

    // MARK: - Browser destinations

    @Test func browserDestinationRemovesMiningCredentialsAndStratumPort() {
        let destination = FleetBrowserURL.destination(
            for:
                "stratum+tcp://worker:secret@pool.example:3333/path?token=hidden#fragment"
        )
        #expect(destination?.absoluteString == "https://pool.example")
    }

    @Test func browserDestinationKeepsExplicitLocalWebSchemeAndPathWithoutQuery() {
        let destination = FleetBrowserURL.destination(for: "http://10.0.0.8/api/system/info?token=hidden")
        #expect(destination?.absoluteString == "http://10.0.0.8/api/system/info")
    }

    @Test func browserDestinationRejectsUnknownSchemesAndEmptyValues() {
        #expect(FleetBrowserURL.destination(for: "javascript://alert") == nil)
        #expect(FleetBrowserURL.destination(for: "   ") == nil)
        #expect(FleetBrowserURL.destination(for: "Not reported") == nil)
    }
}
