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

}
