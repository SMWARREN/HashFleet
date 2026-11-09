import Foundation
import Testing
@testable import HashFleetWatchCore

/// A `URLProtocol` stub for discovery tests. It routes canned responses by host, records every request, tracks
/// peak concurrency, and can delay or stall responses. It never opens a socket.
final class DiscoveryStubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status = 200
        var body = Data()
        /// nil means "omit the Content-Type header entirely".
        var contentType: String? = "application/json"
        var redirectTo: URL?
        var failure: URLError.Code?
        /// Delay before the response is delivered.
        var delay: Duration = .zero
        /// Never deliver; stays open until cancelled.
        var stalls = false
        /// Declared Content-Length, overriding the real body length (to test the declared-oversize guard).
        var declaredLength: Int?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (String) -> Response)?
    nonisolated(unsafe) private static var seen: [URLRequest] = []
    nonisolated(unsafe) private static var active = 0
    nonisolated(unsafe) private static var peak = 0
    nonisolated(unsafe) private static var stopped = 0
    nonisolated(unsafe) private static var started = 0
    nonisolated(unsafe) private static var generation = 0

    static func install(_ handler: @escaping @Sendable (_ host: String) -> Response) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        seen = []
        active = 0
        peak = 0
        stopped = 0
        started = 0
        // A load from an earlier test torn down late must not mutate this test's counters.
        generation += 1
    }

    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    static var peakConcurrency: Int { lock.lock(); defer { lock.unlock() }; return peak }
    static var startedCount: Int { lock.lock(); defer { lock.unlock() }; return started }
    static var stopCount: Int { lock.lock(); defer { lock.unlock() }; return stopped }
    static var activeCount: Int { lock.lock(); defer { lock.unlock() }; return active }
    static var requestedHosts: [String] { requests.compactMap { $0.url?.host } }

    /// Synchronous snapshot of (started, active), taken under the lock. Safe to call from async code because it
    /// never holds the lock across a suspension point.
    static func counts() -> (started: Int, active: Int) {
        lock.lock(); defer { lock.unlock() }
        return (started, active)
    }

    /// Waits (bounded) until every started load of the current generation has been torn down, i.e. no load is
    /// still in flight. Returns true if quiescent, false on timeout.
    static func waitForQuiescent(timeout: Duration = .seconds(5)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            let (started, active) = counts()
            if started > 0 && active == 0 { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    /// Waits (bounded) until at least `count` loads of the current generation have started. Returns true if the
    /// barrier was reached, false on timeout.
    static func waitForStarted(_ count: Int, timeout: Duration = .seconds(5)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if startedCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    static func session() -> URLSession {
        WatchSecureHTTP.ephemeralSession(
            requestTimeout: 1.0, resourceTimeout: 1.5, protocolClasses: [DiscoveryStubURLProtocol.self]
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var work: DispatchWorkItem?
    private var startedGeneration = -1
    private var accounted = false

    override func startLoading() {
        Self.lock.lock()
        Self.seen.append(request)
        Self.active += 1
        Self.started += 1
        Self.peak = max(Self.peak, Self.active)
        startedGeneration = Self.generation
        accounted = true
        let handler = Self.handler
        Self.lock.unlock()

        let host = request.url?.host ?? ""
        let response = handler?(host) ?? Response(status: 404)
        let item = DispatchWorkItem { [weak self] in self?.deliver(response) }
        work = item
        if response.delay == .zero {
            DispatchQueue.global().async(execute: item)
        } else {
            let seconds = Double(response.delay.components.seconds)
                + Double(response.delay.components.attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
        }
    }

    private func deliver(_ response: Response) {
        guard let url = request.url else { return }
        if response.stalls { return }
        if let code = response.failure {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        if let target = response.redirectTo {
            let http = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: http)
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var headers: [String: String] = [:]
        if let type = response.contentType { headers["Content-Type"] = type }
        if let declared = response.declaredLength { headers["Content-Length"] = String(declared) }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        work?.cancel()
        work = nil
        Self.lock.lock()
        // Decrement exactly once, and only against the generation this load actually started in.
        if accounted {
            accounted = false
            if startedGeneration == Self.generation {
                Self.active -= 1
                Self.stopped += 1
            }
        }
        Self.lock.unlock()
    }
}

/// Serves one eligible interface (or none) for the scanner.
struct StubInterfaceProvider: WatchNetworkInterfaceProviding {
    let interface: WatchNetworkInterface?
    func localInterface() -> WatchNetworkInterface? { interface }

    init(_ interface: WatchNetworkInterface?) { self.interface = interface }

    init?(address: String, netmask: String) {
        guard let a = WatchDiscoveryPlan.parseStrictIPv4(address),
              let m = WatchDiscoveryPlan.parseStrictIPv4(netmask) else { return nil }
        self.interface = WatchNetworkInterface(address: a, netmask: m)
    }
}

/// Collects progress callbacks for assertions.
actor ProgressLog {
    private(set) var snapshots: [WatchDiscoveryProgress] = []
    func record(_ p: WatchDiscoveryProgress) { snapshots.append(p) }
    func all() -> [WatchDiscoveryProgress] { snapshots }
}

@Suite(.serialized) struct WatchDiscoveryScannerTests {
    /// A valid miner body for a given model.
    private func minerBody(hostname: String, model: String = "BM1370") -> Data {
        Data(#"{"ASICModel":"\#(model)","hashRate":500,"power":12,"hostname":"\#(hostname)"}"#.utf8)
    }

    /// Interface on a /29: self .50, candidates .49,.51,.52,.53,.54 (5 hosts).
    private func slash29Provider() -> StubInterfaceProvider {
        StubInterfaceProvider(address: "192.168.1.50", netmask: "255.255.255.248")!
    }

    private func policy(
        overall: TimeInterval = 10, perHost: TimeInterval = 1.5, maxConcurrent: Int = 8
    ) -> WatchDiscoveryPolicy {
        WatchDiscoveryPolicy(perHostDeadline: perHost, overallBudget: overall, maxConcurrent: maxConcurrent)
    }

    // MARK: Happy path

    @Test func findsOnlyGenuineMinersSortedByHost() async throws {
        DiscoveryStubURLProtocol.install { host in
            switch host {
            case "192.168.1.51": return .init(body: self.minerBody(hostname: "alpha"))
            case "192.168.1.53": return .init(body: self.minerBody(hostname: "beta"))
            default: return .init(status: 404) // everything else: not a miner
            }
        }
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(),
            policy: policy(overall: 10)
        )
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await scanner.scan { _ in }
        let elapsed = start.duration(to: clock.now)
        #expect(result.totalHosts == 5)
        #expect(result.completedHosts == 5)
        #expect(!result.reachedTimeLimit)
        #expect(!result.isPartialSubnet)
        #expect(result.miners.map(\.address) == ["http://192.168.1.51", "http://192.168.1.53"])
        #expect(result.miners.map(\.name) == ["alpha", "beta"])
        // A fully-successful scan must finish promptly, nowhere near the 10s budget (no timer-wait).
        #expect(elapsed < .seconds(2), "successful scan should complete promptly, took \(elapsed)")
        #expect(await DiscoveryStubURLProtocol.waitForQuiescent(), "all loads torn down")
        #expect(DiscoveryStubURLProtocol.stopCount == DiscoveryStubURLProtocol.startedCount)
    }

    // MARK: Request shape / safety

    @Test func issuesOnlyReadOnlyGETToSystemInfoOncePerHost() async throws {
        DiscoveryStubURLProtocol.install { _ in .init(status: 404) }
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(), policy: policy()
        )
        _ = try await scanner.scan { _ in }
        let requests = DiscoveryStubURLProtocol.requests
        #expect(requests.count == 5)
        for request in requests {
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/system/info")
            #expect(request.url?.port == 80)
            #expect(request.httpBody == nil)
            #expect(request.httpShouldHandleCookies == false)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
            #expect(request.timeoutInterval <= 1.0) // per-request timeout ~1s
        }
        // Each candidate host probed exactly once.
        let hosts = DiscoveryStubURLProtocol.requestedHosts.sorted()
        #expect(Set(hosts).count == hosts.count)
        #expect(Set(hosts) == ["192.168.1.49", "192.168.1.51", "192.168.1.52", "192.168.1.53", "192.168.1.54"])
    }

    @Test func refusesRedirectsAndNeverProbesTarget() async throws {
        DiscoveryStubURLProtocol.install { host in
            if host == "192.168.1.51" { return .init(redirectTo: URL(string: "http://8.8.8.8/api/system/info")) }
            return .init(status: 404)
        }
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(), policy: policy()
        )
        let result = try await scanner.scan { _ in }
        #expect(result.miners.isEmpty)
        #expect(!DiscoveryStubURLProtocol.requestedHosts.contains("8.8.8.8"))
    }

    @Test func rejectsNon200Status() async throws {
        DiscoveryStubURLProtocol.install { host in
            // A real miner body but a non-200 status must not be auto-added.
            if host == "192.168.1.51" { return .init(status: 201, body: self.minerBody(hostname: "x")) }
            return .init(status: 500, body: self.minerBody(hostname: "y"))
        }
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(), policy: policy()
        )
        let result = try await scanner.scan { _ in }
        #expect(result.miners.isEmpty)
    }

    @Test func rejectsNonJSONContentTypeButAcceptsAbsentAndPlusJSON() async throws {
        DiscoveryStubURLProtocol.install { host in
            switch host {
            case "192.168.1.51": return .init(body: self.minerBody(hostname: "html"), contentType: "text/html")
            case "192.168.1.52": return .init(body: self.minerBody(hostname: "none"), contentType: nil)
            case "192.168.1.53": return .init(body: self.minerBody(hostname: "plus"), contentType: "application/problem+json; charset=utf-8")
            default: return .init(status: 404)
            }
        }
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(), policy: policy()
        )
        let result = try await scanner.scan { _ in }
        // text/html rejected; absent and +json accepted.
        #expect(result.miners.map(\.name).sorted() == ["none", "plus"])
    }

    @Test func rejectsStreamedOversizeBody() async throws {
        let big = Data(repeating: UInt8(ascii: " "), count: WatchMinerHTTPClient.maximumResponseBytes + 1024)
        DiscoveryStubURLProtocol.install { host in
            if host == "192.168.1.51" { return .init(body: big) }
            return .init(status: 404)
        }
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(), policy: policy()
        )
        let result = try await scanner.scan { _ in }
        #expect(result.miners.isEmpty)
    }

    @Test func rejectsDeclaredOversizeBody() async throws {
        DiscoveryStubURLProtocol.install { host in
            if host == "192.168.1.51" {
                return .init(body: self.minerBody(hostname: "x"),
                             declaredLength: WatchMinerHTTPClient.maximumResponseBytes + 10)
            }
            return .init(status: 404)
        }
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(), policy: policy()
        )
        let result = try await scanner.scan { _ in }
        #expect(result.miners.isEmpty)
    }

    @Test func timeoutHostIsNotDiscoveredAndNotTreatedAsMiner() async throws {
        DiscoveryStubURLProtocol.install { host in
            if host == "192.168.1.51" { return .init(stalls: true) }   // never answers
            return .init(status: 404)
        }
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(),
            policy: policy(overall: 10, perHost: 0.3)
        )
        let result = try await scanner.scan { _ in }
        #expect(result.miners.isEmpty)
        #expect(result.completedHosts == 5) // the stalled host still completes (as "no miner") within per-host deadline
        #expect(!result.reachedTimeLimit)
    }

    // MARK: Concurrency

    @Test func concurrencyNeverExceedsEight() async throws {
        // /27: self .50 in .32-.63 => 29 candidates, all briefly delayed to force overlap.
        let provider = StubInterfaceProvider(address: "192.168.1.50", netmask: "255.255.255.224")!
        DiscoveryStubURLProtocol.install { _ in .init(status: 404, delay: .milliseconds(40)) }
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: provider, session: DiscoveryStubURLProtocol.session(), policy: policy(maxConcurrent: 8)
        )
        let result = try await scanner.scan { _ in }
        #expect(result.totalHosts == 29)
        #expect(result.completedHosts == 29)
        #expect(DiscoveryStubURLProtocol.peakConcurrency <= 8)
        #expect(DiscoveryStubURLProtocol.peakConcurrency >= 2) // genuinely ran in parallel
    }

    // MARK: Progress

    @Test func progressIsCumulativeMonotonicSortedAndUnique() async throws {
        DiscoveryStubURLProtocol.install { host in
            switch host {
            case "192.168.1.49": return .init(body: self.minerBody(hostname: "a"))
            case "192.168.1.52": return .init(body: self.minerBody(hostname: "b"))
            case "192.168.1.54": return .init(body: self.minerBody(hostname: "c"))
            default: return .init(status: 404)
            }
        }
        let log = ProgressLog()
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(), policy: policy()
        )
        let result = try await scanner.scan { p in await log.record(p) }
        let snaps = await log.all()
        #expect(!snaps.isEmpty)
        // completedHosts strictly increases by 1 each callback and matches the final total.
        #expect(snaps.map(\.completedHosts) == Array(1...5))
        #expect(snaps.last?.completedHosts == result.completedHosts)
        var previousCount = 0
        for snap in snaps {
            // Cumulative: never shrinks.
            #expect(snap.miners.count >= previousCount)
            previousCount = snap.miners.count
            // Always sorted ascending and unique by endpoint.
            let numeric = snap.miners.map { WatchDiscoveryPlan.parseStrictIPv4($0.address.replacingOccurrences(of: "http://", with: ""))! }
            #expect(numeric == numeric.sorted())
            #expect(Set(snap.miners.map(\.address)).count == snap.miners.count)
            #expect(snap.totalHosts == 5)
        }
        #expect(result.miners.map(\.name) == ["a", "b", "c"])
    }

    // MARK: Overall budget

    @Test func overallBudgetReturnsPartialResultWithReachedTimeLimit() async throws {
        // 5 hosts, each delayed ~0.5s, but overall budget 0.2s and only a few can run before the timer fires.
        DiscoveryStubURLProtocol.install { _ in .init(status: 404, delay: .milliseconds(500)) }
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(),
            policy: policy(overall: 0.2, perHost: 1.5)
        )
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await scanner.scan { _ in }
        let elapsed = start.duration(to: clock.now)
        #expect(result.reachedTimeLimit)
        #expect(result.completedHosts < result.totalHosts)
        #expect(result.totalHosts == 5)
        // Hitting the budget is NOT a throw: a partial result is returned.
        // The scan ended on the 0.2s budget, well before the 1.5s per-host deadline or the 0.5s stub delay.
        #expect(elapsed < .seconds(1), "scan should end on the 0.2s budget, took \(elapsed)")
        // In-flight probes were torn down when the budget fired.
        #expect(await DiscoveryStubURLProtocol.waitForQuiescent(), "in-flight loads torn down on budget")
        #expect(DiscoveryStubURLProtocol.stopCount == DiscoveryStubURLProtocol.startedCount)
    }

    // MARK: Cancellation

    @Test func callerCancellationThrowsAndStopsLateProgress() async throws {
        DiscoveryStubURLProtocol.install { _ in .init(status: 404, delay: .milliseconds(300)) }
        let log = ProgressLog()
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: slash29Provider(), session: DiscoveryStubURLProtocol.session(), policy: policy()
        )
        let clock = ContinuousClock()
        let task = Task { try await scanner.scan { p in await log.record(p) } }
        // Barrier: wait until probes are actually in flight, not a fixed sleep.
        #expect(await DiscoveryStubURLProtocol.waitForStarted(1), "probes should start")
        let cancelAt = clock.now
        task.cancel()
        var threwCancellation = false
        do { _ = try await task.value } catch is CancellationError { threwCancellation = true } catch { Issue.record("expected CancellationError, got \(error)") }
        let returnedAfter = cancelAt.duration(to: clock.now)
        #expect(threwCancellation)
        // Cancellation must return promptly, well under the 300ms stub delay / per-host deadline.
        #expect(returnedAfter < .seconds(1), "cancel returned in \(returnedAfter)")
        // In-flight loads were torn down.
        #expect(await DiscoveryStubURLProtocol.waitForQuiescent(), "in-flight loads torn down on cancel")
        #expect(DiscoveryStubURLProtocol.stopCount == DiscoveryStubURLProtocol.startedCount)
        // Any progress seen must have been monotonic; completedHosts increments by 1 (empty is also valid).
        let snaps = await log.all()
        #expect(snaps.map(\.completedHosts) == Array(0..<snaps.count).map { $0 + 1 })
        // No late callback after cancel: record count must not grow after a further delay.
        let countAtCancel = snaps.count
        try await Task.sleep(for: .milliseconds(400))
        #expect(await log.all().count == countAtCancel)
    }

    // MARK: Plan edges via scan

    @Test func noLocalWiFiWhenNoInterface() async {
        let scanner = WatchLocalMinerDiscovery(interfaceProvider: StubInterfaceProvider(nil))
        await #expect(throws: WatchDiscoveryError.noLocalWiFi) { try await scanner.scan { _ in } }
    }

    @Test func emptyPlanCompletesImmediatelyWithNoRequests() async throws {
        DiscoveryStubURLProtocol.install { _ in .init(status: 404) }
        // /31 => zero candidates.
        let provider = StubInterfaceProvider(address: "192.168.1.4", netmask: "255.255.255.254")!
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: provider, session: DiscoveryStubURLProtocol.session(), policy: policy()
        )
        let result = try await scanner.scan { _ in }
        #expect(result.totalHosts == 0)
        #expect(result.miners.isEmpty)
        #expect(DiscoveryStubURLProtocol.requests.isEmpty)
    }

    @Test func widerThanSlash24MarksPartialSubnet() async throws {
        DiscoveryStubURLProtocol.install { _ in .init(status: 404) }
        // 10.5.6.7/16 => scan only 10.5.6.x, partial.
        let provider = StubInterfaceProvider(address: "10.5.6.7", netmask: "255.255.0.0")!
        let scanner = WatchLocalMinerDiscovery(
            interfaceProvider: provider, session: DiscoveryStubURLProtocol.session(), policy: policy()
        )
        let result = try await scanner.scan { _ in }
        #expect(result.isPartialSubnet)
        #expect(result.totalHosts <= WatchDiscoveryPlan.maximumHosts)
        #expect(DiscoveryStubURLProtocol.requestedHosts.allSatisfy { $0.hasPrefix("10.5.6.") })
    }

    // MARK: Content-type rule (direct)

    @Test func contentTypeAcceptabilityRule() {
        func header(_ value: String?) -> HTTPURLResponse {
            var fields: [String: String] = [:]
            if let value { fields["Content-Type"] = value }
            return HTTPURLResponse(url: URL(string: "http://192.168.1.1/api/system/info")!,
                                   statusCode: 200, httpVersion: "HTTP/1.1", headerFields: fields)!
        }
        // Accepted
        #expect(WatchLocalMinerDiscovery.contentTypeAcceptable(header(nil)))                       // absent
        #expect(WatchLocalMinerDiscovery.contentTypeAcceptable(header("application/json")))
        #expect(WatchLocalMinerDiscovery.contentTypeAcceptable(header("application/json; charset=utf-8")))
        #expect(WatchLocalMinerDiscovery.contentTypeAcceptable(header("APPLICATION/JSON")))
        #expect(WatchLocalMinerDiscovery.contentTypeAcceptable(header("application/problem+json")))
        // Rejected
        #expect(!WatchLocalMinerDiscovery.contentTypeAcceptable(header("text/html")))
        #expect(!WatchLocalMinerDiscovery.contentTypeAcceptable(header("text/plain")))
        #expect(!WatchLocalMinerDiscovery.contentTypeAcceptable(header("+json")))                   // bare suffix
        #expect(!WatchLocalMinerDiscovery.contentTypeAcceptable(header("application/+json")))        // empty subtype
        #expect(!WatchLocalMinerDiscovery.contentTypeAcceptable(header("text/vnd+json")))            // not application/
    }
}
