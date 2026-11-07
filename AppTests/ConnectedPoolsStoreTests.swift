import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized) @MainActor
struct ConnectedPoolsStoreTests {
    private let address = "1BoatSLRHtKNngkdXEeobR76b53LETtpyT"

    private struct PoolTestEnv {
        let fleet: FleetStore
        let store: ConnectedPoolsStore
        let defaults: UserDefaults
        let suite: String
    }

    private func setup(cooldown: TimeInterval = 60) throws -> PoolTestEnv {
        PoolAcceptanceProtocol.state.reset()
        let suite = "app.hashfleet.pool-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let devices = [MinerDevice(name: "Read-only fixture", address: "miner.invalid")]
        defaults.set(try JSONEncoder().encode(devices), forKey: "app.hashfleet.devices.v1")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PoolAcceptanceProtocol.self]
        let session = URLSession(configuration: config)
        return PoolTestEnv(
            fleet: FleetStore(defaults: defaults, session: session),
            store: ConnectedPoolsStore(session: session, cooldown: cooldown),
            defaults: defaults,
            suite: suite
        )
    }

    @Test func demoAndOptOutNeverRequestExternalData() async throws {
        let poolEnv = try setup()
        let fleet = poolEnv.fleet
        let store = poolEnv.store
        let defaults = poolEnv.defaults
        let suite = poolEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        fleet.loadDemo()
        await store.refresh(fleet: fleet)
        #expect(store.poolStats.count == 2 && store.accountStats.count == 2)
        #expect(PoolAcceptanceProtocol.state.requests.isEmpty)
        fleet.preferences.externalDataEnabled = false
        await store.refresh(fleet: fleet)
        #expect(store.poolStats.isEmpty && store.accountStats.isEmpty)
        #expect(PoolAcceptanceProtocol.state.requests.isEmpty)
        fleet.clearDemo()
        fleet.preferences.externalDataEnabled = true
        await store.refresh(fleet: fleet)
        #expect(store.poolStats.isEmpty && store.accountStats.isEmpty)
    }

    @Test func allSlotsUseCorrectCoinEndpointsAndDeduplicateAccounts() async throws {
        let poolEnv = try setup()
        let fleet = poolEnv.fleet
        let store = poolEnv.store
        let defaults = poolEnv.defaults
        let suite = poolEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        await fleet.refresh()
        await store.refresh(fleet: fleet)
        #expect(store.poolStats.count == 2 && store.accountStats.count == 2)
        let publicRequests = PoolAcceptanceProtocol.state.publicRequests
        #expect(publicRequests.count == 4)
        #expect(publicRequests.contains { $0.url?.path == "/api/client/\(address)" })
        #expect(publicRequests.contains { $0.url?.path == "/users/\(address)" })
        #expect(!publicRequests.contains { $0.url?.path.contains("/api-btc/client/") == true })
        #expect(publicRequests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && $0.url?.query == nil })
        for result in store.accountStats.values {
            guard case .found(let data) = result else { Issue.record("Expected account fixture"); continue }
            #expect(data.value?.shares == 40)
        }
        await store.refresh(fleet: fleet)
        #expect(PoolAcceptanceProtocol.state.publicRequests.count == 4)
        let key1 = AccountKey(provider: .soloFury, coin: .bch, address: address, host: "bch.solofury.com")
        let key2 = AccountKey(provider: .soloFury, coin: .bch, address: address, host: "eu-bch.solofury.com")
        #expect(Set([key1, key2]).count == 1)
    }

    @Test func identicalPoolPayloadsDoNotReplacePublishedResults() async throws {
        let poolEnv = try setup(cooldown: 0)
        let fleet = poolEnv.fleet
        let store = poolEnv.store
        let defaults = poolEnv.defaults
        let suite = poolEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }

        await fleet.refresh()
        await store.refresh(fleet: fleet)
        let poolKey = PoolKey(provider: .soloFury, coin: .bch)
        let accountKey = AccountKey(
            provider: .soloFury, coin: .bch, address: address, host: "bch.solofury.com"
        )
        let firstPoolFetch: Date
        let firstAccountFetch: Date
        if let result = store.poolStats[poolKey] {
            firstPoolFetch = result.fetchedAt
        } else {
            Issue.record("Expected a pool result")
            return
        }
        if case .found(let result)? = store.accountStats[accountKey] {
            firstAccountFetch = result.fetchedAt
        } else {
            Issue.record("Expected an account result")
            return
        }

        await store.refresh(fleet: fleet)
        let secondPoolFetch = store.poolStats[poolKey]?.fetchedAt
        let secondAccountFetch: Date?
        if case .found(let result)? = store.accountStats[accountKey] {
            secondAccountFetch = result.fetchedAt
        } else {
            secondAccountFetch = nil
        }

        #expect(secondPoolFetch == firstPoolFetch)
        #expect(secondAccountFetch == firstAccountFetch)
    }

    @Test func unknownPoolAndOfflineSnapshotsNeverAuthorizeLookup() async throws {
        let poolEnv = try setup()
        let fleet = poolEnv.fleet
        let store = poolEnv.store
        let defaults = poolEnv.defaults
        let suite = poolEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        PoolAcceptanceProtocol.state.info =
            #"{"hostname":"unknown","stratumURL":"fake-ckpool.org","# +
            #""stratumUser":"1BoatSLRHtKNngkdXEeobR76b53LETtpyT.w"}"#
        await fleet.refresh()
        await store.refresh(fleet: fleet)
        #expect(PoolAcceptanceProtocol.state.publicRequests.isEmpty)
        PoolAcceptanceProtocol.state.info = PoolAcceptanceState.initialInfo
        await fleet.refresh()
        PoolAcceptanceProtocol.state.infoStatus = 503
        await fleet.refresh()
        await store.refresh(fleet: fleet)
        #expect(PoolAcceptanceProtocol.state.publicRequests.isEmpty)
        #expect(store.accountStats.isEmpty)
    }

    @Test func configurationChangesAndRemovalCannotPublishDelayedAccounts() async throws {
        let poolEnv = try setup()
        let fleet = poolEnv.fleet
        let store = poolEnv.store
        let defaults = poolEnv.defaults
        let suite = poolEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        await fleet.refresh()
        PoolAcceptanceProtocol.state.holdPublic = true
        let task = Task { await store.refresh(fleet: fleet) }
        for _ in 0..<100 {
            if !PoolAcceptanceProtocol.state.publicRequests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.isRefreshing)
        #expect(!PoolAcceptanceProtocol.state.publicRequests.isEmpty)
        fleet.remove(fleet.devices[0])
        await store.refresh(fleet: fleet)
        await task.value
        #expect(store.poolStats.isEmpty && store.accountStats.isEmpty)
        #expect(!store.isRefreshing)
    }

    @Test func reconfigurationReplacesOldKeysAndErrorsNeverExposeProviderBodies() async throws {
        let poolEnv = try setup()
        let fleet = poolEnv.fleet
        let store = poolEnv.store
        let defaults = poolEnv.defaults
        let suite = poolEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        await fleet.refresh()
        await store.refresh(fleet: fleet)
        let replacement = "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"
        PoolAcceptanceProtocol.state.info = PoolAcceptanceState.initialInfo.replacingOccurrences(
            of: address,
            with: replacement
        )
        PoolAcceptanceProtocol.state.publicStatus = 503
        await fleet.refresh()
        await store.refresh(fleet: fleet)
        #expect(!store.accountStats.keys.contains { $0.address == address })
        #expect(store.accountStats.count == 2)
        for result in store.accountStats.values {
            guard case .failed(let error) = result else { Issue.record("Expected safe failure"); continue }
            #expect(!error.localizedDescription.contains("PRIVATE_BODY"))
            #expect(error == .http(statusCode: 503))
        }
        store.clear()
        #expect(store.accountStats.isEmpty && store.poolStats.isEmpty)
    }
}

private final class PoolAcceptanceState: @unchecked Sendable {
    static let initialInfo =
        #"{"hostname":"fixture","hashRate":1000,"version":"test","ASICModel":"BM1370","primaryPoolIndex":0,"# +
        #""secondaryPoolIndex":1,"isUsingFallbackStratum":false,"pools":[{"id":0,"stratumURL":"stratum.ckpool.org","# +
        #""stratumUser":"1BoatSLRHtKNngkdXEeobR76b53LETtpyT.w1"},{"id":1,"stratumURL":"bch.solofury.com","# +
        #""stratumUser":"1BoatSLRHtKNngkdXEeobR76b53LETtpyT.w2"},{"id":2,"stratumURL":"eu-bch.solofury.com","# +
        #""stratumUser":"1BoatSLRHtKNngkdXEeobR76b53LETtpyT.w3"}]}"#
    private let lock = NSLock()
    private var journal: [URLRequest] = []
    private var data = initialInfo
    private var infoCode = 200
    private var publicCode = 200
    private var hold = false
    var requests: [URLRequest] { lock.withLock { journal } }
    var publicRequests: [URLRequest] { requests.filter { $0.url?.host != "miner.invalid" } }
    var info: String {
        get { lock.withLock { data } }
        set { lock.withLock { data = newValue } }
    }
    var infoStatus: Int {
        get { lock.withLock { infoCode } }
        set { lock.withLock { infoCode = newValue } }
    }
    var publicStatus: Int {
        get { lock.withLock { publicCode } }
        set { lock.withLock { publicCode = newValue } }
    }
    var holdPublic: Bool {
        get { lock.withLock { hold } }
        set { lock.withLock { hold = newValue } }
    }
    func record(_ request: URLRequest) { lock.withLock { journal.append(request) } }
    func reset() {
        lock.withLock {
            journal = []; data = Self.initialInfo; infoCode = 200; publicCode = 200; hold = false
        }
    }
}
private class PoolAcceptanceProtocol: URLProtocol, @unchecked Sendable {
    static let state = PoolAcceptanceState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.record(request)
        let isMiner = request.url?.host == "miner.invalid"
        if !isMiner && Self.state.holdPublic { return }
        var status = isMiner ? Self.state.infoStatus : Self.state.publicStatus
        let body: String
        switch request.url?.path {
        case "/api/system/info": body = Self.state.info
        case "/api/system/asic": body = #"{"ASICModel":"BM1370"}"#; status = 200
        case "/pool/pool.status": body = #"{"Users":10,"Workers":20,"hashrate1hr":"10T"}"#
        case "/api/pool": body = #"{"totalMiners":10,"totalWorkers":20,"totalHashRate1hr":10000000000000}"#
        default:
            body =
                status == 200
                ? #"{"workers":2,"workersCount":2,"hashRate1hr":1000000000000,"hashrate1hr":"1T","shares":40}"#
                : #"{"error":"PRIVATE_BODY_DO_NOT_DISPLAY"}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
