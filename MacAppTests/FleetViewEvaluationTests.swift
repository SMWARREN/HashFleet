import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

@Suite("SwiftUI View Evaluation Coverage", .serialized)
@MainActor
struct FleetViewEvaluationTests {
    private func makeStore(demo: Bool = true) -> (FleetStore, UserDefaults) {
        let suite = "app.hashfleet.mac.viewtests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let session = URLSession(configuration: .ephemeral)
        let store = FleetStore(defaults: defaults, session: session)
        if demo {
            store.loadDemo()
        }
        return (store, defaults)
    }

    private func evaluate<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 1200)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 1200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    @Test func evaluateDashboardViews() {
        let (demoStore, defaults1) = makeStore(demo: true)
        defer { defaults1.removePersistentDomain(forName: defaults1.description) }

        evaluate(DashboardView(store: demoStore))
        evaluate(FleetChainCard(fleet: demoStore, insights: MiningInsightsStore()))
        evaluate(FleetChainCard(fleet: demoStore, insights: MiningInsightsStore(), compact: true))
        evaluate(FleetChainCard(fleet: demoStore, insights: MiningInsightsStore(), compactPreview: true))

        let (emptyStore, defaults2) = makeStore(demo: false)
        defer { defaults2.removePersistentDomain(forName: defaults2.description) }
        evaluate(DashboardView(store: emptyStore))
        evaluate(FleetChainCard(fleet: emptyStore, insights: MiningInsightsStore()))

        if let device = demoStore.devices.first {
            evaluate(MinerOverviewCard(device: device, snapshot: demoStore.snapshots[device.id], isDemo: demoStore.isDemo))
            evaluate(MinerOverviewCard(device: device, snapshot: demoStore.snapshots[device.id], isDemo: demoStore.isDemo, compact: true))
            evaluate(MinerOverviewCard(device: device, snapshot: demoStore.snapshots[device.id], isDemo: demoStore.isDemo, isLive: true))
        }
    }

    @Test func evaluateDashboardCards() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        evaluate(FleetBestShareCard(devices: store.devices, snapshots: store.snapshots, isDemo: store.isDemo))
        evaluate(FleetPoolsCard(fleet: store))
        evaluate(FleetMilestonesCard(
            devices: store.devices,
            snapshots: store.snapshots,
            blockObservations: [:],
            latestBlockEvent: nil,
            isDemo: store.isDemo,
            openAchievements: {}
        ))
        evaluate(FleetHistoryCard(devices: store.devices, snapshots: store.snapshots, isDemo: store.isDemo))
        evaluate(FleetOnboardingView(addMiner: {}, exploreDemo: {}))
        evaluate(FleetStatusTicker(fleet: store))
    }

    @Test func evaluateMinerDetailAndTuningViews() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let device = store.devices.first else { return }
        let insights = MiningInsightsStore()

        let detail = MinerDetailView(device: device, store: store, insights: insights)
        evaluate(detail)
        evaluate(MinerDetailView(device: device, store: store, insights: insights, liveConnectionError: "Timeout", isLive: false))
        evaluate(MinerDetailView(device: device, store: store, insights: insights, isLive: true))

        if let snapshot = store.snapshots[device.id], let info = snapshot.info {
            let diagnostics = MinerDiagnosticsModel(info: info)
            evaluate(detail.identity(info))
            evaluate(detail.telemetrySections(info))
            evaluate(detail.primaryMetrics(info, diagnostics: diagnostics))
            evaluate(detail.metrics(info, diagnostics: diagnostics))
            evaluate(detail.hashrateHero(info))
            evaluate(detail.controlMinerCard)
            evaluate(detail.poolsSection)
            evaluate(detail.desktopTelemetrySections(info, diagnostics: diagnostics))
            evaluate(detail.desktopPrimarySections(info))
            evaluate(detail.numberFirstTelemetry(info))
            evaluate(FirmwareTelemetryView(
                info: info,
                observedAt: Date(),
                minerIdentity: "Miner",
                isCached: false,
                error: nil,
                isReconnecting: false,
                freshness: nil
            ))
        }

        evaluate(MinerTuningSessionView(device: device, store: store, insights: insights))
        evaluate(MinerTuningPreviewRoute(device: device, store: store, insights: insights))

        evaluate(MinerCoolingPreview(mode: .essentials, info: store.snapshots[device.id]?.info, canEdit: false))
        evaluate(MinerCoolingPreview(mode: .full, info: store.snapshots[device.id]?.info, canEdit: true))

        evaluate(MinerTuningJournalCard(journal: []))
        evaluate(MinerTuningAdvancedSwitch(isOn: .constant(true)))
        evaluate(MinerTuningSafetyCard(riskAcknowledged: .constant(true), isBeyondReference: true, hasReference: true, voltageRestriction: nil))
        evaluate(MinerTuningReferenceCard(reference: nil, isDemo: true))
        evaluate(MinerTuningSessionHeader(deviceName: "Miner", isDemo: true, isOffline: false, chipCount: 1, chipCountWasReported: true, controlMode: .easy))
        evaluate(MinerTuningLiveContextCard(configuredFrequency: "500", measuredFrequency: "505", configuredVoltage: "1050", measuredVoltage: "1048", asicErrors: "0", isChecking: false))
        evaluate(MinerTuningDeltaStrip(stagedFrequency: 550, configuredFrequency: 500, stagedVoltage: 1100, configuredVoltage: 1050, estimatedLoad: 15.0, formatValue: { "\($0)" }))
    }

    @Test func evaluateMinerSettingsViews() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let device = store.devices.first else { return }
        let insights = MiningInsightsStore()

        for category in MinerSettingsCategory.allCases {
            let settings = MinerSettingsView(device: device, store: store, insights: insights, initialCategory: category)
            evaluate(settings)
            evaluate(settings.categoryDestination(category))
        }

        let defaultSettings = MinerSettingsView(device: device, store: store, insights: insights, initialCategory: .general)
        evaluate(defaultSettings.quickChangesCard)
        evaluate(defaultSettings.reportedStateCard)
        evaluate(defaultSettings.controlsCard)
        evaluate(defaultSettings.compatibilityCard)
        if let info = store.snapshots[device.id]?.info {
            let availability = NumberFirstPreview.minerAvailability(info, device: device, store: store)
            evaluate(defaultSettings.compactSettingsHub(availability))
        }
    }

    @Test func evaluateMinerSupportingViews() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let device = store.devices.first else { return }
        let insights = MiningInsightsStore()

        evaluate(MinerCompatibilityView(device: device, store: store, insights: insights))
        evaluate(MinerEndpointCatalogView(device: device, store: store, insights: insights))
        evaluate(MinerEssentialsPoolsView(device: device, store: store))
        evaluate(MiningSetupView(device: device, store: store, insights: insights, onSelectPreset: { _ in }))
        evaluate(XMRigControlView(device: device, store: store))
        evaluate(MinerCustomJSONView(device: device, isDemo: store.isDemo, onStaged: { _ in }))
        evaluate(MinerLiveView(device: device, isDemo: store.isDemo))
        evaluate(MinerEndpointView(device: device, store: store, endpoint: .info, insights: insights))
        evaluate(MinerEndpointView(device: device, store: store, endpoint: .logs, insights: insights))
        evaluate(MinerEndpointView(device: device, store: store, endpoint: .settings, insights: insights))
    }

    @Test func evaluateSettingsViews() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        evaluate(AddMinerView(store: store))
        let coordinator = FleetGlanceCoordinator(defaults: defaults)
        evaluate(MonitoringSettingsView(store: store, coordinator: coordinator))
        evaluate(AboutView(store: store))
        evaluate(FleetPreferencesView(preferences: store.preferences, store: store))
        evaluate(FleetPowerAlertsView(
            devices: store.devices,
            preferences: FleetPowerAlertPreferences(defaults: store.defaults),
            isDemo: store.isDemo
        ))
        evaluate(FleetTemperatureAlertsView(
            devices: store.devices,
            preferences: FleetTemperatureAlertPreferences(defaults: store.defaults),
            isDemo: store.isDemo
        ))
        evaluate(DeveloperTipJarSection(service: DeveloperTipJarService.shared))
        evaluate(DeveloperSupportSection())
        evaluate(FleetWidgetSettingsPage(store: store, coordinator: coordinator))
        evaluate(FleetLiveActivitySettingsPage(store: store, coordinator: coordinator))
    }

    @Test func evaluateNetworkViews() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let insights = MiningInsightsStore()

        evaluate(NetworkInsightsView(fleet: store, insights: insights))
        evaluate(PoolStatsHubView(fleet: store))
        evaluate(CKPoolLookupView(insights: insights))
    }

    @Test func evaluateEnergyViews() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        evaluate(FleetEnergyView(store: store))
    }

    @Test func evaluateAchievementsAndCelebrations() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        evaluate(MiningAchievementsView(devices: store.devices))

        let id = UUID()
        let celebrations = [
            FleetCelebration(kind: .bestShareAllTime, deviceID: id, minerName: "Rig 1", value: "1.2 GH/s", detail: "Difficulty 1.2G"),
            FleetCelebration(kind: .bestShareSession, deviceID: id, minerName: "Rig 2", value: "950 MH/s", detail: "Difficulty 950M"),
            FleetCelebration(kind: .blockFound, deviceID: id, minerName: "Rig 3", value: "Block #840,000", detail: "Mined block #840000")
        ]

        for celebration in celebrations {
            evaluate(FleetCelebrationView(
                celebration: celebration,
                onViewMiner: {},
                onDismiss: {},
                onDisableSessionBestAlerts: {},
                onSupport: {},
                pendingCount: 1,
                onReviewLater: {}
            ))
        }
    }

    @Test func evaluateReportsAndBackup() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        evaluate(FleetReportView(store: store))
        evaluate(FleetBackupView(store: store))
    }

    @Test func evaluateTourAndOnboarding() {
        evaluate(FleetTourView())
        evaluate(FleetStartupSplash(holdForTesting: true, onContinue: {}))
        evaluate(FleetStartupSplash(holdForTesting: true, onContinue: {}, previewReducedMotion: true))
    }

    @Test func evaluateMascotAndPerformance() {
        for mood in BitsyMood.allCases {
            evaluate(BitsyView(mood: mood))
            evaluate(BitsySays(mood: mood, message: "Testing \(mood.rawValue)"))
        }
        evaluate(FleetPerformanceSettingsView())
    }
}
