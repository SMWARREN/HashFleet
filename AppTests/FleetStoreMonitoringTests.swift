import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension FleetStoreTests {
    @Test func duplicateTelemetryDoesNotAppendHistoryOrInvalidateTheSnapshot() throws {
        let real = MinerDevice(name: "Miner", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        defer { fleetEnv.defaults.removePersistentDomain(forName: fleetEnv.suite) }
        store.preferences.telemetryStorageEnabled = false
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let info = MinerInfo(raw: ["hashRate": .number(1_200), "power": .number(19)])

        #expect(store.recordSuccessfulInfo(info, for: real.id, at: firstDate, isCompleteSnapshot: false))
        let firstSnapshot = try #require(store.snapshots[real.id])
        #expect(!store.recordSuccessfulInfo(
            info, for: real.id, at: firstDate.addingTimeInterval(1), isCompleteSnapshot: false
        ))
        let currentSnapshot = try #require(store.snapshots[real.id])
        #expect(currentSnapshot.updatedAt == firstSnapshot.updatedAt)
        #expect(currentSnapshot.history.count == firstSnapshot.history.count)
        for (currentPoint, firstPoint) in zip(currentSnapshot.history, firstSnapshot.history) {
            #expect(currentPoint.date == firstPoint.date)
            #expect(currentPoint.value == firstPoint.value)
        }
    }

    @Test func duplicateCompleteSnapshotAppendsAHistorySampleForCoverage() throws {
        let real = MinerDevice(name: "Miner", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        defer { fleetEnv.defaults.removePersistentDomain(forName: fleetEnv.suite) }
        store.preferences.telemetryStorageEnabled = false
        let firstDate = Date(timeIntervalSince1970: 2_000)
        let secondDate = firstDate.addingTimeInterval(30)
        let info = MinerInfo(raw: ["hashRate": .number(1_200), "power": .number(19)])

        #expect(store.recordSuccessfulInfo(info, for: real.id, at: firstDate))
        #expect(!store.recordSuccessfulInfo(info, for: real.id, at: secondDate))

        let snapshot = try #require(store.snapshots[real.id])
        #expect(snapshot.updatedAt == firstDate)
        #expect(snapshot.completeSnapshotAt == secondDate)
        #expect(snapshot.history.map(\.date) == [firstDate, secondDate])
        #expect(snapshot.history.map(\.value) == [1_200, 1_200])
    }

    @Test func liveConnectionRequiresAutomaticBootstrapUntilSnapshotIsFresh() throws {
        let real = MinerDevice(name: "Miner", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        defer { fleetEnv.defaults.removePersistentDomain(forName: fleetEnv.suite) }

        #expect(store.needsLiveBootstrap(for: real.id))

        store.snapshots[real.id] = MinerSnapshot(
            info: MinerInfo(raw: ["hashRate": .number(1_200)]),
            error: nil,
            updatedAt: Date(),
            history: [],
            isCached: true
        )
        #expect(store.needsLiveBootstrap(for: real.id))

        store.snapshots[real.id]?.isCached = false
        #expect(!store.needsLiveBootstrap(for: real.id))

        store.snapshots[real.id]?.error = "Temporary bootstrap failure"
        #expect(store.needsLiveBootstrap(for: real.id))
    }

    @Test func openButSilentLiveConnectionFallsBackWhenSnapshotStopsAdvancing() throws {
        let real = MinerDevice(name: "Miner", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        defer { fleetEnv.defaults.removePersistentDomain(forName: fleetEnv.suite) }
        let now = Date()

        store.snapshots[real.id] = MinerSnapshot(
            info: MinerInfo(raw: ["hashRate": .number(1_200)]),
            error: nil,
            updatedAt: now.addingTimeInterval(-29),
            completeSnapshotAt: now.addingTimeInterval(-29),
            history: [],
            isCached: false
        )
        #expect(!store.needsFallbackPoll(for: real.id, now: now))

        store.snapshots[real.id]?.completeSnapshotAt = now.addingTimeInterval(-30)
        #expect(store.needsFallbackPoll(for: real.id, now: now))

        // Partial live frames can advance the visible update time without refreshing every metric.
        // The complete-snapshot watchdog must still request HTTP reconciliation in that case.
        store.snapshots[real.id]?.updatedAt = now
        #expect(store.needsFallbackPoll(for: real.id, now: now))

        store.snapshots[real.id]?.error = "Socket stopped updating"
        #expect(store.needsFallbackPoll(for: real.id, now: now))
    }

    @Test func cancelledForegroundCheckKeepsPreviousFailureInReconnectingState() async throws {
        let real = MinerDevice(name: "Slow miner", address: "delayed.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        store.preferences.telemetryStorageEnabled = false
        store.snapshots[real.id] = MinerSnapshot(error: "Previous connection failed")
        let monitoring = Task { await store.runMonitoring() }
        defer {
            monitoring.cancel()
            store.cancelRefresh()
            fleetEnv.defaults.removePersistentDomain(forName: fleetEnv.suite)
        }
        try await waitForRequest(fleetEnv.suite)
        #expect(store.isRefreshing)
        #expect(store.snapshots[real.id]?.isReconnecting == true)
        #expect(FleetStatusTickerModel(devices: store.devices, snapshots: store.snapshots).items.first?.status == .reconnecting)

        monitoring.cancel()
        await monitoring.value
        #expect(store.isRefreshing == false)
        #expect(store.snapshots[real.id]?.isReconnecting == true)
        #expect(store.snapshots[real.id]?.error == "Previous connection failed")
        try await waitForRequest(fleetEnv.suite, stopped: true)
    }

    @Test func monitoringPublishesTheCompleteBootstrapGlanceBeforeStartingLiveWork() async throws {
        let real = MinerDevice(name: "Online", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }

        var published: [FleetGlance] = []
        let monitoring = Task { @MainActor in
            await store.runMonitoring { glance in
                published.append(glance)
            }
        }
        defer {
            monitoring.cancel()
            store.cancelRefresh()
        }

        try await waitForRequest(suite)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while published.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        let glance = try #require(published.first)
        #expect(published.count == 1)
        #expect(glance.minerCount == 1)
        #expect(glance.onlineCount == 1)
        #expect(glance.hashrateGHs == 1200)
        #expect(glance.powerWatts == 19)
    }

    @Test func disablingRealtimeKeepsBootstrapButDoesNotStartLiveWork() async throws {
        let real = MinerDevice(name: "Online", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        store.preferences.realtimeMonitoring = false

        await store.runMonitoring()

        #expect(FleetFixtureProtocol.counter.value(for: suite) > 0)
        #expect(store.lastRefresh != nil)
        #expect(store.liveConnectedDeviceIDs.isEmpty)
        #expect(store.liveConnectionErrors.isEmpty)
    }

    @Test func staleMonitoringOwnerCannotCancelReplacementAutoRefresh() throws {
        let real = MinerDevice(name: "Online", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        defer {
            store.cancelLiveMonitoring()
            fleetEnv.defaults.removePersistentDomain(forName: fleetEnv.suite)
        }

        let staleOwner = UUID()
        let replacementOwner = UUID()
        store.liveGeneration = replacementOwner
        store.liveTasks[real.id] = Task {
            try? await Task.sleep(for: .seconds(60))
        }
        store.liveConnectedDeviceIDs.insert(real.id)
        store.liveConnectionErrors[real.id] = "Retrying"

        // This mirrors an old SwiftUI monitoring task reaching its defer after a replacement
        // task has already installed the next live generation following a manual refresh.
        store.cancelLiveMonitoring(ownedBy: staleOwner)

        #expect(store.liveGeneration == replacementOwner)
        #expect(store.liveTasks[real.id] != nil)
        #expect(store.liveConnectedDeviceIDs == [real.id])
        #expect(store.liveConnectionErrors[real.id] == "Retrying")

        store.cancelLiveMonitoring(ownedBy: replacementOwner)
        #expect(store.liveGeneration != replacementOwner)
        #expect(store.liveTasks.isEmpty)
        #expect(store.liveConnectedDeviceIDs.isEmpty)
        #expect(store.liveConnectionErrors.isEmpty)
    }

    @Test func invalidOrDuplicateAddressDoesNotExitDemo() throws {
        let real = MinerDevice(name: "Original", address: "http://online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        store.loadDemo()
        #expect(throws: (any Error).self) { try store.add(name: "Duplicate", address: "online.test") }
        #expect(throws: (any Error).self) { try store.add(name: "Bad", address: "http://online.test/api/system") }
        #expect(store.isDemo)
        #expect(store.devices.count == 3)
    }

    @Test func addingRealMinerExitsDemoAndPersistsDefaultName() throws {
        let fleetEnv = try fixture()
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        store.loadDemo()
        try store.add(name: "  ", address: " online.test ")
        #expect(!store.isDemo)
        #expect(store.devices.count == 1)
        #expect(store.devices.first?.name == "online.test")
        let restored = FleetStore(defaults: defaults)
        #expect(restored.devices == store.devices)
        store.remove(store.devices[0])
        #expect(store.devices.isEmpty)
        #expect(FleetStore(defaults: defaults).devices.isEmpty)
    }

    @Test func corruptedStorageIsReportedWithoutOverwrite() {
        let suite = "app.hashfleet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("not JSON".utf8)
        defaults.set(original, forKey: "app.hashfleet.devices.v1")
        let store = FleetStore(defaults: defaults)
        #expect(store.persistenceError != nil)
        #expect(store.devices.isEmpty)
        #expect(defaults.data(forKey: "app.hashfleet.devices.v1") == original)
    }

    @Test func corruptedStorageIsBackedUpBeforeAddingNewFleet() throws {
        let fleetEnv = try fixture()
        let storeBeforeCorruption = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        storeBeforeCorruption.cancelRefresh()
        let original = Data("recover this damaged fleet".utf8)
        defaults.set(original, forKey: "app.hashfleet.devices.v1")
        let store = FleetStore(defaults: defaults)
        try store.add(name: "New miner", address: "online.test")
        let recoveryKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("app.hashfleet.devices.v1.recovery.")
        }
        #expect(recoveryKeys.count == 1)
        let recoveryKey = try #require(recoveryKeys.first)
        #expect(defaults.data(forKey: recoveryKey) == original)
        #expect(FleetStore(defaults: defaults).devices == store.devices)
        store.remove(store.devices[0])
        #expect(defaults.data(forKey: recoveryKey) == original)
        #expect(
            defaults.dictionaryRepresentation().keys.filter {
                $0.hasPrefix("app.hashfleet.devices.v1.recovery.")
            }.count == 1
        )
    }

    @Test func cancellingCallerCancelsOwnedNetworkWork() async throws {
        let real = MinerDevice(name: "Slow miner", address: "delayed.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        let caller = Task { await store.refresh() }
        defer { caller.cancel(); store.cancelRefresh() }
        try await waitForRequest(suite)
        #expect(store.isRefreshing)
        caller.cancel()
        await caller.value
        #expect(!store.isRefreshing)
        #expect(store.snapshots.isEmpty)
        #expect(store.lastRefresh == nil)
        try await waitForRequest(suite, stopped: true)
    }

    @Test func enteringDemoCancelsRealRequestsAndRejectsTheirResults() async throws {
        let real = MinerDevice(name: "Slow miner", address: "delayed.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        let caller = Task { await store.refresh() }
        defer { caller.cancel(); store.cancelRefresh() }
        try await waitForRequest(suite)
        store.loadDemo()
        await caller.value
        try await waitForRequest(suite, stopped: true)
        await store.refresh()
        #expect(FleetFixtureProtocol.counter.value(for: suite) == 1)
        #expect(!store.isRefreshing)
        #expect(store.isDemo)
        #expect(store.snapshots[real.id] == nil)
        #expect(store.snapshots.values.allSatisfy { $0.history.count == 60 && $0.error == nil })
        store.clearDemo()
        #expect(store.devices == [real])
        #expect(store.snapshots.isEmpty)
        #expect(FleetFixtureProtocol.counter.value(for: suite) == 1)
    }

    @Test func addingAndClearingDemoDoNotLaunchUnownedRequests() async throws {
        let fleetEnv = try fixture()
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        store.loadDemo()
        try store.add(name: "Real miner", address: "online.test")
        await Task.yield()
        #expect(FleetFixtureProtocol.counter.value(for: suite) == 0)
        #expect(!store.isRefreshing)
        await store.refresh()
        #expect(store.onlineCount == 1)
        // Auto-capabilities probes ASIC once in a background task after successful info fetch.
        // Wait for it to complete so unowned work after clearing demo can be cleanly asserted.
        for _ in 0..<50 {
            if store.capabilities.reports.count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.capabilities.reports.count == 1)
        #expect(FleetFixtureProtocol.counter.value(for: suite) == 2)
        store.loadDemo()
        store.clearDemo()
        await Task.yield()
        #expect(FleetFixtureProtocol.counter.value(for: suite) == 2)
    }

    @Test func firmwareNoticeDismissalPersistsUntilANewerReleaseAppears() {
        let suite = "app.hashfleet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let deviceID = UUID()
        let checkedAt = Date()
        let current = FirmwareUpdateNotice(
            currentVersion: "v1.0.0",
            releases: [
                FirmwareRelease(
                    version: "v1.2.0",
                    url: URL(string: "https://github.com/bitaxeorg/ESP-Miner/releases/tag/v1.2.0")!
                )
            ],
            checkedAt: checkedAt,
            checkFailed: false
        )
        let store = FirmwareUpdateStore(defaults: defaults)
        #expect(store.shouldShow(current, for: deviceID))
        store.dismiss(deviceID: deviceID, releaseVersion: "v1.2.0")
        #expect(!store.shouldShow(current, for: deviceID))

        let restored = FirmwareUpdateStore(defaults: defaults)
        #expect(!restored.shouldShow(current, for: deviceID))
        let newer = FirmwareUpdateNotice(
            currentVersion: "v1.0.0",
            releases: [
                FirmwareRelease(
                    version: "v1.3.0",
                    url: URL(string: "https://github.com/bitaxeorg/ESP-Miner/releases/tag/v1.3.0")!
                ),
                FirmwareRelease(
                    version: "v1.2.0",
                    url: URL(string: "https://github.com/bitaxeorg/ESP-Miner/releases/tag/v1.2.0")!
                )
            ],
            checkedAt: checkedAt.addingTimeInterval(86400),
            checkFailed: false
        )
        #expect(restored.shouldShow(newer, for: deviceID))
    }

    private func waitForRequest(_ suite: String, stopped: Bool = false) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if FleetFixtureProtocol.counter.value(for: suite, stopped: stopped) > 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record(stopped ? "The owned request was not cancelled" : "The fixture request did not start")
        throw URLError(.timedOut)
    }

    @Test func demoNeverPollsAndRestoresSavedFleet() async throws {
        let real = MinerDevice(name: "My miner", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        store.loadDemo()
        let count = FleetFixtureProtocol.counter.value(for: suite)
        await store.refresh()
        #expect(FleetFixtureProtocol.counter.value(for: suite) == count)
        #expect(store.isDemo)
        #expect(store.devices.count == 3)
        #expect(store.onlineCount == 3)
        #expect(abs(store.totalHashrate - 3020) < 0.001)
        #expect(store.snapshots.values.allSatisfy { $0.history.count == 60 })
        let persisted = try JSONDecoder().decode(
            [MinerDevice].self,
            from: defaults.data(forKey: "app.hashfleet.devices.v1")!
        )
        #expect(persisted == [real])
        store.clearDemo()
        #expect(!store.isDemo)
        #expect(store.devices == [real])
    }
}
