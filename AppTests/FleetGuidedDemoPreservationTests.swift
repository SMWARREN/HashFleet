import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@MainActor
struct FleetGuidedDemoPreservationTests {
    @Test func savedMinersAndEveryStoredSettingSurviveDemoEditsAndColdReload() async throws {
        let name = "guided-preservation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let real = FleetStore(defaults: defaults)
        try real.add(name: "My first miner", address: "http://192.0.2.11")
        try real.add(name: "My second miner", address: "http://192.0.2.12")
        real.preferences.appearance = .dark
        real.preferences.dashboardCoins = [.btc, .dgb]
        real.preferences.sort = .temperature
        real.preferences.ascending = false
        real.preferences.compactCards = true
        real.preferences.externalDataEnabled = false
        real.preferences.realtimeMonitoring = false
        real.preferences.blockNotificationsEnabled = true
        real.preferences.bestShareNotificationsEnabled = true
        defaults.set("private-existing-setting", forKey: "app.hashfleet.preservationProbe")
        let savedIDs = real.devices.map(\.id)
        let original = defaults.persistentDomain(forName: name) ?? [:]

        let sample = FleetGuidedDemoSandbox()
        await sample.prepare()
        sample.store.preferences.appearance = .light
        sample.store.preferences.dashboardCoins = [.bch]
        sample.store.preferences.blockNotificationsEnabled = false
        sample.store.preferences.bestShareNotificationsEnabled = false
        if let device = sample.store.devices.first { sample.store.remove(device) }
        // A cold real-store reload is safe even before sandbox cleanup, as after force quit.
        let interruptedReload = FleetStore(defaults: defaults)
        #expect(interruptedReload.devices.map(\.id) == savedIDs)
        #expect(NSDictionary(dictionary: original).isEqual(to: defaults.persistentDomain(forName: name) ?? [:]))
        sample.cleanup()
        let completedReload = FleetStore(defaults: defaults)
        #expect(completedReload.devices.map(\.id) == savedIDs)
        #expect(completedReload.devices.map(\.name) == ["My first miner", "My second miner"])
        #expect(completedReload.preferences.dashboardCoins == [.btc, .dgb])
        #expect(completedReload.preferences.appearance == .dark)
        #expect(completedReload.preferences.blockNotificationsEnabled)
        #expect(completedReload.preferences.bestShareNotificationsEnabled)
        #expect(NSDictionary(dictionary: original).isEqual(to: defaults.persistentDomain(forName: name) ?? [:]))
    }

    @Test func noSavedFleetStaysEmptyAndDoesNotPersistSampleMiners() async throws {
        let name = "guided-empty-preservation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let real = FleetStore(defaults: defaults)
        real.preferences.compactCards = true
        let original = defaults.persistentDomain(forName: name) ?? [:]
        let sample = FleetGuidedDemoSandbox()
        await sample.prepare()
        #expect(!sample.store.devices.isEmpty)
        sample.cleanup()
        let restored = FleetStore(defaults: defaults)
        #expect(restored.devices.isEmpty)
        #expect(restored.preferences.compactCards)
        #expect(defaults.data(forKey: FleetStore.storageKey) == nil)
        #expect(NSDictionary(dictionary: original).isEqual(to: defaults.persistentDomain(forName: name) ?? [:]))
    }
}
