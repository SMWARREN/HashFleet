import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// The app speaks one HTTP API across several hardware families, but they do not share a release
/// feed. Offering a NerdQAxe owner a Bitaxe build is wrong, so identification must be evidence-based.
@Suite("Firmware family identification")
struct MinerFirmwareFamilyTests {
    private func info(_ pairs: [String: String]) -> MinerInfo {
        MinerInfo(raw: pairs.mapValues { JSONValue.string($0) })
    }

    @Test func boardVersionIdentifiesBitaxe() {
        #expect(MinerFirmwareFamily.identify(from: info(["boardVersion": "Bitaxe Ultra 204"])) == .bitaxe)
    }

    @Test func nerdqaxeIsNotMisreadAsBitaxeDespiteContainingAxe() {
        // "nerdqaxe" contains "axe"; a naive substring check would mis-route the release feed.
        for value in ["NerdQAxe++", "nerdqaxeplus", "NerdOCTAXE-Gamma"] {
            #expect(
                MinerFirmwareFamily.identify(from: info(["boardVersion": value])) == .nerdqaxe,
                "\(value) must resolve to the NerdQAxe project"
            )
        }
    }

    @Test func hostnameAndDeviceModelAreAlsoAcceptedAsEvidence() {
        #expect(MinerFirmwareFamily.identify(from: info(["hostname": "nerdqaxe-a1b2"])) == .nerdqaxe)
        #expect(MinerFirmwareFamily.identify(from: info(["deviceModel": "Bitaxe Gamma"])) == .bitaxe)
    }

    @Test func unknownHardwareYieldsNoFamilyRatherThanAGuess() {
        #expect(MinerFirmwareFamily.identify(from: info(["hostname": "miner-01"])) == nil)
        #expect(MinerFirmwareFamily.identify(from: info([:])) == nil)
        #expect(MinerFirmwareFamily.identify(from: nil) == nil)
        // Blank strings are absence of evidence, not evidence.
        #expect(MinerFirmwareFamily.identify(from: info(["boardVersion": "   "])) == nil)
    }

    @Test func eachFamilyPointsAtItsOwnProjectFeed() {
        let bitaxe = MinerFirmwareFamily.bitaxe.releaseFeedURL.absoluteString
        let nerdqaxe = MinerFirmwareFamily.nerdqaxe.releaseFeedURL.absoluteString
        #expect(bitaxe.contains("bitaxeorg/ESP-Miner"))
        #expect(nerdqaxe.contains("NerdQAxePlus"))
        #expect(bitaxe != nerdqaxe)
        for url in [bitaxe, nerdqaxe] {
            #expect(url.hasPrefix("https://"))
        }
    }

    @Test func everyFamilyHasADistinctDisplayNameAndFeed() {
        let names = Set(MinerFirmwareFamily.allCases.map(\.displayName))
        let feeds = Set(MinerFirmwareFamily.allCases.map(\.releaseFeedURL))
        #expect(names.count == MinerFirmwareFamily.allCases.count)
        #expect(feeds.count == MinerFirmwareFamily.allCases.count)
    }
}

/// Each family's live-socket capability comes from its pinned upstream registrar. Only ESP-Miner
/// registers `/api/ws/live`; NerdQAxe and Bitfortun register only the `/api/ws` log stream.
@Suite("Firmware live-socket capability")
struct MinerFirmwareLiveSocketTests {
    @Test func onlyESPMinerRegistersTheLiveSocket() {
        #expect(MinerFirmwareFamily.bitaxe.supportsLiveWebSocket)
        #expect(!MinerFirmwareFamily.nerdqaxe.supportsLiveWebSocket)
        #expect(!MinerFirmwareFamily.bitfortun.supportsLiveWebSocket)
        #expect(!MinerFirmwareFamily.axeForge.supportsLiveWebSocket)
    }

    @Test func bitfortunBoardStringsResolveToBitfortunNotBitaxe() {
        // Upstream bitfortun-BS-1 sets deviceModel to BitfortunAxe, BitfortunQAxe+, BitfortunOCTAXE+ etc.
        for value in ["BitfortunAxe", "BitfortunQAxe+", "BitfortunOCTAXE+", "BitfortunEKO", "BitfortunAxeGamma"] {
            #expect(
                MinerFirmwareFamily.identify(from: MinerInfo(raw: ["deviceModel": .string(value)])) == .bitfortun,
                "\(value) must resolve to Bitfortun"
            )
        }
    }

    @Test func axeForgeBoardNamesResolveToAxeForge() {
        // Upstream AxeForge names its board from boards/*.toml, e.g. "Bitfortun BS-1" in bs1.toml.
        // That name also contains "Bitfortun", so AxeForge must be checked before Bitfortun.
        let forged = MinerFirmwareFamily.identify(from: MinerInfo(raw: ["board": .string("AxeForge rev5.1/6")]))
        #expect(forged == .axeForge)
    }

    @Test func fleetBoardsStayOnESPMinerAndKeepTheSocket() {
        // Gamma 602, Gamma 601a and both Naja Duos report ESP-Miner identity: no project string.
        for board in ["602", "601a", "1201"] {
            let info = MinerInfo(raw: ["boardVersion": .string(board), "axeOSVersion": .string("Unified"),
                                       "hostname": .string("bitaxe")])
            #expect(MinerFirmwareFamily.identify(from: info) == .bitaxe, "board \(board) must stay ESP-Miner")
        }
    }
}

@Suite("Saved firmware family")
struct MinerSavedFirmwareFamilyTests {
    @Test func olderSavedDevicesDecodeWithoutAFamily() throws {
        let legacy = Data(#"{"id":"\#(UUID().uuidString)","name":"Desk","address":"192.168.1.10","kind":"espMiner"}"#.utf8)
        let device = try JSONDecoder().decode(MinerDevice.self, from: legacy)
        #expect(device.firmwareFamily == nil)
    }

    @Test func familyRoundTripsThroughTheSavedFleet() throws {
        let device = MinerDevice(name: "Naja", address: "192.168.86.239", firmwareFamily: "bitaxe")
        let decoded = try JSONDecoder().decode(MinerDevice.self, from: JSONEncoder().encode(device))
        #expect(decoded.firmwareFamily == "bitaxe")
    }
}
