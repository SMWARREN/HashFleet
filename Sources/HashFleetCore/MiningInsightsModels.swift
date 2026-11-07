import Foundation

/// Fixed, read-only public sources. The wallet endpoint URL is a directory, never a supplied host.
public enum MiningInsightsEndpoint: String, CaseIterable, Hashable, Sendable {
    case fees, backlog, tipHeight, mining, price, ckPoolSummary, ckPoolUser, cashStats, xecStats, dgbStats, coinMarkets

    public var sourceName: String {
        switch self {
        case .ckPoolSummary, .ckPoolUser: "CKPool"
        case .cashStats, .xecStats: "Blockchair"
        case .dgbStats: "SoloPool.org"
        case .coinMarkets: "CoinGecko"
        default: "mempool.space"
        }
    }

    public var url: URL {
        let base: String
        let path: String
        switch self {
        case .fees: base = "https://mempool.space"; path = "/api/v1/fees/recommended"
        case .backlog: base = "https://mempool.space"; path = "/api/mempool"
        case .tipHeight: base = "https://mempool.space"; path = "/api/blocks/tip/height"
        case .mining: base = "https://mempool.space"; path = "/api/v1/mining/hashrate/3d"
        case .price: base = "https://mempool.space"; path = "/api/v1/prices"
        case .ckPoolSummary: base = "https://raw.stats.ckpool.org"; path = "/pool/pool.status"
        case .ckPoolUser: base = "https://raw.stats.ckpool.org"; path = "/users/"
        case .cashStats: base = "https://api.blockchair.com"; path = "/bitcoin-cash/stats"
        case .xecStats: base = "https://api.blockchair.com"; path = "/ecash/stats"
        // This is the pool's public network endpoint, not a stratum share-statistics endpoint.
        // The dgb-sha dashboard is explicitly configured for SHA-256 (SHA-256d mining) and
        // labels node.difficulty as Network Difficulty. Do not replace it with generic
        // multi-algorithm DGB difficulty.
        case .dgbStats: base = "https://dgb-sha.solopool.org"; path = "/api/stats"
        case .coinMarkets:
            base = "https://api.coingecko.com"
            path =
                "/api/v3/coins/markets?vs_currency=usd&ids=bitcoin%2Cbitcoin-cash%2Cbitcoinii%2C"
                + "bitcoin-cash-ii%2Cecash%2Cdigibyte&order=market_cap_desc&per_page=250&page=1&sparkline=false"
        }
        // Both components are compile-time constants, not external configuration.
        return URL(string: base + path)!
    }
}

/// Deliberately excludes response bodies, request URLs, wallet addresses, and underlying error text.
public enum MiningInsightsError: Error, LocalizedError, Hashable, Sendable {
    case invalidBitcoinAddress
    case invalidResponse
    case invalidData
    case redirected
    case http(statusCode: Int)
    case timedOut
    case cancelled
    case network(code: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBitcoinAddress:
            "Enter a valid Bitcoin mainnet address only. URLs, worker suffixes, and private keys are not accepted."
        case .invalidResponse: "The public data source returned an unexpected response."
        case .invalidData: "The public data source did not return recognizable, valid statistics."
        case .redirected: "The public data request was redirected. Redirects are blocked for privacy."
        case .http(let statusCode): "The public data source returned HTTP \(statusCode)."
        case .timedOut: "The public data request timed out."
        case .cancelled: "The public data request was cancelled."
        case .network: "The public data source could not be reached."
        }
    }
}

/// A single independently fetched endpoint. Missing values are not zero and timestamps are not inferred.
public struct MiningDataResult<Value: Sendable>: Sendable {
    public let value: Value?
    public let error: MiningInsightsError?
    public let fetchedAt: Date
    public let sourceURL: URL
    public let sourceTimestamp: Date?

    public init(
        value: Value? = nil,
        error: MiningInsightsError? = nil,
        fetchedAt: Date,
        sourceURL: URL,
        sourceTimestamp: Date? = nil
    ) {
        self.value = value
        self.error = error
        self.fetchedAt = fetchedAt
        self.sourceURL = sourceURL
        self.sourceTimestamp = sourceTimestamp
    }
}

extension MiningDataResult: Equatable where Value: Equatable {}
extension MiningDataResult: Hashable where Value: Hashable {}

public struct NetworkSnapshot: Hashable, Sendable {
    public let fetchedAt: Date
    public let fees: MiningDataResult<BitcoinFeeRecommendations>
    public let backlog: MiningDataResult<MempoolBacklog>
    public let tipHeight: MiningDataResult<Int>
    public let mining: MiningDataResult<BitcoinMiningStatistics>
    public let price: MiningDataResult<BitcoinPrice>

    public var isCancelled: Bool {
        fees.error == .cancelled || backlog.error == .cancelled || tipHeight.error == .cancelled
            || mining.error == .cancelled || price.error == .cancelled
    }

    public init(
        fetchedAt: Date,
        fees: MiningDataResult<BitcoinFeeRecommendations>,
        backlog: MiningDataResult<MempoolBacklog>,
        tipHeight: MiningDataResult<Int>,
        mining: MiningDataResult<BitcoinMiningStatistics>,
        price: MiningDataResult<BitcoinPrice>
    ) {
        self.fetchedAt = fetchedAt
        self.fees = fees
        self.backlog = backlog
        self.tipHeight = tipHeight
        self.mining = mining
        self.price = price
    }
}

/// Recommended fee rates in satoshis per virtual byte, not transaction fees or confirmation guarantees.
public struct BitcoinFeeRecommendations: Hashable, Sendable {
    public let fastestFee: Double?
    public let halfHourFee: Double?
    public let hourFee: Double?
    public let economyFee: Double?
    public let minimumFee: Double?

    public init(
        fastestFee: Double? = nil,
        halfHourFee: Double? = nil,
        hourFee: Double? = nil,
        economyFee: Double? = nil,
        minimumFee: Double? = nil
    ) {
        self.fastestFee = fastestFee
        self.halfHourFee = halfHourFee
        self.hourFee = hourFee
        self.economyFee = economyFee
        self.minimumFee = minimumFee
    }
}

public struct MempoolBacklog: Hashable, Sendable {
    public let transactionCount: Int?
    public let virtualSizeBytes: Int?
    public let totalFeeSatoshis: Int64?

    public init(transactionCount: Int? = nil, virtualSizeBytes: Int? = nil, totalFeeSatoshis: Int64? = nil) {
        self.transactionCount = transactionCount
        self.virtualSizeBytes = virtualSizeBytes
        self.totalFeeSatoshis = totalFeeSatoshis
    }
}

public struct BitcoinMiningStatistics: Hashable, Sendable {
    public let hashrateHPS: Double?
    public let difficulty: Double?
    /// Timestamp of the latest historical daily sample, NOT the time of currentHashrate.
    public let hashrateSampleAt: Date?
    /// Time the currently reported difficulty took effect, if present in the history.
    public let difficultyChangedAt: Date?

    public init(
        hashrateHPS: Double? = nil,
        difficulty: Double? = nil,
        hashrateSampleAt: Date? = nil,
        difficultyChangedAt: Date? = nil
    ) {
        self.hashrateHPS = hashrateHPS
        self.difficulty = difficulty
        self.hashrateSampleAt = hashrateSampleAt
        self.difficultyChangedAt = difficultyChangedAt
    }
}

public struct BitcoinPrice: Hashable, Sendable {
    public let usd: Double?
    public init(usd: Double? = nil) { self.usd = usd }
}

/// Read-only market identity returned by CoinGecko. The image URL is used only for
/// presentation and never determines which coin a miner is configured to use.
public struct CoinGeckoMarket: Hashable, Sendable {
    public let id: String
    public let ticker: String
    public let name: String
    public let imageURL: URL?
    public let currentPriceUSD: Double?
    public let marketCapRank: Int?

    public init(
        id: String,
        ticker: String,
        name: String,
        imageURL: URL? = nil,
        currentPriceUSD: Double? = nil,
        marketCapRank: Int? = nil
    ) {
        self.id = id
        self.ticker = ticker
        self.name = name
        self.imageURL = imageURL
        self.currentPriceUSD = currentPriceUSD
        self.marketCapRank = marketCapRank
    }
}

/// CKPool-reported rolling rates, not measurements from any user's miner.
public struct CKPoolSummary: Hashable, Sendable {
    public let uptimeSeconds: TimeInterval?
    public let users: Int?
    public let workers: Int?
    public let idle: Int?
    public let disconnected: Int?
    public let hashrate1MinuteHPS: Double?
    public let hashrate5MinutesHPS: Double?
    public let hashrate1HourHPS: Double?
    public let hashrate1DayHPS: Double?
    public let hashrate7DaysHPS: Double?
    public let bestShare: Double?

    public init(
        uptimeSeconds: TimeInterval? = nil,
        users: Int? = nil,
        workers: Int? = nil,
        idle: Int? = nil,
        disconnected: Int? = nil,
        hashrate1MinuteHPS: Double? = nil,
        hashrate5MinutesHPS: Double? = nil,
        hashrate1HourHPS: Double? = nil,
        hashrate1DayHPS: Double? = nil,
        hashrate7DaysHPS: Double? = nil,
        bestShare: Double? = nil
    ) {
        self.uptimeSeconds = uptimeSeconds
        self.users = users
        self.workers = workers
        self.idle = idle
        self.disconnected = disconnected
        self.hashrate1MinuteHPS = hashrate1MinuteHPS
        self.hashrate5MinutesHPS = hashrate5MinutesHPS
        self.hashrate1HourHPS = hashrate1HourHPS
        self.hashrate1DayHPS = hashrate1DayHPS
        self.hashrate7DaysHPS = hashrate7DaysHPS
        self.bestShare = bestShare
    }
}

/// Returned only after deliberate lookup. Worker identifiers and raw payloads are not retained.
public struct CKPoolUserStatistics: Hashable, Sendable {
    public let hashrate1MinuteHPS: Double?
    public let hashrate5MinutesHPS: Double?
    public let hashrate1HourHPS: Double?
    public let hashrate1DayHPS: Double?
    public let hashrate7DaysHPS: Double?
    public let workers: Int?
    public let shares: Double?
    public let bestShare: Double?
    public let bestEver: Double?
    public let lastShareAt: Date?

    public init(
        hashrate1MinuteHPS: Double? = nil,
        hashrate5MinutesHPS: Double? = nil,
        hashrate1HourHPS: Double? = nil,
        hashrate1DayHPS: Double? = nil,
        hashrate7DaysHPS: Double? = nil,
        workers: Int? = nil,
        shares: Double? = nil,
        bestShare: Double? = nil,
        bestEver: Double? = nil,
        lastShareAt: Date? = nil
    ) {
        self.hashrate1MinuteHPS = hashrate1MinuteHPS
        self.hashrate5MinutesHPS = hashrate5MinutesHPS
        self.hashrate1HourHPS = hashrate1HourHPS
        self.hashrate1DayHPS = hashrate1DayHPS
        self.hashrate7DaysHPS = hashrate7DaysHPS
        self.workers = workers
        self.shares = shares
        self.bestShare = bestShare
        self.bestEver = bestEver
        self.lastShareAt = lastShareAt
    }
}

public enum CKPoolUserLookup: Hashable, Sendable {
    case found(MiningDataResult<CKPoolUserStatistics>)
    /// Only HTTP 404 produces this case. An empty/malformed 200 is an error, not an absent miner.
    case notFound(fetchedAt: Date)
    case failed(MiningInsightsError)
}
