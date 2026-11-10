import Foundation
import Testing
@testable import HashFleetCore

@Suite(.serialized)
struct FleetScheduledCheckTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let id = UUID(uuidString: "a24bf00d-1234-4234-8234-0123456789ab")!
    private func target(_ address: String = "http://192.168.1.10") -> FleetScheduledCheckTarget {
        .init(id: id, name: "Workshop", baseURL: URL(string: address)!, expectedMAC: "02:11:22:33:44:55")
    }
    private func request() -> FleetScheduledCheckRequest {
        .init(deviceID: id, issuedAt: now.timeIntervalSince1970, requestID: "check_123-abc")
    }

    @Test(arguments: ["http://10.1.2.3", "https://10.255.0.1:443/", "http://172.16.0.1:1",
                       "http://172.31.255.254:65535/", "http://192.168.0.1", "https://192.168.255.254/"])
    func permitsCanonicalPrivateIPv4WithOptionalPort(address: String) {
        #expect(FleetScheduledCheckTarget.validBaseURL(URL(string: address)!))
    }

    @Test(arguments: ["http://8.8.8.8", "http://127.0.0.1", "http://169.254.1.1", "http://172.15.1.1",
        "http://172.32.1.1", "http://192.169.1.1", "http://192.168.999.1", "http://10.1.2.256",
        "http://192.168.01.10", "http://3232235786", "http://0xc0a8010a", "http://miner.local",
        "http://example.com", "http://[::1]", "http://[::ffff:192.168.1.10]", "ftp://192.168.1.10",
        "http://192.168.1.10:0", "http://192.168.1.10:65536", "http://192.168.1.10:080",
        "http://user:pass@192.168.1.10", "http://:pass@192.168.1.10", "http://@192.168.1.10",
        "http://192.168.1.10?", "http://192.168.1.10#", "http://192.168.1.10/api/system/restart",
        "http://192.168.1.10/%2F", "http://192.168.1.10.", "http://192.168.1.10:"])
    func rejectsUnsafeOrAmbiguousTargets(address: String) {
        if let url = URL(string: address) { #expect(!FleetScheduledCheckTarget.validBaseURL(url)) }
    }

    @Test func pinsAreStrictAndNamesAreBounded() {
        #expect(FleetScheduledCheckTarget.normalizedMAC("02:ab:cd:12:34:56") == "02ABCD123456")
        #expect(FleetScheduledCheckTarget.normalizedMAC("02-AB-CD-12-34-56") == "02ABCD123456")
        #expect(FleetScheduledCheckTarget.normalizedMAC("02ABCD123456") == "02ABCD123456")
        for value in ["", "garbage02ABCD123456", "02:AB-CD:12:34:56", "00:00:00:00:00:00",
                      "FF:FF:FF:FF:FF:FF", "01:11:22:33:44:55", "02:11:22:33:44:5", "02 11 22 33 44 55"] {
            #expect(FleetScheduledCheckTarget.normalizedMAC(value) == nil)
        }
        #expect(FleetScheduledCheckTarget.safeName("  Work\nshop\0  ") == "Workshop")
        #expect(FleetScheduledCheckTarget.safeName(String(repeating: "a", count: 100)).count == 64)
    }

    @Test func storageIsExplicitlyIsolatedAndFailsClosed() throws {
        let suite = "scheduled-fixture-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FleetScheduledCheckStorage.load(defaults: nil) == .disabled)
        #expect(FleetScheduledCheckStorage.load(defaults: defaults) == .disabled)
        let good = FleetScheduledCheckConfiguration(enabled: true, targets: [target()])
        FleetScheduledCheckStorage.write(good, defaults: defaults)
        #expect(FleetScheduledCheckStorage.load(defaults: defaults) == good)
        let data = try #require(defaults.data(forKey: FleetScheduledCheckStorage.key))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["enabled", "targets"])
        let targets = try #require(object["targets"] as? [[String: Any]])
        #expect(Set(targets[0].keys) == ["id", "name", "baseURL", "expectedMAC"])
        for invalid in [FleetScheduledCheckConfiguration.disabled,
            .init(enabled: true, targets: []), .init(enabled: true, targets: [target(), target()]),
            .init(enabled: true, targets: [target("http://example.com")])] {
            defaults.set(try JSONEncoder().encode(invalid), forKey: FleetScheduledCheckStorage.key)
            #expect(FleetScheduledCheckStorage.load(defaults: defaults) == .disabled)
            FleetScheduledCheckStorage.write(invalid, defaults: defaults)
            #expect(defaults.data(forKey: FleetScheduledCheckStorage.key) == nil)
        }
        defaults.set(Data("not JSON".utf8), forKey: FleetScheduledCheckStorage.key)
        #expect(FleetScheduledCheckStorage.load(defaults: defaults) == .disabled)
        defaults.set(Data(repeating: 32, count: 131_073), forKey: FleetScheduledCheckStorage.key)
        #expect(FleetScheduledCheckStorage.load(defaults: defaults) == .disabled)
        var invalid = target()
        invalid.expectedMAC = "not-a-pin"
        defaults.set(try JSONEncoder().encode(FleetScheduledCheckConfiguration(enabled: true, targets: [invalid])),
                     forKey: FleetScheduledCheckStorage.key)
        #expect(FleetScheduledCheckStorage.load(defaults: defaults) == .disabled)
    }

    @Test func pushRequestStrictlyValidatesVersionTimeIDAndTypes() throws {
        let good: [String: Any] = ["app.hashfleet.deviceID": id.uuidString.lowercased(),
            "app.hashfleet.checkVersion": 1, "app.hashfleet.checkIssuedAt": now.timeIntervalSince1970,
            "app.hashfleet.checkRequestID": "check_123-abc"]
        #expect(FleetScheduledCheckRequest.parse(try JSONSerialization.data(withJSONObject: good), now: now) == request())
        let invalid: [(String, Any)] = [("app.hashfleet.deviceID", "bad"), ("app.hashfleet.deviceID", id.uuidString),
            ("app.hashfleet.checkVersion", 2), ("app.hashfleet.checkVersion", true), ("app.hashfleet.checkVersion", "1"),
            ("app.hashfleet.checkIssuedAt", true), ("app.hashfleet.checkIssuedAt", now.timeIntervalSince1970 - 601),
            ("app.hashfleet.checkIssuedAt", now.timeIntervalSince1970 + 121),
            ("app.hashfleet.checkRequestID", ""), ("app.hashfleet.checkRequestID", "abc\n"),
            ("app.hashfleet.checkRequestID", String(repeating: "x", count: 65))]
        for (key, value) in invalid {
            var object = good
            object[key] = value
            #expect(FleetScheduledCheckRequest.parse(try JSONSerialization.data(withJSONObject: object), now: now) == nil)
        }
        for key in good.keys {
            var object = good
            object.removeValue(forKey: key)
            #expect(FleetScheduledCheckRequest.parse(try JSONSerialization.data(withJSONObject: object), now: now) == nil)
        }
        #expect(FleetScheduledCheckRequest(deviceID: id, issuedAt: .nan, requestID: "x").isValid(now: now) == false)
        #expect(FleetScheduledCheckRequest(deviceID: id, issuedAt: now.timeIntervalSince1970 - 600, requestID: "x").isValid(now: now))
        #expect(FleetScheduledCheckRequest(deviceID: id, issuedAt: now.timeIntervalSince1970 + 120, requestID: "x").isValid(now: now))
    }

    @Test func fixedGETReadsOnlyAllowlistedFreshMetrics() async throws {
        let fixture = CheckHTTPFixture(body: Data((
            #"{"macAddr":"02:11:22:33:44:55","hashRate":2500,"temp":51.2,"power":42,"#
                + #""sharesAccepted":15,"sharesRejected":1,"stratumUser":"PRIVATE_WALLET","#
                + #""stratumPassword":"PRIVATE_PASSWORD","wifiPassword":"PRIVATE_WIFI"}"#
        ).utf8))
        defer { fixture.close() }
        let reading = try await fixture.reader.read(target(fixture.address))
        #expect(reading.hashRateGHs == 2500)
        #expect(reading.temperatureC == 51.2)
        #expect(reading.body.contains("2.50 TH/s"))
        #expect(reading.body.contains("15 accepted shares"))
        #expect(!reading.body.contains("PRIVATE"))
        let sent = try #require(fixture.requests.first)
        #expect(fixture.requests.count == 1)
        #expect(sent.url?.path == "/api/system/info")
        #expect(sent.url?.query == nil)
        #expect(sent.httpMethod == "GET")
        #expect(sent.httpBody == nil)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func missingMalformedAndMismatchedIdentityNeverProducesReading() async {
        for body in [#"{"hashRate":2000}"#, #"{"macAddr":"02:11:22:33:44:66","hashRate":2000}"#,
            #"{"macAddr":"garbage02ABCD123456","hashRate":2000}"#,
            #"{"macAddr":"02:11:22:33:44:55","mac":"02:11:22:33:44:66"}"#,
            #"{"macAddr":true}"#, "[]", "not JSON"] {
            let fixture = CheckHTTPFixture(body: Data(body.utf8))
            defer { fixture.close() }
            await #expect(throws: (any Error).self) { try await fixture.reader.read(target(fixture.address)) }
        }
    }

    @Test func missingAndInvalidMetricsStayUnavailableNotZero() throws {
        let body = Data(#"{"macAddr":"02:11:22:33:44:55","hashRate":true,"temp":999,"power":"NaN","sharesAccepted":-1,"sharesRejected":1.5}"#.utf8)
        let reading = try FleetScheduledCheckReader.decode(body, expectedMAC: "021122334455")
        #expect(reading == FleetScheduledCheckReading())
        #expect(!reading.body.contains("0.0"))
        let unsafe = FleetScheduledCheckReading(hashRateGHs: .infinity, temperatureC: .nan, powerW: -1, sharesAccepted: .max)
        #expect(unsafe == FleetScheduledCheckReading())
        let zero = try FleetScheduledCheckReader.decode(Data(#"{"mac":"02-11-22-33-44-55","hashRate":0,"temp":"0","power":0}"#.utf8), expectedMAC: "021122334455")
        #expect(zero.hashRateGHs == 0)
        #expect(zero.temperatureC == 0)
        #expect(zero.powerW == 0)
    }

    @Test func httpErrorsRedirectsOversizedBodiesAndDeadlinesFailSafely() async {
        for status in [301, 302, 307, 401, 404, 500] {
            let fixture = CheckHTTPFixture(status: status, body: Data(#"{"macAddr":"02:11:22:33:44:55"}"#.utf8))
            defer { fixture.close() }
            await #expect(throws: (any Error).self) { try await fixture.reader.read(target(fixture.address)) }
            #expect(fixture.requests.count == 1)
        }
        for length in [nil, "131073"] as [String?] {
            let fixture = CheckHTTPFixture(body: Data(repeating: 32, count: 131_073), contentLength: length)
            defer { fixture.close() }
            await #expect(throws: FleetScheduledCheckReadError.tooLarge) { try await fixture.reader.read(target(fixture.address)) }
        }
        let timeout = CheckHTTPFixture(error: URLError(.timedOut))
        defer { timeout.close() }
        await #expect(throws: URLError.self) { try await timeout.reader.read(target(timeout.address)) }
    }

    @Test func defaultTransportIsEphemeralBoundedAndHasNoPersistenceOrProxy() {
        let c = FleetScheduledCheckReader.configuration()
        #expect(c.urlCache == nil)
        #expect(c.httpCookieStorage == nil)
        #expect(c.httpShouldSetCookies == false)
        #expect(c.urlCredentialStorage == nil)
        #expect(c.connectionProxyDictionary?.isEmpty == true)
        #expect(c.timeoutIntervalForRequest == 8)
        #expect(c.timeoutIntervalForResource == 12)
        #expect(c.waitsForConnectivity == false)
    }

    @Test func optOutRemovalReplacementAndCancellationAreRecheckedAfterIO() async {
        let original = FleetScheduledCheckConfiguration(enabled: true, targets: [target()])
        let state = CheckState(original)
        let fixedNow = now
        let req = request()
        let fresh = await FleetScheduledCheckRunner.perform(request: req, configuration: { state.value }, now: { fixedNow },
            read: { _ in .init(hashRateGHs: 2000) })
        #expect(fresh.title == "Workshop")
        #expect(fresh.body.contains("2.00 TH/s"))
        var replacement = target()
        replacement.expectedMAC = "02:11:22:33:44:66"
        for changed in [FleetScheduledCheckConfiguration.disabled, .init(enabled: true, targets: []),
                        .init(enabled: true, targets: [replacement])] {
            state.value = original
            let result = await FleetScheduledCheckRunner.perform(request: req, configuration: { state.value }, now: { fixedNow }, read: { _ in
                state.value = changed
                return .init(hashRateGHs: 2000)
            })
            #expect(result == .unavailable)
        }
        state.value = .disabled
        let denied = await FleetScheduledCheckRunner.perform(request: req, configuration: { state.value }, now: { fixedNow }, read: { _ in
            Issue.record("Disabled configuration attempted network I/O")
            return .init()
        })
        #expect(denied == .unavailable)
        state.value = original
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await FleetScheduledCheckRunner.perform(request: req, configuration: { state.value }, now: { fixedNow }, read: { _ in
                Issue.record("Cancelled operation attempted network I/O")
                return .init()
            })
        }
        #expect(await task.value == .unavailable)
    }

    private func fleet() -> [FleetScheduledCheckTarget] {
        [("a24bf00d-1234-4234-8234-0123456789ab", "Naja", "http://192.168.1.10", "02:11:22:33:44:01"),
         ("b24bf00d-1234-4234-8234-0123456789ab", "Naja 2", "http://192.168.1.11", "02:11:22:33:44:02"),
         ("c24bf00d-1234-4234-8234-0123456789ab", "Gamma", "http://192.168.1.12", "02:11:22:33:44:03"),
         ("d24bf00d-1234-4234-8234-0123456789ab", "Gamma 2", "http://192.168.1.13", "02:11:22:33:44:04")]
            .map { .init(id: UUID(uuidString: $0.0)!, name: $0.1, baseURL: URL(string: $0.2)!, expectedMAC: $0.3) }
    }

    private func batchPayload(_ ids: [UUID], primary: UUID? = nil) -> Data {
        (try? JSONSerialization.data(withJSONObject: [
            "app.hashfleet.deviceID": (primary ?? ids[0]).uuidString.lowercased(),
            "app.hashfleet.deviceIDs": ids.map { $0.uuidString.lowercased() },
            "app.hashfleet.checkVersion": 1, "app.hashfleet.checkIssuedAt": now.timeIntervalSince1970,
            "app.hashfleet.checkRequestID": "check_123-abc"])) ?? Data()
    }

    @Test func batchPushParsesEveryListedMinerAndRejectsMalformedLists() throws {
        let ids = fleet().map(\.id)
        let parsed = try #require(FleetScheduledCheckRequest.parse(batchPayload(ids), now: now))
        #expect(parsed.deviceIDs == ids && parsed.deviceID == ids[0])
        // Older single-miner pushes still parse as a one-miner list.
        let single = try #require(FleetScheduledCheckRequest.parse(try JSONSerialization.data(withJSONObject: [
            "app.hashfleet.deviceID": ids[0].uuidString.lowercased(), "app.hashfleet.checkVersion": 1,
            "app.hashfleet.checkIssuedAt": now.timeIntervalSince1970, "app.hashfleet.checkRequestID": "x"]), now: now))
        #expect(single.deviceIDs == [ids[0]])
        #expect(FleetScheduledCheckRequest.parse(batchPayload([ids[0], ids[0]]), now: now) == nil)
        #expect(FleetScheduledCheckRequest.parse(batchPayload([ids[1]], primary: ids[0]), now: now) == nil)
        #expect(FleetScheduledCheckRequest.parse(batchPayload((0..<65).map { _ in UUID() }), now: now) == nil)
    }

    @Test func batchRendersEveryMinerInOneNotificationAndMarksFailures() async {
        let targets = fleet()
        let config = FleetScheduledCheckConfiguration(enabled: true, targets: targets)
        let fixedNow = now
        let req = FleetScheduledCheckRequest(deviceID: targets[0].id, deviceIDs: targets.map(\.id),
            issuedAt: now.timeIntervalSince1970, requestID: "check_123-abc")
        let unreachable = targets[3].id
        let result = await FleetScheduledCheckRunner.perform(request: req, configuration: { config }, now: { fixedNow }, read: { target in
            if target.id == unreachable { throw URLError(.timedOut) }
            return .init(hashRateGHs: target.name.hasPrefix("Naja") ? 9400 : 1100, temperatureC: 47.4, powerW: 121.4)
        })
        #expect(result.title == "Fleet 19.90 TH/s · 3/4 online")
        #expect(result.body == """
            Naja: 9.40 TH/s · 47 °C · 121 W
            Naja 2: 9.40 TH/s · 47 °C · 121 W
            Gamma: 1.10 TH/s · 47 °C · 121 W
            Gamma 2: unreachable
            """)
    }

    @Test func batchSkipsMinersRemovedDuringIOAndFailsClosedWhenNothingRemains() async {
        let targets = fleet()
        let state = CheckState(.init(enabled: true, targets: targets))
        let fixedNow = now
        let req = FleetScheduledCheckRequest(deviceID: targets[0].id, deviceIDs: targets.map(\.id),
            issuedAt: now.timeIntervalSince1970, requestID: "check_123-abc")
        let trimmed = await FleetScheduledCheckRunner.perform(request: req, configuration: { state.value }, now: { fixedNow }, read: { _ in
            state.value = .init(enabled: true, targets: Array(targets.prefix(2)))
            return .init(hashRateGHs: 1000)
        })
        #expect(trimmed.body.split(separator: "\n").count == 2)
        state.value = .init(enabled: true, targets: targets)
        let gone = await FleetScheduledCheckRunner.perform(request: req, configuration: { state.value }, now: { fixedNow }, read: { _ in
            state.value = .disabled
            return .init(hashRateGHs: 1000)
        })
        #expect(gone == .unavailable)
        let none = await FleetScheduledCheckRunner.perform(request: req, configuration: { state.value }, now: { fixedNow }, read: { _ in
            Issue.record("Disabled configuration attempted network I/O")
            return .init()
        })
        #expect(none == .unavailable)
        state.value = .init(enabled: true, targets: targets)
        let allDown = await FleetScheduledCheckRunner.perform(request: req, configuration: { state.value }, now: { fixedNow }, read: { _ in
            throw URLError(.cannotConnectToHost)
        })
        #expect(allDown.title == "Fleet check: miners unreachable" && allDown.body.split(separator: "\n").count == 4)
    }
}

/// All fixture state is lock protected. URLProtocol intercepts every request, so no test can reach a miner.
private final class CheckState: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: FleetScheduledCheckConfiguration
    init(_ value: FleetScheduledCheckConfiguration) { stored = value }
    var value: FleetScheduledCheckConfiguration {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private final class CheckHTTPFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    let address: String
    let reader: FleetScheduledCheckReader
    private let session: URLSession
    private let port: Int
    init(status: Int = 200, body: Data = Data(), contentLength: String? = nil, error: URLError? = nil) {
        port = Int.random(in: 10000...65000)
        address = "http://192.168.1.10:\(port)"
        let c = FleetScheduledCheckReader.configuration()
        c.protocolClasses = [CheckURLProtocol.self]
        session = URLSession(configuration: c)
        reader = FleetScheduledCheckReader(session: session)
        CheckURLProtocol.registry.set(port: port) { [weak self] request in
            self?.lock.withLock { self?.recorded.append(request) }
            if let error { throw error }
            let headers = contentLength.map { ["Content-Length": $0] }
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, body)
        }
    }
    var requests: [URLRequest] { lock.withLock { recorded } }
    func close() { session.invalidateAndCancel(); CheckURLProtocol.registry.set(port: port, handler: nil) }
    deinit { close() }
}
private final class CheckRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)
    private let lock = NSLock()
    private var handlers: [Int: Handler] = [:]
    func set(port: Int, handler: Handler?) { lock.withLock { handlers[port] = handler } }
    func get(port: Int) -> Handler? { lock.withLock { handlers[port] } }
}
private final class CheckURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = CheckRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let port = request.url?.port, let handler = Self.registry.get(port: port) else { throw URLError(.unsupportedURL) }
            let (response, body) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
