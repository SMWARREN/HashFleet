import Foundation
import Testing
@testable import HashFleetMac

@Suite("Native demo preference isolation", .serialized)
struct FleetDemoIsolationTests {
    @MainActor
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "app.hashfleet.mac.demo-isolation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @MainActor
    @Test func demoRoundTripRestoresPresentAndAbsentNotificationAndMenuKeys() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: FleetPreferences.Keys.sessionBestNotificationsEnabled)
        #expect(defaults.object(forKey: FleetPreferences.Keys.realtimeMonitoring) == nil)
        #expect(defaults.object(forKey: FleetMenuBarPreferenceStorage.key) == nil)
        #expect(defaults.object(forKey: FleetMenuBarPreferenceStorage.contentKey) == nil)

        let store = FleetStore(defaults: defaults)
        store.loadDemo()
        store.preferences.sessionBestNotificationsEnabled = false
        store.preferences.realtimeMonitoring = false
        #expect(store.menuBarPreferenceStorage.save(.hidden))
        #expect(store.menuBarPreferenceStorage.saveContentMode(.both))

        store.clearDemo()

        #expect(defaults.object(forKey: FleetPreferences.Keys.sessionBestNotificationsEnabled) as? Bool == true)
        #expect(defaults.object(forKey: FleetPreferences.Keys.realtimeMonitoring) == nil)
        #expect(defaults.object(forKey: FleetMenuBarPreferenceStorage.key) == nil)
        #expect(defaults.object(forKey: FleetMenuBarPreferenceStorage.contentKey) == nil)
        #expect(store.preferences.sessionBestNotificationsEnabled)
        #expect(!store.isDemo)
    }

    @MainActor
    @Test func demoCheckpointRestoresPresentMenuAndNotificationValues() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(false, forKey: FleetPreferences.Keys.sessionBestNotificationsEnabled)
        defaults.set("always", forKey: FleetMenuBarPreferenceStorage.key)
        defaults.set(FleetActivityContentMode.sessionBest.rawValue,
                     forKey: FleetMenuBarPreferenceStorage.contentKey)
        let store = FleetStore(defaults: defaults)
        store.loadDemo()
        store.preferences.sessionBestNotificationsEnabled = true
        #expect(store.menuBarPreferenceStorage.save(.hidden))
        #expect(store.menuBarPreferenceStorage.saveContentMode(.both))
        let demoOnlyTemperatureKey = FleetTemperatureAlertPreferences.keyPrefix + UUID().uuidString
        defaults.set(true, forKey: demoOnlyTemperatureKey)

        // A new store models process relaunch while the demo checkpoint is pending.
        let recoveredStore = FleetStore(defaults: defaults)
        #expect(defaults.object(forKey: FleetPreferences.Keys.sessionBestNotificationsEnabled) as? Bool == false)
        #expect(defaults.string(forKey: FleetMenuBarPreferenceStorage.key) == "always")
        #expect(defaults.string(forKey: FleetMenuBarPreferenceStorage.contentKey)
                == FleetActivityContentMode.sessionBest.rawValue)
        #expect(defaults.object(forKey: FleetStore.preferenceCheckpointKey) == nil)
        #expect(defaults.object(forKey: demoOnlyTemperatureKey) == nil)
        #expect(!recoveredStore.preferences.sessionBestNotificationsEnabled)
    }

    @MainActor
    @Test func storeMenuPreferenceStorageUsesInjectedDefaultsDomain() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let standardValueBefore = UserDefaults.standard.string(forKey: FleetMenuBarPreferenceStorage.key)

        let store = FleetStore(defaults: defaults)
        #expect(store.menuBarPreferenceStorage.save(.hidden))
        #expect(store.menuBarPreferenceStorage.saveContentMode(.both))
        #expect(defaults.string(forKey: FleetMenuBarPreferenceStorage.key) == "hidden")
        #expect(defaults.string(forKey: FleetMenuBarPreferenceStorage.contentKey) == "both")
        #expect(UserDefaults.standard.string(forKey: FleetMenuBarPreferenceStorage.key) == standardValueBefore)
    }
}
