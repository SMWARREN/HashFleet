import Foundation
import Testing
@testable import HashFleetCore

extension APIClientTests {
    struct JSONMutation: Sendable {
        let endpoint: MinerEndpoint
        let payload: JSONValue
    }

    @Test(arguments: [
        JSONMutation(endpoint: .settings, payload: .object([
            "hostname": .string("workshop"), "frequency": .integer(600), "autofanspeed": .integer(1)
        ])),
        JSONMutation(endpoint: .updatePool(7), payload: .object([
            "stratumURL": .string("pool.example"), "stratumPort": .integer(3333),
            "stratumUser": .string("wallet.worker"), "stratumPassword": .string("x")
        ])),
        JSONMutation(endpoint: .updateTheme, payload: .object([
            "colorScheme": .string("dark"), "primaryColor": .string("#ff9900")
        ]))
    ])
    func JSONMutationsRetainFirmwareFieldNamesAndTypes(mutation: JSONMutation) async throws {
        let transport = MockTransport { request in
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(try JSONDecoder().decode(JSONValue.self, from: requestBody(request)) == mutation.payload)
            return try stubResponse(for: request, data: Data(#"{"status":"ok"}"#.utf8))
        }
        let result = try await transport.client.executeJSON(mutation.endpoint, body: mutation.payload)
        #expect(result.objectValue?["status"]?.stringValue == "ok")
    }

    @Test func executionForwardsStatisticsQuery() async throws {
        let columns = "hashrate,power,asicTemp"
        let transport = MockTransport { request in
            let url = try #require(request.url)
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ==
                    [URLQueryItem(name: "columns", value: columns)])
            return try stubResponse(for: request, data: Data(#"{"labels":[],"data":[]}"#.utf8))
        }
        let query = [URLQueryItem(name: "columns", value: columns)]
        let value = try await transport.client.executeJSON(.statistics, query: query)
        #expect(value.objectValue?["data"]?.arrayValue == [])
    }

    @Test func failedMutationsAreNotAutomaticallyRetried() async throws {
        await confirmation(expectedCount: 1) { requestReceived in
            let transport = MockTransport { request in
                requestReceived()
                return try stubResponse(for: request, status: 503, data: Data("busy".utf8))
            }
            do {
                _ = try await transport.client.execute(.restart)
                Issue.record("Expected failed mutation")
            } catch MinerAPIError.http(let status, _, _) {
                #expect(status == 503)
            } catch { Issue.record("Unexpected error: \(error)") }
        }
    }
}
