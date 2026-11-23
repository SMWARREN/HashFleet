import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// The local scan must find cgminer-only miners (Canaan Avalon Nano 3S) on TCP 4028 when port 80
/// has no miner API. Synthetic transports only: no real socket, miner or network is contacted.
@Suite("Miner discovery finds cgminer port 4028")
struct MinerDiscoveryCgminerTests {
    private static let version = #"{"VERSION":[{"CGMiner":"4.11.1","API":"3.7","PROD":"Avalon Nano3s","MODEL":"Nano3s","MAC":"e0e1a9000001"}]}"#
    private static let summary = #"{"SUMMARY":[{"Elapsed":60,"MHS 5m":6000000.0,"Accepted":3,"Rejected":0}]}"#

    private final class Hosts: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        func add(_ host: String) { lock.lock(); asked.append(host); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return asked }
    }

    private static func cgminer(avalon: String, asked: Hosts) -> CgminerClient.Transport {
        { host, port, _, payload in
            asked.add(host)
            guard host == avalon, port == 4028 else { throw CgminerError.connectionFailed("refused") }
            let command = (try? JSONDecoder().decode([String: String].self, from: payload))?["command"]
            switch command {
            case "version": return Data(version.utf8)
            case "summary": return Data(summary.utf8)
            default: throw CgminerError.emptyResponse
            }
        }
    }

    @Test func avalonWithNoHTTPIsFoundOnPort4028AndSavedAsCanaan() async throws {
        let bitaxe = "192.168.1.10", avalon = "192.168.1.20", empty = "192.168.1.30"
        let plan = MinerDiscoveryScanPlan(localAddress: "192.168.1.9", hosts: [bitaxe, avalon, empty])
        let asked = Hosts()
        let found = try await MinerDiscoveryService.scan(
            plan: plan,
            transport: { request in
                let host = request.url!.host!
                guard host == bitaxe else { throw URLError(.cannotConnectToHost) }
                let body = Data(#"{"hostname":"Desk Gamma","boardVersion":"602","ASICModel":"BM1370","hashRate":1}"#.utf8)
                return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                              headerFields: ["Content-Type": "application/json"])!)
            },
            cgminerTransport: Self.cgminer(avalon: avalon, asked: asked)
        )
        let avalonCandidate = try #require(found.first { $0.address.hasPrefix(avalon) })
        #expect(avalonCandidate.address == "\(avalon):4028")
        #expect(avalonCandidate.detectedFamily == "canaan")
        #expect(avalonCandidate.model == "Avalon Nano3s")
        // The HTTP miner is found over HTTP and never probed on 4028.
        #expect(found.contains { $0.address == bitaxe })
        #expect(!asked.all.contains(bitaxe))
        // A host with nothing on either port stays absent.
        #expect(!found.contains { $0.address.hasPrefix(empty) })
    }

    @Test func httpOnlyInjectedScanNeverOpensCgminerSockets() async throws {
        let plan = MinerDiscoveryScanPlan(localAddress: "192.168.1.9", hosts: ["192.168.1.40"])
        let found = try await MinerDiscoveryService.scan(plan: plan, transport: { _ in
            throw URLError(.cannotConnectToHost)
        })
        #expect(found.isEmpty)
    }

    @MainActor
    @Test func addingTheAvalonCandidateSavesItsPortAndFamily() throws {
        let suite = "MinerDiscoveryCgminerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        try store.add(name: "", address: "192.168.1.20:4028", firmwareFamily: nil, detectedFamily: "canaan")
        let saved = try #require(store.devices.first)
        #expect(saved.firmwareFamily == "canaan")
        #expect(try saved.validatedURL().port == 4028)
        #expect(!store.observedFamilyCarriesLiveSocket(for: saved.id))
    }
}
