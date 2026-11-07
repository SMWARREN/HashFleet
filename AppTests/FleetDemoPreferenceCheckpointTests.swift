import XCTest
import HashFleetCore
@testable import HashFleet

@MainActor
final class FleetDemoPreferenceCheckpointTests: XCTestCase {

    func testLoadDemoClearDemoPreservesRealPreferences() throws {
        let defaults = UserDefaults(suiteName: "test.demo.prefs.v1")!
        defaults.removePersistentDomain(forName: "test.demo.prefs.v1")
        let store = FleetStore(defaults: defaults)

        // Set some real preferences
        store.preferences.appearance = .dark
        store.preferences.sort = .hashrate
        store.preferences.ascending = false
        store.preferences.compactCards = true
        store.preferences.hasSeenFeatureTour = true

        // Enter demo mode
        store.loadDemo()

        // Mutate preferences in demo mode
        store.preferences.appearance = .light
        store.preferences.sort = .name
        store.preferences.ascending = true
        store.preferences.compactCards = false
        store.preferences.hasSeenFeatureTour = false

        // Exit demo mode
        store.clearDemo()

        // Verify real preferences were restored
        XCTAssertEqual(store.preferences.appearance, .dark)
        XCTAssertEqual(store.preferences.sort, .hashrate)
        XCTAssertEqual(store.preferences.ascending, false)
        XCTAssertEqual(store.preferences.compactCards, true)
        XCTAssertEqual(store.preferences.hasSeenFeatureTour, true)
    }

    func testMidDemoRelaunchRestoresPreferencesOnInit() throws {
        let suiteName = "test.demo.relaunch.v1"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // First session: set preferences and enter demo
        do {
            let store = FleetStore(defaults: defaults)
            store.preferences.appearance = .dark
            store.preferences.sort = .power
            store.preferences.blockNotificationsEnabled = true

            store.loadDemo()

            // Mutate preferences during demo
            store.preferences.appearance = .light
            store.preferences.sort = .name
            store.preferences.blockNotificationsEnabled = false

            // Checkpoint should exist now
            XCTAssertNotNil(defaults.data(forKey: FleetStore.preferenceCheckpointKey))
        }

        // Simulate app relaunch mid-demo (new FleetStore instance)
        do {
            let store2 = FleetStore(defaults: defaults)

            // Preferences should be restored from checkpoint
            XCTAssertEqual(store2.preferences.appearance, .dark)
            XCTAssertEqual(store2.preferences.sort, .power)
            XCTAssertEqual(store2.preferences.blockNotificationsEnabled, true)

            // Checkpoint should be cleared after restoration
            XCTAssertNil(defaults.data(forKey: FleetStore.preferenceCheckpointKey))
        }
    }

    func testCheckpointDoesNotAffectDeviceFleet() throws {
        let defaults = UserDefaults(suiteName: "test.demo.devices.v1")!
        defaults.removePersistentDomain(forName: "test.demo.devices.v1")
        let store = FleetStore(defaults: defaults)

        // Add a real device
        let device = MinerDevice(name: "Test Miner", address: "192.168.1.100")
        store.devices = [device]
        store.persist()

        // Verify device is persisted
        let savedData = defaults.data(forKey: FleetStore.storageKey)
        XCTAssertNotNil(savedData)

        // Enter demo mode
        store.loadDemo()

        // Demo should have demo devices
        XCTAssertEqual(store.devices.count, 3) // DemoFleet.devices has 3
        XCTAssertTrue(store.isDemo)

        // Device storage key should be unchanged
        XCTAssertEqual(defaults.data(forKey: FleetStore.storageKey), savedData)

        // Exit demo
        store.clearDemo()

        // Real device should be restored
        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.devices.first?.name, "Test Miner")
        XCTAssertEqual(store.devices.first?.address, "192.168.1.100")

        // Device storage key should still be unchanged
        XCTAssertEqual(defaults.data(forKey: FleetStore.storageKey), savedData)
    }

    func testCheckpointIncludesTemperatureAlertPreferences() throws {
        let defaults = UserDefaults(suiteName: "test.demo.temp.v1")!
        defaults.removePersistentDomain(forName: "test.demo.temp.v1")
        let store = FleetStore(defaults: defaults)

        // Set temperature alert preference for a device
        let deviceID = UUID()
        let policy = try MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: 75)
        try store.temperatureAlerts.setPolicy(policy, for: deviceID)

        // Enter demo mode
        store.loadDemo()

        // Mutate temperature alert during demo
        let demoPolicy = try MinerTemperatureAlertPolicy(isEnabled: false, thresholdCelsius: 60)
        try store.temperatureAlerts.setPolicy(demoPolicy, for: deviceID)

        // Exit demo mode
        store.clearDemo()

        // Verify original temperature alert was restored
        let restored = store.temperatureAlerts.policy(for: deviceID)
        XCTAssertEqual(restored.isEnabled, true)
        XCTAssertEqual(restored.thresholdCelsius, 75)
    }

    func testClearDemoWithoutLoadDemoIsNoOp() throws {
        let defaults = UserDefaults(suiteName: "test.demo.noop.v1")!
        defaults.removePersistentDomain(forName: "test.demo.noop.v1")
        let store = FleetStore(defaults: defaults)

        store.preferences.appearance = .dark

        // Clear demo without ever loading it
        store.clearDemo()

        // Preferences should be unchanged
        XCTAssertEqual(store.preferences.appearance, .dark)
        XCTAssertFalse(store.isDemo)
    }
}
