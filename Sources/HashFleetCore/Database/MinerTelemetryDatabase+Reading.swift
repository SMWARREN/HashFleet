import Foundation
import GRDB

/// Recorded miner sensor readings averaged within one time bucket. Missing is not zero.
public struct MinerSensorHistorySample: Sendable {
    public let date: Date
    public let temperature: Double?
    public let power: Double?
}

// MARK: - Reading Writes & Queries

extension MinerTelemetryDatabase {
    /// Record a telemetry reading (batched writes)
    public func recordReading(
        minerId: String,
        timestamp: Date = Date(),
        reading input: MinerReadingInput
    ) {
        let reading = MinerReading(
            minerId: minerId,
            timestamp: timestamp,
            hashrate: input.hashrate,
            power: input.power,
            temp: input.temp,
            vrTemp: input.vrTemp,
            fanSpeed: input.fanSpeed,
            fanRPM: input.fanRPM,
            voltage: input.voltage,
            frequency: input.frequency,
            coreVoltage: input.coreVoltage,
            sharesAccepted: input.sharesAccepted,
            sharesRejected: input.sharesRejected,
            uptimeSeconds: input.uptimeSeconds,
            activePoolIndex: input.activePoolIndex,
            isFallbackPool: input.isFallbackPool
        )

        pendingReadings.append(reading)

        if pendingReadings.count >= batchSize {
            Task { @MainActor in
                await self.flushReadings()
            }
        }
    }

    /// Flush pending readings to database
    public func flushReadings() async {
        guard !pendingReadings.isEmpty, !isFlushingReadings else {
            return
        }
        isFlushingReadings = true
        defer { isFlushingReadings = false }

        await acquireReadingsMutation()
        defer { releaseReadingsMutation() }
        // A clear ahead of us may have consumed the entire pending batch.
        guard !pendingReadings.isEmpty else { return }
        let batch = pendingReadings

        do {
            guard let queue = await self.preparedQueue() else { throw MinerTelemetryDatabaseError.unavailable }
            try await queue.write { db in
                for reading in batch {
                    try reading.insert(db)
                }
            }
            guard pendingReadings.count >= batch.count,
                Array(pendingReadings.prefix(batch.count)) == batch
            else { return }
            pendingReadings.removeFirst(batch.count)
            if pendingReadings.count >= batchSize {
                Task { @MainActor in
                    await self.flushReadings()
                }
            }
        } catch {
            // Keep the batch at the head of the queue so a later flush can retry it. A transient
            // database failure must not silently erase readings from the user's history.
            print("❌ Failed to flush telemetry readings: \(error)")
        }
    }

    /// Get hashrate readings for a time range
    public func getHashrateReadings(
        minerId: String,
        since: Date,
        until: Date = Date()
    ) async -> [HashrateSample] {
        do {
            let queue = await self.preparedQueue()
            return try await queue?.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT timestamp, hashrate FROM miner_readings
                    WHERE miner_id = ? AND timestamp >= ? AND timestamp <= ? AND hashrate IS NOT NULL
                    ORDER BY timestamp ASC
                    """,
                    arguments: [minerId, Int(since.timeIntervalSince1970), Int(until.timeIntervalSince1970)]
                )
                return rows.map { row in
                    HashrateSample(
                        timestamp: Date(timeIntervalSince1970: TimeInterval(row["timestamp"] as Int)),
                        hashrate: row["hashrate"] as Double
                    )
                }
            } ?? []
        } catch {
            print("❌ Failed to read hashrate: \(error)")
            return []
        }
    }

    /// Get temperature readings for a time range
    public func getTemperatureReadings(
        minerId: String,
        since: Date,
        until: Date = Date()
    ) async -> [TemperatureSample] {
        do {
            let queue = await self.preparedQueue()
            return try await queue?.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT timestamp, temp FROM miner_readings
                    WHERE miner_id = ? AND timestamp >= ? AND timestamp <= ? AND temp IS NOT NULL
                    ORDER BY timestamp ASC
                    """,
                    arguments: [minerId, Int(since.timeIntervalSince1970), Int(until.timeIntervalSince1970)]
                )
                return rows.map { row in
                    TemperatureSample(
                        timestamp: Date(timeIntervalSince1970: TimeInterval(row["timestamp"] as Int)),
                        temp: row["temp"] as Double
                    )
                }
            } ?? []
        } catch {
            print("❌ Failed to read temperature: \(error)")
            return []
        }
    }

    /// Returns up to 180 nonempty buckets. No buckets or zero values are created for gaps.
    public func getSensorHistory(minerId: String, since: Date, until: Date) async -> [MinerSensorHistorySample] {
        let start = ceil(since.timeIntervalSince1970)
        let end = floor(until.timeIntervalSince1970)
        guard start.isFinite, end.isFinite, start <= end,
              start >= Double(Int64.min), end < Double(Int64.max) else { return [] }
        let bucketSeconds = max(1, Int64(ceil((end - start + 1) / 180)))
        do {
            let queue = await preparedQueue()
            return try await queue?.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT MIN(timestamp) AS observed,
                           AVG(CASE WHEN temp >= 0 THEN temp END) AS temperature,
                           AVG(CASE WHEN power >= 0 THEN power END) AS watts
                    FROM miner_readings
                    WHERE miner_id = ? AND timestamp BETWEEN ? AND ? AND (temp >= 0 OR power >= 0)
                    GROUP BY CAST((timestamp - ?) / ? AS INTEGER)
                    ORDER BY observed
                    """, arguments: [minerId, Int64(start), Int64(end), Int64(start), bucketSeconds])
                return rows.compactMap { row in
                    let temperature = (row["temperature"] as Double?).flatMap { $0.isFinite ? $0 : nil }
                    let power = (row["watts"] as Double?).flatMap { $0.isFinite ? $0 : nil }
                    guard temperature != nil || power != nil else { return nil }
                    return MinerSensorHistorySample(date: Date(timeIntervalSince1970: row["observed"] as Double),
                                                    temperature: temperature, power: power)
                }
            } ?? []
        } catch {
            print("Failed to read sensor history: \(error)")
            return []
        }
    }
}
