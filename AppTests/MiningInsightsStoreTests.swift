import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized) @MainActor
struct MiningInsightsStoreTests {
    @Test func externalOptOutClearsEveryCoinIncludingDGBAndXEC() async {
        let store = makeStore()
        store.setDemo(true)
        await store.refresh()
        #expect(store.xec?.value != nil && store.dgb?.value != nil)
        store.clearPublicData()
        #expect(store.network == nil && store.pool == nil && store.cash == nil)
        #expect(store.xec == nil && store.dgb == nil && store.poolNetworks.isEmpty)
        #expect(store.coinMarkets.isEmpty && store.coinMarketsResult == nil)
    }

    private func makeStore(cooldown: TimeInterval = 0) -> MiningInsightsStore {
        InsightsStoreProtocol.state.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InsightsStoreProtocol.self]
        return MiningInsightsStore(session: URLSession(configuration: config), cooldown: cooldown)
    }

    @Test func openingAndDemoDoNotContactExternalServices() async {
        let store = makeStore()
        #expect(store.network == nil && store.pool == nil)
        #expect(InsightsStoreProtocol.state.requests.isEmpty)
        store.setDemo(true)
        await store.refresh()
        await store.lookup(address: "1BoatSLRHtKNngkdXEeobR76b53LETtpyT")
        #expect(store.network?.fees.value?.fastestFee == 4)
        #expect(store.pool?.value?.workers == 4500)
        #expect(store.userLookup == nil)
        #expect(InsightsStoreProtocol.state.requests.isEmpty)
        store.setDemo(false)
        #expect(store.network == nil && store.pool == nil)
    }

    @Test func explicitPublicRefreshPreservesPartialFailuresAndSendsNoIdentity() async {
        let store = makeStore()
        InsightsStoreProtocol.state.failPrices = true
        await store.refresh()
        #expect(store.network?.fees.value?.fastestFee == 4)
        #expect(store.network?.price.value == nil)
        #expect(store.network?.price.error == .http(statusCode: 503))
        #expect(store.pool?.value?.workers == 7)
        #expect(store.poolNetworks.count == 5)
        #expect(store.poolNetworks[.bc2]?.value?.networkDifficulty == 123456)
        #expect(store.cash?.value?.difficulty == 430e9)
        #expect(store.dgb?.value?.difficulty == 679406602)
        #expect(ChainObservation.isFresh(store.dgb, now: Date()))
        #expect(!store.isLoading)
        let requests = InsightsStoreProtocol.state.requests
        #expect(requests.count == 15)
        #expect(
            requests.allSatisfy { request in
                request.httpMethod == "GET" && request.httpBody == nil && request.url?.scheme == "https"
                    && ["mempool.space", "raw.stats.ckpool.org", "api.blockchair.com", "api.coingecko.com", "solofury.com", "dgb-sha.solopool.org"].contains(
                        request.url?.host ?? ""
                    ) && request.value(forHTTPHeaderField: "Authorization") == nil
                    && request.value(forHTTPHeaderField: "Cookie") == nil
                    && !(request.url?.path.contains("/users/") ?? true)
            }
        )
        InsightsStoreProtocol.state.failPrices = false
        await store.refresh()
        #expect(store.network?.price.value?.usd == 80000)
        #expect(store.network?.price.error == nil)
    }

    @Test func refreshCooldownPreventsHammeringPublicServices() async {
        let store = makeStore(cooldown: 60)
        await store.refresh()
        await store.refresh()
        #expect(InsightsStoreProtocol.state.requests.count == 15)
        #expect(store.refreshAvailableAt > Date())
    }

    @Test func identicalPublicPayloadsDoNotReplacePublishedResults() async throws {
        let store = makeStore()
        await store.refresh()
        let firstNetworkFetch = try #require(store.network?.fetchedAt)
        let firstPoolFetch = try #require(store.pool?.fetchedAt)
        let firstPoolNetworkFetch = try #require(store.poolNetworks[.bc2]?.fetchedAt)
        let firstMarketFetch = try #require(store.coinMarketsResult?.fetchedAt)
        let initialRequestCount = InsightsStoreProtocol.state.requests.count

        await store.refresh(force: true)

        #expect(InsightsStoreProtocol.state.requests.count == initialRequestCount + 15)
        #expect(store.network?.fetchedAt == firstNetworkFetch)
        #expect(store.pool?.fetchedAt == firstPoolFetch)
        #expect(store.poolNetworks[.bc2]?.fetchedAt == firstPoolNetworkFetch)
        #expect(store.coinMarketsResult?.fetchedAt == firstMarketFetch)
        #expect(store.network?.price.value?.usd == 80000)
        #expect(store.coinMarkets.count == 5)
    }

    @Test func explicitLookupDoesNotRefreshNetworkOrPersistAnAddress() async {
        let store = makeStore()
        await store.lookup(address: "1BoatSLRHtKNngkdXEeobR76b53LETtpyT")
        #expect(store.network == nil && store.pool == nil)
        let requests = InsightsStoreProtocol.state.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url?.path == "/users/1BoatSLRHtKNngkdXEeobR76b53LETtpyT")
        if case .found(let result) = store.userLookup {
            #expect(result.value?.workers == 2)
            #expect(result.value?.hashrate1HourHPS == 2e12)
        } else {
            Issue.record("Expected fixture pool-account statistics")
        }
        store.clearLookup()
        #expect(store.userLookup == nil)
        await store.lookup(address: "http://private.test/secret")
        #expect(InsightsStoreProtocol.state.requests.count == 1)
        if case .failed(.invalidBitcoinAddress) = store.userLookup {
        } else {
            Issue.record("Invalid input must fail locally")
        }
    }

    @Test func cancellationAndDemoTransitionRejectLatePublicResults() async throws {
        let store = makeStore()
        InsightsStoreProtocol.state.hold = true
        let work = Task { await store.refresh() }
        for _ in 0..<100 {
            if !InsightsStoreProtocol.state.requests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!InsightsStoreProtocol.state.requests.isEmpty)
        store.setDemo(true)
        await work.value
        #expect(!store.isLoading && store.network == nil && store.pool == nil)
        InsightsStoreProtocol.state.hold = false
        await store.refresh()
        #expect(store.network?.fees.value?.fastestFee == 4)
        #expect(InsightsStoreProtocol.state.requests.count <= 15)
    }

    @Test func forcedRefreshBypassesCooldownAndMarketTTL() async {
        let store = makeStore(cooldown: 60)
        await store.refresh()
        let initialCount = InsightsStoreProtocol.state.requests.count
        #expect(initialCount == 15)
        #expect(store.coinMarkets.count == 5)
        #expect(store.refreshAvailableAt > Date())

        // An unforced refresh while under cooldown does nothing
        await store.refresh()
        #expect(InsightsStoreProtocol.state.requests.count == initialCount)

        // A forced refresh immediately re-fetches all endpoints including coin markets
        await store.refresh(force: true)
        #expect(InsightsStoreProtocol.state.requests.count == initialCount + 15)
        #expect(store.coinMarkets.count == 5)
        #expect(store.network?.price.value?.usd == 80000)
    }

    @Test func forcedRefreshPreservesPartialFailuresAndAccurateTimestamps() async {
        let store = makeStore()
        await store.refresh()
        #expect(store.network?.price.value?.usd == 80000)
        #expect(store.network?.price.error == nil)

        // Force refresh during provider outage marks the failed source failed without stale success
        InsightsStoreProtocol.state.failPrices = true
        await store.refresh(force: true)
        #expect(store.network?.price.value == nil)
        #expect(store.network?.price.error == .http(statusCode: 503))
        #expect(store.cash?.value?.difficulty == 430e9)
        #expect(store.dgb?.value?.difficulty == 679406602)
        #expect(ChainObservation.isFresh(store.dgb, now: Date()))
        #expect(store.coinMarkets.count == 5)
    }

    @Test func forcedRefreshCancelsInFlightRefreshAndCoinMarkets() async throws {
        let store = makeStore()
        InsightsStoreProtocol.state.hold = true
        let backgroundTask = Task { await store.refresh() }
        for _ in 0..<100 {
            if !InsightsStoreProtocol.state.requests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!InsightsStoreProtocol.state.requests.isEmpty)
        #expect(store.isLoading)

        InsightsStoreProtocol.state.hold = false
        // Forced refresh should supersede in-flight refresh including coinMarketsTask without deadlock
        await store.refresh(force: true)
        await backgroundTask.value
        #expect(!store.isLoading)
        #expect(store.network?.fees.value?.fastestFee == 4)
    }
}

private final class InsightsStoreFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var journal: [URLRequest] = []
    private var failing = false
    private var holding = false
    var requests: [URLRequest] { lock.withLock { journal } }
    var failPrices: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }
    var hold: Bool {
        get { lock.withLock { holding } }
        set { lock.withLock { holding = newValue } }
    }
    func reset() {
        lock.withLock {
            journal = []; failing = false; holding = false
        }
    }
    func record(_ request: URLRequest) { lock.withLock { journal.append(request) } }
}

private class InsightsStoreProtocol: URLProtocol, @unchecked Sendable {
    static let state = InsightsStoreFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.record(request)
        if Self.state.hold { return }
        let path = request.url!.path
        let body: String
        var status = 200
        switch path {
        case "/api/pool", "/api-btc/pool", "/api-bc2/pool", "/api-bch2/pool", "/api-xec/pool":
            body = #"{"networkDifficulty":123456,"blockHeight":59000,"totalHashRate1hr":1000000000000,"totalMiners":10,"totalWorkers":20}"#
        case "/api/v1/fees/recommended": body = #"{"fastestFee":4,"halfHourFee":3,"hourFee":2}"#
        case "/api/mempool": body = #"{"count":100,"vsize":10000,"total_fee":40000}"#
        case "/api/blocks/tip/height": body = "960000"
        case "/api/v1/mining/hashrate/3d": body = #"{"currentHashrate":1e21,"currentDifficulty":140e12}"#
        case "/bitcoin-cash/stats":
            body =
                #"{"data":{"difficulty":430000000000,"best_block_height":967000,"market_price_usd":260},"# +
                #""context":{"code":200}}"#
        case "/ecash/stats":
            body =
                #"{"data":{"difficulty":220000000,"best_block_height":880000,"market_price_usd":0.00002},"# +
                #""context":{"code":200}}"#
        case "/api/stats":
            body = "{\"node\":{\"difficulty\":679406602,\"height\":24199283,\"hashrate\":36076348829567530,\"lastUpdate\":\(Date().timeIntervalSince1970)}}"
        case "/api/v1/prices":
            status = Self.state.failPrices ? 503 : 200
            body = status == 200 ? #"{"USD":80000}"# : #"{"error":"DO_NOT_DISPLAY_RESPONSE_SECRET"}"#
        case "/pool/pool.status": body = "{\"Users\":5,\"Workers\":7}\n{\"hashrate1hr\":\"12P\"}\n{\"bestshare\":100}"
        case "/api/v3/coins/markets":
            // Keep every URL on a single line: a literal newline inside a JSON string is invalid.
            body = #"""
                [
                {"id":"bitcoin","symbol":"btc","name":"Bitcoin","image":"https://example.test/btc.png","current_price":80000,"market_cap_rank":1},
                {"id":"bitcoin-cash","symbol":"bch","name":"Bitcoin Cash","image":"https://example.test/bch.png","current_price":260,"market_cap_rank":30},
                {"id":"bitcoinii","symbol":"bc2","name":"Bitcoin II","image":"https://example.test/bc2.png","current_price":0.01,"market_cap_rank":null},
                {"id":"bitcoin-cash-ii","symbol":"bch2","name":"Bitcoin Cash II","image":"https://example.test/bch2.png","current_price":0.02,"market_cap_rank":null},
                {"id":"ecash","symbol":"xec","name":"eCash","image":"https://example.test/xec.png","current_price":0.00002,"market_cap_rank":80}
                ]
                """#
        default: body = #"{"workers":2,"hashrate1hr":"2T","shares":40}"#
        }
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
