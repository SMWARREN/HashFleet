import XCTest
import GRDB
@testable import HashFleetCore

/// Validates Phase 2 features actually use the database correctly
final class Phase2IntegrationValidationTests: XCTestCase {

    @MainActor
    func testHistoricalChartQueriesDatabase() async throws {
        let dbQueue = try DatabaseQueue()
        let db = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let testMinerId = UUID().uuidString
        let now = Date()

        // Record data over 14 days
        for dayOffset in 0..<14 {
            let timestamp = now.addingTimeInterval(Double(-dayOffset * 86400))
            db.recordReading(
                minerId: testMinerId,
                timestamp: timestamp,
                reading: MinerReadingInput(hashrate: 1000.0 + Double(dayOffset * 10))
            )
        }

        await db.flushReadings()

        // Query 7-day range (like FleetHistoryCard does for .weekly)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86400)
        let sevenDayData = await db.getHashrateReadings(
            minerId: testMinerId,
            since: sevenDaysAgo,
            until: now
        )

        XCTAssertEqual(sevenDayData.count, 8, "Should get 8 readings (today + 7 days)")
        // getHashrateReadings returns ASC order (oldest first)
        XCTAssertEqual(sevenDayData.first?.hashrate ?? -1, 1070.0, accuracy: 0.1, "7 days ago reading (oldest)")
        XCTAssertEqual(sevenDayData.last?.hashrate ?? -1, 1000.0, accuracy: 0.1, "Most recent reading (newest)")

        // Query 30-day range (like FleetHistoryCard does for .monthly)
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 86400)
        let thirtyDayData = await db.getHashrateReadings(
            minerId: testMinerId,
            since: thirtyDaysAgo,
            until: now
        )

        XCTAssertEqual(thirtyDayData.count, 14, "Should get all 14 recorded readings")
    }

    @MainActor
    func testAchievementsViewFiltering() async throws {
        let dbQueue = try DatabaseQueue()
        let db = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let testMinerId = UUID().uuidString
        let now = Date()

        // Record 2 blocks and 3 shares (like real mining activity)
        await seedAchievements(db, minerId: testMinerId, now: now)

        // Test "All" filter (like MiningAchievementsView with .all)
        let allAchievements = await db.getAchievements(minerId: testMinerId)
        XCTAssertEqual(allAchievements.count, 5, "Should get all 5 achievements")

        // Test "Blocks only" filter (like MiningAchievementsView with .blocks)
        let blocksOnly = await db.getAchievements(minerId: testMinerId, eventType: "block_found")
        XCTAssertEqual(blocksOnly.count, 2, "Should get only 2 blocks")
        XCTAssertTrue(blocksOnly.allSatisfy { $0.eventType == "block_found" }, "All should be blocks")
        XCTAssertEqual(blocksOnly.first?.blockHeight, 850000, "Most recent block first")

        // Test "Shares only" filter (like MiningAchievementsView with .shares)
        let sharesOnly = await db.getAchievements(minerId: testMinerId, eventType: "best_share")
        XCTAssertEqual(sharesOnly.count, 3, "Should get only 3 shares")
        XCTAssertTrue(sharesOnly.allSatisfy { $0.eventType == "best_share" }, "All should be shares")

        // Verify sorting (most recent first, like MiningAchievementsView does)
        XCTAssertGreaterThanOrEqual(
            allAchievements[0].timestamp,
            allAchievements[4].timestamp,
            "Should be sorted most recent first"
        )
    }

    @MainActor
    private func seedAchievements(_ db: MinerTelemetryDatabase, minerId: String, now: Date) async {
        await db.recordAchievement(
            minerId: minerId,
            eventType: "block_found",
            timestamp: now,
            blockHeight: 850000,
            metadata: ["height": 850000]
        )

        await db.recordAchievement(
            minerId: minerId,
            eventType: "best_share",
            timestamp: now.addingTimeInterval(-3600),
            blockHeight: nil,
            difficulty: "1500000",
            metadata: nil
        )

        await db.recordAchievement(
            minerId: minerId,
            eventType: "block_found",
            timestamp: now.addingTimeInterval(-7200),
            blockHeight: 849999,
            difficulty: nil,
            metadata: ["height": 849999]
        )

        await db.recordAchievement(
            minerId: minerId,
            eventType: "best_share",
            timestamp: now.addingTimeInterval(-10800),
            blockHeight: nil,
            difficulty: "2500000",
            metadata: nil
        )

        await db.recordAchievement(
            minerId: minerId,
            eventType: "best_share",
            timestamp: now.addingTimeInterval(-14400),
            blockHeight: nil,
            difficulty: "3500000",
            metadata: nil
        )
    }

    func testNotificationDeliveryCodeFixed() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Store/FleetNotificationDelivery.swift")

        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        // Active events retain temperature overlays separately, while every background event
        // passes through the shared durable route before it can be posted.
        XCTAssertTrue(
            source.contains("if case .temperature(let temperature) = event")
                && source.contains("return inAppTemperatures"),
            "Active events should return temperatures and preserve in-app overlay separation"
        )
        XCTAssertTrue(
            source.contains("pending.blocksFound.map(FleetNotificationEvent.blockFound)")
                && source.contains("deliver(event, from: store)")
                && source.contains("post(event, using: postHandlers)"),
            "Blocks must enter the unified event queue and use the durable delivery path"
        )
    }

    @MainActor
    func testEmptyDatabaseReturnsEmptyResults() async throws {
        let dbQueue = try DatabaseQueue()
        let db = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let testMinerId = UUID().uuidString
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86400)

        // Query empty database (like fresh install)
        let readings = await db.getHashrateReadings(
            minerId: testMinerId,
            since: sevenDaysAgo,
            until: now
        )

        let achievements = await db.getAchievements(minerId: testMinerId)

        XCTAssertEqual(readings.count, 0, "Empty database should return no readings")
        XCTAssertEqual(achievements.count, 0, "Empty database should return no achievements")

        // Views should handle empty results gracefully:
        // - FleetHistoryCard shows "No readings in this time window yet"
        // - MiningAchievementsView shows trophy icon with "No achievements yet"
    }

    @MainActor
    func testDatabasePersistenceAcrossSessions() async throws {
        // Simulate app restart by creating new database connection
        let dbQueue = try DatabaseQueue()
        let db1 = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let testMinerId = UUID().uuidString
        let now = Date()

        // Session 1: Record data
        db1.recordReading(
            minerId: testMinerId,
            timestamp: now,
            reading: MinerReadingInput(hashrate: 1250.0)
        )

        await db1.recordAchievement(
            minerId: testMinerId,
            eventType: "block_found",
            timestamp: now,
            blockHeight: 850000,
            difficulty: nil,
            metadata: ["height": 850000]
        )

        await db1.flushReadings()

        // Session 2: Create new database connection (simulates app restart)
        let db2 = MinerTelemetryDatabase(databaseQueue: dbQueue)

        // Data should persist
        let readings = await db2.getHashrateReadings(
            minerId: testMinerId,
            since: now.addingTimeInterval(-60),
            until: now.addingTimeInterval(60)
        )

        let achievements = await db2.getAchievements(minerId: testMinerId)

        XCTAssertEqual(readings.count, 1, "Reading should persist across sessions")
        XCTAssertEqual(readings.first?.hashrate ?? 0, 1250.0, accuracy: 0.1)

        XCTAssertEqual(achievements.count, 1, "Achievement should persist across sessions")
        XCTAssertEqual(achievements.first?.blockHeight, 850000)

        // This validates Phase 2's core value: historical data survives app restarts
    }

    @MainActor
    func testGetAllAchievementsAcrossAllMiners() async throws {
        let dbQueue = try DatabaseQueue()
        let db = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let miner1 = UUID().uuidString
        let miner2 = UUID().uuidString
        let now = Date()

        await db.recordAchievement(
            minerId: miner1,
            eventType: "block_found",
            timestamp: now,
            blockHeight: 850001,
            metadata: ["height": 850001]
        )
        await db.recordAchievement(
            minerId: miner2,
            eventType: "best_share",
            timestamp: now.addingTimeInterval(-60),
            difficulty: "2500000",
            metadata: nil
        )
        await db.recordAchievement(
            minerId: miner2,
            eventType: "block_found",
            timestamp: now.addingTimeInterval(-120),
            blockHeight: 850000,
            metadata: ["height": 850000]
        )

        let all = await db.getAllAchievements()
        XCTAssertEqual(all.count, 3, "Should return all achievements across miners")

        let blocksOnly = await db.getAllAchievements(eventType: "block_found")
        XCTAssertEqual(blocksOnly.count, 2, "Should return only block found achievements")
        XCTAssertEqual(blocksOnly.first?.blockHeight, 850001, "Most recent block first")

        let limited = await db.getAllAchievements(limit: 1)
        XCTAssertEqual(limited.count, 1, "Should respect limit parameter")
    }

    func testMinerInfoBlockFoundProperties() throws {
        let json: [String: JSONValue] = [
            "blockFound": .integer(2),
            "showNewBlock": .bool(true),
            "blockHeight": .integer(850042)
        ]
        let info = MinerInfo(raw: json)
        XCTAssertEqual(info.blockFound, 2)
        XCTAssertTrue(info.showNewBlock)
        XCTAssertEqual(info.blockHeight, 850042)
    }
}
