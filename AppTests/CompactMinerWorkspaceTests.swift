import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// The compact miner workspace shows pools inside a single miner's screen. That screen must resolve
/// and query only that miner. These tests use two miners with different payout addresses so a
/// scoping regression shows up as another miner's address appearing in an outbound request, which is
/// the actual privacy consequence, not just as a wrong count.
@Suite(.serialized) @MainActor
struct CompactMinerWorkspaceTests {
    private let addressA = "1BoatSLRHtKNngkdXEeobR76b53LETtpyT"
    private let addressB = "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"

    private struct WorkspaceTestEnv {
        let fleet: FleetStore
        let store: ConnectedPoolsStore
        let defaults: UserDefaults
        let suite: String
        let devices: [MinerDevice]
    }

    private func setup() throws -> WorkspaceTestEnv {
        WorkspaceScopeProtocol.state.reset()
        let suite = "app.hashfleet.workspace-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let devices = [
            MinerDevice(name: "Miner A", address: "miner-a.invalid"),
            MinerDevice(name: "Miner B", address: "miner-b.invalid")
        ]
        defaults.set(try JSONEncoder().encode(devices), forKey: "app.hashfleet.devices.v1")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WorkspaceScopeProtocol.self]
        let session = URLSession(configuration: config)
        return WorkspaceTestEnv(
            fleet: FleetStore(defaults: defaults, session: session),
            store: ConnectedPoolsStore(session: session),
            defaults: defaults,
            suite: suite,
            devices: devices
        )
    }

    /// Resolution is the gate that authorizes a lookup, so it must be scoped before any request is
    /// built. A `nil` scope keeps the fleet-wide behavior the dashboard card relied on.
    @Test func scopedResolutionCoversOnlyTheSelectedMiner() async throws {
        let workspaceEnv = try setup()
        let fleet = workspaceEnv.fleet
        let defaults = workspaceEnv.defaults
        let suite = workspaceEnv.suite
        let devices = workspaceEnv.devices
        defer { defaults.removePersistentDomain(forName: suite) }
        await fleet.refresh()

        let all = ConnectedPoolsStore.configuredPools(fleet: fleet)
        #expect(all.contains { $0.address == addressA })
        #expect(all.contains { $0.address == addressB })

        let scopedA = ConnectedPoolsStore.configuredPools(fleet: fleet, deviceID: devices[0].id)
        #expect(!scopedA.isEmpty)
        #expect(scopedA.allSatisfy { $0.address == addressA })
        #expect(!scopedA.contains { $0.address == addressB })

        let scopedB = ConnectedPoolsStore.configuredPools(fleet: fleet, deviceID: devices[1].id)
        #expect(!scopedB.isEmpty)
        #expect(scopedB.allSatisfy { $0.address == addressB })

        // An unknown identifier must resolve to nothing rather than silently falling back to the fleet.
        #expect(ConnectedPoolsStore.configuredPools(fleet: fleet, deviceID: UUID()).isEmpty)
    }

    @Test func workspaceScopeNeverQueriesAnotherMinersPayoutAddress() async throws {
        let workspaceEnv = try setup()
        let fleet = workspaceEnv.fleet
        let store = workspaceEnv.store
        let defaults = workspaceEnv.defaults
        let suite = workspaceEnv.suite
        let devices = workspaceEnv.devices
        defer { defaults.removePersistentDomain(forName: suite) }
        await fleet.refresh()
        await store.refresh(fleet: fleet, deviceID: devices[0].id)

        let requests = WorkspaceScopeProtocol.state.publicRequests
        #expect(!requests.isEmpty)
        let paths = requests.compactMap { $0.url?.path }
        #expect(paths.contains { $0.contains(addressA) })
        #expect(!paths.contains { $0.contains(addressB) })
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })

        // Published state is scoped too, so a scoped screen cannot render another miner's account.
        #expect(!store.accountStats.isEmpty)
        #expect(store.accountStats.keys.allSatisfy { $0.address == addressA })
    }

    /// The dashboard card keeps calling without a scope. That path must be unchanged, otherwise
    /// scoping would have silently narrowed the fleet-wide card too.
    @Test func unscopedRefreshStillCoversEveryOnlineMiner() async throws {
        let workspaceEnv = try setup()
        let fleet = workspaceEnv.fleet
        let store = workspaceEnv.store
        let defaults = workspaceEnv.defaults
        let suite = workspaceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        await fleet.refresh()
        await store.refresh(fleet: fleet)

        let paths = WorkspaceScopeProtocol.state.publicRequests.compactMap { $0.url?.path }
        #expect(paths.contains { $0.contains(addressA) })
        #expect(paths.contains { $0.contains(addressB) })
        #expect(Set(store.accountStats.keys.map(\.address)) == [addressA, addressB])
    }

    /// Changing scope on one store must discard the previous scope's results instead of merging
    /// them, so navigating between miners cannot accumulate a cross-miner view.
    @Test func changingScopeReplacesRatherThanMergesResults() async throws {
        let workspaceEnv = try setup()
        let fleet = workspaceEnv.fleet
        let store = workspaceEnv.store
        let defaults = workspaceEnv.defaults
        let suite = workspaceEnv.suite
        let devices = workspaceEnv.devices
        defer { defaults.removePersistentDomain(forName: suite) }
        await fleet.refresh()
        await store.refresh(fleet: fleet, deviceID: devices[0].id)
        #expect(store.accountStats.keys.allSatisfy { $0.address == addressA })

        await store.refresh(fleet: fleet, deviceID: devices[1].id)
        #expect(!store.accountStats.isEmpty)
        #expect(store.accountStats.keys.allSatisfy { $0.address == addressB })
        #expect(!store.accountStats.keys.contains { $0.address == addressA })
    }

    /// Scoped demo mode must still send nothing and must still present only values traceable to the
    /// scoped miner's own configured pools.
    ///
    /// Deliberate limitation, stated so this test is not read as more than it is: every miner in
    /// `DemoFleet` is given the same two pools and the same two payout addresses, so no assertion on
    /// this fixture can distinguish scoped from unscoped demo loading. Cross-miner scoping is proven
    /// by the non-demo tests above, which use two miners with different addresses. What this test
    /// does prove is that adding a scope did not introduce a network call into demo mode and did not
    /// let unrelated values into scoped demo state.
    @Test func scopedDemoSendsNothingAndStaysTraceableToTheScopedMiner() async throws {
        let workspaceEnv = try setup()
        let fleet = workspaceEnv.fleet
        let store = workspaceEnv.store
        let defaults = workspaceEnv.defaults
        let suite = workspaceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        fleet.loadDemo()
        let demoDevice = try #require(fleet.devices.first)

        await store.refresh(fleet: fleet, deviceID: demoDevice.id)
        #expect(!store.accountStats.isEmpty)
        #expect(WorkspaceScopeProtocol.state.requests.isEmpty)

        // Everything presented must be traceable to this device's own configured pools.
        let scoped = ConnectedPoolsStore.configuredPools(fleet: fleet, deviceID: demoDevice.id)
        let allowedAddresses = Set(scoped.compactMap(\.address))
        let allowedPools = Set(
            scoped.compactMap { pool -> PoolKey? in
                guard let provider = pool.provider else { return nil }
                return PoolKey(provider: provider, coin: pool.coin)
            }
        )
        #expect(store.accountStats.keys.allSatisfy { allowedAddresses.contains($0.address) })
        #expect(store.poolStats.keys.allSatisfy { allowedPools.contains($0) })

        await store.refresh(fleet: fleet)
        #expect(WorkspaceScopeProtocol.state.requests.isEmpty)
    }

    /// Opting out or losing a fresh reading must win over the scope, exactly as it does fleet-wide.
    @Test func scopedRefreshStillHonorsOptOutAndStaleTelemetry() async throws {
        let workspaceEnv = try setup()
        let fleet = workspaceEnv.fleet
        let store = workspaceEnv.store
        let defaults = workspaceEnv.defaults
        let suite = workspaceEnv.suite
        let devices = workspaceEnv.devices
        defer { defaults.removePersistentDomain(forName: suite) }
        await fleet.refresh()
        fleet.preferences.externalDataEnabled = false
        await store.refresh(fleet: fleet, deviceID: devices[0].id)
        #expect(WorkspaceScopeProtocol.state.publicRequests.isEmpty)
        #expect(store.accountStats.isEmpty && store.poolStats.isEmpty)

        fleet.preferences.externalDataEnabled = true
        WorkspaceScopeProtocol.state.infoStatus = 503
        await fleet.refresh()
        await store.refresh(fleet: fleet, deviceID: devices[0].id)
        #expect(WorkspaceScopeProtocol.state.publicRequests.isEmpty)
        #expect(store.accountStats.isEmpty)
    }
}

private final class WorkspaceScopeState: @unchecked Sendable {
    /// Two miners with distinct payout addresses. Miner A uses CKPool and SoloFury BCH; miner B uses
    /// SoloFury BCH only. Any request naming B's address while scoped to A is a scope leak.
    static func info(address: String, includeCKPool: Bool) -> String {
        var pools = ""
        if includeCKPool {
            pools += #"{"id":0,"stratumURL":"stratum.ckpool.org","stratumUser":"\#(address).w1"},"#
        }
        pools += #"{"id":1,"stratumURL":"bch.solofury.com","stratumUser":"\#(address).w2"}"#
        return #"{"hostname":"fixture","hashRate":1000,"version":"test","ASICModel":"BM1370","# +
            #""primaryPoolIndex":\#(includeCKPool ? 0 : 1),"secondaryPoolIndex":1,"# +
            #""isUsingFallbackStratum":false,"pools":[\#(pools)]}"#
    }

    private let lock = NSLock()
    private var journal: [URLRequest] = []
    private var infoCode = 200
    var requests: [URLRequest] { lock.withLock { journal } }
    var publicRequests: [URLRequest] {
        requests.filter { !($0.url?.host?.hasSuffix(".invalid") ?? false) }
    }
    var infoStatus: Int {
        get { lock.withLock { infoCode } }
        set { lock.withLock { infoCode = newValue } }
    }
    func record(_ request: URLRequest) { lock.withLock { journal.append(request) } }
    func reset() {
        lock.withLock {
            journal = []; infoCode = 200
        }
    }
}

private class WorkspaceScopeProtocol: URLProtocol, @unchecked Sendable {
    static let state = WorkspaceScopeState()
    static let addressA = "1BoatSLRHtKNngkdXEeobR76b53LETtpyT"
    static let addressB = "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.record(request)
        let host = request.url?.host ?? ""
        let isMiner = host.hasSuffix(".invalid")
        var status = isMiner ? Self.state.infoStatus : 200
        let body: String
        switch request.url?.path {
        case "/api/system/info":
            body = WorkspaceScopeState.info(
                address: host == "miner-a.invalid" ? Self.addressA : Self.addressB,
                includeCKPool: host == "miner-a.invalid"
            )
        case "/api/system/asic":
            body = #"{"ASICModel":"BM1370"}"#
            status = 200
        case "/pool/pool.status":
            body = #"{"Users":10,"Workers":20,"hashrate1hr":"10T"}"#
        case "/api/pool":
            body = #"{"totalMiners":10,"totalWorkers":20,"totalHashRate1hr":10000000000000}"#
        default:
            body = #"{"workers":2,"workersCount":2,"hashRate1hr":1000000000000,"hashrate1hr":"1T","shares":40}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
