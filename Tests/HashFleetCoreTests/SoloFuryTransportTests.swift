import Foundation
import Testing
@testable import HashFleetCore

private enum SoloFuryStubAction {
    case response(URLResponse, Data)
    case redirect(HTTPURLResponse, URLRequest)
    case pending
}

private final class SoloFuryStubState: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> SoloFuryStubAction
    private let lock = NSLock()
    private var handler: Handler?
    private var requests: [URLRequest] = []
    func set(_ handler: Handler?) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        requests = []
    }
    func invoke(_ request: URLRequest) throws -> SoloFuryStubAction {
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

private final class SoloFuryStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = SoloFuryStubState()
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

private final class SoloFuryFixture {
    let session: URLSession
    let client: SoloFuryClient
    init(_ handler: @escaping SoloFuryStubState.Handler) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SoloFuryStubProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "Bearer private-token", "Cookie": "private-cookie=secret"]
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.urlCache = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
        if let cookie = HTTPCookie(properties: [.domain: "solofury.com", .path: "/",
                                                .name: "stored-secret", .value: "private-value"]) {
            config.httpCookieStorage?.setCookie(cookie)
        }
        session = URLSession(configuration: config)
        SoloFuryStubProtocol.state.set(handler)
        client = SoloFuryClient(session: session)
    }
    deinit {
        session.invalidateAndCancel()
        SoloFuryStubProtocol.state.set(nil)
    }
}

private func soloFuryResponse(_ request: URLRequest, status: Int = 200, text: String = "{\"totalWorkers\":0}",
                              headers: [String: String] = [:]) throws -> SoloFuryStubAction {
    let (response, data) = try stubResponse(for: request, status: status, data: Data(text.utf8), headers: headers)
    return .response(response, data)
}

@Suite("SoloFury actual URLSession transport", .serialized, .timeLimit(.minutes(1)))
struct SoloFuryTransportTests {
    @Test func stripsInjectedSecretsCookiesAndCacheWithoutMutatingCaller() async throws {
        let fixture = SoloFuryFixture { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "solofury.com")
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
            return try soloFuryResponse(request, headers: ["Cache-Control": "max-age=3600",
                                                           "Set-Cookie": "replay=private-value; Path=/"])
        }
        let before = Date()
        for coin in MiningPoolCoin.soloFuryCoins {
            let result = await fixture.client.summary(coin: coin)
            #expect(result.value?.totalWorkers == 0)
            #expect(result.error == nil)
            #expect(result.sourceURL.path == coin.soloFuryPrefix.map { $0 + "/pool" })
            #expect(result.sourceTimestamp == nil)
            #expect(result.fetchedAt >= before && result.fetchedAt <= Date())
        }
        _ = await fixture.client.summary(coin: .bch)
        #expect(SoloFuryStubProtocol.state.captured.count == 6)
        let authHeader = fixture.session.configuration.httpAdditionalHeaders?["Authorization"] as? String
        #expect(authHeader == "Bearer private-token")
        #expect(fixture.session.configuration.httpShouldSetCookies)
        #expect(fixture.session.configuration.urlCache != nil)
    }

    @Test func fixedAccountPathsNormalizeOnlyTheCorrectChainOffline() async {
        let fixture = SoloFuryFixture { request in
            try soloFuryResponse(request, text: "{\"workers\":[]}")
        }
        let addresses: [(MiningPoolCoin, String)] = [
            (.btc, "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"),
            (.bc2, "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"),
            (.bch, cashAddrTestVector(prefix: "bitcoincash")),
            (.bch2, cashAddrTestVector(prefix: "bitcoincashii")),
            (.xec, cashAddrTestVector(prefix: "ecash"))
        ]
        for (coin, address) in addresses {
            let host = "JP-\(coin.rawValue.uppercased()).SOLOFURY.COM"
            let pool = ConfiguredMiningPool(id: "slot-7", host: host, coin: coin,
                provider: .soloFury, role: "Slot 7", isActive: nil, address: address, redactedAddress: nil)
            let result = await fixture.client.account(pool: pool)
            #expect(result.error == nil)
            #expect(result.value?.workersReported == true)
            #expect(result.sourceURL.path == coin.soloFuryPrefix.map { $0 + "/client/" + address })
            #expect(result.sourceURL.host == "solofury.com")
            #expect(result.sourceURL.query == nil)
        }
        #expect(SoloFuryStubProtocol.state.captured.count == 5)
    }

    @Test func digibyteNeverUsesASoloFuryEndpoint() async {
        let fixture = SoloFuryFixture { request in try soloFuryResponse(request) }
        let result = await fixture.client.summary(coin: .dgb)
        #expect(result.error == .invalidData)
        #expect(result.value == nil)
        #expect(SoloFuryStubProtocol.state.captured.isEmpty)
        #expect(MiningPoolCoin.dgb.soloFuryPrefix == nil)
    }

    @Test func publicAccountBoundaryRejectsMismatchedCoinAndHostBeforeAnyRequest() async {
        struct BoundaryCase {
            let host: String
            let coin: MiningPoolCoin?
            let provider: MiningPoolProvider?
            let address: String?
            let expected: MiningInsightsError
        }
        let fixture = SoloFuryFixture { request in try soloFuryResponse(request) }
        let inputs: [BoundaryCase] = [
            BoundaryCase(host: "bch.solofury.com", coin: .btc, provider: .soloFury,
                         address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", expected: .invalidData),
            BoundaryCase(host: "evil-btc.solofury.com", coin: .btc, provider: .soloFury,
                         address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", expected: .invalidData),
            BoundaryCase(host: "btc.solofury.com.attacker.invalid", coin: .btc, provider: .soloFury,
                         address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", expected: .invalidData),
            BoundaryCase(host: "btc.solofury.com", coin: .btc, provider: .ckpool,
                         address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", expected: .invalidData),
            BoundaryCase(host: "btc.solofury.com", coin: nil, provider: .soloFury,
                         address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", expected: .invalidData),
            BoundaryCase(host: "btc.solofury.com", coin: .btc, provider: .soloFury,
                         address: "../private-wallet?token=private", expected: .invalidBitcoinAddress),
            BoundaryCase(host: "btc.solofury.com", coin: .btc, provider: .soloFury,
                         address: nil, expected: .invalidBitcoinAddress),
            BoundaryCase(host: "bch2.solofury.com", coin: .bch2, provider: .soloFury,
                         address: cashAddrTestVector(prefix: "bitcoincash"), expected: .invalidBitcoinAddress)
        ]
        for testCase in inputs {
            let pool = ConfiguredMiningPool(id: "slot-0", host: testCase.host, coin: testCase.coin,
                provider: testCase.provider, role: "Primary", isActive: true, address: testCase.address,
                redactedAddress: nil)
            let result = await fixture.client.account(pool: pool)
            #expect(result.error == testCase.expected)
            #expect(result.value == nil)
            #expect(result.error?.localizedDescription.contains("private-wallet") == false)
            #expect(result.error?.localizedDescription.contains("secret-token") == false)
        }
        #expect(SoloFuryStubProtocol.state.captured.isEmpty)
    }

    @Test(arguments: [301, 302, 307, 308])
    func actualRedirectCallbackNeverForwardsToSecondHost(status: Int) async throws {
        let fixture = SoloFuryFixture { request in
            guard request.url?.host == "solofury.com" else {
                Issue.record("Unexpected second-host request")
                return try soloFuryResponse(request)
            }
            let response = try #require(HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Location": "https://unexpected.invalid/private-wallet"]))
            return .redirect(response, URLRequest(url: URL(string: "https://unexpected.invalid/private-wallet")!))
        }
        let result = await fixture.client.summary(coin: .bch)
        #expect(result.error == .redirected)
        #expect(result.value == nil)
        #expect(SoloFuryStubProtocol.state.captured.map { $0.url?.host } == ["solofury.com"])
        #expect(result.error?.localizedDescription.contains("private-wallet") == false)
            #expect(result.error?.localizedDescription.contains("secret-token") == false)
    }

    @Test(arguments: [401, 403, 404, 429, 500, 502, 503])
    func serverFailuresAreTypedAndNeverExposeBodySecrets(status: Int) async {
        let fixture = SoloFuryFixture { request in
            try soloFuryResponse(request, status: status, text: "private-wallet private-key secret-token")
        }
        let result = await fixture.client.summary(coin: .btc)
        #expect(result.error == .http(statusCode: status))
        #expect(result.value == nil)
        #expect(result.error?.localizedDescription.contains("private-wallet") == false)
            #expect(result.error?.localizedDescription.contains("secret-token") == false)
        #expect(result.error?.localizedDescription.contains("secret") == false)
    }

    @Test(arguments: [URLError.Code.timedOut, .cancelled, .cannotFindHost, .notConnectedToInternet])
    func transportErrorsAreSanitized(code: URLError.Code) async {
        let fixture = SoloFuryFixture { _ in
            throw URLError(code, userInfo: [NSLocalizedDescriptionKey: "private-wallet secret-token"])
        }
        let result = await fixture.client.summary(coin: .bch)
        let expected: MiningInsightsError = code == .timedOut ? .timedOut :
            (code == .cancelled ? .cancelled : .network(code: code.rawValue))
        #expect(result.error == expected)
        #expect(result.value == nil)
        #expect(result.error?.localizedDescription.contains("private-wallet") == false)
            #expect(result.error?.localizedDescription.contains("secret-token") == false)
    }

    @Test func cancellationStopsAnInflightRequest() async {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let fixture = SoloFuryFixture { _ in
            continuation.yield(())
            return .pending
        }
        let client = fixture.client
        let task = Task { await client.summary(coin: .bch) }
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        let result = await task.value
        #expect(result.error == .cancelled)
        #expect(result.value == nil)
        continuation.finish()
    }

    @Test func preCancelledTaskNeverRequests() async {
        let fixture = SoloFuryFixture { request in try soloFuryResponse(request) }
        let client = fixture.client
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await client.summary(coin: .bch)
        }.value
        #expect(result.error == .cancelled)
        #expect(SoloFuryStubProtocol.state.captured.isEmpty)
    }

    @Test func invalidResponsesAndOverLimitBodiesAreRejected() async throws {
        do {
            let fixture = SoloFuryFixture { request in
                let response = URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0,
                                           textEncodingName: nil)
                return .response(response, Data())
            }
            #expect(await fixture.client.summary(coin: .bch).error == .invalidResponse)
        }
        do {
            let fixture = SoloFuryFixture { _ in
                let url = URL(string: "https://unexpected.invalid/")!
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return .response(response, Data("{\"totalWorkers\":0}".utf8))
            }
            #expect(await fixture.client.summary(coin: .bch).error == .redirected)
        }
        do {
            let fixture = SoloFuryFixture { request in
                try soloFuryResponse(request, text: String(repeating: "x", count: 1_048_577))
            }
            #expect(await fixture.client.summary(coin: .bch).error == .invalidData)
        }
        do {
            let fixture = SoloFuryFixture { request in try soloFuryResponse(request, text: "{\"totalWorkers\":null}") }
            #expect(await fixture.client.summary(coin: .bch).error == .invalidData)
        }
    }
}
