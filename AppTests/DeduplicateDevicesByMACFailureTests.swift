import Foundation
import Testing
import HashFleetCore
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct DeduplicateDevicesByMACFailureTests {
    @Test func failedMergeRetainsBothDevicesAndCanRetryWithoutDeletion() async throws {
        let probe = MergeProbe()
        probe.shouldFail = true
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let source = fixture.devices[1].id
        let target = fixture.devices[0].id

        await store.deduplicateDevicesByMAC()
        #expect(store.devices.count == 2)
        #expect(store.achievementAliases[source] == nil)
        #expect(store.persistenceError != nil)
        #expect(probe.deletions.isEmpty)

        probe.shouldFail = false
        await store.deduplicateDevicesByMAC()
        #expect(store.devices.map(\.id) == [target])
        #expect(store.achievementDeviceID(for: source) == target)
        #expect(probe.merges.count == 2)
        #expect(probe.deletions.isEmpty)
        #expect(probe.devicesPresentDuringMerge == [2, 2])
    }

    @Test(arguments: [Invalidation.demo, .generation, .address, .kind, .mac, .survivorAddress, .survivorRemoved])
    func suspendedMergeNeverRemovesAChangedFleet(_ invalidation: Invalidation) async throws {
        let probe = MergeProbe()
        let gate = MergeGate()
        probe.gate = gate
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let source = fixture.devices[1].id
        let work = Task { await store.deduplicateDevicesByMAC() }
        await gate.waitUntilEntered()
        #expect(store.achievementDeviceID(for: source) == fixture.devices[0].id)
        switch invalidation {
        case .demo: store.isDemo = true
        case .generation: store.generation = UUID()
        case .address: store.devices[1].address = "http://changed.invalid"
        case .kind: store.devices[1].kind = .xmrig
        case .survivorAddress: store.devices[0].address = "http://changed-survivor.invalid"
        case .mac:
            store.snapshots[source] = snapshot(mac: "DD:EE:FF:44:55:66")
        case .survivorRemoved: store.devices.removeFirst()
        }
        gate.release()
        await work.value
        #expect(store.devices.contains { $0.id == source })
        #expect(store.achievementAliases[source] == nil)
        #expect(probe.deletions.isEmpty)
        #expect(store.achievementMergeProtectedIDs.isEmpty)
    }

    @Test func overlappingDeduplicationRunsOnlyOneMerge() async throws {
        let probe = MergeProbe()
        let gate = MergeGate()
        probe.gate = gate
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let work = Task { await fixture.store.deduplicateDevicesByMAC() }
        await gate.waitUntilEntered()
        await fixture.store.deduplicateDevicesByMAC()
        #expect(probe.merges.count == 1)
        gate.release()
        await work.value
        #expect(fixture.store.devices.count == 1)
        #expect(!fixture.store.isDeduplicatingDevices)
    }

    @Test func cancellationRetainsTheDuplicate() async throws {
        let probe = MergeProbe()
        let gate = MergeGate()
        probe.gate = gate
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let work = Task { await fixture.store.deduplicateDevicesByMAC() }
        await gate.waitUntilEntered()
        work.cancel()
        gate.release()
        await work.value
        #expect(fixture.store.devices.count == 2)
        #expect(fixture.store.achievementAliases.isEmpty)
        #expect(probe.deletions.isEmpty)
        #expect(fixture.store.achievementMergeProtectedIDs.isEmpty)
    }

    @Test func demoAndMissingMACsDoNotMerge() async throws {
        let probe = MergeProbe()
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        fixture.store.isDemo = true
        await fixture.store.deduplicateDevicesByMAC()
        fixture.store.isDemo = false
        fixture.store.snapshots = [:]
        await fixture.store.deduplicateDevicesByMAC()
        #expect(probe.merges.isEmpty)
        #expect(fixture.store.devices.count == 2)
    }

    @Test func identityResolutionFollowsAliasesAndRejectsCyclesOrMissingTargets() async throws {
        let fixture = try fixture(probe: MergeProbe())
        defer { fixture.cleanUp() }
        let store = fixture.store
        let source = UUID()
        let middle = UUID()
        let target = fixture.devices[0].id
        store.achievementAliases = [source: middle, middle: target]
        #expect(store.achievementDeviceID(for: source) == target)
        store.achievementAliases[target] = source
        #expect(store.achievementDeviceID(for: source) == nil)
        store.achievementAliases = [source: UUID()]
        #expect(store.achievementDeviceID(for: source) == nil)
        store.isDemo = true
        #expect(store.achievementDeviceID(for: target) == nil)
    }

    @Test func explicitRemovalRetainsItsInjectedDeletionBehavior() async throws {
        let probe = MergeProbe()
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let id = fixture.devices[1].id
        fixture.store.remove(fixture.devices[1])
        await probe.waitForDeletion()
        #expect(probe.deletions == [id])
        #expect(!fixture.store.devices.contains { $0.id == id })
        #expect(probe.merges.isEmpty)
    }

    @Test(arguments: [0, 1])
    func removalCannotPurgeAnotherIdentityWhileTransferIsAwaited(victimIndex: Int) async throws {
        let probe = MergeProbe()
        let database = MinerTelemetryDatabase(inMemory: true)
        probe.database = database
        let gate = MergeGate()
        probe.afterMergeGate = gate
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let source = fixture.devices[1].id
        let target = fixture.devices[0].id
        await database.recordAchievement(minerId: source.uuidString, eventType: "best_share", difficulty: "500")
        await database.recordAchievement(minerId: target.uuidString, eventType: "block_found", blockHeight: 100)

        let work = Task { await fixture.store.deduplicateDevicesByMAC() }
        await gate.waitUntilEntered()
        fixture.store.remove(fixture.devices[victimIndex])
        #expect(fixture.store.devices.count == 2)
        #expect(fixture.store.persistenceError != nil)
        if !fixture.store.devices.contains(where: { $0.id == fixture.devices[victimIndex].id }) {
            await probe.waitForDeletion()
        }
        gate.release()
        await work.value
        #expect(fixture.store.devices.map(\.id) == [target])
        let rows = await database.getAchievements(minerId: target.uuidString)
        #expect(Set(rows.map(\.eventType)) == ["best_share", "block_found"])
        #expect(probe.deletions.isEmpty)
        #expect(fixture.store.achievementMergeProtectedIDs.isEmpty)
        fixture.store.remove(fixture.devices[0])
        await probe.waitForDeletion()
        #expect(fixture.store.devices.isEmpty)
        let removed = await database.getAchievements(minerId: target.uuidString)
        #expect(removed.isEmpty)
    }

    @Test func realTransferKeepsQueuedAndLateEventsAndCancelsOnlyDuplicateLiveTask() async throws {
        let probe = MergeProbe()
        let database = MinerTelemetryDatabase(inMemory: true)
        probe.database = database
        let mergeGate = MergeGate()
        probe.gate = mergeGate
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let source = fixture.devices[1].id
        let target = fixture.devices[0].id
        let date = Date(timeIntervalSince1970: 1_000_000)
        for id in [source, target] {
            await database.recordAchievement(
                minerId: id.uuidString, eventType: "best_share", timestamp: date, difficulty: "100")
        }
        await database.recordAchievement(
            minerId: source.uuidString, eventType: "block_found", timestamp: date, blockHeight: 500)
        let sourceGate = MergeGate()
        let targetGate = MergeGate()
        let sourceTask = Task { await sourceGate.pause() }
        let targetTask = Task { await targetGate.pause() }
        store.liveTasks = [source: sourceTask, target: targetTask]
        store.liveConnectedDeviceIDs = [source, target]
        await sourceGate.waitUntilEntered()
        await targetGate.waitUntilEntered()
        let work = Task { await store.deduplicateDevicesByMAC() }
        await mergeGate.waitUntilEntered()
        let queuedID = try #require(store.achievementDeviceID(for: source))
        await database.recordAchievement(
            minerId: queuedID.uuidString, eventType: "queued_event", timestamp: date.addingTimeInterval(1))
        mergeGate.release()
        await work.value
        #expect(store.devices.map(\.id) == [target])
        #expect(sourceTask.isCancelled && !targetTask.isCancelled)
        #expect(store.liveTasks[source] == nil && store.liveTasks[target] != nil)
        #expect(store.liveConnectedDeviceIDs == [target])
        #expect(!store.applyLiveMessage(.text(#"{"data":{"hashRate":9999}}"#), for: source))
        #expect(store.snapshots[source] == nil)
        let lateID = try #require(store.achievementDeviceID(for: source))
        await database.recordAchievement(
            minerId: lateID.uuidString, eventType: "late_event", timestamp: date.addingTimeInterval(2))
        let rows = await database.getAchievements(minerId: target.uuidString)
        #expect(Set(rows.map(\.eventType)) == ["best_share", "block_found", "queued_event", "late_event"])
        #expect(rows.count == 4)
        let sourceRows = await database.getAchievements(minerId: source.uuidString)
        #expect(sourceRows.isEmpty)
        #expect(probe.deletions.isEmpty)
        sourceGate.release()
        targetGate.release()
        await sourceTask.value
        await targetTask.value
        store.liveTasks = [:]
    }

    @Test func actualDemoRoundTripDoesNotRemoveSavedRealIdentities() async throws {
        let probe = MergeProbe()
        let database = MinerTelemetryDatabase(inMemory: true)
        probe.database = database
        let gate = MergeGate()
        probe.gate = gate
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let source = fixture.devices[1].id
        let target = fixture.devices[0].id
        await database.recordAchievement(minerId: source.uuidString, eventType: "block_found", blockHeight: 500)
        let work = Task { await store.deduplicateDevicesByMAC() }
        await gate.waitUntilEntered()
        store.loadDemo()
        let demoIDs = store.devices.map(\.id)
        gate.release()
        await work.value
        #expect(store.isDemo)
        #expect(store.devices.map(\.id) == demoIDs)
        #expect(store.savedDevices == fixture.devices)
        #expect(store.achievementAliases[source] == nil)
        #expect(store.achievementMergeProtectedIDs.isEmpty)
        store.clearDemo()
        #expect(store.devices == fixture.devices)
        store.snapshots = Dictionary(uniqueKeysWithValues: fixture.devices.map {
            ($0.id, snapshot(mac: "AA:BB:CC:11:22:33"))
        })
        probe.gate = nil
        await store.deduplicateDevicesByMAC()
        #expect(store.devices.map(\.id) == [target])
        let rows = await database.getAchievements(minerId: target.uuidString)
        #expect(rows.compactMap(\.blockHeight) == [500])
        #expect(probe.deletions.isEmpty)
    }

    @Test func failedGroupDoesNotBlockAnotherMACAndRetryPreservesBothHistories() async throws {
        let probe = MergeProbe()
        let database = MinerTelemetryDatabase(inMemory: true)
        probe.database = database
        let fixture = try fixture(probe: probe)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let source = fixture.devices[1].id
        probe.failingSourceIDs = [source]
        let otherTarget = MinerDevice(name: "Other target", address: "http://other-target.invalid")
        let otherSource = MinerDevice(name: "Other source", address: "http://other-source.invalid")
        store.devices += [otherTarget, otherSource]
        for device in [otherTarget, otherSource] {
            store.snapshots[device.id] = snapshot(mac: "DD:EE:FF:44:55:66")
        }
        await database.recordAchievement(minerId: source.uuidString, eventType: "block_found", blockHeight: 500)
        await database.recordAchievement(minerId: otherSource.id.uuidString, eventType: "block_found", blockHeight: 600)
        await store.deduplicateDevicesByMAC()
        #expect(store.devices.map(\.id) == [fixture.devices[0].id, source, otherTarget.id])
        #expect(store.achievementAliases[source] == nil)
        #expect(store.achievementDeviceID(for: otherSource.id) == otherTarget.id)
        let unmerged = await database.getAchievements(minerId: source.uuidString)
        #expect(unmerged.compactMap(\.blockHeight) == [500])
        probe.failingSourceIDs = []
        await store.deduplicateDevicesByMAC()
        #expect(store.devices.map(\.id) == [fixture.devices[0].id, otherTarget.id])
        let firstRows = await database.getAchievements(minerId: fixture.devices[0].id.uuidString)
        let otherRows = await database.getAchievements(minerId: otherTarget.id.uuidString)
        #expect(firstRows.compactMap(\.blockHeight) == [500])
        #expect(otherRows.compactMap(\.blockHeight) == [600])
        #expect(store.achievementMergeProtectedIDs.isEmpty)
        #expect(probe.deletions.isEmpty)
    }

    func snapshot(mac: String) -> MinerSnapshot {
        MinerSnapshot(info: MinerInfo(raw: ["macAddr": .string(mac)]))
    }

    func fixture(probe: MergeProbe) throws -> Fixture {
        let suite = "app.hashfleet.tests.dedup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let devices = [
            MinerDevice(name: "Survivor", address: "http://survivor.invalid"),
            MinerDevice(name: "Duplicate", address: "http://duplicate.invalid")
        ]
        let store = FleetStore(
            defaults: defaults,
            achievementMerger: { source, target in
                probe.merges.append((source, target))
                probe.devicesPresentDuringMerge.append(probe.store?.devices.count ?? 0)
                if let gate = probe.gate { await gate.pause() }
                if probe.shouldFail || probe.failingSourceIDs.contains(source) { throw MergeFailure.injected }
                if let database = probe.database {
                    _ = try await database.mergeAchievementsChecked(
                        fromMinerId: source.uuidString, intoMinerId: target.uuidString)
                }
                if let gate = probe.afterMergeGate { await gate.pause() }
            },
            achievementDeletion: { id in
                if let database = probe.database {
                    await database.deleteAchievements(minerId: id.uuidString)
                }
                probe.recordDeletion(id)
            }
        )
        probe.store = store
        store.isDemo = false
        store.preferences.telemetryStorageEnabled = false
        store.preferences.externalDataEnabled = false
        store.devices = devices
        store.snapshots = Dictionary(uniqueKeysWithValues: devices.map {
            ($0.id, snapshot(mac: "AA:BB:CC:11:22:33"))
        })
        return Fixture(store: store, devices: devices, defaults: defaults, suite: suite)
    }

    @MainActor struct Fixture {
        let store: FleetStore
        let devices: [MinerDevice]
        let defaults: UserDefaults
        let suite: String
        func cleanUp() { defaults.removePersistentDomain(forName: suite) }
    }

    enum MergeFailure: Error { case injected }

    @MainActor final class MergeProbe {
        weak var store: FleetStore?
        var merges: [(UUID, UUID)] = []
        var devicesPresentDuringMerge: [Int] = []
        var deletions: [UUID] = []
        var shouldFail = false
        var failingSourceIDs: Set<UUID> = []
        var gate: MergeGate?
        var afterMergeGate: MergeGate?
        var database: MinerTelemetryDatabase?
        var deletionWaiter: CheckedContinuation<Void, Never>?
        func recordDeletion(_ id: UUID) {
            deletions.append(id)
            deletionWaiter?.resume()
            deletionWaiter = nil
        }
        func waitForDeletion() async {
            if !deletions.isEmpty { return }
            await withCheckedContinuation { deletionWaiter = $0 }
        }
    }

    @MainActor final class MergeGate {
        var entered = false
        var entryWaiter: CheckedContinuation<Void, Never>?
        var resumeWaiter: CheckedContinuation<Void, Never>?
        func pause() async {
            entered = true
            entryWaiter?.resume()
            entryWaiter = nil
            await withCheckedContinuation { resumeWaiter = $0 }
        }
        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { entryWaiter = $0 }
        }
        func release() {
            resumeWaiter?.resume()
            resumeWaiter = nil
        }
    }
}
