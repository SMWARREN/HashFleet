import Foundation
import Testing
@testable import HashFleetWatchCore

@MainActor
@Suite struct WatchFleetStoreTests {
    // MARK: Configuration

    @Test func addPersistsAndReloads() throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        let store = WatchFleetStore(storageURL: url, client: ScriptedClient())
        try store.addMiner(name: " Gamma ", address: "192.168.1.20")
        #expect(store.miners.map(\.name) == ["Gamma"])
        let reloaded = WatchFleetStore(storageURL: url, client: ScriptedClient())
        #expect(reloaded.miners == store.miners)
        #expect(reloaded.storageError == nil)
    }

    @Test func rejectsInvalidDuplicateAndOverCapacity() throws {
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        #expect(throws: WatchMinerValidationError.notLocalAddress) { try store.addMiner(name: "x", address: "8.8.8.8") }
        try store.addMiner(name: "a", address: "192.168.1.1")
        #expect(throws: WatchFleetStoreError.duplicateMiner) { try store.addMiner(name: "b", address: "http://192.168.1.1:80/") }
        for n in 2...16 { try store.addMiner(name: "m\(n)", address: "192.168.1.\(n)") }
        #expect(store.miners.count == 16)
        #expect(throws: WatchFleetStoreError.limitReached) { try store.addMiner(name: "x", address: "192.168.1.99") }
        #expect(store.miners.count == 16)
    }

    @Test func removeDeletesMinerAndCache() async throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        let store = WatchFleetStore(storageURL: url, client: ScriptedClient())
        try store.addMiner(name: "a", address: "192.168.1.1")
        try store.addMiner(name: "b", address: "192.168.1.2")
        await store.refresh()
        let removed = store.miners[0]
        try store.removeMiner(id: removed.id)
        #expect(store.miners.count == 1)
        #expect(store.readings[removed.id] == nil)
        #expect(store.failures[removed.id] == nil)
        let reloaded = WatchFleetStore(storageURL: url, client: ScriptedClient())
        #expect(reloaded.miners.count == 1)
        #expect(reloaded.readings[removed.id] == nil)
        #expect(throws: WatchFleetStoreError.minerNotFound) { try store.removeMiner(id: removed.id) }
    }

    // MARK: Persistence

    @Test func saveFailureDoesNotAcceptMutation() throws {
        // A file where the parent directory should be makes every save fail.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let store = WatchFleetStore(storageURL: blocker.appendingPathComponent("sub/fleet.json"), client: ScriptedClient())
        #expect(throws: WatchFleetStoreError.persistenceFailed) { try store.addMiner(name: "a", address: "192.168.1.1") }
        #expect(store.miners.isEmpty)
        #expect(throws: WatchFleetStoreError.persistenceFailed) {
            try store.importMiners([try WatchMiner(name: "a", address: "192.168.1.2")])
        }
        #expect(store.miners.isEmpty)
    }

    @Test func removeSaveFailureKeepsMiner() throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        let store = WatchFleetStore(storageURL: url, client: ScriptedClient())
        try store.addMiner(name: "a", address: "192.168.1.1")
        // Replace the file's directory with a plain file so the next save fails.
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
        try Data("x".utf8).write(to: url.deletingLastPathComponent())
        #expect(throws: WatchFleetStoreError.persistenceFailed) { try store.removeMiner(id: store.miners[0].id) }
        #expect(store.miners.count == 1)
    }

    @Test(arguments: [
        "not json at all",
        "{}",
        #"{"version":99,"miners":[],"readings":[]}"#,
        #"{"version":1,"miners":[{"id":"00000000-0000-0000-0000-000000000001","name":"x","address":"http://8.8.8.8"}],"readings":[]}"#,
        #"{"version":1,"miners":[],"readings":[{"minerID":"00000000-0000-0000-0000-000000000009","observedAt":1}]}"#
    ])
    func corruptStorageIsSetAsideAndReported(content: String) throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        let store = WatchFleetStore(storageURL: url, client: ScriptedClient())
        #expect(store.miners.isEmpty)
        #expect(store.storageError != nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // A usable store afterwards.
        try store.addMiner(name: "a", address: "192.168.1.1")
        #expect(store.storageError == nil)
        #expect(WatchFleetStore(storageURL: url, client: ScriptedClient()).miners.count == 1)
    }

    @Test func persistedFileHoldsNoSecretsOrRawFields() async throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        let store = WatchFleetStore(storageURL: url, client: ScriptedClient())
        try store.addMiner(name: "a", address: "192.168.1.1")
        await store.refresh()
        let text = try #require(String(bytes: Data(contentsOf: url), encoding: .utf8))
        for forbidden in ["password", "stratum", "ssid", "wallet", "token", "mac"] {
            #expect(!text.lowercased().contains(forbidden))
        }
    }

    // MARK: Refresh and cached timestamps

    @Test func failurePreservesOriginalReadingTimeAcrossRelaunch() async throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        let client = ScriptedClient()
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        await client.setObservedAt(original)
        let store = WatchFleetStore(storageURL: url, client: client)
        try store.addMiner(name: "a", address: "192.168.1.1")
        await store.refresh()
        let id = store.miners[0].id
        #expect(store.readings[id]?.observedAt == original)

        await client.setDefault(.fail)
        await store.refresh()
        #expect(store.readings[id]?.observedAt == original)
        #expect(store.readings[id]?.hashrateGHs == 500)
        #expect(store.failures[id] != nil)

        let reloaded = WatchFleetStore(storageURL: url, client: client)
        #expect(reloaded.readings[id]?.observedAt == original)
        #expect(reloaded.failures.isEmpty)
    }

    @Test func successClearsPreviousFailure() async throws {
        let client = ScriptedClient(default: .fail)
        let store = WatchFleetStore(storageURL: nil, client: client)
        try store.addMiner(name: "a", address: "192.168.1.1")
        await store.refresh()
        let id = store.miners[0].id
        #expect(store.failures[id] != nil)
        #expect(store.readings[id] == nil)
        await client.setDefault(.succeed(hashrate: 3))
        await store.refresh()
        #expect(store.failures[id] == nil)
        #expect(store.readings[id]?.hashrateGHs == 3)
    }

    @Test func failureOfOneMinerDoesNotAffectOthers() async throws {
        let client = ScriptedClient()
        await client.set(.fail, for: "http://192.168.1.2")
        let store = WatchFleetStore(storageURL: nil, client: client)
        try store.addMiner(name: "a", address: "192.168.1.1")
        try store.addMiner(name: "b", address: "192.168.1.2")
        await store.refresh()
        #expect(store.readings[store.miners[0].id] != nil)
        #expect(store.failures[store.miners[0].id] == nil)
        #expect(store.readings[store.miners[1].id] == nil)
        #expect(store.failures[store.miners[1].id] != nil)
    }

    @Test func olderReadingNeverReplacesNewer() async throws {
        let client = ScriptedClient()
        let store = WatchFleetStore(storageURL: nil, client: client)
        try store.addMiner(name: "a", address: "192.168.1.1")
        await client.setObservedAt(Date(timeIntervalSince1970: 2_000))
        await store.refresh()
        await client.setObservedAt(Date(timeIntervalSince1970: 1_000))
        await client.setDefault(.succeed(hashrate: 1))
        await store.refresh()
        #expect(store.readings[store.miners[0].id]?.observedAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test func emptyFleetRefreshDoesNothing() async {
        let client = ScriptedClient()
        let store = WatchFleetStore(storageURL: nil, client: client)
        await store.refresh()
        #expect(await client.fetchCount() == 0)
        #expect(!store.isRefreshing)
    }

    // MARK: Concurrency

    @Test func removedMinerNeverReappearsFromLateResponse() async throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        let client = ScriptedClient()
        await client.hold("http://192.168.1.1")
        let store = WatchFleetStore(storageURL: url, client: client)
        try store.addMiner(name: "a", address: "192.168.1.1")
        let id = store.miners[0].id
        let refresh = Task { await store.refresh() }
        while !(await client.isWaiting("http://192.168.1.1")) { await Task.yield() }
        try store.removeMiner(id: id)
        await client.release("http://192.168.1.1")
        await refresh.value
        #expect(store.miners.isEmpty)
        #expect(store.readings[id] == nil)
        #expect(store.failures[id] == nil)
        #expect(WatchFleetStore(storageURL: url, client: client).readings[id] == nil)
    }

    @Test func lateFailureForRemovedMinerIsIgnored() async throws {
        let client = ScriptedClient(default: .fail)
        await client.hold("http://192.168.1.1")
        let store = WatchFleetStore(storageURL: nil, client: client)
        try store.addMiner(name: "a", address: "192.168.1.1")
        let id = store.miners[0].id
        let refresh = Task { await store.refresh() }
        while !(await client.isWaiting("http://192.168.1.1")) { await Task.yield() }
        try store.removeMiner(id: id)
        await client.release("http://192.168.1.1")
        await refresh.value
        #expect(store.failures[id] == nil)
    }

    @Test func concurrentRefreshesCoalesceIntoOnePass() async throws {
        let client = ScriptedClient()
        await client.hold("http://192.168.1.1")
        let store = WatchFleetStore(storageURL: nil, client: client)
        try store.addMiner(name: "a", address: "192.168.1.1")
        let first = Task { await store.refresh() }
        while !(await client.isWaiting("http://192.168.1.1")) { await Task.yield() }
        #expect(store.isRefreshing)
        let second = Task { await store.refresh() }
        let third = Task { await store.refresh() }
        await Task.yield()
        await client.release("http://192.168.1.1")
        await first.value; await second.value; await third.value
        #expect(await client.fetchCount() == 1)
        #expect(!store.isRefreshing)
    }

    @Test func refreshConcurrencyIsBounded() async throws {
        let client = ScriptedClient()
        let store = WatchFleetStore(storageURL: nil, client: client)
        for n in 1...16 { try store.addMiner(name: "m\(n)", address: "192.168.1.\(n)") }
        await store.refresh()
        #expect(await client.fetchCount() == 16)
        #expect(await client.peakConcurrency() <= WatchFleetStore.refreshConcurrency)
        #expect(store.readings.count == 16)
    }

    @Test func cancellationDoesNotFabricateFailures() async throws {
        let client = ScriptedClient(default: .hang)
        let store = WatchFleetStore(storageURL: nil, client: client)
        try store.addMiner(name: "a", address: "192.168.1.1")
        try store.addMiner(name: "b", address: "192.168.1.2")
        let refresh = Task { await store.refresh() }
        while await client.fetchCount() < 2 { await Task.yield() }
        refresh.cancel()
        await refresh.value
        #expect(store.failures.isEmpty)
        #expect(store.readings.isEmpty)
        #expect(!store.isRefreshing)
        // The store remains usable afterwards.
        await client.setDefault(.succeed(hashrate: 4))
        await store.refresh()
        #expect(store.readings.count == 2)
    }

    // MARK: Import

    private func incoming(_ n: Int, id: UUID = UUID(), name: String? = nil) throws -> WatchMiner {
        try WatchMiner(id: id, name: name ?? "in\(n)", address: "192.168.1.\(n)")
    }

    @Test func importAppendsOnlyMissingEndpoints() async throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        let client = ScriptedClient()
        let store = WatchFleetStore(storageURL: url, client: client)
        try store.addMiner(name: "local one", address: "192.168.1.1")
        await store.refresh()
        let before = store.miners
        let cachedBefore = store.readings

        let added = try store.importMiners([try incoming(1, name: "renamed"), try incoming(2), try incoming(3)])
        #expect(added == 2)
        #expect(Array(store.miners.prefix(1)) == before)
        #expect(store.miners.first?.name == "local one")
        #expect(store.readings == cachedBefore)
        #expect(store.miners.map(\.address) == ["http://192.168.1.1", "http://192.168.1.2", "http://192.168.1.3"])
        #expect(WatchFleetStore(storageURL: url, client: client).miners == store.miners)
        #expect(try store.importMiners([try incoming(2)]) == 0)
    }

    @Test func importDeduplicatesWithinIncoming() throws {
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        let added = try store.importMiners([try incoming(5), try incoming(5, name: "dup")])
        #expect(added == 1)
        #expect(store.miners.count == 1)
    }

    @Test func importGivesFreshIdentifierOnCollisionWithOtherEndpoint() throws {
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        try store.addMiner(name: "mine", address: "192.168.1.1")
        let collidingID = store.miners[0].id
        let added = try store.importMiners([try incoming(2, id: collidingID)])
        #expect(added == 1)
        #expect(store.miners.count == 2)
        #expect(Set(store.miners.map(\.id)).count == 2)
        #expect(store.miners[0].id == collidingID)
        #expect(store.miners[1].id != collidingID)
        #expect(store.miners[1].address == "http://192.168.1.2")
    }

    @Test func importKeepsIncomingIdentifierWhenFree() throws {
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        let wanted = UUID()
        try store.importMiners([try incoming(2, id: wanted)])
        #expect(store.miners[0].id == wanted)
    }

    @Test func importOverCapacityIsAtomic() throws {
        let url = temporaryStorageURL(); defer { cleanUp(url) }
        let store = WatchFleetStore(storageURL: url, client: ScriptedClient())
        for n in 1...14 { try store.addMiner(name: "m\(n)", address: "192.168.1.\(n)") }
        let before = store.miners
        #expect(throws: WatchFleetStoreError.limitReached) {
            try store.importMiners([try incoming(100), try incoming(101), try incoming(102)])
        }
        #expect(store.miners == before)
        #expect(WatchFleetStore(storageURL: url, client: ScriptedClient()).miners == before)
        // Duplicates of existing endpoints do not count against capacity.
        #expect(try store.importMiners([try incoming(1), try incoming(100), try incoming(101)]) == 2)
        #expect(store.miners.count == 16)
    }

    @Test func importFromValidatedTransfer() throws {
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        let transfer = try WatchFleetSetupTransfer(miners: [incoming(7), incoming(8)])
        #expect(try store.importMiners(transfer.miners) == 2)
    }

    // MARK: Demo

    @Test func demoIsIsolatedReadOnlyAndNeverContactsMiners() async throws {
        let demo = WatchFleetStore.demo()
        #expect(demo.isDemo)
        #expect(!demo.miners.isEmpty)
        #expect(demo.readings.count == demo.miners.count)
        #expect(throws: WatchFleetStoreError.demoIsReadOnly) { try demo.addMiner(name: "x", address: "192.168.1.1") }
        #expect(throws: WatchFleetStoreError.demoIsReadOnly) { try demo.removeMiner(id: demo.miners[0].id) }
        #expect(throws: WatchFleetStoreError.demoIsReadOnly) { try demo.importMiners([try incoming(1)]) }
        await demo.refresh()
        #expect(demo.failures.isEmpty)
        #expect(demo.readings.values.allSatisfy { !$0.isStale(at: Date()) })
        // Demo never writes to the default storage location.
        let stored = WatchFleetStore.defaultStorageURL
        let before = stored.flatMap { try? Data(contentsOf: $0) }
        _ = WatchFleetStore.demo()
        #expect(stored.flatMap { try? Data(contentsOf: $0) } == before)
    }
}
