import Foundation
import Testing
@testable import HashFleet

@Suite(.serialized) @MainActor
struct FleetRemotePushHTTPTests {
    private func identity() throws -> FleetRemotePushIdentity { try FleetRemotePushKeychain.generate() }
    private let good = Data(#"{"ok":true,"mode":"device_check_v1","provider_ready":false,"settings":{"enabled":false,"miners":[]}}"#.utf8)

    @Test func actualRequestUsesOnlyFixedHTTPSOriginAndPrivateHeaders() async throws {
        let fixture = RemoteHTTPFixture(body: good)
        defer { fixture.close() }
        let id = try identity()
        let result = try await fixture.client.send(action: "status", method: "GET", identity: id, body: nil)
        #expect(result.ok && result.mode == "device_check_v1")
        #expect(result.providerReady == false)
        let request = try #require(fixture.requests.first)
        #expect(fixture.requests.count == 1)
        #expect(request.url?.absoluteString == "https://hashfleet.app/api/v1.php?action=status")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + id.secret)
        #expect(request.value(forHTTPHeaderField: "X-HashFleet-Installation") == id.id)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.httpBody == nil)
    }

    @Test func httpStatusAndIncompleteOrLegacyRepliesAreRejected() async throws {
        let id = try identity()
        for status in [301, 302, 307, 401, 403, 429, 500] {
            let fixture = RemoteHTTPFixture(status: status, body: good)
            defer { fixture.close() }
            await #expect(throws: FleetRemotePushError.self) {
                try await fixture.client.send(action: "status", method: "GET", identity: id, body: nil)
            }
            #expect(fixture.requests.count == 1)
        }
        for body in [#"{"ok":true}"#, #"{"ok":true,"mode":"legacy","provider_ready":true,"settings":{"enabled":true,"miners":[]}}"#,
            #"{"ok":true,"mode":"device_check_v1","settings":{"enabled":true,"miners":[]}}"#,
            #"{"ok":false,"mode":"device_check_v1","provider_ready":false,"settings":{"enabled":false,"miners":[]}}"#,
            "[]", "not JSON"] {
            let fixture = RemoteHTTPFixture(body: Data(body.utf8))
            defer { fixture.close() }
            await #expect(throws: FleetRemotePushError.self) {
                try await fixture.client.send(action: "preferences", method: "GET", identity: id, body: nil)
            }
        }
    }

    @Test func oversizedOrWrongOriginRepliesNeverReachCoordinator() async throws {
        let id = try identity()
        for size in [nil, "131073"] as [String?] {
            let fixture = RemoteHTTPFixture(body: Data(repeating: 32, count: 131_073), contentLength: size)
            defer { fixture.close() }
            await #expect(throws: FleetRemotePushError.self) {
                try await fixture.client.send(action: "status", method: "GET", identity: id, body: nil)
            }
        }
        let fixture = RemoteHTTPFixture(body: good, responseURL: URL(string: "https://example.com/api/v1.php"))
        defer { fixture.close() }
        await #expect(throws: FleetRemotePushError.self) {
            try await fixture.client.send(action: "status", method: "GET", identity: id, body: nil)
        }
    }

    @Test func malformedCredentialsDeprecatedActionsAndCancellationNeverStartNetwork() async throws {
        let fixture = RemoteHTTPFixture(body: good)
        defer { fixture.close() }
        let valid = try identity()
        #expect(valid.isValid)
        for secret in ["", "short", String(repeating: "A", count: 42) + "B", valid.secret + "\r\nInjected: value"] {
            let bad = FleetRemotePushIdentity(id: valid.id, secret: secret)
            #expect(!bad.isValid)
            await #expect(throws: FleetRemotePushError.self) {
                try await fixture.client.send(action: "status", method: "GET", identity: bad, body: nil)
            }
        }
        for action in ["telemetry", "relay", "send"] {
            await #expect(throws: FleetRemotePushError.self) {
                try await fixture.client.send(action: action, method: "POST", identity: valid, body: nil)
            }
        }
        let client = fixture.client
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await client.send(action: "status", method: "GET", identity: valid, body: nil)
                return false
            } catch { return true }
        }
        #expect(await cancelled.value)
        #expect(fixture.requests.isEmpty)
    }

    @Test func redirectDelegateNeverForwardsAuthorization() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://hashfleet.app")!)
        let response = HTTPURLResponse(url: URL(string: "https://hashfleet.app/api/v1.php")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let probe = RemoteRedirectProbe()
        FleetRemotePushRedirectGuard().urlSession(session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "https://example.com")!), completionHandler: { probe.record($0) })
        #expect(probe.called && !probe.forwarded)
    }
}

private final class RemoteRedirectProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var state = (false, false)
    func record(_ request: URLRequest?) { lock.withLock { state = (true, request != nil) } }
    var called: Bool { lock.withLock { state.0 } }
    var forwarded: Bool { lock.withLock { state.1 } }
}
private final class RemoteHTTPFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [URLRequest] = []
    private let session: URLSession
    let client: FleetRemotePushClient
    init(status: Int = 200, body: Data, contentLength: String? = nil, responseURL: URL? = nil) {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [RemoteURLProtocol.self]
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.urlCredentialStorage = nil
        c.connectionProxyDictionary = [:]
        session = URLSession(configuration: c, delegate: FleetRemotePushRedirectGuard(), delegateQueue: nil)
        client = FleetRemotePushClient(session: session)
        RemoteURLProtocol.registry.set { [weak self] request in
            self?.lock.withLock { self?.sent.append(request) }
            return (HTTPURLResponse(url: responseURL ?? request.url!, statusCode: status, httpVersion: nil,
                headerFields: contentLength.map { ["Content-Length": $0] })!, body)
        }
    }
    var requests: [URLRequest] { lock.withLock { sent } }
    func close() { session.invalidateAndCancel(); RemoteURLProtocol.registry.set(nil) }
    deinit { close() }
}
private final class RemoteHTTPRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)
    private let lock = NSLock()
    private var handler: Handler?
    func set(_ value: Handler?) { lock.withLock { handler = value } }
    func get() -> Handler? { lock.withLock { handler } }
}
private final class RemoteURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = RemoteHTTPRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.registry.get() else { throw URLError(.unsupportedURL) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
