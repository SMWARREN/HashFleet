import Foundation
import Testing
@testable import HashFleetCore

private let miningInsightsAddressVector = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"

@Suite struct MiningInsightsConnectedPoolTests {
    @Test func resolvesActivePoolByIDNeverArrayPositionAndExcludesSecrets() throws {
        let info = MinerInfo(raw: [
            "isUsingFallbackStratum": .integer(0), "primaryPoolIndex": .integer(3), "secondaryPoolIndex": .integer(0),
            "stratumURL": .string("unsupported.invalid"), "stratumUser": .string("must-not-use"),
            "pools": .array([
                .object(["id": .integer(0), "stratumURL": .string("unsupported.invalid"),
                         "stratumUser": .string("other")]),
                .object(["id": .integer(3), "stratumURL": .string("stratum.ckpool.org"),
                         "stratumUser": .string(miningInsightsAddressVector + ".worker-1"),
                         "stratumPassword": .string("private-password")])
            ])
        ])
        let lookup = try #require(ConnectedPoolLookup.resolve(info: info))
        #expect(lookup.address == miningInsightsAddressVector)
        #expect(lookup.poolHost == "stratum.ckpool.org")
        #expect(lookup.slotID == 3)
        #expect(!lookup.isUsingFallback)
        #expect(!String(describing: lookup).contains("private-password"))
        #expect(!String(describing: lookup).contains("worker-1"))
    }

    @Test func fallbackChoosesOnlySecondaryAndNeverLeaksInactivePrimaryAccount() throws {
        var raw: [String: JSONValue] = [
            "isUsingFallbackStratum": .bool(true), "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1),
            "pools": .array([
                .object(["id": .integer(0), "url": .string("stratum.ckpool.org"),
                         "user": .string(miningInsightsAddressVector)]),
                .object(["id": .integer(1), "url": .string("other-pool.invalid"),
                         "user": .string(miningInsightsAddressVector)])
            ])
        ]
        #expect(ConnectedPoolLookup.resolve(info: MinerInfo(raw: raw)) == nil)
        raw["pools"] = .array([
            .object(["id": .integer(1), "url": .string("stratum+tcp://solo.ckpool.org:3333"),
                     "user": .string(miningInsightsAddressVector + ".fallback")])
        ])
        let lookup = try #require(ConnectedPoolLookup.resolve(info: MinerInfo(raw: raw)))
        #expect(lookup.slotID == 1)
        #expect(lookup.isUsingFallback)
        #expect(lookup.poolHost == "solo.ckpool.org")
    }

    @Test func legacyRequiresExplicitStateAndNeverMixesFallbackAndPrimary() {
        var raw: [String: JSONValue] = ["stratumURL": .string("stratum.ckpool.org"),
                                        "stratumUser": .string(miningInsightsAddressVector)]
        #expect(ConnectedPoolLookup.resolve(info: MinerInfo(raw: raw)) == nil)
        raw["isUsingFallbackStratum"] = .integer(0)
        #expect(ConnectedPoolLookup.resolve(info: MinerInfo(raw: raw))?.address == miningInsightsAddressVector)
        raw["isUsingFallbackStratum"] = .integer(1)
        #expect(ConnectedPoolLookup.resolve(info: MinerInfo(raw: raw)) == nil)
        raw["fallbackStratumURL"] = .string("solo.ckpool.org")
        #expect(ConnectedPoolLookup.resolve(info: MinerInfo(raw: raw)) == nil)
        raw["fallbackStratumUser"] = .string(miningInsightsAddressVector + ".secondary")
        #expect(ConnectedPoolLookup.resolve(info: MinerInfo(raw: raw))?.isUsingFallback == true)
    }

    @Test func incompleteAmbiguousOrInvalidSlotDataFailsClosed() {
        let row = JSONValue.object(["id": .integer(0), "url": .string("solo.ckpool.org"),
                                    "user": .string(miningInsightsAddressVector)])
        let variants: [JSONValue] = [.null, .string("bad"), .array([]), .array([row, row]),
                                    .array([.object(["id": .integer(0), "url": .string("solo.ckpool.org")])])]
        for pools in variants {
            let info = MinerInfo(raw: ["isUsingFallbackStratum": .bool(false), "primaryPoolIndex": .integer(0),
                                      "pools": pools, "stratumURL": .string("solo.ckpool.org"),
                                      "stratumUser": .string(miningInsightsAddressVector)])
            #expect(ConnectedPoolLookup.resolve(info: info) == nil)
        }
        for index in [JSONValue.integer(-1), .integer(8), .number(0.5), .bool(false), .null] {
            let info = MinerInfo(raw: ["isUsingFallbackStratum": .bool(false), "primaryPoolIndex": index,
                                      "pools": .array([row])])
            #expect(ConnectedPoolLookup.resolve(info: info) == nil)
        }
    }

    @Test(arguments: ["solo.ckpool.org.unexpected.invalid", "unexpected.invalid", "https://solo.ckpool.org",
                      "stratum+tcp://user:secret@solo.ckpool.org:3333", "solo.ckpool.org/pool",
                      "solo.ckpool.org?address=secret", "solo.ckpool.org#fragment", "solo.ckpool.org.",
                      "solo.ckpool.org:0", "solo.ckpool.org:65536", "solo%2eckpool.org",
                      "solo.ckpool.org\\evil", "raw.stats.ckpool.org", " solo.ckpool.org"])
    func unsupportedOrUnsafePoolHostNeverResolves(host: String) {
        let info = MinerInfo(raw: ["isUsingFallbackStratum": .integer(0), "stratumURL": .string(host),
                                  "stratumUser": .string(miningInsightsAddressVector)])
        #expect(ConnectedPoolLookup.resolve(info: info) == nil)
    }

    @Test(arguments: ["", "not-a-wallet.worker", "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb.worker",
                      "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker?private=1",
                      "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker/secret",
                      "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.", "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa\nworker"])
    func invalidUserNeverBecomesAnExternalLookup(user: String) {
        let info = MinerInfo(raw: ["isUsingFallbackStratum": .integer(0), "stratumURL": .string("solo.ckpool.org"),
                                  "stratumUser": .string(user)])
        #expect(ConnectedPoolLookup.resolve(info: info) == nil)
    }

    @Test func bitcoinCashUsesBestHeightAndNeverInventsMissingValues() throws {
        let json = #"{"context":{"code":200},"data":{"blocks":967399,"market_price_usd":-1,"# +
                   #""difficulty":0,"hashrate_24h":"NaN","mempool_transactions":0}}"#
        let result = try MiningInsightsBitcoinCashParser.statistics(Data(json.utf8))
        #expect(result.0.tipHeight == nil)
        #expect(result.0.usd == nil)
        #expect(result.0.difficulty == nil)
        #expect(result.0.hashrate24HoursHPS == nil)
        #expect(result.0.mempoolTransactions == 0)
        #expect(result.0.sourceTimestamp == nil)
        #expect(result.1 == nil)
    }

    @Test(arguments: ["2026-02-30 00:00:00", "2026-09-06 23:57:26Z", "", "invalid", "1970-01-01 00:00:00"])
    func invalidSourceDatesAreNotReplacedByFetchTime(timestamp: String) throws {
        let root = JSONValue.object([
            "context": .object(["code": .integer(200), "cache": .object(["since": .string(timestamp)])]),
            "data": .object(["difficulty": .integer(100)])
        ])
        let result = try MiningInsightsBitcoinCashParser.statistics(JSONEncoder().encode(root))
        #expect(result.1 == nil)
        #expect(result.0.sourceTimestamp == nil)
    }

    @Test func providerErrorEnvelopeCannotMasqueradeAsSuccess() {
        #expect(throws: MiningInsightsError.http(statusCode: 429)) {
            let json = #"{"context":{"code":429,"error":"private-body"},"data":{"difficulty":100}}"#
            try MiningInsightsBitcoinCashParser.statistics(Data(json.utf8))
        }
        for text in ["{}", #"{"data":{"difficulty":100}}"#, #"{"context":{"code":200},"data":{}}"#] {
            #expect(throws: MiningInsightsError.invalidData) {
                try MiningInsightsBitcoinCashParser.statistics(Data(text.utf8))
            }
        }
    }
}
