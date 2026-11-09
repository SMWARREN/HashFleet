import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Native solo pool presets")
struct SoloPoolPresetTests {
    private struct PresetExpectation {
        let preset: SoloPoolPreset
        let host: String
        let port: Int
        let coin: String
    }

    @Test func mappingsMatchOfficialStandardSV1Endpoints() {
        let expected: [PresetExpectation] = [
            .init(preset: .ckPoolBTC, host: "stratum.ckpool.org", port: 3333, coin: "BTC"),
            .init(preset: .soloFuryBTC, host: "btc.solofury.com", port: 6060, coin: "BTC"),
            .init(preset: .soloFuryBCH, host: "bch.solofury.com", port: 7070, coin: "BCH"),
            .init(preset: .soloFuryBC2, host: "bc2.solofury.com", port: 8080, coin: "BC2"),
            .init(preset: .soloFuryBCH2, host: "bch2.solofury.com", port: 8585, coin: "BCH2"),
            .init(preset: .soloFuryXEC, host: "xec.solofury.com", port: 9090, coin: "XEC"),
            .init(preset: .soloPoolDGB, host: "us1.solopool.org", port: 8004, coin: "DGB")
        ]
        #expect(SoloPoolPreset.allCases.count == expected.count)
        #expect(Set(SoloPoolPreset.allCases.map(\.id)).count == expected.count)
        for expectation in expected {
            let preset = expectation.preset
            let server = expectation.host
            let port = expectation.port
            let coin = expectation.coin
            #expect(preset.server == server)
            #expect(preset.port == port)
            #expect(preset.coin == coin)
            #expect(preset.stratumProtocol == "SV1")
            #expect(preset.documentationURL.scheme == "https")
            #expect(
                ["solo.ckpool.org", "solofury.com", "dgb-sha.solopool.org"].contains(
                    preset.documentationURL.host ?? ""
                )
            )
        }
    }

    @Test func anyDifferentPresetClearsPreviousWalletIncludingSameCoinDifferentProvider() {
        let oldUser = "previous-chain-wallet.worker"
        for previous in SoloPoolPreset.allCases {
            for next in SoloPoolPreset.allCases where next != previous {
                let fields = next.draft(previousPreset: previous, user: oldUser)
                #expect(fields.user.isEmpty)
                #expect(fields.server == next.server)
                #expect(fields.port == String(next.port))
                #expect(fields.stratumProtocol == "SV1")
            }
        }
        #expect(oldUser == "previous-chain-wallet.worker")
    }

    @Test(arguments: SoloPoolPreset.allCases)
    func newSlotNeverCopiesAnExistingWallet(preset: SoloPoolPreset) {
        let fields = preset.draft(previousPreset: nil, user: "existing-wallet.worker")
        #expect(fields.user.isEmpty)
        #expect(fields.server == preset.server)
        #expect(fields.port == String(preset.port))
        #expect(!String(describing: fields).contains("existing-wallet"))
    }

    @Test func slotIDsAreNotArrayOffsetsAndReportedRolesRemainUnchanged() {
        let raw: [String: JSONValue] = [
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(3), "isUsingFallbackStratum": .integer(1),
            "pools": .array([
                .object(["id": .integer(3), "stratumURL": .string("bch.solofury.com")]),
                .object(["id": .integer(0), "stratumURL": .string("stratum.ckpool.org")])
            ])
        ]
        let before = raw
        let inventory = SoloPoolSlotInventory(raw: raw)
        #expect(inventory.slots.map(\.id) == [0, 3])
        #expect(inventory.firstEmptySlot == 1)
        #expect(inventory.slots[0].roleLabel == "Primary")
        #expect(inventory.slots[1].roleLabel == "Fallback · in use")
        #expect(raw == before)
        #expect(raw["primaryPoolIndex"] == .integer(0))
        #expect(raw["secondaryPoolIndex"] == .integer(3))
    }

    @Test func assignedButMissingRoleSlotsAreNeverAutomaticallyReplaced() {
        let inventory = SoloPoolSlotInventory(raw: [
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1), "pools": .array([])
        ])
        #expect(inventory.firstEmptySlot == 2)
        let blank = SoloPoolSlotInventory(raw: ["pools": .array([])])
        #expect(blank.firstEmptySlot == 0)
    }

    @Test func unknownOrMalformedReportsDoNotClaimAnEmptySlot() {
        let invalid: [[String: JSONValue]?] = [
            nil, [:], ["pools": .null], ["pools": .string("bad")],
            ["pools": .array([.object([:])])],
            ["pools": .array([.object(["id": .integer(0)]), .object(["id": .integer(0)])])],
            ["pools": .array([]), "primaryPoolIndex": .integer(8)],
            ["pools": .array([]), "secondaryPoolIndex": .number(0.5)]
        ]
        for raw in invalid {
            let inventory = SoloPoolSlotInventory(raw: raw)
            #expect(inventory.availability == .unknown)
            #expect(inventory.firstEmptySlot == nil)
        }
    }

    @Test(arguments: [JSONValue.integer(-1), .integer(8), .number(0.5), .bool(true), .null, .string("NaN")])
    func invalidSlotIDsFailClosed(id: JSONValue) {
        let inventory = SoloPoolSlotInventory(raw: ["pools": .array([.object(["id": id])])])
        #expect(inventory.availability == .unknown)
        #expect(inventory.firstEmptySlot == nil)
    }

    @Test func allEightSlotsAreFullAndSevenIsAValidFinalSlot() {
        let rows = (0...7).map {
            JSONValue.object(["id": .integer(Int64($0)), "stratumURL": .string("configured.invalid")])
        }
        let full = SoloPoolSlotInventory(raw: ["pools": .array(rows)])
        #expect(full.slots.count == 8)
        #expect(full.availability == .full)
        #expect(full.firstEmptySlot == nil)
        let last = SoloPoolSlotInventory(raw: ["pools": .array(Array(rows.dropLast()))])
        #expect(last.firstEmptySlot == 7)
    }

    @Test func configuredSlotLabelsNeverRetainPasswordWalletOrURLCredentials() {
        let inventory = SoloPoolSlotInventory(raw: [
            "pools": .array([
                .object([
                    "id": .integer(0),
                    "stratumURL": .string(
                        "stratum+tcp://private-user:private-password@btc.solofury.com:6060/path?private-query"
                    ),
                    "stratumUser": .string("private-wallet.worker"), "stratumPassword": .string("private-password")
                ])
            ])
        ])
        #expect(inventory.slots.first?.serverLabel == "btc.solofury.com")
        #expect(!String(describing: inventory).contains("private"))
    }

    @Test func presetDraftStillRequiresWalletAndFullReplacementAcknowledgementBeforeJSONReview() throws {
        let fields = SoloPoolPreset.soloFuryBCH.draft(previousPreset: .ckPoolBTC, user: "wrong-chain-wallet")
        var draft = MinerTuningPoolDraft(
            slot: 2,
            server: fields.server,
            port: fields.port,
            user: fields.user,
            stratumProtocol: fields.stratumProtocol,
            replacePassword: false,
            password: ""
        )
        #expect(throws: MinerTuningError.self) { try draft.payload(replacementAcknowledged: false) }
        #expect(throws: MinerTuningError.self) { try draft.payload(replacementAcknowledged: true) }
        draft.user = "new-chain-address.worker"
        let payload = try draft.payload(replacementAcknowledged: true)
        #expect(payload["stratumURL"] == .string("bch.solofury.com"))
        #expect(payload["stratumPort"] == .integer(7070))
        #expect(payload["stratumProtocol"] == .string("SV1"))
        #expect(payload["stratumUser"] == .string("new-chain-address.worker"))
        #expect(payload["stratumPassword"] == .string("*****"))
        #expect(payload["primaryPoolIndex"] == nil)
        #expect(payload["secondaryPoolIndex"] == nil)
        #expect(payload["restart"] == nil)
        #expect(
            Set(payload.objectValue?.keys.map { $0 } ?? [])
                == Set(["stratumURL", "stratumPort", "stratumUser", "stratumProtocol", "stratumPassword"])
        )
    }

    @Test func soloPoolPresetsInCatalogCorrespondToVerifiedEndpoints() {
        let expected: [PresetExpectation] = [
            .init(preset: .ckPoolBTC, host: "stratum.ckpool.org", port: 3333, coin: "BTC"),
            .init(preset: .soloFuryBTC, host: "btc.solofury.com", port: 6060, coin: "BTC"),
            .init(preset: .soloFuryBCH, host: "bch.solofury.com", port: 7070, coin: "BCH"),
            .init(preset: .soloFuryBC2, host: "bc2.solofury.com", port: 8080, coin: "BC2"),
            .init(preset: .soloFuryBCH2, host: "bch2.solofury.com", port: 8585, coin: "BCH2"),
            .init(preset: .soloFuryXEC, host: "xec.solofury.com", port: 9090, coin: "XEC"),
            .init(preset: .soloPoolDGB, host: "us1.solopool.org", port: 8004, coin: "DGB")
        ]
        for expectation in expected {
            let preset = expectation.preset
            let server = expectation.host
            let port = expectation.port
            let coin = expectation.coin
            let catalogMatch = MiningSetupCatalog.soloPresets.first(where: { $0.server == server && $0.port == port })
            #expect(catalogMatch != nil)
            #expect(catalogMatch?.coin.symbol == coin)
            #expect(catalogMatch?.mode == .solo)
            #expect(preset.coin == coin)
        }
    }
}
