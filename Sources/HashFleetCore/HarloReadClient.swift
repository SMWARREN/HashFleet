import Foundation

/// Never includes device data, a URL, headers or an underlying Foundation error.
public enum HarloReadError: Error, Equatable, Sendable {
    case invalidAddress, invalidPolicy, notAdvertised, rateLimited, invalidResponse, tooLarge
    case timeout, connectionLost, transport, http(Int)
}

public struct HarloReadPolicy: Sendable {
    public let timeout: TimeInterval
    public let retries: Int
    public let minimumInterval: TimeInterval
    public let maximumBytes: Int

    public init(timeout: TimeInterval = 8, retries: Int = 0, minimumInterval: TimeInterval = 1,
                maximumBytes: Int = 262_144) throws {
        guard (0.1...60).contains(timeout), (0...2).contains(retries),
              (0.1...60).contains(minimumInterval), (1...1_048_576).contains(maximumBytes)
        else { throw HarloReadError.invalidPolicy }
        self.timeout = timeout
        self.retries = retries
        self.minimumInterval = minimumInterval
        self.maximumBytes = maximumBytes
    }
}

/// One opt-in origin, one in-flight read. Retain the client to share its pacing and evidence.
/// The origin is operator-selected, not a LAN-only sandbox. No DNS lookup or request on init.
/// Call `read(.info)` explicitly before optional reads and to refresh the 60-second evidence.
public actor HarloReadClient {
    private let base: URL
    private let policy: HarloReadPolicy
    private let profile: HarloInfoProfile?
    private let session: URLSession
    private let clock = ContinuousClock()
    private var nextAttempt = ContinuousClock.Instant.now
    // A server-imposed cooldown rejects calls rather than queuing sleepers.
    private var cooldownUntil = Date.distantPast
    private var advertised: Set<HarloReadEndpoint> = []
    private var evidenceExpires = ContinuousClock.Instant.now
    private var busy = false

    public init(baseURL: String, policy: HarloReadPolicy? = nil, profile: HarloInfoProfile? = nil) throws {
        try self.init(baseURL: baseURL, policy: policy, profile: profile, protocolClasses: nil)
    }

    // Internal URLProtocol hook for offline tests. Public callers cannot inject a proxying,
    // authenticated or redirect-following session into this client.
    init(baseURL: String, policy: HarloReadPolicy?, profile: HarloInfoProfile?, protocolClasses: [AnyClass]?) throws {
        guard baseURL == baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
              let base = try? MinerDevice(name: "", address: baseURL).validatedURL()
        else { throw HarloReadError.invalidAddress }
        self.base = base
        self.policy = try policy ?? HarloReadPolicy()
        self.profile = profile
        let configuration = Self.configuration(policy: self.policy)
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        self.session = URLSession(configuration: configuration, delegate: HarloTransportGuard(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    static func configuration(policy: HarloReadPolicy) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        // nil inherits system proxies. Explicitly turn off manual proxy, PAC and autodiscovery.
        config.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0,
                                            "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0]
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = policy.timeout
        config.timeoutIntervalForResource = policy.timeout
        config.httpMaximumConnectionsPerHost = 1
        config.waitsForConnectivity = false
        return config
    }

    public func read(_ endpoint: HarloReadEndpoint) async throws -> HarloReadResult {
        try Task.checkCancellation()
        guard !busy, Date.now >= cooldownUntil else { throw HarloReadError.rateLimited }
        if endpoint == .info { advertised.removeAll() }
        busy = true
        defer { busy = false }

        for attempt in 0...policy.retries {
            try authorize(endpoint)
            if clock.now < nextAttempt { try await clock.sleep(until: nextAttempt) }
            try Task.checkCancellation()
            try authorize(endpoint) // Evidence can expire during pacing or a retry.
            nextAttempt = clock.now.advanced(by: .seconds(policy.minimumInterval))
            do {
                let body = try await fetch(endpoint)
                try Task.checkCancellation()
                let result = HarloReadResult.project(endpoint, body: body, profile: profile)
                if case let .info(_, endpoints) = result {
                    advertised = endpoints
                    evidenceExpires = clock.now.advanced(by: .seconds(60))
                }
                return result
            } catch let error as HarloReadError {
                switch error {
                case .timeout, .connectionLost:
                    if attempt < policy.retries { continue }
                case .http(404), .http(405), .http(410): advertised.remove(endpoint)
                default: break
                }
                throw error
            }
        }
        throw HarloReadError.transport
    }

    private func authorize(_ endpoint: HarloReadEndpoint) throws {
        guard endpoint == .info || (clock.now < evidenceExpires && advertised.contains(endpoint))
        else { throw HarloReadError.notAdvertised }
    }

    static func cooldownEnd(_ retryAfter: String?, now: Date) -> Date {
        if let value = retryAfter?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
            if value.utf8.allSatisfy({ (48...57).contains($0) }) {
                // Unrepresentably long cooldowns stay blocked for this client; never sleep on them.
                guard let seconds = UInt64(value) else { return .distantFuture }
                return min(.distantFuture, now.addingTimeInterval(Double(seconds)))
            }
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(secondsFromGMT: 0)
            parser.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            if let end = parser.date(from: value) { return end }
        }
        return now.addingTimeInterval(60)
    }

    private func fetch(_ endpoint: HarloReadEndpoint) async throws -> Data {
        // base is an origin only. The closed enum is the only source of a path component.
        let url = base.appending(component: "api").appending(component: endpoint.rawValue)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: policy.timeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.url == url else { throw HarloReadError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                if http.statusCode == 429 || (http.statusCode == 503 && retryAfter != nil) {
                    cooldownUntil = Self.cooldownEnd(retryAfter, now: .now)
                }
                throw HarloReadError.http(http.statusCode)
            }
            guard response.expectedContentLength <= policy.maximumBytes else { throw HarloReadError.tooLarge }
            var body = Data()
            var count = 0
            for try await byte in bytes {
                try Task.checkCancellation()
                guard count < policy.maximumBytes else { throw HarloReadError.tooLarge }
                count += 1
                if endpoint != .logs { body.append(byte) }
            }
            return body
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            if let safe = error as? HarloReadError { throw safe }
            switch (error as? URLError)?.code {
            case .timedOut: throw HarloReadError.timeout
            case .networkConnectionLost: throw HarloReadError.connectionLost
            default: throw HarloReadError.transport
            }
        }
    }
}

private final class HarloTransportGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Preserve platform TLS verification. Do not provide credentials or display auth prompts.
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .rejectProtectionSpace, nil)
    }
}
