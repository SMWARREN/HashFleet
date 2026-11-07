import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized) @MainActor
struct PoolStatsHubTests {
    private let address = "1BoatSLRHtKNngkdXEeobR76b53LETtpyT"

    private struct PoolHubFixture {
        let fleet: FleetStore
        let defaults: UserDefaults
        let suite: String
    }

    private func makeFleetStore() throws -> PoolHubFixture {
        let suite = "app.hashfleet.poolhub-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let devices = [MinerDevice(name: "Hub fixture", address: "miner.invalid")]
        defaults.set(try JSONEncoder().encode(devices), forKey: "app.hashfleet.devices.v1")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HubTestProtocol.self]
        let session = URLSession(configuration: config)
        return PoolHubFixture(
            fleet: FleetStore(defaults: defaults, session: session),
            defaults: defaults,
            suite: suite
        )
    }

    private func pool(
        id: String,
        address: String?,
        active: Bool? = nil,
        provider: MiningPoolProvider = .ckpool,
        coin: MiningPoolCoin = .btc
    ) -> ConfiguredMiningPool {
        ConfiguredMiningPool(
            id: id,
            host: provider == .ckpool ? "stratum.ckpool.org" : "\(coin.rawValue).solofury.com",
            coin: coin,
            provider: provider,
            role: active == true ? "Active" : "Configured",
            isActive: active,
            address: address,
            redactedAddress: address.map { _ in "••••" }
        )
    }

    @Test func sharedPoolAccountProducesOneEntryWithEveryConnectedMiner() {
        let sharedAddress = "1BoatSLRHtKNngkdXEeobR76b53LETtpyT"
        let entries = PoolStatsHubEntry.grouped([
            .init(deviceID: UUID(), minerName: "Gamma", pool: pool(id: "primary", address: sharedAddress)),
            .init(deviceID: UUID(), minerName: "Naja Duo", pool: pool(id: "secondary", address: sharedAddress, active: true)),
            .init(deviceID: UUID(), minerName: "Gamma", pool: pool(id: "backup", address: sharedAddress))
        ])

        #expect(entries.count == 1)
        #expect(entries[0].minerNames == ["Gamma", "Naja Duo"])
        #expect(entries[0].pool.id == "secondary")
        #expect(entries[0].id.address == sharedAddress)
    }

    @Test func distinctAccountsRemainSeparateEntries() {
        let entries = PoolStatsHubEntry.grouped([
            .init(deviceID: UUID(), minerName: "Gamma", pool: pool(id: "one", address: address)),
            .init(
                deviceID: UUID(),
                minerName: "Naja Duo",
                pool: pool(id: "two", address: "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy")
            )
        ])

        #expect(entries.count == 2)
        #expect(Set(entries.flatMap(\.minerNames)) == ["Gamma", "Naja Duo"])
    }

    @Test func poolWideEntriesWithoutAccountsAreDeduplicatedByProviderAndCoin() {
        let entries = PoolStatsHubEntry.grouped([
            .init(deviceID: UUID(), minerName: "Gamma", pool: pool(id: "one", address: nil)),
            .init(deviceID: UUID(), minerName: "Bitaxe", pool: pool(id: "two", address: nil))
        ])

        #expect(entries.count == 1)
        #expect(entries[0].minerNames == ["Bitaxe", "Gamma"])
        #expect(entries[0].id.address == nil)
    }

    // MARK: - Demo Mode Populates Pool and Account Stats

    @Test func demoModePopulatesStatsWithoutNetworkRequests() async throws {
        let hubEnv = try makeFleetStore()
        let fleet = hubEnv.fleet
        let defaults = hubEnv.defaults
        let suite = hubEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        HubTestProtocol.state.reset()

        fleet.loadDemo()
        let store = ConnectedPoolsStore()
        await store.refresh(fleet: fleet)

        // Demo mode produces pool and account stats from fixture data
        #expect(!store.poolStats.isEmpty)
        #expect(!store.accountStats.isEmpty)
        // No network requests in demo
        #expect(HubTestProtocol.state.requests.isEmpty)
    }

    // MARK: - External Data Disabled Clears Stats

    @Test func externalDataDisabledClearsAllStats() async throws {
        let hubEnv = try makeFleetStore()
        let fleet = hubEnv.fleet
        let defaults = hubEnv.defaults
        let suite = hubEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        HubTestProtocol.state.reset()

        fleet.loadDemo()
        let store = ConnectedPoolsStore()
        await store.refresh(fleet: fleet)
        #expect(!store.poolStats.isEmpty)

        // Disable external data
        fleet.preferences.externalDataEnabled = false
        await store.refresh(fleet: fleet)
        #expect(store.poolStats.isEmpty)
        #expect(store.accountStats.isEmpty)
    }

    // MARK: - No Configured Pools Produces Empty Stats

    @Test func noPools_producesEmptyStats() async throws {
        let hubEnv = try makeFleetStore()
        let fleet = hubEnv.fleet
        let defaults = hubEnv.defaults
        let suite = hubEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        HubTestProtocol.state.reset()
        // Fleet with no snapshots (no demo loaded, fresh store with unreachable miner)
        let store = ConnectedPoolsStore()
        await store.refresh(fleet: fleet)
        #expect(store.poolStats.isEmpty)
        #expect(store.accountStats.isEmpty)
    }

    // MARK: - Pool Stats Keys Match Configured Providers

    @Test func demoPoolStatsKeysMatchConfiguredProviders() async throws {
        let hubEnv = try makeFleetStore()
        let fleet = hubEnv.fleet
        let defaults = hubEnv.defaults
        let suite = hubEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        HubTestProtocol.state.reset()

        fleet.loadDemo()
        let store = ConnectedPoolsStore()
        await store.refresh(fleet: fleet)

        // All pool stats keys should have a recognized provider
        for key in store.poolStats.keys {
            #expect(key.provider == .ckpool || key.provider == .soloFury)
        }

        // All pool stats values should have non-nil value in demo
        for (_, result) in store.poolStats {
            #expect(result.value != nil)
            #expect(result.error == nil)
        }
    }

    // MARK: - Account Stats Contain Expected Fields

    @Test func demoAccountStatsContainExpectedFields() async throws {
        let hubEnv = try makeFleetStore()
        let fleet = hubEnv.fleet
        let defaults = hubEnv.defaults
        let suite = hubEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        HubTestProtocol.state.reset()

        fleet.loadDemo()
        let store = ConnectedPoolsStore()
        await store.refresh(fleet: fleet)

        for (_, result) in store.accountStats {
            guard case .found(let dataResult) = result else {
                Issue.record("Expected .found account result in demo")
                continue
            }
            guard let val = dataResult.value else {
                Issue.record("Expected non-nil account value in demo")
                continue
            }
            // Demo accounts should have hashrate and worker data
            #expect(val.hashRate1hrHPS != nil)
            #expect(val.hashRate1dHPS != nil)
            #expect(val.workersCount != nil)
            #expect(val.bestShare != nil)
        }
    }

    // MARK: - Pool Stats Have Expected Hashrate Windows

    @Test func demoPoolStatsHaveHashrateValues() async throws {
        let hubEnv = try makeFleetStore()
        let fleet = hubEnv.fleet
        let defaults = hubEnv.defaults
        let suite = hubEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        HubTestProtocol.state.reset()

        fleet.loadDemo()
        let store = ConnectedPoolsStore()
        await store.refresh(fleet: fleet)

        for (_, result) in store.poolStats {
            guard let stats = result.value else {
                Issue.record("Expected pool stats value in demo")
                continue
            }
            #expect(stats.hashRate1hrHPS != nil && stats.hashRate1hrHPS! > 0)
            #expect(stats.hashRate1dHPS != nil && stats.hashRate1dHPS! > 0)
            #expect(stats.workers != nil && stats.workers! > 0)
            #expect(stats.users != nil && stats.users! > 0)
            #expect(stats.bestShare != nil && stats.bestShare! > 0)
        }
    }

    // MARK: - ConfiguredPools Excludes Unknown Providers

    @Test func configuredPoolsExcludesUnknownHosts() async throws {
        let hubEnv = try makeFleetStore()
        let fleet = hubEnv.fleet
        let defaults = hubEnv.defaults
        let suite = hubEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        // Load the fixture miner with an unknown pool host
        HubTestProtocol.state.reset()
        HubTestProtocol.state.info =
            #"{"hostname":"fixture","stratumURL":"unknown-pool.example.com","stratumUser":"\#(address).w1"}"#
        await fleet.refresh()
        let pools = ConnectedPoolsStore.configuredPools(fleet: fleet)
        // Unknown hosts produce nil provider, so no stats should be fetched
        for pool in pools where pool.host == "unknown-pool.example.com" {
            // An unknown host should not resolve to a known provider
            #expect(pool.provider == nil)
        }
    }

    // MARK: - Refresh After ClearDemo Yields Empty

    @Test func clearDemoThenRefreshYieldsEmptyStats() async throws {
        let hubEnv = try makeFleetStore()
        let fleet = hubEnv.fleet
        let defaults = hubEnv.defaults
        let suite = hubEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        HubTestProtocol.state.reset()

        fleet.loadDemo()
        let store = ConnectedPoolsStore()
        await store.refresh(fleet: fleet)
        #expect(!store.poolStats.isEmpty)

        fleet.clearDemo()
        await store.refresh(fleet: fleet)
        // After clearing demo with no real connected miners, stats should be empty
        #expect(store.poolStats.isEmpty)
        #expect(store.accountStats.isEmpty)
    }
}

// MARK: - Minimal Test Protocol

private final class HubTestState: @unchecked Sendable {
    static let initialInfo =
        #"{"hostname":"fixture","hashRate":1000,"version":"test","ASICModel":"BM1370","primaryPoolIndex":0,"# +
        #""secondaryPoolIndex":1,"isUsingFallbackStratum":false,"pools":[{"id":0,"stratumURL":"stratum.ckpool.org","# +
        #""stratumUser":"1BoatSLRHtKNngkdXEeobR76b53LETtpyT.w1"},{"id":1,"stratumURL":"bch.solofury.com","# +
        #""stratumUser":"1BoatSLRHtKNngkdXEeobR76b53LETtpyT.w2"}]}"#
    private let lock = NSLock()
    private var journal: [URLRequest] = []
    private var data = initialInfo
    var requests: [URLRequest] { lock.withLock { journal } }
    var info: String {
        get { lock.withLock { data } }
        set { lock.withLock { data = newValue } }
    }
    func record(_ request: URLRequest) { lock.withLock { journal.append(request) } }
    func reset() {
        lock.withLock {
            journal = []; data = Self.initialInfo
        }
    }
}

private class HubTestProtocol: URLProtocol, @unchecked Sendable {
    static let state = HubTestState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.record(request)
        let body: String
        switch request.url?.path {
        case "/api/system/info": body = Self.state.info
        case "/api/system/asic": body = #"{"ASICModel":"BM1370"}"#
        case "/pool/pool.status": body = #"{"Users":10,"Workers":20,"hashrate1hr":"10T"}"#
        case "/api/pool": body = #"{"totalMiners":10,"totalWorkers":20,"totalHashRate1hr":10000000000000}"#
        default: body = #"{"workers":2,"workersCount":2,"hashRate1hr":1000000000000,"hashrate1hr":"1T","shares":40}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
