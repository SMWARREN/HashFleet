import Foundation
import Testing
@testable import HashFleetWatchCore

/// Serialized because StubURLProtocol keeps process-wide state.
@Suite(.serialized) struct WatchMinerHTTPClientTests {
    private let observed = Date(timeIntervalSince1970: 1_800_000_000)

    private func client() -> WatchMinerHTTPClient {
        WatchMinerHTTPClient(session: StubURLProtocol.session(), now: { [observed] in observed })
    }

    private func miner(_ address: String = "192.168.1.50:8080") throws -> WatchMiner {
        try WatchMiner(name: "Test", address: address)
    }

    @Test func issuesOnlyReadOnlyGETToFixedPath() async throws {
        StubURLProtocol.install { _ in .init(body: Data(#"{"hashRate":9}"#.utf8)) }
        let m = try miner()
        let reading = try await client().fetch(m)
        #expect(reading.hashrateGHs == 9)
        #expect(reading.observedAt == observed)
        let requests = StubURLProtocol.requests
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].url?.absoluteString == "http://192.168.1.50:8080/api/system/info")
        #expect(requests[0].httpBody == nil)
        #expect(requests[0].httpShouldHandleCookies == false)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[0].cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test func requestBuilderUsesNormalizedEndpoint() throws {
        let request = try WatchMinerHTTPClient.request(for: miner("https://miner.local/"))
        #expect(request.url?.absoluteString == "https://miner.local/api/system/info")
        #expect(request.httpMethod == "GET")
    }

    @Test func defaultSessionIsEphemeralAndBounded() {
        let session = WatchMinerHTTPClient.makeDefaultSession()
        let c = session.configuration
        #expect(c.urlCache == nil)
        #expect(c.httpCookieStorage == nil)
        #expect(c.urlCredentialStorage == nil)
        #expect(c.httpShouldSetCookies == false)
        #expect(c.timeoutIntervalForRequest <= 10)
        #expect(c.timeoutIntervalForResource <= 15)
        #expect(c.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test func rejectsHTTPErrorStatus() async throws {
        StubURLProtocol.install { _ in .init(status: 500, body: Data(#"{"hashRate":9}"#.utf8)) }
        await #expect(throws: WatchMinerFetchError.badStatus) { try await client().fetch(miner()) }
    }

    @Test func rejectsRedirects() async throws {
        StubURLProtocol.install { _ in .init(redirectTo: URL(string: "http://8.8.8.8/api/system/info")) }
        await #expect(throws: WatchMinerFetchError.redirected) { try await client().fetch(miner()) }
        // The redirect target must never be requested.
        #expect(StubURLProtocol.requests.allSatisfy { $0.url?.host != "8.8.8.8" })
    }

    @Test func rejectsOversizedResponses() async throws {
        let big = Data(repeating: UInt8(ascii: " "), count: WatchMinerHTTPClient.maximumResponseBytes + 10)
        StubURLProtocol.install { _ in .init(body: big) }
        await #expect(throws: WatchMinerFetchError.responseTooLarge) { try await client().fetch(miner()) }
    }

    @Test func rejectsInvalidJSON() async throws {
        StubURLProtocol.install { _ in .init(body: Data("<html>login</html>".utf8)) }
        await #expect(throws: WatchMinerFetchError.invalidResponse) { try await client().fetch(miner()) }
    }

    @Test func errorsAreGenericAndLeakNothing() async throws {
        StubURLProtocol.install { _ in .init(status: 503, body: Data("secret-body-token".utf8)) }
        do {
            _ = try await client().fetch(miner("192.168.7.77"))
            Issue.record("expected failure")
        } catch {
            let text = error.localizedDescription
            #expect(!text.contains("192.168.7.77"))
            #expect(!text.contains("secret-body-token"))
        }
    }

    @Test func cancellationIsPropagatedNotReportedAsFailure() async throws {
        StubURLProtocol.install { _ in .init(body: Data(#"{"hashRate":9}"#.utf8)) }
        let c = client()
        let m = try miner()
        let task = Task { try await c.fetch(m) }
        task.cancel()
        do {
            _ = try await task.value
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test(arguments: [
        (URLError.Code.timedOut, WatchMinerFetchError.timedOut),
        (.cannotConnectToHost, .unreachable),
        (.notConnectedToInternet, .unreachable),
        (.networkConnectionLost, .unreachable),
        (.httpTooManyRedirects, .redirected)
    ])
    func mapsURLErrorsToSafeErrors(code: URLError.Code, expected: WatchMinerFetchError) async throws {
        StubURLProtocol.install { _ in .init(failure: code) }
        do {
            _ = try await client().fetch(miner("192.168.9.9"))
            Issue.record("expected failure")
        } catch let error as WatchMinerFetchError {
            #expect(error == expected)
            #expect(!error.localizedDescription.contains("192.168.9.9"))
            #expect(!error.localizedDescription.lowercased().contains("nsurl"))
        }
    }

    /// A response that never starts is bounded by the per-request timeout (which is shorter than the overall one).
    @Test func totallyStalledLoadTimesOutSafely() async throws {
        StubURLProtocol.install { _ in .init(stalls: true) }
        let c = client()
        let m = try miner()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await c.fetch(m)
            Issue.record("expected a timeout")
        } catch {
            #expect(error as? WatchMinerFetchError == .timedOut)
        }
        let elapsed = start.duration(to: clock.now)
        #expect(elapsed >= .seconds(WatchMinerHTTPClient.requestTimeout - 2))
        #expect(elapsed < .seconds(WatchMinerHTTPClient.overallTimeout + 10))
        #expect(await StubURLProtocol.waitForStop() != nil, "The stalled load was never torn down")
    }

    /// A slow drip keeps resetting the idle timeout, so only the overall deadline can end it.
    @Test func slowDripIsCutOffByOverallDeadline() async throws {
        StubURLProtocol.install { _ in .init(trickles: true) }
        let c = client()
        let m = try miner()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await c.fetch(m)
            Issue.record("expected the overall deadline to fire")
        } catch {
            #expect(error as? WatchMinerFetchError == .timedOut)
        }
        let elapsed = start.duration(to: clock.now)
        // Beyond the per-request timeout, near the overall deadline, with a generous ceiling.
        #expect(elapsed >= .seconds(WatchMinerHTTPClient.overallTimeout - 1))
        #expect(elapsed < .seconds(WatchMinerHTTPClient.overallTimeout + 10))
        // The dripping load was torn down, not left running.
        #expect(await StubURLProtocol.waitForStop() != nil, "The dripping load was never torn down")
    }

    @Test func cancellingAStalledLoadReturnsPromptly() async throws {
        StubURLProtocol.install { _ in .init(stalls: true) }
        let c = client()
        let m = try miner()
        let task = Task { try await c.fetch(m) }
        // Wait until the request actually reached the protocol.
        let clock = ContinuousClock()
        let waitStart = clock.now
        while StubURLProtocol.requests.isEmpty, waitStart.duration(to: clock.now) < .seconds(5) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!StubURLProtocol.requests.isEmpty)
        let cancelStart = clock.now
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
        // Cancellation itself must be prompt. Teardown delivery is asynchronous, so it gets its own bounded wait.
        let cancelReturned = clock.now
        #expect(cancelStart.duration(to: cancelReturned) < .seconds(5))
        let stoppedAt = await StubURLProtocol.waitForStop(timeout: .seconds(5))
        #expect(stoppedAt != nil, "The cancelled load was never torn down")
        if let stoppedAt {
            print("cancel-to-stopLoading: \(cancelStart.duration(to: stoppedAt)), task result after \(cancelStart.duration(to: cancelReturned))")
        }
    }
}
