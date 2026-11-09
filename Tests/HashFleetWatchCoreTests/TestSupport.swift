import Foundation
@testable import HashFleetWatchCore

func temporaryStorageURL(_ name: String = "fleet.json") -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("HashFleetWatchCoreTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(name)
}

func cleanUp(_ url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

/// Scripted client. Records every miner it was asked to read and lets a test hold or fail individual reads.
actor ScriptedClient: WatchMinerReadingClient {
    enum Behavior: Sendable {
        case succeed(hashrate: Double)
        case fail
        case hang
    }

    private var behaviors: [String: Behavior] = [:]
    private var defaultBehavior: Behavior
    private(set) var fetched: [String] = []
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]
    private var gated: Set<String> = []
    private var maxConcurrent = 0
    private var concurrent = 0
    private var nextObservedAt: Date?

    init(default behavior: Behavior = .succeed(hashrate: 500)) {
        self.defaultBehavior = behavior
    }

    func set(_ behavior: Behavior, for address: String) { behaviors[address] = behavior }
    func setDefault(_ behavior: Behavior) { defaultBehavior = behavior }
    func hold(_ address: String) { gated.insert(address) }
    func setObservedAt(_ date: Date?) { nextObservedAt = date }
    func release(_ address: String) {
        gated.remove(address)
        gates.removeValue(forKey: address)?.resume()
    }
    func fetchCount() -> Int { fetched.count }
    func peakConcurrency() -> Int { maxConcurrent }
    func isWaiting(_ address: String) -> Bool { gates[address] != nil }

    func fetch(_ miner: WatchMiner) async throws -> WatchMinerReading {
        fetched.append(miner.address)
        concurrent += 1
        maxConcurrent = max(maxConcurrent, concurrent)
        defer { concurrent -= 1 }
        if gated.contains(miner.address) {
            await withCheckedContinuation { gates[miner.address] = $0 }
        }
        switch behaviors[miner.address] ?? defaultBehavior {
        case let .succeed(hashrate):
            return WatchMinerReading(
                minerID: miner.id,
                observedAt: nextObservedAt ?? Date(),
                hashrateGHs: hashrate,
                powerWatts: 10
            )
        case .fail:
            throw WatchMinerFetchError.unreachable
        case .hang:
            try await Task.sleep(for: .seconds(60))
            throw WatchMinerFetchError.timedOut
        }
    }
}

/// URLProtocol that serves canned responses and records requests. Never opens a socket.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status = 200
        var body = Data()
        var redirectTo: URL?
        /// Fail the load with this URL error instead of responding.
        var failure: URLError.Code?
        /// Never respond. The load stays open until it is cancelled.
        var stalls = false
        /// Send headers, then one harmless byte per second forever. Defeats the idle timeout.
        var trickles = false
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> Response)?
    nonisolated(unsafe) private static var seen: [URLRequest] = []
    nonisolated(unsafe) private static var stopped = 0
    nonisolated(unsafe) private static var generation = 0
    nonisolated(unsafe) private static var stopTimes: [ContinuousClock.Instant] = []

    static func install(_ handler: @escaping @Sendable (URLRequest) -> Response) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        seen = []
        stopped = 0
        stopTimes = []
        // A load from an earlier test that is torn down late must not count toward this one.
        generation += 1
    }

    private static func stopInstant(_ count: Int) -> ContinuousClock.Instant? {
        lock.lock(); defer { lock.unlock() }
        return stopTimes.count >= count ? stopTimes[count - 1] : nil
    }

    /// Waits (bounded) for at least `count` loads of the current generation to be torn down.
    ///
    /// URLSession delivers `stopLoading` asynchronously on the protocol's own queue after a task is cancelled
    /// or finishes, so it can trail the caller's cancellation result by a few milliseconds. Returns the instant
    /// the stop was observed, or nil on timeout.
    static func waitForStop(count: Int = 1, timeout: Duration = .seconds(5)) async -> ContinuousClock.Instant? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let instant = stopInstant(count) { return instant }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    /// How many loads were torn down (cancelled or finished) since `install`.
    static var stopCount: Int {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.seen.append(request)
        startedGeneration = Self.generation
        let handler = Self.handler
        Self.lock.unlock()
        let response = handler?(request) ?? Response(status: 500)
        guard let url = request.url else { return }
        if response.stalls { return }
        if response.trickles {
            let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didLoad: Data(" ".utf8))
            }
            Self.lock.lock(); self.timer = timer; Self.lock.unlock()
            timer.resume()
            return
        }
        if let code = response.failure {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        if let target = response.redirectTo {
            let http = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: http)
            // If the delegate refuses the redirect, the 302 itself is the final response.
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private var timer: DispatchSourceTimer?
    private var startedGeneration = -1

    override func stopLoading() {
        Self.lock.lock()
        if startedGeneration == Self.generation {
            Self.stopped += 1
            Self.stopTimes.append(ContinuousClock().now)
        }
        timer?.cancel()
        timer = nil
        Self.lock.unlock()
    }
}
