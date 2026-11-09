import Testing
@testable import HashFleetCore

extension ConfiguredMiningPoolTests {
    @Test func resolvesPoolsBySlotIDWithPrimaryAndFallbackRoles() {
        let raw: [String: JSONValue] = [
            "pools": .array([
                .object([
                    "id": .integer(0),
                    "url": .string("stratum+tcp://stratum.ckpool.org:3333"),
                    "user": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker1")
                ]),
                .object([
                    "id": .integer(1),
                    "url": .string("stratum+tcp://bch.solofury.com:7070"),
                    "user": .string("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2.worker2")
                ])
            ]),
            "primaryPoolIndex": .integer(0),
            "secondaryPoolIndex": .integer(1),
            "isUsingFallbackStratum": .integer(0)
        ]
        let info = MinerInfo(raw: raw)
        let pools = ConfiguredMiningPool.resolve(info: info)

        #expect(pools.count == 2)

        // Slot 0 (CKPool BTC)
        let p0 = pools[0]
        #expect(p0.id == "slot-0")
        #expect(p0.host == "stratum.ckpool.org")
        #expect(p0.coin == .btc)
        #expect(p0.provider == .ckpool)
        #expect(p0.role == "Primary slot 0")
        #expect(p0.isActive == true)
        #expect(p0.address == "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa")
        #expect(p0.redactedAddress?.starts(with: "1A1zP1") == true)
        #expect(p0.redactedAddress?.contains("worker1") == false)

        // Slot 1 (SoloFury BCH)
        let p1 = pools[1]
        #expect(p1.id == "slot-1")
        #expect(p1.host == "bch.solofury.com")
        #expect(p1.coin == .bch)
        #expect(p1.provider == .soloFury)
        #expect(p1.role == "Fallback slot 1")
        #expect(p1.isActive == false)
        #expect(p1.address == "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2")
    }

    @Test func resolvesFallbackActiveWhenFallbackStratumIsTrue() {
        let raw: [String: JSONValue] = [
            "pools": .array([
                .object([
                    "id": .integer(0),
                    "url": .string("stratum+tcp://stratum.ckpool.org:3333"),
                    "user": .string("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4.workerA")
                ]),
                .object([
                    "id": .integer(1),
                    "url": .string("stratum+tcp://eu-bch.solofury.com:7070"),
                    "user": .string("bitcoincash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpyy.workerB")
                ])
            ]),
            "primaryPoolIndex": .integer(0),
            "secondaryPoolIndex": .integer(1),
            "isUsingFallbackStratum": .bool(true)
        ]
        let info = MinerInfo(raw: raw)
        let pools = ConfiguredMiningPool.resolve(info: info)

        #expect(pools.count == 2)
        #expect(pools[0].isActive == false)
        #expect(pools[1].isActive == true)
        #expect(pools[1].host == "eu-bch.solofury.com")
        #expect(pools[1].coin == .bch)
        #expect(pools[1].provider == .soloFury)
    }

    @Test func resolvesCombinedPrimaryAndFallbackRoleAndUnassignedSlots() {
        let raw: [String: JSONValue] = [
            "pools": .array([
                .object([
                    "id": .integer(0),
                    "url": .string("stratum+tcp://stratum.ckpool.org:3333"),
                    "user": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker0")
                ]),
                .object([
                    "id": .integer(2),
                    "url": .string("stratum+tcp://bch.solofury.com:7070"),
                    "user": .string("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2.worker2")
                ])
            ]),
            "primaryPoolIndex": .integer(0),
            "secondaryPoolIndex": .integer(0),
            "isUsingFallbackStratum": .bool(false)
        ]
        let info = MinerInfo(raw: raw)
        let pools = ConfiguredMiningPool.resolve(info: info)

        #expect(pools.count == 2)
        #expect(pools[0].role == "Primary & fallback slot 0")
        #expect(pools[0].isActive == true)
        #expect(pools[1].role == "Slot 2")
        #expect(pools[1].isActive == false)
    }

    @Test func legacyResolutionSupportsPoolURLFallbackAndHandlesEmptyOrMissingKeys() {
        let poolURLInfo = MinerInfo(raw: [
            "poolURL": .string("stratum+tcp://stratum.ckpool.org:3333"),
            "stratumUser": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker"),
            "fallbackStratumURL": .string("stratum+tcp://solo.ckpool.org"),
            "fallbackStratumPort": .integer(3333),
            "fallbackStratumUser": .string("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.fallback")
        ])
        let pools = ConfiguredMiningPool.resolve(info: poolURLInfo)
        #expect(pools.count == 2)
        #expect(pools[0].id == "legacy-primary")
        #expect(pools[0].host == "stratum.ckpool.org")
        #expect(pools[0].role == "Configured primary")
        #expect(pools[0].isActive == nil)
        #expect(pools[1].id == "legacy-fallback")
        #expect(pools[1].host == "solo.ckpool.org")
        #expect(pools[1].role == "Configured fallback")
        #expect(pools[1].isActive == nil)

        let emptyLegacy = MinerInfo(raw: [:])
        #expect(ConfiguredMiningPool.resolve(info: emptyLegacy).isEmpty)
    }

    @Test func addressRedactionPreservesShortInputsAndTruncatesLongInputs() {
        #expect(ConfiguredMiningPool.redactAddress("") == "")
        #expect(ConfiguredMiningPool.redactAddress("1234567890") == "1234567890")
        #expect(ConfiguredMiningPool.redactAddress("12345678901") == "123456...8901")
        let full = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
        #expect(ConfiguredMiningPool.redactAddress(full) == "1A1zP1...vfNa")
    }

    @Test func coinAndProviderPropertiesMatchSpecifications() {
        let expectedTickers: [(MiningPoolCoin, String)] = [
            (.btc, "BTC"), (.bch, "BCH"), (.bc2, "BC2"),
            (.bch2, "BCH2"), (.xec, "XEC"), (.dgb, "DGB")
        ]
        for (coin, ticker) in expectedTickers {
            #expect(coin.ticker == ticker)
        }

        let expectedCoingecko: [(MiningPoolCoin, String)] = [
            (.btc, "bitcoin"), (.bch, "bitcoin-cash"), (.bc2, "bitcoinii"),
            (.bch2, "bitcoin-cash-ii"), (.xec, "ecash"), (.dgb, "digibyte")
        ]
        for (coin, id) in expectedCoingecko {
            #expect(coin.coingeckoID == id)
        }

        #expect(MiningPoolCoin.dgb.soloFuryPrefix == nil)
        #expect(MiningPoolCoin.bch.soloFuryPrefix == "/api")
        #expect(MiningPoolCoin.btc.soloFuryPrefix == "/api-btc")
        #expect(MiningPoolCoin.bc2.soloFuryPrefix == "/api-bc2")
        #expect(MiningPoolCoin.bch2.soloFuryPrefix == "/api-bch2")
        #expect(MiningPoolCoin.xec.soloFuryPrefix == "/api-xec")
        #expect(MiningPoolCoin.soloFuryCoins.count == 5)
        #expect(!MiningPoolCoin.soloFuryCoins.contains(.dgb))

        let providerNames: [(MiningPoolProvider?, String?)] = [
            (.ckpool, "CKPool"), (.soloFury, "SoloFury"), (.soloPool, "SoloPool"), (nil, nil)
        ]
        for (provider, name) in providerNames {
            let pool = ConfiguredMiningPool(
                id: "test", host: "example.com", coin: nil,
                provider: provider, role: "role", isActive: nil,
                address: nil, redactedAddress: nil
            )
            #expect(pool.providerName == name)
        }
    }
}
