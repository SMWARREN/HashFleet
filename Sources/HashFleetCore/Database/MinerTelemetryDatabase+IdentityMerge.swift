import Foundation
import GRDB

public enum MinerAchievementMergeError: Error, Sendable {
    case invalidIdentity
}

extension MinerTelemetryDatabase {
    /// Moves achievement identity without changing row IDs or losing distinct event fields.
    /// Only byte-identical events, including their timestamp and nullable fields, coalesce.
    /// GRDB commits both statements together or rolls both back on failure.
    @discardableResult
    public func mergeAchievementsChecked(
        fromMinerId source: String, intoMinerId target: String
    ) async throws -> (moved: Int, coalesced: Int) {
        guard let sourceID = UUID(uuidString: source), let targetID = UUID(uuidString: target),
              sourceID != targetID else {
            throw MinerAchievementMergeError.invalidIdentity
        }
        guard let queue = dbQueue else { throw MinerTelemetryDatabaseError.unavailable }
        return try await queue.write { db in
            try db.execute(
                sql: """
                DELETE FROM achievement_events AS source
                WHERE source.miner_id = ? AND EXISTS (
                    SELECT 1 FROM achievement_events AS target
                    WHERE target.miner_id = ?
                      AND target.event_type = source.event_type
                      AND target.timestamp = source.timestamp
                      AND target.block_height IS source.block_height
                      AND target.difficulty IS source.difficulty
                      AND target.metadata IS source.metadata
                )
                """,
                arguments: [source, target]
            )
            let coalesced = db.changesCount
            try db.execute(
                sql: "UPDATE achievement_events SET miner_id = ? WHERE miner_id = ?",
                arguments: [target, source]
            )
            return (moved: db.changesCount, coalesced: coalesced)
        }
    }
}
