import Foundation
import Testing
@testable import HashFleetCore

@Suite struct MiningInsightsValueTests {
    @Test func optionalFieldsRejectInvalidNumbersWithoutLosingValidSiblings() throws {
        let feesJson = #"{"fastestFee":"NaN","halfHourFee":-1,"hourFee":1.25,"economyFee":null,"minimumFee":true}"#
        let fees = try MiningInsightsParser.fees(Data(feesJson.utf8)).0
        #expect(fees.fastestFee == nil)
        #expect(fees.halfHourFee == nil)
        #expect(fees.hourFee == 1.25)
        #expect(fees.economyFee == nil)
        #expect(fees.minimumFee == nil)
        let backlogJson = #"{"count":1.5,"vsize":0,"total_fee":9223372036854775807}"#
        let backlog = try MiningInsightsParser.backlog(Data(backlogJson.utf8)).0
        #expect(backlog.transactionCount == nil)
        #expect(backlog.virtualSizeBytes == 0)
        #expect(backlog.totalFeeSatoshis == Int64.max)
        let miningJson = #"{"currentHashrate":0,"currentDifficulty":10,"# +
                         #""difficulty":[{"time":12345,"difficulty":9}],"# +
                         #""hashrates":[{"timestamp":0,"avgHashrate":100}]}"#
        let mining = try MiningInsightsParser.mining(Data(miningJson.utf8)).0
        #expect(mining.hashrateHPS == nil)
        #expect(mining.difficulty == 10)
        #expect(mining.difficultyChangedAt == nil)
        #expect(mining.hashrateSampleAt == nil)
    }

    @Test func docsAndLiveDifficultyTimeKeysAreBothSupported() throws {
        for key in ["time", "timestamp"] {
            let json = "{\"currentDifficulty\":123,\"difficulty\":[{\"\(key)\":1788640367,\"difficulty\":123}]}"
            let value = try MiningInsightsParser.mining(Data(json.utf8)).0
            #expect(value.difficultyChangedAt == Date(timeIntervalSince1970: 1788640367))
        }
    }

    @Test func poolNDJSONSupportsBlankLinesExtraRecordsAndUnknownKeys() throws {
        let text = "\n{\"Users\":0,\"lastupdate\":1788737796}\r\n \r\n{\"hashrate1m\":\"1.25T\"}\n" +
                   "{\"new_field\":true}\n"
        let (pool, timestamp) = try MiningInsightsParser.pool(Data(text.utf8))
        #expect(pool.users == 0)
        #expect(pool.hashrate1MinuteHPS == 1.25e12)
        #expect(pool.workers == nil)
        #expect(timestamp == Date(timeIntervalSince1970: 1788737796))
        let single = try MiningInsightsParser.pool(Data("{\n\"Users\":1,\n\"hashrate1m\":\"1T\"\n}".utf8))
        #expect(single.0.users == 1)
        #expect(single.1 == nil)
    }

    @Test(arguments: ["{\"Users\":1}\nnot-json", "{\"Users\":1}\n{\"Users\":2}", "{\"Users\":1}\n[]",
                      "{\"hashrate1m\":\"NaNT\"}", "{\"Users\":null}"])
    func corruptOrConflictingNDJSONIsNotPresentedAsComplete(text: String) {
        #expect(throws: MiningInsightsError.invalidData) { try MiningInsightsParser.pool(Data(text.utf8)) }
    }

    @Test(arguments: ["-1", "1.5", "NaN", "true", "\"123\"", "", "<html>123</html>",
                      "999999999999999999999999999999999"])
    func malformedHeightsAreNeverFabricated(text: String) {
        #expect(throws: MiningInsightsError.invalidData) {
            try MiningInsightsParser.height(Data(text.utf8))
        }
    }

    @Test func hashRateSuffixesUseDecimalSIAndPreserveZero() {
        let values: [(String, Double)] = [("0", 0), ("12", 12), ("1k", 1e3), ("2M", 2e6), ("999G", 999e9),
                                          ("1.25T", 1.25e12), ("196P", 196e15), ("1E", 1e18)]
        for (text, expected) in values {
            #expect(MiningInsightsParser.hashrate(.string(text)) == expected)
        }
        for text in ["NaN", "Infinity", "-1T", "1e309T", "1TH/s", "unknown", ""] {
            #expect(MiningInsightsParser.hashrate(.string(text)) == nil)
        }
    }

    @Test func soloProbabilityUsesStablePoissonMathAndCorrectUnits() throws {
        let one = try #require(SoloMiningMath.estimate(hashrateHPS: 4_294_967_296, difficulty: 1, duration: 1))
        #expect(one.expectedBlocks == 1)
        #expect(abs(one.probabilityAtLeastOne - 0.6321205588285577) < 1e-15)
        #expect(one.expectedTimeToBlock == 1)
        let tiny = try #require(SoloMiningMath.estimate(hashrateHPS: 1, difficulty: 1e20, duration: 1))
        #expect(tiny.probabilityAtLeastOne > 0)
        #expect(abs(tiny.probabilityAtLeastOne / tiny.expectedBlocks - 1) < 1e-12)
        let miner = try #require(SoloMiningMath.estimate(hashrateHPS: 1e12, difficulty: 1e14, duration: 86_400,
                                                          height: 840_000, bitcoinPriceUSD: 80_000))
        #expect(abs(miner.expectedBlocks - 2.0116567611694336e-7) < 1e-20)
        #expect(miner.expectedTimeToBlock == 429_496_729_600)
        #expect(miner.blockSubsidyBTC == 3.125)
        #expect(miner.subsidyValueUSD == 250_000)
    }

    @Test func zeroHashrateAndZeroDurationHaveExplicitMeaning() throws {
        let zero = try #require(SoloMiningMath.estimate(hashrateHPS: 0, difficulty: 1, duration: 1))
        #expect(zero.expectedBlocks == 0)
        #expect(zero.probabilityAtLeastOne == 0)
        #expect(zero.expectedTimeToBlock == nil)
        let instant = try #require(SoloMiningMath.estimate(hashrateHPS: 100, difficulty: 1, duration: 0))
        #expect(instant.probabilityAtLeastOne == 0)
        #expect(instant.expectedTimeToBlock != nil)
    }

    @Test func invalidSoloInputsAndInvalidPricesNeverProduceInventedEstimates() {
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            #expect(SoloMiningMath.estimate(hashrateHPS: invalid, difficulty: 1, duration: 1) == nil)
            #expect(SoloMiningMath.estimate(hashrateHPS: 1, difficulty: invalid, duration: 1) == nil)
            #expect(SoloMiningMath.estimate(hashrateHPS: 1, difficulty: 1, duration: invalid) == nil)
            let estimate = SoloMiningMath.estimate(hashrateHPS: 1, difficulty: 1, duration: 1,
                                                    height: 840_000, bitcoinPriceUSD: invalid)
            #expect(estimate?.subsidyValueUSD == nil)
        }
        #expect(SoloMiningMath.estimate(hashrateHPS: 1, difficulty: 0, duration: 1) == nil)
        let zeroPrice = SoloMiningMath.estimate(hashrateHPS: 1, difficulty: 1, duration: 1,
                                                 height: 840_000, bitcoinPriceUSD: 0)
        #expect(zeroPrice?.subsidyValueUSD == nil)
        let noHeight = SoloMiningMath.estimate(hashrateHPS: 1, difficulty: 1, duration: 1, bitcoinPriceUSD: 80_000)
        #expect(noHeight?.subsidyValueUSD == nil)
    }

    @Test func extremeFiniteInputsAvoidIntermediateOverflowAndNaN() throws {
        let recovered = try #require(SoloMiningMath.estimate(hashrateHPS: 1e300, difficulty: 1e300, duration: 1e300))
        #expect(recovered.expectedBlocks.isFinite)
        #expect(recovered.probabilityAtLeastOne == 1)
        let underflowRate = try #require(SoloMiningMath.estimate(hashrateHPS: 1e-300, difficulty: 1e300,
                                                                  duration: 1e300))
        #expect(underflowRate.expectedBlocks > 0)
        #expect(underflowRate.expectedTimeToBlock == nil)
        #expect(SoloMiningMath.estimate(hashrateHPS: 1e300, difficulty: 1e-300, duration: 1e300) == nil)
    }

    @Test func soloMiningEstimateZeroSubsidyAndStructureProperties() throws {
        // When subsidy is 0 BTC (past halving 33), positive price yields $0.0 subsidy value
        let zeroSubsidyEstimate = try #require(SoloMiningMath.estimate(
            hashrateHPS: 1e12, difficulty: 1e14, duration: 86_400,
            height: 6_930_000, bitcoinPriceUSD: 100_000
        ))
        #expect(zeroSubsidyEstimate.blockSubsidyBTC == 0)
        #expect(zeroSubsidyEstimate.subsidyValueUSD == 0)

        // Equatable and Hashable conformance
        let copy = zeroSubsidyEstimate
        #expect(zeroSubsidyEstimate == copy)
        #expect(zeroSubsidyEstimate.hashValue == copy.hashValue)

        // Price overflow returns nil subsidyValueUSD
        let overflowPrice = SoloMiningMath.estimate(
            hashrateHPS: 1e12, difficulty: 1e14, duration: 86_400,
            height: 0, bitcoinPriceUSD: Double.greatestFiniteMagnitude
        )
        #expect(overflowPrice?.subsidyValueUSD == nil)

        // Intermediate halvings
        #expect(SoloMiningMath.blockSubsidyBTC(atHeight: 420_000) == 12.5)
        #expect(SoloMiningMath.blockSubsidyBTC(atHeight: 630_000) == 6.25)
        #expect(SoloMiningMath.blockSubsidyBTC(atHeight: 1_260_000) == 0.78125)
        #expect(SoloMiningMath.blockSubsidyBTC(atHeight: 64 * 210_000) == 0)
        #expect(SoloMiningMath.blockSubsidyBTC(atHeight: 65 * 210_000) == 0)
    }

    @Test func subsidyUsesExactHeightHalvingsAndIntegerSatoshiTruncation() {
        let cases: [(Int, Double)] = [(0, 50), (209_999, 50), (210_000, 25), (839_999, 6.25), (840_000, 3.125),
                                      (1_050_000, 1.5625), (6_720_000, 0.00000001), (6_930_000, 0), (Int.max, 0)]
        for (height, expected) in cases {
            #expect(SoloMiningMath.blockSubsidyBTC(atHeight: height) == expected)
        }
        #expect(SoloMiningMath.blockSubsidyBTC(atHeight: -1) == nil)
    }

    @Test(arguments: ["1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy",
                      "1111111111111111111114oLvT2", "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
                      "BC1SW50QGDZ25J", "bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs",
                      "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"])
    func acceptedAddressesHaveValidBase58OrBIP350Checksums(address: String) {
        #expect(MiningInsightsAddress.validated(" \n\(address) \n") != nil)
        if address.lowercased().hasPrefix("bc1") {
            #expect(MiningInsightsAddress.validated(address) == address.lowercased())
        }
    }

    @Test(arguments: ["bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd",
                      "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh",
                      "bc1p38j9r5y49hruaue7wxjce0updqjuyyx0kh56v8s25huc6995vvpql3jow4",
                      "BC130XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ7ZWS8R",
                      "bc1pw5dgrnzv", "BC1QR508D6QEJXTDG4Y5R3ZARVARYV98GJ9P",
                      "bC1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
                      "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v07qwwzcrf",
                      "tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq47Zagq",
                      "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb", "../../pool/pool.status", "//unexpected.invalid/",
                      "%2e%2e%2f", "bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
                      "ＫwDiBf89QgGbjEhKnhXJuH7SUW1xJXc4s8xg9", "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa\nworker",
                      String(repeating: "1", count: 128)])
    func unsafeOrChecksumInvalidAddressesAreRejected(address: String) {
        #expect(MiningInsightsAddress.validated(address) == nil)
    }
}
