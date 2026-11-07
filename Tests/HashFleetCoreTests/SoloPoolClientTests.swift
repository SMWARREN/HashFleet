import Foundation
import Testing
@testable import HashFleetCore

// MARK: - Offline URLProtocol fixtures (SoloPool)

private enum SoloPoolStubAction {
    case response(URLResponse, Data)
    case redirect(HTTPURLResponse, URLRequest)
    case pending
}

private final class SoloPoolStubState: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> SoloPoolStubAction
    private let lock = NSLock()
    private var handler: Handler?
    private var requests: [URLRequest] = []
    func set(_ handler: Handler?) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        requests = []
    }
    func invoke(_ request: URLRequest) throws -> SoloPoolStubAction {
        lock.lock()
        requests.append(request)
        let handler = handler
        lock.unlock()
        guard let handler else { throw URLError(.unsupportedURL) }
        return try handler(request)
    }
    var captured: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

private final class SoloPoolStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = SoloPoolStubState()
    // Catch ALL requests so a bug cannot reach a miner, public wallet endpoint, or a second real host.
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            switch try Self.state.invoke(request) {
            case .response(let response, let data):
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            case .redirect(let response, let newRequest):
                client?.urlProtocol(self, wasRedirectedTo: newRequest, redirectResponse: response)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            case .pending: break
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private final class SoloPoolFixture {
    let session: URLSession
    let client: SoloPoolClient
    init(_ handler: @escaping SoloPoolStubState.Handler) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SoloPoolStubProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "Bearer private-token", "Cookie": "private-cookie=secret"]
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.urlCache = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
        if let cookie = HTTPCookie(properties: [
            .domain: "dgb-sha.solopool.org", .path: "/", .name: "stored-secret", .value: "private-value"
        ]) {
            config.httpCookieStorage?.setCookie(cookie)
        }
        session = URLSession(configuration: config)
        SoloPoolStubProtocol.state.set(handler)
        client = SoloPoolClient(session: session)
    }
    deinit {
        session.invalidateAndCancel()
        SoloPoolStubProtocol.state.set(nil)
    }
}

private func soloPoolResponse(
    _ request: URLRequest, status: Int = 200,
    text: String = #"{"hashrate":0}"#, headers: [String: String] = [:]
) throws -> SoloPoolStubAction {
    let (response, data) = try stubResponse(for: request, status: status, data: Data(text.utf8), headers: headers)
    return .response(response, data)
}

/// A valid DGB legacy P2PKH address, version byte 0x1e ("D" prefix), for offline fixtures.
/// This is a syntactically valid test vector, not a real funded wallet.
private let testDGBAddress = "DRGenRKV9FUg15qkXyLAgXL4aP93RHrdh9"

private func soloPoolTestPool(
    host: String = "us1.solopool.org",
    address: String? = testDGBAddress
) -> ConfiguredMiningPool {
    ConfiguredMiningPool(
        id: "slot-4",
        host: host,
        coin: .dgb,
        provider: .soloPool,
        role: "Primary",
        isActive: true,
        address: address,
        redactedAddress: nil
    )
}

@Suite("SoloPoolClient actual URLSession transport", .serialized, .timeLimit(.minutes(1)))
struct SoloPoolClientTransportTests {
    @Test func exactGETPathAndHostConstructionForTwoConfiguredHosts() async throws {
        for configuredHost in ["us1.solopool.org", "eu2.solopool.org"] {
            let fixture = SoloPoolFixture { request in
                #expect(request.httpMethod == "GET")
                #expect(request.url?.scheme == "https")
                // The actual request always targets the fixed, verified-working production API
                // host, never the caller-supplied stratum host (see SoloPoolClient's doc comment
                // on the host discrepancy). The stratum host is only an authorization check.
                #expect(request.url?.host == "dgb-sha.solopool.org")
                #expect(request.url?.path == "/api/miners/\(testDGBAddress)")
                #expect(request.url?.query == nil)
                return try soloPoolResponse(request, text: #"{"hashrate":42}"#)
            }
            let pool = soloPoolTestPool(host: configuredHost)
            let result = await fixture.client.account(pool: pool)
            #expect(result.error == nil)
            #expect(result.value?.hashRateHPS == 42)
            #expect(result.sourceURL.host == "dgb-sha.solopool.org")
            #expect(result.sourceURL.path == "/api/miners/\(testDGBAddress)")
        }
    }

    @Test func stripsInjectedSecretsCookiesAndCacheWithoutMutatingCaller() async throws {
        let fixture = SoloPoolFixture { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "dgb-sha.solopool.org")
            #expect(request.url?.query == nil)
            #expect(request.url?.user == nil)
            #expect(request.url?.password == nil)
            #expect(request.timeoutInterval == 15)
            #expect(request.httpShouldHandleCookies == false)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
            #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
            #expect(try requestBody(request).isEmpty)
            return try soloPoolResponse(request, headers: [
                "Cache-Control": "max-age=3600", "Set-Cookie": "replay=private-value; Path=/"
            ])
        }
        let result = await fixture.client.account(pool: soloPoolTestPool())
        #expect(result.error == nil)
        #expect(SoloPoolStubProtocol.state.captured.count == 1)
        // Injected fixtures deliberately carried secrets to prove the client's OWN request never
        // used them, while the caller's session configuration remains untouched.
        let callerHeaders = fixture.session.configuration.httpAdditionalHeaders
        #expect(callerHeaders?["Authorization"] as? String == "Bearer private-token")
        #expect(fixture.session.configuration.httpShouldSetCookies)
        #expect(fixture.session.configuration.urlCache != nil)
    }

    @Test(arguments: [301, 302, 307, 308])
    func actualRedirectCallbackNeverForwardsToSecondHost(status: Int) async throws {
        let fixture = SoloPoolFixture { request in
            guard request.url?.host == "dgb-sha.solopool.org" else {
                Issue.record("Unexpected second-host request")
                return try soloPoolResponse(request)
            }
            let response = try #require(HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Location": "https://unexpected.invalid/private-wallet"]))
            return .redirect(response, URLRequest(url: URL(string: "https://unexpected.invalid/private-wallet")!))
        }
        let result = await fixture.client.account(pool: soloPoolTestPool())
        #expect(result.error == .redirected)
        #expect(result.value == nil)
        #expect(SoloPoolStubProtocol.state.captured.map { $0.url?.host } == ["dgb-sha.solopool.org"])
        #expect(result.error?.localizedDescription.contains("private-wallet") == false)
    }

    @Test func mismatchedHostRejectedBeforeAnyRequest() async {
        let fixture = SoloPoolFixture { request in try soloPoolResponse(request) }
        let impostorHosts = [
            "evil.solopool.org", "us1.solopool.org.attacker.invalid",
            "solopool.org", "dgb-sha.solopool.org"
        ]
        for host in impostorHosts {
            let pool = soloPoolTestPool(host: host)
            let result = await fixture.client.account(pool: pool)
            #expect(result.error == .invalidData)
            #expect(result.value == nil)
        }
        #expect(SoloPoolStubProtocol.state.captured.isEmpty)
    }

    @Test func mismatchedCoinOrProviderRejectedBeforeAnyRequest() async {
        let fixture = SoloPoolFixture { request in try soloPoolResponse(request) }
        struct RejectionCase {
            let coin: MiningPoolCoin?
            let provider: MiningPoolProvider?
            let expected: MiningInsightsError
        }
        let inputs = [
            RejectionCase(coin: .btc, provider: .soloPool, expected: .invalidData),
            RejectionCase(coin: nil, provider: .soloPool, expected: .invalidData),
            RejectionCase(coin: .dgb, provider: .soloFury, expected: .invalidData),
            RejectionCase(coin: .dgb, provider: .ckpool, expected: .invalidData),
            RejectionCase(coin: .dgb, provider: nil, expected: .invalidData)
        ]
        for input in inputs {
            let pool = ConfiguredMiningPool(
                id: "slot-4", host: "us1.solopool.org", coin: input.coin, provider: input.provider,
                role: "Primary", isActive: true, address: testDGBAddress, redactedAddress: nil
            )
            let result = await fixture.client.account(pool: pool)
            #expect(result.error == input.expected)
            #expect(result.value == nil)
        }
        #expect(SoloPoolStubProtocol.state.captured.isEmpty)
    }

    @Test func pathTraversalAndNilAddressRejectedBeforeAnyRequest() async {
        let fixture = SoloPoolFixture { request in try soloPoolResponse(request) }
        // These are syntactically-plausible-looking strings crafted to test traversal/rejection
        // paths, not real addresses; DigiByteAddress.validated should reject most outright, and
        // any survivor must still fail the traversal-character check.
        let maliciousAddresses = [
            "../../../etc/passwd",
            "DRGenRKV9FUg15qkXyLAgXL4aP93RHrdh9/../secret",
            "DRGenRKV9FUg15qkXyLAgXL4aP93RHrdh9%2e%2e",
            "DRGenRKV9FUg15qkXyLAgXL4aP93RHrdh9?token=x",
            "DRGenRKV9FUg15qkXyLAgXL4aP93RHrdh9#fragment"
        ]
        for address in maliciousAddresses {
            let pool = soloPoolTestPool(address: address)
            let result = await fixture.client.account(pool: pool)
            #expect(result.error == .invalidBitcoinAddress)
            #expect(result.value == nil)
        }
        let nilPool = soloPoolTestPool(address: nil)
        let nilResult = await fixture.client.account(pool: nilPool)
        #expect(nilResult.error == .invalidBitcoinAddress)
        #expect(SoloPoolStubProtocol.state.captured.isEmpty)
    }

    @Test func malformedBodyIsRejected() async {
        let fixture = SoloPoolFixture { request in try soloPoolResponse(request, text: "not json at all") }
        let result = await fixture.client.account(pool: soloPoolTestPool())
        #expect(result.error == .invalidData)
        #expect(result.value == nil)
    }

    @Test func oversizedBodyIsRejected() async {
        let fixture = SoloPoolFixture { request in
            let hugeBody = "{\"hashrate\":0,\"pad\":\"" + String(repeating: "x", count: 1_048_577) + "\"}"
            return try soloPoolResponse(request, text: hugeBody)
        }
        let result = await fixture.client.account(pool: soloPoolTestPool())
        #expect(result.error == .invalidData)
        #expect(result.value == nil)
    }

    @Test func safe404NeverSpeciallyMappedUnlessBodyIsLiterallyEmptyOrError() async {
        // A 404 with a JSON body (even error-shaped) is treated as an ordinary typed HTTP error
        // here, matching SoloFuryClient's account() behavior: only the caller (ConnectedPoolsStore)
        // interprets .http(statusCode: 404) as "not found". This client itself never invents a
        // special not-found case from body content; it reports the exact HTTP status.
        let fixture = SoloPoolFixture { request in
            try soloPoolResponse(request, status: 404, text: #"{"error":"miner not found"}"#)
        }
        let result = await fixture.client.account(pool: soloPoolTestPool())
        #expect(result.error == .http(statusCode: 404))
        #expect(result.value == nil)

        let emptyFixture = SoloPoolFixture { request in try soloPoolResponse(request, status: 404, text: "") }
        let emptyResult = await emptyFixture.client.account(pool: soloPoolTestPool())
        #expect(emptyResult.error == .http(statusCode: 404))
        #expect(emptyResult.value == nil)
    }

    @Test(arguments: [401, 403, 429, 500, 502, 503])
    func serverFailuresAreTypedAndNeverExposeBodySecrets(status: Int) async {
        let fixture = SoloPoolFixture { request in
            try soloPoolResponse(request, status: status, text: "private-wallet private-key secret-token")
        }
        let result = await fixture.client.account(pool: soloPoolTestPool())
        #expect(result.error == .http(statusCode: status))
        #expect(result.value == nil)
        #expect(result.error?.localizedDescription.contains("private-wallet") == false)
        #expect(result.error?.localizedDescription.contains("secret-token") == false)
    }

    @Test(arguments: [URLError.Code.timedOut, .cancelled, .cannotFindHost, .notConnectedToInternet])
    func transportErrorsAreSanitized(code: URLError.Code) async {
        let fixture = SoloPoolFixture { _ in
            throw URLError(code, userInfo: [NSLocalizedDescriptionKey: "private-wallet secret-token"])
        }
        let result = await fixture.client.account(pool: soloPoolTestPool())
        let expected: MiningInsightsError = switch code {
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        default: .network(code: code.rawValue)
        }
        #expect(result.error == expected)
        #expect(result.value == nil)
        #expect(result.error?.localizedDescription.contains("private-wallet") == false)
        #expect(result.error?.localizedDescription.contains("secret-token") == false)
    }

    @Test func cancellationStopsAnInflightRequest() async {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let fixture = SoloPoolFixture { _ in
            continuation.yield(())
            return .pending
        }
        let client = fixture.client
        let pool = soloPoolTestPool()
        let task = Task { await client.account(pool: pool) }
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        let result = await task.value
        #expect(result.error == .cancelled)
        #expect(result.value == nil)
        continuation.finish()
    }

    @Test func preCancelledTaskNeverRequests() async {
        let fixture = SoloPoolFixture { request in try soloPoolResponse(request) }
        let client = fixture.client
        let pool = soloPoolTestPool()
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await client.account(pool: pool)
        }.value
        #expect(result.error == .cancelled)
        #expect(SoloPoolStubProtocol.state.captured.isEmpty)
    }

    @Test func nonHTTPResponseIsRejected() async {
        let fixture = SoloPoolFixture { request in
            .response(URLResponse(
                url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil
            ), Data())
        }
        let result = await fixture.client.account(pool: soloPoolTestPool())
        #expect(result.error == .invalidResponse)
        #expect(result.value == nil)
    }
}

// MARK: - Opt-in live smoke test

/// Never runs in ordinary tests. Fetches only the single wallet address confirmed present in
/// the live SoloPool DGB miners list as of 2026-09-10. Does not perform config resolution or
/// touch any user's real miner. Matches the `HASHFLEET_*_SMOKE` pattern used elsewhere
/// (e.g. `SoloFuryLiveTests`, `MiningInsightsLiveTests`).
@Suite(
    "SoloPool account live smoke",
    .enabled(if: ProcessInfo.processInfo.environment["HASHFLEET_SOLOPOOL_SMOKE"] == "1")
)
struct SoloPoolLiveTests {
    @Test func confirmedLiveDGBAddressDecodesThroughProductionTransport() async throws {
        // Confirmed present in the live SoloPool DGB miners list as of 2026-09-10. Do not use any
        // other wallet for this opt-in live test.
        let liveAddress = "DRGenRKV9FUg15qkXyLAgXL4aP93RHrdh9"
        let pool = ConfiguredMiningPool(
            id: "live-smoke",
            host: "us1.solopool.org",
            coin: .dgb,
            provider: .soloPool,
            role: "Live smoke",
            isActive: true,
            address: liveAddress,
            redactedAddress: nil
        )
        let result = await SoloPoolClient().account(pool: pool)
        #expect(result.error == nil)
        let value = try #require(result.value)
        #expect(result.sourceURL.absoluteString == "https://dgb-sha.solopool.org/api/miners/\(liveAddress)")
        #expect(value.hashRateHPS != nil || value.totalWorkers != nil)
        #expect(result.sourceTimestamp == nil)
        // Aggregate metadata only. Do not print worker identifiers, block hashes, or raw payloads.
        let summary = "fetchedAt=\(result.fetchedAt.ISO8601Format()), totalWorkers=\(value.totalWorkers ?? -1)"
        let blocksInfo = "totalBlocks=\(value.totalBlocks ?? -1), workersReported=\(value.workersReported)"
        print("SoloPool live GET success: \(summary), \(blocksInfo)")
    }
}
