import Foundation

public enum MinerAPIError: Error, LocalizedError, Sendable {
    case invalidAddress(String)
    case invalidPoolIndex(Int)
    case webSocketRequired
    case notWebSocket
    case invalidResponse
    case unrecognizedInfo
    case binaryBodyRequired
    case webSocketBufferOverflow
    case http(statusCode: Int, message: String, body: Data)

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "Enter a host, IP address, or .local name with an optional HTTP(S) scheme and port. "
                + "Paths, credentials, queries and fragments are not allowed."
        case .invalidPoolIndex(let index): "Pool slot \(index) is invalid. Use a slot from 0 through 7."
        case .webSocketRequired: "Use webSocketStream for this WebSocket endpoint."
        case .notWebSocket: "This endpoint does not support WebSockets."
        case .invalidResponse: "The miner returned a non-HTTP response."
        case .unrecognizedInfo:
            "The device returned unrecognized system information. "
                + "Check that this address runs compatible ESP-Miner firmware."
        case .binaryBodyRequired:
            "OTA requires raw firmware bytes. Use execute with a binary Data body, not executeJSON."
        case .webSocketBufferOverflow:
            "The WebSocket consumer fell behind. Reconnect to obtain a fresh complete state."
        case .http(let status, let message, _): "HTTP \(status): \(message)"
        }
    }
}

public enum MinerWebSocketMessage: Hashable, Sendable {
    case text(String)
    case data(Data)

    public var data: Data {
        switch self {
        case .text(let string): Data(string.utf8)
        case .data(let data): data
        }
    }
    public var text: String? { String(data: data, encoding: .utf8) }
    public func json() throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }
}

/// Explicit, one-shot requests. No retries, discovery, polling or automatic mutations.
public struct MinerAPIClient: Sendable {
    public let device: MinerDevice
    private let session: URLSession

    public init(device: MinerDevice, session: URLSession = .shared) {
        self.device = device
        self.session = session
    }

    public func info() async throws -> MinerInfo {
        let info = try JSONDecoder().decode(MinerInfo.self, from: await execute(.info))
        guard MinerShapeValidator.isValidInfoShape(.object(info.raw)) else {
            throw MinerAPIError.unrecognizedInfo
        }
        return info
    }

    /// The device's own authoritative best-share history (persisted in NVS, survives reboots),
    /// ranked by difficulty. See `MinerScoreboardEntry` for why this is preferable to
    /// polling-derived best-share detection for a permanent achievements record. Not every
    /// firmware build exposes this endpoint; a 404 propagates as `MinerAPIError.http`.
    public func scoreboard() async throws -> [MinerScoreboardEntry] {
        try JSONDecoder().decode([MinerScoreboardEntry].self, from: await execute(.scoreboard))
    }

    /// Builds a request without resolving or contacting any host.
    public func request(
        for endpoint: MinerEndpoint,
        body: Data? = nil,
        query: [URLQueryItem] = []
    ) throws -> URLRequest {
        try endpoint.validate()
        let base = try device.validatedURL()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw MinerAPIError.invalidAddress(device.address)
        }
        components.path = endpoint.path
        components.queryItems = query.isEmpty ? nil : query
        if endpoint.isWebSocket { components.scheme = components.scheme == "https" ? "wss" : "ws" }
        guard let url = components.url else { throw MinerAPIError.invalidAddress(device.address) }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: endpoint.timeout
        )
        request.httpMethod = endpoint.method
        request.httpShouldHandleCookies = false
        request.httpBody = body
        let acceptsAnything =
            endpoint == .logs || endpoint == .recovery || endpoint.isBinaryUpload || endpoint.isWebSocket
        request.setValue(acceptsAnything ? "*/*" : "application/json", forHTTPHeaderField: "Accept")
        if body != nil || endpoint.isBinaryUpload {
            request.setValue(endpoint.contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Returns response bytes unchanged, including text/HTML and empty successful bodies.
    public func execute(
        _ endpoint: MinerEndpoint,
        body: Data? = nil,
        query: [URLQueryItem] = []
    ) async throws -> Data {
        guard !endpoint.isWebSocket else { throw MinerAPIError.webSocketRequired }
        if endpoint.isBinaryUpload && (body == nil || body?.isEmpty == true) {
            throw MinerAPIError.binaryBodyRequired
        }
        let request = try request(for: endpoint, body: body, query: query)
        let (data, response) = try await session.data(for: request, delegate: MinerRedirectBlocker())
        guard let http = response as? HTTPURLResponse else { throw MinerAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw MinerAPIError.http(
                statusCode: http.statusCode,
                message: Self.errorMessage(data, status: http.statusCode),
                body: data
            )
        }
        return data
    }

    /// JSON convenience. For text/HTML/OTA results use execute instead.
    public func executeJSON(
        _ endpoint: MinerEndpoint,
        body: JSONValue? = nil,
        query: [URLQueryItem] = []
    ) async throws -> JSONValue {
        guard !endpoint.isBinaryUpload else { throw MinerAPIError.binaryBodyRequired }
        let encoded = try body.map { try JSONEncoder().encode($0) }
        let data = try await execute(endpoint, body: encoded, query: query)
        return data.isEmpty ? .null : try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Starts one socket. The firmware pushes frames without a subscription command.
    /// Bounded to 512 pending frames. Overflow fails explicitly, never silently losing diffs.
    /// Cancel the consuming task to close the socket, including when leaving a view early.
    /// A normal close finishes the sequence. There is no automatic reconnect or heartbeat.
    public func webSocketStream(
        _ endpoint: MinerEndpoint = .logWebSocket
    ) throws -> AsyncThrowingStream<MinerWebSocketMessage, any Error> {
        guard endpoint.isWebSocket else { throw MinerAPIError.notWebSocket }
        let request = try request(for: endpoint)
        let socket = session.webSocketTask(with: request)
        socket.delegate = MinerRedirectBlocker()
        return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(512)) { continuation in
            let receiver = Task {
                socket.resume()
                defer { socket.cancel(with: .goingAway, reason: nil) }
                await Self.consumeFrames(socket: socket, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                receiver.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    public func logStream() throws -> AsyncThrowingStream<MinerWebSocketMessage, any Error> {
        try webSocketStream(.logWebSocket)
    }
    public func liveStream() throws -> AsyncThrowingStream<MinerWebSocketMessage, any Error> {
        try webSocketStream(.liveWebSocket)
    }

    private static func consumeFrames(
        socket: URLSessionWebSocketTask,
        continuation: AsyncThrowingStream<MinerWebSocketMessage, any Error>.Continuation
    ) async {
        do {
            while !Task.isCancelled {
                let frame = try await socket.receive()
                let message: MinerWebSocketMessage
                switch frame {
                case .string(let text): message = .text(text)
                case .data(let data): message = .data(data)
                @unknown default: continue
                }
                switch continuation.yield(message) {
                case .dropped:
                    continuation.finish(throwing: MinerAPIError.webSocketBufferOverflow)
                    return
                case .terminated: return
                case .enqueued: break
                @unknown default: break
                }
            }
            continuation.finish()
        } catch {
            if Task.isCancelled || socket.closeCode == .normalClosure {
                continuation.finish()
            } else {
                continuation.finish(throwing: error)
            }
        }
    }

    private static func errorMessage(_ data: Data, status: Int) -> String {
        if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            for key in ["message", "error", "detail"] {
                if let text = json[key]?.stringValue, !text.isEmpty { return text }
                if let nested = json[key]?["message"]?.stringValue, !nested.isEmpty { return nested }
            }
            if case .string(let text) = json, !text.isEmpty { return text }
        }
        let decoded = String(data: data, encoding: .utf8) ?? ""
        let text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : text
    }
}

/// Firmware captive-portal redirects must never turn API calls into apparent HTML successes,
/// nor forward a mutation body to another host. Every redirect remains a visible HTTP error.
private final class MinerRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
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
