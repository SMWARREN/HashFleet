import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension FleetPersistenceBoundaryTests {
    @Test("clearAllTelemetryAndAchievements wipes milestone baselines while preserving health alerts")
    func testClearAllTelemetryAndAchievementsScope() async throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let device = MinerDevice(name: "Rig", address: "http://192.168.1.50")
        defaults.set(try JSONEncoder().encode([device]), forKey: FleetStore.storageKey)

        let store = FleetStore(defaults: defaults)
        let deviceID = device.id

        let blockInfo = MinerInfo(raw: [
            "blockFound": .integer(1),
            "blockHeight": .integer(850_000),
            "showNewBlock": .bool(true)
        ])
        store.blockObservations["key1"] = MinerBlockFoundObservation(info: blockInfo)

        let bestShareInfo = MinerInfo(raw: [
            "bestDiff": .string("50K"),
            "bestSessionDiff": .string("50K")
        ])
        store.bestShareObservations["key2"] = MinerBestShareObservation(info: bestShareInfo)
        store.persistBlockObservations()
        store.persistBestShareObservations()

        let milestoneEntry = FleetNotificationInboxEntry(
            event: .blockFound(MinerBlockFoundEvent(
                deviceID: deviceID, minerName: "Rig", coinLabel: "BTC",
                height: 850_000, count: 1, occurredAt: .now
            )),
            systemDelivered: true, inAppDelivered: false
        )
        let healthEntry = FleetNotificationInboxEntry(
            event: .temperature(MinerTemperatureAlertEvent(
                deviceID: deviceID, minerName: "Rig",
                temperatureCelsius: 75, thresholdCelsius: 70, occurredAt: .now
            )),
            systemDelivered: true, inAppDelivered: false
        )
        store.notificationInbox = [milestoneEntry, healthEntry]
        store.persistNotificationInbox()

        await store.clearAllTelemetryAndAchievements()

        #expect(store.blockObservations.isEmpty)
        #expect(store.bestShareObservations.isEmpty)
        #expect(store.latestBlockFoundEvent == nil)

        // Only milestone alerts are pruned from the durable inbox; health alerts are preserved
        #expect(store.notificationInbox.count == 1)
        #expect(store.notificationInbox.first?.id == healthEntry.id)

        // Reload fresh store to verify durable reset
        let reloaded = FleetStore(defaults: defaults)
        #expect(reloaded.blockObservations.isEmpty)
        #expect(reloaded.bestShareObservations.isEmpty)
        #expect(reloaded.notificationInbox.count == 1)
        #expect(reloaded.notificationInbox.first?.id == healthEntry.id)
    }

    // MARK: - Per-Device Alert Preferences Isolation & Corruption

    @Test("Per-device alert preferences fail closed on corrupt bytes and recover on explicit write")
    func testPerDeviceAlertPreferencesCorruptRecovery() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let deviceID = UUID()
        let corruptedKey = FleetTemperatureAlertPreferences.keyPrefix + deviceID.uuidString
        defaults.set(Data("corrupted plist/json".utf8), forKey: corruptedKey)

        let alertPrefs = FleetTemperatureAlertPreferences(defaults: defaults)
        #expect(alertPrefs.persistenceError != nil)

        // Policy fails closed (disabled)
        let policy = alertPrefs.policy(for: deviceID)
        #expect(!policy.isEnabled)

        // Explicit user save repairs the corrupt record and clears the error
        let validPolicy = try MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: 68)
        try alertPrefs.setPolicy(validPolicy, for: deviceID)

        #expect(alertPrefs.persistenceError == nil)
        #expect(alertPrefs.policy(for: deviceID).isEnabled)
        #expect(alertPrefs.policy(for: deviceID).thresholdCelsius == 68)

        // Removing clears key and error cleanly
        alertPrefs.remove(deviceID: deviceID)
        #expect(defaults.object(forKey: corruptedKey) == nil)
        #expect(alertPrefs.persistenceError == nil)
    }

    // MARK: - Zero Sensitive Credentials Leakage

    @Test("Fleet persistence never records passwords, tokens, or raw secrets into UserDefaults")
    func testZeroSensitiveDataLeakageAcrossUserDefaults() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let device = MinerDevice(name: "Safe Rig", address: "http://192.168.1.40")
        defaults.set(try JSONEncoder().encode([device]), forKey: FleetStore.storageKey)
        let store = FleetStore(defaults: defaults)

        // Cache info with pool URLs containing credentials and sensitive fields
        let rawWithSecrets: [String: JSONValue] = [
            "hashRate": .number(2000),
            "temp": .number(58),
            "password": .string("superSecretAdmin123"),
            "token": .string("bearer_token_abc_xyz"),
            "wallet": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"),
            "stratumURL": .string("stratum+tcp://user:pass@pool.example.com:3333"),
            "pools": .array([
                .object([
                    "url": .string("stratum+tcp://worker1:secret2@backup.example.com:4444"),
                    "enabled": .bool(true)
                ])
            ])
        ]
        store.cacheSuccessfulInfo(MinerInfo(raw: rawWithSecrets), for: device.id, at: .now, force: true)
        store.persist()

        let dictionary = defaults.dictionaryRepresentation()
        let forbiddenWords = ["superSecretAdmin123", "bearer_token_abc_xyz", "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"]

        for (key, val) in dictionary {
            let serialized: String
            if let str = val as? String {
                serialized = str
            } else if let data = val as? Data {
                serialized = String(bytes: data, encoding: .utf8) ?? ""
            } else {
                serialized = String(describing: val)
            }
            for forbidden in forbiddenWords {
                #expect(!serialized.contains(forbidden), "Key '\(key)' leaked sensitive value: \(forbidden)")
            }
        }
    }

    @Test func syntheticStartupRestoreReportsCostAndPreservesContents() throws {
        // Warm, synthetic defaults, not a physical cold-launch or watchdog benchmark.
        // No monitoring starts, and the only addresses are inside the existing loopback fence.
        for scenario in ["fleet20", "fleet128", "rename128", "largeCache128"] {
            let count = scenario == "fleet20" ? 20 : 128
            let automaticNames = scenario == "rename128"
            let (defaults, suite) = try makeSuite()
            defer { defaults.removePersistentDomain(forName: suite) }
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let devices = (0..<count).map { index in
                MinerDevice(name: "Saved fixture \(index)", address: "http://127.0.0.1:50417",
                            usesAutomaticName: automaticNames)
            }
            let now = Date()
            let server = String(repeating: "a", count: 60) + ".example.test"
            let info = MinerInfo(raw: [
                "hostname": .string("restored-fixture"), "ASICModel": .string("BM1370"),
                "boardVersion": .string("602"), "version": .string(String(repeating: "v", count: 200)),
                "hashRate": .number(1200), "power": .number(25), "temp": .number(55),
                "frequency": .integer(500), "coreVoltage": .integer(1050),
                "pools": .array((0..<8).map { index in .object([
                    "id": .integer(index), "url": .string(server), "port": .integer(3333),
                    "enabled": .bool(true), "priority": .integer(index)
                ]) })
            ])
            let entry = MinerSnapshotCacheEntry(info: info, observedAt: now)
            var cache = Dictionary(uniqueKeysWithValues: devices.map { ($0.id.uuidString, entry) })
            if scenario == "largeCache128" {
                // Exercise decoding unrelated cached entries inside the existing byte cap.
                // This is an explicit stress input, not a claim about a typical saved fleet.
                for index in 0..<900 { cache["unused-synthetic-\(index)"] = entry }
            }
            let inbox = (0..<100).map { index in
                FleetNotificationInboxEntry(event: .stateChange(MinerStateChangeEvent(
                    deviceID: devices[index % count].id, minerName: devices[index % count].name,
                    kind: index.isMultiple(of: 2) ? .offline : .backOnline,
                    occurredAt: now.addingTimeInterval(Double(index - 100))
                )), systemDelivered: true, inAppDelivered: true)
            }
            let encoder = JSONEncoder()
            let deviceData = try encoder.encode(devices)
            let cacheData = try encoder.encode(cache)
            let inboxData = try encoder.encode(inbox)
            #expect(cacheData.count <= 2 * 1024 * 1024)
            if scenario == "largeCache128" { #expect(cacheData.count > 1024 * 1024) }
            for repetition in 0..<3 {
                defaults.set(deviceData, forKey: FleetStore.storageKey)
                defaults.set(cacheData, forKey: FleetStore.snapshotCacheKey)
                defaults.set(inboxData, forKey: FleetStore.notificationInboxStorageKey)
                let start = ProcessInfo.processInfo.systemUptime
                let store = FleetStore(defaults: defaults, session: session)
                let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
                #expect(store.devices.map(\.id) == devices.map(\.id))
                #expect(store.snapshots.count == count && store.cachedReadings.count == count)
                #expect(store.notificationInbox.map(\.id) == inbox.map(\.id))
                #expect(store.snapshots.values.allSatisfy { $0.isCached && $0.isReconnecting })
                #expect(store.persistenceError == nil && store.liveTasks.isEmpty && store.refreshTask == nil)
                #expect(defaults.data(forKey: FleetStore.snapshotCacheKey) == cacheData)
                #expect(defaults.data(forKey: FleetStore.notificationInboxStorageKey) == inboxData)
                if automaticNames {
                    #expect(zip(store.devices, devices).allSatisfy { $0.0.name != $0.1.name })
                } else {
                    #expect(store.devices == devices)
                    #expect(defaults.data(forKey: FleetStore.storageKey) == deviceData)
                }
                let row: [String: Any] = [
                    "scenario": scenario, "repetition": repetition, "devices": count,
                    "cached_entries": cache.count, "inbox_entries": inbox.count,
                    "inventory_bytes": deviceData.count, "cache_bytes": cacheData.count,
                    "inbox_bytes": inboxData.count, "initialization_ms": milliseconds,
                    "automatic_names": automaticNames
                ]
                let report = try JSONSerialization.data(withJSONObject: row, options: .sortedKeys)
                let reportText = try #require(String(data: report, encoding: .utf8))
                print("STARTUP_RESTORE_OBSERVATION " + reportText)
            }
        }
    }

    @Test func automaticNameBatchDefersOnlyExplicitSaves() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        let first = MinerDevice(name: "Old first", address: "http://127.0.0.1:50417", usesAutomaticName: true)
        let second = MinerDevice(name: "Old second", address: "http://127.0.0.1:50418", usesAutomaticName: true)
        let manual = MinerDevice(name: "Keep manual", address: "http://127.0.0.1:50419", usesAutomaticName: false)
        store.devices = [first, second, manual]
        store.persist()
        let before = try #require(defaults.data(forKey: FleetStore.storageKey))
        let initialInfo = MinerInfo(raw: ["hostname": .string("restored-first")])
        #expect(store.updateAutomaticName(for: first.id, info: initialInfo, persistImmediately: false))
        #expect(store.updateAutomaticName(for: second.id,
            info: MinerInfo(raw: ["hostname": .string("restored-second")]), persistImmediately: false))
        #expect(defaults.data(forKey: FleetStore.storageKey) == before)
        #expect(!store.updateAutomaticName(for: first.id, info: initialInfo, persistImmediately: false))
        #expect(!store.updateAutomaticName(for: manual.id, info: initialInfo, persistImmediately: false))
        #expect(!store.updateAutomaticName(for: UUID(), info: initialInfo, persistImmediately: false))
        #expect(store.devices[2] == manual)
        store.persist()
        let batched = try #require(defaults.data(forKey: FleetStore.storageKey))
        #expect(try JSONDecoder().decode([MinerDevice].self, from: batched) == store.devices)
        #expect(store.devices.map(\.id) == [first.id, second.id, manual.id])
        #expect(store.updateAutomaticName(for: first.id,
            info: MinerInfo(raw: ["hostname": .string("live-first")])))
        let live = try #require(defaults.data(forKey: FleetStore.storageKey))
        #expect(live != batched)
        #expect(try JSONDecoder().decode([MinerDevice].self, from: live) == store.devices)
        store.isDemo = true
        let demoDevices = store.devices
        #expect(!store.updateAutomaticName(for: first.id, info: initialInfo, persistImmediately: false))
        #expect(store.devices == demoDevices)
        #expect(defaults.data(forKey: FleetStore.storageKey) == live)

        let cache = [first.id.uuidString: MinerSnapshotCacheEntry(info: initialInfo, observedAt: Date()),
            second.id.uuidString: MinerSnapshotCacheEntry(
                info: MinerInfo(raw: ["hostname": .string("final-second")]), observedAt: Date())]
        defaults.set(try JSONEncoder().encode(cache), forKey: FleetStore.snapshotCacheKey)
        let restored = FleetStore(defaults: defaults)
        #expect(restored.devices.map(\.name) == ["restored-first", "final-second", "Keep manual"])
        let saved = try #require(defaults.data(forKey: FleetStore.storageKey))
        #expect(try JSONDecoder().decode([MinerDevice].self, from: saved) == restored.devices)
    }

    // MARK: - Helpers

    func makeSuite() throws -> (UserDefaults, String) {
        let suite = "app.hashfleet.persistence.boundary.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
