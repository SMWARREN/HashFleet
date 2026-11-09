import Foundation
import Testing
import HashFleetCore
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct MinerOperationAuthorizationTests {
    @Test(arguments: ["demo", "removed", "readdressed", "expired"])
    func pendingPreflightCannotKeepRevokedPermission(reason: String) async {
        for endpoint in [MinerEndpoint.settings, .identify] {
            let fixture = AuthorizationFixture()
            defer { fixture.finish() }
            let eligibility = AuthorizationEligibility(device: fixture.device)
            let operation = Task {
                await fixture.model.execute(
                    device: fixture.device, endpoint: endpoint,
                    body: Data(#"{"hostname":"reviewed"}"#.utf8), query: [], isDemo: false,
                    writeAuthorized: { eligibility.allows(fixture.device) }
                )
            }
            await fixture.state.waitForPreflight()
            switch reason {
            case "demo": eligibility.isDemo = true
            case "removed": eligibility.devices = []
            case "readdressed":
                eligibility.devices = [MinerDevice(
                    id: fixture.device.id, name: "Changed target", address: "different.invalid"
                )]
            default: eligibility.now = eligibility.now.addingTimeInterval(181)
            }
            fixture.state.releasePreflight()
            await operation.value
            #expect(fixture.state.methods == ["GET"])
            #expect(fixture.model.error?.contains("connection changed") == true)
            #expect(!fixture.model.isRunning)
        }
    }

    @Test func retainedPermissionSendsExactlyOneReviewedWrite() async {
        for endpoint in [MinerEndpoint.settings, .identify] {
            let fixture = AuthorizationFixture()
            defer { fixture.finish() }
            let eligibility = AuthorizationEligibility(device: fixture.device)
            let operation = Task {
                await fixture.model.execute(
                    device: fixture.device, endpoint: endpoint,
                    body: Data(#"{"hostname":"reviewed"}"#.utf8), query: [], isDemo: false,
                    writeAuthorized: { eligibility.allows(fixture.device) }
                )
            }
            await fixture.state.waitForPreflight()
            #expect(fixture.state.methods == ["GET"])
            fixture.state.releasePreflight()
            await operation.value
            #expect(fixture.state.methods == ["GET", endpoint.method])
            #expect(fixture.model.error == nil)
        }
    }

    @Test func cancellationWhileInfoIsPendingCannotSendAWrite() async {
        let fixture = AuthorizationFixture()
        defer { fixture.finish() }
        let operation = Task {
            await fixture.model.execute(
                device: fixture.device, endpoint: .settings,
                body: Data(#"{"hostname":"reviewed"}"#.utf8), query: [], isDemo: false,
                writeAuthorized: { true }
            )
        }
        await fixture.state.waitForPreflight()
        operation.cancel()
        fixture.state.releasePreflight()
        await operation.value
        #expect(fixture.state.methods == ["GET"])
        #expect(fixture.model.error != nil)
        #expect(!fixture.model.isRunning)
    }

    @Test func refreshedBoardPolicyStillBlocksOvervoltage() async {
        let fixture = AuthorizationFixture()
        defer { fixture.finish() }
        let operation = Task {
            await fixture.model.execute(
                device: fixture.device, endpoint: .settings,
                body: Data(#"{"coreVoltage":1151}"#.utf8), query: [], isDemo: false,
                writeAuthorized: { true }
            )
        }
        await fixture.state.waitForPreflight()
        fixture.state.releasePreflight()
        await operation.value
        #expect(fixture.state.methods == ["GET"])
        #expect(fixture.model.error?.contains("1150") == true)
    }

    @Test func defaultAuthorizationAndDemoReadsNeverReachNetworking() async {
        let fixture = AuthorizationFixture()
        defer { fixture.finish() }
        await fixture.model.execute(
            device: fixture.device, endpoint: .settings, body: nil, query: [], isDemo: false
        )
        #expect(fixture.model.error?.contains("offline or stale") == true)
        await fixture.model.execute(
            device: fixture.device, endpoint: .info, body: nil, query: [], isDemo: true,
            writeAuthorized: { true }
        )
        #expect(fixture.model.error?.contains("Demo mode") == true)
        #expect(fixture.state.methods.isEmpty)
    }
}

@MainActor
private final class AuthorizationEligibility {
    var isDemo = false
    var devices: [MinerDevice]
    var now = Date()
    let snapshot: MinerSnapshot

    init(device: MinerDevice) {
        devices = [device]
        snapshot = MinerSnapshot(info: MinerInfo(raw: ["hostname": .string("fixture")]), updatedAt: now)
    }

    func allows(_ device: MinerDevice) -> Bool {
        MinerWriteAvailability.allows(
            snapshot, device: device, currentDevices: devices, isDemo: isDemo, now: now
        )
    }
}

@MainActor
private struct AuthorizationFixture {
    let id = UUID().uuidString
    let device = MinerDevice(name: "Authorization fixture", address: "authorization.invalid")
    let state = AuthorizationHTTPState()
    let session: URLSession
    let model: MinerOperationModel

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthorizationHTTPProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Authorization-Fixture": id]
        session = URLSession(configuration: configuration)
        model = MinerOperationModel(session: session)
        AuthorizationHTTPProtocol.registry.insert(state, id: id)
    }

    func finish() {
        state.releasePreflight()
        session.invalidateAndCancel()
        AuthorizationHTTPProtocol.registry.remove(id: id)
    }
}

private final class AuthorizationHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private var journal: [String] = []
    private var pending: AuthorizationHTTPProtocol?
    private var waiter: CheckedContinuation<Void, Never>?
    private var reachedPreflight = false
    private var released = false

    var methods: [String] { lock.withLock { journal } }

    func receive(_ request: AuthorizationHTTPProtocol) -> Bool {
        let result = lock.withLock { () -> (Bool, CheckedContinuation<Void, Never>?) in
            journal.append(request.request.httpMethod ?? "GET")
            guard request.request.url?.path == "/api/system/info", !released else { return (false, nil) }
            reachedPreflight = true
            pending = request
            let continuation = waiter
            waiter = nil
            return (true, continuation)
        }
        result.1?.resume()
        return result.0
    }

    func waitForPreflight() async {
        await withCheckedContinuation { continuation in
            let reached = lock.withLock {
                if reachedPreflight { return true }
                waiter = continuation
                return false
            }
            if reached { continuation.resume() }
        }
    }

    func releasePreflight() {
        let request = lock.withLock {
            released = true
            defer { pending = nil }
            return pending
        }
        request?.respond()
    }
}

private final class AuthorizationHTTPRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var fixtures: [String: AuthorizationHTTPState] = [:]
    func insert(_ state: AuthorizationHTTPState, id: String) { lock.withLock { fixtures[id] = state } }
    func remove(id: String) { _ = lock.withLock { fixtures.removeValue(forKey: id) } }
    func state(id: String) -> AuthorizationHTTPState? { lock.withLock { fixtures[id] } }
}

private final class AuthorizationHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let registry = AuthorizationHTTPRegistry()
    private let responseLock = NSRecursiveLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let state = Self.registry.state(id: request.value(forHTTPHeaderField: "X-Authorization-Fixture") ?? "") else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        if !state.receive(self) { respond() }
    }

    func respond() {
        responseLock.withLock {
            guard !stopped, let url = request.url,
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else { return }
            stopped = true
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let payload = request.url?.path == "/api/system/info"
                ? #"{"hostname":"fixture","hashRate":1000,"boardVersion":"601a"}"#
                : #"{"ok":true}"#
            client?.urlProtocol(self, didLoad: Data(payload.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() { responseLock.withLock { stopped = true } }
}
