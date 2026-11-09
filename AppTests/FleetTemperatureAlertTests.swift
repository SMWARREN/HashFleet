import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Temperature alert preferences and settings") @MainActor
struct FleetTemperatureAlertTests {
    @MainActor private final class Fixture {
        let suite = "app.hashfleet.temperature-alert.tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let preferences: FleetTemperatureAlertPreferences
        let device = MinerDevice(name: "Thermal fixture", address: "fixture.invalid")
        let epoch = Date(timeIntervalSince1970: 1_800_000_000)

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            preferences = FleetTemperatureAlertPreferences(defaults: defaults)
        }

        func cleanup() { defaults.removePersistentDomain(forName: suite) }

        func enable(_ device: MinerDevice? = nil, threshold: Double = 75) throws {
            try preferences.setPolicy(
                MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: threshold),
                for: (device ?? self.device).id
            )
        }

        func sample(
            _ value: JSONValue?, at seconds: TimeInterval = 0,
            store: FleetTemperatureAlertPreferences? = nil, device: MinerDevice? = nil,
            online: Bool = true, cached: Bool = false, age: TimeInterval = 0
        ) -> MinerTemperatureAlertEvent? {
            let info = MinerInfo(raw: value.map { ["temp": $0] } ?? [:])
            let date = epoch.addingTimeInterval(seconds)
            return (store ?? preferences).observe(
                device: device ?? self.device, info: info, observedAt: date,
                isOnline: online, isCached: cached, now: date.addingTimeInterval(age)
            )
        }
    }

    @Test func defaultOffAndSettingsRoundTripPerMiner() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let other = MinerDevice(name: "Other fixture", address: "other.invalid")
        #expect(!fixture.preferences.policy(for: fixture.device.id).isEnabled)
        #expect(fixture.sample(.number(99)) == nil)
        try fixture.enable(threshold: 82.5)
        let restored = FleetTemperatureAlertPreferences(defaults: fixture.defaults)
        #expect(restored.policy(for: fixture.device.id).thresholdCelsius == 82.5)
        #expect(restored.policy(for: fixture.device.id).isEnabled)
        #expect(!restored.policy(for: other.id).isEnabled)
    }

    @Test func freshStorePreservesHotLatchAndCooldownAfterRecovery() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.enable()
        #expect(fixture.sample(.number(80)) != nil)
        var restored = FleetTemperatureAlertPreferences(defaults: fixture.defaults)
        #expect(fixture.sample(.number(90), at: 100, store: restored) == nil)
        #expect(fixture.sample(.number(70), at: 101, store: restored) == nil)
        restored = FleetTemperatureAlertPreferences(defaults: fixture.defaults)
        #expect(fixture.sample(.number(90), at: 1799, store: restored) == nil)
        #expect(fixture.sample(.number(90), at: 1800, store: restored) != nil)
        restored = FleetTemperatureAlertPreferences(defaults: fixture.defaults)
        #expect(fixture.sample(.number(90), at: 20_000, store: restored) == nil)
    }

    @Test func perMinerPoliciesAndSuppressionRemainIndependent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let other = MinerDevice(name: "Other fixture", address: "other.invalid")
        try fixture.enable()
        try fixture.enable(other, threshold: 85)
        #expect(fixture.sample(.number(80)) != nil)
        #expect(fixture.sample(.number(80), device: other) == nil)
        #expect(fixture.sample(.number(90), at: 1, device: other)?.deviceID == other.id)
        #expect(fixture.sample(.number(90), at: 1) == nil)
    }

    @Test func twoLiveStoresShareLatestPolicyAndSuppressionState() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let background = FleetTemperatureAlertPreferences(defaults: fixture.defaults)
        try fixture.enable()
        #expect(background.policy(for: fixture.device.id).isEnabled)
        #expect(fixture.sample(.number(90), store: background) != nil)
        #expect(fixture.sample(.number(90), at: 1) == nil)
        // An edit in the surviving foreground store must not overwrite the BG cooldown.
        try fixture.preferences.setPolicy(
            MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: 80), for: fixture.device.id)
        #expect(background.policy(for: fixture.device.id).thresholdCelsius == 80)
        #expect(fixture.sample(.number(90), at: 2, store: background) == nil)
        background.remove(deviceID: fixture.device.id)
        #expect(!fixture.preferences.policy(for: fixture.device.id).isEnabled)
        #expect(fixture.sample(.number(90), at: 2000) == nil)
    }

    @Test func missingInvalidAndUntrustedReadingsDoNotPersistOrRearm() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.enable()
        #expect(fixture.sample(.number(80)) != nil)
        let key = FleetTemperatureAlertPreferences.keyPrefix + fixture.device.id.uuidString
        let before = fixture.defaults.data(forKey: key)
        for value in [nil, JSONValue.null, .bool(true), .string("not a number"), .number(.nan), .number(0)] {
            #expect(fixture.sample(value, at: 1) == nil)
        }
        #expect(fixture.sample(.number(60), at: 2, online: false) == nil)
        #expect(fixture.sample(.number(60), at: 3, cached: true) == nil)
        #expect(fixture.sample(.number(60), at: 4, age: 121) == nil)
        #expect(fixture.defaults.data(forKey: key) == before)
        #expect(fixture.sample(.number(90), at: 2000) == nil)
    }

    @Test func corruptionFailsClosedPerMinerAndPreservesOriginalBytes() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.enable()
        let badID = UUID()
        let key = FleetTemperatureAlertPreferences.keyPrefix + badID.uuidString
        let original = Data("{broken".utf8)
        fixture.defaults.set(original, forKey: key)
        let restored = FleetTemperatureAlertPreferences(defaults: fixture.defaults)
        #expect(!restored.policy(for: badID).isEnabled)
        #expect(restored.policy(for: fixture.device.id).isEnabled)
        #expect(restored.persistenceError != nil)
        #expect(fixture.defaults.data(forKey: key) == original)
        try restored.setPolicy(MinerTemperatureAlertPolicy(), for: badID)
        #expect(fixture.defaults.data(forKey: key) != original)
        #expect(restored.persistenceError == nil)
    }

    @Test func removalIsScopedAndDoesNotChangeOtherPreferences() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.defaults.set("untouched", forKey: "unrelated.fixture")
        let other = MinerDevice(name: "Other fixture", address: "other.invalid")
        try fixture.enable()
        try fixture.enable(other)
        fixture.preferences.remove(deviceID: fixture.device.id)
        #expect(!fixture.preferences.policy(for: fixture.device.id).isEnabled)
        #expect(fixture.preferences.policy(for: other.id).isEnabled)
        fixture.preferences.removeAll()
        #expect(!FleetTemperatureAlertPreferences(defaults: fixture.defaults).policy(for: other.id).isEnabled)
        #expect(fixture.defaults.string(forKey: "unrelated.fixture") == "untouched")
    }

    @Test func draftRequiresSaveAndAuthorizationWithoutChangingOtherAlertFlags() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let otherPreferences = FleetPreferences(defaults: fixture.defaults)
        otherPreferences.bestShareNotificationsEnabled = true
        var requests = 0
        let model = MinerTemperatureAlertSettingsModel(deviceID: fixture.device.id, preferences: fixture.preferences) {
            requests += 1
            return true
        }
        model.isEnabled = true
        model.thresholdText = "82,5"
        #expect(!fixture.preferences.policy(for: fixture.device.id).isEnabled)
        await model.save()
        #expect(requests == 1)
        #expect(fixture.preferences.policy(for: fixture.device.id).thresholdCelsius == 82.5)
        #expect(fixture.preferences.policy(for: fixture.device.id).isEnabled)
        #expect(model.savedMessage != nil)
        #expect(!model.hasChanges)
        let restoredOther = FleetPreferences(defaults: fixture.defaults)
        #expect(restoredOther.bestShareNotificationsEnabled)
        #expect(!restoredOther.blockNotificationsEnabled)
        model.thresholdText = "83"
        #expect(model.savedMessage == nil)
        #expect(model.hasChanges)
        #expect(fixture.preferences.policy(for: fixture.device.id).thresholdCelsius == 82.5)
    }

    @Test func deniedPermissionLeavesSavedPolicyUntouched() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let model = MinerTemperatureAlertSettingsModel(deviceID: fixture.device.id, preferences: fixture.preferences) { false }
        model.isEnabled = true
        await model.save()
        #expect(!fixture.preferences.policy(for: fixture.device.id).isEnabled)
        #expect(model.error?.contains("unchanged") == true)
        #expect(model.savedMessage == nil)
    }

    @Test func disablingDoesNotAskForPermissionAndPreservesCooldown() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.enable()
        #expect(fixture.sample(.number(90)) != nil)
        var requests = 0
        let model = MinerTemperatureAlertSettingsModel(deviceID: fixture.device.id, preferences: fixture.preferences) {
            requests += 1
            return false
        }
        model.isEnabled = false
        await model.save()
        #expect(requests == 0)
        #expect(!fixture.preferences.policy(for: fixture.device.id).isEnabled)
        try fixture.enable()
        #expect(fixture.sample(.number(90), at: 1) == nil)
    }

    @Test(arguments: ["", "NaN", "inf", "-1", "29.99", "110.01", "75 °C", "1,234.5"])
    func invalidDraftCannotSaveOrRequestAuthorization(text: String) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var requests = 0
        let model = MinerTemperatureAlertSettingsModel(deviceID: fixture.device.id, preferences: fixture.preferences) {
            requests += 1
            return true
        }
        model.isEnabled = true
        model.thresholdText = text
        await model.save()
        #expect(model.proposedPolicy == nil)
        #expect(model.error != nil)
        #expect(requests == 0)
        #expect(!fixture.preferences.policy(for: fixture.device.id).isEnabled)
    }

    @Test func payloadIsTemperatureEvidenceNotHardwareActionOrBlockClaim() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.enable()
        let event = try #require(fixture.sample(.number(90)))
        let content = FleetTemperatureAlertNotificationContent(event: event)
        #expect(content.identifier == "app.hashfleet.temperature-alert.\(event.deviceID.uuidString)")
        #expect(content.title.contains(fixture.device.name))
        #expect(content.body.contains("90 °C"))
        #expect(content.body.contains("75 °C"))
        #expect(content.body.contains("No hardware settings were changed"))
        #expect(!content.body.lowercased().contains("block"))
    }
}
