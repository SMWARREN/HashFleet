import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Power-alert coverage mirrors FleetNotificationDeliveryTests and the temperature-alert
/// acceptance tests: the same drain-once, opt-in, removed-miner and retained-reading rules
/// apply, plus the power-specific trigger and resolution notifications.
@Suite("Power alert detection and delivery")
@MainActor
struct FleetPowerAlertTests {
    private func withStore(_ body: (FleetStore) throws -> Void) rethrows {
        let suite = "app.hashfleet.power-alert-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(FleetStore(defaults: defaults))
    }

    private func enable(_ store: FleetStore, thresholdWatts: Double = 120) throws -> MinerDevice {
        try store.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(store.devices.first)
        try store.powerAlerts.setPolicy(
            MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: thresholdWatts), for: device.id)
        return device
    }

    @Test func policyRejectsOutOfRangeThresholds() {
        #expect(throws: MinerPowerAlertPolicy.ValidationError.invalidThreshold) {
            _ = try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 0)
        }
        #expect(throws: MinerPowerAlertPolicy.ValidationError.invalidThreshold) {
            _ = try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: .infinity)
        }
        #expect(throws: Never.self) {
            _ = try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 100)
        }
        #expect(MinerPowerAlertPolicy().isEnabled == false)
    }

    @Test func freshHighReadingQueuesAnAlarm() throws {
        try withStore { store in
            let device = try enable(store)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: .now)
            #expect(store.pendingPowerAlertEvents.count == 1)
            #expect(store.pendingPowerAlertEvents.first?.kind == .exceeded)
            #expect(store.pendingPowerAlertEvents.first?.watts == 150)
            #expect(store.pendingPowerAlertEvents.first?.thresholdWatts == 120)
        }
    }

    @Test func belowThresholdReadingNeverAlerts() throws {
        try withStore { store in
            let device = try enable(store)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(100)]), for: device.id, at: .now)
            #expect(store.pendingPowerAlertEvents.isEmpty)
        }
    }

    @Test func disabledPolicyNeverQueuesAnEvent() throws {
        try withStore { store in
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(400)]), for: device.id, at: .now)
            #expect(store.pendingPowerAlertEvents.isEmpty)
        }
    }

    @Test func readingAtThresholdAlertsOncePerEpisode() throws {
        try withStore { store in
            let device = try enable(store)
            let first = Date.now.addingTimeInterval(-10)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(120)]), for: device.id, at: first)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(130)]), for: device.id, at: .now)
            #expect(store.pendingPowerAlertEvents.count == 1)
        }
    }

    @Test func returnToNormalPostsAResolution() throws {
        try withStore { store in
            let device = try enable(store)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: .now)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(100)]), for: device.id, at: .now)
            #expect(store.pendingPowerAlertEvents.map(\.kind) == [.exceeded, .resolved])
        }
    }

    @Test func hysteresisBandDoesNotResolveEarly() throws {
        try withStore { store in
            let device = try enable(store)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: .now)
            // 118 W is inside the 5 W hysteresis below the 120 W threshold: still alarming.
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(118)]), for: device.id, at: .now)
            #expect(store.pendingPowerAlertEvents.map(\.kind) == [.exceeded])
        }
    }

    @Test func retainedPowerInPartialUpdateDoesNotFabricateAnAlarm() throws {
        try withStore { store in
            let device = try enable(store)
            store.recordSuccessfulInfo(
                MinerInfo(raw: ["power": .number(150), "hashRate": .number(1200)]),
                for: device.id, at: .now, hasFreshPower: false)
            #expect(store.pendingPowerAlertEvents.isEmpty)
            #expect(store.applyLiveMessage(.text(#"{"data":{"hashRate":1250}}"#), for: device.id))
            #expect(store.pendingPowerAlertEvents.isEmpty)
            #expect(store.applyLiveMessage(.text(#"{"data":{"power":150}}"#), for: device.id))
            #expect(store.pendingPowerAlertEvents.count == 1)
        }
    }

    @Test func inactiveDeliveryPostsAlarmOncePerEnabledPolicy() throws {
        try withStore { store in
            store.preferences.powerAlertNotificationsEnabled = true
            let device = try enable(store)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: .now)
            var posted: [MinerPowerAlertEvent] = []
            for _ in 0..<2 {
                FleetNotificationDelivery.consume(from: store, isActive: false, postPower: { posted.append($0) })
            }
            #expect(posted.count == 1)
            #expect(posted.first?.kind == .exceeded)
            #expect(store.pendingPowerAlertEvents.isEmpty)
        }
    }

    @Test func activeDeliveryStillPostsAlarmAndResolution() throws {
        try withStore { store in
            store.preferences.powerAlertNotificationsEnabled = true
            let device = try enable(store)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: .now)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(100)]), for: device.id, at: .now)
            var posted: [MinerPowerAlertEvent.Kind] = []
            FleetNotificationDelivery.consume(from: store, isActive: true,
                postPower: { _ in Issue.record("Pushed while the app was open") },
                presentInApp: { if case .power(let power) = $0 { posted.append(power.kind) } })
            #expect(posted == [.exceeded, .resolved])
        }
    }

    @Test func fleetToggleOffSuppressesDeliveryButStillDrains() throws {
        try withStore { store in
            let device = try enable(store)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: .now)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postPower: { _ in Issue.record("Alarm posted while fleet toggle off") })
            #expect(store.pendingPowerAlertEvents.isEmpty)
        }
    }

    @Test func optingOutAfterDetectionSuppressesPendingDelivery() throws {
        try withStore { store in
            store.preferences.powerAlertNotificationsEnabled = true
            let device = try enable(store)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: .now)
            try store.powerAlerts.setPolicy(MinerPowerAlertPolicy(), for: device.id)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postPower: { _ in Issue.record("Opted-out alarm posted") })
            #expect(store.pendingPowerAlertEvents.isEmpty)
        }
    }

    @Test func removedMinerEventsAreDiscarded() throws {
        try withStore { store in
            store.preferences.powerAlertNotificationsEnabled = true
            let device = try enable(store)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: .now)
            store.remove(device)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postPower: { _ in Issue.record("Removed miner alarm posted") })
            #expect(store.powerAlerts.policy(for: device.id).isEnabled == false)
        }
    }

    @Test func demoModeNeverQueuesOrPostsPowerAlerts() throws {
        try withStore { store in
            store.preferences.powerAlertNotificationsEnabled = true
            let device = try enable(store)
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: .now)
            store.loadDemo()
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(400)]), for: device.id, at: .now)
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postPower: { _ in Issue.record("Demo alarm posted") })
            #expect(store.pendingPowerAlertEvents.isEmpty)
        }
    }

    @Test func staleOrRepeatedReadingsNeverRealert() throws {
        try withStore { store in
            let device = try enable(store)
            let time = Date.now
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: time)
            #expect(store.pendingPowerAlertEvents.count == 1)
            _ = store.drainPendingNotificationEvents()
            // An older or duplicate observation of the same threshold crossing never re-alerts.
            store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(150)]), for: device.id, at: time)
            #expect(store.pendingPowerAlertEvents.isEmpty)
        }
    }

    @Test func notificationContentDescribesBothDirections() {
        let deviceID = UUID()
        let alarm = MinerPowerAlertEvent(
            deviceID: deviceID, minerName: "Desk", kind: .exceeded,
            watts: 150, thresholdWatts: 120, occurredAt: .now)
        let alarmCopy = FleetPowerAlertNotificationContent(event: alarm)
        #expect(alarmCopy.title.contains("Desk"))
        #expect(alarmCopy.body.contains("120"))
        let clear = MinerPowerAlertEvent(
            deviceID: deviceID, minerName: "Desk", kind: .resolved,
            watts: 100, thresholdWatts: 120, occurredAt: .now)
        let clearCopy = FleetPowerAlertNotificationContent(event: clear)
        #expect(clearCopy.title != alarmCopy.title)
        // The resolution replaces the alarm in Notification Center instead of leaving both.
        #expect(clearCopy.identifier == alarmCopy.identifier)
    }

    @Test func policyPersistenceSurvivesAReloadedPreferencesStore() throws {
        let suite = "app.hashfleet.power-alert-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let deviceID = UUID()
        let expected = try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 220)
        let first = FleetPowerAlertPreferences(defaults: defaults)
        try first.setPolicy(expected, for: deviceID)
        let second = FleetPowerAlertPreferences(defaults: defaults)
        let restored = second.policy(for: deviceID)
        #expect(restored == expected)
    }

    @Test func modelDraftRequiresSaveAndAuthorizationWithoutChangingOtherAlertFlags() async throws {
        let suite = "app.hashfleet.power-alert-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FleetPowerAlertPreferences(defaults: defaults)
        let otherPreferences = FleetPreferences(defaults: defaults)
        otherPreferences.blockNotificationsEnabled = true
        // Saving a power policy must preserve a deliberately saved best-share opt-out.
        otherPreferences.bestShareNotificationsEnabled = false
        let deviceID = UUID()

        var authRequests = 0
        let model = MinerPowerAlertSettingsModel(
            deviceID: deviceID,
            preferences: preferences,
            requestAuthorization: {
                authRequests += 1
                return true
            }
        )

        #expect(!model.isEnabled)
        #expect(!model.hasChanges)
        model.isEnabled = true
        model.thresholdText = "125,5"
        #expect(model.hasChanges)
        #expect(!preferences.policy(for: deviceID).isEnabled)

        await model.save()

        #expect(authRequests == 1)
        #expect(preferences.policy(for: deviceID).isEnabled)
        #expect(preferences.policy(for: deviceID).thresholdWatts == 125.5)
        #expect(!model.hasChanges)
        #expect(model.savedMessage == "Power alert settings saved.")
        #expect(model.error == nil)

        let restoredOther = FleetPreferences(defaults: defaults)
        #expect(restoredOther.blockNotificationsEnabled)
        #expect(!restoredOther.bestShareNotificationsEnabled)

        model.thresholdText = "130"
        #expect(model.savedMessage == nil)
        #expect(model.hasChanges)
    }

    @Test func modelDeniedPermissionLeavesSavedPolicyUntouched() async throws {
        let suite = "app.hashfleet.power-alert-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FleetPowerAlertPreferences(defaults: defaults)
        let deviceID = UUID()

        var authRequests = 0
        let model = MinerPowerAlertSettingsModel(
            deviceID: deviceID,
            preferences: preferences,
            requestAuthorization: {
                authRequests += 1
                return false
            }
        )

        model.isEnabled = true
        model.thresholdText = "150"
        await model.save()

        #expect(authRequests == 1)
        #expect(!preferences.policy(for: deviceID).isEnabled)
        #expect(model.savedMessage == nil)
        #expect(model.error?.contains("Notification permission was not granted") == true)
    }

    @Test func modelDisablingDoesNotAskForPermission() async throws {
        let suite = "app.hashfleet.power-alert-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FleetPowerAlertPreferences(defaults: defaults)
        let deviceID = UUID()
        try preferences.setPolicy(
            MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 140),
            for: deviceID
        )

        var authRequests = 0
        let model = MinerPowerAlertSettingsModel(
            deviceID: deviceID,
            preferences: preferences,
            requestAuthorization: {
                authRequests += 1
                return false
            }
        )

        #expect(model.isEnabled)
        model.isEnabled = false
        await model.save()

        #expect(authRequests == 0)
        #expect(!preferences.policy(for: deviceID).isEnabled)
        #expect(model.savedMessage == "Power alerts are off for this miner.")
        #expect(model.error == nil)
    }

    @Test(arguments: ["", "NaN", "inf", "-10", "0", "120 W", "abc"])
    func modelInvalidDraftCannotSaveOrRequestAuthorization(text: String) async throws {
        let suite = "app.hashfleet.power-alert-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FleetPowerAlertPreferences(defaults: defaults)
        let deviceID = UUID()

        var authRequests = 0
        let model = MinerPowerAlertSettingsModel(
            deviceID: deviceID,
            preferences: preferences,
            requestAuthorization: {
                authRequests += 1
                return true
            }
        )

        model.isEnabled = true
        model.thresholdText = text
        await model.save()

        #expect(model.proposedPolicy == nil)
        #expect(model.error != nil)
        #expect(authRequests == 0)
        #expect(!preferences.policy(for: deviceID).isEnabled)
    }
}
