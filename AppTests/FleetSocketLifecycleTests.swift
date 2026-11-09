import Foundation
import Testing
import Darwin
import HashFleetCore
@testable import HashFleet

private actor FrameLatch {
    private(set) var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
    func getCount() -> Int {
        count
    }
}

@Suite("FleetSocketLifecycleTests", .serialized)
struct FleetSocketLifecycleTests {

    /// Strict port parser: validates every comma-separated token is an integer in 50401...50420.
    private static func fixturePort() throws -> Int {
        guard let env = ProcessInfo.processInfo.environment["HASHFLEET_FIXTURE_PORTS"], !env.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }
        let rawTokens = env.split(separator: ",", omittingEmptySubsequences: false)
        guard !rawTokens.isEmpty else { throw CocoaError(.formatting) }
        var parsedPorts: [Int] = []
        for token in rawTokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let portNum = Int(trimmed), (50401...50420).contains(portNum) else {
                throw CocoaError(.formatting)
            }
            parsedPorts.append(portNum)
        }
        return parsedPorts[0]
    }

    @Test("Caller-injected ephemeral session drains allTasks and remains usable across mixed epochs")
    func callerInjectedSessionTaskDrainage() async throws {
        let port = try Self.fixturePort()
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let device = MinerDevice(name: "Lifecycle Test Miner", address: "127.0.0.1:\(port)")
        let client = MinerAPIClient(device: device, session: session)

        // Run 4 comparative epochs of mixed HTTP info + WS stream with explicit cancellation
        for epoch in 0..<4 {
            // 1. Real HTTP info request (nonoptional, must succeed)
            let info = try await client.info()
            #expect(!info.hostname.isEmpty || info.hashRate >= 0)

            // 2. WebSocket liveStream with actor frame counter & bounded wait
            let latch = FrameLatch()
            let stream = try client.liveStream()
            let streamConsumer = Task { () -> Int in
                do {
                    for try await _ in stream {
                        _ = await latch.increment()
                        if Task.isCancelled { break }
                    }
                } catch {}
                return await latch.getCount()
            }

            // Poll latch until count >= 1 or bounded 3.0s deadline
            let frameDeadline = Date().addingTimeInterval(3.0)
            while Date() < frameDeadline {
                if await latch.getCount() >= 1 { break }
                try? await Task.sleep(for: .milliseconds(30))
            }

            // Always explicitly cancel and await consumer completion
            streamConsumer.cancel()
            let receivedFrames = await streamConsumer.value
            #expect(receivedFrames >= 1, "Epoch \(epoch) expected at least 1 real frame within 3s")

            // 3. Per-epoch task drainage assertion on the injected session
            let epochDrainDeadline = Date().addingTimeInterval(3.0)
            var epochDrained = false
            while Date() < epochDrainDeadline {
                if await session.allTasks.isEmpty {
                    epochDrained = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
            #expect(epochDrained, "Epoch \(epoch) failed to drain session tasks within 3.0s")

            // 4. Per-epoch usability check: session data(for:) must execute successfully
            let (testData, testResponse) = try await session.data(for: URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/system/info")!))
            let httpResp = try #require(testResponse as? HTTPURLResponse)
            #expect(httpResp.statusCode == 200)
            #expect(!testData.isEmpty)
        }
    }

    @Test("Direct Foundation vs MinerAPIClient task lifecycle comparison with frame receipt")
    func directFoundationVsClientLifecycle() async throws {
        let port = try Self.fixturePort()
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let device = MinerDevice(name: "Direct vs Client", address: "127.0.0.1:\(port)")
        let client = MinerAPIClient(device: device, session: session)

        // Part A: Direct Foundation URLSessionWebSocketTask with bounded wait & cancellation
        let directTask = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/api/ws/live")!)
        directTask.resume()
        let directLatch = FrameLatch()
        let directConsumer = Task { () -> Int in
            do {
                while !Task.isCancelled {
                    _ = try await directTask.receive()
                    _ = await directLatch.increment()
                    if await directLatch.getCount() >= 1 { break }
                }
            } catch {}
            return await directLatch.getCount()
        }

        let directDeadline = Date().addingTimeInterval(3.0)
        while Date() < directDeadline {
            if await directLatch.getCount() >= 1 { break }
            try? await Task.sleep(for: .milliseconds(30))
        }
        directConsumer.cancel()
        directTask.cancel(with: .goingAway, reason: nil)
        let directFrames = await directConsumer.value
        #expect(directFrames >= 1, "Direct task expected at least 1 real frame within 3s")

        // Part B: MinerAPIClient liveStream with actor latch & bounded wait
        let stream = try client.liveStream()
        let clientLatch = FrameLatch()
        let clientConsumer = Task { () -> Int in
            do {
                for try await _ in stream {
                    _ = await clientLatch.increment()
                    if Task.isCancelled { break }
                }
            } catch {}
            return await clientLatch.getCount()
        }

        let clientDeadline = Date().addingTimeInterval(3.0)
        while Date() < clientDeadline {
            if await clientLatch.getCount() >= 1 { break }
            try? await Task.sleep(for: .milliseconds(30))
        }
        clientConsumer.cancel()
        let clientFrames = await clientConsumer.value
        #expect(clientFrames >= 1, "Client stream expected at least 1 real frame within 3s")

        // Session allTasks drainage check
        let drainageDeadline = Date().addingTimeInterval(3.0)
        var allDrained = false
        while Date() < drainageDeadline {
            if await session.allTasks.isEmpty {
                allDrained = true
                break
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(allDrained, "Both direct task and client stream must drain allTasks on session")
    }
}
