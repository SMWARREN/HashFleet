import Foundation
import Testing
import GRDB
@testable import HashFleetCore

@MainActor
struct IdentityMergeTests {
    @Test func onlyExactEventsCoalesceAndAllDistinctFieldsAndRowIDsSurvive() async throws {
        let queue = try DatabaseQueue()
        let database = MinerTelemetryDatabase(databaseQueue: queue)
        let source = UUID().uuidString
        let target = UUID().uuidString
        try await queue.write { db in
            for (id, miner, timestamp, height, difficulty, metadata) in [
                (1, target, 10, nil as Int?, "100" as String?, nil as String?),
                (2, source, 10, nil, "100", nil),
                (3, source, 11, nil, "100", nil),
                (4, source, 10, nil, "100", "different metadata"),
                (5, source, 12, 500, nil, nil),
                (6, target, 13, 500, nil, nil),
                (7, source, 14, nil, nil, nil),
                (8, target, 14, nil, nil, nil)
            ] {
                try db.execute(
                    sql: "INSERT INTO achievement_events (id, miner_id, event_type, timestamp, block_height, difficulty, metadata) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    arguments: [id, miner, difficulty == nil ? "block_found" : "best_share", timestamp, height, difficulty, metadata]
                )
            }
        }
        let result = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: target)
        #expect(result.moved == 3)
        #expect(result.coalesced == 2)
        let ids = try await queue.read { try Int.fetchAll($0, sql: "SELECT id FROM achievement_events ORDER BY id") }
        #expect(ids == [1, 3, 4, 5, 6, 8])
        let remainingSource = try await queue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM achievement_events WHERE miner_id = ?", arguments: [source])
        }
        #expect(remainingSource == 0)
        let distinctRows = try await queue.read {
            try Int.fetchOne(
                $0,
                sql: "SELECT COUNT(*) FROM achievement_events WHERE miner_id = ? AND "
                    + "(timestamp = 11 OR metadata = 'different metadata' OR (timestamp = 12 AND block_height = 500))",
                arguments: [target]
            )
        }
        #expect(distinctRows == 3)
        let repeated = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: target)
        #expect(repeated.moved == 0 && repeated.coalesced == 0)
    }

    @Test func failingTransferRollsBackEarlierCoalescing() async throws {
        let queue = try DatabaseQueue()
        let database = MinerTelemetryDatabase(databaseQueue: queue)
        let source = UUID().uuidString
        let target = UUID().uuidString
        try await queue.write { db in
            for (id, miner, timestamp) in [(1, target, 10), (2, source, 10), (3, source, 11)] {
                try db.execute(
                    sql: "INSERT INTO achievement_events (id, miner_id, event_type, timestamp) VALUES (?, ?, 'future_event', ?)",
                    arguments: [id, miner, timestamp]
                )
            }
            try db.execute(sql: """
                CREATE TRIGGER reject_identity_transfer BEFORE UPDATE OF miner_id ON achievement_events
                BEGIN SELECT RAISE(ABORT, 'injected merge failure'); END
                """)
        }
        do {
            _ = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: target)
            Issue.record("Injected update failure must reject the merge")
        } catch {
            #expect(error is DatabaseError)
        }
        let rows = try await queue.read { db in
            try String.fetchAll(db, sql: "SELECT miner_id FROM achievement_events ORDER BY id")
        }
        #expect(rows == [target, source, source])
    }

    @Test func invalidIdentityAndUnavailableStorageDoNotSucceed() async throws {
        let database = MinerTelemetryDatabase(inMemory: true)
        let source = UUID().uuidString
        for target in [source, ""] {
            do {
                _ = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: target)
                Issue.record("Self and invalid merges must be rejected")
            } catch {
                #expect(error is MinerAchievementMergeError)
            }
        }
        let queue = try DatabaseQueue()
        try queue.close()
        let unavailable = MinerTelemetryDatabase(databaseQueue: queue)
        do {
            _ = try await unavailable.mergeAchievementsChecked(fromMinerId: source, intoMinerId: UUID().uuidString)
            Issue.record("Unavailable storage cannot report a committed merge")
        } catch {
            #expect(error is MinerTelemetryDatabaseError)
        }
    }
}
