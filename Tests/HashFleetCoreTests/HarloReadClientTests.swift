import Foundation
import Testing
@testable import HashFleetCore

// Synthetic transport fixtures ONLY, never responses captured from Harlo firmware. Fields
// beginning with fixture_ are intentionally invented to test client-side evidence rules.
@Suite("Harlo synthetic read contract")
struct HarloReadClientTests {
    private let marker = "SYNTHETIC_PRIVATE_DO_NOT_RENDER"

    private var fullProfile: HarloInfoProfile {
        get throws {
            let identity = try HarloInfoProfile.Field(keys: ["fixture_family"], equals: .string("offline-test"))
            let ads = try Dictionary(uniqueKeysWithValues: HarloReadEndpoint.allCases.filter { $0 != .info }.map {
                ($0, try HarloInfoProfile.Field(keys: ["fixture_advertises", $0.rawValue], equals: .bool(true)))
            })
            return try HarloInfoProfile(identity: [identity], advertisements: ads)
        }
    }

    private let info = #"{"fixture_family":"offline-test","fixture_advertises":{"network":true,"pools":true,"telemetry":true,"fleet":true,"logs":true}}"#

    @Test func closedCatalogNoRequestsUntilExplicitReads() throws {
        #expect(HarloReadEndpoint.allCases.map(\.path) == ["/api/info", "/api/telemetry", "/api/network", "/api/pools", "/api/fleet", "/api/logs"])
        let fixture = try SyntheticHarloFixture { _, _ in throw URLError(.unsupportedURL) }
        #expect(fixture.record.count == 0)
        for value in ["", "file:///tmp", "http://user:SECRET@example.invalid", "http://example.invalid/api",
                      "a.invalid?", "a.invalid#", "a.invalid:", "a.invalid:65536", "a.invalid%2fescape",
                      "a.invalid\\other", " https://a.invalid", "http://[::not-an-ip]"] {
            #expect(throws: HarloReadError.invalidAddress) { try HarloReadClient(baseURL: value) }
        }
        _ = try HarloReadClient(baseURL: "https://[::1]:12345/") // parse only
    }

    @Test func validatesBoundsAndDisablesImplicitCredentialsAndProxies() throws {
        let policy = try HarloReadPolicy(timeout: 4)
        let config = HarloReadClient.configuration(policy: policy)
        #expect(config.timeoutIntervalForRequest == 4 && config.timeoutIntervalForResource == 4)
        #expect(config.urlCredentialStorage == nil && config.httpCookieStorage == nil && config.urlCache == nil)
        #expect(!config.httpShouldSetCookies && !config.waitsForConnectivity)
        for key in ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable"] {
            #expect(config.connectionProxyDictionary?[key] as? Int == 0)
        }
        #expect(throws: HarloReadError.invalidPolicy) { try HarloReadPolicy(timeout: .nan) }
        #expect(throws: HarloReadError.invalidPolicy) { try HarloReadPolicy(retries: 3) }
        #expect(throws: HarloReadError.invalidPolicy) { try HarloReadPolicy(minimumInterval: 0) }
        #expect(throws: HarloReadError.invalidPolicy) { try HarloReadPolicy(maximumBytes: 0) }
        #expect(throws: HarloReadError.invalidPolicy) { try HarloInfoProfile(identity: [], advertisements: [:]) }
        #expect(throws: HarloReadError.invalidPolicy) { try HarloInfoProfile.Field(keys: [], equals: .bool(true)) }
        #expect(throws: HarloReadError.invalidPolicy) { try HarloInfoProfile.Field(keys: ["x"], equals: .null) }
    }

    @Test func noProfileNeverInfersIdentityOrProbesOptionalRoutes() async throws {
        let fixture = try SyntheticHarloFixture { req, _ in try stubResponse(for: req, data: Data(info.utf8)) }
        #expect(try await fixture.client.read(.info) == .info(identity: .unconfirmed, advertised: []))
        for endpoint in HarloReadEndpoint.allCases where endpoint != .info {
            await #expect(throws: HarloReadError.notAdvertised) { try await fixture.client.read(endpoint) }
        }
        #expect(fixture.record.count == 1)
    }

    @Test func allSixGETsProjectOnlyAllowlistedDataAndNeverChaseFleetChildren() async throws {
        let fixture = try SyntheticHarloFixture(profile: fullProfile) { req, _ in
            let url = try #require(req.url)
            #expect(url.port == 9443 && url.scheme == "https" && url.query == nil && url.fragment == nil)
            #expect(req.httpMethod == "GET" && req.httpBody == nil && req.httpBodyStream == nil)
            #expect(req.value(forHTTPHeaderField: "Authorization") == nil && req.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(req.timeoutInterval == 4 && !req.httpShouldHandleCookies)
            let data: String
            switch url.path {
            case "/api/info": data = info
            case "/api/telemetry": data = "{\"hashrate_ghs\":0,\"device_power_w\":17.5,\"asic_temp_c\":\"\(marker)\",\"other\":[{\"\(marker)\":42}]}"
            case "/api/network": data = "{\"interfaces\":[{\"ssid\":\"\(marker)\"}]}"
            case "/api/pools": data = "{\"pools\":[{\"url\":\"\(marker)\",\"pw\":\"\(marker)\"},{}]}"
            case "/api/fleet": data = "{\"devices\":[{\"ip\":\"child.invalid\",\"name\":\"\(marker)\"}]}"
            case "/api/logs": data = "RAW LOGS: \(marker)\n\(marker)"
            default: throw URLError(.unsupportedURL)
            }
            return try stubResponse(for: req, data: Data(data.utf8))
        }
        await #expect(throws: HarloReadError.notAdvertised) { try await fixture.client.read(.fleet) }
        let advertised = Set(HarloReadEndpoint.allCases.filter { $0 != .info })
        let expected: [HarloReadResult] = [.info(identity: .matchesConfiguredProfile, advertised: advertised),
            .telemetry(hashrateGHs: 0, powerW: 17.5, asicTemperatureC: nil), .network(interfaceCount: 1),
            .pools(entryCount: 2), .fleet(reportedEntryCount: 1), .logsWithheld]
        for (endpoint, value) in zip(HarloReadEndpoint.allCases, expected) {
            let result = try await fixture.client.read(endpoint)
            #expect(result == value)
            #expect(!String(reflecting: result).contains(marker))
        }
        #expect(fixture.record.count == 6)
    }

    @Test func malformedInfoErrorsAndChangedAdvertisementsRevokeEvidence() async throws {
        let fixture = try SyntheticHarloFixture(profile: fullProfile) { req, index in
            let body = switch index {
            case 1: #"{"fixture_family":"offline-test","fixture_advertises":{"logs":"true","pools":true}}"#
            case 2: "untrusted html"
            case 3: info
            default: marker
            }
            return try stubResponse(for: req, status: index == 4 ? 403 : 200, data: Data(body.utf8))
        }
        #expect(try await fixture.client.read(.info) == .info(identity: .matchesConfiguredProfile, advertised: [.pools]))
        await #expect(throws: HarloReadError.notAdvertised) { try await fixture.client.read(.logs) }
        #expect(try await fixture.client.read(.info) == .info(identity: .unconfirmed, advertised: []))
        await #expect(throws: HarloReadError.notAdvertised) { try await fixture.client.read(.pools) }
        _ = try await fixture.client.read(.info)
        await #expect(throws: HarloReadError.http(403)) { try await fixture.client.read(.info) }
        await #expect(throws: HarloReadError.notAdvertised) { try await fixture.client.read(.pools) }
        #expect(fixture.record.count == 4)
    }

    @Test func unknownShapesNeverLeakKeysOrValues() {
        for data in [Data(marker.utf8), Data("{\"\(marker)\":[\"\(marker)\"]}".utf8), Data([0, 255])] {
            for endpoint in HarloReadEndpoint.allCases {
                let result = HarloReadResult.project(endpoint, body: data, profile: nil)
                #expect(!String(reflecting: result).contains(marker))
            }
        }
        #expect(HarloReadResult.project(.telemetry, body: Data(#"{"hashrate_ghs":false}"#.utf8), profile: nil)
                == .telemetry(hashrateGHs: nil, powerW: nil, asicTemperatureC: nil))
        #expect(HarloReadResult.project(.fleet, body: Data(#"{"devices":"secret"}"#.utf8), profile: nil)
                == .fleet(reportedEntryCount: nil))
    }

    @Test func narrowlyRetriesTransportErrorsAndPacesAttempts() async throws {
        let fixture = try SyntheticHarloFixture(retries: 2) { req, index in
            if index == 1 { throw URLError(.timedOut) }
            if index == 2 { throw URLError(.networkConnectionLost) }
            return try stubResponse(for: req)
        }
        let start = ContinuousClock.now
        #expect(try await fixture.client.read(.info) == .info(identity: .unconfirmed, advertised: []))
        #expect(start.duration(to: .now) >= .milliseconds(195))
        #expect(fixture.record.count == 3)
        let fails = try SyntheticHarloFixture(retries: 1) { _, _ in throw URLError(.timedOut) }
        await #expect(throws: HarloReadError.timeout) { try await fails.client.read(.info) }
        #expect(fails.record.count == 2)
    }

    @Test func terminalFailuresNeverExposeDeviceOrTransportDetails() async throws {
        for status in [301, 307, 401, 404, 429, 503] {
            let fixture = try SyntheticHarloFixture(retries: 2) { req, _ in
                try stubResponse(for: req, status: status, data: Data(marker.utf8), headers: ["Location": "https://other.invalid/\(marker)"])
            }
            await #expect(throws: HarloReadError.http(status)) { try await fixture.client.read(.info) }
            #expect(fixture.record.count == 1)
        }
        let fixture = try SyntheticHarloFixture(retries: 2) { _, _ in
            throw NSError(domain: "private", code: 3, userInfo: [NSLocalizedDescriptionKey: marker])
        }
        await #expect(throws: HarloReadError.transport) { try await fixture.client.read(.info) }
        #expect(fixture.record.count == 1)
    }

    @Test func serverCooldownAndRouteWithdrawalAvoidExtraTraffic() async throws {
        let limited = try SyntheticHarloFixture { req, _ in
            try stubResponse(for: req, status: 429, headers: ["Retry-After": "90"])
        }
        await #expect(throws: HarloReadError.http(429)) { try await limited.client.read(.info) }
        await #expect(throws: HarloReadError.rateLimited) { try await limited.client.read(.info) }
        #expect(limited.record.count == 1)
        let epoch = Date(timeIntervalSince1970: 0)
        #expect(HarloReadClient.cooldownEnd("Thu, 01 Jan 1970 00:01:30 GMT", now: epoch) == epoch.addingTimeInterval(90))
        #expect(HarloReadClient.cooldownEnd("unrecognized", now: epoch) == epoch.addingTimeInterval(60))
        #expect(HarloReadClient.cooldownEnd(String(repeating: "9", count: 50), now: epoch) == .distantFuture)
        let missing = try SyntheticHarloFixture(profile: fullProfile) { req, i in
            try stubResponse(for: req, status: i == 1 ? 200 : 404, data: Data(info.utf8))
        }
        _ = try await missing.client.read(.info)
        await #expect(throws: HarloReadError.http(404)) { try await missing.client.read(.fleet) }
        await #expect(throws: HarloReadError.notAdvertised) { try await missing.client.read(.fleet) }
        #expect(missing.record.count == 2)
    }

    @Test func unsolicitedOriginOrNonHTTPResponseIsRejected() async throws {
        let fixture = try SyntheticHarloFixture { _, _ in
            let url = try #require(URL(string: "https://elsewhere.invalid/api/info"))
            return (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)), Data(info.utf8))
        }
        await #expect(throws: HarloReadError.invalidResponse) { try await fixture.client.read(.info) }
        let other = try SyntheticHarloFixture { req, _ in
            (URLResponse(url: try #require(req.url), mimeType: nil, expectedContentLength: 0, textEncodingName: nil), Data())
        }
        await #expect(throws: HarloReadError.invalidResponse) { try await other.client.read(.info) }
    }

    @Test func actualAndAnnouncedLengthsAreBounded() async throws {
        for headers in [["Content-Length": "1000"], [:]] {
            let fixture = try SyntheticHarloFixture(maximumBytes: 4) { req, _ in
                try stubResponse(for: req, data: Data("12345".utf8), headers: headers)
            }
            await #expect(throws: HarloReadError.tooLarge) { try await fixture.client.read(.info) }
        }
        let exact = try SyntheticHarloFixture(maximumBytes: 4) { req, _ in
            try stubResponse(for: req, data: Data("1234".utf8))
        }
        _ = try await exact.client.read(.info)
    }

    @Test func concurrentReadAndCancellationDoNotQueueMoreTraffic() async throws {
        let fixture = try SyntheticHarloFixture(retries: 2, minimumInterval: 1) { _, _ in throw URLError(.timedOut) }
        let first = Task { try await fixture.client.read(.info) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while fixture.record.count == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(fixture.record.count == 1)
        await #expect(throws: HarloReadError.rateLimited) { try await fixture.client.read(.info) }
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(fixture.record.count == 1)
    }
}

// Reductions from original Harlo firmware run under esp-emu, NOT synthetic firmware responses.
// See Tools/virtual-miners/evidence/harlo-gamma601.md, receipts 21954476pb and 30116217jw.
// Tests replay only the non-sensitive fields required here. Empty entry objects below mean
// ALL entry members were removed, not that the original objects were empty. This test suite
// does not boot firmware, contact a miner, or claim that a route is necessarily advertised.
@Suite("Harlo reduced original-firmware captures")
struct HarloCapturedContractTests {
    private static let info = #"""
        {"firmware":"Harlo-OS-V2","version":"0.2.101","fleet_api_version":1,
         "profile":{"id":"bitaxe-gamma-601","name":"Bitaxe Gamma 601","display_supported":true}}
        """#
    private static let fleet = #"{"devices":[]}"#

    @Test func capturedOptInIdentityAdvertisesOnlyFleetAndDoesNotProbeOtherRoutes() async throws {
        let fixture = try SyntheticHarloFixture(profile: .gamma601V02101) { request, _ in
            switch request.url?.path {
            case "/api/info": return try stubResponse(for: request, data: Data(Self.info.utf8))
            case "/api/fleet": return try stubResponse(for: request, data: Data(Self.fleet.utf8))
            default: throw URLError(.unsupportedURL)
            }
        }
        #expect(try await fixture.client.read(.info) == .info(identity: .matchesConfiguredProfile, advertised: [.fleet]))
        #expect(try await fixture.client.read(.fleet) == .fleet(reportedEntryCount: 0))
        for endpoint: HarloReadEndpoint in [.telemetry, .network, .pools, .logs] {
            await #expect(throws: HarloReadError.notAdvertised) { try await fixture.client.read(endpoint) }
        }
        #expect(fixture.record.count == 2)
        #expect(HarloReadResult.project(.info, body: Data(Self.info.utf8), profile: nil) == .info(identity: .unconfirmed, advertised: []))
    }

    @Test func capturedShapesPreserveMissingMeasurementsAndWithholdContents() {
        let reductions: [(HarloReadEndpoint, String, HarloReadResult)] = [
            (.telemetry, #"{"hashrate_ghs":null,"device_power_w":null,"asic_temp_c":null}"#, .telemetry(hashrateGHs: nil, powerW: nil, asicTemperatureC: nil)),
            (.network, #"{"interfaces":[{},{},{}]}"#, .network(interfaceCount: 3)),
            (.pools, #"{"pools":[{},{},{},{}]}"#, .pools(entryCount: 4)),
            (.fleet, Self.fleet, .fleet(reportedEntryCount: 0)),
            (.logs, "{}", .logsWithheld) // All log fields omitted from the public fixture.
        ]
        for (endpoint, reduction, expected) in reductions {
            #expect(HarloReadResult.project(endpoint, body: Data(reduction.utf8), profile: .gamma601V02101) == expected)
        }
    }

    // Intentionally synthetic NEGATIVE variants of the reduced /api/info receipt, not captures.
    @Test func identityAndAdvertisementRequireExactIndependentMatches() throws {
        let captured = try JSONDecoder().decode([String: JSONValue].self, from: Data(Self.info.utf8))
        func project(changing key: String, to value: JSONValue?) throws -> HarloReadResult {
            var fields = captured
            fields[key] = value
            return .project(.info, body: try JSONEncoder().encode(fields), profile: .gamma601V02101)
        }
        for (key, mismatch): (String, JSONValue) in [("firmware", .string("Other")), ("version", .string("0.2.102")),
                ("profile", .object(["id": .string("another-board")]))] {
            #expect(try project(changing: key, to: mismatch) == .info(identity: .unconfirmed, advertised: []))
            #expect(try project(changing: key, to: nil) == .info(identity: .unconfirmed, advertised: []))
        }
        for value: JSONValue? in [nil, .null, .string("1"), .bool(true), .number(1.5), .integer(0), .integer(2), .integer(-1)] {
            #expect(try project(changing: "fleet_api_version", to: value) == .info(identity: .matchesConfiguredProfile, advertised: []))
        }
        for invalid: Int64 in [-1, 0, 65_536] {
            #expect(throws: HarloReadError.invalidPolicy) { try HarloInfoProfile.Field(keys: ["v"], equals: .integer(invalid)) }
        }
        let integer = try HarloInfoProfile.Field(keys: ["v"], equals: .integer(1))
        #expect(throws: HarloReadError.invalidPolicy) { try HarloInfoProfile(identity: [integer], advertisements: [:]) }
    }
}

private struct SyntheticHarloFixture: Sendable {
    let client: HarloReadClient
    let record: SyntheticCount
    let transport: MockTransport // Retains the per-host URLProtocol registration for the lifetime of the fixture.

    init(profile: HarloInfoProfile? = nil, retries: Int = 0, minimumInterval: TimeInterval = 0.1,
         maximumBytes: Int = 262_144, handler: @escaping @Sendable (URLRequest, Int) throws -> (URLResponse, Data)) throws {
        let record = SyntheticCount()
        let transport = MockTransport { req in try handler(req, record.increment()) }
        self.record = record
        self.transport = transport
        self.client = try HarloReadClient(baseURL: "https://\(transport.host):9443/",
            policy: HarloReadPolicy(timeout: 4, retries: retries, minimumInterval: minimumInterval, maximumBytes: maximumBytes),
            profile: profile, protocolClasses: [MockURLProtocol.self])
    }
}

private final class SyntheticCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() -> Int { lock.withLock { value += 1; return value } }
}
