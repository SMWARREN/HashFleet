import Foundation
import Testing
@testable import HashFleetCore

@Suite(.timeLimit(.minutes(1)))
struct APIClientTests {
    @Test func infoUsesInjectedSessionAndDecodesFirmwareObject() async throws {
        let transport = MockTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/system/info")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.timeoutInterval == 15)
            return try stubResponse(for: request,
                                    data: Data(#"{"hashRate":"999.5","hostname":"mock","temp":null}"#.utf8))
        }
        let info = try await transport.client.info()
        #expect(info.hashRate == 999.5)
        #expect(info.hostname == "mock")
        #expect(info.raw["temp"] == .null)
    }

    @Test(arguments: FirmwareOperation.supported.filter { $0.webSocket == false })
    func everyHTTPOperationTravelsThroughInjectedTransport(operation: FirmwareOperation) async throws {
        let expectedBody = operation.contentType.map { _ in Data("{}".utf8) }
        let transport = MockTransport { request in
            #expect(request.httpMethod == operation.method)
            #expect(request.url?.path == operation.path)
            #expect(request.timeoutInterval == operation.timeout)
            #expect(request.value(forHTTPHeaderField: "Content-Type") == operation.contentType)
            #expect(try requestBody(request) == (expectedBody ?? Data()))
            return try stubResponse(for: request, data: Data("ok".utf8))
        }
        let result = try await transport.client.execute(operation.endpoint, body: expectedBody)
        #expect(result == Data("ok".utf8))
    }

    @Test(arguments: [200, 201, 202, 204, 206, 299])
    func allSuccessfulStatusCodesReturnRawData(status: Int) async throws {
        let payload = status == 204 ? Data() : Data([0, 255, 42])
        let transport = MockTransport { try stubResponse(for: $0, status: status, data: payload) }
        #expect(try await transport.client.execute(.logs) == payload)
    }

    @Test(arguments: [301, 302, 307, 308, 400, 401, 403, 404, 409, 413, 422, 429, 500, 503])
    func nonSuccessfulStatusPreservesRawBodyAndStatus(status: Int) async throws {
        let body = Data(#"{"error":"firmware refused this operation"}"#.utf8)
        let transport = MockTransport { try stubResponse(for: $0, status: status, data: body) }
        do {
            _ = try await transport.client.execute(.restart)
            Issue.record("HTTP \(status) was accepted as success")
        } catch MinerAPIError.http(let code, let message, let raw) {
            #expect(code == status)
            #expect(raw == body)
            #expect(message.contains("firmware refused this operation"))
        }
    }

    @Test(arguments: [Data("Unauthorized".utf8), Data(), Data([0xff, 0x00, 0xfe])])
    func errorBodiesNeedNotBeJSONOrUTF8(body: Data) async throws {
        let transport = MockTransport { try stubResponse(for: $0, status: 401, data: body) }
        do {
            _ = try await transport.client.execute(.settings)
            Issue.record("Expected firmware network authorization failure")
        } catch MinerAPIError.http(let code, let message, let raw) {
            #expect(code == 401)
            #expect(raw == body)
            #expect(message.isEmpty == false)
        }
    }

    @Test func rejectsNonHTTPResponse() async throws {
        let transport = MockTransport { request in
            let url = try #require(request.url)
            return (URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), Data())
        }
        do {
            _ = try await transport.client.execute(.info)
            Issue.record("Non-HTTP response accepted")
        } catch MinerAPIError.invalidResponse {
            // Only this exact error case satisfies the test.
        }
    }

    @Test func errorMessageWithHTMLData() async throws {
        // HTML data should fall back to localizedString or raw text
        let htmlBody = Data("<html><body>Service Unavailable</body></html>".utf8)
        let transport = MockTransport { try stubResponse(for: $0, status: 503, data: htmlBody) }
        do {
            _ = try await transport.client.execute(.settings)
            Issue.record("503 with HTML was accepted as success")
        } catch MinerAPIError.http(let code, let message, let raw) {
            #expect(code == 503)
            #expect(raw == htmlBody)
            #expect(message.isEmpty == false)
        }
    }

    @Test func errorMessageWithEmptyData() async throws {
        // Empty data should use localizedString(forStatusCode:)
        let transport = MockTransport { try stubResponse(for: $0, status: 500, data: Data()) }
        do {
            _ = try await transport.client.execute(.settings)
            Issue.record("500 with empty data handled")
        } catch MinerAPIError.http(let code, let message, let raw) {
            #expect(code == 500)
            #expect(raw.isEmpty == true)
            #expect(message.isEmpty == false)
        }
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .cannotFindHost, .cancelled])
    func transportErrorsAreNotReplacedByJSONOrHTTPFailures(code: URLError.Code) async throws {
        let transport = MockTransport { _ in throw URLError(code) }
        do {
            _ = try await transport.client.execute(.info)
            Issue.record("Expected transport failure")
        } catch let error as URLError {
            #expect(error.code == code)
        }
    }

    @Test func executeJSONEncodesAnObjectNotAQuotedJSONString() async throws {
        let payload = JSONValue.object(["partition": .string("ota_1")])
        let transport = MockTransport { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/system/boot")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(try JSONDecoder().decode(JSONValue.self, from: requestBody(request)) == payload)
            return try stubResponse(
                for: request,
                data: Data(#"{"message":"Next boot partition set successfully. Rebooting..."}"#.utf8)
            )
        }
        let response = try await transport.client.executeJSON(.boot, body: payload)
        #expect(response.objectValue?["message"]?.stringValue?.contains("Rebooting") == true)
    }

    @Test(arguments: [MinerEndpoint.otaFirmware, .otaWWW])
    func OTAUploadsAreUnwrappedBinary(endpoint: MinerEndpoint) async throws {
        let firmware = Data([0xe9, 0, 0xff, 0x7b, 0x22, 0x0d, 0x0a])
        let transport = MockTransport { request in
            #expect(try requestBody(request) == firmware)
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
            #expect(request.timeoutInterval == 300)
            #expect(request.httpMethod == "POST")
            return try stubResponse(for: request, data: Data("Update complete".utf8))
        }
        #expect(try await transport.client.execute(endpoint, body: firmware) == Data("Update complete".utf8))
    }

    @Test func invalidJSONDoesNotProduceAnEmptySuccessfulSnapshot() async throws {
        let transport = MockTransport { try stubResponse(for: $0, data: Data("<html>recovery</html>".utf8)) }
        await #expect(throws: (any Error).self) { try await transport.client.info() }
    }

    @Test(arguments: [MinerEndpoint.logWebSocket, .liveWebSocket])
    func HTTPExecutionRejectsWebSocketsWithoutNetworkTraffic(endpoint: MinerEndpoint) async throws {
        await confirmation(expectedCount: 0) { unexpectedRequest in
            let transport = MockTransport { request in
                unexpectedRequest()
                return try stubResponse(for: request)
            }
            do {
                _ = try await transport.client.execute(endpoint)
                Issue.record("WebSocket endpoint was executed as HTTP")
            } catch MinerAPIError.webSocketRequired {
                // Only this exact error case satisfies the test.
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test func socketStreamRejectsHTTPBeforeCreatingASocket() throws {
        let transport = MockTransport { _ in throw URLError(.unsupportedURL) }
        do {
            _ = try transport.client.webSocketStream(.info)
            Issue.record("HTTP endpoint was accepted as WebSocket")
        } catch MinerAPIError.notWebSocket {
            // Only this exact error case satisfies the test.
        }
    }

    @Test func invalidAddressIsRejectedBeforeNetworking() async {
        await confirmation(expectedCount: 0) { unexpectedRequest in
            let transport = MockTransport { request in
                unexpectedRequest()
                return try stubResponse(for: request)
            }
            let client = MinerAPIClient(device: MinerDevice(name: "Bad", address: "http://user:secret@miner.invalid"), session: transport.session)
            do {
                _ = try await client.info()
                Issue.record("Address with credentials was accepted")
            } catch MinerAPIError.invalidAddress {
                // Only this exact error case satisfies the test.
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test(arguments: [MinerEndpoint.otaFirmware, .otaWWW])
    func OTARejectsEmptyAndJSONBodiesBeforeNetworking(endpoint: MinerEndpoint) async {
        await confirmation(expectedCount: 0) { unexpectedRequest in
            let transport = MockTransport { request in
                unexpectedRequest()
                return try stubResponse(for: request)
            }
            for body in [nil, Data()] as [Data?] {
                do {
                    _ = try await transport.client.execute(endpoint, body: body)
                    Issue.record("Empty OTA body accepted")
                } catch MinerAPIError.binaryBodyRequired {
                    // Expected, without contacting a miner.
                } catch { Issue.record("Unexpected error: \(error)") }
            }
            do {
                _ = try await transport.client.executeJSON(endpoint, body: .object(["firmware": .string("not binary")]))
                Issue.record("JSON OTA body accepted")
            } catch MinerAPIError.binaryBodyRequired {
                // Expected, without contacting a miner.
            } catch { Issue.record("Unexpected error: \(error)") }
        }
    }

    @Test func emptyJSONSuccessReturnsNull() async throws {
        let transport = MockTransport { try stubResponse(for: $0, status: 204) }
        #expect(try await transport.client.executeJSON(.restart) == .null)
    }

    @Test(arguments: [
        #"{"message":"message field"}"#,
        #"{"error":{"message":"nested error"}}"#,
        #"{"detail":"detail field"}"#,
        #""plain JSON string""#
    ])
    func commonFirmwareErrorShapesAreReadable(json: String) async throws {
        let transport = MockTransport { try stubResponse(for: $0, status: 400, data: Data(json.utf8)) }
        do {
            _ = try await transport.client.executeJSON(.settings)
            Issue.record("HTTP error accepted")
        } catch MinerAPIError.http(let status, let message, let raw) {
            #expect(status == 400)
            #expect(raw == Data(json.utf8))
            #expect(message.contains("{") == false)
            #expect(message.isEmpty == false)
        }
    }

    @Test func websocketFramesPreserveBytesAndDecodeJSONLocally() throws {
        let text = MinerWebSocketMessage.text(#"{"hashRate":123}"#)
        #expect(text.text == #"{"hashRate":123}"#)
        #expect(try text.json().objectValue?["hashRate"]?.intValue == 123)
        let binary = MinerWebSocketMessage.data(Data([0, 255, 42]))
        #expect(binary.data == Data([0, 255, 42]))
        #expect(binary.text == nil)
        #expect(throws: (any Error).self) { try binary.json() }
    }
}
