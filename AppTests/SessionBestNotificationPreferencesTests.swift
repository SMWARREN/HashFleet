import Foundation
import Testing
@testable import HashFleet

@Suite(.serialized) @MainActor
struct SessionBestNotificationPreferencesTests {
    @Test func freshDefaultsAndLegacyOptOutPersistAcrossReload() throws {
        let suite = "app.hashfleet.session-best.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let fresh = FleetPreferences(defaults: defaults)
        #expect(fresh.bestShareNotificationsEnabled)
        #expect(fresh.sessionBestNotificationsEnabled)
        fresh.bestShareNotificationsEnabled = false
        fresh.sessionBestNotificationsEnabled = false
        fresh.bestShareNotificationsEnabled = true

        let relaunched = FleetPreferences(defaults: defaults)
        #expect(relaunched.bestShareNotificationsEnabled)
        #expect(!relaunched.sessionBestNotificationsEnabled)

        defaults.set(false, forKey: FleetPreferences.Keys.bestShareNotificationsEnabled)
        #expect(!FleetPreferences(defaults: defaults).bestShareNotificationsEnabled)
    }

    @Test func activityContentModePersistsWithoutChangingNotificationDefaults() throws {
        let suite = "app.hashfleet.session-best.mode-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FleetPreferences(defaults: defaults)
        #expect(preferences.activityContentMode == .notifications)
        preferences.activityContentMode = .both
        #expect(FleetPreferences(defaults: defaults).activityContentMode == .both)
        #expect(!preferences.blockNotificationsEnabled)
        #expect(!preferences.stateChangeNotificationsEnabled)
        #expect(!preferences.metricAlertNotificationsEnabled)
        #expect(!preferences.powerAlertNotificationsEnabled)
    }
}
