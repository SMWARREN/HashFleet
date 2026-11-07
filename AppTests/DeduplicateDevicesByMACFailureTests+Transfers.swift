import Foundation
import Testing
import HashFleetCore
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif

extension DeduplicateDevicesByMACFailureTests {
    @Test func threeIdentitiesKeepTheFirstDeviceAndEveryDistinctEvent() async throws {
        let probe = MergeProbe()
        let database = MinerTelemetryDatabase(inMemory: true)
        probe.database = database
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let third = MinerDevice(name: "Third identity", address: "http://third.invalid")
        store.devices.append(third)
        store.snapshots[third.id] = snapshot(mac: "AA:BB:CC:11:22:33")
        let identities = store.devices.map(\.id)
        let target = fixture.devices[0].id
        let date = Date(timeIntervalSince1970: 1_000_000)
        for (index, id) in identities.enumerated() {
            await database.recordAchievement(
                minerId: id.uuidString, eventType: "best_share", timestamp: date, difficulty: "100")
            await database.recordAchievement(
                minerId: id.uuidString, eventType: "block_found", timestamp: date, blockHeight: 500 + index)
        }

        await store.deduplicateDevicesByMAC()
        #expect(store.devices == [fixture.devices[0]])
        #expect(probe.merges.map { $0.0 } == Array(identities.dropFirst()))
        #expect(probe.merges.allSatisfy { $0.1 == target })
        #expect(probe.devicesPresentDuringMerge == [3, 2])
        for id in identities {
            #expect(store.achievementDeviceID(for: id) == target)
        }
        let rows = await database.getAllAchievements()
        #expect(rows.count == 4)
        #expect(rows.allSatisfy { $0.minerId == target.uuidString })
        #expect(Set(rows.compactMap(\.blockHeight)) == [500, 501, 502])
        #expect(rows.filter { $0.eventType == "best_share" }.count == 1)
        await store.deduplicateDevicesByMAC()
        #expect(probe.merges.count == 2)
        #expect(probe.deletions.isEmpty)
        #expect(store.achievementMergeProtectedIDs.isEmpty)
    }

    @Test func unrelatedRemovalRemainsAvailableDuringCommittedTransfer() async throws {
        let probe = MergeProbe()
        let database = MinerTelemetryDatabase(inMemory: true)
        probe.database = database
        let gate = MergeGate()
        probe.afterMergeGate = gate
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let source = fixture.devices[1].id
        let target = fixture.devices[0].id
        let unrelated = MinerDevice(name: "Unrelated", address: "http://unrelated.invalid")
        store.devices.append(unrelated)
        store.snapshots[unrelated.id] = snapshot(mac: "DD:EE:FF:44:55:66")
        await database.recordAchievement(minerId: source.uuidString, eventType: "block_found", blockHeight: 500)
        await database.recordAchievement(minerId: unrelated.id.uuidString, eventType: "block_found", blockHeight: 600)
        let work = Task { await store.deduplicateDevicesByMAC() }
        await gate.waitUntilEntered()

        #expect(store.achievementMergeProtectedIDs == [source, target])
        store.remove(unrelated)
        await probe.waitForDeletion()
        #expect(store.devices == fixture.devices)
        #expect(probe.deletions == [unrelated.id])
        gate.release()
        await work.value
        #expect(store.devices == [fixture.devices[0]])
        let rows = await database.getAllAchievements()
        #expect(rows.count == 1)
        #expect(rows.first?.minerId == target.uuidString)
        #expect(rows.first?.blockHeight == 500)
        #expect(store.achievementMergeProtectedIDs.isEmpty)
    }

    @Test(arguments: [PostCommitInvalidation.cancellation, .generation, .demo])
    func committedTransferSurvivesInvalidationAndRetry(_ invalidation: PostCommitInvalidation) async throws {
        let probe = MergeProbe()
        let database = MinerTelemetryDatabase(inMemory: true)
        probe.database = database
        let gate = MergeGate()
        probe.afterMergeGate = gate
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let source = fixture.devices[1].id
        let target = fixture.devices[0].id
        await database.recordAchievement(minerId: source.uuidString, eventType: "block_found", blockHeight: 500)
        await database.recordAchievement(minerId: target.uuidString, eventType: "best_share", difficulty: "100")
        let work = Task { await store.deduplicateDevicesByMAC() }
        await gate.waitUntilEntered()
        switch invalidation {
        case .cancellation: work.cancel()
        case .generation: store.generation = UUID()
        case .demo: store.loadDemo()
        }
        gate.release()
        await work.value
        #expect(store.achievementMergeProtectedIDs.isEmpty)
        #expect(!store.isDeduplicatingDevices)
        #expect(probe.deletions.isEmpty)
        let committed = await database.getAllAchievements()
        #expect(committed.count == 2)
        #expect(committed.allSatisfy { $0.minerId == target.uuidString })
        if store.isDemo {
            #expect(store.savedDevices == fixture.devices)
            store.clearDemo()
            store.snapshots = Dictionary(uniqueKeysWithValues: fixture.devices.map {
                ($0.id, snapshot(mac: "AA:BB:CC:11:22:33"))
            })
        }
        #expect(store.devices == fixture.devices)
        probe.afterMergeGate = nil
        await store.deduplicateDevicesByMAC()
        #expect(store.devices == [fixture.devices[0]])
        #expect(store.achievementDeviceID(for: source) == target)
        let retried = await database.getAllAchievements()
        #expect(Set(retried.map(\.id)) == Set(committed.map(\.id)))
        #expect(retried.count == 2)
        #expect(probe.deletions.isEmpty)
    }

    enum PostCommitInvalidation: Sendable { case cancellation, generation, demo }
    enum Invalidation: Sendable { case demo, generation, address, kind, mac, survivorAddress, survivorRemoved }
}
