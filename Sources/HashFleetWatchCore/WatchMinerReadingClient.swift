import Foundation

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
        let initialRequest = try Self.request(for: miner, path: Self.defaultPath)
        do {
            let (data, _) = try await transport.load(initialRequest, deadline: Self.overallTimeout)
            try Task.checkCancellation()
            return try WatchMinerInfoDecoder.reading(from: data, minerID: miner.id, observedAt: now())
        } catch {
            if Task.isCancelled { throw CancellationError() }

            #if canImport(Darwin)
            if let endpoint = try? WatchEndpoint.normalize(miner.address), endpoint.port == 4028 {
                if let cgData = try? await Self.queryCgminer(host: endpoint.host, port: 4028, timeout: Self.requestTimeout),
                   let cgReading = try? WatchMinerInfoDecoder.reading(from: cgData, minerID: miner.id, observedAt: now()) {
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
    static func queryCgminer(host: String, port: Int, timeout: TimeInterval) async throws -> Data {
        let cleanHost = host.hasPrefix("[") && host.hasSuffix("]")
            ? String(host.dropFirst().dropLast())
            : host
        guard !cleanHost.isEmpty, (1...65_535).contains(port) else {
            throw WatchMinerFetchError.invalidEndpoint
        }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(cleanHost, String(port), &hints, &res)
        guard status == 0, let first = res else {
            throw WatchMinerFetchError.unreachable
        }
        defer { freeaddrinfo(first) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            defer { cursor = info.pointee.ai_next }
            let fd = Darwin.socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            guard fd >= 0 else { continue }

            var noSigPipe: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            let flags = fcntl(fd, F_GETFL, 0)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

            let connectRes = Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
            var connected = connectRes == 0
            if !connected && errno == EINPROGRESS {
                var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let pollTimeoutMs = Int32(max(1, Int(timeout * 1000)))
                let pollRes = poll(&pfd, 1, pollTimeoutMs)
                if pollRes > 0 && (pfd.revents & Int16(POLLOUT)) != 0 {
                    var sockErr: Int32 = 0
                    var errLen = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(fd, SOL_SOCKET, SO_ERROR, &sockErr, &errLen)
                    if sockErr == 0 { connected = true }
                }
            }
            guard connected else {
                Darwin.close(fd)
                continue
            }

            defer { Darwin.close(fd) }
            _ = fcntl(fd, F_SETFL, flags)

            let cmd = Data("{\"command\":\"summary\"}\n".utf8)
            let written = cmd.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, cmd.count) }
            guard written == cmd.count else { throw WatchMinerFetchError.unreachable }

            var responseData = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            let readDeadline = Date().addingTimeInterval(timeout)
            while Date() < readDeadline {
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let remainingMs = Int32(max(1, Int(readDeadline.timeIntervalSinceNow * 1000)))
                let pollRes = poll(&pfd, 1, remainingMs)
                guard pollRes > 0, (pfd.revents & Int16(POLLIN)) != 0 else { break }
                let bytesRead = Darwin.read(fd, &buffer, buffer.count)
                guard bytesRead > 0 else { break }
                let slice = buffer.prefix(bytesRead)
                if let nullIdx = slice.firstIndex(of: 0) {
                    responseData.append(Data(slice[..<nullIdx]))
                    break
                } else {
                    responseData.append(Data(slice))
                }
            }
            guard !responseData.isEmpty else { throw WatchMinerFetchError.invalidResponse }
            return responseData
        }
        throw WatchMinerFetchError.unreachable
    }
    #endif
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
            case hashRate, hashrate, hashrate_ghs
            case power, device_power_w, asic_rail_power_w
            case temp, temp2, chiptemp1, chiptemp2, asic_temp_c
            case vrTemp, vr_temp_c
            case uptimeSeconds, uptime_seconds
            case sharesAccepted, shares_accepted, sAccepted
            case sharesRejected, shares_rejected, sRejected
            case miningPaused, asic_paused, paused, shutdown
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // A field with the wrong type (string, boolean, ...) is "not reported", not zero.
            func number(_ key: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil }
            func integer(_ key: CodingKeys) -> Int? { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil }
            hashRate = number(.hashRate) ?? number(.hashrate) ?? number(.hashrate_ghs)
            power = number(.power) ?? number(.device_power_w) ?? number(.asic_rail_power_w)
            temp = number(.temp) ?? number(.chiptemp1) ?? number(.asic_temp_c)
            temp2 = number(.temp2) ?? number(.chiptemp2)
            vrTemp = number(.vrTemp) ?? number(.vr_temp_c)
            uptimeSeconds = number(.uptimeSeconds) ?? number(.uptime_seconds)
            sharesAccepted = integer(.sharesAccepted) ?? integer(.shares_accepted) ?? integer(.sAccepted)
            sharesRejected = integer(.sharesRejected) ?? integer(.shares_rejected) ?? integer(.sRejected)
            if let flag = (try? c.decodeIfPresent(Bool.self, forKey: .miningPaused))
                ?? (try? c.decodeIfPresent(Bool.self, forKey: .asic_paused))
                ?? (try? c.decodeIfPresent(Bool.self, forKey: .paused))
                ?? (try? c.decodeIfPresent(Bool.self, forKey: .shutdown)) {
                miningPaused = flag
            } else if let value = integer(.miningPaused) ?? integer(.asic_paused) ?? integer(.paused) ?? integer(.shutdown),
                      value == 0 || value == 1 {
                miningPaused = value == 1
            } else {
                miningPaused = nil
            }
        }
    }

    static func reading(from data: Data, minerID: UUID, observedAt: Date) throws -> WatchMinerReading {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw WatchMinerFetchError.invalidResponse
        }
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
        guard hasMetric else { throw WatchMinerFetchError.invalidResponse }
        return reading
    }

    /// Negative values and zero are sentinels for "no sensor", and absurdly large values are bad data.
    private static func validTemperature(_ value: Double?) -> Double? {
        WatchMinerReading.temperature(value)
    }
}
