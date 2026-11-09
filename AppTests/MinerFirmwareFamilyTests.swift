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
