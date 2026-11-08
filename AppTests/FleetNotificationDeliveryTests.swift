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

    // MARK: - Acknowledged in-app handoff (durable celebration queue)

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    /// Distinct raw values keep each event distinct under the journal's observation dedupe, and the
    /// ascending timestamps keep the journal's chronological order equal to creation order.
    private func recordEvent(
        _ device: MinerDevice, _ raw: String, order: Int,
        kind: MinerBestShareEvent.Kind = .allTime
    ) -> FleetNotificationEvent {
        .bestShare(MinerBestShareEvent(
            deviceID: device.id, minerName: device.name, kind: kind, displayValue: raw, rawValue: raw,
            occurredAt: Date().addingTimeInterval(TimeInterval(order - 600))))
    }

    /// Journal only, as a previous launch would have left it.
    private func journal(_ events: [FleetNotificationEvent], in store: FleetStore) {
        for event in events { store.enqueueNotification(event) }
    }

    /// Journal and drain queue, as real detection does.
    private func detect(_ events: [FleetNotificationEvent], in store: FleetStore) {
        journal(events, in: store)
        for case .bestShare(let share) in events { store.pendingBestShareEvents.append(share) }
    }

    private func entry(for event: FleetNotificationEvent, in store: FleetStore) -> FleetNotificationInboxEntry? {
        store.notificationInbox.first { $0.id == event.id }
    }

    @Test func declinedHandoffKeepsAMarkerAndALaterAcceptanceClearsIt() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let event = recordEvent(device, "2M", order: 0)
            detect([event], in: store)

            var offered: [UUID] = []
            var markerDuringHandoff: [Bool?] = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                markerDuringHandoff.append(store.notificationInbox.first { $0.id == offeredEvent.id }?.inAppAcceptancePending)
                return false
            })
            #expect(offered == [event.id])
            #expect(markerDuringHandoff == [true], "The marker is durable before the handoff is attempted.")
            let declined = try #require(entry(for: event, in: store))
            #expect(declined.systemDelivered, "Active delivery never also pushes the event.")
            #expect(declined.inAppDelivered == false, "A declined handoff is not a shown popup.")
            #expect(declined.inAppAcceptancePending == true)
            #expect(store.undeliveredSystemNotificationEntries.isEmpty)

            // Nothing fresh is queued, so this empty consume must retry the older marked entry.
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [event.id])
            let accepted = try #require(entry(for: event, in: store))
            #expect(accepted.inAppDelivered && accepted.systemDelivered)
            #expect(accepted.inAppAcceptancePending != true, "Acceptance clears the marker.")

            // Accepted records are never offered again.
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty)
        }
    }

    @Test func declinedHandoffSurvivesStoreReconstructionAndRetriesFromTheSameDefaults() throws {
        try withDefaults { defaults in
            let first = FleetStore(defaults: defaults)
            try first.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(first.devices.first)
            let event = recordEvent(device, "2M", order: 0)
            detect([event], in: first)
            FleetNotificationDelivery.consume(from: first, isActive: true, acceptInApp: { _ in false })

            // A relaunch builds a new store from the same defaults. The marker must have been persisted.
            let second = FleetStore(defaults: defaults)
            let restored = try #require(entry(for: event, in: second))
            #expect(restored.inAppAcceptancePending == true)
            #expect(restored.systemDelivered && !restored.inAppDelivered)

            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: second, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [event.id])

            // And the acceptance is itself durable: a third store has nothing left to retry.
            let third = FleetStore(defaults: defaults)
            let settled = try #require(entry(for: event, in: third))
            #expect(settled.inAppDelivered && settled.inAppAcceptancePending != true)
            offered = []
            FleetNotificationDelivery.consume(from: third, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: third, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty)
        }
    }

    @Test func inboxEntryWithoutAnAcceptanceMarkerStillDecodes() throws {
        let device = MinerDevice(name: "Desk", address: "desk.local")
        let event = recordEvent(device, "2M", order: 0)
        let legacy = FleetNotificationInboxEntry(event: event, systemDelivered: true, inAppDelivered: false)

        // Entries written by the previous build have exactly the three original keys.
        let encoded = try JSONEncoder().encode([legacy])
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        object[0].removeValue(forKey: "inAppAcceptancePending")
        #expect(Set(object[0].keys) == ["event", "systemDelivered", "inAppDelivered"])
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode([FleetNotificationInboxEntry].self, from: legacyData)
        #expect(decoded.count == 1)
        #expect(decoded[0].event == event && decoded[0].systemDelivered && !decoded[0].inAppDelivered)
        #expect(decoded[0].inAppAcceptancePending == nil)
        #expect(decoded[0] == legacy)

        // A marked entry round-trips.
        var marked = legacy
        marked.inAppAcceptancePending = true
        let markedRoundTrip = try JSONDecoder().decode(
            [FleetNotificationInboxEntry].self, from: JSONEncoder().encode([marked]))
        #expect(markedRoundTrip == [marked] && markedRoundTrip[0].inAppAcceptancePending == true)

        // The real store restores a legacy journal from defaults without inventing a marker.
        try withDefaults { defaults in
            let seed = FleetStore(defaults: defaults)
            try seed.add(name: "Desk", address: "192.168.1.10")
            let seeded = try #require(seed.devices.first)
            let seededEvent = recordEvent(seeded, "3M", order: 1)
            let entryOnDisk = FleetNotificationInboxEntry(event: seededEvent, systemDelivered: true, inAppDelivered: false)
            var json = try #require(JSONSerialization.jsonObject(
                with: JSONEncoder().encode([entryOnDisk])) as? [[String: Any]])
            json[0].removeValue(forKey: "inAppAcceptancePending")
            defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: FleetStore.notificationInboxStorageKey)

            let reopened = FleetStore(defaults: defaults)
            let restored = try #require(entry(for: seededEvent, in: reopened))
            #expect(restored.inAppAcceptancePending == nil)
            #expect(restored.systemDelivered && !restored.inAppDelivered)
        }
    }

    @Test func historicalSuppressedEntriesAreNeverResurrectedByAcceptanceRetry() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)

            // History 1: delivered or intentionally suppressed by an older build.
            let legacy = recordEvent(device, "2M", order: 0)
            journal([legacy], in: store)
            let legacyIndex = try #require(store.notificationInbox.firstIndex { $0.id == legacy.id })
            store.notificationInbox[legacyIndex].systemDelivered = true
            store.persistNotificationInbox()

            // History 2: suppressed by the user's preference through the real delivery path.
            store.preferences.bestShareNotificationsEnabled = false
            let suppressed = recordEvent(device, "3M", order: 1)
            detect([suppressed], in: store)
            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty)
            let suppressedEntry = try #require(entry(for: suppressed, in: store))
            #expect(suppressedEntry.systemDelivered && !suppressedEntry.inAppDelivered)
            #expect(suppressedEntry.inAppAcceptancePending != true)

            // Re-enabling the preference and a fresh record must offer only the fresh record.
            store.preferences.bestShareNotificationsEnabled = true
            let fresh = recordEvent(device, "4M", order: 2)
            detect([fresh], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [fresh.id])
            for old in [legacy, suppressed] {
                let kept = try #require(entry(for: old, in: store))
                #expect(!kept.inAppDelivered && kept.inAppAcceptancePending != true, "History stays history.")
            }
        }
    }

    @Test func firstDeclinedHandoffBlocksLaterRecordsAndPreservesFIFO() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            let c = recordEvent(device, "4M", order: 2)
            detect([a, b, c], in: store)

            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return false
            })
            #expect(offered == [a.id], "After the first decline no later record may be handed off.")
            #expect(entry(for: a, in: store)?.inAppAcceptancePending == true)
            for waiting in [b, c] { #expect(entry(for: waiting, in: store)?.inAppDelivered == false) }

            // A fresh record arriving while the oldest is still declined waits behind all of them.
            let d = recordEvent(device, "5M", order: 3)
            detect([d], in: store)
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return false
            })
            #expect(offered == [a.id], "The retry stops at the oldest declined record, fresh record included.")
            for waiting in [b, c, d] { #expect(entry(for: waiting, in: store)?.inAppDelivered == false) }

            // Once storage accepts, every record is handed off exactly once in the original order.
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [a.id, b.id, c.id, d.id])
            for event in [a, b, c, d] {
                let settled = try #require(entry(for: event, in: store))
                #expect(settled.inAppDelivered && settled.inAppAcceptancePending != true)
            }
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty)
        }
    }

    @Test func declinedFreshRecordIsRetriedBeforeAnyLaterFreshRecord() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let first = recordEvent(device, "2M", order: 0)
            detect([first], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })

            let second = recordEvent(device, "3M", order: 1)
            detect([second], in: store)
            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [first.id, second.id], "Older marked entries are retried before fresh ones.")
        }
    }

    @Test func replayRetriesOnlyExplicitlyMarkedEntriesInOrder() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let historical = recordEvent(device, "2M", order: 0)
            let firstMarked = recordEvent(device, "3M", order: 1)
            let secondMarked = recordEvent(device, "4M", order: 2)
            journal([historical, firstMarked, secondMarked], in: store)
            for index in store.notificationInbox.indices {
                store.notificationInbox[index].systemDelivered = true
                if store.notificationInbox[index].id != historical.id {
                    store.notificationInbox[index].inAppAcceptancePending = true
                }
            }
            store.persistNotificationInbox()

            // Inactive replay never offers an in-app handoff.
            var offered: [UUID] = []
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: false, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty)

            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return false
            })
            #expect(offered == [firstMarked.id], "A decline stops the replay so FIFO holds.")
            #expect(entry(for: firstMarked, in: store)?.inAppAcceptancePending == true)

            offered = []
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [firstMarked.id, secondMarked.id])
            for event in [firstMarked, secondMarked] {
                let settled = try #require(entry(for: event, in: store))
                #expect(settled.inAppDelivered && settled.inAppAcceptancePending != true)
            }
            let untouched = try #require(entry(for: historical, in: store))
            #expect(!untouched.inAppDelivered && untouched.inAppAcceptancePending != true)
        }
    }

    @Test func backgroundPostedEventsAreNeverReplayedInTheApp() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let event = recordEvent(device, "2M", order: 0)
            detect([event], in: store)

            var posted = 0
            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postBestShare: { _ in posted += 1 },
                acceptInApp: { offeredEvent in
                    offered.append(offeredEvent.id)
                    return true
                })
            #expect(posted == 1 && offered.isEmpty)
            let pushed = try #require(entry(for: event, in: store))
            #expect(pushed.systemDelivered && pushed.inAppDelivered && pushed.inAppAcceptancePending != true)

            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty, "A pushed event is never celebrated a second time.")
            #expect(posted == 1)
        }
    }

    @Test func acceptedHandoffMarksBothChannelsAndIsNeverRepeated() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let events = [recordEvent(device, "2M", order: 0), recordEvent(device, "3M", order: 1, kind: .session)]
            detect(events, in: store)
            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true,
                postBestShare: { _ in Issue.record("Pushed while the app was open") },
                acceptInApp: { offeredEvent in
                    offered.append(offeredEvent.id)
                    return true
                })
            #expect(offered == events.map(\.id))
            for event in events {
                let settled = try #require(entry(for: event, in: store))
                #expect(settled.systemDelivered && settled.inAppDelivered && settled.inAppAcceptancePending != true)
            }
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == events.map(\.id))
        }
    }

    @Test func legacyVoidCallbackStaysMarkBeforeCallAndReentrantSafe() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let first = recordEvent(device, "2M", order: 0)
            let second = recordEvent(device, "3M", order: 1)
            let third = recordEvent(device, "4M", order: 2)
            // Two entries left by an earlier launch, plus one that detection delivers during the callback.
            journal([first, second], in: store)

            var counts: [UUID: Int] = [:]
            var reentered = false
            @MainActor
            func handoff(_ event: FleetNotificationEvent) {
                counts[event.id, default: 0] += 1
                // The entry is already marked shown before the callback, so re-entry cannot repeat it.
                let alreadyMarkedShown = store.isInAppNotificationDelivered(event)
                #expect(alreadyMarkedShown)
                guard !reentered else { return }
                reentered = true
                detect([third], in: store)
                FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                    from: store, isActive: true, presentInApp: handoff)
                FleetNotificationDelivery.consume(from: store, isActive: true, presentInApp: handoff)
            }
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                from: store, isActive: true, presentInApp: handoff)
            #expect(counts[first.id] == 1 && counts[second.id] == 1 && counts[third.id] == 1)
            #expect(counts.count == 3)
            FleetNotificationDelivery.consume(from: store, isActive: true, presentInApp: handoff)
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                from: store, isActive: true, presentInApp: handoff)
            #expect(counts.values.allSatisfy { $0 == 1 })
        }
    }

    @Test func durableAcceptCallbackReenteringConsumeAndReplayNeitherDuplicatesNorDrains() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            let late = recordEvent(device, "4M", order: 2)
            detect([a, b], in: store)

            var offered: [UUID] = []
            var nestedOffers: [UUID] = []
            var reentered = false
            var stateInsideCallback: (pending: Bool?, shown: Bool)?
            var drainedByReentry = true
            @MainActor
            func accept(_ event: FleetNotificationEvent) -> Bool {
                offered.append(event.id)
                guard !reentered else { return true }
                reentered = true
                let inside = store.notificationInbox.first { $0.id == event.id }
                stateInsideCallback = (inside?.inAppAcceptancePending, inside?.inAppDelivered ?? true)
                // A record detected while the first handoff is in flight, then both entry points re-entered.
                detect([late], in: store)
                FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { nested in
                    nestedOffers.append(nested.id)
                    return true
                })
                FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                    from: store, isActive: true, acceptInApp: { nested in
                        nestedOffers.append(nested.id)
                        return true
                    })
                // The re-entrant call must not have drained the queue of fresh detections.
                drainedByReentry = store.pendingBestShareEvents.isEmpty
                return true
            }

            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            #expect(offered == [a.id, b.id], "Each drained record is offered exactly once, in order.")
            #expect(nestedOffers.isEmpty, "Re-entrant consume/replay must not offer anything.")
            #expect(stateInsideCallback?.pending == true && stateInsideCallback?.shown == false,
                    "During the handoff the record is marked pending and not yet shown.")
            #expect(!drainedByReentry, "Re-entrant consume must not drain fresh detections.")
            #expect(store.pendingBestShareEvents.map(\.id) == [late.id])

            // Once the outer handoff has returned, delivery resumes and the late record is offered once.
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: accept)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            #expect(offered == [a.id, b.id, late.id])
            for event in [a, b, late] {
                let settled = try #require(entry(for: event, in: store))
                #expect(settled.inAppDelivered && settled.systemDelivered && settled.inAppAcceptancePending != true)
            }
        }
    }

    @Test func reenteringDurableCallbackThatDeclinesStillLeavesOneRetryableRecord() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            detect([a, b], in: store)

            var offered: [UUID] = []
            var shouldAccept = false
            @MainActor
            func accept(_ event: FleetNotificationEvent) -> Bool {
                offered.append(event.id)
                // Re-enter while declining. It must not hand anything off, in either direction.
                FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { nested in
                    offered.append(nested.id)
                    return true
                })
                FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                    from: store, isActive: true, acceptInApp: { nested in
                        offered.append(nested.id)
                        return true
                    })
                return shouldAccept
            }
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            #expect(offered == [a.id])
            #expect(entry(for: a, in: store)?.inAppAcceptancePending == true)
            #expect(entry(for: a, in: store)?.inAppDelivered == false)
            #expect(entry(for: b, in: store)?.inAppDelivered == false)

            shouldAccept = true
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            #expect(offered == [a.id, b.id])
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            #expect(offered == [a.id, b.id])
        }
    }

    @Test func notificationRouteIsRetainedUntilExplicitlyConsumedAfterAFailedHandoff() throws {
        try withDefaults { defaults in
            let miner = UUID()
            let celebration = FleetCelebration(kind: .blockFound, deviceID: miner, minerName: "Desk",
                                               value: "900,000", detail: "Block found at this height")
            #expect(FleetNotificationRoute.handle(userInfo: celebration.userInfo, defaults: defaults))

            let route = try #require(FleetNotificationRoute.pending(defaults: defaults))
            #expect(route.deviceID == miner)
            #expect(route.celebration == celebration, "The exact record, including its ID, round-trips.")

            // Storage refuses the record: nothing may be consumed, so the tap is not lost.
            let routed = try #require(route.celebration)
            var unavailable = FleetCelebrationQueue(unavailableMessage: "Storage is unavailable.")
            let refused = unavailable.present(routed)
            #expect(refused == false)
            #expect(FleetNotificationRoute.pending(defaults: defaults) == route)
            #expect(FleetNotificationRoute.pending(defaults: defaults) == route, "Peeking is repeatable.")

            // A later successful handoff then consumes it exactly once.
            var queue = FleetCelebrationQueue()
            let accepted = queue.present(routed)
            #expect(accepted)
            #expect(FleetNotificationRoute.consume(defaults: defaults) == route)
            #expect(FleetNotificationRoute.pending(defaults: defaults) == nil)
            #expect(FleetNotificationRoute.consume(defaults: defaults) == nil)
            #expect(queue.current == celebration)
        }
    }

    @Test func notificationRouteWithoutARecordPayloadStillRoutesToTheMiner() throws {
        try withDefaults { defaults in
            let miner = UUID()
            #expect(FleetNotificationRoute.handle(
                userInfo: [FleetCelebration.userInfoDevice: miner.uuidString], defaults: defaults))
            let route = try #require(FleetNotificationRoute.pending(defaults: defaults))
            #expect(route.deviceID == miner && route.celebration == nil)
            #expect(FleetNotificationRoute.consume(defaults: defaults) == route)
            #expect(FleetNotificationRoute.pending(defaults: defaults) == nil)
        }
    }

    // MARK: - Status alerts are never blocked by a declined record handoff

    private func statusEvents(_ device: MinerDevice, order: Int) -> (state: FleetNotificationEvent, power: FleetNotificationEvent) {
        let when = Date().addingTimeInterval(TimeInterval(order - 600))
        return (
            .stateChange(MinerStateChangeEvent(
                deviceID: device.id, minerName: device.name, kind: .offline,
                detail: "Connection refused", occurredAt: when)),
            .power(MinerPowerAlertEvent(
                deviceID: device.id, minerName: device.name, kind: .exceeded,
                watts: 140, thresholdWatts: 100, occurredAt: when)))
    }

    private func enableStatusAlerts(_ store: FleetStore, for device: MinerDevice) throws {
        store.preferences.bestShareNotificationsEnabled = true
        store.preferences.stateChangeNotificationsEnabled = true
        store.preferences.powerAlertNotificationsEnabled = true
        try store.powerAlerts.setPolicy(try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 100), for: device.id)
    }

    private func queueStatus(_ events: (state: FleetNotificationEvent, power: FleetNotificationEvent), in store: FleetStore) {
        journal([events.state, events.power], in: store)
        if case .stateChange(let change) = events.state { store.pendingStateChangeEvents.append(change) }
        if case .power(let power) = events.power { store.pendingPowerAlertEvents.append(power) }
    }

    @Test func declinedRecordNeverBlocksOfflineAndPowerSafetyAlertsInTheSamePass() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            try enableStatusAlerts(store, for: device)
            let record = recordEvent(device, "2M", order: 0)
            let status = statusEvents(device, order: 1)
            detect([record], in: store)
            queueStatus(status, in: store)

            var offered: [UUID] = []
            @MainActor
            func accept(_ event: FleetNotificationEvent) -> Bool {
                offered.append(event.id)
                // Only the durable record queue can decline. Status alerts use the transient surface.
                if case .bestShare = event { return false }
                return true
            }
            FleetNotificationDelivery.consume(from: store, isActive: true,
                postStateChange: { _ in Issue.record("Pushed while the app was open") },
                postPower: { _ in Issue.record("Pushed while the app was open") },
                acceptInApp: accept)

            #expect(Set(offered) == [record.id, status.state.id, status.power.id],
                    "A declined record must not hold back safety alerts in the same pass.")
            #expect(offered.filter { $0 == status.state.id }.count == 1)
            #expect(offered.filter { $0 == status.power.id }.count == 1)

            for event in [status.state, status.power] {
                let settled = try #require(entry(for: event, in: store))
                #expect(settled.systemDelivered && settled.inAppDelivered, "Status alerts are delivered.")
                #expect(settled.inAppAcceptancePending != true)
            }
            let waiting = try #require(entry(for: record, in: store))
            #expect(waiting.inAppAcceptancePending == true && !waiting.inAppDelivered, "The record stays retryable.")

            // The next pass retries only the record. Delivered status alerts are not offered again.
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { event in
                offered.append(event.id)
                return true
            })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { event in
                offered.append(event.id)
                return true
            })
            #expect(offered == [record.id])
            let settled = try #require(entry(for: record, in: store))
            #expect(settled.inAppDelivered && settled.inAppAcceptancePending != true)
        }
    }

    @Test func freshStatusAlertReachesTheAppWhileAnOlderRecordIsStillDeclined() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            try enableStatusAlerts(store, for: device)
            let record = recordEvent(device, "2M", order: 0)
            detect([record], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            #expect(entry(for: record, in: store)?.inAppAcceptancePending == true)

            // An offline alert arrives while the older record is still being declined by storage.
            let status = statusEvents(device, order: 1)
            queueStatus(status, in: store)
            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { event in
                offered.append(event.id)
                if case .bestShare = event { return false }
                return true
            })
            #expect(offered.contains(status.state.id) && offered.contains(status.power.id),
                    "The retry loop must still offer status alerts.")
            #expect(offered.filter { $0 == record.id }.count == 1, "The declined record is retried, not duplicated.")
            #expect(entry(for: status.state, in: store)?.inAppDelivered == true)
            #expect(entry(for: status.power, in: store)?.inAppDelivered == true)
            #expect(entry(for: record, in: store)?.inAppAcceptancePending == true)
            #expect(entry(for: record, in: store)?.inAppDelivered == false)
        }
    }

    @Test func alreadyShownEventStillMarksTheSystemChannelWhenAcceptanceIsEnabled() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let event = recordEvent(device, "2M", order: 0)
            detect([event], in: store)
            // The record was already shown in the app, but the system channel is not yet marked.
            store.markInAppNotificationDelivered(for: event)
            #expect(entry(for: event, in: store)?.systemDelivered == false)

            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true,
                postBestShare: { _ in Issue.record("Pushed while the app was open") },
                acceptInApp: { offeredEvent in
                    offered.append(offeredEvent.id)
                    return true
                })
            #expect(offered.isEmpty, "A record already shown is not offered again.")
            let settled = try #require(entry(for: event, in: store))
            #expect(settled.systemDelivered, "Active delivery keeps its old channel semantics: never pushed later.")
            #expect(settled.inAppDelivered)
            #expect(store.undeliveredSystemNotificationEntries.isEmpty)
        }
    }
}

// The existing synchronous routing tests above remain unchanged. These tests exercise the
// new suspended durable handoff boundary used by both app entry points.
extension FleetNotificationDeliveryTests {
    @MainActor private final class AcceptanceGate {
        var entered = false
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            entered = true
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }

    private func withAsyncStore(_ body: (FleetStore) async throws -> Void) async rethrows {
        let suite = "app.hashfleet.async-delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(FleetStore(defaults: defaults))
    }

    @Test func suspendedDurableHandoffKeepsJournalPendingAndSafetyAlertsImmediate() async throws {
        try await withAsyncStore { store in
            try store.add(name: "Desk", address: "127.0.0.1")
            store.preferences.bestShareNotificationsEnabled = true
            store.preferences.stateChangeNotificationsEnabled = true
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            detect([a, b], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            let gate = AcceptanceGate()
            var offered: [UUID] = []
            let pump = FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { event in
                offered.append(event.id)
                if event.id == a.id { await gate.wait() }
                return true
            }
            for _ in 0..<100 where !gate.entered { try await Task.sleep(for: .milliseconds(5)) }
            #expect(gate.entered)
            #expect(offered == [a.id])
            #expect(entry(for: a, in: store)?.inAppDelivered == false)
            #expect(entry(for: a, in: store)?.inAppAcceptancePending == true)
            let c = recordEvent(device, "4M", order: 2)
            detect([c], in: store)
            let alert = MinerStateChangeEvent(deviceID: device.id, minerName: device.name,
                kind: .offline, detail: "controlled safety alert", occurredAt: .now)
            store.pendingStateChangeEvents.append(alert)
            var safetyShown = false
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { event in
                if case .stateChange = event { safetyShown = true; return true }
                return false
            })
            let samePump = FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { _ in
                Issue.record("A second writer ran while the first handoff was suspended")
                return true
            }
            #expect(safetyShown && offered == [a.id])
            #expect(entry(for: c, in: store)?.inAppDelivered == false)
            gate.open()
            await pump.value
            await samePump.value
            #expect(offered == [a.id, b.id, c.id])
            for event in [a, b, c] {
                #expect(entry(for: event, in: store)?.inAppDelivered == true)
                #expect(entry(for: event, in: store)?.inAppAcceptancePending != true)
            }
        }
    }

    @Test func failedAsyncCommitStopsAtOldestAndRetriesBeforeNewRecords() async throws {
        try await withAsyncStore { store in
            try store.add(name: "Desk", address: "127.0.0.1")
            store.preferences.bestShareNotificationsEnabled = true
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            detect([a, b], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            var declined: [UUID] = []
            await FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { event in
                declined.append(event.id)
                return false
            }.value
            #expect(declined == [a.id])
            #expect(entry(for: a, in: store)?.inAppAcceptancePending == true)
            #expect(entry(for: a, in: store)?.inAppDelivered == false)
            #expect(entry(for: b, in: store)?.inAppDelivered == false)
            let c = recordEvent(device, "4M", order: 2)
            detect([c], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            let queue = FleetCelebrationQueueController(isTesting: true, arguments: [])
            var committed: [UUID] = []
            await FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { event in
                guard let record = FleetCelebration(event) else { return false }
                #expect(entry(for: event, in: store)?.inAppDelivered == false)
                let result = await queue.submit(.present(record, sessionEnabled: true)).value
                #expect(result.accepted)
                #expect(entry(for: event, in: store)?.inAppDelivered == false,
                        "The journal must still be pending until the commit callback returns")
                committed.append(event.id)
                return result.accepted
            }.value
            #expect(committed == [a.id, b.id, c.id])
            #expect(queue.unacknowledgedCount == 3 && queue.current?.id == a.id)
            for event in [a, b, c] { #expect(entry(for: event, in: store)?.inAppDelivered == true) }
            _ = await queue.submit(.close).value
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postBestShare: { _ in Issue.record("An accepted foreground record was pushed again") })
        }
    }

    @Test func asyncCommitRechecksOptOutAndRemovedDevicesAfterSuspension() async throws {
        try await withAsyncStore { store in
            try store.add(name: "Desk", address: "127.0.0.1")
            store.preferences.bestShareNotificationsEnabled = true
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            detect([a, b], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            var offered: [UUID] = []
            await FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { event in
                offered.append(event.id)
                await Task.yield()
                store.preferences.bestShareNotificationsEnabled = false
                return true
            }.value
            #expect(offered == [a.id])
            #expect(entry(for: b, in: store)?.inAppAcceptancePending != true)
            store.preferences.bestShareNotificationsEnabled = true
            let c = recordEvent(device, "4M", order: 2)
            detect([c], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            store.remove(device)
            await FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { _ in
                Issue.record("Removed miner reached durable acceptance")
                return true
            }.value
            #expect(entry(for: c, in: store)?.inAppAcceptancePending != true)
        }
    }
}
