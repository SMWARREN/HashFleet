import Foundation
import Testing
@testable import HashFleetCore

@Suite(.timeLimit(.minutes(1)))
struct MinerCapabilityTests {
    @Test(arguments: [404, 405, 501])
    func unsupportedStatusesAreDistinguishedFromFailures(status: Int) async throws {
        let transport = CapabilityTransport { request in
            try capabilityResponse(for: request, status: status, body: Data(#"{"error":"not available"}"#.utf8))
        }

        let report = try await MinerCapabilityProbe(client: transport.client).check()

        #expect(report.infoStatus == .unsupported(statusCode: status))
        #expect(report.asicStatus == .unsupported(statusCode: status))
        #expect(report.info == nil)
        #expect(report.asic == nil)
    }

    @Test(arguments: [401, 403, 429, 500, 502, 503])
    func authenticationThrottlingAndServerStatusesAreFailures(status: Int) async throws {
        let transport = CapabilityTransport { request in
            try capabilityResponse(for: request, status: status, body: Data(#"{"error":"failure"}"#.utf8))
        }

        let report = try await MinerCapabilityProbe(client: transport.client).check()

        #expect(isFailure(report.infoStatus))
        #expect(isFailure(report.asicStatus))
        #expect(report.info == nil)
        #expect(report.asic == nil)
    }

    @Test
    func partialSuccessPreservesSupportedInfoWhenASICIsUnsupported() async throws {
        let transport = CapabilityTransport { request in
            if request.url?.path == "/api/system/info" {
                return try capabilityResponse(for: request, body: Data(#"{"hashRate":123.4,"hostname":"mock"}"#.utf8))
            }
            return try capabilityResponse(for: request, status: 404, body: Data(#"{"error":"missing"}"#.utf8))
        }

        let report = try await MinerCapabilityProbe(client: transport.client).check()

        #expect(report.infoStatus == .supported)
        #expect(report.info?.hashRate == 123.4)
        #expect(report.asicStatus == .unsupported(statusCode: 404))
        #expect(report.asic == nil)
    }

    @Test
    func successfulInfoAndASICResponsesAreRetained() async throws {
        let transport = CapabilityTransport { request in
            if request.url?.path == "/api/system/info" {
                return try capabilityResponse(for: request, body: Data(#"{"hashRate":321.0,"version":"AxeOS"}"#.utf8))
            }
            return try capabilityResponse(for: request,
                                          body: Data(#"{"ASICModel":"CUSTOM_ASIC","frequencyOptions":[500,600]}"#.utf8))
        }

        let report = try await MinerCapabilityProbe(client: transport.client).check()

        #expect(report.infoStatus == .supported)
        #expect(report.info?.version == "AxeOS")
        #expect(report.asicStatus == .supported)
        #expect(report.asic?["ASICModel"]?.stringValue == "CUSTOM_ASIC")
    }

    @Test(arguments: [Data(#"{}"#.utf8), Data(#"{"error":"firmware failure"}"#.utf8)])
    func clientInfoRejectsEmptyAndUnrecognizedObjects(body: Data) async throws {
        let transport = CapabilityTransport { request in
            try capabilityResponse(for: request, body: body)
        }

        await #expect(throws: (any Error).self) {
            _ = try await transport.client.info()
        }
    }

    @Test
    func clientInfoAcceptsTypedUnknownASICModel() async throws {
        let transport = CapabilityTransport { request in
            try capabilityResponse(for: request, body: Data(#"{"ASICModel":"FutureUnlistedASIC"}"#.utf8))
        }

        let info = try await transport.client.info()

        #expect(info.asicModel == "FutureUnlistedASIC")
    }

    @Test(arguments: [Data(), Data("not-json".utf8), Data("null".utf8), Data("[]".utf8), Data("123".utf8),
                      Data(#"{}"#.utf8)])
    func malformedEmptyAndNonObjectPayloadsFailShapeValidation(body: Data) async throws {
        let transport = CapabilityTransport { request in
            try capabilityResponse(for: request, body: body)
        }

        let report = try await MinerCapabilityProbe(client: transport.client).check()

        #expect(isFailure(report.infoStatus))
        #expect(isFailure(report.asicStatus))
        #expect(report.info == nil)
        #expect(report.asic == nil)
    }

    @Test
    func recognizedKeysRequireMeaningfulTypedValues() async throws {
        let transport = CapabilityTransport { request in
            if request.url?.path == "/api/system/info" {
                return try capabilityResponse(for: request, body: Data(#"{"hashRate":"garbage","hostname":null}"#.utf8))
            }
            return try capabilityResponse(for: request, body: Data(#"{"ASICModel":null,"defaultVoltage":{}}"#.utf8))
        }

        let report = try await MinerCapabilityProbe(client: transport.client).check()

        #expect(isFailure(report.infoStatus))
        #expect(isFailure(report.asicStatus))
    }

    @Test
    func unknownNonEmptyModelsAreRecognizedWithoutAllowlist() async throws {
        let transport = CapabilityTransport { request in
            if request.url?.path == "/api/system/info" {
                return try capabilityResponse(for: request, body: Data(#"{"ASICModel":"BM1397"}"#.utf8))
            }
            return try capabilityResponse(for: request, body: Data(#"{"deviceModel":"CUSTOM_ASIC"}"#.utf8))
        }

        let report = try await MinerCapabilityProbe(client: transport.client).check()

        #expect(report.infoStatus == .supported)
        #expect(report.asicStatus == .supported)
    }

    @Test
    func missingOptionalFieldsDoNotImplyUnsupported() async throws {
        let transport = CapabilityTransport { request in
            if request.url?.path == "/api/system/info" {
                return try capabilityResponse(for: request, body: Data(#"{"hostname":"minimal"}"#.utf8))
            }
            return try capabilityResponse(for: request, body: Data(#"{"defaultFrequency":600}"#.utf8))
        }

        let report = try await MinerCapabilityProbe(client: transport.client).check()

        #expect(report.infoStatus == .supported)
        #expect(report.asicStatus == .supported)
    }

    @Test
    func checkUsesExactlyOneReadOnlyGETForEachCapabilityPath() async throws {
        let recorder = RequestRecorder()
        let transport = CapabilityTransport(recorder: recorder) { request in
            try capabilityResponse(
                for: request,
                body: request.url?.path == "/api/system/info"
                    ? Data(#"{"hashRate":1}"#.utf8)
                    : Data(#"{"ASICModel":"BM1397"}"#.utf8)
            )
        }

        _ = try await MinerCapabilityProbe(client: transport.client).check()

        let requests = recorder.requests
        #expect(requests.count == 2)
        #expect(requests.map { $0.httpMethod } == ["GET", "GET"])
        #expect(Set(requests.compactMap { $0.url?.path }) == Set(["/api/system/info", "/api/system/asic"]))
        #expect(requests.allSatisfy { $0.httpBody == nil })
    }

    @Test
    func cancellationIsPropagatedInsteadOfMappedToCapabilityFailure() async throws {
        let transport = CapabilityTransport { _ in throw URLError(.cancelled) }

        do {
            _ = try await MinerCapabilityProbe(client: transport.client).check()
            Issue.record("Expected cancellation to be thrown")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        } catch is CancellationError {
            // Also acceptable when URLSession normalizes cancellation.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func transportFailureIsReportedAsFailure() async throws {
        let transport = CapabilityTransport { _ in throw URLError(.cannotFindHost) }

        let report = try await MinerCapabilityProbe(client: transport.client).check()

        #expect(isFailure(report.infoStatus))
        #expect(isFailure(report.asicStatus))
    }

    private func isFailure(_ status: MinerProbeStatus) -> Bool {
        if case .failed = status { return true }
        return false
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func append(_ request: URLRequest) {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
    }
}

private final class CapabilityURLProtocol: URLProtocol, @unchecked Sendable {
    fileprivate static let registry = CapabilityRegistry()

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host,
              let handler = Self.registry.handler(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
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

private final class CapabilityRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]

    func set(_ handler: Handler?, for host: String) {
        lock.lock()
        handlers[host] = handler
        lock.unlock()
    }

    func handler(for host: String) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[host]
    }
}

private final class CapabilityTransport: @unchecked Sendable {
    let host: String
    let session: URLSession
    let client: MinerAPIClient

    init(
        recorder: RequestRecorder? = nil,
        handler: @escaping @Sendable (URLRequest) throws -> (URLResponse, Data)
    ) {
        host = "capability-\(UUID().uuidString.lowercased()).invalid"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapabilityURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
        client = MinerAPIClient(device: MinerDevice(name: "Capability fixture", address: host), session: session)
        CapabilityURLProtocol.registry.set({ request in
            recorder?.append(request)
            return try handler(request)
        }, for: host)
    }

    deinit {
        session.invalidateAndCancel()
        CapabilityURLProtocol.registry.set(nil, for: host)
    }
}

private func capabilityResponse(
    for request: URLRequest,
    status: Int = 200,
    body: Data
) throws -> (URLResponse, Data) {
    guard let url = request.url,
          let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                         headerFields: nil) else {
        throw URLError(.badURL)
    }
    return (response, body)
}
