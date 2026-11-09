import Testing
import HashFleetCore
@testable import HashFleet

struct MinerASICCountTests {
    @Test(arguments: [
        ("602", 1), ("601", 1), ("1201", 2),
        ("650", 2), ("801", 2), ("1300", 6), ("303", 6)
    ])
    func knownBoardVersions(board: String, expected: Int) {
        let info = MinerInfo(raw: [
            "boardVersion": .string(board),
            "ASICModel": .string("BM1370"),
            // Firmware can include temp2 even when a second temperature is unavailable.
            "temp2": .integer(-1)
        ])

        #expect(MinerCapabilityPresentation.asicCount(info: info) == expected)
    }

    @Test func explicitFirmwareCountTakesPrecedence() {
        let info = MinerInfo(raw: [
            "asicCount": .integer(2),
            "boardVersion": .string("602"),
            "ASICModel": .string("BM1370")
        ])

        #expect(MinerCapabilityPresentation.asicCount(info: info) == 2)
    }

    @Test func unknownBoardAndTemperatureKeyDoNotGuessChipCount() {
        let info = MinerInfo(raw: [
            "boardVersion": .string("custom-unknown"),
            "ASICModel": .string("BM1370"),
            "temp2": .integer(43)
        ])

        #expect(MinerCapabilityPresentation.asicCount(info: info) == nil)
    }

    @Test func headerDescriptorsShowOneGammaChipAndTwoNajaChips() {
        let gamma = MinerInfo(raw: [
            "boardVersion": .string("602"),
            "ASICModel": .string("BM1370"),
            "temp2": .integer(49)
        ])
        let naja = MinerInfo(raw: [
            "boardVersion": .string("1201"),
            "ASICModel": .string("BM1372/BM1373")
        ])

        #expect(MinerCapabilityPresentation.asicDescriptor(info: gamma) == "1× BM1370")
        #expect(MinerCapabilityPresentation.asicDescriptor(info: naja) == "2× BM1372/BM1373")
    }

    @Test func heatLabelsDescribeSensorsWithoutInventingChipNumbers() {
        let unavailableSecondSensor = MinerInfo(raw: ["temp": .integer(55), "temp2": .integer(-1)])
        let reportedSecondSensor = MinerInfo(raw: ["temp": .integer(55), "temp2": .integer(49)])

        #expect(
            MinerThermalPresentation.reportedTemperatures(unavailableSecondSensor).map(\.title)
                == ["Temperature"]
        )
        #expect(
            MinerThermalPresentation.reportedTemperatures(reportedSecondSensor).map(\.title)
                == ["Temperature", "Temperature 2"]
        )
    }

    @Test func stringCountIsAcceptedButNonpositiveCountIsIgnored() {
        #expect(
            MinerCapabilityPresentation.asicCount(
                info: MinerInfo(raw: ["asicCount": .string("2")])
            ) == 2
        )
        #expect(
            MinerCapabilityPresentation.asicCount(
                info: MinerInfo(raw: ["asicCount": .integer(0), "boardVersion": .string("602")])
            ) == 1
        )
    }
}
