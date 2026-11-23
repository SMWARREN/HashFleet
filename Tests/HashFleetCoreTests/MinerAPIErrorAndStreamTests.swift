import Foundation
import Testing
@testable import HashFleetCore

@Suite(.timeLimit(.minutes(1)))
struct MinerAPIErrorAndStreamTests {
    @Test func everyErrorHasAUserFacingDescription() {
        let errors: [MinerAPIError] = [
            .invalidAddress("x"), .invalidPoolIndex(9), .webSocketRequired, .notWebSocket,
            .invalidResponse, .unrecognizedInfo, .binaryBodyRequired, .webSocketBufferOverflow,
            .http(statusCode: 503, message: "busy", body: Data())
        ]
        for error in errors {
            #expect(!(error.errorDescription ?? "").isEmpty, "\(error)")
        }
        #expect(MinerAPIError.invalidPoolIndex(9).errorDescription?.contains("9") == true)
        #expect(MinerAPIError.http(statusCode: 503, message: "busy", body: Data()).errorDescription == "HTTP 503: busy")
    }

    @Test func socketStreamsFailCleanlyWhenTheMinerIsUnreachable() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let device = MinerDevice(name: "Unreachable", address: "socket-\(UUID().uuidString.lowercased()).invalid")
        let client = MinerAPIClient(device: device, session: session)
        for open in [{ try client.logStream() }, { try client.liveStream() }, { try client.webSocketStream(.logWebSocket) }] {
            let stream = try open()
            var delivered = 0
            do {
                for try await _ in stream { delivered += 1 }
            } catch {
                // An unreachable host must surface an error rather than hang or crash.
            }
            #expect(delivered == 0)
        }
    }

    @Test func cancellingTheConsumerClosesTheStream() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let device = MinerDevice(name: "Cancel", address: "cancel-\(UUID().uuidString.lowercased()).invalid")
        let client = MinerAPIClient(device: device, session: session)
        let stream = try client.liveStream()
        let consumer = Task {
            do { for try await _ in stream {} } catch {}
        }
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()
        await consumer.value
    }
}
