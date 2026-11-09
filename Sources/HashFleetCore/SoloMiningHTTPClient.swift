import Foundation

final class SoloMiningHTTPClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession?) {
        let config = session?.configuration ?? .ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.httpAdditionalHeaders = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    deinit { session.invalidateAndCancel() }

    func get<Value: Sendable>(
        url: URL,
        productionBaseURL: URL,
        parse: @Sendable (Data) throws -> (Value, Date?)
    ) async -> MiningDataResult<Value> {
        guard !Task.isCancelled else { return Self.failure(url, error: .cancelled) }
        guard url.scheme == "https", url.host == productionBaseURL.host, url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            return Self.failure(productionBaseURL, error: .invalidResponse)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request, delegate: MiningInsightsRequestGuard())
            try Task.checkCancellation()
            if let error = Self.responseError(data: data, response: response, url: url) {
                return Self.failure(url, error: error)
            }
            let (parsed, sourceTimestamp) = try parse(data)
            try Task.checkCancellation()
            return MiningDataResult(value: parsed, fetchedAt: Date(), sourceURL: url, sourceTimestamp: sourceTimestamp)
        } catch {
            return Self.failure(url, error: Self.mappedError(error))
        }
    }

    static func failure<Value: Sendable>(_ url: URL, error: MiningInsightsError) -> MiningDataResult<Value> {
        MiningDataResult(error: error, fetchedAt: Date(), sourceURL: url)
    }

    private static func responseError(data: Data, response: URLResponse, url: URL) -> MiningInsightsError? {
        guard data.count <= 1_048_576 else { return .invalidData }
        guard let http = response as? HTTPURLResponse else { return .invalidResponse }
        guard http.url == url, !(300...399).contains(http.statusCode) else { return .redirected }
        guard http.statusCode == 200 else { return .http(statusCode: http.statusCode) }
        return nil
    }

    private static func mappedError(_ error: any Error) -> MiningInsightsError {
        if Task.isCancelled || error is CancellationError { return .cancelled }
        if let error = error as? MiningInsightsError { return error }
        if let error = error as? URLError {
            if error.code == .timedOut { return .timedOut }
            if error.code == .cancelled { return .cancelled }
            return .network(code: error.errorCode)
        }
        return .invalidData
    }
}
