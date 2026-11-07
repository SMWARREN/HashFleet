import Testing
import HashFleetCore
@testable import HashFleet

struct MinerDisplayNameTests {
    @Test(arguments: [
        ("602", "BM1370", "Gamma"), ("601", "BM1370", "Gamma"),
        ("402", "BM1368", "Supra"), ("650", "BM1370", "Gamma Duo"),
        ("801", "BM1370", "Gamma Turbo"), ("1300", "BM1370", "Gamma Hex"),
        ("302", "BM1366", "Hex"), ("702", "BM1368", "Supra Hex"),
        ("204", "BM1366", "Ultra"), ("102", "BM1397", "Max"),
        ("1201", "BM1373", "Naja Duo")
    ])
    func verifiedBoards(board: String, asic: String, expected: String) {
        let info = MinerInfo(raw: [
            "boardVersion": .string(board), "ASICModel": .string(asic), "hostname": .string("bitaxe")
        ])
        #expect(MinerDisplayName.automatic(info: info, address: "miner.local") == expected)
    }
    @Test func asicAloneNeverGuessesBoardFamily() {
        // An ASIC model alone proves neither the board family nor the vendor,
        // so the bare ASIC is the only honest label.
        #expect(
            MinerDisplayName.automatic(info: MinerInfo(raw: ["ASICModel": .string("BM1370")]), address: "miner.local")
                == "BM1370"
        )
        #expect(
            MinerDisplayName.automatic(
                info: MinerInfo(raw: ["ASICModel": .string("BM1368"), "boardVersion": .string("602")]),
                address: "miner.local"
            ) == "BM1368"
        )
    }
    @Test func najaDuoCombinedAsicStringResolvesToFamily() {
        // Real Naja Duo (model 1201) firmware reports both chips in one string,
        // "BM1372/BM1373". The family match must accept the combined value.
        #expect(
            MinerDisplayName.automatic(
                info: MinerInfo(raw: [
                    "boardVersion": .string("1201"),
                    "ASICModel": .string("BM1372/BM1373"),
                    "hostname": .string("bitaxe-naja-duo")
                ]),
                address: "bitaxe-naja-duo.local"
            ) == "Naja Duo"
        )
    }
    @Test func bitaxeHostnameHintKeepsBitaxeLabelCaseInsensitively() {
        // Real Bitaxe hardware defaults to a "bitaxe" hostname, so the familiar label stays.
        #expect(
            MinerDisplayName.automatic(
                info: MinerInfo(raw: ["ASICModel": .string("BM1370"), "hostname": .string("bitaxe")]),
                address: "miner.local"
            ) == "Bitaxe · BM1370"
        )
        #expect(
            MinerDisplayName.automatic(
                info: MinerInfo(raw: ["ASICModel": .string("BM1370"), "hostname": .string("My-BITAXE-Desk")]),
                address: "miner.local"
            ) == "Bitaxe · BM1370"
        )
    }
    @Test func otherOpenSourceMinersAreNotMislabeledBitaxe() {
        // NerdMiner/NerdQAxe-class devices report the same ASIC telemetry minus any
        // bitaxe hint; the label must not invent a vendor.
        #expect(
            MinerDisplayName.automatic(
                info: MinerInfo(raw: ["ASICModel": .string("BM1366"), "hostname": .string("nerdminer")]),
                address: "miner.local"
            ) == "BM1366"
        )
        #expect(
            MinerDisplayName.automatic(
                info: MinerInfo(raw: ["ASICModel": .string("BM1370"), "hostname": .string("nerdqaxe-a1b2")]),
                address: "miner.local"
            ) == "BM1370"
        )
        #expect(
            MinerDisplayName.automatic(
                info: MinerInfo(raw: ["boardVersion": .string("9999")]),
                address: "avalonnano.local"
            ) == "avalonnano.local"
        )
    }
    @Test func ultimateFallbackFallsBackToAddressHostThenMiner() {
        #expect(MinerDisplayName.automatic(info: nil, address: "nerdpool.local") == "nerdpool.local")
        #expect(MinerDisplayName.automatic(info: MinerInfo(raw: [:]), address: "") == "Miner")
    }
    @Test func explicitFirmwareFamilyAndUnknownHostRemainHonest() {
        #expect(
            MinerDisplayName.automatic(
                info: MinerInfo(raw: ["deviceModel": .string("Custom Board")]),
                address: "miner.local"
            ) == "Custom Board"
        )
        #expect(MinerDisplayName.automatic(info: nil, address: "192.168.1.42") == "192.168.1.42")
        #expect(
            MinerDisplayName.automatic(info: MinerInfo(raw: ["hostname": .string("Desk")]), address: "miner.local")
                == "Desk"
        )
    }
}
