import Foundation
import Testing
import UserNotifications
import HashFleetCore
@testable import HashFleet

/// Regressions for notifications that lingered after a miner recovered or appeared twice
/// (system banner plus in-app surface, or re-announced across background/foreground stores).
@Suite("Notification lingering and duplication")
@MainActor
struct FleetNotificationLifecycleTests {
    private func withStore(_ body: (FleetStore) throws -> Void) rethrows {
        let suite = "app.hashfleet.lifecycle-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(FleetStore(defaults: defaults))
    }

    private func makeInfo(hashrate: Double = 500, power: Double = 15) -> MinerInfo {
        MinerInfo(raw: ["hashRate": .number(hashrate), "power": .number(power)])
    }

    @Test func recoveryReplacesTheOfflineNotificationForTheSameMiner() {
        let deviceID = UUID()
        let offline = FleetStateChangeNotificationContent(event: MinerStateChangeEvent(
            deviceID: deviceID, minerName: "Desk", kind: .offline, detail: "Timeout", occurredAt: .now))
        let recovered = FleetStateChangeNotificationContent(event: MinerStateChangeEvent(
            deviceID: deviceID, minerName: "Desk", kind: .backOnline, occurredAt: .now))
        let otherMiner = FleetStateChangeNotificationContent(event: MinerStateChangeEvent(
            deviceID: UUID(), minerName: "Garage", kind: .offline, detail: "Timeout", occurredAt: .now))
        // Same identifier means iOS replaces the stale offline alert rather than keeping both.
        #expect(offline.identifier == recovered.identifier)
        #expect(offline.identifier != otherMiner.identifier)
    }

    @Test func statusAlertsKeepOneNotificationSlotPerMiner() {
        let deviceID = UUID()
        let hot = MinerTemperatureAlertEvent(
            deviceID: deviceID, minerName: "Desk", temperatureCelsius: 80, thresholdCelsius: 75, occurredAt: .now)
        let hotter = MinerTemperatureAlertEvent(
            deviceID: deviceID, minerName: "Desk", temperatureCelsius: 84, thresholdCelsius: 75, occurredAt: .now)
        #expect(FleetTemperatureAlertNotificationContent(event: hot).identifier
            == FleetTemperatureAlertNotificationContent(event: hotter).identifier)

        let drop = MinerMetricAlertEvent(
            deviceID: deviceID, minerName: "Desk", kind: .hashrateDrop, title: "Drop", detail: "", occurredAt: .now)
        let laterDrop = MinerMetricAlertEvent(
            deviceID: deviceID, minerName: "Desk", kind: .hashrateDrop, title: "Drop", detail: "", occurredAt: .now)
        let spike = MinerMetricAlertEvent(
            deviceID: deviceID, minerName: "Desk", kind: .powerSpike, title: "Spike", detail: "", occurredAt: .now)
        #expect(FleetMetricAlertNotificationContent(event: drop).identifier
            == FleetMetricAlertNotificationContent(event: laterDrop).identifier)
        #expect(FleetMetricAlertNotificationContent(event: drop).identifier
            != FleetMetricAlertNotificationContent(event: spike).identifier)
    }

    @Test func foregroundMilestonesDoNotBannerOverTheInAppCelebration() {
        func present(_ category: String, _ visible: Bool) -> UNNotificationPresentationOptions {
            FleetNotificationDelegate.foregroundPresentation(
                forCategory: category, dashboardBannerVisible: visible, celebrationVisible: true)
        }
        let block = present("app.hashfleet.block", false)
        let allTime = present("app.hashfleet.bestShare", false)
        let status = present("", true)
        // Full-screen celebrations always cover these, so no banner on top.
        #expect(!block.contains(.banner) && block.contains(.list))
        #expect(!allTime.contains(.banner) && allTime.contains(.list))
        #expect(status.contains(.banner) && status.contains(.list))
        // A session now uses the same full-screen illustration, even above Settings sheets.
        let sessionShown = present(FleetNotificationDelegate.sessionBestCategory, true)
        let sessionHidden = present(FleetNotificationDelegate.sessionBestCategory, false)
        #expect(!sessionShown.contains(.banner) && sessionShown.contains(.list))
        #expect(!sessionHidden.contains(.banner) && sessionHidden.contains(.list))
        for category in FleetNotificationDelegate.fullScreenCelebratedCategories {
            let hidden = FleetNotificationDelegate.foregroundPresentation(
                forCategory: category, dashboardBannerVisible: false, celebrationVisible: false)
            #expect(hidden.contains(.banner), "A milestone without a visible celebration must banner.")
        }
        let toastOnly = FleetNotificationDelegate.foregroundPresentation(
            forCategory: FleetNotificationDelegate.sessionBestCategory,
            dashboardBannerVisible: true, celebrationVisible: false)
        #expect(toastOnly.contains(.banner), "An unrelated toast cannot claim the session record is visible.")
        // A badge applied while the app is open would stick until the next launch.
        for options in [block, allTime, status, sessionShown, sessionHidden] { #expect(!options.contains(.badge)) }
    }

    @Test func foregroundStoreDoesNotReannounceAnOutageReportedInTheBackground() throws {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // The foreground store holds a healthy in-memory reading when the app is suspended.
        let appStore = FleetStore(defaults: defaults)
        appStore.preferences.stateChangeNotificationsEnabled = true
        try appStore.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(appStore.devices.first)
        appStore.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
        _ = appStore.drainPendingNotificationEvents()

        // A BGTask store sees the outage and announces it.
        let backgroundStore = FleetStore(defaults: defaults)
        backgroundStore.recordFailedInfo("Timeout", for: device.id)
        var backgroundPosts = 0
        FleetNotificationDelivery.consume(from: backgroundStore, isActive: false,
            postStateChange: { _ in backgroundPosts += 1 })
        #expect(backgroundPosts == 1)

        // On resume the app reloads shared baselines; its next failed poll is the same outage.
        appStore.reloadSharedDetectionBaselines()
        appStore.restoreNotificationInbox()
        appStore.recordFailedInfo("Timeout", for: device.id)
        FleetNotificationDelivery.consume(from: appStore, isActive: true,
            postStateChange: { _ in Issue.record("The same outage was announced twice") },
            presentInApp: { _ in Issue.record("The same outage was announced twice") })
    }

    @Test func staleForegroundSnapshotStillAnnouncesRecoveryAfterBackgroundOutage() throws {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let appStore = FleetStore(defaults: defaults)
        appStore.preferences.stateChangeNotificationsEnabled = true
        try appStore.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(appStore.devices.first)
        appStore.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
        _ = appStore.drainPendingNotificationEvents()

        let backgroundStore = FleetStore(defaults: defaults)
        backgroundStore.recordFailedInfo("Timeout", for: device.id)
        FleetNotificationDelivery.consume(from: backgroundStore, isActive: false, postStateChange: { _ in })

        // The foreground snapshot never saw the error, but the shared state says offline, so the
        // recovery is announced and replaces the lingering offline notification.
        appStore.reloadSharedDetectionBaselines()
        appStore.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
        var posted: [MinerStateChangeEvent.Kind] = []
        FleetNotificationDelivery.consume(from: appStore, isActive: true,
            postStateChange: { _ in Issue.record("Pushed while the app was open") },
            presentInApp: { if case .stateChange(let change) = $0 { posted.append(change.kind) } })
        #expect(posted == [.backOnline])
    }

    @Test(arguments: [false, true])
    func identicalTelemetryAfterBackgroundOutageRecoversOnlyOnce(isCompleteSnapshot: Bool) throws {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let appStore = FleetStore(defaults: defaults)
        appStore.preferences.stateChangeNotificationsEnabled = true
        appStore.preferences.telemetryStorageEnabled = false
        try appStore.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(appStore.devices.first)
        let info = makeInfo()
        let firstDate = Date.now.addingTimeInterval(-60)
        #expect(appStore.recordSuccessfulInfo(info, for: device.id, at: firstDate))
        _ = appStore.drainPendingNotificationEvents()

        let backgroundStore = FleetStore(defaults: defaults)
        backgroundStore.recordFailedInfo("Timeout", for: device.id)
        FleetNotificationDelivery.consume(from: backgroundStore, isActive: false, postStateChange: { _ in })
        appStore.reloadSharedDetectionBaselines()

        let recoveryDate = Date.now
        #expect(appStore.recordSuccessfulInfo(
            info, for: device.id, at: recoveryDate, isCompleteSnapshot: isCompleteSnapshot))
        let recoveredSnapshot = try #require(appStore.snapshots[device.id])
        #expect(recoveredSnapshot.updatedAt == recoveryDate)
        #expect(recoveredSnapshot.completeSnapshotAt == (isCompleteSnapshot ? recoveryDate : firstDate))
        var posted: [MinerStateChangeEvent.Kind] = []
        let present: (FleetNotificationEvent) -> Void = {
            if case .stateChange(let change) = $0 { posted.append(change.kind) }
        }
        FleetNotificationDelivery.consume(from: appStore, isActive: true, presentInApp: present)
        #expect(posted == [.backOnline])

        // An identical reading after the recovery is ordinary duplicate telemetry again.
        #expect(!appStore.recordSuccessfulInfo(
            info, for: device.id, at: recoveryDate.addingTimeInterval(1),
            isCompleteSnapshot: isCompleteSnapshot))
        FleetNotificationDelivery.consume(from: appStore, isActive: true, presentInApp: present)
        #expect(posted == [.backOnline])
        #expect(appStore.snapshots[device.id]?.updatedAt == recoveryDate)
    }

    @Test func cachedReadingAloneDoesNotFabricateAnOfflineAlertOnColdLaunch() throws {
        try withStore { store in
            store.preferences.stateChangeNotificationsEnabled = true
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            // A restored last-known reading is not proof the miner was online this session.
            var snapshot = MinerSnapshot()
            snapshot.info = makeInfo()
            snapshot.updatedAt = .now
            snapshot.isCached = true
            store.snapshots[device.id] = snapshot
            store.recordFailedInfo("Timeout", for: device.id)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postStateChange: { _ in Issue.record("A cached reading fabricated an offline transition") })
        }
    }

    @Test func alreadyPresentedMilestoneIsRecognizedAsShownInApp() throws {
        try withStore { store in
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let event = MinerBestShareEvent(
                deviceID: device.id, minerName: "Desk", kind: .session,
                displayValue: "2M", rawValue: "2M", occurredAt: .now)
            store.enqueueNotification(.bestShare(event))
            #expect(!store.isInAppNotificationDelivered(.bestShare(event)))
            store.markInAppNotificationDelivered(for: .bestShare(event))
            #expect(store.isInAppNotificationDelivered(.bestShare(event)))
        }
    }

    @Test func flappingMinerAnnouncesEveryTransitionWithinTheDedupeWindow() throws {
        try withStore { store in
            store.preferences.stateChangeNotificationsEnabled = true
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
            _ = store.drainPendingNotificationEvents()

            var posted: [MinerStateChangeEvent.Kind] = []
            let record = { (event: MinerStateChangeEvent) in posted.append(event.kind) }
            // Two short outages inside one five-minute window. Because offline and recovery share
            // one notification slot, dropping the second offline would leave "back online" shown
            // while the miner is actually down again.
            store.recordFailedInfo("Timeout", for: device.id)
            FleetNotificationDelivery.consume(from: store, isActive: false, postStateChange: record)
            store.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
            FleetNotificationDelivery.consume(from: store, isActive: false, postStateChange: record)
            store.recordFailedInfo("Timeout", for: device.id)
            FleetNotificationDelivery.consume(from: store, isActive: false, postStateChange: record)
            #expect(posted == [.offline, .backOnline, .offline])
        }
    }

    @Test func replayNeverOverwritesANewerStatusWithAnOlderOne() throws {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        store.preferences.stateChangeNotificationsEnabled = true
        try store.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(store.devices.first)

        // An offline event was journaled but never handed to iOS (BG task expired), and the newer
        // recovery was delivered afterwards. Replaying the old offline into the shared slot would
        // replace "back online" with a stale disconnect.
        let offline = MinerStateChangeEvent(
            deviceID: device.id, minerName: "Desk", kind: .offline, detail: "Timeout",
            occurredAt: Date().addingTimeInterval(-600))
        let recovered = MinerStateChangeEvent(
            deviceID: device.id, minerName: "Desk", kind: .backOnline, occurredAt: .now)
        store.enqueueNotification(.stateChange(offline))
        store.enqueueNotification(.stateChange(recovered))
        store.markSystemNotificationDelivered(for: .stateChange(recovered))

        #expect(FleetNotificationDelivery.supersededStatusEntryIDs(in: store.notificationInbox)
            .contains(offline.id))
        #expect(!FleetNotificationDelivery.supersededStatusEntryIDs(in: store.notificationInbox)
            .contains(recovered.id))
    }

    @Test func removingAMinerClearsItsStatusSlotsAndJournal() throws {
        try withStore { store in
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.enqueueNotification(.stateChange(MinerStateChangeEvent(
                deviceID: device.id, minerName: "Desk", kind: .offline, detail: "Timeout", occurredAt: .now)))
            #expect(!store.notificationInbox.isEmpty)
            store.remove(device)
            #expect(store.notificationInbox.isEmpty)

            let identifiers = FleetLocalNotifications.statusNotificationIdentifiers(for: device.id)
            let state = FleetStateChangeNotificationContent(event: MinerStateChangeEvent(
                deviceID: device.id, minerName: "Desk", kind: .offline, occurredAt: .now)).identifier
            let power = FleetPowerAlertNotificationContent(event: MinerPowerAlertEvent(
                deviceID: device.id, minerName: "Desk", kind: .exceeded, watts: 1, thresholdWatts: 1,
                occurredAt: .now)).identifier
            let temperature = FleetTemperatureAlertNotificationContent(event: MinerTemperatureAlertEvent(
                deviceID: device.id, minerName: "Desk", temperatureCelsius: 80, thresholdCelsius: 75,
                occurredAt: .now)).identifier
            let metric = FleetMetricAlertNotificationContent(event: MinerMetricAlertEvent(
                deviceID: device.id, minerName: "Desk", kind: .efficiencyDrop, title: "", detail: "",
                occurredAt: .now)).identifier
            for identifier in [state, power, temperature, metric] { #expect(identifiers.contains(identifier)) }
        }
    }

    @Test func liveMonitoringOutageTriggersNotificationDelivery() throws {
        try withStore { store in
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
            _ = store.drainPendingNotificationEvents()
            let before = store.pendingNotificationsChangedAt

            // A live WebSocket failure falls back to recordFailedInfo without a full refresh.
            // The app delivers on this signal, so an outage must bump it even when no other
            // miner produces a reading.
            store.recordFailedInfo("Timeout", for: device.id)
            #expect(!store.pendingStateChangeEvents.isEmpty)
            #expect(store.pendingNotificationsChangedAt != before)
        }
    }

    // MARK: - One channel per event: in-app banner OR push, never both

    @Test func openAppShowsStatusInAppAndNeverPushes() throws {
        try withStore { store in
            store.preferences.stateChangeNotificationsEnabled = true
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
            _ = store.drainPendingNotificationEvents()
            store.recordFailedInfo("Timeout", for: device.id)

            var pushes = 0
            var banners = 0
            FleetNotificationDelivery.consume(from: store, isActive: true,
                postStateChange: { _ in pushes += 1 }, presentInApp: { _ in banners += 1 })
            #expect(pushes == 0 && banners == 1)
            // Leaving the app later must not push the outage the user already saw.
            FleetNotificationDelivery.consume(from: store, isActive: false, postStateChange: { _ in pushes += 1 })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store)
            #expect(pushes == 0)
        }
    }

    @Test func closedAppPushesAndNeverRepeatsAsBannerOnOpen() throws {
        try withStore { store in
            store.preferences.stateChangeNotificationsEnabled = true
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
            _ = store.drainPendingNotificationEvents()
            store.recordFailedInfo("Timeout", for: device.id)

            var pushes = 0
            var banners = 0
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postStateChange: { _ in pushes += 1 }, presentInApp: { _ in banners += 1 })
            #expect(pushes == 1 && banners == 0)
            // Opening the app afterwards must not show the same outage again as a banner.
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                from: store, isActive: true, presentInApp: { _ in banners += 1 })
            #expect(banners == 0)
        }
    }

    @Test func pushedMilestoneIsNotCelebratedAgainOnOpen() throws {
        try withStore { store in
            store.preferences.blockNotificationsEnabled = true
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let block = MinerBlockFoundEvent(
                deviceID: device.id, minerName: "Desk", coinLabel: "BTC", height: 1, count: 1, occurredAt: .now)
            store.pendingBlockFoundEvents.append(block)
            store.enqueueNotification(.blockFound(block))
            var pushes = 0
            FleetNotificationDelivery.consume(from: store, isActive: false, postBlock: { _ in pushes += 1 })
            #expect(pushes == 1)
            // The app's celebration checks this before presenting, so the push is the only surface.
            #expect(store.isInAppNotificationDelivered(.blockFound(block)))
        }
    }

    @Test func unsentBackgroundAlertIsShownInAppWhenOpenedNotPushedLate() throws {
        let suite = "app.hashfleet.lifecycle-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        store.preferences.stateChangeNotificationsEnabled = true
        try store.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(store.devices.first)
        // A background task detected the outage but expired before posting it.
        store.enqueueNotification(.stateChange(MinerStateChangeEvent(
            deviceID: device.id, minerName: "Desk", kind: .offline, detail: "Timeout", occurredAt: .now)))

        var banners = 0
        FleetNotificationDelivery.replayUndeliveredSystemNotifications(
            from: store, isActive: true, presentInApp: { _ in banners += 1 })
        #expect(banners == 1)
        #expect(store.undeliveredSystemNotificationEntries.isEmpty, "It must not also be pushed later.")
    }
}
