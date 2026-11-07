import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

// MARK: - Suite 5 (continued) and 6: Recovery, XMRig and cancellation boundaries

extension FleetMonitoringBoundaryTests {
    @Test("fallbackPoll failure records error and emits offline transition event when previously online")
    func fallbackPollFailureRecordsErrorAndEmitsOfflineEvent() async throws {
        try await withAsyncFixture(
            handler: { _ in throw URLError(.timedOut) },
            test: { store, device in
                let baseDate = Date()
                store.snapshots[device.id] = MinerSnapshot(
                    info: makeBaseInfo(), error: nil, updatedAt: baseDate, completeSnapshotAt: baseDate, isCached: false, isReconnecting: true
                )
                store.stateObservations[device.id.uuidString] = MinerFleetStateObservation(info: makeBaseInfo(), isOnline: true, observedAt: baseDate)
                store.pendingStateChangeEvents.removeAll()

                let token = store.liveGeneration
                await store.fallbackPoll(device, token: token)

                let snapshot = try #require(store.snapshots[device.id])
                #expect(snapshot.error != nil && snapshot.isReconnecting == false)

                let stateEvent = try #require(store.pendingStateChangeEvents.first)
                #expect(stateEvent.kind == .offline && stateEvent.deviceID == device.id)
            }
        )
    }

    @Test("fallbackPoll recovery clears error and emits backOnline state change event")
    func fallbackPollRecoveryEmitsBackOnlineEvent() async throws {
        try await withAsyncFixture(
            name: "Recovered Miner",
            handler: { req in
                try BoundaryTestContext.jsonResponse(
                    for: req, json: #"{"hashRate":1250,"power":19.0,"temp":53.0,"hostname":"recovered","ASICModel":"BM1370"}"#
                )
            },
            test: { store, device in
                let past = Date(timeIntervalSince1970: 5000)
                store.snapshots[device.id] = MinerSnapshot(
                    info: makeBaseInfo(), error: "Offline earlier", updatedAt: past, completeSnapshotAt: past, isCached: false, isReconnecting: true
                )
                store.stateObservations[device.id.uuidString] = MinerFleetStateObservation(info: makeBaseInfo(), isOnline: false, observedAt: past)
                store.pendingStateChangeEvents.removeAll()

                let token = store.liveGeneration
                await store.fallbackPoll(device, token: token)

                let snapshot = try #require(store.snapshots[device.id])
                #expect(snapshot.error == nil && snapshot.isReconnecting == false && snapshot.completeSnapshotAt != nil)

                let stateEvent = try #require(store.pendingStateChangeEvents.first)
                #expect(stateEvent.kind == .backOnline && stateEvent.deviceID == device.id)
            }
        )
    }

    @Test("fallbackPoll supports XMRig device kind by querying summary endpoint")
    func fallbackPollSupportsXMRigDeviceKind() async throws {
        try await withAsyncFixture(
            name: "XMRig Host",
            kind: .xmrig,
            handler: { req in
                #expect(req.url?.path.contains("summary") == true)
                let json = """
                {"id":"1","worker_id":"rig-cpu","version":"6.18.0",
                 "hashrate":{"total":[2500000000.0]},
                 "results":{"shares_good":10,"shares_total":12,"best":[999999]},
                 "connection":{"pool":"xmr.pool.test","uptime":1200},"paused":false}
                """
                return try BoundaryTestContext.jsonResponse(for: req, json: json)
            },
            test: { store, device in
                let token = store.liveGeneration
                await store.fallbackPoll(device, token: token)

                let snapshot = try #require(store.snapshots[device.id])
                #expect(snapshot.error == nil && snapshot.completeSnapshotAt != nil)
                #expect(snapshot.info?.raw["sharesAccepted"]?.intValue == 10 && snapshot.info?.raw["sharesRejected"]?.intValue == 2)
                #expect(snapshot.info?.raw["hostname"]?.stringValue == "rig-cpu")
            }
        )
    }

    @Test("fallbackPoll records failure when XMRig summary request errors")
    func fallbackPollXMRigFailureRecordsError() async throws {
        try await withAsyncFixture(
            name: "XMRig Host",
            kind: .xmrig,
            handler: { _ in throw URLError(.cannotConnectToHost) },
            test: { store, device in
                store.snapshots[device.id] = MinerSnapshot(info: nil, error: nil, isReconnecting: true)
                await store.fallbackPoll(device, token: store.liveGeneration)

                let snapshot = try #require(store.snapshots[device.id])
                #expect(snapshot.error != nil && snapshot.isReconnecting == false)
            }
        )
    }

    // MARK: - Suite 6: Run Monitoring Lifecycle Entry and Cleanup Guards

    @Test("runMonitoring in demo mode exits immediately without modifying monitoring state")
    func runMonitoringInDemoModeIsStrictNoOp() async throws {
        let ctx = BoundaryTestContext()
        defer { ctx.teardown() }
        let (_, store) = try ctx.makeDeviceAndStore(name: "Demo Miner")
        store.isDemo = true

        let initialGeneration = store.liveGeneration
        await store.runMonitoring()

        #expect(store.liveGeneration == initialGeneration)
        #expect(store.liveTasks.isEmpty == true && store.liveConnectedDeviceIDs.isEmpty == true && store.isRefreshing == false)
    }

    @Test("runMonitoring with an empty fleet completes bootstrap without spawning live tasks")
    func runMonitoringWithEmptyFleetPerformsBootstrapWithoutSpawningLiveTasks() async throws {
        let ctx = BoundaryTestContext()
        defer { ctx.teardown() }
        let store = try ctx.makeStore(devices: [])
        store.preferences.realtimeMonitoring = true

        await store.runMonitoring()

        #expect(store.liveTasks.isEmpty == true && store.liveConnectedDeviceIDs.isEmpty == true && store.liveConnectionErrors.isEmpty == true)
    }

    @Test("runMonitoring with cancelled caller task exits cleanly without starting live monitoring")
    func runMonitoringWhenCancelledExitsImmediately() async throws {
        let ctx = BoundaryTestContext()
        defer { ctx.teardown() }
        let (_, store) = try ctx.makeDeviceAndStore()

        let task = Task { @MainActor in
            Task.cancelVisitor()
            await store.runMonitoring()
        }
        task.cancel()
        await task.value

        #expect(store.liveTasks.isEmpty == true && store.liveConnectedDeviceIDs.isEmpty == true)
    }
}
