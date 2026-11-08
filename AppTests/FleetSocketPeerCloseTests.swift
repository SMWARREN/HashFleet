import Foundation
import Testing
import HashFleetCore

private struct PeerCloseObservation: Sendable, Codable {
    let port: Int
    let frames: Int
    let elapsed: Double
    let terminalError: String?
}

private actor PeerCloseLedger {
    private var completed: [Int: PeerCloseObservation] = [:]
    func record(_ value: PeerCloseObservation) { completed[value.port] = value }
    func snapshot() -> [PeerCloseObservation] { completed.values.sorted { $0.port < $1.port } }
}

/// Diagnostic regression for REMOTE normal close, not the explicit consumer-cancel path.
/// Requires the owned loopback fixture to send a valid normal-close frame after one second.
/// allTasks drainage is measured separately from OS sockets, which the external driver samples.
/// Ephemeral controls own their session. The shared-session case never invalidates it.
@Suite("Twenty endpoint remote-close lifecycle", .serialized)
struct FleetSocketPeerCloseTests {
    private static func ports() throws -> [Int] {
        let raw = try #require(ProcessInfo.processInfo.environment["HASHFLEET_FIXTURE_PORTS"])
        let values = try raw.split(separator: ",", omittingEmptySubsequences: false).map { token in
            let value = try #require(Int(token.trimmingCharacters(in: .whitespacesAndNewlines)))
            try #require((50401...50420).contains(value))
            return value
        }
        try #require(values.count == 20 && Set(values).count == 20)
        return values
    }

    @Test func directFoundationTwentyEndpointPeerClose() async throws {
        try await exercise(useClient: false)
    }

    @Test func productionClientTwentyEndpointPeerClose() async throws {
        try await exercise(useClient: true)
    }

    @Test func sharedSessionProductionClientTwentyEndpointPeerClose() async throws {
        try await exercise(useClient: true, useSharedSession: true)
    }

    private func exercise(useClient: Bool, useSharedSession: Bool = false) async throws {
        let ports = try Self.ports()
        let session: URLSession
        if useSharedSession {
            session = .shared
            try #require(useClient && session === URLSession.shared)
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 10
            session = URLSession(configuration: configuration)
        }
        defer { if !useSharedSession { session.invalidateAndCancel() } }
        let mode = useSharedSession ? "shared-production" : (useClient ? "production" : "foundation")
        if useSharedSession {
            // Observe, never override, the production session's actual runtime configuration.
            print("FLEET_SHARED_SESSION request_timeout=\(session.configuration.timeoutIntervalForRequest) resource_timeout=\(session.configuration.timeoutIntervalForResource)")
        }

        for epoch in 0..<3 {
            let ledger = PeerCloseLedger()
            let started = Date()
            print("FLEET_PEER_CLOSE mode=\(mode) epoch=\(epoch) begin=\(started.timeIntervalSince1970)")
            let consumers = ports.map { port in
                Task {
                    var frames = 0
                    var terminalError: String?
                    if useClient {
                        do {
                            let client = MinerAPIClient(
                                device: MinerDevice(name: "Owned peer-close \(port)", address: "127.0.0.1:\(port)"),
                                session: session
                            )
                            for try await _ in try client.liveStream() {
                                frames += 1
                            }
                        } catch {
                            terminalError = String(describing: error)
                        }
                    } else {
                        let url = URL(string: "ws://127.0.0.1:\(port)/api/ws/live")!
                        let socket = session.webSocketTask(with: url)
                        socket.resume()
                        defer { socket.cancel(with: .goingAway, reason: nil) }
                        do {
                            while !Task.isCancelled {
                                _ = try await socket.receive()
                                frames += 1
                            }
                        } catch {
                            if socket.closeCode != .normalClosure {
                                terminalError = String(describing: error)
                            }
                        }
                    }
                    await ledger.record(PeerCloseObservation(
                        port: port, frames: frames,
                        elapsed: Date().timeIntervalSince(started), terminalError: terminalError
                    ))
                }
            }

            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if await ledger.snapshot().count == ports.count { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            // Capture natural completion BEFORE cancelling. Cleanup cannot turn a timeout into a pass.
            let natural = await ledger.snapshot()
            let activeAtDeadline = await session.allTasks.count
            for consumer in consumers { consumer.cancel() }
            // Also cancel direct receive tasks if they did not respond to Task cancellation.
            if natural.count != ports.count && !useSharedSession {
                for task in await session.allTasks { task.cancel() }
            }
            for consumer in consumers { await consumer.value }

            let drainDeadline = Date().addingTimeInterval(3)
            while Date() < drainDeadline {
                if await session.allTasks.isEmpty { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            let remainingTasks = await session.allTasks.count
            let report: [String: String] = [
                "mode": mode, "epoch": String(epoch),
                "naturallyCompleted": String(natural.count),
                "activeAtDeadline": String(activeAtDeadline),
                "remainingTasksAfterCleanup": String(remainingTasks),
                "observations": String(decoding: try JSONEncoder().encode(natural), as: UTF8.self)
            ]
            let encoded = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
            print("FLEET_PEER_CLOSE \(encoded)")
            Attachment.record(encoded, named: "peer-close-\(mode)-epoch-\(epoch).json")
            #expect(natural.count == ports.count, "All twenty streams must finish from peer close, not forced cancellation")
            #expect(natural.allSatisfy { $0.frames > 0 }, "Every endpoint must deliver a real frame")
            #expect(natural.allSatisfy { $0.terminalError == nil }, "Normal remote closure must not become an error")
            #expect(remainingTasks == 0, "Session tasks must drain separately from OS socket observations")

            let url = URL(string: "http://127.0.0.1:\(ports[epoch])/api/system/info")!
            let (_, response) = try await session.data(for: URLRequest(url: url))
            let http = try #require(response as? HTTPURLResponse)
            #expect(http.statusCode == 200, "Borrowed session remains usable after a twenty-stream epoch")
            // Leave an observable idle interval for the external lsof resource recorder.
            try await Task.sleep(for: .milliseconds(700))
        }
    }
}
