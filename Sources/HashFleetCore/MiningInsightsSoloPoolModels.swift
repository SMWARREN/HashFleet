import Foundation

// SoloPool account response models. Split from MiningInsightsModels.swift for file length;
// these mirror the documented `dgb-sha.solopool.org` account API responses.

// MARK: - SoloPool Account Models

/// Single worker details from a SoloPool account response.
public struct SoloPoolWorkerStats: Hashable, Sendable {
    public let name: String
    public let hashRateHPS: UInt64?
    public let averageHashRateHPS: UInt64?
    public let lastShare: Date?
    public let validShares: Int?
    public let invalidShares: Int?
    public let staleShares: Int?
    public let offline: Bool?
    public let dead: Bool?
    public let port: Int?
    public let geo: String?

    public init(
        name: String,
        hashRateHPS: UInt64? = nil,
        averageHashRateHPS: UInt64? = nil,
        lastShare: Date? = nil,
        validShares: Int? = nil,
        invalidShares: Int? = nil,
        staleShares: Int? = nil,
        offline: Bool? = nil,
        dead: Bool? = nil,
        port: Int? = nil,
        geo: String? = nil
    ) {
        self.name = name
        self.hashRateHPS = hashRateHPS
        self.averageHashRateHPS = averageHashRateHPS
        self.lastShare = lastShare
        self.validShares = validShares
        self.invalidShares = invalidShares
        self.staleShares = staleShares
        self.offline = offline
        self.dead = dead
        self.port = port
        self.geo = geo
    }
}

/// Block details from a SoloPool account response.
public struct SoloPoolBlockEntry: Hashable, Sendable {
    public let height: Int?
    public let hash: String?
    public let tx: String?
    public let timestamp: Date?
    public let networkDifficulty: Double?
    public let shareDiff: Double?
    public let poolShares: Double?
    public let minerShares: Double?
    public let blockReward: UInt64?
    public let minerReward: UInt64?
    public let feeReward: UInt64?
    public let miner: String?
    public let worker: String?
    public let geo: String?
    public let state: Int?

    public init(
        height: Int? = nil,
        hash: String? = nil,
        tx: String? = nil,
        timestamp: Date? = nil,
        networkDifficulty: Double? = nil,
        shareDiff: Double? = nil,
        poolShares: Double? = nil,
        minerShares: Double? = nil,
        blockReward: UInt64? = nil,
        minerReward: UInt64? = nil,
        feeReward: UInt64? = nil,
        miner: String? = nil,
        worker: String? = nil,
        geo: String? = nil,
        state: Int? = nil
    ) {
        self.height = height
        self.hash = hash
        self.tx = tx
        self.timestamp = timestamp
        self.networkDifficulty = networkDifficulty
        self.shareDiff = shareDiff
        self.poolShares = poolShares
        self.minerShares = minerShares
        self.blockReward = blockReward
        self.minerReward = minerReward
        self.feeReward = feeReward
        self.miner = miner
        self.worker = worker
        self.geo = geo
        self.state = state
    }
}

/// Blocks summary period entry from a SoloPool account response.
public struct SoloPoolBlocksSummaryEntry: Hashable, Sendable {
    public let period: Int?
    public let blocks: Int?
    public let total: UInt64?
    public let luck: Double?

    public init(period: Int? = nil, blocks: Int? = nil, total: UInt64? = nil, luck: Double? = nil) {
        self.period = period
        self.blocks = blocks
        self.total = total
        self.luck = luck
    }
}

/// Hashrate chart data point from a SoloPool account response.
public struct SoloPoolChartPoint: Hashable, Sendable {
    public let timestamp: Date?
    public let hashRateHPS: UInt64?

    public init(timestamp: Date? = nil, hashRateHPS: UInt64? = nil) {
        self.timestamp = timestamp
        self.hashRateHPS = hashRateHPS
    }
}

/// Account statistics for a single wallet address returned by `GET /api/miners/{address}`.
public struct SoloPoolAccountStats: Hashable, Sendable {
    public let hashRateHPS: UInt64?
    public let averageHashRateHPS: UInt64?
    public let onlineWorkers: Int?
    public let offlineWorkers: Int?
    public let deadWorkers: Int?
    public let totalWorkers: Int?
    public let lastShare: Date?
    public let roundShares: UInt64?
    public let bestShare: UInt64?
    public let totalBlocks: Int?
    public let lastBlockTime: Date?
    public let workers: [SoloPoolWorkerStats]
    /// Distinguishes a reported empty dict from a missing or malformed dict.
    public let workersReported: Bool
    public let blocks: [SoloPoolBlockEntry]?
    public let blocksSummary: [SoloPoolBlocksSummaryEntry]?
    public let charts: [SoloPoolChartPoint]?

    public init(
        hashRateHPS: UInt64? = nil,
        averageHashRateHPS: UInt64? = nil,
        onlineWorkers: Int? = nil,
        offlineWorkers: Int? = nil,
        deadWorkers: Int? = nil,
        totalWorkers: Int? = nil,
        lastShare: Date? = nil,
        roundShares: UInt64? = nil,
        bestShare: UInt64? = nil,
        totalBlocks: Int? = nil,
        lastBlockTime: Date? = nil,
        workers: [SoloPoolWorkerStats] = [],
        workersReported: Bool = false,
        blocks: [SoloPoolBlockEntry]? = nil,
        blocksSummary: [SoloPoolBlocksSummaryEntry]? = nil,
        charts: [SoloPoolChartPoint]? = nil
    ) {
        self.hashRateHPS = hashRateHPS
        self.averageHashRateHPS = averageHashRateHPS
        self.onlineWorkers = onlineWorkers
        self.offlineWorkers = offlineWorkers
        self.deadWorkers = deadWorkers
        self.totalWorkers = totalWorkers
        self.lastShare = lastShare
        self.roundShares = roundShares
        self.bestShare = bestShare
        self.totalBlocks = totalBlocks
        self.lastBlockTime = lastBlockTime
        self.workers = workers
        self.workersReported = workersReported
        self.blocks = blocks
        self.blocksSummary = blocksSummary
        self.charts = charts
    }
}
