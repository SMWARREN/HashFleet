import Foundation
import Observation
import HashFleetCore

/// Compares the information carried by a public API response without treating a new local fetch
/// timestamp as new remote data. Public endpoint responses are commonly cached upstream, so
/// assigning an otherwise identical result on every refresh needlessly invalidates every view that
/// observes the insights store.
extension MiningDataResult where Value: Equatable {
    func hasSamePayload(as other: Self) -> Bool {
        value == other.value
            && error == other.error
            && sourceURL == other.sourceURL
            && sourceTimestamp == other.sourceTimestamp
    }
}

extension NetworkSnapshot {
    func hasSamePayload(as other: Self) -> Bool {
        fees.hasSamePayload(as: other.fees)
            && backlog.hasSamePayload(as: other.backlog)
            && tipHeight.hasSamePayload(as: other.tipHeight)
            && mining.hasSamePayload(as: other.mining)
            && price.hasSamePayload(as: other.price)
    }
}

/// Read-only public data state. Foreground views request refreshes. No miner configuration or address persistence.
@MainActor @Observable
final class MiningInsightsStore {
    private(set) var network: NetworkSnapshot?
    private(set) var pool: MiningDataResult<CKPoolSummary>?
    private(set) var cash: MiningDataResult<BitcoinCashStatistics>?
    private(set) var xec: MiningDataResult<BitcoinCashStatistics>?
    private(set) var dgb: MiningDataResult<BitcoinCashStatistics>?
    private(set) var poolNetworks: [MiningPoolCoin: MiningDataResult<SoloFuryPoolStats>] = [:]
    private(set) var coinMarkets: [MiningPoolCoin: CoinGeckoMarket] = [:]
    private(set) var coinMarketsResult: MiningDataResult<[MiningPoolCoin: CoinGeckoMarket]>?
    private(set) var userLookup: CKPoolUserLookup?
    private(set) var isLoading = false
    private(set) var isLookingUp = false
    private(set) var isDemo = false
    private(set) var refreshAvailableAt = Date.distantPast
    private(set) var lookupAvailableAt = Date.distantPast
    @ObservationIgnored private let client: MiningInsightsClient
    @ObservationIgnored private let poolClient: SoloFuryClient
    @ObservationIgnored private let cooldown: TimeInterval
    @ObservationIgnored private var refreshTask: Task<RefreshResults, Never>?
    @ObservationIgnored private var coinMarketsTask: Task<MiningDataResult<[MiningPoolCoin: CoinGeckoMarket]>, Never>?
    @ObservationIgnored private var lookupTask: Task<CKPoolUserLookup, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lookupGeneration = UUID()
    @ObservationIgnored private var lastCoinMarketsFetchAt: Date?

    init(session: URLSession? = nil, cooldown: TimeInterval = 60) {
        client = MiningInsightsClient(session: session)
        poolClient = SoloFuryClient(session: session)
        self.cooldown = max(0, cooldown)
    }

    func setDemo(_ demo: Bool) {
        guard demo != isDemo else { return }
        cancel()
        isDemo = demo
        network = nil
        pool = nil
        cash = nil
        xec = nil
        dgb = nil
        poolNetworks = [:]
        coinMarkets = [:]
        coinMarketsResult = nil
        lastCoinMarketsFetchAt = nil
        userLookup = nil
        refreshAvailableAt = .distantPast
        lookupAvailableAt = .distantPast
    }

    func refresh(force: Bool = false) async {
        if isDemo {
            applyDemoData()
            return
        }
        guard shouldRunRefresh(force: force) else { return }
        isLoading = true
        refreshAvailableAt = Date().addingTimeInterval(cooldown)
        let token = UUID()
        generation = token
        let client = client
        let poolClient = poolClient
        let marketsTask = makeCoinMarketsTask(force: force)
        coinMarketsTask = marketsTask
        let task = Task.detached(priority: .utility) {
            await Self.fetchAll(client: client, poolClient: poolClient, coinMarkets: marketsTask)
        }
        refreshTask = task
        defer {
            if generation == token {
                isLoading = false
                refreshTask = nil
                coinMarketsTask = nil
            }
        }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
            marketsTask?.cancel()
        }
        guard !Task.isCancelled, generation == token, !isDemo else { return }
        // A failed source is replaced by an explicit failure, never made fresh by another source succeeding.
        apply(result)
    }

    private func applyDemoData() {
        network = MiningInsightsDemo.network
        pool = MiningInsightsDemo.pool
        cash = MiningInsightsDemo.cash
        xec = MiningInsightsDemo.xec
        dgb = MiningInsightsDemo.dgb
        poolNetworks = Dictionary(uniqueKeysWithValues: MiningPoolCoin.soloFuryCoins.map { coin in
            (coin, MiningDataResult(value: SoloFuryPoolStats(totalHashRate1hrHPS: 1e15,
                totalMiners: 10, totalWorkers: 20, blockHeight: 59000,
                networkDifficulty: coin == .bc2 || coin == .bch2 ? 2e9 : 4e11),
                fetchedAt: Date(), sourceURL: URL(string: "https://solofury.com\(coin.soloFuryPrefix!)/pool")!))
        })
    }

    private func shouldRunRefresh(force: Bool) -> Bool {
        if isLoading {
            if force {
                cancel()
            } else {
                return false
            }
        }
        guard !Task.isCancelled else { return false }
        if !force { guard Date() >= refreshAvailableAt else { return false } }
        return true
    }

    private func makeCoinMarketsTask(force: Bool) -> Task<MiningDataResult<[MiningPoolCoin: CoinGeckoMarket]>, Never>? {
        let shouldRefresh =
            force
            || coinMarkets.isEmpty
            || lastCoinMarketsFetchAt.map { Date().timeIntervalSince($0) >= 15 * 60 } ?? true
        guard shouldRefresh else { return nil }
        let client = client
        return Task.detached(priority: .utility) { await client.coinMarkets() }
    }

    private nonisolated static func fetchAll(
        client: MiningInsightsClient,
        poolClient: SoloFuryClient,
        coinMarkets marketsTask: Task<MiningDataResult<[MiningPoolCoin: CoinGeckoMarket]>, Never>?
    ) async -> RefreshResults {
        async let network = client.bitcoinNetwork()
        async let pool = client.ckPoolSummary()
        async let cash = client.bitcoinCash()
        async let xec = client.eCash()
        async let dgb = client.digiByte()
        async let poolNetworks = fetchPoolNetworks(client: poolClient)
        return await RefreshResults(
            network: network,
            pool: pool,
            cash: cash,
            xec: xec,
            dgb: dgb,
            poolNetworks: poolNetworks,
            coinMarkets: marketsTask?.value
        )
    }

    private func apply(_ result: RefreshResults) {
        if network?.hasSamePayload(as: result.network) != true {
            network = result.network
        }
        if pool?.hasSamePayload(as: result.pool) != true {
            pool = result.pool
        }
        if cash?.hasSamePayload(as: result.cash) != true {
            cash = result.cash
        }
        if xec?.hasSamePayload(as: result.xec) != true {
            xec = result.xec
        }
        if dgb?.hasSamePayload(as: result.dgb) != true {
            dgb = result.dgb
        }
        if !poolNetworksHaveSamePayload(as: result.poolNetworks) {
            poolNetworks = result.poolNetworks
        }
        if let coinMarketsResult = result.coinMarkets {
            let changed = self.coinMarketsResult?.hasSamePayload(as: coinMarketsResult) != true
            if changed {
                self.coinMarketsResult = coinMarketsResult
            }
            if coinMarketsResult.error == nil, let value = coinMarketsResult.value {
                if changed || coinMarkets != value {
                    coinMarkets = value
                }
                // This is observation-ignored bookkeeping. Keep the 15-minute market TTL moving
                // even when the response body is unchanged, without publishing another redraw.
                lastCoinMarketsFetchAt = coinMarketsResult.fetchedAt
            }
        }
    }

    private func poolNetworksHaveSamePayload(
        as other: [MiningPoolCoin: MiningDataResult<SoloFuryPoolStats>]
    ) -> Bool {
        guard poolNetworks.count == other.count else { return false }
        return poolNetworks.allSatisfy { entry in
            guard let next = other[entry.key] else { return false }
            return entry.value.hasSamePayload(as: next)
        }
    }

    func lookup(address: String) async {
        guard !isDemo, !isLookingUp, !Task.isCancelled, Date() >= lookupAvailableAt else { return }
        isLookingUp = true
        userLookup = nil
        lookupAvailableAt = Date().addingTimeInterval(cooldown)
        let token = UUID()
        lookupGeneration = token
        let client = client
        let task = Task.detached(priority: .utility) {
            await client.ckPoolUser(address: address.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        lookupTask = task
        defer {
            if lookupGeneration == token { isLookingUp = false; lookupTask = nil }
        }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !Task.isCancelled, lookupGeneration == token, !isDemo else { return }
        userLookup = result
    }

    func clearPublicData() {
        cancel()
        network = nil
        pool = nil
        cash = nil
        xec = nil
        dgb = nil
        poolNetworks = [:]
        coinMarkets = [:]
        coinMarketsResult = nil
        lastCoinMarketsFetchAt = nil
        refreshAvailableAt = .distantPast
    }

    func clearLookup() {
        lookupTask?.cancel()
        lookupTask = nil
        lookupGeneration = UUID()
        isLookingUp = false
        userLookup = nil
    }

    func cancel() {
        refreshTask?.cancel()
        refreshTask = nil
        coinMarketsTask?.cancel()
        coinMarketsTask = nil
        generation = UUID()
        isLoading = false
        clearLookup()
    }
    /// One full refresh pass. Named fields instead of a large tuple.
    struct RefreshResults: Sendable {
        let network: NetworkSnapshot
        let pool: MiningDataResult<CKPoolSummary>
        let cash: MiningDataResult<BitcoinCashStatistics>
        let xec: MiningDataResult<BitcoinCashStatistics>
        let dgb: MiningDataResult<BitcoinCashStatistics>
        let poolNetworks: [MiningPoolCoin: MiningDataResult<SoloFuryPoolStats>]
        let coinMarkets: MiningDataResult<[MiningPoolCoin: CoinGeckoMarket]>?
    }

    /// Fixed public aggregate endpoints only. No miner addresses, wallets or credentials are sent.
    private nonisolated static func fetchPoolNetworks(
        client: SoloFuryClient
    ) async -> [MiningPoolCoin: MiningDataResult<SoloFuryPoolStats>] {
        return await withTaskGroup(of: (MiningPoolCoin, MiningDataResult<SoloFuryPoolStats>).self) { group in
            for coin in MiningPoolCoin.soloFuryCoins {
                group.addTask { (coin, await client.summary(coin: coin)) }
            }
            var results: [MiningPoolCoin: MiningDataResult<SoloFuryPoolStats>] = [:]
            for await (coin, result) in group { results[coin] = result }
            return results
        }
    }
}

/// Clearly labeled sample data, never used on the real-data path or persisted.
enum MiningInsightsDemo {
    static var network: NetworkSnapshot {
        let now = Date()
        return NetworkSnapshot(
            fetchedAt: now,
            fees: result(
                BitcoinFeeRecommendations(fastestFee: 4, halfHourFee: 3, hourFee: 2, economyFee: 1, minimumFee: 1),
                path: "v1/fees/recommended",
                at: now
            ),
            backlog: result(
                MempoolBacklog(transactionCount: 2400, virtualSizeBytes: 1500000, totalFeeSatoshis: 5000000),
                path: "mempool",
                at: now
            ),
            tipHeight: result(960000, path: "blocks/tip/height", at: now),
            mining: result(
                BitcoinMiningStatistics(
                    hashrateHPS: 1e21,
                    difficulty: 140e12,
                    hashrateSampleAt: now,
                    difficultyChangedAt: nil
                ),
                path: "v1/mining/hashrate/3d",
                at: now
            ),
            price: result(BitcoinPrice(usd: 80000), path: "v1/prices", at: now)
        )
    }

    static var pool: MiningDataResult<CKPoolSummary> {
        MiningDataResult(
            value: CKPoolSummary(
                uptimeSeconds: 86400,
                users: 3000,
                workers: 4500,
                hashrate1MinuteHPS: 12e15,
                hashrate5MinutesHPS: 13e15,
                hashrate1HourHPS: 12.5e15,
                hashrate1DayHPS: 12e15
            ),
            error: nil,
            fetchedAt: Date(),
            sourceURL: URL(string: "https://raw.stats.ckpool.org/pool/pool.status")!,
            sourceTimestamp: nil
        )
    }

    static var cash: MiningDataResult<BitcoinCashStatistics> {
        MiningDataResult(
            value: BitcoinCashStatistics(
                difficulty: 430e9,
                tipHeight: 967000,
                usd: 260,
                hashrate24HoursHPS: 3e18,
                mempoolTransactions: 75
            ),
            fetchedAt: Date(),
            sourceURL: URL(string: "https://api.blockchair.com/bitcoin-cash/stats")!
        )
    }

    static var xec: MiningDataResult<BitcoinCashStatistics> {
        MiningDataResult(
            value: BitcoinCashStatistics(
                difficulty: 140e9,
                tipHeight: 1025000,
                usd: 0.000027,
                hashrate24HoursHPS: 1.2e18,
                mempoolTransactions: 120
            ),
            fetchedAt: Date(),
            sourceURL: URL(string: "https://api.blockchair.com/ecash/stats")!
        )
    }

    static var dgb: MiningDataResult<BitcoinCashStatistics> {
        MiningDataResult(
            value: BitcoinCashStatistics(
                difficulty: 90e6,
                tipHeight: 21500000,
                usd: 0.008,
                hashrate24HoursHPS: 2e14,
                mempoolTransactions: 45
            ),
            fetchedAt: Date(),
            sourceURL: MiningInsightsEndpoint.dgbStats.url
        )
    }

    private static func result<T: Sendable>(_ value: T, path: String, at date: Date) -> MiningDataResult<T> {
        MiningDataResult(
            value: value,
            error: nil,
            fetchedAt: date,
            sourceURL: URL(string: "https://mempool.space/api/\(path)")!,
            sourceTimestamp: nil
        )
    }
}
