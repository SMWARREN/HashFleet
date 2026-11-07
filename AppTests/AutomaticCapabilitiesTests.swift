import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized) @MainActor
struct AutomaticCapabilitiesTests {
    @Test
    func autoDetectReusesObservedInfoAndPerformsExactlyOneASICRead() async throws {
        let fixture = StoreFixture { request in
            if request.url?.path == "/api/system/asic" {
                return try storeResponse(body: Data(#"{"deviceModel":"BitaxeMax","ASICModel":"BM1397"}"#.utf8))
            }
            return try storeResponse(status: 404, body: Data())
        }
        let capabilities = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "Rig1", address: fixture.host)
        let observedInfo = MinerInfo(raw: [
            "hostname": .string("rig1"),
            "version": .string("2.1.0"),
            "ASICModel": .string("BM1397"),
            "boardVersion": .string("204")
        ])

        await capabilities.autoDetect(device: device, observedInfo: observedInfo, isDemo: false)

        #expect(fixture.requestCount == 1)
        let report = capabilities.reports[device.id]
        #expect(report != nil)
        #expect(report?.infoStatus == .supported)
        #expect(report?.asicStatus == .supported)
        #expect(report?.info?.hostname == "rig1")
        #expect(report?.asic?["deviceModel"]?.stringValue == "BitaxeMax")
        #expect(capabilities.checking.isEmpty)
    }

    @Test
    func autoDetectRunsOnlyOncePerDeviceIdentity() async throws {
        let fixture = StoreFixture { request in
            if request.url?.path == "/api/system/asic" {
                return try storeResponse(body: Data(#"{"ASICModel":"BM1397"}"#.utf8))
            }
            return try storeResponse(status: 404, body: Data())
        }
        let capabilities = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "Rig2", address: fixture.host)
        let info1 = MinerInfo(raw: [
            "hostname": .string("rig2"),
            "version": .string("2.1.0"),
            "ASICModel": .string("BM1397")
        ])

        // First detection triggers ASIC probe
        await capabilities.autoDetect(device: device, observedInfo: info1, isDemo: false)
        #expect(fixture.requestCount == 1)

        // Subsequent calls with the same identity (even if non-identity fields change) do not probe again
        let info2 = MinerInfo(raw: [
            "hostname": .string("rig2-renamed"),
            "version": .string("2.1.0"),
            "ASICModel": .string("BM1397"),
            "hashRate": .number(450)
        ])
        await capabilities.autoDetect(device: device, observedInfo: info2, isDemo: false)
        #expect(fixture.requestCount == 1)
        #expect(
            capabilities.reports[device.id]?.info?.hostname == "rig2",
            "Dated check snapshots must not silently become live telemetry"
        )
    }

    @Test
    func autoDetectProbesAgainWhenIdentityChanges() async throws {
        let fixture = StoreFixture { request in
            if request.url?.path == "/api/system/asic" {
                return try storeResponse(body: Data(#"{"ASICModel":"BM1397"}"#.utf8))
            }
            return try storeResponse(status: 404, body: Data())
        }
        let capabilities = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "Rig3", address: fixture.host)
        let infoV1 = MinerInfo(raw: [
            "hostname": .string("rig3"),
            "version": .string("2.1.0"),
            "ASICModel": .string("BM1397")
        ])
        await capabilities.autoDetect(device: device, observedInfo: infoV1, isDemo: false)
        #expect(fixture.requestCount == 1)

        // Firmware upgrade changes version -> triggers new probe
        let infoV2 = MinerInfo(raw: [
            "hostname": .string("rig3"),
            "version": .string("2.2.0"),
            "ASICModel": .string("BM1397")
        ])
        await capabilities.autoDetect(device: device, observedInfo: infoV2, isDemo: false)
        #expect(fixture.requestCount == 2)
    }

    @Test
    func failureBacksOffUntilExplicitRetryOrIdentityChange() async throws {
        let fixture = StoreFixture { request in
            if request.url?.path == "/api/system/asic" {
                return try storeResponse(status: 500, body: Data(#"{"error":"internal"}"#.utf8))
            }
            return try storeResponse(status: 404, body: Data())
        }
        let capabilities = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "Failing", address: fixture.host)
        let info = MinerInfo(raw: [
            "hostname": .string("rig-fail"),
            "version": .string("2.1.0"),
            "ASICModel": .string("BM1397")
        ])

        await capabilities.autoDetect(device: device, observedInfo: info, isDemo: false)
        #expect(fixture.requestCount == 1)
        #expect(capabilities.reports[device.id]?.asicStatus.isFailed == true)

        // Subsequent auto-poll on the same identity does not re-probe
        await capabilities.autoDetect(device: device, observedInfo: info, isDemo: false)
        #expect(fixture.requestCount == 1)
    }

    @Test
    func demoModeNeverPerformsAutoDetectionOrNetwork() async throws {
        let fixture = StoreFixture { _ in
            Issue.record("Demo mode performed network I/O during autoDetect")
            return try storeResponse(status: 500, body: Data())
        }
        let capabilities = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "DemoAxe", address: fixture.host)
        let info = MinerInfo(raw: [
            "hostname": .string("demo"),
            "version": .string("2.1.0"),
            "ASICModel": .string("BM1397")
        ])

        await capabilities.autoDetect(device: device, observedInfo: info, isDemo: true)
        #expect(fixture.requestCount == 0)
        #expect(capabilities.reports.isEmpty)
    }

    @Test
    func invalidInfoShapeDoesNotTriggerDetection() async throws {
        let fixture = StoreFixture { _ in
            Issue.record("Invalid info shape performed network I/O during autoDetect")
            return try storeResponse(status: 500, body: Data())
        }
        let capabilities = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "Unrecognized", address: fixture.host)
        // Empty or non-ESP-Miner info shape
        let invalidInfo = MinerInfo(raw: ["unrelatedKey": .string("hello")])

        await capabilities.autoDetect(device: device, observedInfo: invalidInfo, isDemo: false)
        #expect(fixture.requestCount == 0)
        #expect(capabilities.reports.isEmpty)
    }

    @Test
    func removalAndResetCleanlyClearAutoDetectedReportsAndIdentities() async throws {
        let fixture = StoreFixture { _ in
            try storeResponse(body: Data(#"{"ASICModel":"BM1397"}"#.utf8))
        }
        let capabilities = MinerCapabilitiesStore(session: fixture.session)
        let d1 = MinerDevice(name: "D1", address: fixture.host)
        let d2 = MinerDevice(name: "D2", address: fixture.host)
        let info = MinerInfo(raw: ["hostname": .string("rig"), "version": .string("1.0")])

        await capabilities.autoDetect(device: d1, observedInfo: info, isDemo: false)
        await capabilities.autoDetect(device: d2, observedInfo: info, isDemo: false)
        #expect(capabilities.reports.count == 2)

        capabilities.remove(d1.id)
        #expect(capabilities.reports[d1.id] == nil)
        #expect(capabilities.probedIdentities[d1.id] == nil)
        #expect(capabilities.reports[d2.id] != nil)

        capabilities.reset()
        #expect(capabilities.reports.isEmpty)
        #expect(capabilities.probedIdentities.isEmpty)
        #expect(capabilities.failedIdentities.isEmpty)
    }

    @Test
    func taskCancellationRejectsLateAutoDetectReport() async throws {
        let fixture = StoreFixture(delayed: true) { _ in
            try storeResponse(body: Data(#"{"ASICModel":"BM1397"}"#.utf8))
        }
        let capabilities = MinerCapabilitiesStore(session: fixture.session)
        let device = MinerDevice(name: "SlowAuto", address: fixture.host)
        let info = MinerInfo(raw: ["hostname": .string("rig"), "version": .string("1.0")])

        let task = Task {
            await capabilities.autoDetect(device: device, observedInfo: info, isDemo: false)
        }
        try await fixture.waitForRequest()
        #expect(capabilities.checking.contains(device.id))
        task.cancel()
        await task.value

        #expect(capabilities.reports[device.id] == nil)
        #expect(capabilities.checking.isEmpty)
    }
}

private final class StoreFixture: @unchecked Sendable {
    let host: String
    let session: URLSession
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    init(
        delayed: Bool = false,
        handler: @escaping @Sendable (URLRequest) throws -> (URLResponse, Data)
    ) {
        host = "auto-cap-\(UUID().uuidString.lowercased()).invalid"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutoCapURLProtocol.self]
        session = URLSession(configuration: configuration)
        AutoCapURLProtocol.registry.set(
            { [weak self] request in
                self?.increment()
                return try handler(request)
            },
            for: host
        )
        if delayed { AutoCapURLProtocol.registry.setDelayed(host, value: true) }
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func waitForRequest() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if requestCount > 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.timedOut)
    }

    deinit {
        session.invalidateAndCancel()
        AutoCapURLProtocol.registry.setDelayed(host, value: false)
        AutoCapURLProtocol.registry.set(nil, for: host)
    }
}

private class AutoCapURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = AutoCapRegistry()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host,
            let handler = Self.registry.handler(for: host)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if Self.registry.isDelayed(host) {
            _ = try? handler(request)
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

private final class AutoCapRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    private var delayedHosts: Set<String> = []

    func set(_ handler: Handler?, for host: String) {
        lock.lock()
        handlers[host] = handler
        lock.unlock()
    }

    func setDelayed(_ host: String, value: Bool) {
        lock.lock()
        if value { delayedHosts.insert(host) } else { delayedHosts.remove(host) }
        lock.unlock()
    }

    func isDelayed(_ host: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return delayedHosts.contains(host)
    }

    func handler(for host: String) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[host]
    }
}

private func storeResponse(status: Int = 200, body: Data) throws -> (URLResponse, Data) {
    let url = URL(string: "http://fixture.invalid")!
    return (HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, body)
}
