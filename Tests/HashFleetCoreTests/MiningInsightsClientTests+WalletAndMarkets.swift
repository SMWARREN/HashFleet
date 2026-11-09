import Foundation
import Testing
@testable import HashFleetCore

extension MiningInsightsClientTests {
    @Test func deliberateWalletLookupHasSafePathAndNoAutomaticWorkerExtraction() async {
        // Public genesis address is an OFFLINE test vector. URLProtocol prevents any external request.
        let address = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
        let fixture = MiningInsightsFixture { request in
            #expect(request.url?.absoluteString == "https://raw.stats.ckpool.org/users/\(address)")
            #expect(request.httpMethod == "GET")
            let json = #"{"workers":2,"hashrate1m":"1.2T","hashrate1hr":"999G","shares":42,"# +
                       #""bestshare":125.5,"bestever":999,"lastshare":1788737700,"# +
                       #""worker":[{"workername":"not-retained"}]}"#
            return try stubResponse(for: request, data: Data(json.utf8))
        }
        let result = await fixture.client.ckPoolUser(address: address)
        guard case .found(let result) = result else { Issue.record("Expected typed user statistics"); return }
        #expect(result.value?.workers == 2)
        #expect(result.value?.hashrate1MinuteHPS == 1.2e12)
        #expect(result.value?.hashrate1HourHPS == 999e9)
        #expect(result.value?.shares == 42)
        #expect(result.value?.lastShareAt == Date(timeIntervalSince1970: 1788737700))
        #expect(result.sourceTimestamp == nil)
        #expect(result.value?.hashrate7DaysHPS == nil)
        #expect(String(describing: result.value).contains("not-retained") == false)
    }

    @Test(arguments: [404, 401, 429, 503, 200])
    func walletNotFoundIsDistinctFromErrors(status: Int) async {
        let fixture = MiningInsightsFixture { try stubResponse(for: $0, status: status, data: Data("{}".utf8)) }
        let result = await fixture.client.ckPoolUser(address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa")
        if status == 404 {
            guard case .notFound = result else { Issue.record("Expected explicit notFound"); return }
        } else {
            #expect(result == .failed(status == 200 ? .invalidData : .http(statusCode: status)))
        }
    }

    @Test(arguments: ["", "../pool/pool.status", "https://unexpected.invalid",
                      "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker",
                      "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa?secret=x",
                      "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb"])
    func invalidWalletNeverContactsAnyHost(address: String) async {
        let fixture = MiningInsightsFixture { _ in
            Issue.record("Invalid wallet performed a request")
            throw URLError(.unsupportedURL)
        }
        #expect(await fixture.client.ckPoolUser(address: address) == .failed(.invalidBitcoinAddress))
        #expect(MiningInsightsStubProtocol.state.requestedPaths.isEmpty)
    }

    @Test(arguments: ["http://mempool.space/api/mempool", "https://mempool.space:443/api/mempool",
                      "https://user:secret@mempool.space/api/mempool",
                      "https://mempool.space/api/mempool?x=1", "https://mempool.space/api/mempool#x",
                      "https://mempool.space/anything", "https://mempool.space.unexpected.invalid/api/mempool"])
    func allowlistCannotBeBypassed(url: String) {
        #expect(throws: MiningInsightsError.self) {
            try MiningInsightsClient().request(for: .backlog, url: URL(string: url))
        }
    }

    @Test func redirectAndCacheDelegatesAlwaysDenyForwardingAndStorage() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = MiningInsightsEndpoint.ckPoolSummary.url
        let response = try #require(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil))
        let task = session.dataTask(with: url) // Never resumed.
        let delegate = MiningInsightsRequestGuard()
        for destination in ["https://unexpected.invalid", url.absoluteString, "http://raw.stats.ckpool.org/pool/pool.status"] {
            let allowed: Bool = await withCheckedContinuation { continuation in
                delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                    newRequest: URLRequest(url: URL(string: destination)!)) {
                    continuation.resume(returning: $0 != nil)
                }
            }
            #expect(!allowed)
        }
        let cached: Bool = await withCheckedContinuation { continuation in
            let cachedResponse = CachedURLResponse(response: response, data: Data())
            delegate.urlSession(session, dataTask: task, willCacheResponse: cachedResponse) {
                continuation.resume(returning: $0 != nil)
            }
        }
        #expect(!cached)
    }

    @Test func timeoutIsFiniteAndBounded() {
        for value in [Double.nan, .infinity, -.infinity, -1, 0] {
            #expect(MiningInsightsClient(timeout: value).timeout == 15)
        }
        #expect(MiningInsightsClient(timeout: 120).timeout == 60)
        #expect(MiningInsightsClient(timeout: 0.25).timeout == 0.25)
    }

    @Test func bitcoinCashUsesSeparateReadOnlySourceAndPreservesProviderCacheAge() async {
        let fixture = MiningInsightsFixture { request in
            #expect(request.url?.absoluteString == "https://api.blockchair.com/bitcoin-cash/stats")
            #expect(request.httpMethod == "GET")
            #expect(request.httpShouldHandleCookies == false)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(try requestBody(request).isEmpty)
            let json = #"{"data":{"difficulty":428672956037.77,"best_block_height":967397,"# +
                       #""blocks":967399,"market_price_usd":260.96,"# +
                       #""hashrate_24h":"2899427286391434277","mempool_transactions":4},"# +
                       #""context":{"code":200,"cache":{"since":"2026-09-06 23:57:26"}}}"#
            return try stubResponse(for: request, data: Data(json.utf8))
        }
        let result = await fixture.client.bitcoinCash()
        #expect(result.error == nil)
        #expect(result.value?.difficulty == 428672956037.77)
        #expect(result.value?.tipHeight == 967397)
        #expect(result.value?.usd == 260.96)
        #expect(result.value?.hashrate24HoursHPS == 2_899_427_286_391_434_277)
        #expect(result.value?.mempoolTransactions == 4)
        #expect(result.sourceTimestamp?.ISO8601Format() == "2026-09-06T23:57:26Z")
        #expect(result.value?.sourceTimestamp == result.sourceTimestamp)
        #expect(result.sourceURL == MiningInsightsEndpoint.cashStats.url)
    }

    @Test func coinMarketsUseCoinGeckoAndMapSupportedTickersAndIcons() async throws {
        let fixture = MiningInsightsFixture { request in
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "api.coingecko.com")
            #expect(request.url?.path == "/api/v3/coins/markets")
            let url = try #require(request.url)
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(queryItems.first(where: { $0.name == "vs_currency" })?.value == "usd")
            #expect(queryItems.first(where: { $0.name == "order" })?.value == "market_cap_desc")
            #expect(queryItems.first(where: { $0.name == "sparkline" })?.value == "false")
            #expect(queryItems.first(where: { $0.name == "ids" })?.value?.contains("bitcoin-cash-ii") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            let body = try JSONSerialization.data(withJSONObject: coinGeckoMarketsFixtureRows())
            return try stubResponse(for: request, data: body)
        }

        let result = await fixture.client.coinMarkets()
        #expect(result.error == nil)
        #expect(result.sourceURL == MiningInsightsEndpoint.coinMarkets.url)
        #expect(result.value?.count == MiningPoolCoin.allCases.count)
        #expect(result.value?[.btc]?.ticker == "BTC")
        #expect(result.value?[.bch]?.name == "Bitcoin Cash")
        #expect(result.value?[.bc2]?.ticker == "BC2")
        #expect(result.value?[.bch2]?.imageURL?.host == "coin-images.coingecko.com")
        #expect(result.value?[.xec]?.currentPriceUSD == 0.00002)
        #expect(result.value?[.dgb]?.ticker == "DGB")
        #expect(MiningInsightsStubProtocol.state.requestedPaths == ["/api/v3/coins/markets"])
    }

    @Test(arguments: [401, 429, 503])
    func bitcoinCashFailuresDoNotBecomeBitcoinValues(status: Int) async {
        let fixture = MiningInsightsFixture {
            try stubResponse(for: $0, status: status, data: Data("private-body".utf8))
        }
        let result = await fixture.client.bitcoinCash()
        #expect(result.value == nil)
        #expect(result.error == .http(statusCode: status))
        #expect(result.error?.localizedDescription.contains("private-body") == false)
    }
}
