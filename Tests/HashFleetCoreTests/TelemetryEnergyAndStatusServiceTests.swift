import XCTest
import GRDB
@testable import HashFleetCore

final class TelemetryEnergyAndStatusServiceTests: XCTestCase {

    @MainActor
    func testMinerPowerMinuteInitAndProperties() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let minute = MinerPowerMinute(minerId: "m1", minuteStart: date, averageWatts: 15.5)
        XCTAssertEqual(minute.minerId, "m1")
        XCTAssertEqual(minute.minuteStart, date)
        XCTAssertEqual(minute.averageWatts, 15.5)

        let same = MinerPowerMinute(minerId: "m1", minuteStart: date, averageWatts: 15.5)
        XCTAssertEqual(minute, same)
    }

    @MainActor
    func testGetPowerMinutesEmptyMinerIds() async throws {
        let db = MinerTelemetryDatabase(databaseQueue: try DatabaseQueue())
        let results = await db.getPowerMinutes(minerIds: [], since: Date())
        XCTAssertTrue(results.isEmpty)
    }

    @MainActor
    func testGetPowerMinutesAggregatesReadingsPerMinute() async throws {
        let db = MinerTelemetryDatabase(databaseQueue: try DatabaseQueue())
        let start = Date(timeIntervalSince1970: 1_800_000_000) // minute aligned (1800000000 % 60 == 0)
        let end = start.addingTimeInterval(300)

        // Record readings in minute 0 (offsets 10s, 30s)
        db.recordReading(
            minerId: "miner-1",
            timestamp: start.addingTimeInterval(10),
            reading: MinerReadingInput(power: 20.0)
        )
        db.recordReading(
            minerId: "miner-1",
            timestamp: start.addingTimeInterval(30),
            reading: MinerReadingInput(power: 30.0)
        )
        // Record negative power (should be excluded)
        db.recordReading(
            minerId: "miner-1",
            timestamp: start.addingTimeInterval(40),
            reading: MinerReadingInput(power: -5.0)
        )

        // Record reading in minute 1 (offset 70s)
        db.recordReading(
            minerId: "miner-1",
            timestamp: start.addingTimeInterval(70),
            reading: MinerReadingInput(power: 50.0)
        )

        // Record reading for another miner
        db.recordReading(
            minerId: "miner-2",
            timestamp: start.addingTimeInterval(15),
            reading: MinerReadingInput(power: 100.0)
        )

        await db.flushReadings()

        let powerMinutes = await db.getPowerMinutes(minerIds: ["miner-1", "miner-2"], since: start, until: end)
        XCTAssertFalse(powerMinutes.isEmpty)

        let miner1Minutes = powerMinutes.filter { $0.minerId == "miner-1" }
        XCTAssertEqual(miner1Minutes.count, 2)
        // Minute 0 average should be (20 + 30) / 2 = 25.0
        XCTAssertEqual(miner1Minutes[0].averageWatts, 25.0)
        // Minute 1 average should be 50.0
        XCTAssertEqual(miner1Minutes[1].averageWatts, 50.0)

        let miner2Minutes = powerMinutes.filter { $0.minerId == "miner-2" }
        XCTAssertEqual(miner2Minutes.count, 1)
        XCTAssertEqual(miner2Minutes[0].averageWatts, 100.0)
    }

    @MainActor
    func testFleetStatusServiceReadsDevicesAndSortsByName() async {
        let dev1 = MinerDevice(
            name: "Beta Miner",
            address: "127.0.0.1:65530",
            kind: .espMiner,
            firmwareFamily: "bitaxe"
        )
        let dev2 = MinerDevice(
            name: "Alpha Miner",
            address: "127.0.0.1:65531",
            kind: .xmrig
        )

        let snapshot = await FleetStatusService.read(devices: [dev1, dev2], xmrigBearerToken: "token")
        XCTAssertEqual(snapshot.miners.count, 2)
        // Must be sorted alphabetically by name
        XCTAssertEqual(snapshot.miners[0].name, "Alpha Miner")
        XCTAssertEqual(snapshot.miners[1].name, "Beta Miner")
        // Since localhost high ports are not serving, both should capture errors
        XCTAssertNotNil(snapshot.miners[0].error)
        XCTAssertNotNil(snapshot.miners[1].error)
    }

    @MainActor
    func testFleetStatusServiceWithEmptyDevices() async {
        let snapshot = await FleetStatusService.read(devices: [])
        XCTAssertTrue(snapshot.miners.isEmpty)
    }
}
