import XCTest
import GRDB
@testable import HashFleetCore

/// Tests that telemetry database persists data across sessions
final class TelemetryDatabasePersistenceTests: XCTestCase {

    @MainActor
    func testDatabaseWritesAndReadsPersist() async throws {
        // Create in-memory database for testing
        let dbQueue = try DatabaseQueue()
        let db = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let testMinerId = UUID().uuidString
        let testDate = Date()

        // Write a reading
        db.recordReading(
            minerId: testMinerId,
            timestamp: testDate,
            reading: MinerReadingInput(
                hashrate: 1250.5,
                power: 19.2,
                temp: 54.3,
                vrTemp: 52.1,
                fanSpeed: 65,
                fanRPM: 3200,
                voltage: 1200,
                frequency: 650,
                coreVoltage: 850,
                sharesAccepted: 1234,
                sharesRejected: 5,
                uptimeSeconds: 86400,
                activePoolIndex: 0,
                isFallbackPool: false
            )
        )

        // Flush to ensure it's written
        await db.flushReadings()

        // Read back hashrate data
        let hashrateData = await db.getHashrateReadings(
            minerId: testMinerId,
            since: testDate.addingTimeInterval(-60),
            until: testDate.addingTimeInterval(60)
        )

        XCTAssertEqual(hashrateData.count, 1, "Should have one hashrate reading")
        XCTAssertEqual(hashrateData.first?.hashrate ?? 0, 1250.5, accuracy: 0.1)

        // Read back temperature data
        let tempData = await db.getTemperatureReadings(
            minerId: testMinerId,
            since: testDate.addingTimeInterval(-60),
            until: testDate.addingTimeInterval(60)
        )

        XCTAssertEqual(tempData.count, 1, "Should have one temperature reading")
        XCTAssertEqual(tempData.first?.temp ?? 0, 54.3, accuracy: 0.1)
    }

    @MainActor
    func testBatchWriteFlushes() async throws {
        let dbQueue = try DatabaseQueue()
        let db = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let testMinerId = UUID().uuidString
        let startDate = Date()

        // Write 15 readings (should trigger auto-flush at 10)
        for readingIndex in 0..<15 {
            db.recordReading(
                minerId: testMinerId,
                timestamp: startDate.addingTimeInterval(Double(readingIndex * 30)),
                reading: MinerReadingInput(hashrate: 1200.0 + Double(readingIndex))
            )
        }

        // Small delay to allow batch flush
        try await Task.sleep(for: .milliseconds(100))

        let data = await db.getHashrateReadings(
            minerId: testMinerId,
            since: startDate.addingTimeInterval(-60),
            until: startDate.addingTimeInterval(500)
        )

        XCTAssertGreaterThanOrEqual(data.count, 10, "At least 10 readings should be flushed")
    }

    @MainActor
    func testAchievementsArePersisted() async throws {
        let dbQueue = try DatabaseQueue()
        let db = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let testMinerId = UUID().uuidString
        let testDate = Date()

        // Record a block found
        await db.recordAchievement(
            minerId: testMinerId,
            eventType: "block_found",
            timestamp: testDate,
            blockHeight: 123456,
            difficulty: nil,
            metadata: ["height": 123456]
        )

        // Record a best share
        await db.recordAchievement(
            minerId: testMinerId,
            eventType: "best_share",
            timestamp: testDate.addingTimeInterval(60),
            blockHeight: nil,
            difficulty: "1234567890",
            metadata: nil
        )

        // Read back all achievements
        let allAchievements = await db.getAchievements(minerId: testMinerId)
        XCTAssertEqual(allAchievements.count, 2, "Should have 2 achievement events")

        // Read back only blocks
        let blocks = await db.getAchievements(minerId: testMinerId, eventType: "block_found")
        XCTAssertEqual(blocks.count, 1, "Should have 1 block event")
        XCTAssertEqual(blocks.first?.blockHeight, 123456)

        // Read back only best shares
        let shares = await db.getAchievements(minerId: testMinerId, eventType: "best_share")
        XCTAssertEqual(shares.count, 1, "Should have 1 best share event")
        XCTAssertEqual(shares.first?.difficulty, "1234567890")
    }

    @MainActor
    func testPollingThenScoreboardKeepsOnlyAuthoritativeHighScore() async throws {
        let db = MinerTelemetryDatabase(databaseQueue: try DatabaseQueue())
        let minerId = UUID().uuidString
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let pollingInserted = await db.recordPollingBestShareAchievement(
            minerId: minerId, timestamp: timestamp, difficulty: 2_500_000)
        XCTAssertTrue(pollingInserted)
        let inserted = await db.reconcileScoreboard(
            minerId: minerId,
            entries: [MinerScoreboardEntry(
                difficulty: 2_500_100,
                jobId: "job-authoritative",
                extranonce2: "00",
                ntime: UInt32(timestamp.timeIntervalSince1970),
                nonce: "01",
                versionBits: "00000000",
                coin: "BTC",
                poolIndex: 0
            )]
        )

        XCTAssertEqual(inserted, 1)
        let shares = await db.getAchievements(minerId: minerId, eventType: "best_share")
        XCTAssertEqual(shares.count, 1)
        XCTAssertEqual(shares.first?.difficulty, "2500100")
        XCTAssertTrue(shares.first?.metadata?.contains("\"source\":\"scoreboard\"") == true)
    }

    @MainActor
    func testScoreboardThenPollingRejectsRoundedDuplicateHighScore() async throws {
        let db = MinerTelemetryDatabase(databaseQueue: try DatabaseQueue())
        let minerId = UUID().uuidString
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        _ = await db.reconcileScoreboard(
            minerId: minerId,
            entries: [MinerScoreboardEntry(
                difficulty: 2_500_100,
                jobId: "job-first",
                extranonce2: "00",
                ntime: UInt32(timestamp.timeIntervalSince1970),
                nonce: "01",
                versionBits: "00000000",
                coin: "BTC",
                poolIndex: 0
            )]
        )

        let pollingInserted = await db.recordPollingBestShareAchievement(
            minerId: minerId,
            timestamp: timestamp.addingTimeInterval(1),
            difficulty: 2_500_000
        )
        XCTAssertFalse(pollingInserted)
        let shares = await db.getAchievements(minerId: minerId, eventType: "best_share")
        XCTAssertEqual(shares.count, 1)
        XCTAssertTrue(shares.first?.metadata?.contains("\"source\":\"scoreboard\"") == true)
    }

    @MainActor
    func testScoreboardJobIDWildcardsDoNotCreateFalseDeduplication() async throws {
        let db = MinerTelemetryDatabase(databaseQueue: try DatabaseQueue())
        let minerId = UUID().uuidString
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let firstInserted = await db.reconcileScoreboard(
            minerId: minerId,
            entries: [MinerScoreboardEntry(
                difficulty: 2_500_000,
                jobId: "job-existing",
                extranonce2: "00",
                ntime: UInt32(timestamp.timeIntervalSince1970),
                nonce: "01",
                versionBits: "00000000",
                coin: "BTC",
                poolIndex: 0
            )]
        )
        XCTAssertEqual(firstInserted, 1)

        let wildcardInserted = await db.reconcileScoreboard(
            minerId: minerId,
            entries: [MinerScoreboardEntry(
                difficulty: 2_600_000,
                jobId: "job%_",
                extranonce2: "00",
                ntime: UInt32(timestamp.addingTimeInterval(1).timeIntervalSince1970),
                nonce: "02",
                versionBits: "00000000",
                coin: "BTC",
                poolIndex: 0
            )]
        )

        XCTAssertEqual(wildcardInserted, 1)
        let shares = await db.getAchievements(minerId: minerId, eventType: "best_share")
        XCTAssertEqual(shares.count, 2)
        XCTAssertTrue(shares.contains { $0.metadata?.contains("\"jobId\":\"job%_\"") == true })
    }

    @MainActor
    func testCleanupRemovesLegacyAbbreviatedPollingDuplicate() async throws {
        let db = MinerTelemetryDatabase(databaseQueue: try DatabaseQueue())
        let minerId = UUID().uuidString
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        await db.recordAchievement(
            minerId: minerId,
            eventType: "best_share",
            timestamp: timestamp,
            difficulty: "2.5M"
        )
        await db.recordAchievement(
            minerId: minerId,
            eventType: "best_share",
            timestamp: timestamp.addingTimeInterval(1),
            difficulty: "2500100",
            metadata: ["kind": "allTime", "source": "scoreboard", "jobId": "job-legacy"]
        )
        await db.recordAchievement(
            minerId: minerId,
            eventType: "best_share",
            timestamp: timestamp.addingTimeInterval(2),
            difficulty: "3.1M"
        )

        let deleted = await db.purgePollingDuplicatesOfScoreboardAchievements()

        XCTAssertEqual(deleted, 1)
        let shares = await db.getAchievements(minerId: minerId, eventType: "best_share")
        XCTAssertEqual(shares.count, 2)
        XCTAssertEqual(Set(shares.compactMap(\.difficulty)), ["2500100", "3.1M"])
        let secondPass = await db.purgePollingDuplicatesOfScoreboardAchievements()
        XCTAssertEqual(secondPass, 0)
    }

    @MainActor
    func testScoreboardImmediatelyReplacesLegacyAbbreviatedPollingRow() async throws {
        let db = MinerTelemetryDatabase(databaseQueue: try DatabaseQueue())
        let minerId = UUID().uuidString
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        await db.recordAchievement(
            minerId: minerId,
            eventType: "best_share",
            timestamp: timestamp,
            difficulty: "2.5M"
        )

        let inserted = await db.reconcileScoreboard(
            minerId: minerId,
            entries: [MinerScoreboardEntry(
                difficulty: 2_500_100,
                jobId: "job-replaces-legacy",
                extranonce2: "00",
                ntime: UInt32(timestamp.timeIntervalSince1970),
                nonce: "01",
                versionBits: "00000000",
                coin: "BTC",
                poolIndex: 0
            )]
        )

        XCTAssertEqual(inserted, 1)
        let shares = await db.getAchievements(minerId: minerId, eventType: "best_share")
        XCTAssertEqual(shares.count, 1)
        XCTAssertEqual(shares.first?.difficulty, "2500100")
        XCTAssertTrue(shares.first?.metadata?.contains("\"source\":\"scoreboard\"") == true)
    }

    @MainActor
    func testPruningRemovesOldData() async throws {
        let dbQueue = try DatabaseQueue()
        let db = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let testMinerId = UUID().uuidString
        let now = Date()
        let oldDate = now.addingTimeInterval(-40 * 24 * 60 * 60) // 40 days ago
        let recentDate = now.addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago

        // Write old reading
        db.recordReading(
            minerId: testMinerId,
            timestamp: oldDate,
            reading: MinerReadingInput(hashrate: 1000.0)
        )

        // Write recent reading
        db.recordReading(
            minerId: testMinerId,
            timestamp: recentDate,
            reading: MinerReadingInput(hashrate: 1200.0)
        )

        await db.flushReadings()

        // Prune data older than 30 days
        await db.pruneOldReadings(olderThan: 30)

        // Query all data
        let allData = await db.getHashrateReadings(
            minerId: testMinerId,
            since: oldDate.addingTimeInterval(-60),
            until: now
        )

        XCTAssertEqual(allData.count, 1, "Only recent reading should remain after pruning")
        XCTAssertEqual(allData.first?.hashrate ?? 0, 1200.0, accuracy: 0.1)
    }

    @MainActor
    func testClearAllDataWorks() async throws {
        let dbQueue = try DatabaseQueue()
        let db = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let testMinerId = UUID().uuidString
        let testDate = Date()

        // Write some data
        db.recordReading(
            minerId: testMinerId,
            timestamp: testDate,
            reading: MinerReadingInput(hashrate: 1250.0)
        )

        await db.recordAchievement(
            minerId: testMinerId,
            eventType: "block_found",
            timestamp: testDate
        )

        await db.flushReadings()

        // Verify data exists
        let dataBeforeClear = await db.getHashrateReadings(
            minerId: testMinerId,
            since: testDate.addingTimeInterval(-60),
            until: testDate.addingTimeInterval(60)
        )
        XCTAssertEqual(dataBeforeClear.count, 1)

        // Clear all data
        await db.clearAllData()

        // Verify data is gone
        let dataAfterClear = await db.getHashrateReadings(
            minerId: testMinerId,
            since: testDate.addingTimeInterval(-60),
            until: testDate.addingTimeInterval(60)
        )
        XCTAssertEqual(dataAfterClear.count, 0, "All data should be cleared")

        let achievementsAfterClear = await db.getAchievements(minerId: testMinerId)
        XCTAssertEqual(achievementsAfterClear.count, 0, "All achievements should be cleared")
    }

    @MainActor
    func testDeduplicateBestShareKeepsEarliestPerDifficulty() async throws {
        let dbQueue = try DatabaseQueue()
        let db = MinerTelemetryDatabase(databaseQueue: dbQueue)

        let minerA = UUID().uuidString
        let minerB = UUID().uuidString
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        // Miner A logged the SAME record share three times (reset/flash re-fires).
        await db.recordAchievement(
            minerId: minerA, eventType: "best_share", timestamp: t0, difficulty: "5000000")
        await db.recordAchievement(
            minerId: minerA, eventType: "best_share", timestamp: t0.addingTimeInterval(3600), difficulty: "5000000")
        await db.recordAchievement(
            minerId: minerA, eventType: "best_share", timestamp: t0.addingTimeInterval(7200), difficulty: "5000000")
        // A genuinely higher record on the same miner must be kept.
        await db.recordAchievement(
            minerId: minerA, eventType: "best_share", timestamp: t0.addingTimeInterval(9000), difficulty: "9000000")
        // Same numeric value on a different miner is a distinct record and must be kept.
        await db.recordAchievement(
            minerId: minerB, eventType: "best_share", timestamp: t0.addingTimeInterval(60), difficulty: "5000000")
        // A block-found row must never be touched by best-share dedupe.
        await db.recordAchievement(
            minerId: minerA, eventType: "block_found", timestamp: t0, blockHeight: 42, difficulty: nil)

        let deleted = await db.deduplicateBestShareAchievements()
        XCTAssertEqual(deleted, 2, "The two later 5M repeats on miner A should be removed")

        let aShares = await db.getAchievements(minerId: minerA, eventType: "best_share")
        XCTAssertEqual(aShares.count, 2, "Miner A keeps one 5M and one 9M")
        XCTAssertEqual(Set(aShares.map { $0.difficulty }), ["5000000", "9000000"])
        // The kept 5M row is the earliest one.
        let kept5M = aShares.first { $0.difficulty == "5000000" }
        XCTAssertEqual(kept5M?.timestamp.timeIntervalSince1970, t0.timeIntervalSince1970)

        let bShares = await db.getAchievements(minerId: minerB, eventType: "best_share")
        XCTAssertEqual(bShares.count, 1, "Different miner's identical value is untouched")

        let blocks = await db.getAchievements(minerId: minerA, eventType: "block_found")
        XCTAssertEqual(blocks.count, 1, "Block-found rows are untouched")

        // Idempotent: a second pass deletes nothing.
        let secondPass = await db.deduplicateBestShareAchievements()
        XCTAssertEqual(secondPass, 0, "Dedupe is idempotent")
    }
}
