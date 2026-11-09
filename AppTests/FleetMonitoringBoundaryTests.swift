import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Thread-safe box for capturing mutable test state across Sendable boundaries.
private final class LockedBox<T>: @unchecked Sendable {
    var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ value: T) { lock.withLock { self.value = value } }
}

/// Isolated mock network protocol specifically for monitoring boundary tests.
/// Routes requests by unique mock hostname to prevent cross-test interference.
private final class BoundaryStubRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    func set(_ handler: Handler?, for host: String) { lock.withLock { handlers[host] = handler } }
    func handler(for host: String) -> Handler? { lock.withLock { handlers[host] } }
}

final class BoundaryMockURLProtocol: URLProtocol, @unchecked Sendable {
    fileprivate static let registry = BoundaryStubRegistry()
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host, let handler = Self.registry.handler(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Fully isolated test fixture context with dedicated UserDefaults suite and URLSession.
@MainActor
final class BoundaryTestContext {
    let host: String
    let suite: String
    let defaults: UserDefaults
    let session: URLSession
    private var stores: [FleetStore] = []

    nonisolated static func jsonResponse(for req: URLRequest, json: String, status: Int = 200) throws -> (URLResponse, Data) {
        guard let url = req.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { throw URLError(.badURL) }
        return (response, Data(json.utf8))
    }

    init(handler: @escaping @Sendable (URLRequest) throws -> (URLResponse, Data) = { req in
        try BoundaryTestContext.jsonResponse(for: req, json: #"{"hashRate":1200,"power":19,"temp":54,"hostname":"fixture","ASICModel":"BM1370"}"#)
    }) {
        self.host = "mock-\(UUID().uuidString.lowercased()).invalid"
        self.suite = "app.hashfleet.boundary.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: self.suite)!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundaryMockURLProtocol.self]
        self.session = URLSession(configuration: configuration)
        BoundaryMockURLProtocol.registry.set(handler, for: self.host)
    }

    func makeStore(devices: [MinerDevice] = []) throws -> FleetStore {
        if !devices.isEmpty { defaults.set(try JSONEncoder().encode(devices), forKey: FleetStore.storageKey) }
        let store = FleetStore(defaults: defaults, session: session)
        stores.append(store)
        return store
    }

    func makeDeviceAndStore(name: String = "Miner", kind: MinerDevice.Kind = .espMiner) throws -> (MinerDevice, FleetStore) {
        let device = MinerDevice(name: name, address: host, kind: kind)
        return (device, try makeStore(devices: [device]))
    }

    func teardown() {
        let pendingProbes = stores.flatMap { $0.capabilities.cancelAll() }
        stores.forEach { $0.cancelRefresh() }
        stores.removeAll()
        let session = session
        Task {
            for probe in pendingProbes { _ = await probe.result }
            session.invalidateAndCancel()
        }
        BoundaryMockURLProtocol.registry.set(nil, for: host)
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite("Fleet Monitoring Boundary Tests", .serialized)
@MainActor
struct FleetMonitoringBoundaryTests {
    @Test("Missing power does not starve the foreground menu-bar bootstrap callback")
    func missingPowerStillPublishesMenuBootstrap() async throws {
        try await withAsyncFixture(handler: { request in
            try BoundaryTestContext.jsonResponse(for: request, json: #"{"hostname":"fixture","hashRate":0}"#)
        }, test: { store, device in
            store.preferences.realtimeMonitoring = false
            store.preferences.telemetryStorageEnabled = false
            var calls = 0
            await store.runMonitoring { glance in
                calls += 1
                #expect(glance == .empty)
                #expect(!store.canPublishGlance && store.canPublishMenuBar)
                #expect(store.menuBarSnapshot.reportedHashrate == 0)
                #expect(store.menuBarSnapshot.reportedPower == nil)
                #expect(store.menuBarSnapshot.miners.first?.id == device.id)
            }
            #expect(calls == 1)
            #expect(store.liveTasks.isEmpty)
        })
    }

    func makeBaseInfo(
        hashRate: Double = 1100, power: Double = 18.5, temp: Double = 52.0
    ) -> MinerInfo {
        MinerInfo(raw: [
            "hostname": .string("Desk"), "boardVersion": .string("602"),
            "frequency": .integer(600), "hashRate": .number(hashRate),
            "power": .number(power), "temp": .number(temp)
        ])
    }

    fileprivate func withFixture(
        name: String = "Miner", kind: MinerDevice.Kind = .espMiner,
        handler: (@Sendable (URLRequest) throws -> (URLResponse, Data))? = nil,
        test: (FleetStore, MinerDevice) throws -> Void
    ) throws {
        let ctx = handler != nil ? BoundaryTestContext(handler: handler!) : BoundaryTestContext()
        defer { ctx.teardown() }
        let (device, store) = try ctx.makeDeviceAndStore(name: name, kind: kind)
        try test(store, device)
    }

    func withAsyncFixture(
        name: String = "Miner", kind: MinerDevice.Kind = .espMiner,
        handler: (@Sendable (URLRequest) throws -> (URLResponse, Data))? = nil,
        test: (FleetStore, MinerDevice) async throws -> Void
    ) async throws {
        let ctx = handler != nil ? BoundaryTestContext(handler: handler!) : BoundaryTestContext()
        defer { ctx.teardown() }
        let (device, store) = try ctx.makeDeviceAndStore(name: name, kind: kind)
        try await test(store, device)
    }

    fileprivate func populateLiveTasks(
        store: FleetStore, device: MinerDevice, token: UUID = UUID(), error: String = "Network issue"
    ) -> Task<Void, Never> {
        store.liveGeneration = token
        let task = Task {
            _ = try? await Task.sleep(for: .seconds(60))
        }
        store.liveTasks[device.id] = task
        store.liveConnectedDeviceIDs.insert(device.id)
        store.liveConnectionErrors[device.id] = error
        return task
    }

    // MARK: - Suite 1: Live Message Validation and Rejection Boundaries

    @Test("Rejects malformed, non-JSON or empty WebSocket message payloads")
    func rejectsMalformedOrInvalidJSON() throws {
        try withFixture { store, device in
            store.snapshots[device.id] = MinerSnapshot(info: makeBaseInfo(), error: nil, updatedAt: Date(), history: [])
            let initialSnapshot = store.snapshots[device.id]
            #expect(store.applyLiveMessage(.text("not valid json at all"), for: device.id) == false)
            #expect(store.applyLiveMessage(.text(""), for: device.id) == false)
            #expect(store.snapshots[device.id]?.info?.raw == initialSnapshot?.info?.raw)
            #expect(store.snapshots[device.id]?.history.isEmpty == true)
        }
    }

    @Test("Rejects envelopes without an object dictionary or with an empty data payload")
    func rejectsNonObjectOrMissingDataEnvelope() throws {
        try withFixture { store, device in
            store.snapshots[device.id] = MinerSnapshot(info: makeBaseInfo(), error: nil, updatedAt: Date(), history: [])
            for payload in ["[]", #"{"status":"ok"}"#, #"{"data":[1,2,3]}"#, #"{"data":{}}"#] {
                #expect(store.applyLiveMessage(.text(payload), for: device.id) == false)
            }
        }
    }

    @Test("Rejects live frame when miner snapshot has active error")
    func rejectsLiveFrameWhenSnapshotHasError() throws {
        try withFixture { store, device in
            store.snapshots[device.id] = MinerSnapshot(
                info: makeBaseInfo(), error: "Connection lost", updatedAt: Date(), history: []
            )
            let frame = MinerWebSocketMessage.text(#"{"data":{"hashRate":1450}}"#)
            #expect(store.applyLiveMessage(frame, for: device.id) == false)
            #expect(store.snapshots[device.id]?.error == "Connection lost")
            #expect(store.snapshots[device.id]?.info?.raw["hashRate"]?.doubleValue == 1100)
            #expect(store.snapshots[device.id]?.history.isEmpty == true)
        }
    }

    @Test("Rejects live frame when miner snapshot is cached")
    func rejectsLiveFrameWhenSnapshotIsCached() throws {
        try withFixture { store, device in
            store.snapshots[device.id] = MinerSnapshot(
                info: makeBaseInfo(), error: "Offline, showing cached settings",
                updatedAt: Date(), history: [], isCached: true
            )
            let frame = MinerWebSocketMessage.text(#"{"data":{"hashRate":1450}}"#)
            #expect(store.applyLiveMessage(frame, for: device.id) == false)
            #expect(store.snapshots[device.id]?.isCached == true)
            #expect(store.snapshots[device.id]?.error != nil)
        }
    }

    @Test("Rejects live frame when miner snapshot base info is nil")
    func rejectsLiveFrameWhenSnapshotInfoIsNil() throws {
        try withFixture { store, device in
            store.snapshots[device.id] = MinerSnapshot(info: nil, error: nil, updatedAt: Date(), history: [])
            let frame = MinerWebSocketMessage.text(#"{"data":{"hashRate":1450}}"#)
            #expect(store.applyLiveMessage(frame, for: device.id) == false)
            #expect(store.snapshots[device.id]?.info == nil)
        }
    }

    // MARK: - Suite 2: Partial Telemetry Merging and Alert Contracts

    @Test("Partial frame updates target metrics while preserving unaffected base attributes")
    func partialFrameMergesWithoutErasingExistingAttributes() throws {
        try withFixture { store, device in
            store.snapshots[device.id] = MinerSnapshot(
                info: makeBaseInfo(hashRate: 1100, power: 18.5, temp: 52.0), error: nil,
                updatedAt: Date(timeIntervalSince1970: 1000), completeSnapshotAt: Date(timeIntervalSince1970: 1000), history: []
            )
            #expect(store.applyLiveMessage(.text(#"{"data":{"hashRate":1320,"temp":57.5}}"#), for: device.id) == true)
            let updatedInfo = try #require(store.snapshots[device.id]?.info)
            #expect(updatedInfo.raw["hashRate"]?.doubleValue == 1320 && updatedInfo.raw["temp"]?.doubleValue == 57.5)
            #expect(updatedInfo.raw["hostname"]?.stringValue == "Desk" && updatedInfo.raw["boardVersion"]?.stringValue == "602")
            #expect(updatedInfo.raw["frequency"]?.intValue == 600 && updatedInfo.raw["power"]?.doubleValue == 18.5)
        }
    }

    @Test("Partial frame advances updatedAt but strictly preserves completeSnapshotAt")
    func partialFrameUpdatesUpdatedAtWithoutAdvancingCompleteSnapshotAt() throws {
        try withFixture { store, device in
            let initialDate = Date(timeIntervalSince1970: 10_000)
            store.snapshots[device.id] = MinerSnapshot(
                info: makeBaseInfo(), error: nil, updatedAt: initialDate, completeSnapshotAt: initialDate, history: []
            )
            #expect(store.applyLiveMessage(.text(#"{"data":{"hashRate":1250}}"#), for: device.id) == true)
            let snapshot = try #require(store.snapshots[device.id])
            #expect(snapshot.completeSnapshotAt == initialDate)
            let updatedAt = try #require(snapshot.updatedAt)
            #expect(updatedAt > initialDate)
        }
    }

    @Test("History buffer accumulates points and strictly caps capacity at 360")
    func historyBufferAccumulatesPointsAndCapsAtMaximum360() throws {
        try withFixture { store, device in
            store.snapshots[device.id] = MinerSnapshot(
                info: makeBaseInfo(), error: nil, updatedAt: Date(), completeSnapshotAt: Date(), history: []
            )
            for rate in 1...365 {
                let frame = MinerWebSocketMessage.text(#"{"data":{"hashRate":\#(rate)}}"#)
                #expect(store.applyLiveMessage(frame, for: device.id) == true)
            }
            let history = try #require(store.snapshots[device.id]?.history)
            #expect(history.count == 360 && history.first?.value == 6.0 && history.last?.value == 365.0)
        }
    }

    @Test("Temperature alert observation only triggers when temp key is fresh in the frame")
    func temperatureAlertOnlyTriggeredWhenTemperatureKeyIsFreshInFrame() throws {
        try withFixture { store, device in
            try store.temperatureAlerts.setPolicy(
                MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: 75), for: device.id
            )
            store.snapshots[device.id] = MinerSnapshot(
                info: makeBaseInfo(hashRate: 1100, power: 19.0, temp: 78.0),
                error: nil, updatedAt: Date(), completeSnapshotAt: Date(), history: []
            )
            store.pendingTemperatureEvents.removeAll()
            #expect(store.applyLiveMessage(.text(#"{"data":{"hashRate":1220}}"#), for: device.id) == true)
            #expect(store.pendingTemperatureEvents.isEmpty == true)
            #expect(store.applyLiveMessage(.text(#"{"data":{"temp":81.5}}"#), for: device.id) == true)
            #expect(store.pendingTemperatureEvents.first?.temperatureCelsius == 81.5)
        }
    }

    @Test("Power alert observation only triggers when power key is fresh in the frame")
    func powerAlertOnlyTriggeredWhenPowerKeyIsFreshInFrame() throws {
        try withFixture { store, device in
            try store.powerAlerts.setPolicy(
                MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 25.0), for: device.id
            )
            store.snapshots[device.id] = MinerSnapshot(
                info: makeBaseInfo(hashRate: 1100, power: 30.0, temp: 50.0),
                error: nil, updatedAt: Date(), completeSnapshotAt: Date(), history: []
            )
            store.pendingPowerAlertEvents.removeAll()
            #expect(store.applyLiveMessage(.text(#"{"data":{"hashRate":1220}}"#), for: device.id) == true)
            #expect(store.pendingPowerAlertEvents.isEmpty == true)
            #expect(store.applyLiveMessage(.text(#"{"data":{"power":32.5}}"#), for: device.id) == true)
            #expect(store.pendingPowerAlertEvents.first?.watts == 32.5)
        }
    }

    // MARK: - Suite 3: Needs Live Bootstrap & Needs Fallback Poll Predicate Boundaries

    @Test("needsLiveBootstrap boundary logic validates all snapshot combinations")
    func needsLiveBootstrapBoundaryMatrix() throws {
        try withFixture { store, device in
            #expect(store.needsLiveBootstrap(for: device.id) == true)
            let cases: [(MinerInfo?, String?, Bool, Bool)] = [
                (nil, nil, false, true),
                (makeBaseInfo(), "Temporary error", false, true),
                (makeBaseInfo(), nil, true, true),
                (makeBaseInfo(), nil, false, false)
            ]
            for (info, err, cached, expected) in cases {
                store.snapshots[device.id] = MinerSnapshot(info: info, error: err, isCached: cached)
                #expect(store.needsLiveBootstrap(for: device.id) == expected)
            }
        }
    }

    @Test("needsFallbackPoll evaluates complete snapshot timestamp and exact 30s threshold")
    func needsFallbackPollBoundaryMatrixAndThresholds() throws {
        try withFixture { store, device in
            let now = Date(timeIntervalSince1970: 50_000)
            #expect(store.needsFallbackPoll(for: device.id, now: now) == true)

            store.snapshots[device.id] = MinerSnapshot(
                info: makeBaseInfo(), error: nil, updatedAt: now, completeSnapshotAt: nil, isCached: false
            )
            #expect(store.needsFallbackPoll(for: device.id, now: now) == true)

            for (offset, expected) in [(-29.0, false), (-30.0, true), (-31.0, true)] {
                store.snapshots[device.id]?.completeSnapshotAt = now.addingTimeInterval(offset)
                #expect(store.needsFallbackPoll(for: device.id, now: now) == expected)
            }

            store.snapshots[device.id]?.updatedAt = now
            store.snapshots[device.id]?.completeSnapshotAt = now.addingTimeInterval(-35.0)
            #expect(store.needsFallbackPoll(for: device.id, now: now) == true)

            store.snapshots[device.id]?.error = "Socket error"
            store.snapshots[device.id]?.completeSnapshotAt = now.addingTimeInterval(-5.0)
            #expect(store.needsFallbackPoll(for: device.id, now: now) == true)
        }
    }
}

// MARK: - Extension for Suites 4, 5, and 6

extension FleetMonitoringBoundaryTests {

    // MARK: - Suite 4: Lifecycle and Generation Token Boundaries

    @Test("cancelLiveMonitoring with nil token clears all live tasks, sets and updates generation")
    func cancelLiveMonitoringWithNilTokenClearsAllStateAndIncrementsGeneration() throws {
        try withFixture { store, device in
            let initialToken = store.liveGeneration
            let dummyTask = populateLiveTasks(store: store, device: device, token: initialToken)
            defer { dummyTask.cancel() }

            store.cancelLiveMonitoring(ownedBy: nil)

            #expect(store.liveGeneration != initialToken)
            #expect(store.liveTasks.isEmpty == true && dummyTask.isCancelled == true)
            #expect(store.liveConnectedDeviceIDs.isEmpty == true && store.liveConnectionErrors.isEmpty == true)
        }
    }

    @Test("cancelLiveMonitoring with mismatched token preserves active monitoring state")
    func cancelLiveMonitoringWithMismatchedTokenPreservesActiveMonitoring() throws {
        try withFixture { store, device in
            let currentToken = UUID()
            let dummyTask = populateLiveTasks(store: store, device: device, token: currentToken, error: "Glitch")
            defer { dummyTask.cancel() }

            store.cancelLiveMonitoring(ownedBy: UUID())

            #expect(store.liveGeneration == currentToken)
            #expect(store.liveTasks[device.id] != nil && dummyTask.isCancelled == false)
            #expect(store.liveConnectedDeviceIDs.contains(device.id) == true)
            #expect(store.liveConnectionErrors[device.id] == "Glitch")
        }
    }

    @Test("cancelLiveMonitoring with matching token tears down generation cleanly")
    func cancelLiveMonitoringWithMatchingTokenTearsDownGeneration() throws {
        try withFixture { store, device in
            let ownerToken = UUID()
            let dummyTask = populateLiveTasks(store: store, device: device, token: ownerToken, error: "Offline")
            defer { dummyTask.cancel() }

            store.cancelLiveMonitoring(ownedBy: ownerToken)

            #expect(store.liveGeneration != ownerToken)
            #expect(store.liveTasks.isEmpty == true && dummyTask.isCancelled == true)
            #expect(store.liveConnectedDeviceIDs.isEmpty == true && store.liveConnectionErrors.isEmpty == true)
        }
    }

    // MARK: - Suite 5: Fallback Poll Execution, Error Recovery, and Cancellation Boundaries

    @Test("fallbackPoll rejects call with stale generation token without performing work")
    func fallbackPollRejectsStaleTokenWithoutNetworkCallOrStateChange() async throws {
        let requested = LockedBox(false)
        try await withAsyncFixture(
            handler: { _ in
                requested.set(true)
                throw URLError(.badServerResponse)
            },
            test: { store, device in
                store.liveGeneration = UUID()
                await store.fallbackPoll(device, token: UUID())
                #expect(requested.get() == false && store.snapshots[device.id] == nil)
            }
        )
    }

    @Test("fallbackPoll is a strict no-op in demo mode")
    func fallbackPollRejectsDemoModeWithoutNetworkCall() async throws {
        let requested = LockedBox(false)
        try await withAsyncFixture(
            handler: { _ in
                requested.set(true)
                throw URLError(.badServerResponse)
            },
            test: { store, device in
                store.isDemo = true
                await store.fallbackPoll(device, token: store.liveGeneration)
                #expect(requested.get() == false && store.snapshots[device.id] == nil)
            }
        )
    }

    @Test("fallbackPoll discards response if device was removed from fleet during request")
    func fallbackPollIgnoresResultIfDeviceRemovedDuringInFlightRequest() async throws {
        let ctx = BoundaryTestContext()
        defer { ctx.teardown() }
        let device = MinerDevice(name: "Miner", address: ctx.host)
        let store = try ctx.makeStore(devices: [])

        await store.fallbackPoll(device, token: store.liveGeneration)
        #expect(store.snapshots[device.id] == nil)
    }

    @Test("fallbackPoll success sets complete snapshot timestamp, updates info and clears error")
    func fallbackPollSuccessSetsCompleteSnapshotAndClearsReconnecting() async throws {
        try await withAsyncFixture(
            handler: { req in
                try BoundaryTestContext.jsonResponse(
                    for: req, json: #"{"hashRate":1400,"power":21.5,"temp":56.0,"hostname":"gamma-1","ASICModel":"BM1370"}"#
                )
            },
            test: { store, device in
                store.snapshots[device.id] = MinerSnapshot(
                    info: nil, error: "Previous outage",
                    updatedAt: Date(timeIntervalSince1970: 1000), completeSnapshotAt: nil,
                    isCached: false, isReconnecting: true
                )
                let token = store.liveGeneration
                await store.fallbackPoll(device, token: token)

                let snapshot = try #require(store.snapshots[device.id])
                #expect(snapshot.error == nil && snapshot.isReconnecting == false && snapshot.completeSnapshotAt != nil)
                #expect(snapshot.info?.raw["hashRate"]?.doubleValue == 1400 && snapshot.info?.raw["power"]?.doubleValue == 21.5)
                #expect(store.cachedReadings[device.id.uuidString] != nil)
            }
        )
    }

    // MARK: - Suite 7: Stream Ownership & Obsolete Monitor Return

    @Test("Obsolete monitor return preserves replacement-generation state")
    func obsoleteMonitorReturnPreservesReplacementState() async throws {
        let requested = LockedBox(false)
        try await withAsyncFixture(handler: { _ in
            requested.set(true)
            throw URLError(.unsupportedURL)
        }) { store, device in
            let replacement = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            let obsolete = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            let sentinel = populateLiveTasks(
                store: store, device: device, token: replacement, error: "replacement-only"
            )
            defer { sentinel.cancel() }

            await store.monitor(device: device, token: obsolete)

            let connected = store.liveConnectedDeviceIDs
            let ownsTask = store.liveTasks[device.id] != nil
            let wasCancelled = sentinel.isCancelled
            let generation = store.liveGeneration
            let error = store.liveConnectionErrors[device.id]
            sentinel.cancel()
            await sentinel.value

            #expect(generation == replacement)
            #expect(connected == [device.id])
            #expect(ownsTask && !wasCancelled)
            #expect(error == "replacement-only")
            #expect(!requested.get())
        }
    }
}

extension FleetMonitoringBoundaryTests {
    private func waitForBoundary(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }

    @Test("Finishing an obsolete stream preserves the replacement connection")
    func obsoleteStreamFinishPreservesReplacementConnection() async throws {
        let requested = LockedBox(false)
        try await withAsyncFixture(handler: { _ in
            requested.set(true)
            throw URLError(.unsupportedURL)
        }) { store, device in
            let original = UUID()
            store.liveGeneration = original
            let pair = AsyncThrowingStream<MinerWebSocketMessage, Error>.makeStream()
            let completed = LockedBox(false)
            let failure = LockedBox<String?>(nil)
            let consumer = Task { @MainActor in
                defer { completed.set(true) }
                do { try await store.consumeLiveStream(pair.stream, device: device, token: original) }
                catch { failure.set(String(describing: type(of: error))) }
            }
            defer { pair.continuation.finish(); consumer.cancel() }
            let connected = try await waitForBoundary { store.liveConnectedDeviceIDs.contains(device.id) }
            try #require(connected)
            let replacement = UUID()
            let sentinel = populateLiveTasks(store: store, device: device, token: replacement, error: "replacement-only")
            defer { sentinel.cancel() }
            pair.continuation.finish()
            let finished = try await waitForBoundary { completed.get() }
            try #require(finished)
            await consumer.value
            #expect(failure.get() == nil)
            #expect(store.liveGeneration == replacement)
            #expect(store.liveConnectedDeviceIDs == [device.id])
            #expect(store.liveTasks[device.id] != nil && !sentinel.isCancelled)
            #expect(store.liveConnectionErrors[device.id] == "replacement-only")
            #expect(!requested.get())
            sentinel.cancel()
            await sentinel.value
        }
    }

    @Test("A frame suspended in bootstrap cannot overwrite a replacement snapshot")
    func bootstrapReturnRejectsObsoleteFrame() async throws {
        let requested = LockedBox(false)
        let responseReleased = LockedBox(false)
        let release = DispatchSemaphore(value: 0)
        try await withAsyncFixture(handler: { request in
            requested.set(true)
            guard release.wait(timeout: .now() + 3) == .success else { throw URLError(.timedOut) }
            responseReleased.set(true)
            return try BoundaryTestContext.jsonResponse(for: request, json: #"{"hashRate":1111,"power":19,"temp":54,"hostname":"old"}"#)
        }) { store, device in
            store.preferences.telemetryStorageEnabled = false
            let original = UUID()
            store.liveGeneration = original
            let pair = AsyncThrowingStream<MinerWebSocketMessage, Error>.makeStream()
            let completed = LockedBox(false)
            let failure = LockedBox<String?>(nil)
            let consumer = Task { @MainActor in
                defer { completed.set(true) }
                do { try await store.consumeLiveStream(pair.stream, device: device, token: original) }
                catch { failure.set(String(describing: type(of: error))) }
            }
            defer { release.signal(); pair.continuation.finish(); consumer.cancel() }
            pair.continuation.yield(.text(#"{"data":{"hashRate":2222}}"#))
            let bootstrapStarted = try await waitForBoundary { requested.get() }
            try #require(bootstrapStarted)
            let replacement = UUID()
            let sentinel = populateLiveTasks(store: store, device: device, token: replacement, error: "replacement-only")
            defer { sentinel.cancel() }
            let replacementDate = Date(timeIntervalSince1970: 12345)
            store.snapshots[device.id] = MinerSnapshot(
                info: makeBaseInfo(hashRate: 3333), error: nil, updatedAt: replacementDate,
                completeSnapshotAt: replacementDate, history: []
            )
            release.signal()
            pair.continuation.finish()
            let finished = try await waitForBoundary { completed.get() }
            try #require(finished)
            await consumer.value
            #expect(responseReleased.get() && failure.get() == nil)
            #expect(store.liveGeneration == replacement)
            #expect(store.snapshots[device.id]?.info?.raw["hashRate"]?.doubleValue == 3333)
            #expect(store.snapshots[device.id]?.updatedAt == replacementDate)
            #expect(store.snapshots[device.id]?.history.isEmpty == true)
            #expect(store.liveConnectedDeviceIDs == [device.id])
            #expect(store.liveTasks[device.id] != nil && !sentinel.isCancelled)
            #expect(store.liveConnectionErrors[device.id] == "replacement-only")
            sentinel.cancel()
            await sentinel.value
        }
    }

    @Test("The current stream owner still applies buffered frames in order and disconnects")
    func currentStreamOwnerDrainsBufferedFrames() async throws {
        let requested = LockedBox(false)
        try await withAsyncFixture(handler: { _ in
            requested.set(true)
            throw URLError(.unsupportedURL)
        }) { store, device in
            store.preferences.telemetryStorageEnabled = false
            let token = UUID()
            store.liveGeneration = token
            store.snapshots[device.id] = MinerSnapshot(info: makeBaseInfo(), error: nil, updatedAt: Date(), history: [])
            let pair = AsyncThrowingStream<MinerWebSocketMessage, Error>.makeStream()
            for rate in [1200, 1300, 1400] {
                pair.continuation.yield(.text(#"{"data":{"hashRate":\#(rate)}}"#))
            }
            pair.continuation.finish()
            try await store.consumeLiveStream(pair.stream, device: device, token: token)
            #if os(macOS)
            #expect(store.snapshots[device.id]?.history.map(\.value) == [1400])
            #else
            #expect(store.snapshots[device.id]?.history.map(\.value) == [1200, 1300, 1400])
            #endif
            #expect(store.snapshots[device.id]?.info?.raw["hashRate"]?.doubleValue == 1400)
            #expect(!store.liveConnectedDeviceIDs.contains(device.id))
            #expect(store.liveGeneration == token)
            #expect(!requested.get())
        }
    }
}

extension Task where Success == Never, Failure == Never {
    static func cancelVisitor() {}
}
