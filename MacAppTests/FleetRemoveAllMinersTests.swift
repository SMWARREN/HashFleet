import Foundation
import Testing
import HashFleetCore
@testable import HashFleetMac

@Suite("FleetStore removeAllMiners correctness", .serialized)
@MainActor
struct FleetRemoveAllMinersTests {
    private func isolatedStore(
        onDelete: @escaping @MainActor (UUID) -> Void = { _ in }
    ) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.removeall.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = []
        let session = URLSession(configuration: config)
        let store = FleetStore(
            defaults: defaults,
            session: session,
            achievementDeletion: { id in
                await MainActor.run { onDelete(id) }
            }
        )
        return (store, defaults, suite)
    }

    @Test func removeAllMinersClearsPersistedDevicesAndCachedReadings() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        try store.add(name: "Miner Alpha", address: "192.168.1.101")
        try store.add(name: "Miner Beta", address: "192.168.1.102")
        #expect(store.devices.count == 2)

        let devA = store.devices[0]
        let devB = store.devices[1]
        let info = MinerInfo(raw: ["hashRate": .number(500), "temp": .number(60)])
        store.cachedReadings[devA.id.uuidString] = MinerSnapshotCacheEntry(info: info, observedAt: Date())
        store.cachedReadings[devB.id.uuidString] = MinerSnapshotCacheEntry(info: info, observedAt: Date())
        store.cachePersistedAt[devA.id] = Date()
        store.cachePersistedAt[devB.id] = Date()
        store.persistCachedReadings()

        store.removeAllMiners()

        #expect(store.devices.isEmpty)
        #expect(store.cachedReadings.isEmpty)
        #expect(store.cachePersistedAt.isEmpty)

        // Verify persisted defaults store empty array
        let reloaded = FleetStore(defaults: defaults)
        #expect(reloaded.devices.isEmpty)
    }

    @Test func removeAllMinersTriggersAchievementDeletionCallbacks() async throws {
        var deletedIDs: [UUID] = []
        let (store, defaults, suite) = isolatedStore(onDelete: { id in
            deletedIDs.append(id)
        })
        defer { defaults.removePersistentDomain(forName: suite) }

        try store.add(name: "Unit One", address: "192.168.1.201")
        try store.add(name: "Unit Two", address: "192.168.1.202")
        let targetIDs = Set(store.devices.map(\.id))
        #expect(targetIDs.count == 2)

        store.removeAllMiners()

        // Bounded deterministic polling wait up to 2 seconds
        let deadline = Date().addingTimeInterval(2.0)
        while deletedIDs.count < targetIDs.count && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(deletedIDs.count == 2)
        #expect(Set(deletedIDs) == targetIDs)
    }

    @Test func removeAllMinersInDemoModeProtectsRealFleet() throws {
        var deletedIDs: [UUID] = []
        let (store, defaults, suite) = isolatedStore(onDelete: { id in
            deletedIDs.append(id)
        })
        defer { defaults.removePersistentDomain(forName: suite) }

        try store.add(name: "Real Device", address: "192.168.1.55")
        #expect(store.devices.count == 1)

        store.loadDemo()
        #expect(store.isDemo)
        #expect(store.devices.count > 1)

        store.removeAllMiners()
        #expect(store.devices.isEmpty)

        // Demo devices must never invoke achievement deletion for real hardware
        #expect(deletedIDs.isEmpty)

        // Clearing demo mode restores the real persisted fleet
        store.clearDemo()
        #expect(!store.isDemo)
        #expect(store.devices.count == 1)
        #expect(store.devices.first?.name == "Real Device")
    }

    @Test func removeAllMinersRespectsAchievementMergeGuard() async throws {
        var deletedIDs: [UUID] = []
        let (store, defaults, suite) = isolatedStore(onDelete: { id in
            deletedIDs.append(id)
        })
        defer { defaults.removePersistentDomain(forName: suite) }

        try store.add(name: "Protected Miner", address: "192.168.1.10")
        try store.add(name: "Unprotected Miner", address: "192.168.1.20")
        let protectedDevice = store.devices[0]
        let unprotectedDevice = store.devices[1]

        store.achievementMergeProtectedIDs.insert(protectedDevice.id)

        store.removeAllMiners()

        // Protected miner remains in devices
        #expect(store.devices.count == 1)
        #expect(store.devices.first?.id == protectedDevice.id)
        #expect(store.persistenceError != nil)

        // Bounded deterministic polling wait up to 2 seconds
        let deadline = Date().addingTimeInterval(2.0)
        while deletedIDs.isEmpty && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(deletedIDs == [unprotectedDevice.id])
    }

    @Test func removeAllMinersCleansUpSnapshotsAndObservations() throws {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        try store.add(name: "Observed Miner", address: "192.168.1.80")
        let device = store.devices[0]

        store.snapshots[device.id] = MinerSnapshot()
        store.blockObservations[device.id.uuidString] = MinerBlockFoundObservation(
            count: 1, showNewBlock: true, height: 800000
        )
        store.stateObservations[device.id.uuidString] = MinerFleetStateObservation(
            isOnline: true, hashrate: 500, power: 15, observedAt: Date()
        )
        store.bestShareObservations[device.id.uuidString] = MinerBestShareObservation(
            bestDiff: "1M", bestSessionDiff: "500K"
        )

        store.removeAllMiners()

        #expect(store.devices.isEmpty)
        #expect(store.snapshots.isEmpty)
        #expect(store.blockObservations.isEmpty)
        #expect(store.stateObservations.isEmpty)
        #expect(store.bestShareObservations.isEmpty)
    }

    @Test func removeAllMinersOnEmptyFleetIsSafeNoOp() {
        let (store, defaults, suite) = isolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.devices.isEmpty)
        store.removeAllMiners()
        #expect(store.devices.isEmpty)
        #expect(store.persistenceError == nil)
    }
}
