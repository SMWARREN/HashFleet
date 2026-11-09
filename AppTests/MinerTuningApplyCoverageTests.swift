import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

private final class MinerApplyCoverageState: @unchecked Sendable {
    let lock = NSLock()
    var queue: [String: [MinerApplyCoverageProtocol.Action]] = [:]
    var history: [String: [URLRequest]] = [:]
}

private let sharedCoverageState = MinerApplyCoverageState()

private class MinerApplyCoverageProtocol: URLProtocol, @unchecked Sendable {
    enum Action {
        case succeed(Data)
        case fail(Error)
        case empty
    }

    static func enqueue(_ actions: [Action], for id: String) {
        sharedCoverageState.lock.withLock {
            sharedCoverageState.queue[id] = actions
            sharedCoverageState.history[id] = []
        }
    }

    static func getHistory(for id: String) -> [URLRequest] {
        sharedCoverageState.lock.withLock {
            sharedCoverageState.history[id] ?? []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private func capturedRequest() throws -> URLRequest {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = body
        }
        return captured
    }

    override func startLoading() {
        let captured: URLRequest
        do {
            captured = try capturedRequest()
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let id = request.value(forHTTPHeaderField: "X-Test-ID") ?? "unknown"
        let action: Action? = sharedCoverageState.lock.withLock {
            sharedCoverageState.history[id, default: []].append(captured)
            var q = sharedCoverageState.queue[id, default: []]
            let a = q.isEmpty ? nil : q.removeFirst()
            sharedCoverageState.queue[id] = q
            return a
        }

        guard let action = action else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch action {
        case .fail(let err):
            client?.urlProtocol(self, didFailWithError: err)
        case .succeed(let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .empty:
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@Suite("Miner tuning apply coverage") @MainActor
struct MinerTuningApplyCoverageTests {
    private func fixture(id: String) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MinerApplyCoverageProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-ID": id]
        return URLSession(configuration: configuration)
    }

    @Test func transportFailureOnPreflightThrowsDirectly() async {
        let id = UUID().uuidString
        let session = fixture(id: id)
        defer { session.invalidateAndCancel() }
        MinerApplyCoverageProtocol.enqueue([.fail(URLError(.notConnectedToInternet))], for: id)

        let service = MinerTuningApplyService(session: session)
        do {
            _ = try await service.apply(
                device: MinerDevice(name: "Test", address: "test.local"),
                payload: .object(["frequency": .number(600)]),
                isDemo: false,
                writeAuthorized: { true }
            )
            Issue.record("Should have thrown URLError")
        } catch let err as URLError {
            #expect(err.code == .notConnectedToInternet)
        } catch {
            Issue.record("Threw wrong error: \(error)")
        }

        let history = MinerApplyCoverageProtocol.getHistory(for: id)
        #expect(history.count == 1)
        #expect(history.first?.httpMethod == "GET")
        #expect(history.first?.url?.path == "/api/system/info")
    }

    @Test func transportFailureOnExecuteThrowsDirectly() async {
        let id = UUID().uuidString
        let session = fixture(id: id)
        defer { session.invalidateAndCancel() }

        let preflightData = Data("{\"frequency\":600}".utf8)
        MinerApplyCoverageProtocol.enqueue([
            .succeed(preflightData), // preflight
            .fail(URLError(.badServerResponse)) // execute
        ], for: id)

        let service = MinerTuningApplyService(session: session)
        do {
            _ = try await service.apply(
                device: MinerDevice(name: "Test", address: "test.local"),
                payload: .object(["frequency": .number(600)]),
                isDemo: false,
                writeAuthorized: { true }
            )
            Issue.record("Should have thrown URLError")
        } catch let err as URLError {
            #expect(err.code == .badServerResponse)
        } catch {
            Issue.record("Threw wrong error: \(error)")
        }

        let history = MinerApplyCoverageProtocol.getHistory(for: id)
        #expect(history.count == 2)
        #expect(history.first?.httpMethod == "GET")
        #expect(history.dropFirst().first?.httpMethod == "PATCH")
        #expect(history.dropFirst().first?.url?.path == "/api/system")
        let requestBody = history.dropFirst().first?.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        #expect(requestBody == "{\"frequency\":600}")
    }

    @Test func readbackMismatchReturnsUnverified() async throws {
        let id = UUID().uuidString
        let session = fixture(id: id)
        defer { session.invalidateAndCancel() }

        let preflightData = Data("{\"frequency\":600}".utf8)
        let readbackData = Data("{\"frequency\":500}".utf8)
        MinerApplyCoverageProtocol.enqueue([
            .succeed(preflightData), // preflight
            .empty,                  // execute
            .succeed(readbackData)   // readback
        ], for: id)

        let service = MinerTuningApplyService(session: session)
        let result = try await service.apply(
            device: MinerDevice(name: "Test", address: "test.local"),
            payload: .object(["frequency": .number(600)]),
            isDemo: false,
            writeAuthorized: { true }
        )

        guard case .unverified(let msg) = result else {
            Issue.record("Expected unverified, got \(result)")
            return
        }
        #expect(msg.contains("do not match the reviewed change"))

        let history = MinerApplyCoverageProtocol.getHistory(for: id)
        #expect(history.count == 3)
        #expect(history.first?.httpMethod == "GET")
        #expect(history.dropFirst().first?.httpMethod == "PATCH")
        #expect(history.dropFirst(2).first?.httpMethod == "GET")
        let requestBody = history.dropFirst().first?.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        #expect(requestBody == "{\"frequency\":600}")
    }

    @Test func readbackFailureReturnsUnverified() async throws {
        let id = UUID().uuidString
        let session = fixture(id: id)
        defer { session.invalidateAndCancel() }

        let preflightData = Data("{\"frequency\":600}".utf8)
        MinerApplyCoverageProtocol.enqueue([
            .succeed(preflightData), // preflight
            .empty,                  // execute
            .fail(URLError(.notConnectedToInternet)) // readback
        ], for: id)

        let service = MinerTuningApplyService(session: session)
        let result = try await service.apply(
            device: MinerDevice(name: "Test", address: "test.local"),
            payload: .object(["frequency": .number(600)]),
            isDemo: false,
            writeAuthorized: { true }
        )

        guard case .unverified(let msg) = result else {
            Issue.record("Expected unverified, got \(result)")
            return
        }
        #expect(msg.contains("readback could not verify it"))

        let history = MinerApplyCoverageProtocol.getHistory(for: id)
        #expect(history.count == 3)
        #expect(history.first?.httpMethod == "GET")
        #expect(history.dropFirst().first?.httpMethod == "PATCH")
        #expect(history.dropFirst(2).first?.httpMethod == "GET")
    }

    @Test func authorizationRevokedAfterPreflightThrowsBlocked() async {
        let id = UUID().uuidString
        let session = fixture(id: id)
        defer { session.invalidateAndCancel() }
        let preflightData = Data("{\"frequency\":600}".utf8)
        MinerApplyCoverageProtocol.enqueue([.succeed(preflightData)], for: id)

        let service = MinerTuningApplyService(session: session)
        var checks = 0
        do {
            _ = try await service.apply(
                device: MinerDevice(name: "Test", address: "test.local"),
                payload: .object(["frequency": .number(600)]),
                isDemo: false,
                writeAuthorized: {
                    checks += 1
                    return checks == 1
                }
            )
            Issue.record("Should have thrown blocked error")
        } catch MinerTuningApplyService.ApplyError.blocked(let msg) {
            #expect(msg.contains("connection changed during review"))
        } catch {
            Issue.record("Threw wrong error: \(error)")
        }
        #expect(checks == 2)

        let history = MinerApplyCoverageProtocol.getHistory(for: id)
        #expect(history.count == 1) // Only preflight should have been executed
        #expect(history.first?.httpMethod == "GET")
    }

    @Test func missingOrInvalidPayloadFieldsThrowsBlocked() async {
        let id = UUID().uuidString
        let session = fixture(id: id)
        defer { session.invalidateAndCancel() }

        let service = MinerTuningApplyService(session: session)

        let payloads: [JSONValue] = [
            .object([:]),
            .object(["unknown": .number(500)]),
            .object(["frequency": .string("not_a_number")]),
            .array([])
        ]

        for payload in payloads {
            do {
                _ = try await service.apply(
                    device: MinerDevice(name: "Test", address: "test.local"),
                    payload: payload,
                    isDemo: false,
                    writeAuthorized: { true }
                )
                Issue.record("Should have thrown blocked error for \(payload)")
            } catch MinerTuningApplyService.ApplyError.blocked(let msg) {
                #expect(msg.contains("payload is invalid"))
            } catch {
                Issue.record("Threw wrong error: \(error)")
            }

            let history = MinerApplyCoverageProtocol.getHistory(for: id)
            #expect(history.isEmpty) // No request should be sent when validation fails
        }
    }

    @Test func preflight601aConstraintsThrowsBlocked() async {
        let id = UUID().uuidString
        let session = fixture(id: id)
        defer { session.invalidateAndCancel() }
        let preflightData = Data("{\"boardVersion\":\"601a\"}".utf8)
        MinerApplyCoverageProtocol.enqueue([.succeed(preflightData)], for: id)

        let service = MinerTuningApplyService(session: session)
        do {
            _ = try await service.apply(
                device: MinerDevice(name: "Unknown 601a", address: "unverified.local"),
                payload: .object(["coreVoltage": .number(1151)]),
                isDemo: false,
                writeAuthorized: { true }
            )
            Issue.record("Should have thrown blocked error")
        } catch MinerTuningApplyService.ApplyError.blocked(let msg) {
            #expect(msg.contains("1150 mV core-voltage ceiling"))
        } catch {
            Issue.record("Threw wrong error: \(error)")
        }

        let history = MinerApplyCoverageProtocol.getHistory(for: id)
        #expect(history.count == 1) // Only preflight was made
        #expect(history.first?.httpMethod == "GET")
    }

    @Test func cancellationBeforeExecutePreventsAnyWrite() async {
        let id = UUID().uuidString
        let session = fixture(id: id)
        defer { session.invalidateAndCancel() }

        let preflightData = Data("{\"frequency\":600}".utf8)
        MinerApplyCoverageProtocol.enqueue([.succeed(preflightData)], for: id)

        let service = MinerTuningApplyService(session: session)
        let task = Task {
            try await service.apply(
                device: MinerDevice(name: "Test", address: "test.local"),
                payload: .object(["frequency": .number(600)]),
                isDemo: false,
                writeAuthorized: { true }
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Should have thrown cancellation error")
        } catch is CancellationError {
            // Cancellation after preflight is checked by the service.
        } catch let error as URLError where error.code == .cancelled {
            // Cancellation during preflight is reported directly by URLSession.
        } catch {
            Issue.record("Threw wrong error: \(error)")
        }

        let history = MinerApplyCoverageProtocol.getHistory(for: id)
        #expect(history.count <= 1)
        #expect(history.allSatisfy { $0.httpMethod == "GET" })
        #expect(!history.contains(where: { $0.httpMethod == "PATCH" }))
    }
}
