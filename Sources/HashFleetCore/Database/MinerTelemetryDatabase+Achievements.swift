import Foundation
import GRDB

// MARK: - Achievement Events

extension MinerTelemetryDatabase {
    /// Record an achievement event (block found, best share)
    public func recordAchievement(
        minerId: String,
        eventType: String,
        timestamp: Date = Date(),
        blockHeight: Int? = nil,
        difficulty: String? = nil,
        metadata: [String: Any]? = nil
    ) async {
        do {
            let metadataJSON: Data?
            if let metadata {
                metadataJSON = try? JSONSerialization.data(withJSONObject: metadata, options: [])
            } else {
                metadataJSON = nil
            }

            let queue = self.dbQueue
            try await queue?.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO achievement_events
                    (miner_id, event_type, timestamp, block_height, difficulty, metadata)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        minerId,
                        eventType,
                        Int(timestamp.timeIntervalSince1970),
                        blockHeight,
                        difficulty,
                        metadataJSON.flatMap { String(data: $0, encoding: .utf8) }
                    ]
                )
            }
        } catch {
            print("❌ Failed to record achievement: \(error)")
        }
    }

    /// Formats a scoreboard difficulty to match the plain numeric-string style already stored for
    /// polling-derived best-share achievements (e.g. firmware's `bestDiff` field), so both sources
    /// render identically in the UI regardless of which one produced a given row.
    private static nonisolated func formatScoreboardDifficulty(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    /// Parses both current plain numeric storage and abbreviated difficulty strings written by
    /// older app builds, such as `2.5M`. Database reconciliation and maintenance share this so a
    /// legacy row cannot evade deduplication or distort the chronological high-water mark.
    static nonisolated func parsedAchievementDifficulty(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !value.isEmpty else { return nil }

        let multipliers: [Character: Double] = [
            "K": 1_000,
            "M": 1_000_000,
            "G": 1_000_000_000,
            "T": 1_000_000_000_000,
            "P": 1_000_000_000_000_000
        ]
        let suffix = value.last.flatMap { multipliers[$0] }
        let numberText = suffix == nil ? value : String(value.dropLast())
        guard let number = Double(numberText), number.isFinite, number >= 0 else { return nil }
        return number * (suffix ?? 1)
    }

    /// Records a polling-derived all-time best share without racing the authoritative firmware
    /// scoreboard import. If the scoreboard row landed first, polling skips its rounded duplicate.
    /// If polling landed first, `reconcileScoreboard` replaces it atomically with the precise row.
    @discardableResult
    public func recordPollingBestShareAchievement(
        minerId: String,
        timestamp: Date = Date(),
        difficulty: Double
    ) async -> Bool {
        guard difficulty.isFinite, difficulty > 0 else { return false }
        do {
            let queue = self.dbQueue
            return try await queue?.write { db in
                let tolerance = max(1.0, difficulty * 0.0001)
                let exists = try Bool.fetchOne(
                    db,
                    sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM achievement_events
                        WHERE miner_id = ? AND event_type = 'best_share'
                          AND ABS(CAST(difficulty AS REAL) - ?) < ?
                    )
                    """,
                    arguments: [minerId, difficulty, tolerance]
                ) ?? false
                guard !exists else { return false }

                let metadata = try? JSONSerialization.data(
                    withJSONObject: ["kind": "allTime", "source": "polling"], options: [])
                try db.execute(
                    sql: """
                    INSERT INTO achievement_events
                    (miner_id, event_type, timestamp, block_height, difficulty, metadata)
                    VALUES (?, 'best_share', ?, NULL, ?, ?)
                    """,
                    arguments: [
                        minerId,
                        Int(timestamp.timeIntervalSince1970),
                        Self.formatScoreboardDifficulty(difficulty),
                        metadata.flatMap { String(data: $0, encoding: .utf8) }
                    ]
                )
                return true
            } ?? false
        } catch {
            print("❌ Failed to record polling best-share achievement: \(error)")
            return false
        }
    }

    /// Get all achievement events for a miner
    public func getAchievements(
        minerId: String,
        eventType: String? = nil
    ) async -> [AchievementEvent] {
        do {
            let queue = self.dbQueue
            return try await queue?.read { db in
                var sql = "SELECT * FROM achievement_events WHERE miner_id = ?"
                var arguments: [DatabaseValueConvertible] = [minerId]

                if let eventType {
                    sql += " AND event_type = ?"
                    arguments.append(eventType)
                }

                sql += " ORDER BY timestamp DESC"

                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                return rows.map { row in
                    AchievementEvent(
                        id: row["id"],
                        minerId: row["miner_id"],
                        eventType: row["event_type"],
                        timestamp: Date(timeIntervalSince1970: TimeInterval(row["timestamp"] as Int)),
                        blockHeight: row["block_height"],
                        difficulty: row["difficulty"],
                        metadata: row["metadata"]
                    )
                }
            } ?? []
        } catch {
            print("❌ Failed to read achievements: \(error)")
            return []
        }
    }

    /// Deletes every achievement event for an explicitly removed device. Automatic same-MAC
    /// deduplication must use `mergeAchievementsChecked` instead so distinct history survives
    /// under the retained identity, rather than deleting the duplicate's unique events.
    public func deleteAchievements(minerId: String) async {
        do {
            let queue = self.dbQueue
            try await queue?.write { db in
                try db.execute(
                    sql: "DELETE FROM achievement_events WHERE miner_id = ?",
                    arguments: [minerId]
                )
            }
        } catch {
            print("❌ Failed to delete achievements for \(minerId): \(error)")
        }
    }

    /// Reconciles a miner's firmware scoreboard (its own NVS-persisted, authoritative best-share
    /// history — see `MinerScoreboardEntry`) into the achievements table. Unlike detection from
    /// periodic polling, this is ground truth straight from the ASIC and survives reboots/app
    /// reinstalls, so it's the right source for a permanent "concrete list" of best shares.
    ///
    /// The scoreboard itself is just the top-N shares ever seen, not in chronological order and
    /// not each a "record" at the time it happened. Importing all of them verbatim as `allTime`
    /// achievements made the timeline nonsensical: e.g. a 128M-difficulty share followed later by
    /// a 14M-difficulty share, both stamped "all-time record". This walks the entries in
    /// chronological order (`ntime`) and only imports the ones that were a genuine new high at
    /// that point — the real record-breaking sequence — matching how `detectBestShare` already
    /// defines an all-time record.
    ///
    /// Dedupes by the share's own `jobId` (unique per share) rather than by difficulty value, so
    /// two genuinely different shares that happen to round to the same displayed difficulty are
    /// both kept. Only inserts entries not already recorded; never deletes existing rows here.
    /// Returns the number of new achievement rows inserted.
    @discardableResult
    public func reconcileScoreboard(
        minerId: String,
        entries: [MinerScoreboardEntry]
    ) async -> Int {
        guard !entries.isEmpty else { return 0 }
        do {
            let queue = self.dbQueue
            let inserted = try await queue?.write { db -> Int in
                // Remove a rounded polling row for any share now represented by the firmware's
                // precise scoreboard. Doing this before computing priorMax makes the replacement
                // atomic and prevents a transient duplicate from reaching the Achievements view.
                let existingRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, difficulty, metadata FROM achievement_events
                    WHERE miner_id = ? AND event_type = 'best_share' AND difficulty IS NOT NULL
                    """,
                    arguments: [minerId]
                )
                let pollingIDsToReplace: [Int64] = existingRows.compactMap { row in
                    let metadata: String? = row["metadata"]
                    guard metadata?.contains("\"source\":\"scoreboard\"") != true else { return nil }
                    let rawDifficulty: String = row["difficulty"]
                    guard let stored = Self.parsedAchievementDifficulty(rawDifficulty) else { return nil }
                    let matches = entries.contains { entry in
                        abs(entry.difficulty - stored) < max(1.0, stored * 0.0001)
                    }
                    return matches ? row["id"] : nil
                }
                if !pollingIDsToReplace.isEmpty {
                    let placeholders = Array(repeating: "?", count: pollingIDsToReplace.count).joined(separator: ", ")
                    try db.execute(
                        sql: "DELETE FROM achievement_events WHERE id IN (\(placeholders))",
                        arguments: StatementArguments(pollingIDsToReplace)
                    )
                }

                // Establish the running high-water mark from what's already recorded (both from
                // polling and prior scoreboard imports), so a later reconcile pass on a growing
                // scoreboard doesn't re-derive "records" using only this batch's own entries.
                let priorRows = try String.fetchAll(
                    db,
                    sql: """
                    SELECT difficulty FROM achievement_events
                    WHERE miner_id = ? AND event_type = 'best_share' AND difficulty IS NOT NULL
                    """,
                    arguments: [minerId]
                )
                let priorMax = priorRows.compactMap(Self.parsedAchievementDifficulty).max() ?? 0

                var runningMax = priorMax
                var count = 0
                for entry in entries.sorted(by: { $0.ntime < $1.ntime }) {
                    guard entry.difficulty > runningMax else { continue }
                    runningMax = entry.difficulty

                    let existingMetadata = try String.fetchAll(
                        db,
                        sql: """
                        SELECT metadata FROM achievement_events
                        WHERE miner_id = ? AND event_type = 'best_share' AND metadata IS NOT NULL
                        """,
                        arguments: [minerId]
                    )
                    let exists = existingMetadata.contains { metadata in
                        guard let data = metadata.data(using: .utf8),
                            let object = try? JSONSerialization.jsonObject(with: data, options: []),
                            let dictionary = object as? [String: Any],
                            let storedJobID = dictionary["jobId"] as? String
                        else { return false }
                        return storedJobID == entry.jobId
                    }
                    guard !exists else { continue }
                    let metadataJSON = try? JSONSerialization.data(
                        withJSONObject: [
                            "kind": "allTime",
                            "source": "scoreboard",
                            "jobId": entry.jobId,
                            "coin": entry.coin as Any
                        ].compactMapValues { $0 },
                        options: []
                    )
                    try db.execute(
                        sql: """
                        INSERT INTO achievement_events
                        (miner_id, event_type, timestamp, block_height, difficulty, metadata)
                        VALUES (?, 'best_share', ?, NULL, ?, ?)
                        """,
                        arguments: [
                            minerId,
                            Int(entry.occurredAt.timeIntervalSince1970),
                            Self.formatScoreboardDifficulty(entry.difficulty),
                            metadataJSON.flatMap { String(data: $0, encoding: .utf8) }
                        ]
                    )
                    count += 1
                }
                return count
            } ?? 0
            if inserted > 0 {
                print("✅ Reconciled \(inserted) scoreboard entry(ies) for miner \(minerId)")
            }
            return inserted
        } catch {
            print("❌ Failed to reconcile scoreboard for \(minerId): \(error)")
            return 0
        }
    }

    /// Get all achievement events across all miners, optionally filtered by eventType and limited
    public func getAllAchievements(
        eventType: String? = nil,
        limit: Int? = nil
    ) async -> [AchievementEvent] {
        do {
            let queue = self.dbQueue
            return try await queue?.read { db in
                var sql = "SELECT * FROM achievement_events"
                var arguments: [DatabaseValueConvertible] = []

                if let eventType {
                    sql += " WHERE event_type = ?"
                    arguments.append(eventType)
                }

                sql += " ORDER BY timestamp DESC"

                if let limit {
                    sql += " LIMIT ?"
                    arguments.append(limit)
                }

                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                return rows.map { row in
                    AchievementEvent(
                        id: row["id"],
                        minerId: row["miner_id"],
                        eventType: row["event_type"],
                        timestamp: Date(timeIntervalSince1970: TimeInterval(row["timestamp"] as Int)),
                        blockHeight: row["block_height"],
                        difficulty: row["difficulty"],
                        metadata: row["metadata"]
                    )
                }
            } ?? []
        } catch {
            print("❌ Failed to read all achievements: \(error)")
            return []
        }
    }
}
