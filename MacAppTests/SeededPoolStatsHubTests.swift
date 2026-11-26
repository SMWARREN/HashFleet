import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Tests evaluating the disclosure branches and account states in PoolStatsHubView.
/// Uses installed preview results on ConnectedPoolsStore with valid addresses so the
/// account statistics, found/failed/not-found branches, and metrics render completely offline.
@Suite("Seeded Pool Stats Hub Evaluation", .serialized)
@MainActor
struct SeededPoolStatsHubTests {
    private func evaluate<V: View>(_ view: V, width: CGFloat = 800, height: CGFloat = 1200) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private func makeStore() throws -> (FleetStore, MinerDevice, UserDefaults, String) {
        let suite = "app.hashfleet.mac.poolhub.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let fleet = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        fleet.preferences.externalDataEnabled = true
        let device = MinerDevice(name: "AxeRig", address: "192.168.1.100")
        fleet.devices = [device]

        // Valid addresses for Bitcoin (SegWit) and Bitcoin Cash (CashAddress)
        let validBTCAddress = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
        let validBCHAddress = "bitcoincash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpyy"

        let raw: [String: JSONValue] = [
            "hostname": .string("AxeRig"),
            "stratumURL": .string("solo.ckpool.org"),
            "stratumPort": .integer(3333),
            "stratumUser": .string("\(validBTCAddress).workerA"),
            "fallbackStratumURL": .string("bch.solofury.com"),
            "fallbackStratumPort": .integer(3333),
            "fallbackStratumUser": .string("\(validBCHAddress).workerB"),
            "isUsingFallbackStratum": .bool(false)
        ]

        let info = MinerInfo(raw: raw)
        fleet.snapshots[device.id] = MinerSnapshot(
            info: info, previousInfo: nil, error: nil, updatedAt: Date(),
            completeSnapshotAt: Date(), powerObservedAt: Date(),
            history: [], isCached: false, isReconnecting: false
        )
        return (fleet, device, defaults, suite)
    }

    @Test func evaluatePoolStatsHubAccountFoundStates() throws {
        let (fleet, _, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let validBTCAddress = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
        let btcAccountKey = AccountKey(
            provider: .ckpool,
            coin: .btc,
            address: validBTCAddress,
            host: "solo.ckpool.org"
        )
        let btcPoolKey = PoolKey(provider: .ckpool, coin: .btc)

        let source = URL(string: "https://solo.ckpool.org")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let poolStats = ConnectedPoolStats(
            hashRate1hrHPS: 1_250_000_000_000_000,
            hashRate1dHPS: 980_000_000_000_000,
            users: 100,
            workers: 42,
            bestShare: 18.4
        )

        let accountStats = ConnectedAccountStats(
            hashRate1hrHPS: 1_180_000_000_000,
            hashRate1dHPS: 980_000_000_000,
            workersCount: 3,
            shares: 45_120,
            bestShare: 54.2,
            bestEver: 128.5,
            lastShare: now
        )

        let poolStore = ConnectedPoolsStore()
        poolStore.installPreviewResults(
            poolStats: [btcPoolKey: MiningDataResult(value: poolStats, fetchedAt: now, sourceURL: source, sourceTimestamp: now)],
            accountStats: [btcAccountKey: .found(MiningDataResult(value: accountStats, fetchedAt: now, sourceURL: source, sourceTimestamp: now))]
        )

        let hubView = PoolStatsHubView(fleet: fleet, store: poolStore)
        evaluate(hubView, width: 900, height: 1400)
        evaluate(hubView, width: 420, height: 1600)
    }

    @Test func evaluatePoolStatsHubAccountNotFoundAndFailedBranches() throws {
        let (fleet, _, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let validBTCAddress = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
        let btcAccountKey = AccountKey(
            provider: .ckpool,
            coin: .btc,
            address: validBTCAddress,
            host: "solo.ckpool.org"
        )
        let btcPoolKey = PoolKey(provider: .ckpool, coin: .btc)

        let validBCHAddress = "bitcoincash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpyy"
        let bchAccountKey = AccountKey(
            provider: .soloFury,
            coin: .bch,
            address: validBCHAddress,
            host: "bch.solofury.com"
        )
        let bchPoolKey = PoolKey(provider: .soloFury, coin: .bch)

        let source = URL(string: "https://solo.ckpool.org")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let poolStore = ConnectedPoolsStore()

        // Test notFound and failed branches
        poolStore.installPreviewResults(
            poolStats: [
                btcPoolKey: MiningDataResult(error: .timedOut, fetchedAt: now, sourceURL: source),
                bchPoolKey: MiningDataResult(error: .http(statusCode: 500), fetchedAt: now, sourceURL: source)
            ],
            accountStats: [
                btcAccountKey: .notFound(fetchedAt: now),
                bchAccountKey: .failed(.http(statusCode: 404))
            ],
            isRefreshing: false
        )

        evaluate(PoolStatsHubView(fleet: fleet, store: poolStore), width: 800, height: 1200)

        // Test refreshing with no results
        let loadingStore = ConnectedPoolsStore()
        loadingStore.installPreviewResults(
            poolStats: [:],
            accountStats: [:],
            isRefreshing: true
        )
        evaluate(PoolStatsHubView(fleet: fleet, store: loadingStore), width: 800, height: 1200)

        // Test accountFoundContent with error
        let errorResultStore = ConnectedPoolsStore()
        errorResultStore.installPreviewResults(
            poolStats: [:],
            accountStats: [
                btcAccountKey: .found(MiningDataResult(value: nil, error: .timedOut, fetchedAt: now, sourceURL: source))
            ]
        )
        evaluate(PoolStatsHubView(fleet: fleet, store: errorResultStore), width: 800, height: 1200)
    }
}
