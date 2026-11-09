import Foundation
import HashFleetWatchCore

/// Launch-argument handling.
///
/// - `--ui-testing`: in-memory real store with a deterministic local client. Starts EMPTY and never touches
///   production storage or the network.
/// - `--ui-testing-seeded`: adds three fixture miners (one always unreachable).
/// - `--ui-testing-stale`: seeded, but fetched readings carry a genuinely old `observedAt`.
/// - `--ui-testing-offline`: every fixture fetch fails.
/// - `--demo`: starts in the isolated demo store. The real store is only constructed when demo is exited.
struct WatchLaunchConfiguration: Sendable {
    var isUITesting = false
    var seedsFixtures = false
    var usesStaleReadings = false
    var isOffline = false
    var startsInDemo = false
    var usesSlowRefresh = false
    var discoveryFixture = UITestingMinerDiscovery.Mode.empty

    static var current: WatchLaunchConfiguration {
        parse(ProcessInfo.processInfo.arguments)
    }

    static func parse(_ arguments: [String]) -> WatchLaunchConfiguration {
        var configuration = WatchLaunchConfiguration()
        let stale = arguments.contains("--ui-testing-stale")
        configuration.isUITesting = arguments.contains { $0.hasPrefix("--ui-testing") }
        configuration.usesStaleReadings = stale
        configuration.seedsFixtures = arguments.contains("--ui-testing-seeded") || stale
        configuration.isOffline = arguments.contains("--ui-testing-offline")
        configuration.startsInDemo = arguments.contains("--demo")
        configuration.usesSlowRefresh = arguments.contains("--ui-testing-refresh-slow")
        if arguments.contains("--ui-testing-discovery-found") { configuration.discoveryFixture = .found }
        if arguments.contains("--ui-testing-discovery-stalled") { configuration.discoveryFixture = .stalled }
        if arguments.contains("--ui-testing-discovery-unavailable") { configuration.discoveryFixture = .unavailable }
        return configuration
    }

    /// Test launches never construct a live discovery scanner. Production scans still start only in an active real scene.
    @MainActor
    func makeDiscoveryController() -> WatchMinerDiscoveryController {
        if isUITesting {
            return WatchMinerDiscoveryController(discovery: UITestingMinerDiscovery(mode: discoveryFixture))
        }
        return WatchMinerDiscoveryController()
    }

    /// The isolated demo store. Never reads production storage and never contacts a miner.
    @MainActor
    func makeDemoStore() -> WatchFleetStore {
        WatchFleetStore.demo()
    }

    /// The real (or UI-testing) inventory store. Call lazily so `--demo` launches never open production storage.
    @MainActor
    func makeRealStore() -> WatchFleetStore {
        guard isUITesting else { return WatchFleetStore() }
        let client = UITestingReadingClient(isOffline: isOffline, usesStaleReadings: usesStaleReadings, usesSlowRefresh: usesSlowRefresh)
        let store = WatchFleetStore(storageURL: nil, client: client)
        if seedsFixtures {
            try? store.addMiner(name: "Gamma A", address: "192.168.1.21")
            try? store.addMiner(name: "Gamma B", address: "192.168.1.22")
            try? store.addMiner(name: "Duo", address: "192.168.1.26")
        }
        return store
    }
}

/// Deterministic discovery with no interface enumeration, sockets or HTTP requests.
struct UITestingMinerDiscovery: WatchMinerDiscovering {
    enum Mode: Sendable { case empty, found, stalled, unavailable }
    let mode: Mode

    func scan(onProgress: @escaping @Sendable (WatchDiscoveryProgress) async -> Void) async throws -> WatchDiscoveryResult {
        await onProgress(WatchDiscoveryProgress(miners: [], completedHosts: 1, totalHosts: 253, isPartialSubnet: false))
        if mode == .stalled { try await Task.sleep(for: .seconds(3_600)) }
        try Task.checkCancellation()
        if mode == .unavailable { throw WatchDiscoveryError.noLocalWiFi }
        let miners = mode == .found ? [
            try WatchMiner(name: "Workshop Gamma", address: "192.168.1.31"),
            try WatchMiner(name: "Rack Duo", address: "192.168.1.32")
        ] : []
        return WatchDiscoveryResult(miners: miners, completedHosts: 253, totalHosts: 253, isPartialSubnet: false, reachedTimeLimit: false)
    }
}

/// Deterministic, network-free reading source for UI tests.
struct UITestingReadingClient: WatchMinerReadingClient {
    struct Unreachable: LocalizedError {
        var errorDescription: String? { "Couldn't reach this miner." }
    }

    let isOffline: Bool
    var usesStaleReadings = false
    var usesSlowRefresh = false

    func fetch(_ miner: WatchMiner) async throws -> WatchMinerReading {
        if usesSlowRefresh { try await Task.sleep(for: .seconds(5)) }
        if isOffline || miner.name == "Duo" { throw Unreachable() }
        // Stale fixtures keep a real old timestamp so freshness logic is exercised, not bypassed.
        let observedAt = usesStaleReadings ? Date().addingTimeInterval(-3_600) : Date()
        return WatchMinerReading(
            minerID: miner.id,
            observedAt: observedAt,
            hashrateGHs: 1_020,
            powerWatts: 14.2,
            chipTemperatureC: 58,
            vrTemperatureC: 49,
            uptimeSeconds: 93_600,
            acceptedShares: 1_204,
            rejectedShares: 3,
            isMiningPaused: false
        )
    }
}
