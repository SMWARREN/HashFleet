import Foundation
import HashFleetCore

/// Each fixture has its own reserved .invalid hostname. The lock protects the
/// registry only, never handler execution, so parallel tests cannot steal stubs.
private final class StubRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]

    func set(_ handler: Handler?, for host: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers[host] = handler
    }

    func handler(for host: String) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[host]
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    fileprivate static let registry = StubRegistry()

    // Catch everything, including unexpected requests, so no test falls through
    // to DNS, sockets, physical miners, or the public internet.
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host,
              let handler = Self.registry.handler(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class MockTransport: Sendable {
    let host: String
    let session: URLSession
    let client: MinerAPIClient

    init(handler: @escaping @Sendable (URLRequest) throws -> (URLResponse, Data)) {
        let host = "mock-\(UUID().uuidString.lowercased()).invalid"
        self.host = host
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)
        self.client = MinerAPIClient(device: MinerDevice(name: "Offline fixture", address: host), session: session)
        MockURLProtocol.registry.set(handler, for: host)
    }

    deinit {
        session.invalidateAndCancel()
        MockURLProtocol.registry.set(nil, for: host)
    }
}

func stubResponse(for request: URLRequest, status: Int = 200,
                  data: Data = Data(), headers: [String: String] = [:]) throws -> (URLResponse, Data) {
    guard let url = request.url,
          let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                         headerFields: headers) else {
        throw URLError(.badURL)
    }
    return (response, data)
}

/// URLSession may move httpBody to httpBodyStream before URLProtocol receives it.
func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
        if count == 0 { return data }
        data.append(contentsOf: buffer.prefix(count))
    }
}
