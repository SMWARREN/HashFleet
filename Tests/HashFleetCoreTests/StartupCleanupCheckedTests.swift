import Foundation
import Testing
import GRDB
@testable import HashFleetCore

@MainActor
struct StartupCleanupCheckedTests {
    @Test func emptySuccessfulTransactionsReturnZero() async throws {
        let database = MinerTelemetryDatabase(inMemory: true)
        for operation in operations(database) {
            #expect(try await operation() == 0)
        }
    }

    @Test func transactionFailureIsNotReportedAsSuccessfulZeroRows() async throws {
        let queue = try DatabaseQueue()
        let database = MinerTelemetryDatabase(databaseQueue: queue)
        try queue.close()
        for operation in operations(database) {
            do {
                _ = try await operation()
                Issue.record("A closed database must not report successful cleanup")
            } catch {
                #expect(error is DatabaseError)
            }
        }
    }

    @Test func unavailableDatabaseRemainsAnError() async throws {
        let queue = try DatabaseQueue()
        try queue.close()
        let database = MinerTelemetryDatabase(databaseQueue: queue)
        for operation in operations(database) {
            do {
                _ = try await operation()
                Issue.record("Unavailable storage must leave cleanup retryable")
            } catch {
                #expect(error is MinerTelemetryDatabaseError)
            }
        }
    }

    private func operations(_ database: MinerTelemetryDatabase) -> [@MainActor () async throws -> Int] {
        [
            { try await database.purgePhantomBlockAchievementsChecked() },
            { try await database.deduplicateBestShareAchievementsChecked() },
            { try await database.purgeOrphanedAchievementsChecked(keepingMinerIds: ["fixture-id"]) },
            { try await database.purgeSessionBestShareAchievementsChecked() },
            { try await database.purgePollingDuplicatesOfScoreboardAchievementsChecked() },
            { try await database.recomputeChronologicalBestShareRecordsChecked() }
        ]
    }
}
