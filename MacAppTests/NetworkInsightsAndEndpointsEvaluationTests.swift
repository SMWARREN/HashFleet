import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Evaluation coverage for the network insights, connected-pool, miner-endpoint, and developer
/// tip jar surfaces. Each view is hosted in an off-screen window and forced through a layout pass
/// so the real SwiftUI body, `@ViewBuilder` branches, and state-dependent sections execute without
/// contacting a miner, a pool API, or the App Store.
@Suite("Network Insights And Endpoints Evaluation", .serialized)
@MainActor
struct NetworkInsightsAndEndpointsTests {
    private func makeStore(demo: Bool = true) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.netinsights.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let session = URLSession(configuration: .ephemeral)
        let store = FleetStore(defaults: defaults, session: session)
        if demo { store.loadDemo() }
        return (store, defaults, suite)
    }

    private func evaluate<V: View>(_ view: V, width: CGFloat = 800, height: CGFloat = 1200) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    /// A reasonably complete ESP-Miner Info payload carrying cooling, tuning, and pool fields so the
    /// availability checks and write-eligible branches can take their populated paths.
    private func fullInfo(name: String = "Rig One") -> MinerInfo {
        MinerInfo(raw: [
            "hostname": .string(name), "macAddr": .string("A1:B2:C3:D4:E5:F6"),
            "version": .string("v2.15.2"), "ASICModel": .string("BM1370"),
            "hashRate": .number(1180), "power": .number(19.4), "voltage": .number(5200),
            "temp": .number(54), "vrTemp": .number(61), "fanspeed": .number(68),
            "fanrpm": .number(4200), "frequency": .number(575), "coreVoltage": .number(1150),
            "sharesAccepted": .number(12486), "sharesRejected": .number(3),
            "uptimeSeconds": .number(245820), "wifiRSSI": .number(-48),
            "bestDiff": .string("18.4G"), "bestSessionDiff": .string("9.2M"),
            "stratumURL": .string("solo.ckpool.org"), "stratumPort": .integer(3333),
            "stratumUser": .string("bc1qexampleworker.rig"),
            "fallbackStratumURL": .string("bch.solofury.com"),
            "fallbackStratumPort": .integer(3333),
            "fallbackStratumUser": .string("bitcoincash:qexample.rig")
        ])
    }

    /// A non-demo store with one real device and a fresh, writable snapshot.
    private func makeLiveStore() throws -> (FleetStore, MinerDevice, UserDefaults, String) {
        let (store, defaults, suite) = makeStore(demo: false)
        try store.add(name: "Rig One", address: "192.168.1.50")
        let device = try #require(store.devices.first)
        store.snapshots[device.id] = MinerSnapshot(
            info: fullInfo(), previousInfo: nil, error: nil, updatedAt: Date(),
            completeSnapshotAt: Date(), powerObservedAt: Date(), history: [],
            isCached: false, isReconnecting: false
        )
        return (store, device, defaults, suite)
    }

    /// A demo insights store with sample network, pool, and coin data applied synchronously.
    private func makeDemoInsights() async -> MiningInsightsStore {
        let insights = MiningInsightsStore()
        insights.setDemo(true)
        await insights.refresh()
        return insights
    }

    // MARK: - NetworkInsightsView

    @Test func evaluateNetworkInsightsDemoAndCards() async throws {
        let (fleet, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = await makeDemoInsights()
        let view = NetworkInsightsView(fleet: fleet, insights: insights)
        let now = Date()

        evaluate(view)
        evaluate(view, width: 420, height: 1600)
        evaluate(view.hubLinks)

        let network = MiningInsightsDemo.network
        evaluate(view.soloCard(network, now: now))
        evaluate(view.cashCard(MiningInsightsDemo.cash, now: now))
        evaluate(view.additionalCoinCard(.xec, result: MiningInsightsDemo.xec, now: now))
        evaluate(view.additionalCoinCard(.dgb, result: MiningInsightsDemo.dgb, now: now))
        evaluate(view.poolCard(MiningInsightsDemo.pool, now: now))
        for (coin, result) in insights.poolNetworks {
            evaluate(view.poolNetworkCard(coin, result: result, now: now))
        }
    }

    @Test func evaluateNetworkInsightsSoloOutcomes() async throws {
        let (fleet, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = await makeDemoInsights()
        let view = NetworkInsightsView(fleet: fleet, insights: insights)
        let now = Date()

        let scopes = view.soloOutcomeScopes(now: now)
        #expect(!scopes.isEmpty)
        let difficulty = try #require(MiningInsightsDemo.network.mining.value?.difficulty)
        for scope in scopes {
            evaluate(view.soloOutcomePage(scope: scope, difficulty: difficulty))
            _ = scope.id
            _ = scope.title
            _ = scope.subtitle
            _ = scope.hashrateHPS
        }

        for window in SoloOutcomeWindow.allCases {
            _ = window.id
            _ = window.duration
            _ = window.title
            _ = window.accessibilityTitle
            if let estimate = SoloMiningMath.estimate(
                hashrateHPS: 1e12, difficulty: difficulty, duration: window.duration
            ) {
                _ = NetworkInsightsView.probabilityText(estimate)
                _ = NetworkInsightsView.expectedBlocksText(estimate)
            }
        }
    }

    @Test func evaluateNetworkInsightsNonDemoAndEmpty() throws {
        // A non-demo fleet with external data disabled and no loaded insights takes the
        // "load public data" control and the empty-grid paths.
        let (fleet, defaults, suite) = makeStore(demo: false)
        defer { defaults.removePersistentDomain(forName: suite) }
        fleet.preferences.externalDataEnabled = false
        let insights = MiningInsightsStore()
        evaluate(NetworkInsightsView(fleet: fleet, insights: insights))

        fleet.preferences.externalDataEnabled = true
        evaluate(NetworkInsightsView(fleet: fleet, insights: insights))
        evaluate(NetworkInsightsView(fleet: fleet, insights: insights), width: 1280, height: 1000)
    }

    // MARK: - PoolStatsHubView

    @Test func evaluatePoolStatsHubStates() throws {
        let (demoFleet, demoDefaults, demoSuite) = makeStore(demo: true)
        defer { demoDefaults.removePersistentDomain(forName: demoSuite) }
        evaluate(PoolStatsHubView(fleet: demoFleet))
        evaluate(PoolStatsHubView(fleet: demoFleet), width: 420, height: 1600)

        // External data disabled takes the disabled-notice branch.
        let (offFleet, offDefaults, offSuite) = makeStore(demo: false)
        defer { offDefaults.removePersistentDomain(forName: offSuite) }
        offFleet.preferences.externalDataEnabled = false
        evaluate(PoolStatsHubView(fleet: offFleet))

        // External data enabled but no online miners takes the empty-notice branch.
        offFleet.preferences.externalDataEnabled = true
        evaluate(PoolStatsHubView(fleet: offFleet))
    }

    @Test func evaluatePoolStatsHubLiveMiner() throws {
        let (store, _, defaults, suite) = try makeLiveStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.preferences.externalDataEnabled = true
        evaluate(PoolStatsHubView(fleet: store))
        evaluate(PoolStatsHubView(fleet: store), width: 1280, height: 1000)
    }

    // MARK: - FleetPoolsCard+Stats

    @Test func evaluateFleetPoolsCardStatsAndBadges() throws {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        let card = FleetPoolsCard(fleet: store)
        evaluate(card)
        evaluate(card.statsDisclosure(
            provider: .ckpool, coin: .btc, address: "bc1qtest", host: "solo.ckpool.org"
        ))
        evaluate(card.statsDisclosure(provider: .soloFury, coin: nil, address: nil, host: "solofury.com"))
        evaluate(card.statsDisclosure(provider: .soloFury, coin: .bch, address: "", host: "solofury.com"))

        evaluate(card.activeBadge(true))
        evaluate(card.activeBadge(false))
        evaluate(card.coverageBadge(count: 0))
        evaluate(card.coverageBadge(count: 1))
        evaluate(card.coverageBadge(count: 4))
        for coin in MiningPoolCoin.allCases {
            evaluate(card.coinBadge(coin))
        }

        // External data off takes the disclosure "turned off" branch.
        store.preferences.externalDataEnabled = false
        let offCard = FleetPoolsCard(fleet: store)
        evaluate(offCard.statsDisclosure(
            provider: .ckpool, coin: .btc, address: "bc1qtest", host: "solo.ckpool.org"
        ))
    }

    @Test func evaluateFleetPoolsCardFetchedStatistics() throws {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.preferences.externalDataEnabled = true
        let card = FleetPoolsCard(fleet: store)
        let source = URL(string: "https://solo.ckpool.org")!
        let fetched = Date(timeIntervalSince1970: 1_700_000_000)
        let poolKey = PoolKey(provider: .ckpool, coin: .btc)
        let accountKey = AccountKey(provider: .ckpool, coin: .btc, address: "bc1qtest", host: "solo.ckpool.org")
        let stats = ConnectedPoolStats(hashRate1hrHPS: 1_250_000_000_000_000, workers: 42)
        let account = ConnectedAccountStats(
            hashRate1hrHPS: 1_180_000_000_000, hashRate1dHPS: 980_000_000_000,
            workersCount: 2, shares: 12_486, bestShare: 18.4, bestEver: 44.2,
            lastShare: fetched
        )

        card.store.installPreviewResults(
            poolStats: [poolKey: MiningDataResult(value: stats, fetchedAt: fetched, sourceURL: source, sourceTimestamp: fetched)],
            accountStats: [accountKey: .found(MiningDataResult(value: account, fetchedAt: fetched, sourceURL: source, sourceTimestamp: fetched))]
        )
        evaluate(card.statsDisclosure(provider: .ckpool, coin: .btc, address: "bc1qtest", host: "solo.ckpool.org"))

        card.store.installPreviewResults(
            poolStats: [poolKey: MiningDataResult(error: .timedOut, fetchedAt: fetched, sourceURL: source)],
            accountStats: [accountKey: .failed(.http(statusCode: 503))],
            isRefreshing: true
        )
        evaluate(card.statsDisclosure(provider: .ckpool, coin: .btc, address: "bc1qtest", host: "solo.ckpool.org"))

        card.store.installPreviewResults(
            accountStats: [accountKey: .notFound(fetchedAt: fetched)],
            isRefreshing: true
        )
        evaluate(card.statsDisclosure(provider: .ckpool, coin: .btc, address: "bc1qtest", host: "solo.ckpool.org"))
        evaluate(card.statsDisclosure(provider: .soloFury, coin: .bch, address: nil, host: "solofury.com"))
    }

    // MARK: - MinerEndpointView and MinerCompletionAlert

    @Test func evaluateMinerEndpointViewAcrossCatalog() throws {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = try #require(store.devices.first)
        let insights = MiningInsightsStore()

        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            for endpoint in MinerEndpoint.catalog where !endpoint.isWebSocket {
                let view = MinerEndpointView(
                    device: device, store: store, endpoint: endpoint, insights: insights
                )
                evaluate(view)
                _ = view.resolvedEndpoint
                _ = view.isBinary
                _ = view.needsJSON
                _ = view.isPool
                _ = view.canWrite
                _ = view.simpleCommandEffect
                _ = view.navigationIdentity
            }
        }
    }

    @Test func evaluateMinerEndpointViewLiveAndOffline() throws {
        let (store, device, defaults, suite) = try makeLiveStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Fresh writable snapshot: write endpoints take the authorized branch.
        let live = MinerEndpointView(
            device: device, store: store, endpoint: .settings,
            initialJSON: "{\"frequency\":575}", onWriteCompleted: {}
        )
        evaluate(live)
        #expect(live.canWrite)

        // A stale error snapshot takes the offline-settings notice branch.
        store.snapshots[device.id] = MinerSnapshot(
            info: nil, previousInfo: nil, error: "Connection timed out", updatedAt: Date(),
            completeSnapshotAt: nil, powerObservedAt: nil, history: [],
            isCached: false, isReconnecting: false
        )
        let offline = MinerEndpointView(device: device, store: store, endpoint: .restart)
        evaluate(offline)
        #expect(!offline.canWrite)
        evaluate(MinerEndpointView(device: device, store: store, endpoint: .updatePool(2)))
    }

    @Test func evaluateMinerCompletionAlert() {
        let read = MinerCompletionAlert(title: "Request accepted", message: "Done")
        #expect(read.title == "Request accepted")
        #expect(read.message == "Done")
        #expect(!read.didWrite)

        let write = MinerCompletionAlert(title: "Change", message: "Applied", didWrite: true)
        #expect(write.didWrite)
        #expect(read.id != write.id)
    }

    // MARK: - DeveloperTipJarService and DeveloperTipJarSection

    @Test func evaluateTipJarServiceStates() async {
        let service = DeveloperTipJarService(startUpdatesListener: false)
        let small = DeveloperTipProduct.small.rawValue
        await service.performPurchase(productID: small) { .success(small) }
        #expect(service.purchaseState == .success(small))

        let medium = DeveloperTipProduct.medium.rawValue
        await service.performPurchase(productID: medium) { .pending(medium) }
        #expect(service.purchaseState == .pending(medium))

        await service.performPurchase(productID: DeveloperTipProduct.large.rawValue) { .cancelled }
        await service.performPurchase(productID: DeveloperTipProduct.supporter.rawValue) { .failed("No") }
        // An unapproved identifier is rejected by the in-flight gate without changing state.
        await service.performPurchase(productID: "invalid.id") { .success("invalid.id") }

        service.resetState()
        #expect(service.purchaseState == .idle)
        #expect(!service.isPurchaseInProgress)

        for tier in DeveloperTipProduct.allCases {
            _ = tier.id
            _ = tier.defaultTitle
            _ = tier.defaultDescription
            _ = tier.iconName
        }
        #expect(DeveloperTipJarService.approvedProductIDs == DeveloperSupport.appStoreTipProductIDs)
    }

    @Test func evaluateTipJarSectionBranches() async {
        // No products loaded: the loading and empty-after-load branches render.
        let service = DeveloperTipJarService(startUpdatesListener: false)
        evaluate(DeveloperTipJarSection(service: service))

        // Driving a success state exercises the state-dependent copy paths on next layout.
        let small = DeveloperTipProduct.small.rawValue
        await service.performPurchase(productID: small) { .success(small) }
        evaluate(DeveloperTipJarSection(service: service))
        evaluate(DeveloperTipJarSection(service: service), width: 420, height: 1600)
    }
}
