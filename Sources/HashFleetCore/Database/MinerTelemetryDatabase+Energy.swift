import Foundation
import GRDB

/// Average reported power for one miner during one clock minute.
public struct MinerPowerMinute: Sendable, Equatable {
    public let minerId: String
    public let minuteStart: Date
    public let averageWatts: Double

    public init(minerId: String, minuteStart: Date, averageWatts: Double) {
        self.minerId = minerId
        self.minuteStart = minuteStart
        self.averageWatts = averageWatts
    }
}

// MARK: - Energy Queries

extension MinerTelemetryDatabase {
    /// Per-minute average power for the given miners. Aggregating in SQL keeps a week of
    /// once-a-second readings (millions of rows) down to at most 1,440 rows per miner per day.
    /// Minutes with no power reading are absent rather than zero, so gaps never count as idle.
    public func getPowerMinutes(
        minerIds: [String],
        since: Date,
        until: Date = Date()
    ) async -> [MinerPowerMinute] {
        guard !minerIds.isEmpty else { return [] }
        do {
            let queue = self.dbQueue
            let placeholders = Array(repeating: "?", count: minerIds.count).joined(separator: ",")
            let sqlArguments: StatementArguments = [
                Int(since.timeIntervalSince1970), Int(until.timeIntervalSince1970)
            ] + StatementArguments(minerIds)
            return try await queue?.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT miner_id, timestamp / 60 AS minute, AVG(power) AS watts
                    FROM miner_readings
                    WHERE timestamp >= ? AND timestamp <= ?
                      AND power IS NOT NULL AND power >= 0
                      AND miner_id IN (\(placeholders))
                    GROUP BY miner_id, minute
                    ORDER BY minute ASC
                    """,
                    arguments: sqlArguments
                )
                return rows.compactMap { row -> MinerPowerMinute? in
                    let watts: Double = row["watts"]
                    guard watts.isFinite else { return nil }
                    let minute: Int = row["minute"]
                    return MinerPowerMinute(
                        minerId: row["miner_id"],
                        minuteStart: Date(timeIntervalSince1970: TimeInterval(minute * 60)),
                        averageWatts: watts
                    )
                }
            } ?? []
        } catch {
            print("❌ Failed to read power minutes: \(error)")
            return []
        }
    }
}
