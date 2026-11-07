import Testing
@testable import HashFleetCore

extension ConfiguredMiningPoolTests {
    @Test func unknownHostProducesNilCoinAndProvider() {
        let (provider, coin) = ConfiguredMiningPool.inferProviderAndCoin(host: "evil-ckpool.org.attacker.com")
        #expect(provider == nil)
        #expect(coin == nil)

        let attacker = "fake-solofury.com.attacker.com"
        let (solofuryImpostor, impostorCoin) = ConfiguredMiningPool.inferProviderAndCoin(host: attacker)
        #expect(solofuryImpostor == nil)
        #expect(impostorCoin == nil)
    }

    @Test func urlComponentsHostExtractionRejectsUnsafeElements() {
        // Path, query, fragment, credentials must be rejected
        #expect(ConfiguredMiningPool.extractHost("stratum+tcp://user:pass@bch.solofury.com:7070") == nil)
        #expect(ConfiguredMiningPool.extractHost("stratum+tcp://bch.solofury.com:7070/secret") == nil)
        #expect(ConfiguredMiningPool.extractHost("stratum+tcp://bch.solofury.com:7070?query=1") == nil)
        #expect(ConfiguredMiningPool.extractHost("stratum+tcp://bch.solofury.com:7070#frag") == nil)
        #expect(ConfiguredMiningPool.extractHost("stratum+tcp://bch.solofury.com:7070") == "bch.solofury.com")
    }

    @Test func cashAddressValidatesStrictly() {
        // Valid lowercase CashAddr
        let validCashAddr = "bitcoincash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpyy"
        #expect(CashAddress.validated(validCashAddr, expectedPrefix: "bitcoincash") == validCashAddr)

        // Valid uppercase CashAddr normalizes to lowercase with prefix
        let upperCashAddr = "BITCOINCASH:QP3WJPA3TJLJ042Z2WV7HAHSLDGWHWY0RQ9SYWJPYY"
        #expect(CashAddress.validated(upperCashAddr, expectedPrefix: "bitcoincash") == validCashAddr)

        // Reject mixed case CashAddr
        let mixedCashAddr = "bitcoincash:Qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpyy"
        #expect(CashAddress.validated(mixedCashAddr, expectedPrefix: "bitcoincash") == nil)

        // Reject wrong prefix
        #expect(CashAddress.validated(validCashAddr, expectedPrefix: "ecash") == nil)

        // Reject invalid checksum or altered character
        let invalidChecksum = "bitcoincash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpzz"
        #expect(CashAddress.validated(invalidChecksum, expectedPrefix: "bitcoincash") == nil)

        // Reject wrong length (too short / truncated payload)
        let tooShort = "bitcoincash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq"
        #expect(CashAddress.validated(tooShort, expectedPrefix: "bitcoincash") == nil)

        // Legacy Base58 on BCH
        let legacyBase58 = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
        #expect(CashAddress.validated(legacyBase58, expectedPrefix: "bitcoincash") == legacyBase58)
    }
}
