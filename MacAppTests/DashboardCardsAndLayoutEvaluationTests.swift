import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Evaluation coverage for Dashboard views, layout containers, cards, and navigation paths.
/// Each test mounts the view hierarchy in an off-screen window and triggers layoutSubtreeIfNeeded(),
/// exercising real @ViewBuilder conditions and state branches without live device requests.
@Suite("Dashboard Cards And Layout Evaluation", .serialized)
@MainActor
struct DashboardCardsAndLayoutEvaluationTests {
    private func makeStore(demo: Bool = true) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.dashlayout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let session = URLSession(configuration: .ephemeral)
        let store = FleetStore(defaults: defaults, session: session)
        if demo { store.loadDemo() }
        return (store, defaults, suite)
    }

    private func evaluate<V: View>(_ view: V, width: CGFloat = 900, height: CGFloat = 1400) {
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

    private func makeInsights(demo: Bool = true) async -> MiningInsightsStore {
        let insights = MiningInsightsStore()
        if demo {
            insights.setDemo(true)
            await insights.refresh()
        }
        return insights
    }

    // MARK: - DashboardView Entire Hierarchy & Sections

    @Test func evaluateDashboardViewPopulatedAndEmpty() async {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = await makeInsights(demo: true)

        let dashboard = DashboardView(
            store: store,
            insights: insights,
            coordinator: nil,
            startupReady: true
        )
        evaluate(dashboard)
        evaluate(dashboard.fleetToolsSection)
        evaluate(dashboard.demoNotice)
        evaluate(dashboard.poolIconDemoGallery)
        evaluate(dashboard.summaryMetrics(wide: true))
        evaluate(dashboard.summaryMetrics(wide: false))

        let destinations: [DashboardPageDestination] = [
            .overview, .settings, .about, .support, .featureTour,
            .energy, .network, .reports, .backup, .achievements
        ]
        for dest in destinations {
            dashboard.routeToDashboardPage(dest)
        }
        if let first = store.devices.first {
            dashboard.routeToDashboardPage(.miner(first.id))
        }

        // Clear devices to evaluate empty / onboarding branch
        store.devices.removeAll()
        evaluate(dashboard)
    }

    @Test func evaluateDashboardViewDifferentModes() async {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = await makeInsights(demo: true)

        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            let dashboard = DashboardView(
                store: store,
                insights: insights,
                coordinator: nil,
                startupReady: true
            )
            evaluate(dashboard, width: 600, height: 1000)
            evaluate(dashboard, width: 1200, height: 900)
        }
    }

    // MARK: - AddMinerView

    @Test func evaluateAddMinerViewBranches() {
        let (store, defaults, suite) = makeStore(demo: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        var bulkSuccessCalled = false
        let addMiner = AddMinerView(
            store: store,
            onBulkAddSuccess: { bulkSuccessCalled = true }
        )
        evaluate(addMiner)
        evaluate(addMiner, width: 500, height: 800)
        #expect(!bulkSuccessCalled)
    }

    // MARK: - FleetMilestonesCard

    @Test func evaluateFleetMilestonesCardSummary() {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        let card = FleetMilestonesCard(
            devices: store.devices,
            snapshots: store.snapshots,
            blockObservations: [:],
            latestBlockEvent: nil,
            isDemo: store.isDemo,
            openAchievements: {}
        )
        evaluate(card)
        evaluate(card.searchingContent(sum: FleetMilestonesSummary(devices: store.devices, snapshots: store.snapshots, blockObservations: [:], latestEvent: nil)))

        let event = MinerBlockFoundEvent(
            id: UUID(),
            deviceID: store.devices.first?.id ?? UUID(),
            minerName: "Bitaxe Alpha",
            coinLabel: "Bitcoin",
            height: 890000,
            count: 1,
            occurredAt: Date()
        )
        let blockCard = FleetMilestonesCard(
            devices: store.devices,
            snapshots: store.snapshots,
            blockObservations: [:],
            latestBlockEvent: event,
            isDemo: false,
            openAchievements: {}
        )
        evaluate(blockCard)
        let summary = FleetMilestonesSummary(
            devices: store.devices,
            snapshots: store.snapshots,
            blockObservations: [:],
            latestEvent: event
        )
        evaluate(blockCard.blockFoundBanner(sum: summary))
        #expect(summary.totalBlocksFound == 1)
        #expect(summary.latestBlockMinerName == "Bitaxe Alpha")
        #expect(summary.latestBlockHeight == 890000)
    }

    // MARK: - FleetChainCard

    @Test func evaluateFleetChainCardCompactAndStandard() async {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = await makeInsights(demo: true)

        let standardCard = FleetChainCard(
            fleet: store,
            insights: insights,
            compact: false,
            compactPreview: false
        )
        let compactCard = FleetChainCard(
            fleet: store,
            insights: insights,
            compact: true,
            compactPreview: true
        )
        evaluate(standardCard)
        evaluate(compactCard)
    }

    // MARK: - FleetSplitView Container

    @Test func evaluateFleetSplitViewNavigation() async {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = await makeInsights(demo: true)

        let split = FleetSplitView(
            store: store,
            insights: insights,
            coordinator: nil,
            startupReady: true,
            fleetPath: .constant(NavigationPath()),
            sidebarSelection: .constant(.overview)
        )
        evaluate(split)

        if let deviceID = store.devices.first?.id {
            let dest = MinerDetailDestinationView(
                deviceID: deviceID,
                store: store,
                insights: insights
            )
            evaluate(dest)
        }

        let unavailableDest = MinerDetailDestinationView(
            deviceID: UUID(),
            store: store,
            insights: insights
        )
        evaluate(unavailableDest)
    }

    // MARK: - FleetToolsSection

    @Test func evaluateFleetToolsSectionTools() {
        var routed: DashboardPageDestination?
        var toured = false

        let section = FleetToolsSection(
            compact: false,
            onRoute: { routed = $0 },
            onTour: { toured = true }
        )
        evaluate(section)

        let compactSection = FleetToolsSection(
            compact: true,
            onRoute: { routed = $0 },
            onTour: { toured = true }
        )
        evaluate(compactSection)

        for tool in FleetToolsSection.tools {
            #expect(!tool.id.isEmpty)
            #expect(!tool.title.isEmpty)
            #expect(!tool.subtitle.isEmpty)
            #expect(!tool.symbol.isEmpty)
        }

        section.onTour()
        #expect(toured)
        section.onRoute(.network)
        #expect(routed == .network)
    }

    // MARK: - FleetHistoryCard Chart & Metric Controls

    @Test func evaluateFleetHistoryCardMetricControls() {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        for _ in MinerHistoryMetric.allCases {
            let card = FleetHistoryCard(
                devices: store.visibleDevices,
                snapshots: store.snapshots,
                isDemo: store.isDemo,
                initialRecentRange: .oneMinute,
                isCompactDashboard: false,
                dashboardMode: .full,
                numberFirst: false
            )
            evaluate(card.chartTitle)
            evaluate(card.metricMenu)
            evaluate(card.numberFirstMinerChartHeading)
            evaluate(card.numberFirstChartControls)
            evaluate(card.essentialsHistoryControls)
        }
    }
}
