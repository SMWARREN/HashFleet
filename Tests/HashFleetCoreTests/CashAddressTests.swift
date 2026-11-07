import Foundation
import Testing
@testable import HashFleetCore

/// Independent test-only CashAddr encoder. No wallet or network access.
/// Checksum constants and bit packing follow the public CashAddr specification.
func cashAddrTestVector(prefix: String, version: UInt8 = 0, hashSize: Int = 20,
                        invalidPadding: Bool = false) -> String {
    let bytes = [version] + [UInt8](repeating: 0, count: hashSize)
    let bits = bytes.flatMap { byte in (0..<8).reversed().map { Int((byte >> $0) & 1) } }
    var data: [UInt8] = []
    for start in stride(from: 0, to: bits.count, by: 5) {
        var word = 0
        for offset in 0..<5 { word = word * 2 + (start + offset < bits.count ? bits[start + offset] : 0) }
        data.append(UInt8(word))
    }
    if invalidPadding { data[data.count - 1] |= 1 }
    let generators: [UInt64] = [0x98f2bc8e61, 0x79b76d99e2, 0xf33e5fb3c4, 0xae2eabe2a8, 0x1e4f43e470]
    var checksum: UInt64 = 1
    let expanded = prefix.utf8.map { $0 & 31 } + [0] + data + [UInt8](repeating: 0, count: 8)
    for value in expanded {
        let top = checksum >> 35
        checksum = ((checksum & 0x07ffffffff) << 5) ^ UInt64(value)
        for index in 0..<5 where top & (1 << index) != 0 { checksum ^= generators[index] }
    }
    checksum ^= 1
    let checkWords = (0..<8).reversed().map { UInt8((checksum >> ($0 * 5)) & 31) }
    let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    return prefix + ":" + String((data + checkWords).map { alphabet[Int($0)] })
}

@Suite("Strict CashAddr and chain formats")
struct CashAddressTests {
    @Test(arguments: ["bitcoincash", "bitcoincashii", "ecash"])
    func validatesAllDocumentedPrefixesAndNormalizesCase(prefix: String) {
        let address = cashAddrTestVector(prefix: prefix)
        #expect(CashAddress.validated(address, expectedPrefix: prefix) == address)
        #expect(CashAddress.validated(address.uppercased(), expectedPrefix: prefix) == address)
        let rawSplit = String(address.split(separator: ":")[1])
        #expect(CashAddress.validated(rawSplit, expectedPrefix: prefix) == address)
        #expect(CashAddress.validated(prefix + ":" + rawSplit.uppercased(), expectedPrefix: prefix) == nil)
    }

    @Test func checksAllEncodedHashSizesAndBothSupportedTypes() {
        let sizes = [20, 24, 28, 32, 40, 48, 56, 64]
        for (code, size) in sizes.enumerated() {
            for type: UInt8 in [0, 8] {
                let address = cashAddrTestVector(prefix: "bitcoincashii", version: type | UInt8(code), hashSize: size)
                #expect(CashAddress.validated(address, expectedPrefix: "bitcoincashii") == address)
            }
        }
    }

    @Test func validChecksumsCannotBypassReservedVersionHashLengthOrPaddingChecks() {
        #expect(CashAddress.validated(cashAddrTestVector(prefix: "bitcoincash", version: 0x80)) == nil)
        #expect(CashAddress.validated(cashAddrTestVector(prefix: "bitcoincash", version: 0x10)) == nil)
        #expect(CashAddress.validated(cashAddrTestVector(prefix: "bitcoincash", version: 1, hashSize: 20)) == nil)
        #expect(CashAddress.validated(cashAddrTestVector(prefix: "bitcoincash", invalidPadding: true)) == nil)
    }

    @Test func checksumAndPathAbuseFailClosed() {
        let address = cashAddrTestVector(prefix: "bitcoincash")
        let altered = String(address.dropLast()) + (address.last == "q" ? "p" : "q")
        #expect(CashAddress.validated(altered) == nil)
        for value in [
            address + "/worker",
            address + "?secret=1",
            address + "#fragment",
            address + "%2F",
            address + ":q",
            String(repeating: "q", count: 10_000),
            "bitcoincash:é"
        ] {
            #expect(CashAddress.validated(value) == nil)
        }
    }

    @Test func chainPrefixesAndLegacyFormatsCannotBeSilentlyReusedAcrossChains() {
        let legacy = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
        let bch = cashAddrTestVector(prefix: "bitcoincash")
        let bch2 = cashAddrTestVector(prefix: "bitcoincashii")
        let xec = cashAddrTestVector(prefix: "ecash")
        #expect(CashAddress.validated(legacy, expectedPrefix: "bitcoincash") == legacy)
        for prefix in ["bitcoincashii", "ecash", "attacker", ""] {
            #expect(CashAddress.validated(legacy, expectedPrefix: prefix) == nil)
        }
        #expect(ConfiguredMiningPool.extractAndValidateAddress(rawUser: legacy + ".worker", coin: .bc2) == legacy)
        #expect(ConfiguredMiningPool.extractAndValidateAddress(rawUser: bch + ".worker", coin: .bch) == bch)
        #expect(ConfiguredMiningPool.extractAndValidateAddress(rawUser: bch2 + ".worker", coin: .bch2) == bch2)
        #expect(ConfiguredMiningPool.extractAndValidateAddress(rawUser: xec + ".worker", coin: .xec) == xec)
        #expect(ConfiguredMiningPool.extractAndValidateAddress(rawUser: bch + ".worker", coin: .bc2) == nil)
        #expect(ConfiguredMiningPool.extractAndValidateAddress(rawUser: bch + ".worker", coin: .bch2) == nil)
        #expect(ConfiguredMiningPool.extractAndValidateAddress(rawUser: legacy + ".worker/private", coin: .btc) == nil)
    }

    @Test func cryptoAddressValidatorBase58RejectsInvalidCharactersLengthsAndChecksums() {
        let validBTC = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
        #expect(CryptoAddressValidator.isValidBase58(validBTC, validVersionBytes: [0]) == true)
        #expect(CryptoAddressValidator.isValidBase58(validBTC, validVersionBytes: [5]) == false)
        #expect(CryptoAddressValidator.isValidBase58(validBTC, validVersionBytes: [30, 63]) == false)

        // Non-Base58 characters: 0, O, I, l
        for nonB58 in ["0A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
                       "OA1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
                       "IA1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
                       "lA1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
                       "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa ",
                       " 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"] {
            #expect(CryptoAddressValidator.isValidBase58(nonB58, validVersionBytes: [0, 5]) == false)
        }

        // Altered checksum (last char changed)
        let corruptChecksum = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb"
        #expect(CryptoAddressValidator.isValidBase58(corruptChecksum, validVersionBytes: [0]) == false)

        // Decoded length too short or too long
        #expect(CryptoAddressValidator.isValidBase58("1111", validVersionBytes: [0]) == false)
        #expect(CryptoAddressValidator.isValidBase58(String(repeating: "1", count: 36), validVersionBytes: [0]) == false)
    }

    @Test func cryptoAddressValidatorSegwitEnforcesBIP173AndBIP350Rules() {
        let validP2WPKH = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
        let validTaproot = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"
        let validV16 = "BC1SW50QGDZ25J"

        #expect(CryptoAddressValidator.isValidSegwit(validP2WPKH, hrp: "bc") == true)
        #expect(CryptoAddressValidator.isValidSegwit(validP2WPKH.uppercased(), hrp: "bc") == true)
        #expect(CryptoAddressValidator.isValidSegwit(validTaproot, hrp: "bc") == true)
        #expect(CryptoAddressValidator.isValidSegwit(validV16, hrp: "bc") == true)

        // Wrong HRP
        #expect(CryptoAddressValidator.isValidSegwit(validP2WPKH, hrp: "tb") == false)
        #expect(CryptoAddressValidator.isValidSegwit(validP2WPKH, hrp: "dgb") == false)

        // Mixed case rejected
        #expect(CryptoAddressValidator.isValidSegwit("Bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", hrp: "bc") == false)
        #expect(CryptoAddressValidator.isValidSegwit("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4A", hrp: "bc") == false)

        // Missing separator '1' or missing prefix
        #expect(CryptoAddressValidator.isValidSegwit("bcqw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", hrp: "bc") == false)
        #expect(CryptoAddressValidator.isValidSegwit("bc1", hrp: "bc") == false)

        // Invalid character in payload (b, i, o are not in Bech32 alphabet)
        #expect(CryptoAddressValidator.isValidSegwit("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3tb", hrp: "bc") == false)
        #expect(CryptoAddressValidator.isValidSegwit("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3ti", hrp: "bc") == false)
        #expect(CryptoAddressValidator.isValidSegwit("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3to", hrp: "bc") == false)

        // Version 0 with Bech32m checksum is invalid
        let v0Bech32m = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh"
        #expect(CryptoAddressValidator.isValidSegwit(v0Bech32m, hrp: "bc") == false)

        // Version 1 with Bech32 checksum is invalid
        let v1Bech32 = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd"
        #expect(CryptoAddressValidator.isValidSegwit(v1Bech32, hrp: "bc") == false)
    }

    @Test func digiByteAddressValidatesBase58AndSegwitFormsStrictly() {
        // Valid DGB legacy P2PKH address
        let validDGB = "DRGenRKV9FUg15qkXyLAgXL4aP93RHrdh9"
        #expect(DigiByteAddress.validated("  \(validDGB) \n") == validDGB)
        #expect(DigiByteAddress.validated(validDGB) == validDGB)

        // Rejection of BTC addresses by DGB validator
        #expect(DigiByteAddress.validated("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa") == nil)
        #expect(DigiByteAddress.validated("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4") == nil)

        // Rejection of out of range lengths and non-ASCII
        #expect(DigiByteAddress.validated("") == nil)
        #expect(DigiByteAddress.validated("dgb1") == nil)
        #expect(DigiByteAddress.validated(String(repeating: "D", count: 100)) == nil)
        #expect(DigiByteAddress.validated("dgb1\u{00E9}123456789012345") == nil)

        // Rejection of bad checksums
        #expect(DigiByteAddress.validated("DRGenRKV9FUg15qkXyLAgXL4aP93RHrdh8") == nil)
    }

    @Test func cashAddressRejectsUnsupportedPrefixesAndBadHeaders() {
        let bch = cashAddrTestVector(prefix: "bitcoincash")
        #expect(CashAddress.validated(bch, expectedPrefix: "dogecoin") == nil)
        #expect(CashAddress.validated(bch, expectedPrefix: "btc") == nil)
        #expect(CashAddress.validated(bch, expectedPrefix: "") == nil)

        // Empty input or whitespace only
        #expect(CashAddress.validated("") == nil)
        #expect(CashAddress.validated("   ") == nil)

        // Non-ASCII input
        #expect(CashAddress.validated("bitcoincash:qp3\u{00FF}test") == nil)
    }
}
