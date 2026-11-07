import SwiftUI
@preconcurrency import BackgroundTasks
import UserNotifications
import LucideSwift
import HashFleetCore

@main
struct HashFleetApp: App {
    @UIApplicationDelegateAdaptor(FleetRemotePushAppDelegate.self) private var remotePushDelegate
    @State var store: FleetStore
    @State var glanceCoordinator: FleetGlanceCoordinator
    @SceneStorage("selectedTab") var selectedTab = 0
    @SceneStorage("sidebarSelectionID") var restoredSidebarSelectionID: String?
    @State var insights = MiningInsightsStore()
    @State var fleetPath = NavigationPath()
    @State var showsStartup = true
    @State var celebrations = FleetCelebrationQueue()
    var celebration: FleetCelebration? { celebrations.current }
    @State var sidebarSelection: FleetSidebarDestination? = .overview
    @State var presentationResetID = UUID()
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let isTesting: Bool

    init() {
        let defaults: UserDefaults
        let isTesting = ProcessInfo.processInfo.arguments
            .contains("--ui-testing")
            || ProcessInfo.processInfo.environment[
                "XCTestConfigurationFilePath"
            ] != nil
        self.isTesting = isTesting
        _showsStartup = State(
            initialValue: !isTesting
                || ProcessInfo.processInfo.arguments
                .contains("--show-launch-splash")
        )
        if isTesting {
            defaults = UserDefaults(suiteName: "app.hashfleet.ui-tests")!
            if !ProcessInfo.processInfo.arguments.contains("--ui-test-preserve-storage") {
                defaults.removePersistentDomain(forName: "app.hashfleet.ui-tests")
            } else if ProcessInfo.processInfo.arguments.contains("--demo") {
                // An explicit preserved UI fixture resumes its current demo preferences.
                // This suite contains no real settings. Leave production and non-demo
                // launches on FleetStore's normal pre-demo checkpoint recovery path.
                defaults.removeObject(forKey: FleetStore.preferenceCheckpointKey)
            }
            // Deterministic UI tests never use public services unless explicitly opted into live acceptance.
            defaults.set(ProcessInfo.processInfo.arguments.contains("--demo") ||
                         ProcessInfo.processInfo.arguments.contains("--live-public-data"),
                         forKey: FleetPreferences.Keys.externalData)
            if !ProcessInfo.processInfo.arguments.contains("--ui-test-system-appearance") {
                // Existing visual regressions use an explicit dark starting mode.
                // System acceptance deliberately exercises the real default instead.
                defaults.set(true, forKey: FleetPreferences.Keys.systemAppearanceMigration)
                let isLight = ProcessInfo.processInfo.arguments
                    .contains("--ui-test-light-appearance")
                defaults.set(
                    isLight ? "light" : "dark",
                    forKey: FleetPreferences.Keys.appearance
                )
            }
        } else {
            defaults = .standard
        }
        _store = State(initialValue: FleetStore(defaults: defaults,
            hardwareControlGate: isTesting ? nil : .shared))
        // Applied before the debug acceptance shortcut below so every launch path is styled.
        MainActor.assumeIsolated {
            FleetTabBarAppearance.apply()
        }
        #if DEBUG
        if isTesting && ProcessInfo.processInfo.arguments.contains("--demo") &&
            ProcessInfo.processInfo.arguments.contains("--live-activity-ui-test") {
            // Explicit acceptance mode: only synthetic data, no real cache or activity namespace.
            _glanceCoordinator = State(initialValue: FleetGlanceCoordinator(defaults: defaults,
                storage: FleetGlanceStorage(defaults: nil), activityName: "HashFleet UI Test"))
            return
        }
        #endif
        _glanceCoordinator = State(initialValue: FleetGlanceCoordinator(defaults: defaults,
            refreshStorage: isTesting ? .init(directory: nil) : .shared,
            isTesting: isTesting))
        if !isTesting {
            FleetLocalNotifications.setup()
            FleetBackgroundRefresh.register()
            FleetBackgroundRefresh.schedule()
            // Ask for notification permission at launch so block-found and best-share
            // alerts can reach the iOS notification window even if the user never opens
            // Temperature Alert settings (the only other place authorization was requested).
            Task { @MainActor in
                _ = await FleetLocalNotifications.requestAuthorization()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                mainTabs
                .tint(FleetTheme.accent)
                .foregroundStyle(FleetTheme.ink)
                .background(FleetTheme.canvas.ignoresSafeArea())
                .overlay(alignment: .bottomLeading) {
                    FleetPerformanceOverlay()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 82)
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    FleetPerformanceMonitor.shared.setActive(phase == .active)
                }
                .onChange(of: store.isDemo, initial: true) { _, demo in
                    insights.setDemo(demo)
                    FleetRemotePushCoordinator.shared.updateFleet(
                        devices: store.visibleDevices, snapshots: store.snapshots, isDemo: demo)
                    glanceCoordinator.updateWidgetRefreshFleet(
                        devices: store.visibleDevices, snapshots: store.snapshots, isDemo: demo,
                        isForeground: scenePhase == .active)
                }
                .onChange(of: store.visibleDevices) { _, devices in
                    FleetRemotePushCoordinator.shared.updateFleet(
                        devices: devices, snapshots: store.snapshots, isDemo: store.isDemo)
                    glanceCoordinator.updateWidgetRefreshFleet(
                        devices: devices, snapshots: store.snapshots, isDemo: store.isDemo,
                        isForeground: scenePhase == .active)
                }
                .onChange(of: store.snapshots.mapValues(\.completeSnapshotAt)) { _, _ in
                    FleetRemotePushCoordinator.shared.updateFleet(
                        devices: store.visibleDevices, snapshots: store.snapshots, isDemo: store.isDemo)
                    glanceCoordinator.updateWidgetRefreshFleet(
                        devices: store.visibleDevices, snapshots: store.snapshots, isDemo: store.isDemo,
                        isForeground: scenePhase == .active)
                }
                .task(id: scenePhase) { await refreshRemotePushWhileActive() }
                .onChange(of: store.preferences.externalDataEnabled) { _, enabled in
                    if !enabled { insights.clearPublicData() }
                }
                .onChange(of: store.notificationDeliveryTrigger) { _, _ in
                    if scenePhase == .active { FleetSharedStore.markAppActive(true) }
                    let warnings = FleetNotificationDelivery.consume(
                        from: store, isActive: scenePhase == .active,
                        presentInApp: presentInAppNotification)
                    for warning in warnings {
                        FleetInAppAlertCenter.shared.present(FleetInAppAlert(.temperature(warning)))
                        store.markInAppNotificationDelivered(for: .temperature(warning))
                    }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    // Reload a BGTask store's baselines and journal; show unsent alerts in-app.
                    store.reloadSharedDetectionBaselines()
                    store.restoreNotificationInbox()
                    FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                        from: store, isActive: true,
                        presentInApp: presentInAppNotification)
                }
                .onOpenURL { url in
                    guard url.scheme == "hashfleet", url.host == "fleet" else { return }
                    fleetPath = NavigationPath()
                    selectedTab = 0
                    sidebarSelection = .overview
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: FleetSystemNavigation.requested)
                        .receive(on: RunLoop.main)
                ) { _ in
                    openPendingFleetDestination()
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: FleetNotificationRoute.requested)
                        .receive(on: RunLoop.main)
                ) { _ in
                    openPendingMinerRoute()
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: FleetCelebrationPreview.requested)
                        .receive(on: RunLoop.main)
                ) { note in
                    guard let kind = FleetCelebrationPreview.kind(from: note) else { return }
                    presentPreviewCelebration(kind)
                }
                .task(id: showsStartup) {
                    guard !showsStartup else { return }
                    openPendingMinerRoute()
                    // Demo devices load asynchronously; give the store a moment before the test hook.
                    for _ in 0..<20 where store.visibleDevices.isEmpty {
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                    presentUITestCelebrationIfRequested()
                    presentUITestInAppAlertIfRequested()
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        store.beginReconnecting()
                        openPendingFleetDestination()
                        if !showsStartup { openPendingMinerRoute() }
                    }
                }
                .task(id: GlancePublishingIdentity(
                    phase: scenePhase, glance: store.glance, menuBarSnapshot: store.menuBarSnapshot
                )) {
                    guard scenePhase == .active else { return }
                    guard store.canPublishGlance || store.canPublishMenuBar else { return }
                    await glanceCoordinator.publish(
                        store.glance,
                        menuBarSnapshot: store.menuBarSnapshot,
                        publishAggregate: store.canPublishGlance
                    )
                }
                .task(id: MonitoringIdentity(
                    phase: scenePhase,
                    deviceIDs: store.visibleDevices.map(\.id),
                    isDemo: store.isDemo,
                    realtimeMonitoring: store.preferences.realtimeMonitoring
                )) {
                    guard scenePhase == .active else { return }

                    // Demo shares the production storage path, so never schedule maintenance
                    // from Demo. Recheck inside the task in case Demo starts before it executes.
                    if !store.isDemo {
                        if store.preferences.telemetryStorageEnabled {
                            Task { @MainActor in
                                guard !Task.isCancelled, !store.isDemo else { return }
                                await MinerTelemetryDatabase.shared.pruneOldReadings(
                                    olderThan: store.preferences.telemetryRetention.days
                                )
                            }
                        }
                        FleetStartupMaintenance(store: store).run()
                    }

                    store.cancelRefresh()
                    await store.runMonitoring { glance in
                        // A foreground bootstrap is a deliberate user-visible refresh. Force one
                        // widget reload here, while live frames use the coordinator's throttle.
                        await glanceCoordinator.publish(
                            glance,
                            menuBarSnapshot: store.menuBarSnapshot,
                            publishAggregate: store.canPublishGlance,
                            forceWidgetReload: true
                        )
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    FleetSharedStore.markAppActive(phase == .active)
                    if phase == .active {
                        FleetLocalNotifications.clearBadge()
                    }
                    if phase == .inactive {
                        // A transient inactive phase (Control Center, incoming call) keeps the
                        // next background poll queued so state-change and metric detection
                        // continues while the app is not fully foregrounded.
                        FleetBackgroundRefresh.schedule()
                    }
                    if phase == .background && !isTesting {
                        // The foreground monitoring task is cancelled by its phase identity. Cancel
                        // any in-flight pull explicitly, then let this grace-period task own the
                        // background refresh instead of cancelling it in the shared inactive path.
                        store.cancelRefresh()
                        store.beginReconnecting()
                        // Request a finite grace period, whose duration is controlled by iOS.
                        // Publish its final complete reading before suspension, not just its alerts.
                        let expectedDemo = store.isDemo
                        let refreshRunID = FleetBackgroundRefreshDiagnostics.shared.began()
                        var bgTaskID = UIBackgroundTaskIdentifier.invalid
                        var backgroundWork: Task<Void, Never>?
                        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "app.hashfleet.background-poll") {
                            backgroundWork?.cancel()
                            FleetBackgroundRefreshDiagnostics.shared.finished(refreshRunID, outcome: .expired)
                            if bgTaskID != .invalid {
                                UIApplication.shared.endBackgroundTask(bgTaskID)
                                bgTaskID = .invalid
                            }
                        }
                        backgroundWork = Task { @MainActor in
                            defer {
                                if bgTaskID != .invalid {
                                    UIApplication.shared.endBackgroundTask(bgTaskID)
                                    bgTaskID = .invalid
                                }
                            }
                            guard bgTaskID != .invalid else {
                                FleetBackgroundRefreshDiagnostics.shared.finished(refreshRunID, outcome: .expired)
                                return
                            }
                            await store.refresh()
                            guard bgTaskID != .invalid, !Task.isCancelled else {
                                FleetBackgroundRefreshDiagnostics.shared.finished(refreshRunID, outcome: .cancelled)
                                return
                            }
                            let complete = await FleetBackgroundGlancePublication.publish(
                                store.glance, isComplete: store.canPublishGlance, expectedDemo: expectedDemo
                            ) { glance in
                                await glanceCoordinator.publish(glance)
                            }
                            guard bgTaskID != .invalid, !Task.isCancelled else {
                                FleetBackgroundRefreshDiagnostics.shared.finished(refreshRunID, outcome: .cancelled)
                                return
                            }
                            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store)
                            FleetNotificationDelivery.consume(from: store, isActive: false)
                            await MinerTelemetryDatabase.shared.flushReadings()
                            FleetBackgroundRefresh.schedule()
                            FleetBackgroundRefreshDiagnostics.shared.finished(refreshRunID,
                                outcome: Task.isCancelled ? .cancelled : (complete ? .completeSnapshot : .noCompleteSnapshot))
                        }
                        return
                    }
                    if phase != .active {
                        store.cancelRefresh()
                        store.capabilities.cancelAll()
                        insights.cancel()
                    }
                }
                .alert("Local storage", isPresented: Binding(
                    get: { store.persistenceError != nil },
                    set: { if !$0 { store.persistenceError = nil } }
                )) {
                    Button("OK") { store.persistenceError = nil }
                } message: {
                    Text(store.persistenceError ?? "")
                }
                .accessibilityHidden(showsStartup || celebration != nil)
                .allowsHitTesting(!showsStartup)

                if showsStartup {
                    FleetStartupSplash(
                        holdForTesting: ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
                            ProcessInfo.processInfo.arguments.contains("--ui-test-hold-splash")
                    ) {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                            showsStartup = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                FleetNotificationWindowHost(
                    isEnabled: !showsStartup && scenePhase == .active,
                    capturesAllTouches: celebration != nil
                ) {
                    notificationLayer
                        .preferredColorScheme(store.preferences.appearance.colorScheme)
                }
                .frame(width: 0, height: 0)
            }
            .onAppear {
                restoreSceneStateIfPossible()
            }
            .onChange(of: sidebarSelection) { _, newDestination in
                if !isTesting {
                    restoredSidebarSelectionID = newDestination?.id
                }
            }
            .fleetWindowViewport()
            .environment(\.fleetPresentationResetID, presentationResetID)
            .preferredColorScheme(store.preferences.appearance.colorScheme)
        }
        .commands {
            SidebarCommands()
            CommandMenu("Fleet") {
                Button("Refresh Fleet Data") {
                    Task { @MainActor in
                        await store.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Fleet Overview") {
                    selectedTab = 0
                    sidebarSelection = .overview
                    fleetPath = NavigationPath()
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Fleet Reports") {
                    selectedTab = 0
                    sidebarSelection = .reports
                    fleetPath = NavigationPath()
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Mining Insights") {
                    selectedTab = 0
                    sidebarSelection = .network
                    fleetPath = NavigationPath()
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("Fleet Energy") {
                    selectedTab = 0
                    sidebarSelection = .energy
                    fleetPath = NavigationPath()
                }
                .keyboardShortcut("4", modifiers: [.command])

                Button("Fleet Achievements") {
                    selectedTab = 0
                    sidebarSelection = .achievements
                    fleetPath = NavigationPath()
                }
                .keyboardShortcut("5", modifiers: [.command])

                Divider()

                Button("Fleet Preferences") {
                    selectedTab = 0
                    sidebarSelection = .preferences
                    fleetPath = NavigationPath()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }

}
