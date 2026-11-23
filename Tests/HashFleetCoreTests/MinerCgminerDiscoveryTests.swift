import Foundation
import Testing
@testable import HashFleetCore

/// Canaan Avalon (Nano 3S) answers only the cgminer TCP API on port 4028, never HTTP. These are
/// synthetic fixtures shaped like the original Nano 3S SDK replies (`version`, `summary`,
/// `estats` with the bracketed `MM ID0` string). No real socket or miner is contacted.
@Suite("cgminer port 4028 discovery and fallback")
struct MinerCgminerDiscoveryTests {

    static let nano3sVersion = #"""
    {"STATUS":[{"STATUS":"S","When":1,"Code":22,"Msg":"CGMiner versions","Description":"cgminer 4.11.1"}],"VERSION":[{"CGMiner":"4.11.1","API":"3.7","PROD":"Avalon Nano3s","MODEL":"Nano3s","HWTYPE":"N_MM1v1_X1","SWTYPE":"MM319","LVERSION":"25021401_56abae7","MAC":"e0e1a9000001"}],"id":1}
    """#
    static let nano3sSummary = #"""
    {"STATUS":[{"STATUS":"S","Code":11,"Msg":"Summary"}],"SUMMARY":[{"Elapsed":3600,"MHS av":6000000.0,"MHS 5m":6100000.0,"Accepted":120,"Rejected":2,"Best Share":5400000}],"id":1}
    """#
    static let nano3sEstats = #"""
    {"STATUS":[{"STATUS":"S","Code":70,"Msg":"CGMiner stats"}],"STATS":[{"STATS":0,"ID":"AVALON0","MM ID0":"Ver[Nano3s-25021401_56abae7] TMax[71] TAvg[66] Fan1[2400] FanR[45%] Freq[500.00] GHSavg[6050.00] MPO[140] WORKMODE[1]"}],"id":1}
    """#

    /// A stub cgminer listener: replies per command, records every command it was asked.
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var commands: [String] = []
        func record(_ command: String) { lock.lock(); commands.append(command); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return commands }
    }

    static func nano3sTransport(_ recorder: Recorder) -> CgminerClient.Transport {
        { _, port, _, payload in
            #expect(port == 4028)
            let request = (try? JSONDecoder().decode([String: String].self, from: payload)) ?? [:]
            let command = request["command"] ?? ""
            recorder.record(command)
            switch command {
            case "version": return Data(nano3sVersion.utf8)
            case "summary": return Data(nano3sSummary.utf8)
            case "estats": return Data(nano3sEstats.utf8)
            default: throw CgminerError.emptyResponse
            }
        }
    }

    @Test func avalonNano3sIsIdentifiedOnPort4028AsCanaan() async throws {
        let recorder = Recorder()
        let identity = try #require(await MinerFirmwareAdapter.identifyCgminer(
            host: "192.168.86.207", transport: Self.nano3sTransport(recorder)
        ))
        #expect(identity.family == "canaan")
        #expect(identity.port == 4028)
        #expect(identity.model == "Avalon Nano3s")
        #expect(identity.info.raw["firmwareFamily"]?.stringValue == "canaan")
        // Read-only: only cgminer read commands were sent, never ascset or a pool/reboot command.
        #expect(Set(recorder.all).isSubset(of: ["version", "summary", "estats", "stats", "pools"]))
    }

    @Test func coreScanCandidateKeepsPortAndCanaanFamily() async throws {
        let recorder = Recorder()
        let candidate = try #require(await FleetNetworkDiscovery.probeCgminer(
            host: "192.168.86.207", transport: Self.nano3sTransport(recorder)
        ))
        #expect(candidate.address == "192.168.86.207:4028")
        #expect(candidate.device.firmwareFamily == "canaan")
        #expect(try candidate.device.validatedURL().port == 4028)
    }

    @Test func savedCanaanMinerReadsTelemetryThroughCgminer() async throws {
        let recorder = Recorder()
        let device = MinerDevice(name: "Avalon", address: "192.168.86.207:4028", firmwareFamily: "canaan")
        let info = try await MinerFirmwareAdapter(
            device: device, cgminerTransport: Self.nano3sTransport(recorder)
        ).info()
        #expect(info.raw["firmwareFamily"]?.stringValue == "canaan")
        #expect(info.sharesAccepted == 120)
        #expect(info.sharesRejected == 2)
        #expect(info.hashRate > 5_000)
        #expect(info.power == 140)
    }

    @Test func nonCgminerTextOnPort4028IsNotAMiner() async {
        let notAMiner: CgminerClient.Transport = { _, _, _, _ in Data("SSH-2.0-OpenSSH_9.6\r\n".utf8) }
        #expect(await MinerFirmwareAdapter.identifyCgminer(host: "192.168.86.50", transport: notAMiner) == nil)
        let emptyVersion: CgminerClient.Transport = { _, _, _, _ in Data(#"{"VERSION":[{}]}"#.utf8) }
        #expect(await MinerFirmwareAdapter.identifyCgminer(host: "192.168.86.50", transport: emptyVersion) == nil)
        let refused: CgminerClient.Transport = { _, _, _, _ in throw CgminerError.connectionFailed("refused") }
        #expect(await MinerFirmwareAdapter.identifyCgminer(host: "192.168.86.50", transport: refused) == nil)
    }

    @Test func versionResponseGuardAcceptsCgminerShapesOnly() throws {
        let nano = try CgminerClient.parseResponse(Self.nano3sVersion)
        #expect(MinerFirmwareAdapter.isCgminerVersionResponse(nano))
        let braiins: [String: JSONValue] = ["VERSION": .array([.object(["BOSminer+": .string("23.08"), "API": .string("3.7")])])]
        #expect(MinerFirmwareAdapter.isCgminerVersionResponse(braiins))
        #expect(!MinerFirmwareAdapter.isCgminerVersionResponse([:]))
        #expect(!MinerFirmwareAdapter.isCgminerVersionResponse(["VERSION": .array([.object(["foo": .string("bar")])])]))
    }

    @Test func httpFailuresThatMeanNoMinerAPIAllowTheCgminerFallback() {
        let allows = MinerFirmwareAdapter.httpFailureAllowsCgminerFallback
        #expect(allows(URLError(.cannotConnectToHost)))
        #expect(allows(URLError(.timedOut)))
        #expect(allows(MinerAPIError.http(statusCode: 404, message: "", body: Data())))
        #expect(allows(MinerAPIError.unrecognizedInfo))
        // A real HTTP miner that errors, an auth wall, cancellation or a bad address never switches protocol.
        #expect(!allows(MinerAPIError.http(statusCode: 500, message: "", body: Data())))
        #expect(!allows(MinerAPIError.http(statusCode: 401, message: "", body: Data())))
        #expect(!allows(CancellationError()))
        #expect(!allows(MinerAPIError.invalidAddress("x")))
        #expect(!allows(URLError(.cancelled)))
    }

    @Test func knownHTTPFirmwareNeverFallsBackToPort4028() {
        for family in ["bitaxe", "bitfortun", "nerdqaxe", "bitforge", "nmaxe", "warpaxe"] {
            #expect(MinerFirmwareAdapter.httpOnlyFamilies.contains(family))
        }
        #expect(!MinerFirmwareAdapter.httpOnlyFamilies.contains(""))
        #expect(!MinerFirmwareAdapter.httpOnlyFamilies.contains("canaan"))
    }
}

/// Fails every HTTP request as "connection refused", like a device with no web server on port 80.
private final class RefusingHTTPProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hits = 0
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.hits += 1
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }
    override func stopLoading() {}
}

@Suite("Saved miner with no family falls back to cgminer", .serialized)
struct MinerCgminerSavedFallbackTests {
    private func refusingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RefusingHTTPProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func unidentifiedSavedAvalonIsReadOverPort4028WhenHTTPIsRefused() async throws {
        let recorder = MinerCgminerDiscoveryTests.Recorder()
        // Saved before this fix: plain IP, no firmware family, like 192.168.86.207 on the phone.
        let device = MinerDevice(name: "Avalon Nano 3S", address: "192.168.86.207")
        let info = try await MinerFirmwareAdapter(
            device: device,
            session: refusingSession(),
            cgminerTransport: MinerCgminerDiscoveryTests.nano3sTransport(recorder)
        ).info()
        #expect(info.raw["firmwareFamily"]?.stringValue == "canaan")
        #expect(info.sharesAccepted == 120)
        #expect(recorder.all.first == "version")
    }

    @Test func knownHTTPFamilyKeepsItsHTTPErrorInsteadOfProbing4028() async {
        let recorder = MinerCgminerDiscoveryTests.Recorder()
        let device = MinerDevice(name: "Gamma", address: "192.168.86.240", firmwareFamily: "bitaxe")
        await #expect(throws: (any Error).self) {
            _ = try await MinerFirmwareAdapter(
                device: device,
                session: refusingSession(),
                cgminerTransport: MinerCgminerDiscoveryTests.nano3sTransport(recorder)
            ).info()
        }
        #expect(recorder.all.isEmpty)
    }

    @Test func unidentifiedDeviceWithNoCgminerKeepsTheOriginalHTTPError() async {
        let refused: CgminerClient.Transport = { _, _, _, _ in throw CgminerError.connectionFailed("refused") }
        let device = MinerDevice(name: "Offline", address: "192.168.86.201")
        do {
            _ = try await MinerFirmwareAdapter(device: device, session: refusingSession(), cgminerTransport: refused).info()
            Issue.record("An offline device must not produce a reading")
        } catch let error as URLError {
            #expect(error.code == .cannotConnectToHost)
        } catch {
            Issue.record("Expected the original HTTP error, got \(error)")
        }
    }
}
