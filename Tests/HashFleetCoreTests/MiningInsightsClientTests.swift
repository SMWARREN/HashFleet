import Foundation
import Testing
@testable import HashFleetCore

@Suite(.serialized, .timeLimit(.minutes(1)))
struct MiningInsightsClientTests {
    @Test func aggregateRefreshUsesOnlyExpectedGETsAndKeepsIndependentSourceTimes() async throws {
        let fixture = MiningInsightsFixture { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.scheme == "https")
            #expect(["mempool.space", "raw.stats.ckpool.org"].contains(request.url?.host ?? ""))
            #expect(request.url?.query == nil)
            #expect(request.url?.user == nil)
            #expect(request.timeoutInterval == 15)
            #expect(request.httpShouldHandleCookies == false)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
            #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
            #expect(try requestBody(request).isEmpty)
            let text = try #require(miningInsightsFixtures[request.url?.path ?? ""])
            return try stubResponse(for: request, data: Data(text.utf8),
                                    headers: ["Cache-Control": "max-age=3600", "Set-Cookie": "private-cookie=secret"])
        }
        let before = Date()
        let snapshot = await fixture.client.bitcoinNetwork()
        let pool = await fixture.client.ckPoolSummary()
        #expect(snapshot.fees.value?.halfHourFee == 1.5)
        #expect(snapshot.backlog.value?.transactionCount == 120)
        #expect(snapshot.backlog.value?.totalFeeSatoshis == 98765)
        #expect(snapshot.tipHeight.value == 965849)
        #expect(snapshot.mining.value?.hashrateHPS == 9e20)
        #expect(snapshot.mining.value?.difficulty == 127450789715843.1)
        #expect(snapshot.mining.value?.hashrateSampleAt == Date(timeIntervalSince1970: 1788652800))
        #expect(snapshot.mining.value?.difficultyChangedAt == Date(timeIntervalSince1970: 1788640367))
        #expect(snapshot.mining.sourceTimestamp == nil)
        #expect(snapshot.fees.sourceTimestamp == nil)
        #expect(snapshot.price.sourceTimestamp == Date(timeIntervalSince1970: 1788737703))
        #expect(snapshot.price.value?.usd == 80204)
        #expect(snapshot.fetchedAt >= before && snapshot.fetchedAt <= Date())
        #expect(snapshot.isCancelled == false)
        #expect(pool.value?.hashrate1MinuteHPS == 196e15)
        #expect(pool.value?.users == 32197)
        #expect(pool.value?.bestShare == 42158485242557)
        #expect(pool.sourceTimestamp == Date(timeIntervalSince1970: 1788737796))
        #expect(Set(MiningInsightsStubProtocol.state.requestedPaths) == Set(miningInsightsFixtures.keys))
        // A cacheable response must not prevent the next explicit refresh reaching the transport.
        _ = await fixture.client.bitcoinNetwork()
        #expect(MiningInsightsStubProtocol.state.requestedPaths.count == 11)
    }

    @Test func partialFailuresNeverDiscardOtherEndpointsOrInventMissingZeros() async {
        let fixture = MiningInsightsFixture { request in
            switch request.url?.path {
            case "/api/v1/fees/recommended":
                return try stubResponse(for: request, status: 429, data: Data("private-body".utf8))
            case "/api/mempool":
                return try stubResponse(for: request, data: Data(#"{"count":0,"vsize":null}"#.utf8))
            case "/api/v1/prices":
                return try stubResponse(for: request, data: Data(#"{"USD":-1}"#.utf8))
            default:
                let fallback = miningInsightsFixtures[request.url?.path ?? ""] ?? "{}"
                return try stubResponse(for: request, data: Data(fallback.utf8))
            }
        }
        let snapshot = await fixture.client.bitcoinNetwork()
        #expect(snapshot.fees.error == .http(statusCode: 429))
        #expect(snapshot.fees.value == nil)
        #expect(snapshot.backlog.value?.transactionCount == 0)
        #expect(snapshot.backlog.value?.virtualSizeBytes == nil)
        #expect(snapshot.tipHeight.value == 965849)
        #expect(snapshot.mining.value?.difficulty != nil)
        #expect(snapshot.price.error == .invalidData)
    }

    @Test(arguments: [301, 302, 307, 308, 401, 403, 404, 429, 500, 502, 503])
    func HTTPFailuresAreTypedAndNeverExposeResponseSecrets(status: Int) async {
        let fixture = MiningInsightsFixture { request in
            try stubResponse(for: request, status: status, data: Data("private-body bitcoin-address private-key".utf8),
                             headers: ["Location": "https://unexpected.invalid/private-key"])
        }
        let result = await fixture.client.ckPoolSummary()
        #expect(result.value == nil)
        #expect(result.error == ((300...399).contains(status) ? .redirected : .http(statusCode: status)))
        #expect(result.error?.localizedDescription.contains("private") == false)
        #expect(result.error?.localizedDescription.contains("unexpected.invalid") == false)
        #expect(MiningInsightsStubProtocol.state.requestedPaths == ["/pool/pool.status"])
    }

    @Test(arguments: [URLError.Code.timedOut, .cancelled, .notConnectedToInternet, .cannotFindHost])
    func transportFailureTextIsSanitized(code: URLError.Code) async {
        let fixture = MiningInsightsFixture { _ in
            throw URLError(code, userInfo: [NSLocalizedDescriptionKey: "private-key wallet-address",
                                             NSURLErrorFailingURLStringErrorKey: "https://private.invalid"])
        }
        let result = await fixture.client.ckPoolSummary()
        let expected: MiningInsightsError = code == .timedOut ? .timedOut :
            (code == .cancelled ? .cancelled : .network(code: code.rawValue))
        #expect(result.error == expected)
        #expect(result.error?.localizedDescription.contains("private") == false)
        #expect(result.value == nil)
    }

    @Test func cancellationStopsAnInFlightRequestAndNeverReturnsSuccess() async {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let fixture = MiningInsightsFixture { _ in
            continuation.yield(())
            return nil
        }
        let client = fixture.client
        let task = Task { await client.ckPoolSummary() }
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        let result = await task.value
        #expect(result.error == .cancelled)
        #expect(result.value == nil)
        continuation.finish()
    }

    @Test func cancelledNetworkTaskHasExplicitCancelledSnapshot() async {
        let fixture = MiningInsightsFixture { request in try stubResponse(for: request, data: Data("{}".utf8)) }
        let client = fixture.client
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await client.bitcoinNetwork()
        }
        let result = await task.value
        #expect(result.isCancelled)
        #expect(result.fees.error == .cancelled)
        #expect(result.backlog.error == .cancelled)
        #expect(result.tipHeight.error == .cancelled)
        #expect(result.mining.error == .cancelled)
        #expect(result.price.error == .cancelled)
        #expect(MiningInsightsStubProtocol.state.requestedPaths.isEmpty)
    }

    @Test func nonHTTPAndUnexpectedFinalURLAreRejected() async throws {
        do {
            let fixture = MiningInsightsFixture { request in
                let url = try #require(request.url)
                let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0,
                                           textEncodingName: nil)
                return (response, Data())
            }
            #expect(await fixture.client.ckPoolSummary().error == .invalidResponse)
        }
        do {
            let fixture = MiningInsightsFixture { _ in
                let url = URL(string: "https://unexpected.invalid/pool")!
                let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                             headerFields: nil))
                return (response, Data(#"{"Users":1}"#.utf8))
            }
            #expect(await fixture.client.ckPoolSummary().error == .redirected)
        }
    }

    @Test(arguments: ["", "{}", "[]", "null", "<html>private-key</html>", "{\"Users\":-1}", "oversized-body"])
    func malformedAndOversizedSuccessfulBodiesAreErrors(body: String) async {
        let payload = body == "oversized-body" ? String(repeating: "x", count: 1_048_577) : body
        let fixture = MiningInsightsFixture { try stubResponse(for: $0, data: Data(payload.utf8)) }
        #expect(await fixture.client.ckPoolSummary().error == .invalidData)
    }

}
