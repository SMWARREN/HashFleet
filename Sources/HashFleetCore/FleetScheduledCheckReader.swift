import Foundation

public enum FleetScheduledCheckReadError: Error, Equatable {
    case invalidTarget, invalidResponse, tooLarge, identityMismatch
}

private final class ScheduledCheckRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// A fixed-endpoint, bounded read. This client cannot control or discover miners.
public struct FleetScheduledCheckReader: Sendable {
    private let injectedSession: URLSession?
    public static let maximumBytes = 131_072
    public init() { injectedSession = nil }
    // Internal injection is for URLProtocol fixtures, never payload-supplied configuration.
    init(session: URLSession) { injectedSession = session }

    static func configuration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.urlCredentialStorage = nil
        c.connectionProxyDictionary = [:]
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 12
        c.waitsForConnectivity = false
        c.httpMaximumConnectionsPerHost = 1
        return c
    }

    public func read(_ target: FleetScheduledCheckTarget) async throws -> FleetScheduledCheckReading {
        guard target.isValid else { throw FleetScheduledCheckReadError.invalidTarget }
        try Task.checkCancellation()
        let session = injectedSession ?? URLSession(configuration: Self.configuration(),
            delegate: ScheduledCheckRedirectGuard(), delegateQueue: nil)
        defer { if injectedSession == nil { session.invalidateAndCancel() } }
        let url = target.baseURL.appendingPathComponent("api/system/info")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == url else {
            throw FleetScheduledCheckReadError.invalidResponse
        }
        guard response.expectedContentLength <= Int64(Self.maximumBytes) else { throw FleetScheduledCheckReadError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumBytes else { throw FleetScheduledCheckReadError.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try Self.decode(data, expectedMAC: target.expectedMAC)
    }

    static func decode(_ data: Data, expectedMAC: String) throws -> FleetScheduledCheckReading {
        guard data.count <= maximumBytes else { throw FleetScheduledCheckReadError.tooLarge }
        guard let pin = FleetScheduledCheckTarget.normalizedMAC(expectedMAC),
              let object = try? JSONDecoder().decode(FirmwareSummary.self, from: data) else {
            throw FleetScheduledCheckReadError.invalidResponse
        }
        guard !object.macs.isEmpty,
              object.macs.allSatisfy({ FleetScheduledCheckTarget.normalizedMAC($0) == pin }) else {
            throw FleetScheduledCheckReadError.identityMismatch
        }
        return object.reading
    }
}

/// Decode only allowlisted fields. Unknown firmware fields are never retained, uploaded or logged.
private struct FirmwareSummary: Decodable {
    let macs: [String]
    let reading: FleetScheduledCheckReading
    enum CodingKeys: String, CodingKey {
        case macAddr, macAddress, mac, hashRate, hashrate, temp, power, sharesAccepted, sharesRejected
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var identities: [String] = []
        for key in [CodingKeys.macAddr, .macAddress, .mac] where c.contains(key) {
            // A present malformed identity must not be hidden by a different valid alias.
            identities.append(try c.decode(String.self, forKey: key))
        }
        macs = identities
        func number(_ key: CodingKeys) -> Double? {
            if let value = try? c.decode(Double.self, forKey: key) { return value }
            if let text = try? c.decode(String.self, forKey: key), text.utf8.count <= 32 { return Double(text) }
            return nil
        }
        func count(_ key: CodingKeys) -> UInt64? { try? c.decode(UInt64.self, forKey: key) }
        reading = .init(hashRateGHs: number(.hashRate) ?? number(.hashrate), temperatureC: number(.temp),
                        powerW: number(.power), sharesAccepted: count(.sharesAccepted), sharesRejected: count(.sharesRejected))
    }
}
