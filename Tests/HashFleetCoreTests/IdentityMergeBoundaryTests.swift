import Foundation
import GRDB
import Testing
@testable import HashFleetCore

@MainActor
struct IdentityMergeBoundaryTests {
    @Test(arguments: 0..<9)
    func noDistinctEventFieldIsCollapsed(variant: Int) async throws {
        let queue = try DatabaseQueue()
        let database = MinerTelemetryDatabase(databaseQueue: queue)
        let source = UUID().uuidString
        let target = UUID().uuidString
        let baseline = Fields(type: "future_event", timestamp: 10, height: nil, difficulty: nil, metadata: nil)
        var distinct = baseline
        switch variant {
        case 0: distinct.type = "FUTURE_EVENT"
        case 1: distinct.timestamp += 1
        case 2: distinct.height = 0
        case 3: distinct.height = -1
        case 4: distinct.difficulty = ""
        case 5: distinct.difficulty = "0"
        case 6: distinct.metadata = ""
        case 7: distinct.metadata = "{}"
        default: distinct.metadata = "Unicode: 雪 ❄"
        }
        let before = [Event(id: 1, miner: target, fields: baseline), Event(id: 2, miner: source, fields: distinct)]
        try await seed(before, into: queue)
        let result = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: target)
        #expect(result.moved == 1 && result.coalesced == 0)
        let after = try await events(in: queue)
        #expect(after == before.map { Event(id: $0.id, miner: target, fields: $0.fields) })
    }

    @Test func emptyTargetMovesAllRowsWithoutDeletingSourceMultiplicityOrOtherMiners() async throws {
        let queue = try DatabaseQueue()
        let database = MinerTelemetryDatabase(databaseQueue: queue)
        let source = UUID().uuidString
        let target = UUID().uuidString
        let other = UUID().uuidString
        let fields = Fields(type: "future_event", timestamp: 10, height: nil, difficulty: "100", metadata: nil)
        let before = [
            Event(id: 1, miner: source, fields: fields), Event(id: 2, miner: source, fields: fields),
            Event(id: 3, miner: other, fields: fields)
        ]
        try await seed(before, into: queue)
        let result = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: target)
        #expect(result.moved == 2 && result.coalesced == 0)
        let after = try await events(in: queue)
        #expect(after.map(\.id) == [1, 2, 3])
        #expect(after.map(\.miner) == [target, target, other])
        let repeated = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: target)
        #expect(repeated.moved == 0 && repeated.coalesced == 0)
        let unchanged = try await events(in: queue)
        #expect(unchanged == after)
    }

    @Test func coalescingDoesNotRewriteExistingTargetCopies() async throws {
        let queue = try DatabaseQueue()
        let database = MinerTelemetryDatabase(databaseQueue: queue)
        let source = UUID().uuidString
        let target = UUID().uuidString
        let fields = Fields(type: "block_found", timestamp: 10, height: 500, difficulty: nil, metadata: "{}")
        let before = (1...5).map { Event(id: $0, miner: $0 <= 2 ? target : source, fields: fields) }
        try await seed(before, into: queue)
        let result = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: target)
        #expect(result.moved == 0 && result.coalesced == 3)
        let after = try await events(in: queue)
        #expect(after == Array(before.prefix(2)))
    }

    @Test func deterministicBulkMergeMatchesExactFieldOracle() async throws {
        let queue = try DatabaseQueue()
        let database = MinerTelemetryDatabase(databaseQueue: queue)
        let source = UUID().uuidString
        let target = UUID().uuidString
        let other = UUID().uuidString
        var before = (1...240).map { id -> Event in
            let key = id % 19
            return Event(
                id: id, miner: id % 17 == 0 ? other : (id % 4 == 0 ? target : source),
                fields: Fields(
                    type: key % 2 == 0 ? "block_found" : "future_event", timestamp: key / 4,
                    height: key % 3 == 0 ? nil : key,
                    difficulty: key % 5 == 0 ? nil : String(key),
                    metadata: key % 7 == 0 ? nil : "{\"fixture\":\(key)}"
                )
            )
        }
        let unique = Fields(type: "new_event", timestamp: 999, height: nil, difficulty: "0", metadata: "")
        before += [Event(id: 241, miner: source, fields: unique), Event(id: 242, miner: source, fields: unique)]
        try await seed(before, into: queue)
        let targetFields = Set(before.filter { $0.miner == target }.map(\.fields))
        let removed = before.filter { $0.miner == source && targetFields.contains($0.fields) }
        let removedIDs = Set(removed.map(\.id))
        let expected = before.filter { !removedIDs.contains($0.id) }.map {
            Event(id: $0.id, miner: $0.miner == source ? target : $0.miner, fields: $0.fields)
        }
        let result = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: target)
        let after = try await events(in: queue)
        #expect(result.coalesced == removed.count)
        #expect(result.moved == before.filter { $0.miner == source }.count - removed.count)
        #expect(after == expected)
    }

    @Test func simultaneousSourcesIntoOneTargetSerializeWithoutLosingDistinctEvents() async throws {
        let database = MinerTelemetryDatabase(inMemory: true)
        let first = UUID().uuidString
        let second = UUID().uuidString
        let target = UUID().uuidString
        await database.recordAchievement(minerId: first, eventType: "block_found", blockHeight: 100)
        await database.recordAchievement(minerId: second, eventType: "block_found", blockHeight: 101)
        let left = Task { try await database.mergeAchievementsChecked(fromMinerId: first, intoMinerId: target) }
        let right = Task { try await database.mergeAchievementsChecked(fromMinerId: second, intoMinerId: target) }
        let leftResult = try await left.value
        let rightResult = try await right.value
        #expect(leftResult.moved == 1 && rightResult.moved == 1)
        let rows = await database.getAchievements(minerId: target)
        #expect(Set(rows.compactMap(\.blockHeight)) == [100, 101])
        let firstRows = await database.getAchievements(minerId: first)
        let secondRows = await database.getAchievements(minerId: second)
        #expect(firstRows.isEmpty && secondRows.isEmpty)
    }

    @Test func closedQueueAndCaseVariantSelfIdentityAreRejected() async throws {
        let queue = try DatabaseQueue()
        let database = MinerTelemetryDatabase(databaseQueue: queue)
        let source = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        for invalidSource in ["", "invalid"] {
            do {
                _ = try await database.mergeAchievementsChecked(fromMinerId: invalidSource, intoMinerId: UUID().uuidString)
                Issue.record("Invalid source identity must fail closed")
            } catch { #expect(error is MinerAchievementMergeError) }
        }
        do {
            _ = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: source.lowercased())
            Issue.record("Case-variant self transfer must fail closed")
        } catch { #expect(error is MinerAchievementMergeError) }
        try queue.close()
        do {
            _ = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: UUID().uuidString)
            Issue.record("Closed queue must not report an empty successful merge")
        } catch { #expect(error is DatabaseError) }
    }

    @Test func transferredRowsSupportPublicQueriesAndFutureScoreboardReconciliation() async throws {
        let database = MinerTelemetryDatabase(inMemory: true)
        let source = UUID().uuidString
        let target = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = MinerScoreboardEntry(
            difficulty: 2_500_100, jobId: "transferred-job%_", extranonce2: "00",
            ntime: UInt32(date.timeIntervalSince1970), nonce: "01", versionBits: "00000000",
            coin: "BTC", poolIndex: 0)
        let inserted = await database.reconcileScoreboard(minerId: source, entries: [first])
        #expect(inserted == 1)
        let originalRows = await database.getAchievements(minerId: source, eventType: "best_share")
        let original = try #require(originalRows.first)
        let pollingInserted = await database.recordPollingBestShareAchievement(
            minerId: target, timestamp: date.addingTimeInterval(1), difficulty: 2_500_000)
        #expect(pollingInserted)
        await database.recordAchievement(
            minerId: source, eventType: "block_found", timestamp: date.addingTimeInterval(2), blockHeight: 500)

        let merged = try await database.mergeAchievementsChecked(fromMinerId: source, intoMinerId: target)
        #expect(merged.moved == 2 && merged.coalesced == 0)
        let movedRows = await database.getAchievements(minerId: target, eventType: "best_share")
        #expect(movedRows.count == 2, "Identity transfer must not semantically collapse nonidentical polling and scoreboard events")
        let staleSourceRows = await database.getAchievements(minerId: source)
        #expect(staleSourceRows.isEmpty)
        let pollingDuplicate = await database.recordPollingBestShareAchievement(
            minerId: target, timestamp: date.addingTimeInterval(3), difficulty: 2_500_000)
        #expect(!pollingDuplicate)
        let repeatedImport = await database.reconcileScoreboard(minerId: target, entries: [first])
        #expect(repeatedImport == 0)
        let reconciled = await database.getAchievements(minerId: target, eventType: "best_share")
        #expect(reconciled.count == 1)
        #expect(reconciled.first?.id == original.id)
        #expect(reconciled.first?.metadata == original.metadata)
        #expect(reconciled.first?.timestamp == original.timestamp)

        let next = MinerScoreboardEntry(
            difficulty: 3_000_000, jobId: "new-record", extranonce2: "00",
            ntime: UInt32(date.timeIntervalSince1970 + 4), nonce: "02", versionBits: "00000000",
            coin: "BTC", poolIndex: 0)
        let nextImport = await database.reconcileScoreboard(minerId: target, entries: [first, next])
        #expect(nextImport == 1)
        let shares = await database.getAllAchievements(eventType: "best_share")
        #expect(shares.count == 2)
        #expect(shares.allSatisfy { $0.minerId == target })
        #expect(shares.contains { $0.id == original.id })
        let blocks = await database.getAllAchievements(eventType: "block_found")
        #expect(blocks.count == 1 && blocks.first?.blockHeight == 500)
        #expect(blocks.first?.minerId == target)
        let latest = await database.getAllAchievements(limit: 1)
        #expect(latest.count == 1 && latest.first?.difficulty == "3000000")
    }

    private struct Fields: Hashable, Sendable {
        var type: String
        var timestamp: Int
        var height: Int?
        var difficulty: String?
        var metadata: String?
    }
    private struct Event: Equatable, Sendable {
        let id: Int
        let miner: String
        let fields: Fields
    }
    private func seed(_ events: [Event], into queue: DatabaseQueue) async throws {
        try await queue.write { db in
            for event in events {
                try db.execute(
                    sql: "INSERT INTO achievement_events (id, miner_id, event_type, timestamp, block_height, difficulty, metadata) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    arguments: [event.id, event.miner, event.fields.type, event.fields.timestamp, event.fields.height, event.fields.difficulty, event.fields.metadata]
                )
            }
        }
    }
    private func events(in queue: DatabaseQueue) async throws -> [Event] {
        try await queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM achievement_events ORDER BY id").map { row in
                Event(id: row["id"], miner: row["miner_id"], fields: Fields(
                    type: row["event_type"], timestamp: row["timestamp"], height: row["block_height"],
                    difficulty: row["difficulty"], metadata: row["metadata"]
                ))
            }
        }
    }
}
