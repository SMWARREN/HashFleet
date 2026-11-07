import Foundation

/// Explicit, one-shot public-data requests. No polling, retries, discovery, or miner configuration access.
public struct MiningInsightsClient: Sendable {
    private let transport: MiningInsightsTransport
    public let timeout: TimeInterval

    /// Copies an injected session's configuration (including URLProtocol fixtures), then strips cookies,
    /// caches, credential storage, and additional headers. The caller's session is never mutated.
    public init(session: URLSession? = nil, timeout: TimeInterval = 15) {
        let boundedTimeout = timeout.isFinite && timeout > 0 ? min(timeout, 60) : 15
        self.timeout = boundedTimeout
        let configuration = session?.configuration ?? .ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = boundedTimeout
        configuration.timeoutIntervalForResource = boundedTimeout
        configuration.waitsForConnectivity = false
        self.transport = MiningInsightsTransport(configuration: configuration)
    }

    /// Five independent requests. Endpoint failures do not discard successful siblings.
    /// Cancellation is represented by typed .cancelled failures and NetworkSnapshot.isCancelled.
    public func bitcoinNetwork() async -> NetworkSnapshot {
        async let fees = fetch(.fees, parse: MiningInsightsParser.fees)
        async let backlog = fetch(.backlog, parse: MiningInsightsParser.backlog)
        async let height = fetch(.tipHeight, parse: MiningInsightsParser.height)
        async let mining = fetch(.mining, parse: MiningInsightsParser.mining)
        async let price = fetch(.price, parse: MiningInsightsParser.price)
        let results = await (fees, backlog, height, mining, price)
        if Task.isCancelled {
            return NetworkSnapshot(
                fetchedAt: Date(),
                fees: cancelled(.fees),
                backlog: cancelled(.backlog),
                tipHeight: cancelled(.tipHeight),
                mining: cancelled(.mining),
                price: cancelled(.price)
            )
        }
        return NetworkSnapshot(
            fetchedAt: Date(),
            fees: results.0,
            backlog: results.1,
            tipHeight: results.2,
            mining: results.3,
            price: results.4
        )
    }

    public func ckPoolSummary() async -> MiningDataResult<CKPoolSummary> {
        await fetch(.ckPoolSummary, parse: MiningInsightsParser.pool)
    }

    /// Independent BCH assumptions. Bitcoin's snapshot is never relabeled as another chain.
    public func bitcoinCash() async -> MiningDataResult<BitcoinCashStatistics> {
        await fetch(.cashStats, parse: MiningInsightsBitcoinCashParser.statistics)
    }

    /// eCash (XEC) network stats from Blockchair. Same structure as BCH.
    public func eCash() async -> MiningDataResult<BitcoinCashStatistics> {
        await fetch(.xecStats, parse: MiningInsightsBitcoinCashParser.statistics)
    }

    /// DigiByte (DGB) SHA-256d network stats from the dedicated public SHA-256 pool endpoint.
    /// The existing result type is retained for app compatibility; only fields with verified
    /// network semantics are populated.
    public func digiByte() async -> MiningDataResult<BitcoinCashStatistics> {
        await fetch(.dgbStats, parse: MiningInsightsDigiByteParser.statistics)
    }

    /// Fetches canonical market symbols and icon URLs for all supported SHA-256d coins.
    /// This is read-only presentation data and never changes miner configuration.
    public func coinMarkets() async -> MiningDataResult<[MiningPoolCoin: CoinGeckoMarket]> {
        await fetch(.coinMarkets, parse: MiningInsightsParser.coinMarkets)
    }

    /// Use a manually entered address or a ConnectedPoolLookup after honoring the app's disclosure/opt-out.
    /// This method does not itself inspect miner configuration. Aggregate refresh never invokes it.
    public func ckPoolUser(address: String) async -> CKPoolUserLookup {
        guard !Task.isCancelled else { return .failed(.cancelled) }
        guard let address = MiningInsightsAddress.validated(address) else { return .failed(.invalidBitcoinAddress) }
        let url = MiningInsightsEndpoint.ckPoolUser.url.appendingPathComponent(address)
        let result = await fetch(.ckPoolUser, url: url, parse: MiningInsightsParser.user)
        if result.error == .http(statusCode: 404) { return .notFound(fetchedAt: result.fetchedAt) }
        if let error = result.error { return .failed(error) }
        return .found(result)
    }

    private func cancelled<Value: Sendable>(_ endpoint: MiningInsightsEndpoint) -> MiningDataResult<Value> {
        MiningDataResult(error: .cancelled, fetchedAt: Date(), sourceURL: endpoint.url)
    }

    private func fetch<Value: Sendable>(
        _ endpoint: MiningInsightsEndpoint,
        url: URL? = nil,
        parse: @Sendable (Data) throws -> (Value, Date?)
    ) async -> MiningDataResult<Value> {
        let sourceURL = url ?? endpoint.url
        do {
            try Task.checkCancellation()
            let request = try request(for: endpoint, url: sourceURL)
            let (data, response) = try await transport.session.data(
                for: request,
                delegate: MiningInsightsRequestGuard()
            )
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw MiningInsightsError.invalidResponse }
            // A second check protects against custom transports returning a different destination.
            guard http.url == sourceURL else { throw MiningInsightsError.redirected }
            guard !(300...399).contains(http.statusCode) else { throw MiningInsightsError.redirected }
            guard (200...299).contains(http.statusCode) else {
                throw MiningInsightsError.http(statusCode: http.statusCode)
            }
            guard data.count <= 1_048_576 else { throw MiningInsightsError.invalidData }
            let (value, timestamp) = try parse(data)
            try Task.checkCancellation()
            return MiningDataResult(value: value, fetchedAt: Date(), sourceURL: sourceURL, sourceTimestamp: timestamp)
        } catch {
            return MiningDataResult(error: sanitized(error), fetchedAt: Date(), sourceURL: sourceURL)
        }
    }

    /// Internal for exhaustive tests. There is no public arbitrary-URL execution method.
    func request(for endpoint: MiningInsightsEndpoint, url: URL? = nil) throws -> URLRequest {
        let url = url ?? endpoint.url
        guard url.scheme == "https", url.host == endpoint.url.host, url.port == nil,
            url.user == nil, url.password == nil, url.fragment == nil
        else {
            throw MiningInsightsError.invalidResponse
        }
        if endpoint == .ckPoolUser {
            let address = url.lastPathComponent
            guard MiningInsightsAddress.validated(address) == address,
                url.absoluteString == endpoint.url.appendingPathComponent(address).absoluteString
            else {
                throw MiningInsightsError.invalidBitcoinAddress
            }
        } else {
            guard url == endpoint.url else { throw MiningInsightsError.invalidResponse }
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json, text/plain;q=0.9", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func sanitized(_ error: any Error) -> MiningInsightsError {
        if Task.isCancelled || error is CancellationError { return .cancelled }
        if let error = error as? MiningInsightsError { return error }
        if let error = error as? URLError {
            switch error.code {
            case .cancelled: return .cancelled
            case .timedOut: return .timedOut
            default: return .network(code: error.errorCode)
            }
        }
        return .invalidData
    }
}

private final class MiningInsightsTransport: Sendable {
    let session: URLSession
    init(configuration: URLSessionConfiguration) { session = URLSession(configuration: configuration) }
    deinit { session.invalidateAndCancel() }
}

/// All redirects are rejected, including same-host redirects, to prevent accidental wallet forwarding.
final class MiningInsightsRequestGuard: NSObject, URLSessionDataDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        willCacheResponse proposedResponse: CachedURLResponse,
        completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void
    ) {
        completionHandler(nil)
    }
}
