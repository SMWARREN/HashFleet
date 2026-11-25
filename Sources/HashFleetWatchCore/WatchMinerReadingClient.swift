import Foundation
import Network

/// Reads one miner. Implementations must be read-only.
public protocol WatchMinerReadingClient: Sendable {
    func fetch(_ miner: WatchMiner) async throws -> WatchMinerReading
}

/// Safe, generic fetch failures. Messages never include addresses, response bodies or system error text.
public enum WatchMinerFetchError: Error, Equatable, Sendable, LocalizedError {
    case invalidEndpoint
    case unreachable
    case timedOut
    case redirected
    case badStatus
    case invalidResponse
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "This miner's address isn't valid."
        case .unreachable: "Couldn't reach this miner."
        case .timedOut: "The miner didn't answer in time."
        case .redirected: "The miner tried to send the Watch somewhere else."
        case .badStatus: "The miner returned an error."
        case .invalidResponse: "The miner's answer wasn't readable."
        case .responseTooLarge: "The miner's answer was too large."
        }
    }
}

/// Builds the ephemeral, bounded, cookie/cache/credential-free sessions used by both the single-miner reader and
/// the local discovery scanner. Keeping one factory means every read-only client shares identical safety defaults.
enum WatchSecureHTTP {
    /// Ephemeral session: no cookies, cache or credential storage, and bounded timeouts. `protocolClasses`
    /// is only supplied by tests to install a `URLProtocol` stub; production callers leave it `nil`.
    static func ephemeralSession(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        maximumConnectionsPerHost: Int = 2,
        protocolClasses: [AnyClass]? = nil
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = maximumConnectionsPerHost
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return URLSession(configuration: configuration)
    }
}

/// Bounded, secure, read-only HTTP transport shared by the single-miner reader and the local discovery scanner.
/// It streams at most `maximumResponseBytes`, rejects every redirect, validates a 2xx status, maps failures to
/// `WatchMinerFetchError`, and honors cancellation. It never persists raw response data.
struct WatchHTTPTransport: Sendable {
    let session: URLSession
    let maximumResponseBytes: Int

    init(session: URLSession, maximumResponseBytes: Int = WatchMinerHTTPClient.maximumResponseBytes) {
        self.session = session
        self.maximumResponseBytes = maximumResponseBytes
    }

    /// Runs `load` under a hard wall-clock deadline that cancels the request if it is exceeded.
    func load(_ request: URLRequest, deadline: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        try await withDeadline(seconds: deadline) { try await self.load(request) }
    }

    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RedirectRejector())
            guard let http = response as? HTTPURLResponse else { throw WatchMinerFetchError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw (300..<400).contains(http.statusCode) ? WatchMinerFetchError.redirected : .badStatus
            }
            if response.expectedContentLength > Int64(maximumResponseBytes) {
                throw WatchMinerFetchError.responseTooLarge
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maximumResponseBytes { throw WatchMinerFetchError.responseTooLarge }
            }
            return (data, http)
        } catch let error as WatchMinerFetchError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if Task.isCancelled { throw CancellationError() }
            switch error.code {
            case .timedOut: throw WatchMinerFetchError.timedOut
            case .httpTooManyRedirects: throw WatchMinerFetchError.redirected
            default: throw WatchMinerFetchError.unreachable
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw WatchMinerFetchError.unreachable
        }
    }

    func withDeadline<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw WatchMinerFetchError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw WatchMinerFetchError.unreachable }
            return first
        }
    }
}

/// Direct, read-only HTTP client. It issues only `GET /api/system/info`, never follows redirects, never stores
/// cookies, caches or credentials, and bounds time and response size. Raw response data is never persisted.
public struct WatchMinerHTTPClient: WatchMinerReadingClient {
    public static let defaultPath = "/api/system/info"
    public static let fallbackPaths = ["/api/telemetry", "/api/status", "/probe"]
    public static let path = defaultPath

    public static let maximumResponseBytes = 256 * 1024
    public static let requestTimeout: TimeInterval = 5
    public static let overallTimeout: TimeInterval = 10

    private let transport: WatchHTTPTransport
    private let now: @Sendable () -> Date

    /// Uses `makeDefaultSession()` unless a session is injected (for tests).
    public init(session: URLSession = WatchMinerHTTPClient.makeDefaultSession()) {
        self.transport = WatchHTTPTransport(session: session)
        self.now = { Date() }
    }

    init(session: URLSession, now: @escaping @Sendable () -> Date) {
        self.transport = WatchHTTPTransport(session: session)
        self.now = now
    }

    /// Ephemeral session: no cookies, cache or credential storage, and bounded timeouts.
    public static func makeDefaultSession() -> URLSession {
        WatchSecureHTTP.ephemeralSession(requestTimeout: requestTimeout, resourceTimeout: overallTimeout)
    }

    public static func request(for miner: WatchMiner) throws -> URLRequest {
        try request(for: miner, path: defaultPath)
    }

    public static func request(for miner: WatchMiner, path: String) throws -> URLRequest {
        // Revalidate: the address must still be a safe local endpoint.
        guard let endpoint = try? WatchEndpoint.normalize(miner.address),
              let url = URL(string: endpoint.description + path)
        else { throw WatchMinerFetchError.invalidEndpoint }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: requestTimeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func fetch(_ miner: WatchMiner) async throws -> WatchMinerReading {
        #if canImport(Darwin)
        if let endpoint = try? WatchEndpoint.normalize(miner.address), endpoint.port == 4028 {
            if let cgReading = try? await Self.queryCgminerReading(
                host: endpoint.host, port: 4028, minerID: miner.id, observedAt: now(), timeout: Self.requestTimeout
            ) {
                return cgReading
            }
        }
        #endif

        let initialRequest = try Self.request(for: miner, path: Self.defaultPath)
        do {
            let (data, _) = try await transport.load(initialRequest, deadline: Self.overallTimeout)
            try Task.checkCancellation()
            return try WatchMinerInfoDecoder.reading(from: data, minerID: miner.id, observedAt: now())
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if (error as? WatchMinerFetchError) == .timedOut { throw error }

            #if canImport(Darwin)
            if let endpoint = try? WatchEndpoint.normalize(miner.address), endpoint.port == 4028 {
                if let cgReading = try? await Self.queryCgminerReading(
                    host: endpoint.host, port: 4028, minerID: miner.id, observedAt: now(), timeout: Self.requestTimeout
                ) {
                    return cgReading
                }
            }
            #endif

            for fallbackPath in Self.fallbackPaths {
                guard let fallbackReq = try? Self.request(for: miner, path: fallbackPath) else { continue }
                if let (data, _) = try? await transport.load(fallbackReq, deadline: Self.overallTimeout),
                   let reading = try? WatchMinerInfoDecoder.reading(from: data, minerID: miner.id, observedAt: now()) {
                    return reading
                }
            }
            throw error
        }
    }

    #if canImport(Darwin)
    static func queryCgminerReading(
        host: String,
        port: Int,
        minerID: UUID,
        observedAt: Date,
        timeout: TimeInterval
    ) async throws -> WatchMinerReading {
        let summaryData = try await queryCgminer(host: host, port: port, command: "summary", timeout: timeout)
        let baseReading = try WatchMinerInfoDecoder.reading(from: summaryData, minerID: minerID, observedAt: observedAt)
        var chipTemp = baseReading.chipTemperatureC
        var power = baseReading.powerWatts

        let statsTimeout = min(timeout, 3)
        if let statsData = try? await queryCgminer(host: host, port: port, command: "stats", timeout: statsTimeout),
           let stats = try? JSONDecoder().decode(WatchCgminerStatsPayload.self, from: statsData),
           let item = stats.stats?.first {
            if chipTemp == nil {
                if let tMax = item.mmid0Summary?.hashInfo?.tMax {
                    chipTemp = WatchMinerReading.temperature(tMax)
                } else if let str = item.mmid0,
                          let range = str.range(of: "TMax\\[(\\d+)\\]", options: .regularExpression) {
                    let numStr = str[range].dropFirst(5).dropLast()
                    chipTemp = WatchMinerReading.temperature(Double(numStr))
                }
            }
            if power == nil, let str = item.mmid0,
               let range = str.range(of: "MPO\\[(\\d+)\\]", options: .regularExpression) {
                let numStr = str[range].dropFirst(4).dropLast()
                power = Double(numStr)
            }
        }

        return WatchMinerReading(
            minerID: minerID,
            observedAt: observedAt,
            hashrateGHs: baseReading.hashrateGHs,
            powerWatts: power ?? baseReading.powerWatts,
            chipTemperatureC: chipTemp ?? baseReading.chipTemperatureC,
            vrTemperatureC: baseReading.vrTemperatureC,
            uptimeSeconds: baseReading.uptimeSeconds,
            acceptedShares: baseReading.acceptedShares,
            rejectedShares: baseReading.rejectedShares,
            isMiningPaused: baseReading.isMiningPaused
        )
    }

    static func queryCgminer(
        host: String,
        port: Int,
        command: String = "summary",
        timeout: TimeInterval
    ) async throws -> Data {
        let cleanHost = host.hasPrefix("[") && host.hasSuffix("]")
            ? String(host.dropFirst().dropLast())
            : host
        guard !cleanHost.isEmpty,
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw WatchMinerFetchError.invalidEndpoint
        }
        let nwHost = NWEndpoint.Host(cleanHost)
        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "app.hashfleet.watch.cgminer")

        return try await withCheckedThrowingContinuation { continuation in
            final class SafeContinuation: @unchecked Sendable {
                private let lock = NSLock()
                private var continuation: CheckedContinuation<Data, any Error>?
                private weak var connection: NWConnection?

                init(continuation: CheckedContinuation<Data, any Error>, connection: NWConnection) {
                    self.continuation = continuation
                    self.connection = connection
                }

                func resume(with result: Result<Data, any Error>) {
                    lock.lock()
                    guard let cont = continuation else {
                        lock.unlock()
                        return
                    }
                    continuation = nil
                    let conn = connection
                    lock.unlock()
                    conn?.stateUpdateHandler = nil
                    conn?.cancel()
                    cont.resume(with: result)
                }
            }

            let safe = SafeContinuation(continuation: continuation, connection: connection)

            queue.asyncAfter(deadline: .now() + timeout) {
                safe.resume(with: .failure(WatchMinerFetchError.timedOut))
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let cmd = Data("{\"command\":\"\(command)\"}\n".utf8)
                    connection.send(content: cmd, completion: .contentProcessed { error in
                        if let error {
                            safe.resume(with: .failure(error))
                            return
                        }
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                            if let error {
                                safe.resume(with: .failure(error))
                            } else if let data, !data.isEmpty {
                                let cleanData: Data
                                if let nullIdx = data.firstIndex(of: 0) {
                                    cleanData = data.prefix(upTo: nullIdx)
                                } else {
                                    cleanData = data
                                }
                                safe.resume(with: .success(cleanData))
                            } else {
                                safe.resume(with: .failure(WatchMinerFetchError.invalidResponse))
                            }
                        }
                    })
                case .failed(let error):
                    safe.resume(with: .failure(error))
                case .cancelled:
                    safe.resume(with: .failure(WatchMinerFetchError.unreachable))
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
    #endif
}

private struct WatchCgminerSummaryPayload: Decodable {
    struct Item: Decodable {
        let elapsed: Double?
        let mhsAv: Double?
        let mhs5m: Double?
        let mhs1m: Double?
        let mhs5s: Double?
        let accepted: Int?
        let rejected: Int?

        enum CodingKeys: String, CodingKey {
            case elapsed = "Elapsed"
            case mhsAv = "MHS av"
            case mhs5m = "MHS 5m"
            case mhs1m = "MHS 1m"
            case mhs5s = "MHS 5s"
            case accepted = "Accepted"
            case rejected = "Rejected"
        }
    }
    let summary: [Item]?
    enum CodingKeys: String, CodingKey {
        case summary = "SUMMARY"
    }
}

private struct WatchCgminerStatsPayload: Decodable {
    struct HashInfo: Decodable {
        let tMax: Double?
        enum CodingKeys: String, CodingKey {
            case tMax = "TMax"
        }
    }
    struct MMID0Summary: Decodable {
        let hashInfo: HashInfo?
        enum CodingKeys: String, CodingKey {
            case hashInfo = "Hashinfo"
        }
    }
    struct StatItem: Decodable {
        let mmid0Summary: MMID0Summary?
        let mmid0: String?

        enum CodingKeys: String, CodingKey {
            case mmid0Summary = "MMID0Summary"
            case mmid0 = "MM ID0"
        }
    }
    let stats: [StatItem]?
    enum CodingKeys: String, CodingKey {
        case stats = "STATS"
    }
}

/// Refuses every redirect so a miner (or anything impersonating it) can't steer the Watch elsewhere.
final class RedirectRejector: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Decodes AxeOS-style `/api/system/info` JSON into a reading. Only the fields below are read, so pool, Wi-Fi
/// and other private fields never enter the model.
enum WatchMinerInfoDecoder {
    private struct Payload: Decodable {
        let hashRate: Double?
        let power: Double?
        let temp: Double?
        let temp2: Double?
        let vrTemp: Double?
        let uptimeSeconds: Double?
        let sharesAccepted: Int?
        let sharesRejected: Int?
        let miningPaused: Bool?

        enum CodingKeys: String, CodingKey {
            case hashRate, hashrate
            case hashrateGhs = "hashrate_ghs"
            case power
            case devicePowerW = "device_power_w"
            case asicRailPowerW = "asic_rail_power_w"
            case temp, temp2, chiptemp1, chiptemp2
            case asicTempC = "asic_temp_c"
            case vrTemp
            case vrTempC = "vr_temp_c"
            case uptimeSeconds
            case uptimeSecondsSnake = "uptime_seconds"
            case sharesAccepted
            case sharesAcceptedSnake = "shares_accepted"
            case sAccepted
            case sharesRejected
            case sharesRejectedSnake = "shares_rejected"
            case sRejected
            case miningPaused
            case asicPaused = "asic_paused"
            case paused, shutdown
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // A field with the wrong type (string, boolean, ...) is "not reported", not zero.
            func number(_ key: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil }
            func integer(_ key: CodingKeys) -> Int? { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil }
            hashRate = number(.hashRate) ?? number(.hashrate) ?? number(.hashrateGhs)
            power = number(.power) ?? number(.devicePowerW) ?? number(.asicRailPowerW)
            temp = number(.temp) ?? number(.chiptemp1) ?? number(.asicTempC)
            temp2 = number(.temp2) ?? number(.chiptemp2)
            vrTemp = number(.vrTemp) ?? number(.vrTempC)
            uptimeSeconds = number(.uptimeSeconds) ?? number(.uptimeSecondsSnake)
            sharesAccepted = integer(.sharesAccepted) ?? integer(.sharesAcceptedSnake) ?? integer(.sAccepted)
            sharesRejected = integer(.sharesRejected) ?? integer(.sharesRejectedSnake) ?? integer(.sRejected)
            if let flag = (try? c.decodeIfPresent(Bool.self, forKey: .miningPaused))
                ?? (try? c.decodeIfPresent(Bool.self, forKey: .asicPaused))
                ?? (try? c.decodeIfPresent(Bool.self, forKey: .paused))
                ?? (try? c.decodeIfPresent(Bool.self, forKey: .shutdown)) {
                miningPaused = flag
            } else if let value = integer(.miningPaused) ?? integer(.asicPaused) ?? integer(.paused) ?? integer(.shutdown),
                      value == 0 || value == 1 {
                miningPaused = value == 1
            } else {
                miningPaused = nil
            }
        }
    }

    static func reading(from data: Data, minerID: UUID, observedAt: Date) throws -> WatchMinerReading {
        if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            let temperatures = [payload.temp, payload.temp2].compactMap(validTemperature)
            let reading = WatchMinerReading(
                minerID: minerID,
                observedAt: observedAt,
                hashrateGHs: payload.hashRate,
                powerWatts: payload.power,
                chipTemperatureC: temperatures.max(),
                vrTemperatureC: validTemperature(payload.vrTemp),
                uptimeSeconds: payload.uptimeSeconds,
                acceptedShares: payload.sharesAccepted,
                rejectedShares: payload.sharesRejected,
                isMiningPaused: payload.miningPaused
            )
            // A page that parses as JSON but has none of the expected metrics is not a miner reading.
            let hasMetric = reading.hashrateGHs != nil || reading.powerWatts != nil
                || reading.chipTemperatureC != nil || reading.vrTemperatureC != nil
                || reading.uptimeSeconds != nil || reading.acceptedShares != nil
                || reading.rejectedShares != nil || reading.isMiningPaused != nil
            if hasMetric { return reading }
        }

        if let cgminer = try? JSONDecoder().decode(WatchCgminerSummaryPayload.self, from: data),
           let item = cgminer.summary?.first {
            let mhs = item.mhs5m ?? item.mhs1m ?? item.mhsAv ?? item.mhs5s
            let ghs = mhs.map { $0 / 1000.0 }
            let reading = WatchMinerReading(
                minerID: minerID,
                observedAt: observedAt,
                hashrateGHs: ghs,
                powerWatts: nil,
                chipTemperatureC: nil,
                vrTemperatureC: nil,
                uptimeSeconds: item.elapsed,
                acceptedShares: item.accepted,
                rejectedShares: item.rejected,
                isMiningPaused: nil
            )
            return reading
        }

        throw WatchMinerFetchError.invalidResponse
    }

    /// Negative values and zero are sentinels for "no sensor", and absurdly large values are bad data.
    private static func validTemperature(_ value: Double?) -> Double? {
        WatchMinerReading.temperature(value)
    }
}
