import AppKit
import Foundation
import Observation
import HashFleetCore

@MainActor @Observable
final class FleetMacRuntime {
    let store: FleetStore
    let glanceCoordinator: FleetGlanceCoordinator
    let defaults: UserDefaults
    let isTesting: Bool
    let menuBarPreferences: FleetMenuBarPreferenceStorage
    var presentInAppNotification: (@MainActor (FleetNotificationEvent) -> Void)?
    var acceptInAppNotification: (@MainActor (FleetNotificationEvent) -> Bool)?
    var commitInAppRecord: (@MainActor (FleetNotificationEvent) async -> Bool)?
    private(set) var isRunning = false
    @ObservationIgnored private let requestNotificationAuthorization: @MainActor () async -> Bool
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var authorizationTask: Task<Bool, Never>?
    @ObservationIgnored private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored private var monitoringIdentity: MonitoringConfiguration?
    @ObservationIgnored private var lastMaintenanceAt: Date?

    init(
        defaults injectedDefaults: UserDefaults? = nil,
        isTesting testingOverride: Bool? = nil,
        requestNotificationAuthorization: @escaping @MainActor () async -> Bool = {
            await FleetLocalNotifications.requestAuthorization()
        }
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        let testing = testingOverride ?? (arguments.contains("--ui-testing")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil)
        isTesting = testing
        if let injectedDefaults {
            defaults = injectedDefaults
        } else if testing {
            let suite = "app.hashfleet.mac.ui-tests"
            defaults = UserDefaults(suiteName: suite)!
            if !arguments.contains("--ui-test-preserve-storage") {
                defaults.removePersistentDomain(forName: suite)
            }
            defaults.set(false, forKey: FleetPreferences.Keys.externalData)
            defaults.set(true, forKey: FleetPreferences.Keys.systemAppearanceMigration)
            defaults.set(arguments.contains("--ui-test-light-appearance") ? "light" : "dark",
                         forKey: FleetPreferences.Keys.appearance)
        } else {
            defaults = .standard
        }
        self.requestNotificationAuthorization = requestNotificationAuthorization
        store = FleetStore(defaults: defaults, hardwareControlGate: testing ? nil : .shared)
        glanceCoordinator = FleetGlanceCoordinator(defaults: defaults, isTesting: testing)
        menuBarPreferences = FleetMenuBarPreferenceStorage(defaults: defaults)
    }

    /// This task belongs to the application, not a scene. Closing or defocusing the workspace
    /// therefore cannot create a second poller, cancel the menu bar, or stop monitoring.
    func start() {
        guard lifecycleTask == nil else { return }
        isRunning = true
        if !isTesting { FleetLocalNotifications.setup() }
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            await self.authorizeNotificationsBeforeMonitoringIfNeeded()
            guard !Task.isCancelled, self.isRunning else { return }
            while !Task.isCancelled {
                self.runDatabaseMaintenanceIfDue()
                self.reconcileMonitoring()
                let visible = NSApp.isActive && NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
                if !self.isTesting {
                    _ = FleetNotificationDelivery.consume(
                        from: self.store, isActive: visible,
                        presentInApp: { [weak self] event in self?.presentInAppNotification?(event) },
                        acceptInApp: self.acceptInAppNotification)
                    if visible, let commit = self.commitInAppRecord {
                        FleetNotificationDelivery.schedulePendingRecordAcceptances(from: self.store, accept: commit)
                    }
                }
                FleetPerformanceMonitor.shared.setActive(visible)
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    /// The iOS scene runs retention pruning and the one-time database cleanups, but that file is
    /// not part of the Mac target, so the Mac never applied the "Keep data for" setting and its
    /// telemetry database grew without bound. Run both at launch and then once a day.
    private func runDatabaseMaintenanceIfDue(now: Date = Date()) {
        guard !isTesting, !store.isDemo else { return }
        if let lastMaintenanceAt, now.timeIntervalSince(lastMaintenanceAt) < 24 * 60 * 60 { return }
        let isFirstRun = lastMaintenanceAt == nil
        lastMaintenanceAt = now
        if isFirstRun { FleetStartupMaintenance(store: store).run() }
        guard store.preferences.telemetryStorageEnabled else { return }
        let days = store.preferences.telemetryRetention.days
        Task { await MinerTelemetryDatabase.shared.pruneOldReadings(olderThan: days) }
    }

    func stop() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        monitoringTask?.cancel()
        monitoringTask = nil
        monitoringIdentity = nil
        store.cancelRefresh()
        store.cancelLiveMonitoring()
        store.capabilities.cancelAll()
        isRunning = false
    }

    private func authorizeNotificationsBeforeMonitoringIfNeeded() async {
        guard Self.shouldRequestStartupNotificationAuthorization(
            isTesting: isTesting,
            isDemo: store.isDemo,
            hasEnabledAlerts: hasEnabledNotificationAlerts
        ) else { return }

        let task: Task<Bool, Never>
        if let existing = authorizationTask {
            task = existing
        } else {
            let request = requestNotificationAuthorization
            task = Task { @MainActor in await request() }
            authorizationTask = task
        }
        _ = await task.value
        if !Task.isCancelled { authorizationTask = nil }
    }

    private var hasEnabledNotificationAlerts: Bool {
        let preferences = store.preferences
        if preferences.blockNotificationsEnabled
            || preferences.bestShareNotificationsEnabled
            || preferences.stateChangeNotificationsEnabled
            || preferences.metricAlertNotificationsEnabled
            || (preferences.powerAlertNotificationsEnabled
                && store.visibleDevices.contains { store.powerAlerts.policy(for: $0.id).isEnabled })
            || store.visibleDevices.contains(where: { store.temperatureAlerts.policy(for: $0.id).isEnabled }) {
            return true
        }
        return false
    }

    static func shouldRequestStartupNotificationAuthorization(
        isTesting: Bool,
        isDemo: Bool,
        hasEnabledAlerts: Bool
    ) -> Bool {
        !isTesting && !isDemo && hasEnabledAlerts
    }

    private func reconcileMonitoring() {
        let identity = MonitoringConfiguration(
            devices: store.visibleDevices.map { DeviceIdentity(id: $0.id, address: $0.address) },
            realtime: store.preferences.realtimeMonitoring, isDemo: store.isDemo)
        guard identity != monitoringIdentity else { return }
        monitoringIdentity = identity
        monitoringTask?.cancel()
        store.cancelRefresh()
        store.cancelLiveMonitoring()
        guard !store.isDemo else { return }
        monitoringTask = Task { [weak store] in
            guard let store else { return }
            await store.runMonitoring()
        }
    }

    private struct DeviceIdentity: Equatable {
        let id: UUID
        let address: String
    }

    private struct MonitoringConfiguration: Equatable {
        let devices: [DeviceIdentity]
        let realtime: Bool
        let isDemo: Bool
    }
}
