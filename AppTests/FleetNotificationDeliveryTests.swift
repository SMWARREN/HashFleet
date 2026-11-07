import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Notification delivery integration")
@MainActor
struct FleetNotificationDeliveryTests {
    private func withStore(_ body: (FleetStore) throws -> Void) rethrows {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(FleetStore(defaults: defaults))
    }

    private func enqueueMilestones(_ store: FleetStore) {
        for name in ["One", "Two"] {
            let device = MinerDevice(name: name, address: "\(name.lowercased()).local")
            store.devices.append(device)
            store.pendingBestShareEvents.append(MinerBestShareEvent(
                deviceID: device.id, minerName: name, kind: .allTime,
                displayValue: "2M", rawValue: "2M", occurredAt: .now
            ))
            store.pendingBlockFoundEvents.append(MinerBlockFoundEvent(
                deviceID: device.id, minerName: name, coinLabel: "BTC",
                height: 900_000, count: 1, occurredAt: .now
            ))
        }
    }

    @Test func inactiveDeliveryPostsEveryEnabledEventExactlyOnce() {
        withStore { store in
            store.preferences.blockNotificationsEnabled = true
            store.preferences.bestShareNotificationsEnabled = true
            enqueueMilestones(store)
            var blocks = 0
            var shares = 0
            for _ in 0..<2 {
                FleetNotificationDelivery.consume(from: store, isActive: false,
                    postBlock: { _ in blocks += 1 }, postBestShare: { _ in shares += 1 },
                    postTemperature: { _ in Issue.record("Unexpected temperature event") })
            }
            #expect(blocks == 2 && shares == 2)
        }
    }

    @Test func activeMilestonesStayInAppAndAreNeverPushed() {
        withStore { store in
            store.preferences.blockNotificationsEnabled = true
            store.preferences.bestShareNotificationsEnabled = true
            enqueueMilestones(store)
            // One channel per event: while the app is open the in-app celebration owns milestones,
            // so no system notification is posted now or replayed later.
            FleetNotificationDelivery.consume(from: store, isActive: true,
                postBlock: { _ in Issue.record("Pushed while the app was open") },
                postBestShare: { _ in Issue.record("Pushed while the app was open") },
                postTemperature: { _ in Issue.record("Unexpected event") })
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postBlock: { _ in Issue.record("Active event replayed") },
                postBestShare: { _ in Issue.record("Active event replayed") },
                postTemperature: { _ in Issue.record("Unexpected event") })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store)
            #expect(store.undeliveredSystemNotificationEntries.isEmpty)
            #expect(store.pendingBestShareEvents.isEmpty && store.pendingBlockFoundEvents.isEmpty)
        }
    }

    @Test func deletedMinerMilestonesAreDiscarded() {
        withStore { store in
            store.preferences.blockNotificationsEnabled = true
            store.preferences.bestShareNotificationsEnabled = true
            enqueueMilestones(store)
            for device in store.devices { store.remove(device) }
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postBlock: { _ in Issue.record("Removed miner notified") },
                postBestShare: { _ in Issue.record("Removed miner notified") })
            #expect(store.pendingBestShareEvents.isEmpty)
        }
    }

    @Test func foregroundRetainsAllSimultaneousThermalWarnings() throws {
        try withStore { store in
            for index in 1...2 {
                try store.add(name: "Miner \(index)", address: "192.168.1.\(index)")
                let device = try #require(store.devices.last)
                try store.temperatureAlerts.setPolicy(
                    MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: 70), for: device.id)
                store.recordSuccessfulInfo(MinerInfo(raw: ["temp": .number(80)]), for: device.id, at: .now)
            }
            let warnings = FleetNotificationDelivery.consume(from: store, isActive: true)
            #expect(warnings.count == 2)
            #expect(Set(warnings.map(\.deviceID)) == Set(store.devices.map(\.id)))
        }
    }

    @Test func disabledAndDemoMilestonesNeverPost() {
        withStore { store in
            // Best-share alerts now default on. This test exercises an explicit opt-out,
            // not a dependency on the old installation default.
            store.preferences.bestShareNotificationsEnabled = false
            for demo in [false, true] {
                if demo { store.loadDemo() }
                enqueueMilestones(store)
                FleetNotificationDelivery.consume(from: store, isActive: false,
                    postBlock: { _ in Issue.record("Disabled/demo event posted") },
                    postBestShare: { _ in Issue.record("Disabled/demo event posted") },
                    postTemperature: { _ in Issue.record("Disabled/demo event posted") })
                #expect(store.pendingBestShareEvents.isEmpty)
            }
        }
    }

    @Test func freshThermalReadingReachesForegroundWarningAndIsNotReplayed() throws {
        try withStore { store in
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            try store.temperatureAlerts.setPolicy(
                MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: 70), for: device.id)
            store.recordSuccessfulInfo(MinerInfo(raw: ["temp": .number(80)]), for: device.id, at: .now)
            let warnings = FleetNotificationDelivery.consume(from: store, isActive: true,
                postTemperature: { _ in Issue.record("Foreground notification posted") })
            #expect(warnings.count == 1)
            #expect(warnings.first?.deviceID == device.id)
            #expect(store.pendingTemperatureEvents.isEmpty)
            #expect(FleetNotificationDelivery.consume(from: store, isActive: false).isEmpty)
        }
    }

    @Test func retainedTemperatureInPartialUpdateDoesNotFabricateAnAlert() throws {
        try withStore { store in
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            try store.temperatureAlerts.setPolicy(
                MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: 70), for: device.id)
            store.recordSuccessfulInfo(MinerInfo(raw: ["temp": .number(80), "hashRate": .number(1200)]),
                for: device.id, at: .now, hasFreshTemperature: false)
            #expect(store.pendingTemperatureEvents.isEmpty)
            #expect(store.applyLiveMessage(.text(#"{"data":{"hashRate":1250}}"#), for: device.id))
            #expect(store.pendingTemperatureEvents.isEmpty)
            #expect(store.applyLiveMessage(.text(#"{"data":{"temp":80}}"#), for: device.id))
            #expect(store.pendingTemperatureEvents.count == 1)
        }
    }

    @Test func optingOutAfterDetectionSuppressesPendingThermalDelivery() throws {
        try withStore { store in
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            try store.temperatureAlerts.setPolicy(
                MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: 70), for: device.id)
            store.recordSuccessfulInfo(MinerInfo(raw: ["temp": .number(80)]), for: device.id, at: .now)
            try store.temperatureAlerts.setPolicy(MinerTemperatureAlertPolicy(), for: device.id)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postTemperature: { _ in Issue.record("Opted-out alert posted") })
            #expect(store.pendingTemperatureEvents.isEmpty)
        }
    }

    private func makeInfo(hashrate: Double = 500, power: Double = 15) -> MinerInfo {
        MinerInfo(raw: ["hashRate": .number(hashrate), "power": .number(power)])
    }

    @Test func offlineTransitionPostsOnceAndRecoveryPostsOnce() throws {
        try withStore { store in
            store.preferences.stateChangeNotificationsEnabled = true
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
            _ = store.drainPendingNotificationEvents()

            var posted: [MinerStateChangeEvent.Kind] = []
            // Repeated failures during one outage alert exactly once.
            for _ in 0..<3 {
                store.recordFailedInfo("Connection refused", for: device.id)
            }
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postStateChange: { posted.append($0.kind) },
                postMetricAlert: { _ in Issue.record("Unexpected metric alert") })
            #expect(posted == [.offline])

            // Recovery alerts once; a following steady poll stays silent.
            store.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
            store.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postStateChange: { posted.append($0.kind) })
            #expect(posted == [.offline, .backOnline])
        }
    }

    @Test func offlineDetectionSurvivesAColdStoreRelaunch() throws {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = FleetStore(defaults: defaults)
        try first.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(first.devices.first)
        first.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)

        // A background refresh builds a fresh store from the same defaults. The persisted
        // baseline still reports the miner as online, so the failure is an offline transition.
        let second = FleetStore(defaults: defaults)
        second.preferences.stateChangeNotificationsEnabled = true
        second.recordFailedInfo("Timeout", for: device.id)
        var posted = 0
        FleetNotificationDelivery.consume(from: second, isActive: false,
            postStateChange: { _ in posted += 1 })
        #expect(posted == 1)
        // And a second failed poll from yet another fresh store does not re-alert.
        let third = FleetStore(defaults: defaults)
        third.recordFailedInfo("Timeout", for: device.id)
        FleetNotificationDelivery.consume(from: third, isActive: false,
            postStateChange: { _ in Issue.record("Repeated outage re-alerted") })
    }

    @Test func backgroundMilestoneSurvivesStoreReloadForTheInAppSurface() throws {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let backgroundStore = FleetStore(defaults: defaults)
        backgroundStore.preferences.bestShareNotificationsEnabled = true
        try backgroundStore.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(backgroundStore.devices.first)
        backgroundStore.recordSuccessfulInfo(
            MinerInfo(raw: ["bestDiff": .string("1M"), "bestSessionDiff": .string("1M")]),
            for: device.id, at: .now)
        backgroundStore.recordSuccessfulInfo(
            MinerInfo(raw: ["bestDiff": .string("2M"), "bestSessionDiff": .string("1M")]),
            for: device.id, at: .now)

        var posted = 0
        FleetNotificationDelivery.consume(from: backgroundStore, isActive: false,
            postBestShare: { _ in posted += 1 })
        #expect(posted == 1)

        // One channel per event: the record was already pushed, so opening the app does not
        // celebrate it a second time. It stays in the journal as delivered on both surfaces.
        let foregroundStore = FleetStore(defaults: defaults)
        #expect(foregroundStore.latestBestShareEvent == nil)
        #expect(foregroundStore.notificationInbox.count == 1)
        #expect(foregroundStore.notificationInbox.first?.systemDelivered == true)
        #expect(foregroundStore.notificationInbox.first?.inAppDelivered == true)
    }

    @Test func undeliveredBackgroundMilestoneIsCelebratedInAppOnOpen() throws {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // A background task detected a record but expired before pushing it. The app is the
        // single surface, so opening it hydrates the celebration and never pushes late.
        let backgroundStore = FleetStore(defaults: defaults)
        backgroundStore.preferences.bestShareNotificationsEnabled = true
        try backgroundStore.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(backgroundStore.devices.first)
        backgroundStore.recordSuccessfulInfo(
            MinerInfo(raw: ["bestDiff": .string("1M"), "bestSessionDiff": .string("1M")]),
            for: device.id, at: .now)
        backgroundStore.recordSuccessfulInfo(
            MinerInfo(raw: ["bestDiff": .string("2M"), "bestSessionDiff": .string("1M")]),
            for: device.id, at: .now)

        let foregroundStore = FleetStore(defaults: defaults)
        #expect(foregroundStore.latestBestShareEvent?.rawValue == "2M")
        FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: foregroundStore, isActive: true)
        #expect(foregroundStore.undeliveredSystemNotificationEntries.isEmpty)
    }

    @Test func undeliveredBackgroundEventIsReplayedExactlyOnce() throws {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let backgroundStore = FleetStore(defaults: defaults)
        backgroundStore.preferences.blockNotificationsEnabled = true
        try backgroundStore.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(backgroundStore.devices.first)
        backgroundStore.recordSuccessfulInfo(
            MinerInfo(raw: ["blockFound": .integer(0)]), for: device.id, at: .now)
        backgroundStore.recordSuccessfulInfo(
            MinerInfo(raw: ["blockFound": .integer(1)]), for: device.id, at: .now)

        let foregroundStore = FleetStore(defaults: defaults)
        #expect(foregroundStore.notificationInbox.first?.systemDelivered == false)
        FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: foregroundStore)
        #expect(foregroundStore.notificationInbox.first?.systemDelivered == true)
        FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: foregroundStore)
        #expect(foregroundStore.notificationInbox.filter { !$0.systemDelivered }.isEmpty)
    }

    @Test func resumeReloadsJournalWrittenByASeparateBackgroundStore() throws {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let appStore = FleetStore(defaults: defaults)
        try appStore.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(appStore.devices.first)

        // The app store remains in memory while a BGTask handler creates its own store.
        let backgroundStore = FleetStore(defaults: defaults)
        backgroundStore.preferences.bestShareNotificationsEnabled = true
        backgroundStore.recordSuccessfulInfo(
            MinerInfo(raw: ["bestDiff": .string("1M"), "bestSessionDiff": .string("1M")]),
            for: device.id, at: .now)
        backgroundStore.recordSuccessfulInfo(
            MinerInfo(raw: ["bestDiff": .string("2M"), "bestSessionDiff": .string("1M")]),
            for: device.id, at: .now)
        FleetNotificationDelivery.consume(from: backgroundStore, isActive: false)

        #expect(appStore.latestBestShareEvent == nil)
        appStore.restoreNotificationInbox()
        // The journal is reloaded, but the record was already pushed, so it is not celebrated again.
        #expect(appStore.notificationInbox.first?.systemDelivered == true)
        #expect(appStore.notificationInbox.first?.inAppDelivered == true)
        #expect(appStore.latestBestShareEvent == nil)
    }

    @Test func significantHashrateDropAlertsAndSmallDriftDoesNot() throws {
        try withStore { store in
            store.preferences.metricAlertNotificationsEnabled = true
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.recordSuccessfulInfo(makeInfo(hashrate: 500, power: 15), for: device.id, at: .now)
            _ = store.drainPendingNotificationEvents()

            var posted: [MinerMetricAlertEvent.Kind] = []
            // 2% drift is normal noise, not an alert.
            store.recordSuccessfulInfo(makeInfo(hashrate: 490, power: 15), for: device.id, at: .now)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postMetricAlert: { posted.append($0.kind) })
            #expect(posted.isEmpty)

            // A drop below the 30% threshold, plus a stopped hashrate, both alert once.
            store.recordSuccessfulInfo(makeInfo(hashrate: 300, power: 15), for: device.id, at: .now)
            store.recordSuccessfulInfo(makeInfo(hashrate: 0, power: 2), for: device.id, at: .now)
            FleetNotificationDelivery.consume(from: store, isActive: true,
                postMetricAlert: { _ in Issue.record("Pushed while the app was open") },
                presentInApp: { if case .metricAlert(let alert) = $0 { posted.append(alert.kind) } })
            #expect(posted == [.hashrateDrop, .hashrateStopped])
        }
    }

    @Test func powerSpikeAndEfficiencyDropAlert() throws {
        try withStore { store in
            store.preferences.metricAlertNotificationsEnabled = true
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.recordSuccessfulInfo(makeInfo(hashrate: 500, power: 15), for: device.id, at: .now)
            _ = store.drainPendingNotificationEvents()

            var posted: [MinerMetricAlertEvent.Kind] = []
            // Power +33% at the same hashrate is a spike; the spike takes priority.
            store.recordSuccessfulInfo(makeInfo(hashrate: 500, power: 20), for: device.id, at: .now)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postMetricAlert: { posted.append($0.kind) })
            #expect(posted == [.powerSpike])

            // Hashrate -10% with power +20% clears neither single-metric threshold, but the
            // efficiency worsens by 33% on its own.
            store.recordSuccessfulInfo(makeInfo(hashrate: 450, power: 24), for: device.id, at: .now)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postMetricAlert: { posted.append($0.kind) })
            #expect(posted == [.powerSpike, .efficiencyDrop])
        }
    }

    @Test func disabledAndDemoSuppressStateAndMetricDelivery() throws {
        try withStore { store in
            store.preferences.stateChangeNotificationsEnabled = false
            store.preferences.metricAlertNotificationsEnabled = false
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.recordSuccessfulInfo(makeInfo(hashrate: 500, power: 15), for: device.id, at: .now)
            store.recordSuccessfulInfo(makeInfo(hashrate: 100, power: 15), for: device.id, at: .now)
            store.recordFailedInfo("Timeout", for: device.id)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postStateChange: { _ in Issue.record("Disabled state change posted") },
                postMetricAlert: { _ in Issue.record("Disabled metric alert posted") })

            // Detection queues nothing in demo mode and delivery drains without posting.
            store.loadDemo()
            store.preferences.stateChangeNotificationsEnabled = true
            store.preferences.metricAlertNotificationsEnabled = true
            store.recordFailedInfo("Timeout", for: device.id)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postStateChange: { _ in Issue.record("Demo state change posted") },
                postMetricAlert: { _ in Issue.record("Demo metric alert posted") })
            #expect(store.pendingStateChangeEvents.isEmpty && store.pendingMetricAlertEvents.isEmpty)
        }
    }

    @Test func disconnectNotificationContentIncludesTimestampAndReason() {
        let occurredAt = Date(timeIntervalSince1970: 1_780_000_000)
        let offline = FleetStateChangeNotificationContent(event: MinerStateChangeEvent(
            deviceID: UUID(), minerName: "Desk", kind: .offline,
            detail: "Connection refused", occurredAt: occurredAt))
        #expect(offline.title == "Desk went offline")
        #expect(offline.body.contains("Connection refused"))
        let expectedTimestamp = occurredAt.formatted(date: .abbreviated, time: .shortened)
        #expect(offline.body.contains(expectedTimestamp))
        #expect(offline.identifier.hasPrefix("app.hashfleet.state-change."))

        let recovered = FleetStateChangeNotificationContent(event: MinerStateChangeEvent(
            deviceID: UUID(), minerName: "Desk", kind: .backOnline, occurredAt: occurredAt))
        #expect(recovered.title == "Desk is back online")
        #expect(recovered.body.contains(expectedTimestamp))
    }

    @Test func disconnectToggleOffSuppressesOnlyDisconnectDelivery() throws {
        try withStore { store in
            store.preferences.stateChangeNotificationsEnabled = false
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.recordSuccessfulInfo(makeInfo(), for: device.id, at: .now)
            _ = store.drainPendingNotificationEvents()
            store.recordFailedInfo("Connection refused", for: device.id)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postStateChange: { _ in Issue.record("Opted-out disconnect posted") })
            // The event is drained even when suppressed so it cannot replay after re-enabling.
            #expect(store.pendingStateChangeEvents.isEmpty)
        }
    }
}
