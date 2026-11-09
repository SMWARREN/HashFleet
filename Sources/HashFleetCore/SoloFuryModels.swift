import Foundation

/// Response models for the read-only SoloFury public API. Split from SoloFuryClient.swift
/// for file length; field semantics are unchanged.

public struct SoloFuryBlockEvent: Hashable, Sendable {
    public let height: Int?
    public let timestamp: Date?
    public let status: String?
    public init(height: Int? = nil, timestamp: Date? = nil, status: String? = nil) {
        self.height = height
        self.timestamp = timestamp
        self.status = status
    }
}

/// Public pool statistics returned by `GET /api[-coin]/pool`.
public struct SoloFuryPoolStats: Hashable, Sendable {
    public let totalHashRateHPS: Double?
    public let totalHashRate1mHPS: Double?
    public let totalHashRate1hrHPS: Double?
    public let totalHashRate1dHPS: Double?
    public let totalHashRate7dHPS: Double?
    public let totalMiners: Int?
    public let totalWorkers: Int?
    public let activeMiners7d: Int?
    public let activeWorkers7d: Int?
    public let blockHeight: Int?
    public let networkDifficulty: Double?
    public let networkHashRateHPS: Double?
    /// Present only for an explicitly reported numeric total. Never inferred from a potentially limited event list.
    public let blocksFound: Int?
    public let blockEvents: [SoloFuryBlockEvent]?
    public var reportedBlockEventCount: Int? { blockEvents?.count }
    public let bestDifficulty: Double?
    public let roundShares: Int?
    public let efficiency: Double?
    public let fee: Double?

    public init(
        totalHashRateHPS: Double? = nil,
        totalHashRate1mHPS: Double? = nil,
        totalHashRate1hrHPS: Double? = nil,
        totalHashRate1dHPS: Double? = nil,
        totalHashRate7dHPS: Double? = nil,
        totalMiners: Int? = nil,
        totalWorkers: Int? = nil,
        activeMiners7d: Int? = nil,
        activeWorkers7d: Int? = nil,
        blockHeight: Int? = nil,
        networkDifficulty: Double? = nil,
        networkHashRateHPS: Double? = nil,
        blocksFound: Int? = nil,
        bestDifficulty: Double? = nil,
        roundShares: Int? = nil,
        efficiency: Double? = nil,
        fee: Double? = nil,
        blockEvents: [SoloFuryBlockEvent]? = nil
    ) {
        self.totalHashRateHPS = totalHashRateHPS
        self.totalHashRate1mHPS = totalHashRate1mHPS
        self.totalHashRate1hrHPS = totalHashRate1hrHPS
        self.totalHashRate1dHPS = totalHashRate1dHPS
        self.totalHashRate7dHPS = totalHashRate7dHPS
        self.totalMiners = totalMiners
        self.totalWorkers = totalWorkers
        self.activeMiners7d = activeMiners7d
        self.activeWorkers7d = activeWorkers7d
        self.blockHeight = blockHeight
        self.networkDifficulty = networkDifficulty
        self.networkHashRateHPS = networkHashRateHPS
        self.blocksFound = blocksFound
        self.blockEvents = blockEvents
        self.bestDifficulty = bestDifficulty
        self.roundShares = roundShares
        self.efficiency = efficiency
        self.fee = fee
    }
}

/// Single worker details returned in client account response.
public struct SoloFuryWorkerStats: Hashable, Sendable {
    public let name: String
    public let hashRateHPS: Double?
    public let hashRate1mHPS: Double?
    public let hashRate1hrHPS: Double?
    public let bestDifficulty: Double?
    public let bestEver: Double?
    public let currentDiff: Double?
    public let shares: Int?
    public let lastSeen: Date?
    public let protocolType: String?
    public let region: String?

    public init(
        name: String,
        hashRateHPS: Double? = nil,
        hashRate1mHPS: Double? = nil,
        hashRate1hrHPS: Double? = nil,
        bestDifficulty: Double? = nil,
        bestEver: Double? = nil,
        currentDiff: Double? = nil,
        shares: Int? = nil,
        lastSeen: Date? = nil,
        protocolType: String? = nil,
        region: String? = nil
    ) {
        self.name = name
        self.hashRateHPS = hashRateHPS
        self.hashRate1mHPS = hashRate1mHPS
        self.hashRate1hrHPS = hashRate1hrHPS
        self.bestDifficulty = bestDifficulty
        self.bestEver = bestEver
        self.currentDiff = currentDiff
        self.shares = shares
        self.lastSeen = lastSeen
        self.protocolType = protocolType
        self.region = region
    }
}

/// Account statistics for a single wallet address returned by `GET /api[-coin]/client/<address>`.
public struct SoloFuryAccountStats: Hashable, Sendable {
    public let hashRateHPS: Double?
    public let hashRate1mHPS: Double?
    public let hashRate5mHPS: Double?
    public let hashRate1hrHPS: Double?
    public let hashRate1dHPS: Double?
    public let hashRate7dHPS: Double?
    public let workersCount: Int?
    public let bestDifficulty: Double?
    public let bestShare: Double?
    public let bestEver: Double?
    public let lastShare: Date?
    public let shares: Int?
    public let efficiency: Double?
    public let luck: Double?
    public let workers: [SoloFuryWorkerStats]
    /// Distinguishes a reported empty list from a missing or malformed list. No worker count is inferred.
    public let workersReported: Bool

    public init(
        hashRateHPS: Double? = nil,
        hashRate1mHPS: Double? = nil,
        hashRate5mHPS: Double? = nil,
        hashRate1hrHPS: Double? = nil,
        hashRate1dHPS: Double? = nil,
        hashRate7dHPS: Double? = nil,
        workersCount: Int? = nil,
        bestDifficulty: Double? = nil,
        bestShare: Double? = nil,
        bestEver: Double? = nil,
        lastShare: Date? = nil,
        shares: Int? = nil,
        efficiency: Double? = nil,
        luck: Double? = nil,
        workers: [SoloFuryWorkerStats] = [],
        workersReported: Bool = false
    ) {
        self.hashRateHPS = hashRateHPS
        self.hashRate1mHPS = hashRate1mHPS
        self.hashRate5mHPS = hashRate5mHPS
        self.hashRate1hrHPS = hashRate1hrHPS
        self.hashRate1dHPS = hashRate1dHPS
        self.hashRate7dHPS = hashRate7dHPS
        self.workersCount = workersCount
        self.bestDifficulty = bestDifficulty
        self.bestShare = bestShare
        self.bestEver = bestEver
        self.lastShare = lastShare
        self.shares = shares
        self.efficiency = efficiency
        self.luck = luck
        self.workers = workers
        self.workersReported = workersReported
    }
}

/// Public REST client for SoloFury mining pool strictly targeting `https://solofury.com`.
/// Hardened privacy controls:
/// - Base URL is strictly `https://solofury.com`, no arbitrary base URL override
/// - Ephemeral URLSession with credential storage nil, cookies disabled, local cache ignored
/// - Custom URLSessionTaskDelegate blocking redirects per-task
/// - Injected URLSession sanitizes configuration and enforces delegate
/// - Fixed 15s timeout
/// - Task.checkCancellation before and after fetch
/// - Caps response body to 1 MB
/// - GET only
