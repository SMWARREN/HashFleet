import XCTest
@testable import HashFleetCore

final class FleetFormatTests: XCTestCase {
    func testHashrateUsesSameUnitsAcrossSurfaces() {
        XCTAssertEqual(FleetFormat.hashrate(1_529), "1.53")
        XCTAssertEqual(FleetFormat.hashrateUnit(1_529), "TH/s")
        XCTAssertEqual(FleetFormat.hashrateWithUnit(1_529), "1.53 TH/s")
        XCTAssertEqual(FleetFormat.hashrate(750), "750")
        XCTAssertEqual(FleetFormat.hashrateUnit(750), "GH/s")
        XCTAssertEqual(FleetFormat.hashrateWithUnit(750), "750 GH/s")
        XCTAssertEqual(FleetFormat.hashrateWithUnit(-1), "—")
        XCTAssertEqual(FleetFormat.hashrateWithUnit(.infinity), "—")
    }

    func testNumericFormattersHandleMissingAndInvalidValues() {
        XCTAssertEqual(FleetFormat.measurement(nil, unit: "W"), "Not reported")
        XCTAssertEqual(FleetFormat.number(.infinity), "—")
        XCTAssertEqual(FleetFormat.number(19.365, decimals: 1), "19.4")
        XCTAssertEqual(FleetFormat.blockHeight(969_865), "969865")
    }

    func testSensorReadsFirmwareAliasesAndRejectsInvalidValues() {
        let info = MinerInfo(raw: [
            "hashrate": .number(9_955.68),
            "temp": .number(49.8),
            "invalid": .number(-1)
        ])

        XCTAssertEqual(FleetFormat.sensor(info, keys: "hashRate", "hashrate"), 9_955.68)
        XCTAssertEqual(FleetFormat.sensor(info, keys: "temp"), 49.8)
        XCTAssertNil(FleetFormat.sensor(info, keys: "invalid"))
    }
}
