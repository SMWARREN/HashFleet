import Foundation
import Testing
@testable import HashFleet

@Suite("Miner discovery safety")
struct MinerDiscoveryTests {
    @Test func scanPlanIsBoundedToPrivateSlashTwentyFourAndSkipsThePhone() {
        let plan = MinerDiscoveryScanPlan.plan(forIPv4Address: "192.168.1.42")
        #expect(plan?.localAddress == "192.168.1.42")
        #expect(plan?.hosts.count == 253)
        #expect(plan?.hosts.first == "192.168.1.1")
        #expect(plan?.hosts.last == "192.168.1.254")
        #expect(plan?.hosts.contains("192.168.1.42") == false)
    }

    @Test(arguments: ["8.8.8.8", "172.15.0.4", "172.32.0.4", "192.0.2.7", "not-an-ip", "192.168.1.999"])
    func scanPlanRejectsPublicAndMalformedAddresses(_ address: String) {
        #expect(MinerDiscoveryScanPlan.plan(forIPv4Address: address) == nil)
    }

    @Test func validSystemInfoBecomesAReadOnlyCandidate() throws {
        let body = Data(#"{"hostname":"Desk Gamma","ASICModel":"BM1370","hashRate":1220,"power":19}"#.utf8)
        let candidate = MinerDiscoveryService.candidate(
            host: "192.168.1.17",
            statusCode: 200,
            contentType: "application/json",
            body: body
        )
        #expect(candidate?.name == "Desk Gamma")
        #expect(candidate?.model == "BM1370")
        #expect(candidate?.address == "192.168.1.17")
    }

    @Test func captivePortalHtmlAndUnknownJsonNeverBecomeMiners() {
        let html = Data("<html>sign in</html>".utf8)
        #expect(
            MinerDiscoveryService.candidate(
                host: "192.168.1.17",
                statusCode: 200,
                contentType: "text/html",
                body: html
            ) == nil
        )
        let unknown = Data(#"{"message":"hello"}"#.utf8)
        #expect(
            MinerDiscoveryService.candidate(
                host: "192.168.1.18",
                statusCode: 200,
                contentType: "application/json",
                body: unknown
            ) == nil
        )
        #expect(
            MinerDiscoveryService.candidate(
                host: "192.168.1.19",
                statusCode: 503,
                contentType: "application/json",
                body: unknown
            ) == nil
        )
    }
}

@Suite("Miner discovery ordering and grouping")
struct MinerDiscoveryOrderingTests {
    private func candidate(_ address: String, model: String? = nil, name: String = "m") -> MinerDiscoveryCandidate {
        MinerDiscoveryCandidate(address: address, name: name, model: model)
    }

    @Test func addressesSortNumericallyNotLexicographically() {
        let input = [
            candidate("192.168.1.10"),
            candidate("192.168.1.2"),
            candidate("192.168.1.9")
        ]
        // Lexicographic order would yield .10, .2, .9. A user comparing the list against
        // their rack expects numeric order.
        #expect(
            MinerDiscoveryService.sorted(input).map(\.address) ==
                ["192.168.1.2", "192.168.1.9", "192.168.1.10"]
        )
    }

    @Test func sameAddressTiesBreakByName() {
        let input = [
            candidate("192.168.1.7", name: "Zeta"),
            candidate("192.168.1.7", name: "Alpha")
        ]
        #expect(MinerDiscoveryService.sorted(input).map(\.name) == ["Alpha", "Zeta"])
    }

    @Test func groupingBucketingByModelSortsGroupsAndKeepsUnknownLast() {
        let groups = MinerDiscoveryGrouping.groups(for: [
            candidate("192.168.1.20", model: "BM1370"),
            candidate("192.168.1.9", model: "BM1368"),
            candidate("192.168.1.30", model: nil),
            candidate("192.168.1.2", model: "BM1370")
        ])
        #expect(groups.map(\.title) == ["BM1368", "BM1370", MinerDiscoveryGrouping.otherTitle])
        #expect(groups[1].candidates.map(\.address) == ["192.168.1.2", "192.168.1.20"])
        #expect(groups[2].candidates.map(\.address) == ["192.168.1.30"])
    }

    @Test func groupingMergesModelNamesThatDifferOnlyByCase() {
        let groups = MinerDiscoveryGrouping.groups(for: [
            candidate("192.168.1.2", model: "BM1370"),
            candidate("192.168.1.3", model: "bm1370")
        ])
        #expect(groups.count == 1)
        #expect(groups[0].candidates.count == 2)
    }

    @Test func singleGroupProducesOneSection() {
        let groups = MinerDiscoveryGrouping.groups(for: [
            candidate("192.168.1.2", model: "BM1370"),
            candidate("192.168.1.3", model: "BM1370")
        ])
        #expect(groups.count == 1)
    }
}

@Suite("Miner discovery bounded fallback")
struct MinerDiscoveryFallbackTests {
    private func response(host: String, status: Int = 200, body: String = #"{"hostname":"Recovered miner","ASICModel":"BM1370","hashRate":1}"#) -> (Data, URLResponse) {
        let url = URL(string: "http://\(host)/api/system/info")!
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }

    @Test func retriesOnlyTransientHostsAndKeepsFoundCandidates() async throws {
        let hosts = ["192.168.1.1", "192.168.1.2", "192.168.1.3"]
        let plan = MinerDiscoveryScanPlan(localAddress: "192.168.1.9", hosts: hosts)
        let calls = CallLedger()
        let progress = ProgressLedger()
        let found = try await MinerDiscoveryService.scan(plan: plan, onProgress: { batch, count in
            progress.append(batch: batch, count: count)
        }, transport: { request in
            let host = request.url!.host!
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/system/info")
            calls.append(host, timeout: request.timeoutInterval)
            if host == hosts[0] { return response(host: host) }
            if host == hosts[1] {
                // Simulate the short first deadline then succeed on selective fallback.
                if request.timeoutInterval < 2 { throw URLError(.timedOut) }
                try await Task.sleep(for: .milliseconds(30))
                return response(host: host)
            }
            return response(host: host, status: 200, body: "<html>portal</html>")
        })
        #expect(found.map(\.address).sorted() == Array(hosts.prefix(2)).sorted())
        #expect(Set(found.map(\.address)).count == found.count)
        #expect(calls.count(for: hosts[0]) == 1)
        #expect(calls.count(for: hosts[1]) == 2)
        #expect(calls.count(for: hosts[2]) == 1)
        #expect(calls.timeouts(for: hosts[1]) == [1, 2.5])
        let updates = progress.snapshot()
        #expect(updates.map(\.count) == [hosts.count, hosts.count])
        #expect(updates.map { $0.batch.map(\.address) } == [[hosts[0]], [hosts[1]]])
    }

    @Test func earlyTimeoutsDoNotStarveRetryAtEndOfSubnet() async throws {
        let plan = try #require(MinerDiscoveryScanPlan.plan(forIPv4Address: "192.168.1.42"))
        let late = try #require(plan.hosts.last)
        let quick = try #require(plan.hosts.first)
        let calls = CallLedger()
        let found = try await MinerDiscoveryService.scan(plan: plan, transport: { request in
            let host = request.url!.host!
            calls.append(host, timeout: request.timeoutInterval)
            if host == quick || (host == late && request.timeoutInterval > 1) { return response(host: host) }
            throw URLError(.timedOut)
        })
        #expect(found.map(\.address) == [quick, late])
        #expect(calls.total == plan.hosts.count * 2 - 1)
        #expect(calls.timeouts(for: late) == [1, 2.5])
        #expect(calls.count(for: plan.localAddress) == 0)
    }

    @Test func slowHTTPMinerIsFoundWithTheProductionTransport() async throws {
        let server = try LoopbackMinerServer()
        defer { server.stop() }
        server.setInfoResponse(status: 200, json: #"{"hostname":"Slow HTTP miner","ASICModel":"BM1370","hashRate":1234}"#)
        server.setInfoDelay(1.4)
        let address = try server.start()
        // The production plan factory remains limited to its local IPv4 subnet.
        // Only this handcrafted fixture plan can specify a random local port.
        let plan = MinerDiscoveryScanPlan(localAddress: "127.0.0.1", hosts: [address])
        let progress = ProgressLedger()
        let found = try await MinerDiscoveryService.scan(plan: plan, onProgress: { batch, count in
            progress.append(batch: batch, count: count)
        })
        #expect(found.map(\.name) == ["Slow HTTP miner"])
        #expect(progress.snapshot().map { $0.batch.count } == [0, 1])
        #expect(server.journal.map(\.method) == ["GET", "GET"])
        #expect(server.journal.allSatisfy { $0.path == "/api/system/info" })
    }

    @Test func cancellationStopsFallbackWork() async throws {
        let host = "192.168.1.1"
        let plan = MinerDiscoveryScanPlan(localAddress: "192.168.1.9", hosts: [host])
        let started = CallLedger()
        let task = Task {
            try await MinerDiscoveryService.scan(plan: plan, transport: { request in
                started.append(request.url!.host!, timeout: request.timeoutInterval)
                if request.timeoutInterval < 2 { throw URLError(.timedOut) }
                try await Task.sleep(for: .seconds(10))
                return response(host: request.url!.host!)
            })
        }
        defer { task.cancel() }
        let deadline = ContinuousClock.now + .seconds(2)
        while started.count(for: host) < 2 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(started.timeouts(for: host) == [1, 2.5])
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
        #expect(started.count(for: host) == 2)
    }

    @Test func deniedNetworkIsNotTreatedAsASlowMiner() async {
        let plan = MinerDiscoveryScanPlan(localAddress: "192.168.1.9", hosts: ["192.168.1.1"])
        let calls = CallLedger()
        do {
            _ = try await MinerDiscoveryService.scan(plan: plan, transport: { request in
                calls.append(request.url!.host!, timeout: request.timeoutInterval)
                throw URLError(.dataNotAllowed)
            })
            Issue.record("Expected unavailable network")
        } catch MinerDiscoveryService.ScanError.networkUnavailable {
            #expect(calls.total == 1)
        } catch {
            Issue.record("Unexpected scan error: \(error)")
        }
    }
}

private final class CallLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(String, TimeInterval)] = []
    func append(_ host: String, timeout: TimeInterval) { lock.lock(); calls.append((host, timeout)); lock.unlock() }
    var total: Int { lock.lock(); defer { lock.unlock() }; return calls.count }
    func count(for host: String) -> Int { lock.lock(); defer { lock.unlock() }; return calls.filter { $0.0 == host }.count }
    func timeouts(for host: String) -> [TimeInterval] { lock.lock(); defer { lock.unlock() }; return calls.filter { $0.0 == host }.map(\.1).sorted() }
}

private final class ProgressLedger: @unchecked Sendable {
    private let lock = NSLock()
    typealias Entry = (batch: [MinerDiscoveryCandidate], count: Int)
    private var entries: [Entry] = []
    func append(batch: [MinerDiscoveryCandidate], count: Int) { lock.lock(); entries.append((batch, count)); lock.unlock() }
    func snapshot() -> [Entry] { lock.lock(); defer { lock.unlock() }; return entries }
}
