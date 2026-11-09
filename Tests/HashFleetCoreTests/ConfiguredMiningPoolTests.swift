import Testing
import Foundation
@testable import HashFleetCore

@Suite("Configured mining pool resolver tests")
struct ConfiguredMiningPoolTests {

    @Test func soloPoolCoinRequiresTheCorrectHostPortAndAlgorithm() {
        for host in ["us1.solopool.org", "eu2.solopool.org"] {
            for port in [8004, 7004, 9004] {
                for embedded in [false, true] {
                    var row: [String: JSONValue] = ["id": .integer(6),
                        "stratumURL": .string(embedded ? "stratum+tcp://\(host):\(port)" : host)]
                    if !embedded { row["stratumPort"] = .integer(Int64(port)) }
                    let info = MinerInfo(raw: ["activePoolIndex": .integer(6), "pools": .array([.object(row)])])
                    let pool = ConfiguredMiningPool.resolve(info: info).first
                    #expect(pool?.coin == .dgb)
                    #expect(pool?.providerName == "SoloPool")
                    #expect(pool?.provider == .soloPool)
                    #expect(pool?.address == nil)
                    #expect(pool?.isActive == true)
                    #expect(ConnectedPoolLookup.resolve(info: info) == nil)
                }
            }
        }
        #expect(ConfiguredMiningPool.inferProviderAndCoin(host: "us1.solopool.org", port: 8005).1 == .btc)
        #expect(ConfiguredMiningPool.inferProviderAndCoin(host: "us1.solopool.org").1 == nil)
        #expect(ConfiguredMiningPool.inferProviderAndCoin(host: "us1.solopool.org", port: 3333).1 == nil)
        #expect(ConfiguredMiningPool.inferProviderAndCoin(host: "eu3.solopool.org", port: 8004).1 == nil)
        let attackerHost = "us1.solopool.org.attacker.invalid"
        #expect(ConfiguredMiningPool.inferProviderAndCoin(host: attackerHost, port: 8004).1 == nil)
    }

    @Test func soloPoolLegacyAndMalformedPortHandlingNeverGuessDGB() {
        let legacy = MinerInfo(raw: ["stratumURL": .string("us1.solopool.org"), "stratumPort": .integer(8004),
                                    "isUsingFallbackStratum": .bool(false)])
        #expect(ConfiguredMiningPool.resolve(info: legacy).first?.coin == .dgb)
        for port: JSONValue in [.null, .bool(true), .string("bad"), .number(8004.5), .integer(8005)] {
            let info = MinerInfo(raw: ["pools": .array([.object(["id": .integer(0),
                "url": .string("us1.solopool.org:8004"), "port": port])])])
            #expect(ConfiguredMiningPool.resolve(info: info).first?.coin == nil)
        }
    }

    @Test func rotationFollowsActiveSlotAcrossCoinsRegardlessOfPrimaryOrFallbackFlag() {
        var raw: [String: JSONValue] = [
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1),
            "poolRotationEnabled": .bool(true),
            "pools": .array([
                .object(["id": .integer(5), "url": .string("xec.solofury.com")]),
                .object(["id": .integer(1), "url": .string("bch.solofury.com")]),
                .object(["id": .integer(0), "url": .string("stratum.ckpool.org"),
                         "user": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker")])
            ])
        ]
        for flag: JSONValue? in [.bool(false), .bool(true), nil] {
            raw["isUsingFallbackStratum"] = flag
            for (slot, coin) in [(1, MiningPoolCoin.bch), (5, .xec), (0, .btc), (1, .bch)] {
                raw["activePoolIndex"] = .integer(Int64(slot))
                let info = MinerInfo(raw: raw)
                let pools = ConfiguredMiningPool.resolve(info: info)
                #expect(pools.filter { $0.isActive == true }.count == 1)
                #expect(pools.first { $0.isActive == true }?.id == "slot-\(slot)")
                #expect(pools.first { $0.isActive == true }?.coin == coin)
                #expect(ConnectedPoolLookup.resolve(info: info)?.slotID == (slot == 0 ? 0 : nil))
            }
        }
    }

    @Test func invalidExplicitActiveSlotNeverFallsBackToPrimaryOrLegacyAccount() {
        let badSlots: [JSONValue] = [.null, .integer(-1), .integer(8), .integer(7), .number(0.5),
                                     .bool(false), .string("bad")]
        for active: JSONValue in badSlots {
            var raw: [String: JSONValue] = [
                "activePoolIndex": active, "primaryPoolIndex": .integer(0),
                "isUsingFallbackStratum": .bool(false), "stratumURL": .string("stratum.ckpool.org"),
                "stratumUser": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker"),
                "pools": .array([.object(["id": .integer(0), "url": .string("stratum.ckpool.org"),
                                         "user": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker")])])
            ]
            #expect(ConfiguredMiningPool.resolve(info: MinerInfo(raw: raw)).allSatisfy { $0.isActive == nil })
            #expect(ConnectedPoolLookup.resolve(info: MinerInfo(raw: raw)) == nil)
            raw.removeValue(forKey: "pools")
            #expect(ConfiguredMiningPool.resolve(info: MinerInfo(raw: raw)).isEmpty)
            #expect(ConnectedPoolLookup.resolve(info: MinerInfo(raw: raw)) == nil)
        }
    }

    @Test func fractionalOutOfRangeAndNonFiniteSlotsAreRejectedWithoutTruncation() {
        let invalid: [JSONValue] = [.number(0.5), .number(7.5), .integer(-1), .integer(8), .bool(false),
                                    .string("1.5"), .number(.infinity), .number(.nan)]
        for id in invalid {
            let info = MinerInfo(raw: ["pools": .array([.object(["id": id, "url": .string("btc.solofury.com")])])])
            #expect(ConfiguredMiningPool.resolve(info: info).isEmpty)
        }
        for id in [0, 7] {
            let rawObj: JSONValue = .object(["id": .integer(Int64(id)), "url": .string("btc.solofury.com")])
            let info = MinerInfo(raw: ["pools": .array([rawObj])])
            #expect(ConfiguredMiningPool.resolve(info: info).first?.id == "slot-\(id)")
        }
    }

    @Test func activeRemainsUnknownWhenSelectedIndexIsMissingMalformedOrAbsentFromTable() {
        let rows: JSONValue = .array([.object(["id": .integer(0), "url": .string("btc.solofury.com")])])
        for selected: JSONValue in [.null, .number(0.5), .integer(7)] {
            for fallback in [false, true] {
                let selectedKey = fallback ? "secondaryPoolIndex" : "primaryPoolIndex"
                let info = MinerInfo(raw: ["pools": rows, "isUsingFallbackStratum": .bool(fallback),
                                           selectedKey: selected])
                let pool = ConfiguredMiningPool.resolve(info: info).first
                #expect(pool != nil)
                #expect(pool?.isActive == nil)
            }
        }
        let missing = MinerInfo(raw: ["pools": rows, "isUsingFallbackStratum": .integer(0)])
        #expect(ConfiguredMiningPool.resolve(info: missing).first?.isActive == nil)
    }

    @Test func unsafeRawURLsDoNotLeakCredentialsIntoDisplayModel() {
        let info = MinerInfo(raw: ["pools": .array([.object([
            "id": .integer(0), "url": .string("stratum+tcp://private-user:private-password@btc.solofury.com:6060"),
            "user": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker")
        ])])])
        let pool = ConfiguredMiningPool.resolve(info: info).first
        #expect(pool?.host == "Unrecognized pool host")
        #expect(pool?.provider == nil)
        #expect(pool?.address == nil)
        #expect(String(describing: pool).contains("private-password") == false)
        #expect(ConfiguredMiningPool.extractHost("https://btc.solofury.com") == nil)
        #expect(ConfiguredMiningPool.extractHost("stratum2+tcp://btc.solofury.com:3333") == "btc.solofury.com")
        #expect(ConfiguredMiningPool.extractHost("stratum+ssl://eu-btc.solofury.com:6043") == "eu-btc.solofury.com")
    }

    @Test func unknownActiveStatusWhenPrimaryOrSecondaryIndicesMissing() {
        let raw: [String: JSONValue] = [
            "pools": .array([
                .object([
                    "id": .integer(0),
                    "url": .string("stratum+tcp://stratum.ckpool.org:3333"),
                    "user": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker1")
                ])
            ]),
            // indices absent, fallback flag absent
            "isUsingFallbackStratum": .null
        ]
        let info = MinerInfo(raw: raw)
        let pools = ConfiguredMiningPool.resolve(info: info)
        #expect(pools.count == 1)
        #expect(pools[0].isActive == nil)
    }

    @Test func failsClosedOnMalformedPoolsArrayAndNeverFallsBackToLegacy() {
        // pools has duplicate IDs
        let duplicateIds: [String: JSONValue] = [
            "pools": .array([
                .object(["id": .integer(0), "url": .string("stratum+tcp://stratum.ckpool.org:3333")]),
                .object(["id": .integer(0), "url": .string("stratum+tcp://bch.solofury.com:7070")])
            ]),
            "stratumURL": .string("stratum+tcp://stratum.ckpool.org:3333")
        ]
        #expect(ConfiguredMiningPool.resolve(info: MinerInfo(raw: duplicateIds)).isEmpty)

        // pools has missing ID
        let missingId: [String: JSONValue] = [
            "pools": .array([
                .object(["url": .string("stratum+tcp://stratum.ckpool.org:3333")])
            ]),
            "stratumURL": .string("stratum+tcp://stratum.ckpool.org:3333")
        ]
        #expect(ConfiguredMiningPool.resolve(info: MinerInfo(raw: missingId)).isEmpty)

        // pools has non-integer ID
        let invalidIdType: [String: JSONValue] = [
            "pools": .array([
                .object(["id": .string("zero"), "url": .string("stratum+tcp://stratum.ckpool.org:3333")])
            ]),
            "stratumURL": .string("stratum+tcp://stratum.ckpool.org:3333")
        ]
        #expect(ConfiguredMiningPool.resolve(info: MinerInfo(raw: invalidIdType)).isEmpty)

        // pools is not an array
        let notArray: [String: JSONValue] = [
            "pools": .object(["id": .integer(0)]),
            "stratumURL": .string("stratum+tcp://stratum.ckpool.org:3333")
        ]
        #expect(ConfiguredMiningPool.resolve(info: MinerInfo(raw: notArray)).isEmpty)
    }

    @Test func fallsBackToLegacyOnlyWhenPoolsKeyIsCompletelyAbsent() {
        let raw: [String: JSONValue] = [
            "stratumURL": .string("stratum+tcp://solo.ckpool.org:3333"),
            "stratumUser": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.legacy"),
            "isUsingFallbackStratum": .integer(0)
        ]
        let info = MinerInfo(raw: raw)
        let pools = ConfiguredMiningPool.resolve(info: info)

        #expect(pools.count == 1)
        #expect(pools[0].id == "legacy-primary")
        #expect(pools[0].host == "solo.ckpool.org")
        #expect(pools[0].coin == .btc)
        #expect(pools[0].provider == .ckpool)
        #expect(pools[0].isActive == true)
    }

    @Test func allDocumentedSoloFury45EndpointsResolveCorrectly() {
        // Official SoloFury reference: 9 regions x 5 coins = 45 stratum hostnames
        // https://raw.githubusercontent.com/solofurypool-code/solofury-public-docs/main/reference/stratum-endpoints.md
        let regions = ["", "pnw-", "eu-", "uk-", "me-", "afr-", "lat-", "asia-", "jp-"]
        let coins = ["bch", "btc", "bc2", "bch2", "xec"]
        #expect(ConfiguredMiningPool.documentedSoloFuryHosts.count == 45)

        for reg in regions {
            for coin in coins {
                let host = "\(reg)\(coin).solofury.com"
                #expect(ConfiguredMiningPool.documentedSoloFuryHosts.contains(host))
                let (provider, parsedCoin) = ConfiguredMiningPool.inferProviderAndCoin(host: host)
                #expect(provider == .soloFury)
                #expect(parsedCoin?.rawValue == coin)
            }
        }
    }
}
