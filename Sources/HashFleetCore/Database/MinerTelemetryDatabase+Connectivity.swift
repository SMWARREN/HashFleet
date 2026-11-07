import Foundation
import GRDB

// MARK: - Connectivity & Pool Switch Events

extension MinerTelemetryDatabase {
    /// Record connectivity event
    public func recordConnectivityEvent(
        minerId: String,
        eventType: String,
        timestamp: Date = Date(),
        errorMessage: String? = nil
    ) async {
        do {
            let queue = self.dbQueue
            try await queue?.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO connectivity_events
                    (miner_id, timestamp, event_type, error_message)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [minerId, Int(timestamp.timeIntervalSince1970), eventType, errorMessage]
                )
            }
        } catch {
            print("❌ Failed to record connectivity event: \(error)")
        }
    }

    /// Record pool switch event
    public func recordPoolSwitch(
        minerId: String,
        timestamp: Date = Date(),
        fromPool: String?,
        toPool: String?,
        poolIndex: Int?,
        isFallback: Bool?
    ) async {
        do {
            let queue = self.dbQueue
            try await queue?.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO pool_switches
                    (miner_id, timestamp, from_pool, to_pool, pool_index, is_fallback)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [minerId, Int(timestamp.timeIntervalSince1970), fromPool, toPool, poolIndex, isFallback]
                )
            }
        } catch {
            print("❌ Failed to record pool switch: \(error)")
        }
    }

    /// Get connectivity events for a miner
    public func getConnectivityEvents(
        minerId: String,
        since: Date? = nil
    ) async -> [ConnectivityEvent] {
        do {
            let queue = self.dbQueue
            return try await queue?.read { db in
                var sql = "SELECT * FROM connectivity_events WHERE miner_id = ?"
                var arguments: [DatabaseValueConvertible] = [minerId]
                if let since {
                    sql += " AND timestamp >= ?"
                    arguments.append(Int(since.timeIntervalSince1970))
                }
                sql += " ORDER BY timestamp DESC"
                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                return rows.map { row in
                    ConnectivityEvent(
                        id: row["id"],
                        minerId: row["miner_id"],
                        timestamp: Date(timeIntervalSince1970: TimeInterval(row["timestamp"] as Int)),
                        eventType: row["event_type"],
                        errorMessage: row["error_message"]
                    )
                }
            } ?? []
        } catch {
            print("❌ Failed to read connectivity events: \(error)")
            return []
        }
    }

    /// Get pool switches for a miner
    public func getPoolSwitches(
        minerId: String,
        since: Date? = nil
    ) async -> [PoolSwitchEvent] {
        do {
            let queue = self.dbQueue
            return try await queue?.read { db in
                var sql = "SELECT * FROM pool_switches WHERE miner_id = ?"
                var arguments: [DatabaseValueConvertible] = [minerId]
                if let since {
                    sql += " AND timestamp >= ?"
                    arguments.append(Int(since.timeIntervalSince1970))
                }
                sql += " ORDER BY timestamp DESC"
                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                return rows.map { row in
                    PoolSwitchEvent(
                        id: row["id"],
                        minerId: row["miner_id"],
                        timestamp: Date(timeIntervalSince1970: TimeInterval(row["timestamp"] as Int)),
                        fromPool: row["from_pool"],
                        toPool: row["to_pool"],
                        poolIndex: row["pool_index"],
                        isFallback: row["is_fallback"]
                    )
                }
            } ?? []
        } catch {
            print("❌ Failed to read pool switches: \(error)")
            return []
        }
    }
}
