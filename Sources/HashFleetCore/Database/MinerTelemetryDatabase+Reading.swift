import Foundation
import GRDB

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

}
