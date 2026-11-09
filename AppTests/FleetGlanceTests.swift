import ActivityKit
import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Tests use private disposable defaults suites, never the application's App Group.
@MainActor
struct FleetGlanceTests {
    @Test func menuSnapshotPublishesMissingPowerWithoutFabricatingATotal() throws {
        let suite = "app.hashfleet.menu-release.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = MinerDevice(name: "No watt sensor", address: "fixture.invalid")
        let store = FleetStore(defaults: defaults)
        store.devices = [device]
        store.snapshots[device.id] = MinerSnapshot(info: MinerInfo(raw: ["hashRate": .integer(0)]), updatedAt: timestamp)
        store.lastRefresh = timestamp
        #expect(!store.canPublishGlance && store.glance == .empty)
        #expect(store.canPublishMenuBar)
        let snapshot = store.menuBarSnapshot
        #expect(snapshot.glance.minerCount == 1 && snapshot.glance.onlineCount == 1)
        #expect(snapshot.reportedHashrate == 0 && snapshot.reportedPower == nil)
        #expect(snapshot.miners.first?.status == .online)
        #expect(FleetMenuBarFormat.power(snapshot.reportedPower) == "Not reported")
        #expect(FleetMenuBarFormat.power(0) != "Not reported")
        #expect(FleetMenuBarFormat.hashrate(0) != "Not reported")
        let storage = FleetMenuBarSnapshotStorage(defaults: defaults)
        #expect(storage.save(snapshot))
        #expect(storage.load() == snapshot)
        store.snapshots[device.id]?.info = MinerInfo(raw: ["hashRate": .integer(500)])
        store.lastRefresh = timestamp.addingTimeInterval(2)
        #expect(storage.save(store.menuBarSnapshot))
        #expect(storage.load().reportedHashrate == 500)
        #expect(storage.load().reportedPower == nil)
        #expect(GlancePublishingIdentity(phase: .active, glance: .empty, menuBarSnapshot: snapshot)
            != GlancePublishingIdentity(phase: .active, glance: .empty, menuBarSnapshot: store.menuBarSnapshot),
            "A changed per-miner snapshot must retrigger publication even while the strict widget glance stays empty")
    }

    @Test func mixedAlgorithmMenuRowsPublishButRatesNeverCombine() {
        let esp = MinerDevice(name: "ESP", address: "esp.invalid")
        let cpu = MinerDevice(name: "CPU", address: "cpu.invalid", kind: .xmrig)
        let snapshots = [
            esp.id: MinerSnapshot(info: MinerInfo(raw: ["hashRate": .integer(1200), "power": .integer(20)])),
            cpu.id: MinerSnapshot(info: MinerInfo(raw: ["hashRate": .number(0.000002)]))
        ]
        let result = FleetGlanceCoordinator.menuBarSnapshot(
            devices: [esp, cpu], snapshots: snapshots, updatedAt: timestamp, isDemo: false)
        #expect(result.miners.count == 2 && result.glance.onlineCount == 2)
        #expect(result.miners.allSatisfy { $0.status == .online })
        #expect(result.reportedPower == nil && result.reportedHashrate == nil)
    }

    @Test func cachedMenuRowsNeverBecomeGreenLive() {
        let device = MinerDevice(name: "Cached", address: "cached.invalid")
        let info = MinerInfo(raw: ["hashRate": .integer(1200), "power": .integer(20)])
        let snapshot = MinerSnapshot(info: info, updatedAt: timestamp, isCached: true)
        let result = FleetGlanceCoordinator.menuBarSnapshot(
            devices: [device], snapshots: [device.id: snapshot], updatedAt: timestamp, isDemo: false)
        #expect(result.glance.onlineCount == 0)
        #expect(result.miners.first?.status == .offline)
        #expect(result.miners.allSatisfy { !FleetMenuBarFormat.rowIsLive($0, isStale: false) })
    }

    @Test func menuLegacyPayloadRetainsCompleteMetrics() throws {
        let bytes = try JSONSerialization.data(withJSONObject: [
            "glance": try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample())),
            "miners": []
        ])
        let decoded = try JSONDecoder().decode(FleetMenuBarSnapshot.self, from: bytes)
        #expect(decoded.hashrateIsComplete == nil && decoded.powerIsComplete == nil)
        #expect(decoded.reportedHashrate == sample().hashrateGHs && decoded.reportedPower == sample().powerWatts)
    }

    @Test func menuExpiredRowsAndDemoClosedTitlesAreHonest() {
        let miner = FleetMenuBarMinerSummary(id: UUID(), name: "Fixture", status: .online,
            segments: ["1 TH/s"], notices: [], isSimulated: false)
        let glance = sample()
        let expired = glance.isStale(at: timestamp.addingTimeInterval(60))
        #expect(expired)
        #expect(FleetMenuBarFormat.rowStatus(miner, isStale: expired) == "Stale")
        #expect(!FleetMenuBarFormat.rowIsLive(miner, isStale: expired))
        #expect(FleetMenuBarFormat.rowStatus(miner, isStale: false) == "Live")
        #expect(FleetMenuBarFormat.rowIsLive(miner, isStale: false))
        #expect(FleetMenuBarFormat.compactTitle(glance, now: timestamp.addingTimeInterval(60)).contains("!"))
        #expect(FleetMenuBarFormat.accessibilityTitle(glance, now: timestamp.addingTimeInterval(60)).contains("stale"))
        for now in [timestamp, timestamp.addingTimeInterval(120)] {
            #expect(FleetMenuBarFormat.compactTitle(sample(isDemo: true), now: now).contains("DEMO"))
            #expect(FleetMenuBarFormat.accessibilityTitle(sample(isDemo: true), now: now).contains("DEMO sample data"))
        }
    }

    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    func sample(isDemo: Bool = false) -> FleetGlance {
        FleetGlance(
            updatedAt: timestamp,
            onlineCount: 2,
            minerCount: 3,
            hashrateGHs: 2400.5,
            powerWatts: 38.25,
            isDemo: isDemo
        )
    }

    struct GlanceFixture {
        let storage: FleetGlanceStorage
        let defaults: UserDefaults
        let suite: String
    }

    func fixture() throws -> GlanceFixture {
        let suite = "app.hashfleet.glance.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return GlanceFixture(storage: FleetGlanceStorage(defaults: defaults), defaults: defaults, suite: suite)
    }

    /// Discover the key written by the storage implementation rather than reaching
    /// into its private constants or accidentally corrupting production defaults.
    func storedKey(in defaults: UserDefaults, suite: String) throws -> String {
        let domain = try #require(defaults.persistentDomain(forName: suite))
        #expect(domain.count == 1, "Glance storage should persist only its aggregate snapshot")
        return try #require(domain.first(where: { $0.value is Data })?.key)
    }

    @Test(arguments: [false, true])
    func aggregateSnapshotCodableAndHashableRoundTrip(isDemo: Bool) throws {
        let original = sample(isDemo: isDemo)
        let decoded = try JSONDecoder().decode(FleetGlance.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(Set([original, decoded]).count == 1)
        #expect(decoded.updatedAt == timestamp)
        #expect(decoded.onlineCount == 2)
        #expect(decoded.minerCount == 3)
        #expect(decoded.hashrateGHs == 2400.5)
        #expect(decoded.powerWatts == 38.25)
        #expect(decoded.isDemo == isDemo)
    }

    @Test func freshStorageLoadsTheExplicitEmptySnapshot() throws {
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(storage.load() == .empty)
        #expect(FleetGlance.empty.onlineCount == 0)
        #expect(FleetGlance.empty.minerCount == 0)
        #expect(FleetGlance.empty.hashrateGHs == 0)
        #expect(FleetGlance.empty.powerWatts == 0)
        #expect(FleetGlance.empty.isDemo == false)
        #expect(FleetGlance.empty.isStale(at: timestamp))
    }

    @Test(arguments: [false, true])
    func savedAggregateSurvivesASeparateStorageInstance(isDemo: Bool) throws {
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = sample(isDemo: isDemo)
        storage.save(expected)
        #expect(storage.load() == expected)
        let reloadedDefaults = try #require(UserDefaults(suiteName: suite))
        #expect(FleetGlanceStorage(defaults: reloadedDefaults).load() == expected)
    }

    @Test func savingAgainReplacesRatherThanAccumulatesHistory() throws {
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        storage.save(sample())
        let latest = FleetGlance(
            updatedAt: timestamp.addingTimeInterval(30),
            onlineCount: 1,
            minerCount: 4,
            hashrateGHs: 1200,
            powerWatts: 19,
            isDemo: true
        )
        storage.save(latest)
        #expect(storage.load() == latest)
        let key = try storedKey(in: defaults, suite: suite)
        let bytes = try #require(defaults.data(forKey: key))
        #expect(try JSONDecoder().decode(FleetGlance.self, from: bytes) == latest)
    }

    @Test(arguments: [
        "not JSON", "", "{", "null", "[]", "{}",
        #"{"updatedAt":"wrong type","onlineCount":2}"#
    ])
    func corruptOrIncompleteCacheLoadsEmpty(json: String) throws {
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        storage.save(sample())
        let key = try storedKey(in: defaults, suite: suite)
        defaults.set(Data(json.utf8), forKey: key)
        #expect(storage.load() == .empty)
    }

    @Test func wrongDefaultsValueTypeLoadsEmptyAndCanRecover() throws {
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        storage.save(sample())
        let key = try storedKey(in: defaults, suite: suite)
        defaults.set("not encoded Data", forKey: key)
        #expect(storage.load() == .empty)
        storage.save(sample(isDemo: true))
        #expect(storage.load() == sample(isDemo: true))
    }

    @Test func injectedDefaultsSuitesDoNotLeakBetweenFleets() throws {
        let firstEnv = try fixture()
        let first = firstEnv.storage
        let firstDefaults = firstEnv.defaults
        let firstSuite = firstEnv.suite
        let secondEnv = try fixture()
        let second = secondEnv.storage
        let secondDefaults = secondEnv.defaults
        let secondSuite = secondEnv.suite
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        first.save(sample())
        #expect(second.load() == .empty)
        second.save(sample(isDemo: true))
        #expect(first.load() == sample())
        #expect(second.load() == sample(isDemo: true))
    }

    @Test(arguments: [TimeInterval(0), 1, 30, 59, 59.999])
    func snapshotsYoungerThanOneMinuteAreFresh(age: TimeInterval) {
        #expect(sample().isStale(at: timestamp.addingTimeInterval(age)) == false)
    }

    @Test(arguments: [TimeInterval(60), 60.001, 61, 3600, 86_400])
    func snapshotsAtLeastOneMinuteOldAreStale(age: TimeInterval) {
        #expect(sample().isStale(at: timestamp.addingTimeInterval(age)))
    }

    @Test(arguments: [TimeInterval(-0.001), -1, -5])
    func smallFutureClockSkewIsTolerated(age: TimeInterval) {
        #expect(sample().isStale(at: timestamp.addingTimeInterval(age)) == false)
    }

    @Test(arguments: [TimeInterval(-5.001), -6, -60, -3600])
    func futureTimestampsBeyondClockSkewAllowanceAreStale(age: TimeInterval) {
        #expect(sample().isStale(at: timestamp.addingTimeInterval(age)))
    }

    @Test func storagePreservesCaptureTimeRatherThanMakingOldValuesFresh() throws {
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        storage.save(sample())
        let loaded = storage.load()
        #expect(loaded.updatedAt == timestamp)
        #expect(loaded.isStale(at: timestamp.addingTimeInterval(61)))
    }

    @Test(arguments: [false, true])
    func encodedAndPersistedPayloadContainsOnlyApprovedAggregates(isDemo: Bool) throws {
        let expectedKeys: Set<String> = [
            "updatedAt", "onlineCount", "minerCount", "hashrateGHs", "powerWatts", "isDemo"
        ]
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        let value = sample(isDemo: isDemo)
        let encoded = try JSONEncoder().encode(value)
        storage.save(value)
        let key = try storedKey(in: defaults, suite: suite)
        let persisted = try #require(defaults.data(forKey: key))
        for bytes in [encoded, persisted] {
            let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let keysMessage = "Do not add hostnames, IPs, device names, credentials, pool URLs or raw " +
                "miner payloads to the shared cache"
            #expect(
                Set(object.keys) == expectedKeys,
                Comment(rawValue: keysMessage)
            )
            #expect(
                object.values.allSatisfy { $0 is NSNumber },
                "The aggregate cache needs only numeric values, a timestamp and the demo Boolean"
            )
        }
    }

    @Test func emptyFleetIsNotPresentedAsFreshTelemetry() {
        let empty = FleetGlance(
            updatedAt: timestamp,
            onlineCount: 0,
            minerCount: 0,
            hashrateGHs: 0,
            powerWatts: 0,
            isDemo: false
        )
        #expect(empty.isValid)
        #expect(empty.isStale(at: timestamp))
    }

    @Test func unavailableAppGroupFailsClosedWithoutStandardDefaultsFallback() {
        let storage = FleetGlanceStorage(defaults: nil)
        #expect(storage.isAvailable == false)
        #expect(storage.load() == .empty)
        #expect(storage.save(sample()) == false)
        storage.clear()
        #expect(storage.load() == .empty)
    }

    @Test func clearingSnapshotPreservesUnrelatedPreferences() throws {
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(storage.isAvailable)
        #expect(storage.save(sample()))
        defaults.set("keep", forKey: "unrelated.test.preference")
        storage.clear()
        #expect(storage.load() == .empty)
        #expect(defaults.string(forKey: "unrelated.test.preference") == "keep")
        #expect(storage.save(sample(isDemo: true)))
        #expect(storage.load() == sample(isDemo: true))
    }

    @Test func menuBarVisibilityModesMatchTheSystemItemContract() {
        #expect(FleetMenuBarVisibilityMode.always.shouldShow)
        #expect(FleetMenuBarVisibilityMode.hidden.shouldShow == false)
        #expect(FleetMenuBarLaunch.showURL.absoluteString == "hashfleet-menubar://show")
    }

    @Test func menuBarPreferenceDefaultsSafelyAndRoundTripsInAnInjectedSuite() throws {
        let suite = "app.hashfleet.menu-bar-preference.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = FleetMenuBarPreferenceStorage(defaults: defaults)

        #expect(storage.load() == .always)
        #expect(storage.save(.hidden))
        #expect(storage.load() == .hidden)
        defaults.set("whenAppIsOpen", forKey: FleetMenuBarPreferenceStorage.key)
        #expect(storage.load() == .always)
        defaults.set("future-unknown-mode", forKey: FleetMenuBarPreferenceStorage.key)
        #expect(storage.load() == .always)
    }

    @Test func menuBarSnapshotRoundTripsOnlyTheCompactPerMinerPresentation() throws {
        let suite = "app.hashfleet.menu-bar-snapshot.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = FleetMenuBarSnapshotStorage(defaults: defaults)
        let miner = FleetMenuBarMinerSummary(
            id: UUID(),
            name: "Garage miner",
            status: .online,
            segments: ["1.25 TH/s", "21 W", "Accepted 1,234", "Best 51.62G"],
            notices: [],
            isSimulated: false
        )
        let expected = FleetMenuBarSnapshot(glance: sample(), miners: [miner])

        #expect(storage.save(expected))
        #expect(storage.load() == expected)

        let data = try #require(defaults.data(forKey: FleetMenuBarSnapshotStorage.key))
        let encoded = try #require(String(bytes: data, encoding: .utf8))
        for forbidden in ["http://", "stratum", "password", "wallet", "seed"] {
            #expect(encoded.localizedCaseInsensitiveContains(forbidden) == false)
        }
    }

    @Test func menuBarSnapshotFallsBackToTheLegacyAggregateWithoutInventingMinerRows() throws {
        let suite = "app.hashfleet.menu-bar-legacy.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FleetMenuBarGlanceStorage(defaults: defaults).save(sample()))

        let loaded = FleetMenuBarSnapshotStorage(defaults: defaults).load()
        #expect(loaded.glance == sample())
        #expect(loaded.miners.isEmpty)
    }

    @Test func foregroundPublishWritesTheSnapshotReadByTheWidgetProvider() async throws {
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = FleetGlanceCoordinator(
            defaults: defaults,
            storage: storage,
            activityName: "HashFleet Foreground Widget Test \(suite)"
        )
        let initial = FleetGlance.empty
        coordinator.setWidgetSharing(true, glance: initial)
        let fresh = FleetGlance(
            updatedAt: Date(),
            onlineCount: 1,
            minerCount: 1,
            hashrateGHs: 1_200,
            powerWatts: 19,
            isDemo: false
        )

        await coordinator.publish(fresh)

        #expect(coordinator.sharesWithWidgets)
        #expect(storage.load() == fresh)
    }

}
