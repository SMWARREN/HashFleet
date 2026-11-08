import Foundation
import GRDB

// MARK: - Maintenance

extension MinerTelemetryDatabase {
    /// Rows deleted by one prune before a VACUUM is worth its full-file rewrite.
    static let vacuumThreshold = 5_000

    /// Delete readings older than retention period
    public func pruneOldReadings(olderThan days: Int) async {
        let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 60 * 60))

        do {
            let queue = await self.preparedQueue()
            let deleted = try await queue?.write { db -> Int in
                var removed = 0
                try db.execute(
                    sql: "DELETE FROM miner_readings WHERE timestamp < ?",
                    arguments: [Int(cutoffDate.timeIntervalSince1970)]
                )
                removed += db.changesCount
                try db.execute(
                    sql: "DELETE FROM connectivity_events WHERE timestamp < ?",
                    arguments: [Int(cutoffDate.timeIntervalSince1970)]
                )
                removed += db.changesCount
                try db.execute(
                    sql: "DELETE FROM pool_switches WHERE timestamp < ?",
                    arguments: [Int(cutoffDate.timeIntervalSince1970)]
                )
                removed += db.changesCount
                return removed
            } ?? 0

            // VACUUM rewrites the whole file and blocks every other read and write meanwhile.
            // This runs on each foreground activation, so only reclaim space when pruning
            // actually freed a meaningful amount.
            if deleted >= Self.vacuumThreshold {
                try await queue?.vacuum()
            }

            print("✅ Pruned telemetry data older than \(days) days")
        } catch {
            print("❌ Failed to prune old data: \(error)")
        }
    }

    /// Approximate on-disk footprint, including WAL and shared-memory sidecars.
    /// File sizes may change between reads; this is not a transactional snapshot.
    public func getDatabaseSize() async -> Int64 {
        guard let writer = await preparedQueue() else { return 0 }
        let path = writer.path
        return await Task.detached(priority: .utility) {
            [path, path + "-wal", path + "-shm"].reduce(Int64(0)) { total, file in
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: file),
                      let size = attributes[.size] as? Int64 else { return total }
                return total + size
            }
        }.value
    }

    /// Clear all telemetry data
    public func clearAllData() async {
        do {
            try await clearAllDataChecked()
        } catch {
            print("❌ Failed to clear data: \(error)")
        }
    }

    /// Clears persisted telemetry after the delete transaction succeeds. Vacuum is a best-effort
    /// space-reclamation step outside the transaction, so a vacuum failure is reported without
    /// falsely claiming that the delete failed or leaving already-deleted readings in memory.
    /// Pending in-memory readings are retained when the delete transaction itself fails.
    public func clearAllDataChecked() async throws {
        await acquireReadingsMutation()
        defer { releaseReadingsMutation() }
        guard let queue = await self.preparedQueue() else { throw MinerTelemetryDatabaseError.unavailable }
        try await queue.write { db in
            try db.execute(sql: "DELETE FROM miner_readings")
            try db.execute(sql: "DELETE FROM achievement_events")
            try db.execute(sql: "DELETE FROM connectivity_events")
            try db.execute(sql: "DELETE FROM pool_switches")
        }

        pendingReadings.removeAll()
        do {
            // Vacuum reclaims space but is intentionally outside the delete transaction.
            try await queue.vacuum()
        } catch {
            print("⚠️ Telemetry data was cleared, but database vacuum failed: \(error)")
        }
        print("✅ Cleared all telemetry data")
    }

    /// Removes phantom `block_found` achievements recorded before the reboot/real-solve guard
    /// existed. The firmware `blockFound` counter resets to 0 on every reboot and re-climbs, so a
    /// power-cycle or reflash previously logged a false block. A genuine solve always carries a
    /// `block_height`; the counter-reset phantoms never do. Returns the number of rows deleted.
    @discardableResult
    public func purgePhantomBlockAchievementsChecked() async throws -> Int {
        do {
            guard let queue = await self.preparedQueue() else { throw MinerTelemetryDatabaseError.unavailable }
            let deleted = try await queue.write { db -> Int in
                try db.execute(
                    sql: """
                    DELETE FROM achievement_events
                    WHERE event_type = 'block_found' AND block_height IS NULL
                    """
                )
                return db.changesCount
            }
            if deleted > 0 {
                print("✅ Purged \(deleted) phantom block-found achievement(s)")
            }
            return deleted
        } catch {
            print("❌ Failed to purge phantom block achievements: \(error)")
            throw error
        }
    }

    /// Removes duplicate `best_share` achievements created before the monotonic high-water-mark
    /// guard existed. A miner reset/flash wiped the firmware `bestDiff`, so the same record share
    /// re-fired and was logged again at a later timestamp (the same value at different times).
    /// Keeps the earliest row for each (miner_id, difficulty) best-share and deletes the later
    /// repeats. Rows with a NULL difficulty are left untouched. Returns the number of rows deleted.
    @discardableResult
    public func deduplicateBestShareAchievementsChecked() async throws -> Int {
        do {
            guard let queue = await self.preparedQueue() else { throw MinerTelemetryDatabaseError.unavailable }
            let deleted = try await queue.write { db -> Int in
                try db.execute(
                    sql: """
                    DELETE FROM achievement_events
                    WHERE event_type = 'best_share'
                      AND difficulty IS NOT NULL
                      AND id NOT IN (
                        SELECT MIN(id) FROM achievement_events
                        WHERE event_type = 'best_share' AND difficulty IS NOT NULL
                        GROUP BY miner_id, difficulty
                      )
                    """
                )
                return db.changesCount
            }
            if deleted > 0 {
                print("✅ Removed \(deleted) duplicate best-share achievement(s)")
            }
            return deleted
        } catch {
            print("❌ Failed to deduplicate best-share achievements: \(error)")
            throw error
        }
    }

    /// Removes achievement rows for miners that no longer exist in the fleet. A device added
    /// under two addresses (its IP and its mDNS hostname, e.g. Naja Duo boards) got its own UUID
    /// and independently logged the same block-found/best-share achievement before
    /// `deduplicateDevicesByMAC()` collapsed the duplicate device — leaving the orphaned copy's
    /// achievement forever visible alongside the surviving device's copy. Returns rows deleted.
    @discardableResult
    public func purgeOrphanedAchievementsChecked(keepingMinerIds: Set<String>) async throws -> Int {
        guard !keepingMinerIds.isEmpty else { return 0 }
        do {
            guard let queue = await self.preparedQueue() else { throw MinerTelemetryDatabaseError.unavailable }
            let deleted = try await queue.write { db -> Int in
                let placeholders = Array(repeating: "?", count: keepingMinerIds.count).joined(separator: ", ")
                try db.execute(
                    sql: """
                    DELETE FROM achievement_events
                    WHERE miner_id NOT IN (\(placeholders))
                    """,
                    arguments: StatementArguments(Array(keepingMinerIds))
                )
                return db.changesCount
            }
            if deleted > 0 {
                print("✅ Purged \(deleted) orphaned achievement(s) for removed/duplicate miners")
            }
            return deleted
        } catch {
            print("❌ Failed to purge orphaned achievements: \(error)")
            throw error
        }
    }

    /// Removes session-best achievements. Only the all-time record is a genuine, permanent
    /// milestone; a session-best is merely a new high since the miner's last reboot/reset and is
    /// frequently *lower* than the fleet's real all-time best, so it doesn't belong in the
    /// permanent Achievements timeline (it made the timeline look duplicated with entries that
    /// weren't real records). Rows written before the `kind` metadata existed have no metadata and
    /// are treated as all-time (their old behavior) and left alone. Returns rows deleted.
    @discardableResult
    public func purgeSessionBestShareAchievementsChecked() async throws -> Int {
        do {
            guard let queue = await self.preparedQueue() else { throw MinerTelemetryDatabaseError.unavailable }
            let deleted = try await queue.write { db -> Int in
                try db.execute(
                    sql: """
                    DELETE FROM achievement_events
                    WHERE event_type = 'best_share'
                      AND metadata LIKE '%"kind":"session"%'
                    """
                )
                return db.changesCount
            }
            if deleted > 0 {
                print("✅ Purged \(deleted) session-best achievement(s), keeping all-time records only")
            }
            return deleted
        } catch {
            print("❌ Failed to purge session-best achievements: \(error)")
            throw error
        }
    }

    /// Removes best-share rows written by the app's own polling-based detection when a matching
    /// scoreboard-imported row (the miner's own authoritative firmware record) already exists for
    /// the same miner and a very close difficulty value. Both paths logged the same real share
    /// once `reconcileScoreboard()` shipped alongside the still-active polling write, so every
    /// all-time record briefly appeared twice: once as a rounded integer with no metadata, once as
    /// the precise scoreboard entry. Keeps the scoreboard row (more precise, has real timestamp
    /// and metadata) and deletes the redundant polling row. Returns rows deleted.
    @discardableResult
    public func purgePollingDuplicatesOfScoreboardAchievementsChecked() async throws -> Int {
        do {
            guard let queue = await self.preparedQueue() else { throw MinerTelemetryDatabaseError.unavailable }
            let deleted = try await queue.write { db -> Int in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, miner_id, difficulty, metadata
                    FROM achievement_events
                    WHERE event_type = 'best_share' AND difficulty IS NOT NULL
                    """
                )
                let scoreboardValues = rows.reduce(into: [String: [Double]]()) { result, row in
                    let metadata: String? = row["metadata"]
                    guard metadata?.contains("\"source\":\"scoreboard\"") == true else { return }
                    let minerId: String = row["miner_id"]
                    let rawDifficulty: String = row["difficulty"]
                    guard let difficulty = Self.parsedAchievementDifficulty(rawDifficulty) else { return }
                    result[minerId, default: []].append(difficulty)
                }

                let idsToDelete: [Int64] = rows.compactMap { row in
                    let metadata: String? = row["metadata"]
                    guard metadata?.contains("\"source\":\"scoreboard\"") != true else { return nil }
                    let minerId: String = row["miner_id"]
                    let rawDifficulty: String = row["difficulty"]
                    guard let pollingValue = Self.parsedAchievementDifficulty(rawDifficulty) else { return nil }
                    let isDuplicate = scoreboardValues[minerId, default: []].contains { scoreboardValue in
                        abs(scoreboardValue - pollingValue) < max(1.0, pollingValue * 0.0001)
                    }
                    return isDuplicate ? row["id"] : nil
                }
                guard !idsToDelete.isEmpty else { return 0 }
                let placeholders = Array(repeating: "?", count: idsToDelete.count).joined(separator: ", ")
                try db.execute(
                    sql: "DELETE FROM achievement_events WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(idsToDelete)
                )
                return idsToDelete.count
            }
            if deleted > 0 {
                print("✅ Purged \(deleted) polling-duplicate best-share achievement(s), kept scoreboard originals")
            }
            return deleted
        } catch {
            print("❌ Failed to purge polling duplicates of scoreboard achievements: \(error)")
            throw error
        }
    }

    /// Recomputes which `best_share` rows are genuine chronological all-time records and deletes
    /// the rest. The firmware scoreboard is an unordered top-N list, not a record-breaking
    /// sequence; the initial `reconcileScoreboard()` import inserted every entry verbatim, which
    /// made the Achievements timeline show non-monotonic "all-time records" (e.g. a 128M share
    /// followed later by a 14M share, both labeled all-time). This walks each miner's rows in
    /// timestamp order and keeps only the ones that were a strict new high at that point in time,
    /// deleting the rest. Safe to run repeatedly; a fully correct history is a no-op. Returns rows
    /// deleted.
    @discardableResult
    public func recomputeChronologicalBestShareRecordsChecked() async throws -> Int {
        do {
            guard let queue = await self.preparedQueue() else { throw MinerTelemetryDatabaseError.unavailable }
            let deleted = try await queue.write { db -> Int in
                let minerIds = try String.fetchAll(
                    db,
                    sql: "SELECT DISTINCT miner_id FROM achievement_events WHERE event_type = 'best_share'"
                )
                var totalDeleted = 0
                for minerId in minerIds {
                    let rows = try Row.fetchAll(
                        db,
                        sql: """
                        SELECT id, difficulty FROM achievement_events
                        WHERE miner_id = ? AND event_type = 'best_share' AND difficulty IS NOT NULL
                        ORDER BY timestamp ASC, id ASC
                        """,
                        arguments: [minerId]
                    )
                    var runningMax = -Double.infinity
                    var idsToDelete: [Int64] = []
                    for row in rows {
                        let rawDifficulty: String = row["difficulty"]
                        guard let value = Self.parsedAchievementDifficulty(rawDifficulty) else { continue }
                        if value > runningMax {
                            runningMax = value
                        } else {
                            idsToDelete.append(row["id"])
                        }
                    }
                    guard !idsToDelete.isEmpty else { continue }
                    let placeholders = Array(repeating: "?", count: idsToDelete.count).joined(separator: ", ")
                    try db.execute(
                        sql: "DELETE FROM achievement_events WHERE id IN (\(placeholders))",
                        arguments: StatementArguments(idsToDelete)
                    )
                    totalDeleted += idsToDelete.count
                }
                return totalDeleted
            }
            if deleted > 0 {
                print("✅ Removed \(deleted) non-monotonic best-share row(s), keeping the true chronological record sequence")
            }
            return deleted
        } catch {
            print("❌ Failed to recompute chronological best-share records: \(error)")
            throw error
        }
    }
}

// Existing callers retain the best-effort API. Migration completion must use the checked
// variants above so an unavailable database or failed transaction cannot look like zero rows.
extension MinerTelemetryDatabase {
    @discardableResult
    public func purgePhantomBlockAchievements() async -> Int {
        (try? await purgePhantomBlockAchievementsChecked()) ?? 0
    }

    @discardableResult
    public func deduplicateBestShareAchievements() async -> Int {
        (try? await deduplicateBestShareAchievementsChecked()) ?? 0
    }

    @discardableResult
    public func purgeOrphanedAchievements(keepingMinerIds: Set<String>) async -> Int {
        (try? await purgeOrphanedAchievementsChecked(keepingMinerIds: keepingMinerIds)) ?? 0
    }

    @discardableResult
    public func purgeSessionBestShareAchievements() async -> Int {
        (try? await purgeSessionBestShareAchievementsChecked()) ?? 0
    }

    @discardableResult
    public func purgePollingDuplicatesOfScoreboardAchievements() async -> Int {
        (try? await purgePollingDuplicatesOfScoreboardAchievementsChecked()) ?? 0
    }

    @discardableResult
    public func recomputeChronologicalBestShareRecords() async -> Int {
        (try? await recomputeChronologicalBestShareRecordsChecked()) ?? 0
    }
}
