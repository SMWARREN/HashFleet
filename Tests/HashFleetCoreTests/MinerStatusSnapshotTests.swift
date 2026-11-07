import XCTest
@testable import HashFleetCore

final class MinerStatusSnapshotTests: XCTestCase {
    func testOnlineSnapshotExposesNormalizedStatusAndFleetTotals() throws {
        let device = MinerDevice(name: "Gamma", address: "192.0.2.15")
        let info = MinerInfo(raw: [
            "hashRate": .number(1.42),
            "temp": .number(59.5),
            "power": .number(20),
            "uptimeSeconds": .integer(3600),
            "ASICModel": .string("BM1370"),
            "version": .string("v2.15.3")
        ])
        let snapshot = MinerStatusSnapshot(device: device, info: info)
        let fleet = FleetStatusSnapshot(miners: [snapshot])

        XCTAssertTrue(snapshot.isOnline)
        XCTAssertEqual(snapshot.hashrate, 1.42)
        XCTAssertEqual(snapshot.temperatureCelsius, 59.5)
        XCTAssertEqual(snapshot.powerWatts, 20)
        XCTAssertEqual(snapshot.uptimeSeconds, 3600)
        XCTAssertEqual(snapshot.asicModel, "BM1370")
        XCTAssertEqual(snapshot.firmware, "v2.15.3")
        XCTAssertEqual(fleet.onlineCount, 1)
        XCTAssertEqual(fleet.offlineCount, 0)
        XCTAssertEqual(fleet.totalHashrateGHs, 1.42)
    }

    func testOfflineSnapshotPreservesErrorAndHidesUnavailableMetrics() {
        let device = MinerDevice(name: "Offline", address: "192.0.2.16")
        let snapshot = MinerStatusSnapshot(device: device, error: "timed out")

        XCTAssertFalse(snapshot.isOnline)
        XCTAssertEqual(snapshot.error, "timed out")
        XCTAssertNil(snapshot.hashrate)
        XCTAssertNil(snapshot.power)
        XCTAssertNil(snapshot.temperature)
        XCTAssertEqual(snapshot.hashrateGHs, 0)
    }

    func testOnlineSnapshotHidesNegativeFirmwareSentinels() {
        let snapshot = MinerStatusSnapshot(
            device: MinerDevice(name: "Invalid metrics", address: "192.0.2.17"),
            info: MinerInfo(raw: [
                "hashRate": .number(-1),
                "power": .number(-1),
                "temp": .number(-1),
                "uptimeSeconds": .integer(-1)
            ])
        )

        XCTAssertNil(snapshot.hashrate)
        XCTAssertNil(snapshot.power)
        XCTAssertNil(snapshot.temperatureCelsius)
        XCTAssertNil(snapshot.uptimeSeconds)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = MinerStatusSnapshot(
            device: MinerDevice(name: "Gamma", address: "192.0.2.15"),
            observedAt: Date(timeIntervalSince1970: 123),
            info: MinerInfo(raw: ["hashRate": .number(1.5)])
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MinerStatusSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }
}
