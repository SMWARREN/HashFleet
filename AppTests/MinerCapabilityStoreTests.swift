import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized) @MainActor
struct MinerCapabilityStoreTests {
    @Test
    func demoCheckDoesNotNetworkOrCreateReport() async {
        let fixture = StoreFixture { _ in
            Issue.record("Demo capability check performed network I/O")
            return try storeResponse(status: 500, body: Data())
        }
        let store = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "Demo", address: fixture.host)

        await store.check(device: device, isDemo: true)

        #expect(fixture.requestCount == 0)
        #expect(store.reports.isEmpty)
        #expect(store.checking.isEmpty)
    }

    @Test
    func partialSuccessIsStoredAsReturnedByProbe() async {
        let fixture = StoreFixture { request in
            if request.url?.path == "/api/system/info" {
                return try storeResponse(body: Data(#"{"hostname":"fixture","hashRate":100}"#.utf8))
            }
            return try storeResponse(status: 404, body: Data(#"{"error":"missing"}"#.utf8))
        }
        let store = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "Partial", address: fixture.host)

        await store.check(device: device, isDemo: false)

        let report = store.reports[device.id]
        #expect(report?.infoStatus == .supported)
        #expect(report?.info?.hostname == "fixture")
        #expect(report?.asicStatus == .unsupported(statusCode: 404))
        #expect(store.checking.isEmpty)
    }

    @Test
    func removeClearsReportAndCancelsState() async {
        let fixture = StoreFixture { request in
            try storeResponse(
                body: request.url?.path == "/api/system/info"
                    ? Data(#"{"hostname":"fixture"}"#.utf8)
                    : Data(#"{"ASICModel":"BM1397"}"#.utf8)
            )
        }
        let store = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "Removable", address: fixture.host)

        await store.check(device: device, isDemo: false)
        #expect(store.reports[device.id] != nil)
        store.remove(device.id)

        #expect(store.reports[device.id] == nil)
        #expect(!store.checking.contains(device.id))
    }

    @Test
    func resetClearsAllCapabilityReports() async {
        let fixture = StoreFixture { request in
            try storeResponse(
                body: request.url?.path == "/api/system/info"
                    ? Data(#"{"hostname":"fixture"}"#.utf8)
                    : Data(#"{"defaultFrequency":600}"#.utf8)
            )
        }
        let store = MinerCapabilitiesStore(session: fixture.session)
        let first = MinerDevice(name: "One", address: fixture.host)
        let second = MinerDevice(name: "Two", address: fixture.host)

        await store.check(device: first, isDemo: false)
        await store.check(device: second, isDemo: false)
        #expect(store.reports.count == 2)
        store.reset()

        #expect(store.reports.isEmpty)
        #expect(store.checking.isEmpty)
    }

    @Test
    func callerCancellationDoesNotPublishStaleReport() async throws {
        let fixture = StoreFixture(delayed: true) { request in
            try storeResponse(
                body: request.url?.path == "/api/system/info"
                    ? Data(#"{"hostname":"fixture"}"#.utf8)
                    : Data(#"{"ASICModel":"BM1397"}"#.utf8)
            )
        }
        let store = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "Slow", address: fixture.host)
        let caller = Task { await store.check(device: device, isDemo: false) }
        defer {
            caller.cancel()
            store.cancelAll()
            fixture.session.invalidateAndCancel()
        }

        try await fixture.waitForRequest()
        #expect(store.checking.contains(device.id))
        caller.cancel()
        await caller.value

        #expect(store.reports[device.id] == nil)
        #expect(!store.checking.contains(device.id))
    }
}

private final class StoreFixture: @unchecked Sendable {
    let host: String
    let session: URLSession
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    init(
        delayed: Bool = false,
        handler: @escaping @Sendable (URLRequest) throws -> (URLResponse, Data)
    ) {
        host = "store-capability-\(UUID().uuidString.lowercased()).invalid"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StoreCapabilityURLProtocol.self]
        session = URLSession(configuration: configuration)
        StoreCapabilityURLProtocol.registry.set(
            { [weak self] request in
                self?.increment()
                return try handler(request)
            },
            for: host
        )
        if delayed { StoreCapabilityURLProtocol.registry.setDelayed(host, value: true) }
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func waitForRequest() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if requestCount > 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.timedOut)
    }

    deinit {
        session.invalidateAndCancel()
        StoreCapabilityURLProtocol.registry.setDelayed(host, value: false)
        StoreCapabilityURLProtocol.registry.set(nil, for: host)
    }
}

private class StoreCapabilityURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = StoreCapabilityRegistry()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host,
            let handler = Self.registry.handler(for: host)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if Self.registry.isDelayed(host) {
            // Invoke the fixture handler only to record that URLSession started
            // the request, then intentionally leave the protocol pending.
            _ = try? handler(request)
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

private final class StoreCapabilityRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]

    private var delayedHosts: Set<String> = []

    func set(_ handler: Handler?, for host: String) {
        lock.lock()
        handlers[host] = handler
        lock.unlock()
    }

    func setDelayed(_ host: String, value: Bool) {
        lock.lock()
        if value { delayedHosts.insert(host) } else { delayedHosts.remove(host) }
        lock.unlock()
    }

    func isDelayed(_ host: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return delayedHosts.contains(host)
    }

    func handler(for host: String) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[host]
    }
}

private func storeResponse(status: Int = 200, body: Data) throws -> (URLResponse, Data) {
    let url = URL(string: "http://fixture.invalid")!
    return (HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, body)
}
