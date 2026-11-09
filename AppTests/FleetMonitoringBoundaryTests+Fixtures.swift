import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Thread-safe box for capturing mutable test state across Sendable boundaries.
final class LockedBox<T>: @unchecked Sendable {
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
