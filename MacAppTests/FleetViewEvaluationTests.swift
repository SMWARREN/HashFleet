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
        evaluate(MinerCoolingPreview(mode: .full, info: nil, canEdit: false))
        evaluate(MinerCoolingPreview(mode: .full, info: store.snapshots[device.id]?.info, canEdit: true, live: .init(target: "192.168.1.100", save: { _, draft in draft })))

        if let info = store.snapshots[device.id]?.info {
            let availability = NumberFirstPreview.minerAvailability(info, device: device, store: store)
            evaluate(MinerTuningPreview(
                mode: .full, device: device, store: store, info: info,
                isDemo: store.isDemo, canEdit: availability.tuning, insights: insights
            ))
            evaluate(MinerTuningPreview(
                mode: .essentials, device: device, store: store, info: info,
                isDemo: store.isDemo, canEdit: false, insights: insights
            ))
            var draft = MinerTuningPreviewDraft(info: info)
            draft.edit(.frequency, "550")
            if let review = draft.review {
                evaluate(MinerTuningPreviewReview(
                    request: review, canConfirm: true, isLive: false,
                    attemptMessage: "Verification succeeded", confirm: {}
                ))
                evaluate(MinerTuningPreviewReview(
                    request: review, canConfirm: false, isLive: true,
                    attemptMessage: "Error occurred", confirm: {}
                ))
            }
        }

        var setpointFreq = 525.0
        var setpointVolt = 1060.0
        let freqDial = MinerTuningDial(
            title: "Frequency", unit: "MHz",
            setpoint: Binding(get: { setpointFreq }, set: { setpointFreq = $0 }),
            range: 300...800, liveValue: 520.0, configuredValue: 500.0,
            referenceMaximum: 550.0, isBeyondReference: false, isRestricted: false,
            isEnabled: true, referenceOptions: [400, 500, 525, 550, 600],
            accessibilityPrefix: "tuning.freq", compact: false
        )
        let voltDial = MinerTuningDial(
            title: "Core Voltage", unit: "mV",
            setpoint: Binding(get: { setpointVolt }, set: { setpointVolt = $0 }),
            range: 900...1200, liveValue: 1055.0, configuredValue: 1050.0,
            referenceMaximum: 1150.0, isBeyondReference: true, isRestricted: true,
            isEnabled: false, referenceOptions: [1000, 1050, 1100, 1150],
            accessibilityPrefix: "tuning.volt", compact: true
        )
        evaluate(freqDial)
        evaluate(voltDial)
        evaluate(MinerTuningDialPair(frequency: freqDial, voltage: voltDial))

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
            let essentialsSettings = MinerSettingsView(device: device, store: store, insights: insights, initialCategory: .general)
            evaluate(essentialsSettings.compactSettingsHub(availability))

            _ = MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: .object(["hostname": .string("Axe")]))
            _ = MinerDirectSavePolicy.qualifies(endpoint: .info, payload: .object(["hostname": .string("Axe")]))
            _ = MinerDisplaySetting.rotation.matches(.object(["rotation": .number(0)]), in: info)
            _ = MinerDisplaySetting.colors.matches(.object(["invertscreen": .bool(true)]), in: info)
            _ = MinerDisplaySetting.timeout.matches(.object(["displayTimeout": .number(60)]), in: info)

            evaluate(defaultSettings.displaySaveButton("Apply Rotation", setting: .rotation) { .object(["rotation": .number(0)]) })
            evaluate(defaultSettings.displaySaveButton("Apply Colors", setting: .colors) { .object(["invertscreen": .bool(true)]) })
            evaluate(defaultSettings.displaySaveButton("Apply Timeout", setting: .timeout) { .object(["displayTimeout": .number(60)]) })
        }
        defaultSettings.submit(.settings, json: .object(["hostname": .string("TestMiner")]))
        defaultSettings.submit(.settings, object: ["hostname": "TestMiner"])
        _ = defaultSettings.everydayTitle(review: "Review", save: "Save")
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

        if let info = store.snapshots[device.id]?.info {
            let write = PendingMinerWrite(
                endpoint: .settings,
                body: Data("{\"frequency\": 550}".utf8),
                query: [URLQueryItem(name: "save", value: "true")],
                filename: nil,
                opensExactRequest: true
            )
            evaluate(MinerWriteConfirmation(device: device, request: write, isDemo: false, onConfirm: {}))
            let highRiskWrite = PendingMinerWrite(
                endpoint: .otaFirmware,
                body: Data("firmware".utf8),
                query: [],
                filename: "firmware.bin",
                opensExactRequest: false
            )
            evaluate(MinerWriteConfirmation(device: device, request: highRiskWrite, isDemo: true, onConfirm: {}))

            _ = try? MinerRequestSafety.jsonData("{\"test\": 123}")
            _ = MinerRequestSafety.pretty(Data("{\"test\": 123}".utf8))
            _ = MinerRequestSafety.reviewedBody(Data("{\"test\": 123}".utf8))
            _ = MinerRequestSafety.reviewedBody(nil)
            _ = MinerRequestSafety.isWrite(.settings)
            _ = MinerRequestSafety.isWrite(.info)
            _ = MinerRequestSafety.isHighRisk(.otaFirmware, data: nil)
            _ = MinerRequestSafety.isHighRisk(.settings, data: Data("{\"coreVoltage\": 1100}".utf8))
            _ = MinerRequestSafety.coreVoltage(in: Data("{\"coreVoltage\": 1150}".utf8))

            if let identity = MinerInlineActionState.identity(from: info),
               let baseline = MinerEssentialsPoolBaseline(role: .primary, raw: info.raw) {
                evaluate(MinerEssentialsPoolEditor(device: device, store: store, initial: baseline, identity: identity))
            }
        }
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
        insights.setDemo(true)

        let networkView = NetworkInsightsView(fleet: store, insights: insights)
        evaluate(networkView)
        evaluate(networkView.soloCard(MiningInsightsDemo.network, now: Date()))
        for scope in networkView.soloOutcomeScopes(now: Date()) {
            evaluate(networkView.soloOutcomePage(scope: scope, difficulty: 80e12))
        }
        for window in SoloOutcomeWindow.allCases {
            _ = window.duration
            _ = window.title
            _ = window.accessibilityTitle
        }
        if let network = insights.network {
            evaluate(networkView.soloCard(network, now: Date()))
        }
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

        let (_, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let runtime = FleetMacRuntime(defaults: defaults, isTesting: true)
        evaluate(FleetMacMenuBarContent(runtime: runtime, openDestination: { _ in }))
        let controller = FleetMacStatusItemController(runtime: runtime, openDestination: { _ in })
        controller.stop()
    }

    @Test func evaluateDashboardSplitView() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let insights = MiningInsightsStore()
        insights.setDemo(true)
        let coordinator = FleetGlanceCoordinator(defaults: defaults)

        evaluate(FleetActivityPopup(store: store))
        evaluate(FleetSplitView(
            store: store,
            insights: insights,
            coordinator: coordinator,
            startupReady: true,
            fleetPath: .constant(NavigationPath()),
            sidebarSelection: .constant(.overview)
        ))

        let destinations: [FleetSidebarDestination] = [
            .overview, .network, .energy, .achievements, .reports, .backup, .monitoring, .preferences, .about, .support
        ]
        for dest in destinations {
            evaluate(FleetSplitView(
                store: store,
                insights: insights,
                coordinator: coordinator,
                startupReady: true,
                fleetPath: .constant(NavigationPath()),
                sidebarSelection: .constant(dest)
            ))
        }
        if let device = store.devices.first {
            evaluate(FleetSplitView(
                store: store,
                insights: insights,
                coordinator: coordinator,
                startupReady: true,
                fleetPath: .constant(NavigationPath()),
                sidebarSelection: .constant(.miner(device.id))
            ))
        }
    }
}
