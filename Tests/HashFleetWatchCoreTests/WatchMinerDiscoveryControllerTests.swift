import Foundation
import Testing
@testable import HashFleetWatchCore

@MainActor
@Suite struct WatchMinerDiscoveryControllerTests {
    private func result(_ miners: [WatchMiner] = [], partial: Bool = false, timedOut: Bool = false) -> WatchDiscoveryResult {
        WatchDiscoveryResult(miners: miners, completedHosts: timedOut ? 12 : 253, totalHosts: 253, isPartialSubnet: partial, reachedTimeLimit: timedOut)
    }

    @Test func automaticallyAddsAndPersistsWithoutReadingOrPhone() async throws {
        let url = temporaryStorageURL()
        defer { cleanUp(url) }
        let miners = [try WatchMiner(name: "Gamma", address: "192.168.1.31"), try WatchMiner(name: "Duo", address: "192.168.1.32")]
        let scanner = ControllerDiscoveryStub(result: result(miners))
        let reader = ScriptedClient()
        let store = WatchFleetStore(storageURL: url, client: reader)
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        controller.startAutomaticallyIfNeeded(store: store)
        await controller.waitForCurrentScan()
        #expect(store.miners == miners)
        #expect(controller.addedCount == 2)
        #expect(!controller.isScanning)
        #expect(await reader.fetchCount() == 0, "Inventory discovery must not own the readings polling loop")
        #expect(WatchFleetStore(storageURL: url, client: reader).miners == miners)
    }

    @Test func emptyResultRunsAutomaticallyOnlyOnceButAllowsExplicitRetry() async {
        let scanner = ControllerDiscoveryStub(result: result())
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        controller.startAutomaticallyIfNeeded(store: store)
        await controller.waitForCurrentScan()
        controller.startAutomaticallyIfNeeded(store: store)
        controller.startAutomaticallyIfNeeded(store: store)
        #expect(await scanner.callCount == 1)
        #expect(controller.message?.contains("No compatible miners found") == true)
        controller.start(store: store)
        await controller.waitForCurrentScan()
        #expect(await scanner.callCount == 2)
    }

    @Test func existingFleetAndItsLaterRemovalDoNotStartAnAutomaticScan() async throws {
        let scanner = ControllerDiscoveryStub(result: result())
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        try store.addMiner(name: "Saved", address: "192.168.1.31")
        controller.startAutomaticallyIfNeeded(store: store)
        try store.removeMiner(id: store.miners[0].id)
        controller.startAutomaticallyIfNeeded(store: store)
        #expect(await scanner.callCount == 0)
        #expect(store.miners.isEmpty)
    }

    @Test func demoNeverStartsDiscoveryEvenOnExplicitRequest() async {
        let scanner = ControllerDiscoveryStub(result: result())
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        let store = WatchFleetStore.demo()
        let before = store.miners
        controller.startAutomaticallyIfNeeded(store: store)
        controller.start(store: store)
        #expect(await scanner.callCount == 0)
        #expect(store.miners == before)
        #expect(!controller.isScanning)
    }

    @Test func rescanningDeduplicatesWithoutRenamingOrReplacingReadings() async throws {
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        try store.addMiner(name: "My custom label", address: "192.168.1.31")
        await store.refresh()
        let original = store.miners[0]
        let oldReading = store.readings[original.id]
        let duplicate = try WatchMiner(name: "Different remote label", address: "192.168.1.31")
        let addition = try WatchMiner(name: "Duo", address: "192.168.1.32")
        let scanner = ControllerDiscoveryStub(result: result([duplicate, addition, addition]))
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        controller.start(store: store)
        await controller.waitForCurrentScan()
        #expect(store.miners == [original, addition])
        #expect(store.readings[original.id] == oldReading)
        #expect(controller.addedCount == 1)
        #expect(controller.foundCount == 2)
        controller.start(store: store)
        await controller.waitForCurrentScan()
        #expect(store.miners == [original, addition])
        #expect(controller.addedCount == 0)
    }

    @Test func limitsAdditionsToRemainingCapacityAndExplainsIt() async throws {
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        for n in 1...14 { try store.addMiner(name: "Existing \(n)", address: "192.168.1.\(n)") }
        let before = store.miners
        let found = try (31...35).map { try WatchMiner(name: "Found \($0)", address: "192.168.1.\($0)") }
        let controller = WatchMinerDiscoveryController(discovery: ControllerDiscoveryStub(result: result(found)))
        controller.start(store: store)
        await controller.waitForCurrentScan()
        #expect(store.miners.count == 16)
        #expect(Array(store.miners.prefix(14)) == before)
        #expect(controller.addedCount == 2)
        #expect(controller.message?.contains("up to 16") == true)
    }

    @Test func failedSaveDoesNotAcceptDiscoveredMiners() async throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("discovery-blocker-\(UUID())")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let store = WatchFleetStore(storageURL: blocker.appendingPathComponent("child/fleet.json"), client: ScriptedClient())
        let found = [try WatchMiner(name: "Gamma", address: "192.168.1.31")]
        let controller = WatchMinerDiscoveryController(discovery: ControllerDiscoveryStub(result: result(found)))
        controller.start(store: store)
        await controller.waitForCurrentScan()
        #expect(store.miners.isEmpty)
        #expect(controller.addedCount == nil)
        #expect(controller.message?.contains("couldn't save") == true)
    }

    @Test func partialSearchIsExplicitWithoutInventingOfflineStatus() async throws {
        let found = [try WatchMiner(name: "Gamma", address: "192.168.1.31")]
        let controller = WatchMinerDiscoveryController(discovery: ControllerDiscoveryStub(result: result(found, partial: true, timedOut: true)))
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        controller.start(store: store)
        await controller.waitForCurrentScan()
        #expect(controller.isPartialSubnet)
        #expect(controller.reachedTimeLimit)
        #expect(controller.completedHosts == 12)
        #expect(controller.totalHosts == 253)
        #expect(store.failures.isEmpty)
    }

    @Test func unrelatedErrorNeverLeaksSystemErrorOrAddress() async {
        let scanner = ControllerDiscoveryStub(result: result(), failure: NSError(domain: "secret.example 192.168.1.31 wallet", code: 9))
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        controller.start(store: store)
        await controller.waitForCurrentScan()
        #expect(controller.message?.contains("couldn't finish") == true)
        #expect(controller.message?.contains("192.168") == false)
        #expect(controller.message?.contains("wallet") == false)
        #expect(store.miners.isEmpty)
    }

    @Test func cancellationAndOldCallbacksCannotMutateANewerScan() async throws {
        let old = try WatchMiner(name: "Old scan", address: "192.168.1.31")
        let new = try WatchMiner(name: "New scan", address: "192.168.1.32")
        let scanner = ControllerDiscoveryStub(result: result(), isGated: true)
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        controller.startAutomaticallyIfNeeded(store: store)
        try await scanner.waitForCalls(1)
        controller.start(store: store)
        #expect(await scanner.callCount == 1, "A repeated action must not overlap a scan")
        controller.cancel()
        #expect(!controller.isScanning)
        #expect(store.miners.isEmpty)
        controller.start(store: store)
        try await scanner.waitForCalls(2)
        await scanner.report(WatchDiscoveryProgress(miners: [old], completedHosts: 200, totalHosts: 253, isPartialSubnet: true), call: 0)
        #expect(controller.completedHosts == 0)
        #expect(controller.foundCount == 0)
        await scanner.complete(result([old]), call: 0)
        await scanner.complete(result([new]), call: 1)
        await controller.waitForCurrentScan()
        #expect(store.miners == [new])
        #expect(controller.addedCount == 1)
    }

    @Test func removingASavedMinerWhileScanningDoesNotReAddIt() async throws {
        let old = try WatchMiner(name: "Remove me", address: "192.168.1.31")
        let new = try WatchMiner(name: "Keep me", address: "192.168.1.32")
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        try store.importMiners([old])
        let scanner = ControllerDiscoveryStub(result: result(), isGated: true)
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        controller.start(store: store)
        try await scanner.waitForCalls(1)
        try store.removeMiner(id: old.id)
        await scanner.complete(result([old, new]), call: 0)
        await controller.waitForCurrentScan()
        #expect(store.miners == [new])
    }

    @Test func manuallyAddedEntryDuringScanKeepsItsOwnName() async throws {
        let remote = try WatchMiner(name: "Remote label", address: "192.168.1.31")
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        let scanner = ControllerDiscoveryStub(result: result(), isGated: true)
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        controller.start(store: store)
        try await scanner.waitForCalls(1)
        try store.addMiner(name: "My label", address: "192.168.1.31")
        let manual = store.miners[0]
        await scanner.complete(result([remote]), call: 0)
        await controller.waitForCurrentScan()
        #expect(store.miners == [manual])
        #expect(controller.addedCount == 0)
    }

    @Test func backgroundSavesValidatedProgressAndAutomaticallyRetriesWithoutDuplicates() async throws {
        let url = temporaryStorageURL()
        defer { cleanUp(url) }
        let found = try WatchMiner(name: "Found before wrist down", address: "192.168.1.31")
        let later = try WatchMiner(name: "Found after return", address: "192.168.1.32")
        let scanner = ControllerDiscoveryStub(result: result(), isGated: true)
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        let store = WatchFleetStore(storageURL: url, client: ScriptedClient())
        controller.startAutomaticallyIfNeeded(store: store)
        try await scanner.waitForCalls(1)
        await scanner.report(WatchDiscoveryProgress(miners: [found], completedHosts: 42, totalHosts: 253, isPartialSubnet: false), call: 0)
        controller.suspendForBackground(store: store)
        #expect(controller.isPaused)
        #expect(!controller.isScanning)
        #expect(store.miners == [found])
        #expect(WatchFleetStore(storageURL: url, client: ScriptedClient()).miners == [found])
        controller.startAutomaticallyIfNeeded(store: store)
        try await scanner.waitForCalls(2)
        #expect(!controller.isPaused)
        #expect(controller.isScanning)
        await scanner.report(WatchDiscoveryProgress(miners: [later], completedHosts: 253, totalHosts: 253, isPartialSubnet: false), call: 0)
        #expect(controller.completedHosts == 0, "Old callbacks must not affect the retry")
        await scanner.complete(result([later]), call: 0)
        await scanner.complete(result([found, later]), call: 1)
        await controller.waitForCurrentScan()
        #expect(store.miners == [found, later])
        #expect(controller.addedCount == 1)
    }

    @Test func explicitStopAfterBackgroundPausePreventsAutomaticRetry() async throws {
        let scanner = ControllerDiscoveryStub(result: result(), isGated: true)
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        controller.start(store: store)
        try await scanner.waitForCalls(1)
        controller.suspendForBackground(store: store)
        controller.cancel()
        controller.startAutomaticallyIfNeeded(store: store)
        #expect(!controller.isPaused)
        #expect(!controller.isScanning)
        #expect(await scanner.callCount == 1)
        await scanner.complete(result(), call: 0)
    }

    @Test func backgroundProgressDoesNotReAddRemovedMinerOrOverwriteManualName() async throws {
        let old = try WatchMiner(name: "Remove", address: "192.168.1.31")
        let remote = try WatchMiner(name: "Remote", address: "192.168.1.32")
        let scanner = ControllerDiscoveryStub(result: result(), isGated: true)
        let controller = WatchMinerDiscoveryController(discovery: scanner)
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        try store.importMiners([old])
        controller.start(store: store)
        try await scanner.waitForCalls(1)
        try store.removeMiner(id: old.id)
        try store.addMiner(name: "My label", address: remote.address)
        let manual = store.miners[0]
        await scanner.report(WatchDiscoveryProgress(miners: [old, remote], completedHosts: 42, totalHosts: 253, isPartialSubnet: false), call: 0)
        controller.suspendForBackground(store: store)
        #expect(store.miners == [manual])
        controller.cancel()
        await scanner.complete(result(), call: 0)
    }
}

@MainActor
@Suite struct WatchFleetActivityTests {
    private func emptyResult() -> WatchDiscoveryResult {
        WatchDiscoveryResult(miners: [], completedHosts: 253, totalHosts: 253, isPartialSubnet: false, reachedTimeLimit: false)
    }

    @Test func wristDownDoesNotStopOrRestartAnOngoingSearch() async throws {
        let scanner = ControllerDiscoveryStub(result: emptyResult(), isGated: true)
        let discovery = WatchMinerDiscoveryController(discovery: scanner)
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        let activity = WatchFleetActivity()
        activity.update(phase: .inactive, store: store, discovery: discovery)
        #expect(!activity.isPolling, "Inactive launch is not permission to start new work")
        activity.update(phase: .active, store: store, discovery: discovery)
        try await scanner.waitForCalls(1)
        activity.update(phase: .inactive, store: store, discovery: discovery)
        #expect(discovery.isScanning)
        #expect(!discovery.isPaused)
        #expect(activity.isPolling)
        activity.update(phase: .active, store: store, discovery: discovery)
        #expect(await scanner.callCount == 1)
        await scanner.complete(emptyResult(), call: 0)
        await discovery.waitForCurrentScan()
        activity.update(phase: .background, store: store, discovery: discovery)
        await activity.waitForStoppedPolling()
    }

    @Test func backgroundPausesSearchButReturnRestartsItAndExplicitStopDoesNot() async throws {
        let scanner = ControllerDiscoveryStub(result: emptyResult(), isGated: true)
        let discovery = WatchMinerDiscoveryController(discovery: scanner)
        let store = WatchFleetStore(storageURL: nil, client: ScriptedClient())
        let activity = WatchFleetActivity()
        activity.update(phase: .active, store: store, discovery: discovery)
        try await scanner.waitForCalls(1)
        activity.update(phase: .background, store: store, discovery: discovery)
        await activity.waitForStoppedPolling()
        #expect(discovery.isPaused)
        #expect(!activity.isPolling)
        activity.update(phase: .active, store: store, discovery: discovery)
        try await scanner.waitForCalls(2)
        #expect(discovery.isScanning)
        discovery.cancel()
        activity.update(phase: .background, store: store, discovery: discovery)
        activity.update(phase: .active, store: store, discovery: discovery)
        #expect(await scanner.callCount == 2)
        #expect(!discovery.isScanning)
        await scanner.complete(emptyResult(), call: 0)
        await scanner.complete(emptyResult(), call: 1)
        activity.update(phase: .background, store: store, discovery: discovery)
        await activity.waitForStoppedPolling()
    }

    @Test(.timeLimit(.minutes(1))) func repeatedReadsContinueFrontmostAndRefreshImmediatelyOnReturn() async throws {
        let reader = ScriptedClient()
        let store = WatchFleetStore(storageURL: nil, client: reader)
        try store.addMiner(name: "Continuous", address: "192.168.1.31")
        let discovery = WatchMinerDiscoveryController(discovery: ControllerDiscoveryStub(result: emptyResult()))
        let activity = WatchFleetActivity()
        activity.update(phase: .active, store: store, discovery: discovery)
        defer { activity.update(phase: .background, store: store, discovery: discovery) }
        try await waitForReads(1, reader: reader)
        let first = try #require(store.readings.values.first?.observedAt)
        activity.update(phase: .inactive, store: store, discovery: discovery)
        try await waitForReads(2, reader: reader, timeout: .seconds(15))
        let second = try #require(store.readings.values.first?.observedAt)
        #expect(second.timeIntervalSince(first) >= 9.9)
        activity.update(phase: .active, store: store, discovery: discovery)
        try await waitForReads(3, reader: reader)
        let third = try #require(store.readings.values.first?.observedAt)
        #expect(third > second)
        #expect(third.timeIntervalSince(second) < 3, "Waking the Watch must not wait another timer interval")
        try await waitForReads(4, reader: reader, timeout: .seconds(15))
        #expect(store.readings.values.first!.observedAt > third)
        activity.update(phase: .background, store: store, discovery: discovery)
        await activity.waitForStoppedPolling()
        let count = await reader.fetchCount()
        try await Task.sleep(for: .milliseconds(40))
        #expect(await reader.fetchCount() == count)
        #expect(await reader.peakConcurrency() == 1)
        #expect(store.failures.isEmpty)
    }

    @Test func inventoryChangeReadsNewMinersWithoutWaitingForTimer() async throws {
        let reader = ScriptedClient()
        let store = WatchFleetStore(storageURL: nil, client: reader)
        let discovery = WatchMinerDiscoveryController(discovery: ControllerDiscoveryStub(result: emptyResult()))
        let activity = WatchFleetActivity()
        activity.update(phase: .active, store: store, discovery: discovery)
        await discovery.waitForCurrentScan()
        try store.addMiner(name: "New", address: "192.168.1.31")
        activity.inventoryDidChange(store: store)
        try await waitForReads(1, reader: reader)
        #expect(store.readings.count == 1)
        activity.update(phase: .background, store: store, discovery: discovery)
        await activity.waitForStoppedPolling()
    }

    @Test func demoStopsRealLoopAndNeverPollsOrScans() async throws {
        let reader = ScriptedClient()
        let store = WatchFleetStore(storageURL: nil, client: reader)
        try store.addMiner(name: "Real", address: "192.168.1.31")
        let scanner = ControllerDiscoveryStub(result: emptyResult())
        let discovery = WatchMinerDiscoveryController(discovery: scanner)
        let activity = WatchFleetActivity()
        activity.update(phase: .active, store: store, discovery: discovery)
        try await waitForReads(1, reader: reader)
        let demo = WatchFleetStore.demo()
        let before = demo.readings
        activity.update(phase: .active, store: demo, discovery: discovery)
        await activity.waitForStoppedPolling()
        activity.inventoryDidChange(store: demo)
        #expect(!activity.isPolling)
        #expect(demo.readings == before)
        #expect(await scanner.callCount == 0)
    }

    @Test func fastBackgroundReturnWaitsForCancelledPassBeforeFreshRead() async throws {
        let reader = ScriptedClient(default: .hang)
        let store = WatchFleetStore(storageURL: nil, client: reader)
        try store.addMiner(name: "Return", address: "192.168.1.31")
        let discovery = WatchMinerDiscoveryController(discovery: ControllerDiscoveryStub(result: emptyResult()))
        let activity = WatchFleetActivity()
        activity.update(phase: .active, store: store, discovery: discovery)
        try await waitForReads(1, reader: reader)
        await reader.setDefault(.succeed(hashrate: 700))
        activity.update(phase: .background, store: store, discovery: discovery)
        activity.update(phase: .active, store: store, discovery: discovery)
        try await waitForReads(2, reader: reader)
        #expect(store.readings.values.first?.hashrateGHs == 700)
        #expect(store.failures.isEmpty)
        #expect(await reader.peakConcurrency() == 1)
        activity.update(phase: .background, store: store, discovery: discovery)
        await activity.waitForStoppedPolling()
    }

    private func waitForReads(_ count: Int, reader: ScriptedClient, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now + timeout
        while await reader.fetchCount() < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await reader.fetchCount() >= count)
        await Task.yield()
    }
}

/// Tests may deliberately deliver a cancelled scan's progress/result to exercise generation guards.
private actor ControllerDiscoveryStub: WatchMinerDiscovering {
    let result: WatchDiscoveryResult
    let failure: (any Error)?
    let isGated: Bool
    private(set) var callCount = 0
    private var callbacks: [Int: @Sendable (WatchDiscoveryProgress) async -> Void] = [:]
    private var gates: [Int: CheckedContinuation<WatchDiscoveryResult, any Error>] = [:]

    init(result: WatchDiscoveryResult, failure: (any Error)? = nil, isGated: Bool = false) {
        self.result = result
        self.failure = failure
        self.isGated = isGated
    }

    func scan(onProgress: @escaping @Sendable (WatchDiscoveryProgress) async -> Void) async throws -> WatchDiscoveryResult {
        let call = callCount
        callCount += 1
        callbacks[call] = onProgress
        if let failure { throw failure }
        if isGated {
            return try await withCheckedThrowingContinuation { gates[call] = $0 }
        }
        await onProgress(WatchDiscoveryProgress(miners: result.miners, completedHosts: result.completedHosts, totalHosts: result.totalHosts, isPartialSubnet: result.isPartialSubnet))
        return result
    }

    func waitForCalls(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while callCount < count && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        guard callCount >= count else { throw CancellationError() }
    }

    func report(_ progress: WatchDiscoveryProgress, call: Int) async { await callbacks[call]?(progress) }
    func complete(_ value: WatchDiscoveryResult, call: Int) { gates.removeValue(forKey: call)?.resume(returning: value) }
}
