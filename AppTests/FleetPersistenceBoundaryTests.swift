import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Fleet persistence boundary", .serialized)
@MainActor
struct FleetPersistenceBoundaryTests {
    @Test func failedDatabaseClearPreservesBaselinesAndCanRetry() async throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        let info = MinerInfo(raw: ["blockFound": .integer(1), "bestDiff": .string("50K")])
        store.blockObservations["fixture"] = MinerBlockFoundObservation(info: info)
        store.bestShareObservations["fixture"] = MinerBestShareObservation(info: info)
        store.persistBlockObservations()
        store.persistBestShareObservations()
        let originalBlock = defaults.data(forKey: FleetStore.blockObservationStorageKey)
        let originalBest = defaults.data(forKey: FleetStore.bestShareObservationStorageKey)
        struct WriteFailure: Error {}
        var attempts = 0
        let failed = await store.clearAllTelemetryAndAchievements {
            attempts += 1
            throw WriteFailure()
        }
        #expect(!failed && attempts == 1)
        #expect(store.blockObservations.count == 1 && store.bestShareObservations.count == 1)
        #expect(defaults.data(forKey: FleetStore.blockObservationStorageKey) == originalBlock)
        #expect(defaults.data(forKey: FleetStore.bestShareObservationStorageKey) == originalBest)
        #expect(store.persistenceError?.contains("Unable to clear telemetry") == true)
        let succeeded = await store.clearAllTelemetryAndAchievements { attempts += 1 }
        #expect(succeeded && attempts == 2)
        #expect(store.blockObservations.isEmpty && store.bestShareObservations.isEmpty)
        #expect(store.persistenceError == nil)
    }

    @Test func demoClearNeverCallsDatabase() async throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        store.isDemo = true
        var called = false
        let cleared = await store.clearAllTelemetryAndAchievements { called = true }
        #expect(!cleared && !called)
    }

    // MARK: - Corrupt Saved Fleet & Recovery Key Storage

    @Test("Corrupted saved fleet JSON is held in unreadableStorage and blocks export until recovered")
    func testCorruptSavedFleetPreservationAndRecovery() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let corruptedPayload = Data("{ invalid: json: payload ".utf8)
        defaults.set(corruptedPayload, forKey: FleetStore.storageKey)

        let store = FleetStore(defaults: defaults)
        #expect(store.devices.isEmpty)
        #expect(store.unreadableStorage == corruptedPayload)
        #expect(store.persistenceError != nil)

        // While unreadableStorage is present, export and restore must fail closed
        #expect(throws: FleetBackupError.storageUnavailable) {
            _ = try store.fleetBackupExportData()
        }
        let dummyPreview = FleetBackupRestorePreview(additions: [], alreadyPresent: [])
        #expect(throws: FleetBackupError.storageUnavailable) {
            _ = try store.applyFleetBackup(data: Data(), expectedPreview: dummyPreview)
        }

        // Recovering by adding a device moves corrupted data to a recovery key before overwriting
        try store.add(name: "Recovered Miner", address: "http://192.168.1.50")
        #expect(store.unreadableStorage == nil)
        #expect(store.devices.count == 1)
        #expect(store.devices.first?.name == "Recovered Miner")

        // Locate the created recovery key and verify the exact corrupted bytes were preserved
        let allKeys = defaults.dictionaryRepresentation().keys
        let recoveryKeys = allKeys.filter { $0.hasPrefix(FleetStore.storageKey + ".recovery.") }
        #expect(recoveryKeys.count == 1)
        if let recoveryKey = recoveryKeys.first {
            #expect(defaults.data(forKey: recoveryKey) == corruptedPayload)
        }

        // On the original store instance, persistenceError remains set until next launch
        #expect(store.persistenceError != nil)
        #expect(throws: FleetBackupError.storageUnavailable) {
            _ = try store.fleetBackupExportData()
        }

        // A freshly launched FleetStore decodes the recovered fleet cleanly and permits export
        let recoveredStore = FleetStore(defaults: defaults)
        #expect(recoveredStore.devices.count == 1)
        #expect(recoveredStore.devices.first?.name == "Recovered Miner")
        #expect(recoveredStore.unreadableStorage == nil)
        #expect(recoveredStore.persistenceError == nil)
        let exported = try recoveredStore.fleetBackupExportData()
        #expect(!exported.isEmpty)
    }

    @Test("Legacy saved fleet without optional metadata decodes and persists cleanly")
    func testLegacySavedFleetDecodingAndPersistence() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let legacyJSON = """
        [
            {
                "id": "11111111-2222-3333-4444-555555555555",
                "name": "Legacy Rig",
                "address": "http://192.168.1.100"
            }
        ]
        """
        defaults.set(Data(legacyJSON.utf8), forKey: FleetStore.storageKey)

        let store = FleetStore(defaults: defaults)
        #expect(store.devices.count == 1)
        let loaded = try #require(store.devices.first)
        #expect(loaded.name == "Legacy Rig")
        #expect(loaded.address == "http://192.168.1.100")
        #expect(store.unreadableStorage == nil)
        #expect(store.persistenceError == nil)

        // Writing persists without error
        store.persist()
        let reloaded = FleetStore(defaults: defaults)
        #expect(reloaded.devices.count == 1)
        #expect(reloaded.devices.first?.id == loaded.id)
    }

    // MARK: - Snapshot Cache Boundary & Validation

    @Test("Snapshot cache drops oversized data, future clock skew, and empty entries")
    func testSnapshotCacheValidationBoundaries() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let device = MinerDevice(name: "Rig", address: "http://192.168.1.20")
        defaults.set(try JSONEncoder().encode([device]), forKey: FleetStore.storageKey)

        // 1. Oversized cache data (> 2MB) is ignored completely
        let oversized = Data(repeating: 0x7B, count: (2 * 1024 * 1024) + 10)
        defaults.set(oversized, forKey: FleetStore.snapshotCacheKey)
        var store = FleetStore(defaults: defaults)
        #expect(store.snapshots.isEmpty)

        // 2. Future timestamp (> 60s skew) is rejected
        let futureDate = Date().addingTimeInterval(120)
        let futureEntry = MinerSnapshotCacheEntry(
            info: MinerInfo(raw: ["hashRate": .number(1500), "temp": .number(60)]),
            observedAt: futureDate
        )
        let futureCache = try JSONEncoder().encode([device.id.uuidString: futureEntry])
        defaults.set(futureCache, forKey: FleetStore.snapshotCacheKey)
        store = FleetStore(defaults: defaults)
        #expect(store.snapshots[device.id] == nil)

        // 3. Valid cache entry restores snapshot with isReconnecting and isCached flags
        let validDate = Date().addingTimeInterval(-30)
        let validEntry = MinerSnapshotCacheEntry(
            info: MinerInfo(raw: ["hashRate": .number(1200), "temp": .number(55)]),
            observedAt: validDate
        )
        let validCache = try JSONEncoder().encode([device.id.uuidString: validEntry])
        defaults.set(validCache, forKey: FleetStore.snapshotCacheKey)
        store = FleetStore(defaults: defaults)
        let restoredSnapshot = try #require(store.snapshots[device.id])
        #expect(restoredSnapshot.isCached)
        #expect(restoredSnapshot.isReconnecting)
        #expect(restoredSnapshot.updatedAt == validDate)
    }

    @Test("Snapshot cache throttling separates rapid telemetry from immediate settings changes")
    func testSnapshotCacheThrottlingDistinction() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let device = MinerDevice(name: "Paced Rig", address: "http://192.168.1.25")
        defaults.set(try JSONEncoder().encode([device]), forKey: FleetStore.storageKey)
        let store = FleetStore(defaults: defaults)

        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        let initialInfo = MinerInfo(raw: [
            "hashRate": .number(1000),
            "frequency": .number(500),
            "temp": .number(50)
        ])
        store.cacheSuccessfulInfo(initialInfo, for: device.id, at: t0)
        #expect(store.cachePersistedAt[device.id] == t0)

        // Rapid telemetry-only update within 5 seconds must not persist
        let t1 = t0.addingTimeInterval(2)
        let telemetryOnlyInfo = MinerInfo(raw: [
            "hashRate": .number(1050),
            "frequency": .number(500),
            "temp": .number(52)
        ])
        store.cacheSuccessfulInfo(telemetryOnlyInfo, for: device.id, at: t1)
        #expect(store.cachePersistedAt[device.id] == t0)

        // Settings change within 5 seconds (frequency changed) must persist immediately
        let settingsChangedInfo = MinerInfo(raw: [
            "hashRate": .number(1050),
            "frequency": .number(550),
            "temp": .number(52)
        ])
        store.cacheSuccessfulInfo(settingsChangedInfo, for: device.id, at: t1)
        #expect(store.cachePersistedAt[device.id] == t1)

        // Forced update within 5 seconds must persist immediately
        let t2 = t1.addingTimeInterval(1)
        store.cacheSuccessfulInfo(settingsChangedInfo, for: device.id, at: t2, force: true)
        #expect(store.cachePersistedAt[device.id] == t2)
    }

    // MARK: - Notification Inbox Durability, Retention & Pruning

    @Test("Notification inbox retention discards entries older than 14 days and orphaned device alerts")
    func testNotificationInboxRetentionAndOrphanPruning() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let activeMiner = MinerDevice(name: "Active Rig", address: "http://192.168.1.30")
        defaults.set(try JSONEncoder().encode([activeMiner]), forKey: FleetStore.storageKey)

        let now = Date()
        let oldDate = now.addingTimeInterval(-(15 * 24 * 60 * 60)) // 15 days old
        let recentDate = now.addingTimeInterval(-(2 * 24 * 60 * 60)) // 2 days old
        let orphanedMinerID = UUID()

        let expiredEntry = FleetNotificationInboxEntry(
            event: .stateChange(MinerStateChangeEvent(
                deviceID: activeMiner.id, minerName: activeMiner.name,
                kind: .offline, occurredAt: oldDate
            )),
            systemDelivered: true, inAppDelivered: true
        )
        let orphanedEntry = FleetNotificationInboxEntry(
            event: .stateChange(MinerStateChangeEvent(
                deviceID: orphanedMinerID, minerName: "Deleted Rig",
                kind: .offline, occurredAt: recentDate
            )),
            systemDelivered: true, inAppDelivered: true
        )
        let retainedEntry = FleetNotificationInboxEntry(
            event: .stateChange(MinerStateChangeEvent(
                deviceID: activeMiner.id, minerName: activeMiner.name,
                kind: .backOnline, occurredAt: recentDate
            )),
            systemDelivered: false, inAppDelivered: false
        )

        let inboxData = try JSONEncoder().encode([expiredEntry, orphanedEntry, retainedEntry])
        defaults.set(inboxData, forKey: FleetStore.notificationInboxStorageKey)

        let store = FleetStore(defaults: defaults)
        #expect(store.notificationInbox.count == 1)
        #expect(store.notificationInbox.first?.id == retainedEntry.id)
    }

    @Test("Notification inbox caps durable journal at 100 entries preserving newest")
    func testNotificationInboxLimitBoundary() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let device = MinerDevice(name: "Rig", address: "http://192.168.1.31")
        defaults.set(try JSONEncoder().encode([device]), forKey: FleetStore.storageKey)

        let baseDate = Date().addingTimeInterval(-3600)
        let entries = (0..<120).map { index in
            FleetNotificationInboxEntry(
                event: .temperature(MinerTemperatureAlertEvent(
                    deviceID: device.id, minerName: device.name,
                    temperatureCelsius: Double(70 + index),
                    thresholdCelsius: 65,
                    occurredAt: baseDate.addingTimeInterval(Double(index))
                )),
                systemDelivered: true, inAppDelivered: true
            )
        }
        let inboxData = try JSONEncoder().encode(entries)
        defaults.set(inboxData, forKey: FleetStore.notificationInboxStorageKey)

        let store = FleetStore(defaults: defaults)
        #expect(store.notificationInbox.count == 100)
        // Kept entries must be the latest 100 entries
        #expect(store.notificationInbox.first?.id == entries[20].id)
        #expect(store.notificationInbox.last?.id == entries[119].id)
    }

    @Test("Notification deduplication collapses duplicate state changes while keeping toggles")
    func testNotificationDeduplicationStateTransitions() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FleetStore(defaults: defaults)
        let deviceID = UUID()
        let t0 = Date()

        let offline1 = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            deviceID: deviceID, minerName: "Test Rig", kind: .offline, occurredAt: t0
        ))
        let offlineDuplicate = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            deviceID: deviceID, minerName: "Test Rig", kind: .offline, occurredAt: t0.addingTimeInterval(10)
        ))
        let backOnline = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            deviceID: deviceID, minerName: "Test Rig", kind: .backOnline, occurredAt: t0.addingTimeInterval(20)
        ))
        let offlineAgain = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            deviceID: deviceID, minerName: "Test Rig", kind: .offline, occurredAt: t0.addingTimeInterval(30)
        ))

        store.enqueueNotification(offline1)
        #expect(store.notificationInbox.count == 1)

        store.enqueueNotification(offlineDuplicate)
        #expect(store.notificationInbox.count == 1)

        store.enqueueNotification(backOnline)
        #expect(store.notificationInbox.count == 2)

        store.enqueueNotification(offlineAgain)
        #expect(store.notificationInbox.count == 3)
    }

    @Test("Hydration preserves every unseen record instead of silently marking older popups seen")
    func testCelebrationHydrationPreservesUnseenRecords() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let device = MinerDevice(name: "Rig", address: "http://192.168.1.32")
        defaults.set(try JSONEncoder().encode([device]), forKey: FleetStore.storageKey)

        let t0 = Date().addingTimeInterval(-600)
        let olderBestShare = FleetNotificationInboxEntry(
            event: .bestShare(MinerBestShareEvent(
                deviceID: device.id, minerName: device.name, kind: .session,
                displayValue: "1.0M", rawValue: "1M", occurredAt: t0
            )),
            systemDelivered: false, inAppDelivered: false
        )
        let newerBestShare = FleetNotificationInboxEntry(
            event: .bestShare(MinerBestShareEvent(
                deviceID: device.id, minerName: device.name, kind: .session,
                displayValue: "2.0M", rawValue: "2M", occurredAt: t0.addingTimeInterval(100)
            )),
            systemDelivered: false, inAppDelivered: false
        )

        let inboxData = try JSONEncoder().encode([olderBestShare, newerBestShare])
        defaults.set(inboxData, forKey: FleetStore.notificationInboxStorageKey)

        let store = FleetStore(defaults: defaults)
        #expect(store.latestBestShareEvent?.rawValue == "2M")

        let olderInStore = store.notificationInbox.first { $0.id == olderBestShare.id }
        let newerInStore = store.notificationInbox.first { $0.id == newerBestShare.id }
        #expect(olderInStore?.inAppDelivered == false)
        #expect(newerInStore?.inAppDelivered == false)
        var popups = FleetCelebrationQueue()
        FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true,
            presentInApp: { event in
                if let celebration = FleetCelebration(event) { popups.present(celebration) } else { Issue.record("Expected only record popups") }
            })
        #expect(popups.current?.id == olderBestShare.id)
        #expect(popups.pending.map(\.id) == [newerBestShare.id])
        #expect(store.undeliveredSystemNotificationEntries.isEmpty)
        #expect(store.notificationInbox.allSatisfy { $0.inAppDelivered })
    }

    // MARK: - Telemetry & Milestone Wipe Boundary

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
                print("STARTUP_RESTORE_OBSERVATION " + String(decoding: report, as: UTF8.self))
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

    private func makeSuite() throws -> (UserDefaults, String) {
        let suite = "app.hashfleet.persistence.boundary.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
