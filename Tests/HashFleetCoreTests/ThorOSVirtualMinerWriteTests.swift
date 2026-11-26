import Foundation
import Testing
@testable import HashFleetCore

/// Drives HashFleet's real ThorOS write path against the lab's stateful ThorOS
/// fixture (`Tools/virtual-miners`, `backend = "api-fixture"`) on IPv4 loopback.
/// The fixture follows the official THOR API Reference V1.0.0 and derives its
/// telemetry from the applied settings, so each write is observed end to end.
/// Skipped when python3 or the lab is unavailable.
@Suite("ThorOS virtual miner write round trip", .serialized)
struct ThorOSVirtualMinerWriteTests {
    private static var labDirectory: URL? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        let lab = url.appendingPathComponent("Tools/virtual-miners")
        return FileManager.default.fileExists(atPath: lab.appendingPathComponent("virtual_miners").path) ? lab : nil
    }

    private static func freePort() -> Int {
        // Ephemeral range away from the lab's configured fixture ports.
        Int.random(in: 41000..<49000)
    }

    private static func launchFixture(port: Int) throws -> Process? {
        guard let lab = labDirectory, FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            return nil
        }
        let script = """
        import sys
        from virtual_miners.api_fixture import serve
        fixture = serve({"name": "thor-x1", "board": "thor-x1", "http_port": \(port), "scenario": "normal"})
        print("ready", flush=True)
        sys.stdin.read()
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-B", "-c", script]
        process.currentDirectoryURL = lab
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let ready = output.fileHandleForReading.availableData
        guard String(bytes: ready, encoding: .utf8)?.contains("ready") == true else {
            process.terminate()
            return nil
        }
        return process
    }

    private static func minerStatus(port: Int) async throws -> [String: JSONValue] {
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/v2/miner/status"))
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        return try #require(decoded["data"]?.objectValue)
    }

    @Test func fanFrequencyAndRestartChangeLiveTelemetry() async throws {
        let port = Self.freePort()
        guard let process = try Self.launchFixture(port: port) else { return }
        defer { process.terminate() }

        let device = MinerDevice(name: "Thor X1", address: "127.0.0.1:\(port)", firmwareFamily: "thorOS")
        let adapter = MinerFirmwareAdapter(device: device)

        let info = try await adapter.info()
        #expect(info.raw["device_model"]?.stringValue == "THOR X1")
        let before = try await Self.minerStatus(port: port)
        let baseHashrate = try #require(before["current_hashrate"]?.doubleValue)
        #expect(before["frequency"]?.intValue == 385)

        #expect(try await adapter.setFrequency(475))
        #expect(try await adapter.setFanSpeed(100))
        let tuned = try await Self.minerStatus(port: port)
        #expect(tuned["frequency"]?.intValue == 475)
        #expect(tuned["fan_mode"]?.intValue == 1)
        #expect(tuned["fan_target_speed"]?.intValue == 100)
        #expect(try #require(tuned["current_hashrate"]?.doubleValue) > baseHashrate)

        #expect(try await adapter.setAutoFan(true))
        #expect(try await Self.minerStatus(port: port)["fan_mode"]?.intValue == 0)

        #expect(try await adapter.restart())
        #expect(try await Self.minerStatus(port: port)["shares_accepted"]?.intValue == 0)
    }
}
