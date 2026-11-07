import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Safe settings fields save directly. Everything else keeps the reviewed flow.
struct MinerDirectSavePolicyTests {
    @Test func safeFieldsUseTheDirectSavePath() {
        let payload: JSONValue = .object([
            "hostname": .string("rig"), "statsFrequency": .integer(60),
            "rotation": .integer(90), "invertscreen": .integer(1),
            "displayTimeout": .integer(5)
        ])
        #expect(MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: payload))
    }

    @Test func thermalControlsAlwaysKeepReview() {
        let payload: JSONValue = .object([
            "autofanspeed": .integer(0),
            "temptarget": .integer(60)
        ])
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: payload))
    }

    @Test func unifiedFlowDoesNotAddFrictionToSafeFields() {
        let payload: JSONValue = .object(["hostname": .string("rig")])
        #expect(MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: payload))
    }

    @Test(arguments: [
        "frequency", "coreVoltage", "manualFanSpeed", "minFanSpeed", "stratumURL", "stratumPassword",
        "primaryPoolIndex", "customFeature", "ssid", "wifiPass", "overclockEnabled"
    ])
    func riskyOrUnknownFieldsKeepReview(key: String) {
        let payload: JSONValue = .object(["hostname": .string("rig"), key: .integer(1)])
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: payload))
    }

    @Test func otherEndpointsAndEmptyPayloadsKeepReview() {
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: .object([:])))
        #expect(!MinerDirectSavePolicy.qualifies(
            endpoint: .updatePool(0), payload: .object(["hostname": .string("rig")])
        ))
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .restart, payload: .object([:])))
    }
}

@Suite(.serialized) @MainActor
struct MinerPostWriteRefreshTests {
    @Test func preWriteFallbackCannotOverwriteFreshPostWriteState() async throws {
        let suite = "app.hashfleet.post-write-fallback.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = OrderedRefreshURLProtocol.Fixture()
        OrderedRefreshURLProtocol.fixture = fixture
        defer { OrderedRefreshURLProtocol.fixture = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OrderedRefreshURLProtocol.self]
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)
        let store = FleetStore(defaults: defaults, session: session)
        defer {
            let probes = store.capabilities.cancelAll()
            store.cancelRefresh()
            Task {
                for probe in probes { _ = await probe.result }
                session.invalidateAndCancel()
            }
        }
        store.preferences.telemetryStorageEnabled = false
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        store.devices = [device]
        let liveGeneration = store.liveGeneration
        let older = Task { await store.fallbackPoll(device, token: liveGeneration) }
        var started = fixture.started.makeAsyncIterator()
        _ = await started.next()
        #expect(await store.refreshAfterWrite(for: device))
        fixture.releaseOldResponse()
        await older.value
        #expect(store.liveGeneration == liveGeneration, "Post-write refresh must not stop live monitoring")
        #expect(store.snapshots[device.id]?.info?.hostname == "after-write")
    }

    @Test(arguments: [false, true])
    func inFlightReadCannotApplyToReplacedOrRemovedTarget(remove: Bool) async throws {
        let suite = "app.hashfleet.in-flight-target.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = OrderedRefreshURLProtocol.Fixture()
        OrderedRefreshURLProtocol.fixture = fixture
        defer { OrderedRefreshURLProtocol.fixture = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OrderedRefreshURLProtocol.self]
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)
        let store = FleetStore(defaults: defaults, session: session)
        defer {
            let probes = store.capabilities.cancelAll()
            store.cancelRefresh()
            Task {
                for probe in probes { _ = await probe.result }
                session.invalidateAndCancel()
            }
        }
        store.preferences.telemetryStorageEnabled = false
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        store.devices = [device]
        let request = Task { await store.refresh() }
        var started = fixture.started.makeAsyncIterator()
        _ = await started.next()
        if remove { store.devices = [] } else { store.devices[0].address = "replacement.invalid" }
        fixture.releaseOldResponse()
        await request.value
        #expect(store.snapshots[device.id] == nil)
    }

    @Test func postWriteRefreshReplacesSuspendedPreWriteRead() async throws {
        let suite = "app.hashfleet.post-write.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = OrderedRefreshURLProtocol.Fixture()
        OrderedRefreshURLProtocol.fixture = fixture
        defer { OrderedRefreshURLProtocol.fixture = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OrderedRefreshURLProtocol.self]
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)
        let store = FleetStore(defaults: defaults, session: session)
        defer {
            let probes = store.capabilities.cancelAll()
            store.cancelRefresh()
            Task {
                for probe in probes { _ = await probe.result }
                session.invalidateAndCancel()
            }
        }
        store.preferences.telemetryStorageEnabled = false
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        store.devices = [device]
        let older = Task { await store.refresh() }
        var started = fixture.started.makeAsyncIterator()
        _ = await started.next()
        let oldGeneration = store.generation
        #expect(store.isRefreshing)
        #expect(await store.refreshAfterWrite(for: device))
        await older.value
        #expect(store.generation != oldGeneration)
        #expect(fixture.requestCount == 2)
        #expect(store.snapshots[device.id]?.info?.hostname == "after-write")
        #expect(store.snapshots[device.id]?.completeSnapshotAt != nil)
        #expect(!store.isRefreshing)
        store.snapshots[device.id]?.updatedAt = Date().addingTimeInterval(-600)
        store.snapshots[device.id]?.completeSnapshotAt = Date().addingTimeInterval(-600)
        #expect(await store.refreshAfterWrite(for: device), "An identical but newly fetched complete response is fresh")
        #expect(fixture.requestCount == 3)
    }

    @Test func removedChangedDemoAndCancelledTargetsCannotReloadForms() async throws {
        let suite = "app.hashfleet.post-write-guards.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        #expect(!(await store.refreshAfterWrite(for: device)))
        var replacement = device
        replacement.address = "replacement.invalid"
        store.devices = [replacement]
        #expect(!(await store.refreshAfterWrite(for: device)))
        store.devices = [device]
        store.isDemo = true
        #expect(!(await store.refreshAfterWrite(for: device)))
        store.isDemo = false
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await store.refreshAfterWrite(for: device)
        }
        #expect(!(await cancelled.value))
        #expect(store.snapshots.isEmpty)
    }
}

private final class OrderedRefreshURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var fixture: Fixture?
    final class Fixture: @unchecked Sendable {
        let started: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation
        private let lock = NSLock()
        private var count = 0
        private var suspended: OrderedRefreshURLProtocol?
        init() {
            let pair = AsyncStream<Void>.makeStream()
            started = pair.stream
            continuation = pair.continuation
        }
        var requestCount: Int { lock.withLock { count } }
        func begin() -> Int {
            lock.withLock { count += 1; return count }
        }
        func suspend(_ request: OrderedRefreshURLProtocol) {
            lock.withLock { suspended = request }
            continuation.yield(())
            continuation.finish()
        }
        func releaseOldResponse() {
            let request = lock.withLock { let value = suspended; suspended = nil; return value }
            request?.respond(hostname: "before-write")
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.path == "/api/system/info", let fixture = Self.fixture else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        // The first response remains suspended until URLSession cancels it. A joined refresh
        // would hang here instead of issuing the second, post-write GET.
        guard fixture.begin() > 1 else {
            fixture.suspend(self)
            return
        }
        respond(hostname: "after-write")
    }
    func respond(hostname: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"hostname\":\"\(hostname)\",\"hashRate\":0,\"power\":0}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
