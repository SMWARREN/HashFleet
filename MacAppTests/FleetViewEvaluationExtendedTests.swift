import SwiftUI
import AppKit
import Testing
import UserNotifications
import HashFleetCore
@testable import HashFleetMac

@Suite("SwiftUI Extended View Evaluation Coverage", .serialized)
@MainActor
struct FleetViewEvaluationExtendedTests {
    private func makeStore(demo: Bool = true) -> (FleetStore, UserDefaults) {
        let suite = "app.hashfleet.mac.extendedtests.\(UUID().uuidString)"
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

    @Test func evaluateMinerDiagnosticsExpanded() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let device = store.devices.first,
              let info = store.snapshots[device.id]?.info else { return }

        let model = MinerDiagnosticsModel(info: info)
        let collapsed = MinerDiagnosticsView(model: model, isExpanded: false)
        let expanded = MinerDiagnosticsView(model: model, isExpanded: true)
        evaluate(collapsed)
        evaluate(expanded)
        evaluate(expanded.clocksAndElectricalSection)
        evaluate(expanded.thermalAndCoolingSection)
        evaluate(expanded.hashrateAndPerformanceSection)
    }

    @Test func evaluateHashFleetAppRouting() async {
        let app = HashFleetApp()
        evaluate(app.notificationLayer)
        evaluate(app.mainTabs)
        evaluate(app.fleetNavigation)
        evaluate(app.aboutNavigation)

        app.presentPreviewCelebration(.blockFound)
        evaluate(app.notificationLayer)
        app.presentPreviewCelebration(.bestShareSession)
        evaluate(app.notificationLayer)
        app.presentPreviewCelebration(.bestShareAllTime)
        evaluate(app.notificationLayer)

        app.pauseCelebrations()
        app.resumeCelebrations()
        app.disableSessionBestAlerts()
        app.reconcileCelebrationSessionPreference()
        app.openPendingFleetDestination()
        app.openPendingMinerRoute()
        app.restoreSceneStateIfPossible()
        app.presentUITestCelebrationIfRequested()
        app.presentUITestInAppAlertIfRequested()
        app.dismissCelebration()

        let deviceID = UUID()
        app.presentInAppNotification(.stateChange(MinerStateChangeEvent(deviceID: deviceID, minerName: "Desk", kind: .offline, occurredAt: Date())))
        app.presentInAppNotification(.metricAlert(MinerMetricAlertEvent(deviceID: deviceID, minerName: "Desk", kind: .hashrateDrop, title: "Drop", detail: "Down", occurredAt: Date())))
        _ = app.acceptInAppNotification(.temperature(MinerTemperatureAlertEvent(deviceID: deviceID, minerName: "Desk", temperatureCelsius: 85, thresholdCelsius: 75, occurredAt: Date())))
        _ = await app.commitInAppRecord(.blockFound(MinerBlockFoundEvent(deviceID: deviceID, minerName: "Desk", coinLabel: "BTC", height: 900_000, count: 1, occurredAt: Date())))

        app.openSupportFromCelebration()
        app.openMiner(deviceID, dismissCelebration: true)
        app.openMiner(deviceID, dismissCelebration: false)
    }

    @Test func evaluateNumberFirstDetailView() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let device = store.devices.first,
              let info = store.snapshots[device.id]?.info else { return }
        let insights = MiningInsightsStore()

        let detailView = MinerDetailView(device: device, store: store, insights: insights)
        evaluate(detailView.numberFirstTelemetry(info))

        let availability = NumberFirstPreview.minerAvailability(info, device: device, store: store)
        _ = availability.canEditSettings
        _ = availability.quickActions
        _ = availability.cooling
        _ = availability.tuning
        _ = availability.rawAPI
        _ = availability.settingsCategories(usesEssentialsPools: false)
        _ = availability.settingsCategories(usesEssentialsPools: true)
        _ = availability.showsSettingsHub(in: .full)
        _ = availability.showsSettingsHub(in: .essentials)
        _ = availability.firmwareUpdate(NumberFirstPreview.minerFirmwareNotice)
    }

    @Test func evaluateFleetHistoryCardDeep() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

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
            evaluate(card)
            evaluate(card.numberFirstChartControls)
            evaluate(card.essentialsHistoryControls)
        }

        for range in FleetRecentRange.allCases {
            let card = FleetHistoryCard(
                devices: store.visibleDevices,
                snapshots: store.snapshots,
                isDemo: store.isDemo,
                initialRecentRange: range,
                isCompactDashboard: true,
                dashboardMode: .essentials,
                numberFirst: true
            )
            evaluate(card)
        }

        let pageCache = FleetHistoryPageCache()
        let pageIdentity = FleetHistoryPageIdentity(
            window: .daily,
            recentRange: .oneMinute,
            displayMode: .fleet,
            kind: .sha256,
            currentSignatures: [],
            storedSignatures: [],
            storedRevision: 1,
            deviceMetadata: []
        )
        let resolvedPage = pageCache.resolve(pageIdentity) {
            (histories: [], segments: nil)
        }
        _ = pageCache.resolve(pageIdentity) { resolvedPage }

        let rangeCache = FleetHistoryRangeCache()
        let rangeIdentity = FleetHistoryRangeIdentity(
            kind: .sha256,
            currentSignatures: [],
            storedSignatures: [],
            storedRevision: 1
        )
        let ranges = rangeCache.resolve(rangeIdentity, now: Date()) {
            (ranges: [.oneMinute, .fifteenMinutes], expiration: Date().addingTimeInterval(60))
        }
        _ = rangeCache.resolve(rangeIdentity, now: Date()) {
            (ranges: ranges, expiration: Date().addingTimeInterval(60))
        }
    }
}

extension FleetViewEvaluationExtendedTests {
    @Test func evaluateAddMinerViews() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        evaluate(AddMinerScanRadar(
            probedHosts: 10, hostCount: 254, candidatesCount: 2, isScanning: true, onCancel: {}
        ))
        evaluate(AddMinerScanRadar(
            probedHosts: 254, hostCount: 254, candidatesCount: 5, isScanning: false, onCancel: {}
        ))

        let addMiner = AddMinerView(store: store)
        evaluate(addMiner)
        evaluate(addMiner.discoveryContent)
        evaluate(addMiner.discoveryEmptyState(
            title: "No compatible miners found",
            message: "Connect to Wi-Fi to scan for miners."
        ))
    }

    @Test func evaluateOverviewAndMiningContext() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let device = store.devices.first else { return }
        let info = store.snapshots[device.id]?.info

        let ctx = MinerMiningContext.resolve(info: info)
        _ = ctx.headline
        _ = ctx.coinLabel
        _ = ctx.providerLabel
        _ = ctx.routeLabel
        _ = ctx.sourceLabel
        _ = ctx.symbol
        _ = ctx.id
        evaluate(MinerMiningContextRow(context: ctx))
        evaluate(MinerMiningContextRow(context: ctx, isLastKnown: true))

        let pool1 = ConfiguredMiningPool(
            id: "0", host: "solo.ckpool.org:3333", coin: .btc,
            provider: .ckpool, role: "Primary", isActive: true,
            address: "bc1qtest", redactedAddress: "bc1q...test"
        )
        let ctx1 = MinerMiningContext(pool: pool1)
        _ = ctx1.providerLabel
        _ = ctx1.routeLabel
        _ = ctx1.symbol
        evaluate(MinerMiningContextRow(context: ctx1))

        let pool2 = ConfiguredMiningPool(
            id: "1", host: "solofury.com:3333", coin: nil,
            provider: .soloFury, role: "Fallback", isActive: false,
            address: nil, redactedAddress: nil
        )
        let ctx2 = MinerMiningContext(pool: pool2)
        _ = ctx2.providerLabel
        _ = ctx2.routeLabel
        _ = ctx2.symbol
        evaluate(MinerMiningContextRow(context: ctx2))

        evaluate(MinerOverviewCard(device: device, snapshot: store.snapshots[device.id], isDemo: store.isDemo, compact: false, numberFirst: true))
        evaluate(MinerOverviewCard(device: device, snapshot: store.snapshots[device.id], isDemo: store.isDemo, compact: true, numberFirst: true))
        evaluate(MinerOverviewCard(device: device, snapshot: store.snapshots[device.id], isDemo: store.isDemo, compact: false, numberFirst: false))
        evaluate(MinerOverviewCard(device: device, snapshot: store.snapshots[device.id], isDemo: store.isDemo, compact: true, numberFirst: false))
        evaluate(MinerOverviewCard(device: device, snapshot: nil, isDemo: false, compact: false, numberFirst: false))
    }

    @Test func evaluateDashboardBannersAndHero() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let device = store.devices.first else { return }

        let bestShare = MinerBestShareEvent(
            deviceID: device.id,
            minerName: device.name,
            kind: .allTime,
            displayValue: "5.4G",
            rawValue: "5400000000",
            occurredAt: Date()
        )
        evaluate(FleetBestShareCelebrationBanner(event: bestShare, dismiss: {}))

        let blockEvent = MinerBlockFoundEvent(
            deviceID: device.id,
            minerName: device.name,
            coinLabel: "BTC",
            height: 840_000,
            count: 1,
            occurredAt: Date()
        )
        evaluate(FleetBlockFoundCelebrationBanner(event: blockEvent, dismiss: {}))

        evaluate(FleetHeroCard(
            hashrate: store.hashrateReading,
            power: store.powerReading,
            onlineCount: store.onlineCount,
            deviceCount: store.devices.count,
            isDemo: store.isDemo,
            isRefreshing: false,
            isInitialLoading: false,
            realtimeMonitoring: true,
            liveConnectionCount: 1,
            liveFallbackCount: 0,
            sourceTitle: "SHA-256",
            compact: true,
            numberFirst: true
        ))
        evaluate(FleetHeroCard(
            hashrate: store.hashrateReading,
            power: store.powerReading,
            onlineCount: 0,
            deviceCount: store.devices.count,
            isDemo: false,
            isRefreshing: true,
            isInitialLoading: true,
            realtimeMonitoring: false,
            liveConnectionCount: 0,
            liveFallbackCount: 1,
            sourceTitle: "SHA-256",
            compact: false,
            numberFirst: false
        ))

        evaluate(FleetMetricCard(
            title: "Hashrate", value: "1.2", unit: "TH/s", symbol: "waveform.path",
            caption: "Fleet total", identifier: "metric.hashrate", accessibleValue: "1.2 TH/s"
        ))
    }

    @Test func evaluateEndpointsAndSettingsPools() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let device = store.devices.first else { return }
        let insights = MiningInsightsStore()

        let endpoints: [MinerEndpoint] = [
            .restart, .pause, .resume, .otaFirmware, .otaWWW,
            .updatePool(0), .deletePool(0), .updateTheme, .boot
        ]
        for ep in endpoints {
            evaluate(MinerEndpointView(device: device, store: store, endpoint: ep, insights: insights))
        }

        let defaultSettings = MinerSettingsView(device: device, store: store, insights: insights, initialCategory: .pools)
        evaluate(defaultSettings.soloPoolPresets)
        _ = defaultSettings.poolInventory
        _ = defaultSettings.draftPoolCoin
        _ = defaultSettings.poolSlotTitle(0)
        evaluate(defaultSettings.poolCoinIdentity(.btc))
        evaluate(defaultSettings.poolCoinIdentity(nil))

        let poolsCard = FleetPoolsCard(fleet: store)
        evaluate(poolsCard.statsDisclosure(provider: .ckpool, coin: .btc, address: "bc1qtest", host: "solo.ckpool.org"))
        evaluate(poolsCard.statsDisclosure(provider: .soloFury, coin: nil, address: nil, host: "solofury.com"))
    }

    @Test func evaluateTipJarAndNotifications() async {
        let service = DeveloperTipJarService(startUpdatesListener: false)
        await service.performPurchase(productID: DeveloperTipProduct.small.rawValue) { .success(DeveloperTipProduct.small.rawValue) }
        await service.performPurchase(productID: DeveloperTipProduct.medium.rawValue) { .pending(DeveloperTipProduct.medium.rawValue) }
        await service.performPurchase(productID: DeveloperTipProduct.large.rawValue) { .cancelled }
        await service.performPurchase(productID: DeveloperTipProduct.supporter.rawValue) { .failed("Declined") }
        await service.performPurchase(productID: "invalid.id") { .cancelled }
        service.resetState()

        for tier in DeveloperTipProduct.allCases {
            _ = tier.id
            _ = tier.defaultTitle
            _ = tier.defaultDescription
            _ = tier.iconName
        }

        for alert in FleetNotificationSettingsModel.Alert.allCases {
            _ = alert.title
            _ = alert.identifier
            _ = alert.explanation
        }

        let accessStatuses: [UNAuthorizationStatus] = [.authorized, .denied, .notDetermined, .provisional]
        for status in accessStatuses {
            let access = FleetNotificationSettingsModel.Access(authorization: status)
            _ = access.permitsNotifications
            _ = access.title
            _ = access.explanation
        }

        _ = FleetNotificationSettingsModel.TestNotificationState.queued.message
        _ = FleetNotificationSettingsModel.TestNotificationState.blocked.message
        _ = FleetNotificationSettingsModel.TestNotificationState.failed.message
    }

    @Test func evaluateLiveModelAndViews() {
        let (store, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let device = store.devices.first else { return }

        let liveModel = MinerLiveModel()
        liveModel.connect(device: device, endpoint: .liveWebSocket, isDemo: true)
        liveModel.disconnect()
        liveModel.clear()
        liveModel.frames.append(MinerLiveFrame(text: "{\"hashrate\": 550.0}"))
        liveModel.latestFields = ["hashrate": .number(550.0)]

        evaluate(MinerLiveView(device: device, isDemo: true, initialEndpoint: .liveWebSocket))
        evaluate(MinerLiveView(device: device, isDemo: false, initialEndpoint: .logWebSocket))
    }
}
