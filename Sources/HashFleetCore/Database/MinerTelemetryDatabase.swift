import Foundation
import GRDB

public enum MinerTelemetryDatabaseError: Error, LocalizedError, Sendable {
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Telemetry storage is unavailable."
        }
    }
}

/// Persistent storage for all miner telemetry readings, achievements, and events
@MainActor
public final class MinerTelemetryDatabase {
    public static let shared = MinerTelemetryDatabase()

    let dbQueue: DatabaseQueue?
    let batchSize = 10
    var pendingReadings: [MinerReading] = []
    var isFlushingReadings = false

    public init(inMemory: Bool = false) {
        do {
            if inMemory {
                let queue = try DatabaseQueue()
                try Self.createSchema(in: queue)
                self.dbQueue = queue
            } else {
                let fileURL = try Self.databaseFileURL()
                let queue = try DatabaseQueue(path: fileURL.path)
                try Self.createSchema(in: queue)
                self.dbQueue = queue
            }
        } catch {
            print("❌ Failed to initialize telemetry database: \(error)")
            self.dbQueue = nil
        }
    }

    public init(databaseQueue: DatabaseQueue) {
        do {
            try Self.createSchema(in: databaseQueue)
            self.dbQueue = databaseQueue
        } catch {
            print("❌ Failed to initialize telemetry database: \(error)")
            self.dbQueue = nil
        }
    }

    // MARK: - Database Setup

    public static func databaseFileURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("miner_telemetry.db")
    }

    private static func createSchema(in dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            try createSchema(db)
        }
    }

    private static func createSchema(_ db: Database) throws {
        // Main telemetry readings table
        try db.create(table: "miner_readings", ifNotExists: true) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("miner_id", .text).notNull().indexed()
            table.column("timestamp", .integer).notNull().indexed()

            // Performance metrics
            table.column("hashrate", .double)              // GH/s
            table.column("power", .double)                 // watts
            table.column("temp", .double)                  // °C
            table.column("vr_temp", .double)               // °C
            table.column("fan_speed", .integer)            // %
            table.column("fan_rpm", .integer)
            table.column("voltage", .integer)              // mV
            table.column("frequency", .integer)            // MHz
            table.column("core_voltage", .integer)         // mV

            // Mining stats
            table.column("shares_accepted", .integer)
            table.column("shares_rejected", .integer)
            table.column("uptime_seconds", .integer)

            // Pool info
            table.column("active_pool_index", .integer)
            table.column("is_fallback_pool", .boolean)
        }

        // Achievement events (blocks found, best shares)
        try db.create(table: "achievement_events", ifNotExists: true) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("miner_id", .text).notNull().indexed()
            table.column("event_type", .text).notNull()    // 'block_found', 'best_share'
            table.column("timestamp", .integer).notNull().indexed()

            // Event-specific data
            table.column("block_height", .integer)         // for block_found
            table.column("difficulty", .text)              // for best_share
            table.column("metadata", .text)                // JSON for extensibility
        }

        // Connectivity tracking (online/offline)
        try db.create(table: "connectivity_events", ifNotExists: true) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("miner_id", .text).notNull().indexed()
            table.column("timestamp", .integer).notNull().indexed()
            table.column("event_type", .text).notNull()    // 'online', 'offline', 'error'
            table.column("error_message", .text)
        }

        // Pool switches
        try db.create(table: "pool_switches", ifNotExists: true) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("miner_id", .text).notNull().indexed()
            table.column("timestamp", .integer).notNull().indexed()
            table.column("from_pool", .text)
            table.column("to_pool", .text)
            table.column("pool_index", .integer)
            table.column("is_fallback", .boolean)
        }

        // Composite indices for common queries
        try db.create(index: "idx_miner_time", on: "miner_readings", columns: ["miner_id", "timestamp"], ifNotExists: true)
        try db.create(index: "idx_miner_events", on: "achievement_events", columns: ["miner_id", "event_type", "timestamp"], ifNotExists: true)
        try db.create(index: "idx_miner_connectivity", on: "connectivity_events", columns: ["miner_id", "timestamp"], ifNotExists: true)
        try db.create(index: "idx_miner_pool_switches", on: "pool_switches", columns: ["miner_id", "timestamp"], ifNotExists: true)
    }

}

// MARK: - Models

/// Groups the optional telemetry fields for a single `recordReading` call so the database API
/// stays under the parameter-count lint limit while keeping every field explicit at call sites.
public struct MinerReadingInput: Sendable {
    public var hashrate: Double?
    public var power: Double?
    public var temp: Double?
    public var vrTemp: Double?
    public var fanSpeed: Int?
    public var fanRPM: Int?
    public var voltage: Int?
    public var frequency: Int?
    public var coreVoltage: Int?
    public var sharesAccepted: Int?
    public var sharesRejected: Int?
    public var uptimeSeconds: Int?
    public var activePoolIndex: Int?
    public var isFallbackPool: Bool?

    public init(
        hashrate: Double? = nil,
        power: Double? = nil,
        temp: Double? = nil,
        vrTemp: Double? = nil,
        fanSpeed: Int? = nil,
        fanRPM: Int? = nil,
        voltage: Int? = nil,
        frequency: Int? = nil,
        coreVoltage: Int? = nil,
        sharesAccepted: Int? = nil,
        sharesRejected: Int? = nil,
        uptimeSeconds: Int? = nil,
        activePoolIndex: Int? = nil,
        isFallbackPool: Bool? = nil
    ) {
        self.hashrate = hashrate
        self.power = power
        self.temp = temp
        self.vrTemp = vrTemp
        self.fanSpeed = fanSpeed
        self.fanRPM = fanRPM
        self.voltage = voltage
        self.frequency = frequency
        self.coreVoltage = coreVoltage
        self.sharesAccepted = sharesAccepted
        self.sharesRejected = sharesRejected
        self.uptimeSeconds = uptimeSeconds
        self.activePoolIndex = activePoolIndex
        self.isFallbackPool = isFallbackPool
    }
}

public struct MinerReading: Codable, Equatable, Sendable {
    public let minerId: String
    public let timestamp: Date
    public let hashrate: Double?
    public let power: Double?
    public let temp: Double?
    public let vrTemp: Double?
    public let fanSpeed: Int?
    public let fanRPM: Int?
    public let voltage: Int?
    public let frequency: Int?
    public let coreVoltage: Int?
    public let sharesAccepted: Int?
    public let sharesRejected: Int?
    public let uptimeSeconds: Int?
    public let activePoolIndex: Int?
    public let isFallbackPool: Bool?

    public init(
        minerId: String,
        timestamp: Date,
        hashrate: Double?,
        power: Double?,
        temp: Double?,
        vrTemp: Double?,
        fanSpeed: Int?,
        fanRPM: Int?,
        voltage: Int?,
        frequency: Int?,
        coreVoltage: Int?,
        sharesAccepted: Int?,
        sharesRejected: Int?,
        uptimeSeconds: Int?,
        activePoolIndex: Int?,
        isFallbackPool: Bool?
    ) {
        self.minerId = minerId
        self.timestamp = timestamp
        self.hashrate = hashrate
        self.power = power
        self.temp = temp
        self.vrTemp = vrTemp
        self.fanSpeed = fanSpeed
        self.fanRPM = fanRPM
        self.voltage = voltage
        self.frequency = frequency
        self.coreVoltage = coreVoltage
        self.sharesAccepted = sharesAccepted
        self.sharesRejected = sharesRejected
        self.uptimeSeconds = uptimeSeconds
        self.activePoolIndex = activePoolIndex
        self.isFallbackPool = isFallbackPool
    }
}

extension MinerReading: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "miner_readings" }

    public enum Columns: String, ColumnExpression {
        case minerId = "miner_id"
        case timestamp
        case hashrate, power, temp
        case vrTemp = "vr_temp"
        case fanSpeed = "fan_speed"
        case fanRPM = "fan_rpm"
        case voltage, frequency
        case coreVoltage = "core_voltage"
        case sharesAccepted = "shares_accepted"
        case sharesRejected = "shares_rejected"
        case uptimeSeconds = "uptime_seconds"
        case activePoolIndex = "active_pool_index"
        case isFallbackPool = "is_fallback_pool"
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.minerId] = minerId
        container[Columns.timestamp] = Int(timestamp.timeIntervalSince1970)
        container[Columns.hashrate] = hashrate
        container[Columns.power] = power
        container[Columns.temp] = temp
        container[Columns.vrTemp] = vrTemp
        container[Columns.fanSpeed] = fanSpeed
        container[Columns.fanRPM] = fanRPM
        container[Columns.voltage] = voltage
        container[Columns.frequency] = frequency
        container[Columns.coreVoltage] = coreVoltage
        container[Columns.sharesAccepted] = sharesAccepted
        container[Columns.sharesRejected] = sharesRejected
        container[Columns.uptimeSeconds] = uptimeSeconds
        container[Columns.activePoolIndex] = activePoolIndex
        container[Columns.isFallbackPool] = isFallbackPool
    }
}

public struct AchievementEvent: Codable, Sendable, Identifiable {
    public let id: Int64
    public let minerId: String
    public let eventType: String
    public let timestamp: Date
    public let blockHeight: Int?
    public let difficulty: String?
    public let metadata: String?

    public init(
        id: Int64,
        minerId: String,
        eventType: String,
        timestamp: Date,
        blockHeight: Int?,
        difficulty: String?,
        metadata: String?
    ) {
        self.id = id
        self.minerId = minerId
        self.eventType = eventType
        self.timestamp = timestamp
        self.blockHeight = blockHeight
        self.difficulty = difficulty
        self.metadata = metadata
    }
}

public struct ConnectivityEvent: Codable, Sendable, Identifiable {
    public let id: Int64
    public let minerId: String
    public let timestamp: Date
    public let eventType: String
    public let errorMessage: String?

    public init(
        id: Int64,
        minerId: String,
        timestamp: Date,
        eventType: String,
        errorMessage: String?
    ) {
        self.id = id
        self.minerId = minerId
        self.timestamp = timestamp
        self.eventType = eventType
        self.errorMessage = errorMessage
    }
}

public struct PoolSwitchEvent: Codable, Sendable, Identifiable {
    public let id: Int64
    public let minerId: String
    public let timestamp: Date
    public let fromPool: String?
    public let toPool: String?
    public let poolIndex: Int?
    public let isFallback: Bool?

    public init(
        id: Int64,
        minerId: String,
        timestamp: Date,
        fromPool: String?,
        toPool: String?,
        poolIndex: Int?,
        isFallback: Bool?
    ) {
        self.id = id
        self.minerId = minerId
        self.timestamp = timestamp
        self.fromPool = fromPool
        self.toPool = toPool
        self.poolIndex = poolIndex
        self.isFallback = isFallback
    }
}

public struct HashrateSample: Sendable {
    public let timestamp: Date
    public let hashrate: Double

    public init(timestamp: Date, hashrate: Double) {
        self.timestamp = timestamp
        self.hashrate = hashrate
    }
}

public struct TemperatureSample: Sendable {
    public let timestamp: Date
    public let temp: Double

    public init(timestamp: Date, temp: Double) {
        self.timestamp = timestamp
        self.temp = temp
    }
}
