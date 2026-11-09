import Foundation
import Testing
@testable import HashFleetCore

struct XMRigAPIClientTests {
    @Test func summaryEndpoint2Success() async throws {
        let json = """
        {
          "id": "1",
          "worker_id": "rig1",
          "version": "6.18.0",
          "hashrate": {
            "total": [12345.6, 12345.6, 12345.6]
          },
          "results": {
            "shares_good": 10,
            "shares_total": 12,
            "best": [1234567]
          },
          "connection": {
            "pool": "pool.example.com",
            "uptime": 3600
          },
          "paused": false
        }
        """
        let recordedRequest = LockedBox<URLRequest?>(nil)
        let transport = MockTransport { req in
            recordedRequest.set(req)
            return try stubResponse(for: req, status: 200, data: Data(json.utf8))
        }
        let client = XMRigAPIClient(
            device: MinerDevice(name: "XMR", address: transport.host, kind: .xmrig),
            session: transport.session
        )
        let info = try await client.summary()
        #expect(info.hashRate == 12345.6 / 1_000_000_000.0)
        #expect(info.sharesAccepted == 10)
        #expect(info.sharesRejected == 2)
        #expect(info.bestDiff == "1234567")
        #expect(info.poolURL == "pool.example.com")
        #expect(info.uptimeSeconds == 3600)
        #expect(info.miningPaused == false)
        #expect(info.version == "6.18.0")
        #expect(info.hostname == "rig1")

        #expect(recordedRequest.get()?.url?.path == "/2/summary")
    }

    @Test func summaryEndpoint1Fallback() async throws {
        let json1 = """
        {
          "id": "1",
          "worker_id": "rig2",
          "hashrate": {
            "total": [5000000000.0]
          },
          "results": {
            "shares_good": 100,
            "shares_total": 100,
            "best": [1234]
          },
          "connection": {
            "pool": "pool.example.com",
            "uptime": 3600
          },
          "paused": true
        }
        """

        let requests = LockedBox<[URLRequest]>([])
        let transport = MockTransport { req in
            requests.append(req)
            if req.url?.path == "/2/summary" {
                return try stubResponse(for: req, status: 404, data: Data())
            } else {
                return try stubResponse(for: req, status: 200, data: Data(json1.utf8))
            }
        }

        let client = XMRigAPIClient(
            device: MinerDevice(name: "XMR", address: transport.host, kind: .xmrig),
            session: transport.session
        )
        let info = try await client.summary()
        #expect(info.hashRate == 5.0) // 5,000,000,000 / 1e9
        #expect(info.sharesAccepted == 100)
        #expect(info.sharesRejected == 0)
        #expect(info.miningPaused == true)
        #expect(info.hostname == "rig2")

        let reqs = requests.get()
        #expect(reqs.count == 2)
        #expect(reqs[0].url?.path == "/2/summary")
        #expect(reqs[1].url?.path == "/1/summary")
    }

    @Test func authorizationHeaderIsSetIfTokenProvided() async throws {
        let recordedRequest = LockedBox<URLRequest?>(nil)
        let transport = MockTransport { req in
            recordedRequest.set(req)
            return try stubResponse(
                for: req,
                status: 200,
                data: Data("{\"worker_id\":\"rig\",\"version\":\"6.18.0\",\"paused\":false}".utf8)
            )
        }
        let client = XMRigAPIClient(
            device: MinerDevice(name: "XMR", address: transport.host, kind: .xmrig),
            bearerToken: "my-secret-token",
            session: transport.session
        )
        _ = try await client.summary()
        let request = try #require(recordedRequest.get())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer my-secret-token")
    }

    @Test func unrelatedSummaryShapesAreRejected() async throws {
        let bodies = [
            "{}",
            "[]",
            "null",
            "{\"version\":\"gateway\"}",
            "{\"jsonrpc\":\"2.0\",\"result\":{}}"
        ]
        for body in bodies {
            let transport = MockTransport { req in
                try stubResponse(for: req, status: 200, data: Data(body.utf8))
            }
            let client = XMRigAPIClient(
                device: MinerDevice(name: "XMR", address: transport.host, kind: .xmrig),
                session: transport.session
            )
            do {
                _ = try await client.summary()
                Issue.record("Unrelated XMRig summary shape was accepted: \(body)")
            } catch MinerAPIError.unrecognizedInfo {
                // Expected.
            } catch {
                Issue.record("Unexpected error for shape \(body): \(error)")
            }
        }
    }

    @Test func pauseResumeConstructsJSONRPC() async throws {
        let successJSON = """
        {"id": 1, "jsonrpc": "2.0", "error": null, "result": {}}
        """
        let requests = LockedBox<[URLRequest]>([])
        let transport = MockTransport { req in
            requests.append(req)
            return try stubResponse(for: req, status: 200, data: Data(successJSON.utf8))
        }
        let client = XMRigAPIClient(
            device: MinerDevice(name: "XMR", address: transport.host, kind: .xmrig),
            bearerToken: "secret",
            session: transport.session
        )

        try await client.pause()
        let req1 = try #require(requests.get().first)
        #expect(req1.url?.path == "/json_rpc")
        #expect(req1.httpMethod == "POST")
        #expect(req1.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        if let bodyData = try? requestBody(req1), let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            #expect(json["method"] as? String == "pause")
        } else {
            Issue.record("Failed to parse POST body")
        }

        try await client.resume()
        let req2 = try #require(requests.get().last)
        if let bodyData = try? requestBody(req2), let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            #expect(json["method"] as? String == "resume")
        } else {
            Issue.record("Failed to parse POST body")
        }
    }

    @Test func jsonRPCErrorSurfacesAsHTTPError() async throws {
        let errorJSON = """
        {"id": 1, "jsonrpc": "2.0", "error": {"code": -32601, "message": "Method not found"}, "result": null}
        """
        let transport = MockTransport { req in
            return try stubResponse(for: req, status: 200, data: Data(errorJSON.utf8))
        }
        let client = XMRigAPIClient(
            device: MinerDevice(name: "XMR", address: transport.host, kind: .xmrig),
            session: transport.session
        )

        do {
            try await client.pause()
            Issue.record("Should have thrown error")
        } catch MinerAPIError.http(_, let message, _) {
            #expect(message == "Method not found")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func pauseResumeWith404FallsBackToEndpoint1() async throws {
        // When /2/summary returns 404, client should fall back to /1/summary
        let json1 = """
        {
          "id": "1",
          "worker_id": "rig1",
          "hashrate": {
            "total": [12345.6, 12345.6, 12345.6]
          },
          "results": {
            "shares_good": 10,
            "shares_total": 12,
            "best": [1234567]
          },
          "connection": {
            "pool": "pool.example.com",
            "uptime": 3600
          },
          "paused": false
        }
        """

        let requests = LockedBox<[URLRequest]>([])
        let transport = MockTransport { req in
            requests.append(req)
            if req.url?.path == "/2/summary" {
                return try stubResponse(for: req, status: 404, data: Data())
            } else {
                return try stubResponse(for: req, status: 200, data: Data(json1.utf8))
            }
        }

        let client = XMRigAPIClient(
            device: MinerDevice(name: "XMR", address: transport.host, kind: .xmrig),
            session: transport.session
        )
        let info = try await client.summary()
        #expect(info.hostname == "rig1")
        #expect(info.miningPaused == false)

        let reqs = requests.get()
        #expect(reqs.count == 2)
        #expect(reqs[0].url?.path == "/2/summary")
        #expect(reqs[1].url?.path == "/1/summary")
    }

    @Test func jsonRPCErrorWithDifferentStatusCodes() async throws {
        // Test various HTTP status codes from JSON-RPC calls
        for status in [200, 400, 404, 500, 503] {
            let errorJSON = """
            {"id": 1, "jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid request"}, "result": null}
            """
            let transport = MockTransport { req in
                return try stubResponse(for: req, status: status, data: Data(errorJSON.utf8))
            }
            let client = XMRigAPIClient(
                device: MinerDevice(name: "XMR", address: transport.host, kind: .xmrig),
                session: transport.session
            )

            do {
                try await client.pause()
                Issue.record("Status \(status) should have thrown")
            } catch MinerAPIError.http(_, let message, _) {
                let expected = status == 200
                    ? "Invalid request"
                    : HTTPURLResponse.localizedString(forStatusCode: status)
                #expect(message == expected)
            } catch {
                Issue.record("Unexpected error for status \(status): \(error)")
            }
        }
    }

    @Test func jsonRPCRequiresMatchingIDAndObjectResult() async throws {
        let bodies = [
            "{\"id\":2,\"jsonrpc\":\"2.0\",\"error\":null,\"result\":{}}",
            "{\"id\":1,\"jsonrpc\":\"2.0\",\"error\":null,\"result\":null}",
            "{\"id\":1,\"jsonrpc\":\"2.0\",\"error\":null,\"result\":[]}",
            "{\"id\":1,\"jsonrpc\":\"2.0\",\"error\":{\"code\":-1}}"
        ]
        for body in bodies {
            let transport = MockTransport { req in
                try stubResponse(for: req, status: 200, data: Data(body.utf8))
            }
            let client = XMRigAPIClient(
                device: MinerDevice(name: "XMR", address: transport.host, kind: .xmrig),
                session: transport.session
            )
            do {
                try await client.pause()
                Issue.record("Malformed JSON-RPC success was accepted: \(body)")
            } catch {
                // Every malformed or error envelope must fail before UI acknowledgment.
            }
        }
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func set(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }
}
extension LockedBox where T: RangeReplaceableCollection {
    func append(_ element: T.Element) {
        lock.lock()
        defer { lock.unlock() }
        value.append(element)
    }
}
