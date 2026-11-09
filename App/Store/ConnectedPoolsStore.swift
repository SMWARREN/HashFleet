import Foundation
import Observation
import HashFleetCore

private extension ConnectedAccountResult {
    /// Ignores the local fetch timestamp when deciding whether a pool/account card has new data.
    /// A repeated `.notFound` or identical failure is still a successful refresh attempt, but it
    /// does not need to invalidate the card hierarchy again.
    func hasSamePayload(as other: Self) -> Bool {
        switch (self, other) {
        case (.found(let lhs), .found(let rhs)):
            return lhs.hasSamePayload(as: rhs)
        case (.notFound, .notFound):
            return true
        case (.failed(let lhs), .failed(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

/// Strictly enforces 60-second cooldown per provider/coin/address, rejects redirects,
/// cancels on background or miner removal, and respects user opt-out and demo mode.
@MainActor @Observable
final class ConnectedPoolsStore {
    private(set) var poolStats: [PoolKey: MiningDataResult<ConnectedPoolStats>] = [:]
    private(set) var accountStats: [AccountKey: ConnectedAccountResult] = [:]
    private(set) var isRefreshing = false

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let cooldown: TimeInterval
    @ObservationIgnored private var poolAvailableAt: [PoolKey: Date] = [:]
    @ObservationIgnored private var accountAvailableAt: [AccountKey: Date] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lastConfigIdentity: String = ""

    init(session: URLSession = .shared, cooldown: TimeInterval = 60) {
        self.session = session
        self.cooldown = max(0, cooldown)
    }

    /// Only fresh connected observations authorize account queries. Resolve again after every await.
    ///
    /// `deviceID` scopes the result to a single miner. Inside one miner's workspace nothing about any
    /// other miner may be resolved, so no other payout address can reach a pool API from that screen.
    /// `nil` keeps the whole-fleet behavior used by the fleet-wide card.
    static func configuredPools(
        fleet: FleetStore,
        deviceID: UUID? = nil,
        now: Date = Date()
    ) -> [ConfiguredMiningPool] {
        fleet.devices.flatMap { device -> [ConfiguredMiningPool] in
            guard deviceID == nil || device.id == deviceID else { return [] }
            guard let snapshot = fleet.snapshots[device.id], snapshot.error == nil,
                let info = snapshot.info, let date = snapshot.updatedAt,
                fleet.isDemo || (-60...300).contains(now.timeIntervalSince(date))
            else { return [] }
            return ConfiguredMiningPool.resolve(info: info)
        }
    }

    private struct Configuration: Equatable {
        let pools: Set<PoolKey>
        let accounts: Set<AccountKey>
        init(_ entries: [ConfiguredMiningPool]) {
            pools = Set(
                entries.compactMap { entry in
                    guard let provider = entry.provider, let coin = entry.coin else { return nil }
                    return PoolKey(provider: provider, coin: coin)
                }
            )
            accounts = Set(
                entries.compactMap { entry in
                    guard let provider = entry.provider, let coin = entry.coin, let address = entry.address else {
                        return nil
                    }
                    return AccountKey(provider: provider, coin: coin, address: address, host: entry.host)
                }
            )
        }
    }
    @ObservationIgnored private var currentConfiguration: Configuration?
    @ObservationIgnored private var lastWasDemo = false

    /// Inputs for one refresh pass: resolved configuration, due keys, and the task generation.
    private struct RefreshPlan {
        let configuration: Configuration
        let token: UUID
        let poolKeys: Set<PoolKey>
        let accountKeys: Set<AccountKey>
    }

    /// `deviceID` restricts every resolution, cache filter and post-await re-check to one miner.
    /// One store instance serves one scope; changing scope replaces the configuration and cancels
    /// in-flight work, so a scoped screen can never publish another miner's results.
    func refresh(fleet: FleetStore, deviceID: UUID? = nil) async {
        guard let plan = prepareRefresh(fleet: fleet, deviceID: deviceID) else { return }
        let task = Task<Void, Never> { [weak self] in
            await self?.run(plan: plan, fleet: fleet, deviceID: deviceID)
        }
        refreshTask = task
        defer { if generation == plan.token { isRefreshing = false; refreshTask = nil } }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Guards and state preparation for a refresh. Returns nil when nothing should run.
    private func prepareRefresh(fleet: FleetStore, deviceID: UUID?) -> RefreshPlan? {
        guard fleet.preferences.externalDataEnabled else { clear(); return nil }
        if fleet.isDemo { loadDemo(fleet: fleet, deviceID: deviceID); lastWasDemo = true; return nil }
        if lastWasDemo { clear(); lastWasDemo = false }
        let configuration = Configuration(Self.configuredPools(fleet: fleet, deviceID: deviceID))
        if currentConfiguration != configuration {
            cancel()
            currentConfiguration = configuration
        }
        let retainedPoolStats = poolStats.filter { configuration.pools.contains($0.key) }
        if retainedPoolStats != poolStats {
            poolStats = retainedPoolStats
        }
        let retainedAccountStats = accountStats.filter { configuration.accounts.contains($0.key) }
        if retainedAccountStats != accountStats {
            accountStats = retainedAccountStats
        }
        poolAvailableAt = poolAvailableAt.filter { configuration.pools.contains($0.key) }
        accountAvailableAt = accountAvailableAt.filter { configuration.accounts.contains($0.key) }
        guard !isRefreshing, !Task.isCancelled else { return nil }
        let now = Date()
        let poolKeys = configuration.pools.filter { (poolAvailableAt[$0] ?? .distantPast) <= now }
        let accountKeys = configuration.accounts.filter { (accountAvailableAt[$0] ?? .distantPast) <= now }
        guard !poolKeys.isEmpty || !accountKeys.isEmpty else { return nil }
        let token = UUID()
        generation = token
        isRefreshing = true
        for key in poolKeys { poolAvailableAt[key] = now.addingTimeInterval(cooldown) }
        for key in accountKeys { accountAvailableAt[key] = now.addingTimeInterval(cooldown) }
        return RefreshPlan(configuration: configuration, token: token, poolKeys: poolKeys, accountKeys: accountKeys)
    }

    private func run(plan: RefreshPlan, fleet: FleetStore, deviceID: UUID?) async {
        let clients = FetchClients(session: session)
        async let pools = Self.fetchPools(keys: plan.poolKeys, clients: clients)
        async let accounts = Self.fetchAccounts(keys: plan.accountKeys, clients: clients)
        let (poolResults, accountResults) = await (pools, accounts)
        guard !Task.isCancelled, generation == plan.token,
            fleet.preferences.externalDataEnabled, !fleet.isDemo,
            Configuration(Self.configuredPools(fleet: fleet, deviceID: deviceID)) == plan.configuration
        else { return }
        for (key, result) in poolResults where poolStats[key]?.hasSamePayload(as: result) != true {
            poolStats[key] = result
        }
        for (key, result) in accountResults where accountStats[key]?.hasSamePayload(as: result) != true {
            accountStats[key] = result
        }
    }
    func clear() {
        cancel()
        poolStats.removeAll()
        accountStats.removeAll()
        poolAvailableAt.removeAll()
        accountAvailableAt.removeAll()
        currentConfiguration = nil
    }

    func cancel() {
        refreshTask?.cancel()
        refreshTask = nil
        generation = UUID()
        isRefreshing = false
    }

    private func loadDemo(fleet: FleetStore, deviceID: UUID? = nil) {
        clear()
        let now = Date()
        for device in fleet.devices {
            guard deviceID == nil || device.id == deviceID else { continue }
            guard let info = fleet.snapshots[device.id]?.info else { continue }
            for pool in ConfiguredMiningPool.resolve(info: info) {
                guard let provider = pool.provider else { continue }
                demoPoolStat(provider: provider, pool: pool, now: now)
            }
        }
    }

    private func demoPoolStat(provider: MiningPoolProvider, pool: ConfiguredMiningPool, now: Date) {
        let isCK = provider == .ckpool
        let key = PoolKey(provider: provider, coin: pool.coin)
        poolStats[key] = MiningDataResult(
            value: ConnectedPoolStats(
                hashRate1hrHPS: isCK ? 12.5e15 : 45e15,
                hashRate1dHPS: isCK ? 12e15 : 42e15,
                users: isCK ? 3000 : 400,
                workers: isCK ? 4500 : 850,
                bestShare: isCK ? 100 : 250
            ),
            error: nil,
            fetchedAt: now,
            sourceURL: URL(
                string: isCK
                    ? "https://raw.stats.ckpool.org/pool/pool.status" : "https://solofury.com/api/pool"
            )!,
            sourceTimestamp: nil
        )
        if let address = pool.address, !address.isEmpty {
            demoAccountStat(provider: provider, pool: pool, address: address, isCK: isCK, now: now)
        }
    }

    private func demoAccountStat(
        provider: MiningPoolProvider,
        pool: ConfiguredMiningPool,
        address: String,
        isCK: Bool,
        now: Date
    ) {
        let key = AccountKey(provider: provider, coin: pool.coin, address: address, host: pool.host)
        let stats = ConnectedAccountStats(
            hashRate1hrHPS: isCK ? 2.1e12 : 1.8e12,
            hashRate1dHPS: isCK ? 2.0e12 : 1.7e12,
            workersCount: isCK ? 3 : 2,
            shares: isCK ? 14200 : 8900,
            bestShare: isCK ? 4.5e9 : 1.2e9,
            bestEver: isCK ? 8.2e9 : 3.4e9,
            lastShare: now.addingTimeInterval(-60)
        )
        accountStats[key] = .found(
            MiningDataResult(
                value: stats,
                error: nil,
                fetchedAt: now,
                sourceURL: URL(
                    string: isCK
                        ? "https://raw.stats.ckpool.org/users/\(address)"
                        : "https://solofury.com/api/client/\(address)"
                )!,
                sourceTimestamp: nil
            )
        )
    }

}
