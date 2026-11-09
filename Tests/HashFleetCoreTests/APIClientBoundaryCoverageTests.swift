import Foundation
import Testing
@testable import HashFleetCore

/// Boundary coverage for MinerAPIClient wire/HTTP/error/request-building edges that
/// APIClientTests, APIClientTests+JSON, and EndpointTests do not exercise:
/// error-message extraction priority, slot validation at execute time, info-shape
/// acceptance/rejection, scoreboard wire decoding, and query/WebSocket/address corners.
@Suite(.timeLimit(.minutes(1)))
struct APIClientBoundaryCoverageTests {

    // MARK: - Request validation boundaries (no network traffic allowed)

    @Test(arguments: [
        (endpoint: MinerEndpoint.updatePool(8), index: 8),
        (endpoint: MinerEndpoint.updatePool(-1), index: -1),
        (endpoint: MinerEndpoint.deletePool(100), index: 100)
    ])
    func executeRejectsInvalidPoolSlotsBeforeAnyNetworking(fixture: (endpoint: MinerEndpoint, index: Int)) async {
        await confirmation(expectedCount: 0) { unexpectedRequest in
            let transport = MockTransport { request in
                unexpectedRequest()
                return try stubResponse(for: request)
            }
            do {
                _ = try await transport.client.execute(fixture.endpoint, body: Data("{}".utf8))
                Issue.record("Pool slot \(fixture.index) reached the transport")
            } catch MinerAPIError.invalidPoolIndex(let rejected) {
                #expect(rejected == fixture.index)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - HTTP error message extraction boundaries

    @Test func errorMessagePrefersMessageThenErrorThenDetail() async throws {
        let cases: [(body: String, expected: String)] = [
            (#"{"message":"primary","error":"secondary","detail":"tertiary"}"#, "primary"),
            (#"{"error":"secondary","detail":"tertiary"}"#, "secondary"),
            (#"{"detail":"tertiary"}"#, "tertiary")
        ]
        for (body, expected) in cases {
            let transport = MockTransport { try stubResponse(for: $0, status: 400, data: Data(body.utf8)) }
            do {
                _ = try await transport.client.execute(.restart)
                Issue.record("HTTP 400 with \(body) accepted as success")
            } catch MinerAPIError.http(let status, let message, let raw) {
                #expect(status == 400)
                #expect(message == expected)
                #expect(raw == Data(body.utf8))
            }
        }
    }

    @Test func errorMessageReadsNestedErrorMessageExactly() async throws {
        let body = #"{"error":{"message":"pool slot limit reached","code":7}}"#
        let transport = MockTransport { try stubResponse(for: $0, status: 422, data: Data(body.utf8)) }
        do {
            _ = try await transport.client.executeJSON(.updatePool(0), body: .object(["id": .integer(0)]))
            Issue.record("HTTP 422 accepted as success")
        } catch MinerAPIError.http(let status, let message, let raw) {
            #expect(status == 422)
            #expect(message == "pool slot limit reached")
            #expect(raw == Data(body.utf8))
        }
    }

    @Test func plainTextErrorBodyIsTrimmedButOtherwiseVerbatim() async throws {
        let body = Data("  Pool temporarily unavailable\r\n\n".utf8)
        let transport = MockTransport { try stubResponse(for: $0, status: 503, data: body) }
        do {
            _ = try await transport.client.execute(.settings)
            Issue.record("HTTP 503 accepted as success")
        } catch MinerAPIError.http(let status, let message, let raw) {
            #expect(status == 503)
            #expect(message == "Pool temporarily unavailable")
            #expect(raw == body)
        }
    }

    @Test func whitespaceOnlyErrorBodyFallsBackToLocalizedStatusText() async throws {
        let body = Data("  \n\t\n".utf8)
        let transport = MockTransport { try stubResponse(for: $0, status: 500, data: body) }
        do {
            _ = try await transport.client.execute(.logs)
            Issue.record("HTTP 500 accepted as success")
        } catch MinerAPIError.http(let status, let message, let raw) {
            #expect(status == 500)
            #expect(raw == body)
            // Production falls back to Foundation's status phrase when no usable text exists.
            #expect(message == HTTPURLResponse.localizedString(forStatusCode: 500))
        }
    }

    // MARK: - executeJSON decoding boundaries

    @Test func executeJSONDecodesTopLevelArrays() async throws {
        let body = Data(#"[[1,"a"],[2,"b"]]"#.utf8)
        let transport = MockTransport { try stubResponse(for: $0, data: body) }
        let value = try await transport.client.executeJSON(.statistics)
        #expect(value == .array([.array([.integer(1), .string("a")]), .array([.integer(2), .string("b")])]))
    }

    // MARK: - info() shape-validation boundaries

    @Test func infoAcceptsShapeRecognizedOnlyByNumericMetric() async throws {
        let transport = MockTransport { try stubResponse(for: $0, data: Data(#"{"power":12.5}"#.utf8)) }
        let info = try await transport.client.info()
        #expect(info.power == 12.5)
        #expect(info.hostname == "")
    }

    @Test(arguments: [
        #"{"mysteryField":42}"#,          // decodable object, zero recognized keys
        #"{"hostname":""}"#,              // recognized key but empty value carries no identity
        #"{"power":"offline"}"#           // recognized key but unparsable value
    ])
    func infoRejectsUnrecognizedShapesAfterExactlyOneRequest(body: String) async throws {
        await confirmation(expectedCount: 1) { requestReceived in
            let transport = MockTransport { request in
                requestReceived()
                return try stubResponse(for: request, data: Data(body.utf8))
            }
            do {
                _ = try await transport.client.info()
                Issue.record("Unrecognized info shape accepted: \(body)")
            } catch MinerAPIError.unrecognizedInfo {
                // Only this exact error case satisfies the test.
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - scoreboard() wire contract boundaries

    @Test func scoreboardDecodesFirmwareWireShapeIncludingOptionals() async throws {
        let body = Data(#"""
        [
          {"difficulty": 512, "job_id": "1f", "extranonce2": "00000000",
           "ntime": 1760000000, "nonce": "deadbeef", "version_bits": "20000000",
           "coin": "BTC", "poolIndex": 0},
          {"difficulty": 2147483648, "job_id": "20", "extranonce2": "0a01",
           "ntime": 1760000100, "nonce": "aa55", "version_bits": "1fff0000"}
        ]
        """#.utf8)
        let transport = MockTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/system/scoreboard")
            return try stubResponse(for: request, data: body)
        }
        let entries = try await transport.client.scoreboard()
        #expect(entries.count == 2)
        #expect(entries[0].difficulty == 512)
        #expect(entries[0].jobId == "1f")
        #expect(entries[0].ntime == 1_760_000_000)
        #expect(entries[0].occurredAt == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(entries[0].coin == "BTC")
        #expect(entries[0].poolIndex == 0)
        // Older single-coin firmware omits coin/poolIndex entirely.
        #expect(entries[1].coin == nil)
        #expect(entries[1].poolIndex == nil)
    }

    @Test func scoreboardPropagates404WithExactStatusMessageAndBody() async throws {
        let body = Data(#"{"error":"scoreboard not available on this firmware"}"#.utf8)
        let transport = MockTransport { try stubResponse(for: $0, status: 404, data: body) }
        do {
            _ = try await transport.client.scoreboard()
            Issue.record("404 scoreboard response accepted as success")
        } catch MinerAPIError.http(let status, let message, let raw) {
            #expect(status == 404)
            #expect(message == "scoreboard not available on this firmware")
            #expect(raw == body)
        }
    }

    @Test func scoreboardRejectsNonArrayPayloadWithoutCoercing() async throws {
        let transport = MockTransport { try stubResponse(for: $0, data: Data(#"{"entries":[]}"#.utf8)) }
        await #expect(throws: (any Error).self) { _ = try await transport.client.scoreboard() }
    }

    // MARK: - request(for:) URL construction boundaries (built offline, no session traffic)

    @Test(arguments: [MinerEndpoint.logWebSocket, .liveWebSocket])
    func webSocketRequestsRetainQueryItemsAndInsecureScheme(endpoint: MinerEndpoint) throws {
        let client = MinerAPIClient(device: MinerDevice(name: "Offline", address: "miner.invalid"))
        let query = [URLQueryItem(name: "level", value: "info&debug")]
        let url = try #require(try client.request(for: endpoint, query: query).url)
        #expect(url.scheme == "ws")
        #expect(url.path == endpoint.path)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems == query)
    }

    @Test func uppercaseSchemeHostAndTrailingSlashAreNormalized() throws {
        let client = MinerAPIClient(device: MinerDevice(name: "Offline", address: "HTTP://Miner.INVALID:8080/"))
        let url = try #require(try client.request(for: .wifiScan).url)
        #expect(url.absoluteString == "http://miner.invalid:8080/api/system/wifi/scan")
        #expect(url.host == "miner.invalid")
        #expect(url.port == 8080)
    }
}
