import Foundation
import Testing
@testable import HashFleetCore

final class MiningInsightsStubState: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)?
    private let lock = NSLock()
    private var storedHandler: Handler?
    private var paths: [String] = []

    func set(_ handler: Handler?) {
        lock.lock()
        defer { lock.unlock() }
        storedHandler = handler
        paths = []
    }

    func invoke(_ request: URLRequest) throws -> (URLResponse, Data)? {
        lock.lock()
        let handler = storedHandler
        paths.append(request.url?.path ?? "missing")
        lock.unlock()
        guard let handler else { throw URLError(.unsupportedURL) }
        return try handler(request)
    }

    var requestedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }
}

final class MiningInsightsStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = MiningInsightsStubState()
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let (response, data) = try Self.state.invoke(request) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class MiningInsightsFixture {
    let session: URLSession
    let client: MiningInsightsClient
    init(timeout: TimeInterval = 15, handler: @escaping MiningInsightsStubState.Handler) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MiningInsightsStubProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization": "Bearer private-header", "Cookie": "private-cookie"]
        configuration.urlCache = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
        session = URLSession(configuration: configuration)
        MiningInsightsStubProtocol.state.set(handler)
        client = MiningInsightsClient(session: session, timeout: timeout)
    }
    deinit {
        session.invalidateAndCancel()
        MiningInsightsStubProtocol.state.set(nil)
    }
}

let miningInsightsFixtures: [String: String] = [
    "/api/v1/fees/recommended": #"{"fastestFee":2,"halfHourFee":1.5,"hourFee":1,"economyFee":0.5,"minimumFee":0.1}"#,
    "/api/mempool": #"{"count":120,"vsize":123456,"total_fee":98765}"#,
    "/api/blocks/tip/height": "965849\n",
    "/api/v1/mining/hashrate/3d": #"{"currentHashrate":9e20,"currentDifficulty":127450789715843.1,"# +
        #""hashrates":[{"timestamp":1788652800,"avgHashrate":9e20}],"# +
        #""difficulty":[{"time":1788640367,"difficulty":127450789715843.1}]}"#,
    "/api/v1/prices": #"{"time":1788737703,"USD":80204}"#,
    "/pool/pool.status": """
        {"runtime":2558411,"lastupdate":1788737796,"Users":32197,"Workers":53293,"Idle":16746,"Disconnected":6377}
        {"hashrate1m":"196P","hashrate5m":"196P","hashrate1hr":"188P","hashrate1d":"410P","hashrate7d":"286P"}
        {"diff":140.72,"accepted":179287914322674,"rejected":90662342389159633,"bestshare":42158485242557}
        """
]

/// Test-only CoinGecko `/coins/markets` fixture rows, kept independent of any live response shape.
func coinGeckoMarketsFixtureRows() -> [[String: Any]] {
    [
        ["id": "bitcoin", "symbol": "btc", "name": "Bitcoin",
         "image": "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png?1696501400",
         "current_price": 80000, "market_cap_rank": 1],
        ["id": "bitcoin-cash", "symbol": "bch", "name": "Bitcoin Cash",
         "image": "https://coin-images.coingecko.com/coins/images/780/large/bitcoin-cash-circle.png" +
                  "?1696501932",
         "current_price": 260, "market_cap_rank": 30],
        ["id": "bitcoinii", "symbol": "bc2", "name": "Bitcoin II",
         "image": "https://coin-images.coingecko.com/coins/images/69865/large/200.png?1759876613",
         "current_price": 0.01, "market_cap_rank": NSNull()],
        ["id": "bitcoin-cash-ii", "symbol": "bch2", "name": "Bitcoin Cash II",
         "image": "https://coin-images.coingecko.com/coins/images/102172755/large/" +
                  "bch2_logo_%282%29.png?1775376231",
         "current_price": 0.02, "market_cap_rank": NSNull()],
        ["id": "ecash", "symbol": "xec", "name": "eCash",
         "image": "https://coin-images.coingecko.com/coins/images/16646/large/Logo_final-22.png" +
                  "?1696516207",
         "current_price": 0.00002, "market_cap_rank": 80],
        ["id": "digibyte", "symbol": "dgb", "name": "DigiByte",
         "image": "https://coin-images.coingecko.com/coins/images/63/large/digibyte.png?1696501454",
         "current_price": 0.003, "market_cap_rank": 311],
        ["id": "unrelated", "symbol": "nope", "name": "Ignored Coin",
         "image": "https://coin-images.coingecko.com/coins/images/999/large/nope.png",
         "current_price": 1, "market_cap_rank": 999]
    ]
}
