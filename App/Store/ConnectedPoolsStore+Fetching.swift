import Foundation
import Observation
import HashFleetCore

/// Pool and account fetch helpers for ConnectedPoolsStore. Each provider gets its own
/// single-result helper so the group loops stay small and auditable.

/// The three read-only public clients used by one refresh pass.
struct FetchClients: Sendable {
    let ckPool: MiningInsightsClient
    let soloFury: SoloFuryClient
    let soloPool: SoloPoolClient

    init(session: URLSession?) {
        ckPool = MiningInsightsClient(session: session)
        soloFury = SoloFuryClient(session: session)
        soloPool = SoloPoolClient(session: session)
    }
}

extension ConnectedPoolsStore {
    /// Fetches every due pool key; failures are per-key results, never silent skips.
    nonisolated static func fetchPools(
        keys: Set<PoolKey>,
        clients: FetchClients
    ) async -> [PoolKey: MiningDataResult<ConnectedPoolStats>] {
        await withTaskGroup(of: (PoolKey, MiningDataResult<ConnectedPoolStats>).self) { group in
            for key in keys {
                group.addTask { await Self.fetchPool(key: key, clients: clients) }
            }
            var results: [PoolKey: MiningDataResult<ConnectedPoolStats>] = [:]
            for await (key, res) in group {
                results[key] = res
            }
            return results
        }
    }

    nonisolated static func fetchPool(
        key: PoolKey,
        clients: FetchClients
    ) async -> (PoolKey, MiningDataResult<ConnectedPoolStats>) {
        switch key.provider {
        case .ckpool: return await Self.ckPoolStats(key: key, client: clients.ckPool)
        case .soloFury: return await Self.soloFuryPoolStats(key: key, client: clients.soloFury)
        case .soloPool: return Self.soloPoolPlaceholder(key: key)
        }
    }

    private nonisolated static func ckPoolStats(
        key: PoolKey,
        client: MiningInsightsClient
    ) async -> (PoolKey, MiningDataResult<ConnectedPoolStats>) {
        let res = await client.ckPoolSummary()
        let norm = ConnectedPoolStats(
            hashRate1hrHPS: res.value?.hashrate1HourHPS,
            hashRate1dHPS: res.value?.hashrate1DayHPS,
            users: res.value?.users,
            workers: res.value?.workers,
            bestShare: res.value?.bestShare
        )
        return (key, res.normalizing(to: norm))
    }

    private nonisolated static func soloFuryPoolStats(
        key: PoolKey,
        client: SoloFuryClient
    ) async -> (PoolKey, MiningDataResult<ConnectedPoolStats>) {
        guard let coin = key.coin else {
            return (
                key,
                MiningDataResult(
                    error: .invalidData,
                    fetchedAt: Date(),
                    sourceURL: URL(string: "https://solofury.com")!
                )
            )
        }
        let res = await client.summary(coin: coin)
        let norm = ConnectedPoolStats(
            hashRate1hrHPS: res.value?.totalHashRate1hrHPS,
            hashRate1dHPS: res.value?.totalHashRate1dHPS,
            users: res.value?.totalMiners,
            workers: res.value?.totalWorkers,
            bestShare: res.value?.bestDifficulty
        )
        return (key, res.normalizing(to: norm))
    }

    /// SoloPool has no documented public pool-level aggregate endpoint, only the per-address
    /// account endpoint. Never fabricate a pool summary.
    private nonisolated static func soloPoolPlaceholder(key: PoolKey) -> (PoolKey, MiningDataResult<ConnectedPoolStats>) {
        (
            key,
            MiningDataResult(
                error: .invalidData,
                fetchedAt: Date(),
                sourceURL: SoloPoolClient.productionBaseURL
            )
        )
    }

    /// Fetches every due account key; failures are per-key results, never silent skips.
    nonisolated static func fetchAccounts(
        keys: Set<AccountKey>,
        clients: FetchClients
    ) async -> [AccountKey: ConnectedAccountResult] {
        await withTaskGroup(of: (AccountKey, ConnectedAccountResult).self) { group in
            for key in keys {
                group.addTask { await Self.fetchAccount(key: key, clients: clients) }
            }
            var results: [AccountKey: ConnectedAccountResult] = [:]
            for await (key, res) in group {
                results[key] = res
            }
            return results
        }
    }

    nonisolated static func fetchAccount(
        key: AccountKey,
        clients: FetchClients
    ) async -> (AccountKey, ConnectedAccountResult) {
        switch key.provider {
        case .ckpool: return await Self.ckPoolAccount(key: key, client: clients.ckPool)
        case .soloFury: return await Self.soloFuryAccount(key: key, client: clients.soloFury)
        case .soloPool: return await Self.soloPoolAccount(key: key, client: clients.soloPool)
        }
    }

    private nonisolated static func ckPoolAccount(
        key: AccountKey,
        client: MiningInsightsClient
    ) async -> (AccountKey, ConnectedAccountResult) {
        switch await client.ckPoolUser(address: key.address) {
        case .found(let res):
            let norm = ConnectedAccountStats(
                hashRate1hrHPS: res.value?.hashrate1HourHPS,
                hashRate1dHPS: res.value?.hashrate1DayHPS,
                workersCount: res.value?.workers,
                shares: res.value?.shares,
                bestShare: res.value?.bestShare,
                bestEver: res.value?.bestEver,
                lastShare: res.value?.lastShareAt
            )
            return (key, .found(res.normalizing(to: norm)))
        case .notFound(let fetchedAt):
            return (key, .notFound(fetchedAt: fetchedAt))
        case .failed(let error):
            return (key, .failed(error))
        }
    }

    private nonisolated static func soloFuryAccount(
        key: AccountKey,
        client: SoloFuryClient
    ) async -> (AccountKey, ConnectedAccountResult) {
        guard let coin = key.coin else { return (key, .failed(.invalidData)) }
        let canonicalHost = "\(coin.rawValue).solofury.com"
        let pool = ConfiguredMiningPool(
            id: "lookup",
            host: key.host.isEmpty ? canonicalHost : key.host,
            coin: coin,
            provider: .soloFury,
            role: "lookup",
            isActive: true,
            address: key.address,
            redactedAddress: nil
        )
        let res = await client.account(pool: pool)
        if res.error == .http(statusCode: 404) { return (key, .notFound(fetchedAt: res.fetchedAt)) }
        if let error = res.error { return (key, .failed(error)) }
        guard let val = res.value else { return (key, .failed(.invalidData)) }
        let norm = ConnectedAccountStats(
            hashRate1hrHPS: val.hashRate1hrHPS,
            hashRate1dHPS: val.hashRate1dHPS,
            workersCount: val.workersCount,
            shares: val.shares.map(Double.init),
            bestShare: val.bestShare,
            bestEver: val.bestEver,
            lastShare: val.lastShare
        )
        return (key, .found(res.normalizing(to: norm)))
    }

    private nonisolated static func soloPoolAccount(
        key: AccountKey,
        client: SoloPoolClient
    ) async -> (AccountKey, ConnectedAccountResult) {
        guard let coin = key.coin else { return (key, .failed(.invalidData)) }
        let pool = ConfiguredMiningPool(
            id: "lookup",
            host: key.host,
            coin: coin,
            provider: .soloPool,
            role: "lookup",
            isActive: true,
            address: key.address,
            redactedAddress: nil
        )
        let res = await client.account(pool: pool)
        if res.error == .http(statusCode: 404) { return (key, .notFound(fetchedAt: res.fetchedAt)) }
        if let error = res.error { return (key, .failed(error)) }
        guard let val = res.value else { return (key, .failed(.invalidData)) }
        let norm = ConnectedAccountStats(
            hashRate1hrHPS: val.hashRateHPS.map(Double.init),
            hashRate1dHPS: val.averageHashRateHPS.map(Double.init),
            workersCount: val.totalWorkers,
            shares: val.roundShares.map(Double.init),
            bestShare: val.bestShare.map(Double.init),
            bestEver: nil,
            lastShare: val.lastShare
        )
        return (key, .found(res.normalizing(to: norm)))
    }
}

extension MiningDataResult {
    /// Replaces a fetched upstream value with its normalized presentation form. A fetch that
    /// produced no value or failed keeps its explicit error and never surfaces a synthesized value.
    func normalizing<NewValue: Sendable>(to norm: NewValue) -> MiningDataResult<NewValue> {
        MiningDataResult<NewValue>(
            value: value != nil ? norm : nil,
            error: error,
            fetchedAt: fetchedAt,
            sourceURL: sourceURL,
            sourceTimestamp: sourceTimestamp
        )
    }
}
