import XCTest
import GRDB
@testable import HashFleetCore

/// Behavior coverage for `MinerTelemetryDatabase+Maintenance` (and its `+Connectivity`
/// collaborators that the same maintenance flows prune). Every test drives a real, isolated
/// in-memory GRDB `DatabaseQueue` through the public maintenance API and asserts the resulting
/// persisted rows, so nothing touches a real fleet database and no cleanup of shared state is
/// required beyond dropping the instance.
///
/// These fixtures cover phantom, orphaned, and session-best achievement cleanup,
/// chronological-best recomputation, duplicate removal, pruning of connectivity and
/// pool-switch history, and clearing buffered readings. Assertions inspect real persisted
/// rows after each operation. They do not exercise disk sizing or forced database errors.
@MainActor
final class DatabaseMaintenanceCoverageTests: XCTestCase {

    // MARK: - Helpers

    private func makeDatabase() throws -> MinerTelemetryDatabase {
        MinerTelemetryDatabase(databaseQueue: try DatabaseQueue())
    }

    private func insertAchievement(
        _ db: MinerTelemetryDatabase,
        minerId: String,
        type: String,
        at timestamp: Date,
        blockHeight: Int? = nil,
        difficulty: String? = nil,
        metadata: [String: Any]? = nil
    ) async {
        await db.recordAchievement(
            minerId: minerId,
            eventType: type,
            timestamp: timestamp,
            blockHeight: blockHeight,
            difficulty: difficulty,
            metadata: metadata
        )
    }

    private func bestShareCount(
        _ db: MinerTelemetryDatabase, minerId: String
    ) async -> Int {
        await db.getAchievements(minerId: minerId, eventType: "best_share").count
    }

    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - purgePhantomBlockAchievements

    func testPurgePhantomBlocksDeletesOnlyCounterResetRowsWithoutHeight() async throws {
        let db = try makeDatabase()
        let minerId = UUID().uuidString
        let base = Self.epoch

        // A genuine solve always carries a block height.
        await insertAchievement(db, minerId: minerId, type: "block_found", at: base, blockHeight: 850_001)
        // Counter-reset phantoms from a power cycle/reflash never do.
        await insertAchievement(db, minerId: minerId, type: "block_found", at: base.addingTimeInterval(60))
        await insertAchievement(db, minerId: minerId, type: "block_found", at: base.addingTimeInterval(120))
        // Best-share rows are out of scope for this purge.
        await insertAchievement(db, minerId: minerId, type: "best_share", at: base, difficulty: "1000")

        let deleted = await db.purgePhantomBlockAchievements()

        XCTAssertEqual(deleted, 2, "Only the two height-less block rows are phantom")
        let blocks = await db.getAchievements(minerId: minerId, eventType: "block_found")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.blockHeight, 850_001, "The genuine solve survives")
        let shares = await db.getAchievements(minerId: minerId, eventType: "best_share")
        XCTAssertEqual(shares.count, 1, "Best-share rows are untouched")
    }

    func testPurgePhantomBlocksIsIdempotentAndNoOpWithoutPhantoms() async throws {
        let db = try makeDatabase()
        let minerId = UUID().uuidString

        let deletedOnEmpty = await db.purgePhantomBlockAchievements()
        XCTAssertEqual(deletedOnEmpty, 0, "Empty database: nothing to purge")

        await insertAchievement(
            db, minerId: minerId, type: "block_found", at: Self.epoch, blockHeight: 42)
        let second = await db.purgePhantomBlockAchievements()
        XCTAssertEqual(second, 0, "A database with only genuine solves is a no-op")
    }

    func testPurgeOrphanedAchievementsKeepsOnlySurvivingFleetMiners() async throws {
        let db = try makeDatabase()
        let survivor = UUID().uuidString
        let duplicateAddressCopy = UUID().uuidString
        let removedMiner = UUID().uuidString
        let base = Self.epoch

        for miner in [survivor, duplicateAddressCopy, removedMiner] {
            await insertAchievement(
                db, minerId: miner, type: "block_found", at: base, blockHeight: 900_000)
            await insertAchievement(
                db, minerId: miner, type: "best_share", at: base.addingTimeInterval(1), difficulty: "2000")
        }

        let deleted = await db.purgeOrphanedAchievements(keepingMinerIds: [survivor])

        XCTAssertEqual(deleted, 4, "Two orphaned miners x two achievements each")
        let keptBlocks = await db.getAchievements(minerId: survivor, eventType: "block_found")
        let keptShares = await db.getAchievements(minerId: survivor, eventType: "best_share")
        XCTAssertEqual(keptBlocks.count, 1)
        XCTAssertEqual(keptShares.count, 1)
        for orphan in [duplicateAddressCopy, removedMiner] {
            let remaining = await db.getAchievements(minerId: orphan)
            XCTAssertEqual(remaining.count, 0, "Orphan \(orphan) rows must be gone")
        }
    }

    func testPurgeOrphanedAchievementsRefusesEmptyFleetGuard() async throws {
        let db = try makeDatabase()
        let minerId = UUID().uuidString
        await insertAchievement(
            db, minerId: minerId, type: "block_found", at: Self.epoch, blockHeight: 1)

        // An empty keep-set means the device table was not consulted; deleting everything
        // would erase real achievements, so the guard must decline.
        let deleted = await db.purgeOrphanedAchievements(keepingMinerIds: [])
        XCTAssertEqual(deleted, 0)
        let remaining = await db.getAchievements(minerId: minerId)
        XCTAssertEqual(remaining.count, 1, "Nothing was deleted by the empty-set guard")
    }

    // MARK: - purgeSessionBestShareAchievements

    func testPurgeSessionBestShareDeletesSessionKindOnlyAndKeepsLegacyRows() async throws {
        let db = try makeDatabase()
        let minerId = UUID().uuidString
        let base = Self.epoch

        // All-time record: permanent, always kept.
        await insertAchievement(
            db, minerId: minerId, type: "best_share", at: base, difficulty: "5000",
            metadata: ["kind": "allTime"])
        // Session-best rows: new high since last reboot, frequently lower than the all-time.
        await insertAchievement(
            db, minerId: minerId, type: "best_share", at: base.addingTimeInterval(60), difficulty: "3000",
            metadata: ["kind": "session"])
        await insertAchievement(
            db, minerId: minerId, type: "best_share", at: base.addingTimeInterval(120), difficulty: "2000",
            metadata: ["kind": "session"])
        // Pre-`kind` rows have no metadata: legacy all-time behavior, left alone.
        await insertAchievement(
            db, minerId: minerId, type: "best_share", at: base.addingTimeInterval(180), difficulty: "1000")
        // A block row with a session-looking metadata string in another event type stays.
        await insertAchievement(
            db, minerId: minerId, type: "block_found", at: base.addingTimeInterval(200), blockHeight: 5,
            metadata: ["kind": "session"])

        let deleted = await db.purgeSessionBestShareAchievements()

        XCTAssertEqual(deleted, 2, "Only best_share rows tagged kind:session are removed")
        let shares = await db.getAchievements(minerId: minerId, eventType: "best_share")
        XCTAssertEqual(shares.count, 2)
        XCTAssertEqual(
            Set(shares.compactMap(\.difficulty)), ["5000", "1000"],
            "All-time and legacy rows survive")
        let blocks = await db.getAchievements(minerId: minerId, eventType: "block_found")
        XCTAssertEqual(blocks.count, 1, "Block rows are not in scope of this purge")
    }

    func testPurgeSessionBestShareIsIdempotent() async throws {
        let db = try makeDatabase()
        let minerId = UUID().uuidString
        await insertAchievement(
            db, minerId: minerId, type: "best_share", at: Self.epoch, difficulty: "10",
            metadata: ["kind": "session"])

        let firstPurge = await db.purgeSessionBestShareAchievements()
        XCTAssertEqual(firstPurge, 1)
        let secondPurge = await db.purgeSessionBestShareAchievements()
        XCTAssertEqual(secondPurge, 0, "Second pass is a no-op")
    }

    // MARK: - recomputeChronologicalBestShareRecords

    func testRecomputeChronologicalRecordsKeepsStrictNewHighsOnly() async throws {
        let db = try makeDatabase()
        let minerA = UUID().uuidString
        let minerB = UUID().uuidString
        let base = Self.epoch

        // Miner A: the documented non-monotonic import (128M followed later by 14M).
        await insertAchievement(
            db, minerId: minerA, type: "best_share", at: base, difficulty: "128000000")
        await insertAchievement(
            db, minerId: minerA, type: "best_share", at: base.addingTimeInterval(3600), difficulty: "14000000")
        // Equal difficulty repeated is not a new high either.
        await insertAchievement(
            db, minerId: minerA, type: "best_share", at: base.addingTimeInterval(7200), difficulty: "128000000")
        // A later genuine record re-opens the sequence.
        await insertAchievement(
            db, minerId: minerA, type: "best_share", at: base.addingTimeInterval(9000), difficulty: "256000000")
        // Unparseable difficulty rows are skipped, never deleted by this pass.
        await insertAchievement(
            db, minerId: minerA, type: "best_share", at: base.addingTimeInterval(9500), difficulty: "not-a-number")
        // Miner B is fully monotonic from the start: nothing to delete.
        await insertAchievement(
            db, minerId: minerB, type: "best_share", at: base, difficulty: "5000")
        await insertAchievement(
            db, minerId: minerB, type: "best_share", at: base.addingTimeInterval(60), difficulty: "9000")
        // Block rows are not best-share records and stay.
        await insertAchievement(
            db, minerId: minerA, type: "block_found", at: base.addingTimeInterval(10), blockHeight: 7)

        let deleted = await db.recomputeChronologicalBestShareRecords()

        XCTAssertEqual(deleted, 2, "The 14M dip and the repeated 128M on miner A are not records")

        let aShares = await db.getAchievements(minerId: minerA, eventType: "best_share")
        XCTAssertEqual(
            Set(aShares.compactMap(\.difficulty)),
            ["128000000", "256000000", "not-a-number"],
            "Only strict new highs plus the unparseable row remain")
        let aBlocks = await db.getAchievements(minerId: minerA, eventType: "block_found")
        XCTAssertEqual(aBlocks.count, 1, "Block-found rows are untouched")

        let bShares = await bestShareCount(db, minerId: minerB)
        XCTAssertEqual(bShares, 2, "Miner B was already monotonic")

        // A correct history is a no-op on re-run.
        let secondPass = await db.recomputeChronologicalBestShareRecords()
        XCTAssertEqual(secondPass, 0, "Recompute is idempotent")
    }

    func testRecomputeChronologicalRecordsTreatsLegacyAbbreviationsAsValues() async throws {
        let db = try makeDatabase()
        let minerId = UUID().uuidString
        let base = Self.epoch

        // Older app builds wrote abbreviated difficulties; the high-water mark must parse
        // them so a later smaller plain-number row is recognized as a non-record.
        await insertAchievement(
            db, minerId: minerId, type: "best_share", at: base, difficulty: "2.5M")
        await insertAchievement(
            db, minerId: minerId, type: "best_share", at: base.addingTimeInterval(60), difficulty: "100000")

        let deleted = await db.recomputeChronologicalBestShareRecords()
        XCTAssertEqual(deleted, 1, "100K after a 2.5M record is not a new high")

        let shares = await db.getAchievements(minerId: minerId, eventType: "best_share")
        XCTAssertEqual(shares.compactMap(\.difficulty), ["2.5M"])
    }

    // MARK: - clearAllData

    func testClearAllDataDropsPendingReadingsBufferAndEveryEventTable() async throws {
        let db = try makeDatabase()
        let minerId = UUID().uuidString
        let now = Date()

        // Buffered (not yet flushed) readings must be discarded by clearAllData too,
        // otherwise they would be flushed to the "cleared" database afterwards.
        db.recordReading(minerId: minerId, timestamp: now, reading: MinerReadingInput(hashrate: 10))
        await insertAchievement(
            db, minerId: minerId, type: "block_found", at: now, blockHeight: 3)
        await db.recordConnectivityEvent(
            minerId: minerId, eventType: "offline", timestamp: now, errorMessage: "unreachable")
        await db.recordPoolSwitch(
            minerId: minerId, timestamp: now, fromPool: "old", toPool: "new",
            poolIndex: 1, isFallback: false)

        try await db.clearAllDataChecked()

        // The pending buffer was cleared: flushing now writes nothing.
        await db.flushReadings()
        let readings = await db.getHashrateReadings(
            minerId: minerId, since: now.addingTimeInterval(-60), until: now.addingTimeInterval(60))
        XCTAssertEqual(readings.count, 0, "No reading rows after clear, including buffered ones")
        let achievements = await db.getAchievements(minerId: minerId)
        XCTAssertEqual(achievements.count, 0)
        let connectivity = await db.getConnectivityEvents(minerId: minerId)
        XCTAssertEqual(connectivity.count, 0)
        let switches = await db.getPoolSwitches(minerId: minerId)
        XCTAssertEqual(switches.count, 0)
    }

    // MARK: - pruneOldReadings also prunes connectivity and pool switches

    func testPruneOldReadingsAlsoPrunesConnectivityAndPoolSwitchHistory() async throws {
        let db = try makeDatabase()
        let minerId = UUID().uuidString
        let now = Date()
        let fortyDaysAgo = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let tenDaysAgo = now.addingTimeInterval(-10 * 24 * 60 * 60)

        db.recordReading(minerId: minerId, timestamp: fortyDaysAgo, reading: MinerReadingInput(hashrate: 5))
        db.recordReading(minerId: minerId, timestamp: tenDaysAgo, reading: MinerReadingInput(hashrate: 6))
        await db.flushReadings()
        await db.recordConnectivityEvent(minerId: minerId, eventType: "offline", timestamp: fortyDaysAgo)
        await db.recordConnectivityEvent(minerId: minerId, eventType: "online", timestamp: tenDaysAgo)
        await db.recordPoolSwitch(
            minerId: minerId, timestamp: fortyDaysAgo, fromPool: nil, toPool: "solo", poolIndex: 0, isFallback: true)
        await db.recordPoolSwitch(
            minerId: minerId, timestamp: tenDaysAgo, fromPool: "solo", toPool: "pool", poolIndex: 1, isFallback: false)

        await db.pruneOldReadings(olderThan: 30)

        let readings = await db.getHashrateReadings(
            minerId: minerId, since: fortyDaysAgo.addingTimeInterval(-60), until: now)
        XCTAssertEqual(readings.count, 1, "Only the recent reading survives")

        let connectivity = await db.getConnectivityEvents(minerId: minerId)
        XCTAssertEqual(connectivity.count, 1, "Only the recent connectivity event survives")
        XCTAssertEqual(connectivity.first?.eventType, "online")

        let switches = await db.getPoolSwitches(minerId: minerId)
        XCTAssertEqual(switches.count, 1, "Only the recent pool switch survives")
        XCTAssertEqual(switches.first?.toPool, "pool")
    }

    // MARK: - empty in-memory maintenance calls

    func testGuardedMaintenanceIsNoOpForEmptyInMemoryDatabase() async throws {
        // This is a valid, schema-initialized GRDB memory queue. These assertions cover empty
        // database behavior, not an unavailable-queue catch arm.
        let db = try makeDatabase()

        let phantomBlocks = await db.purgePhantomBlockAchievements()
        XCTAssertEqual(phantomBlocks, 0)
        let orphaned = await db.purgeOrphanedAchievements(keepingMinerIds: [UUID().uuidString])
        XCTAssertEqual(orphaned, 0)
        let deduplicated = await db.deduplicateBestShareAchievements()
        XCTAssertEqual(deduplicated, 0)
        let sessionPurged = await db.purgeSessionBestShareAchievements()
        XCTAssertEqual(sessionPurged, 0)
        let pollingPurged = await db.purgePollingDuplicatesOfScoreboardAchievements()
        XCTAssertEqual(pollingPurged, 0)
        let recomputed = await db.recomputeChronologicalBestShareRecords()
        XCTAssertEqual(recomputed, 0)
    }
}
