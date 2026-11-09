import Foundation

/// Full CashAddress validation per the CashAddr specification (Bitcoin Cash and eCash):
/// - Lowercase/uppercase consistency (no mixed case)
/// - Prefix expansion + 40-bit polymod checksum
/// - Decodes 5-bit chunks to payload bytes
/// - Validates version byte (most significant bit MUST be 0, type 0 = P2PKH, 1 = P2SH)
/// - Validates hash length encoding (bits 0...2: 0=20B, 1=24B, 2=28B, 3=32B, 4=40B, 5=48B, 6=56B, 7=64B)
/// - Validates 0 padding bits
/// BCH additionally permits its documented legacy Base58 form. BC2 uses Bitcoin's validator instead.
/// Only standard P2PKH/P2SH CashAddr types are supported, not token-aware extension types.
public enum CashAddress {

    /// Bits 0...2 of the version byte map to the hash length per the CashAddr spec.
    private static let hashSizes: [UInt8: Int] = [0: 20, 1: 24, 2: 28, 3: 32, 4: 40, 5: 48, 6: 56, 7: 64]

    /// Validates an address for the given coin. Returns the normalized lowercase address (or Base58 string).
    public static func validated(_ input: String, expectedPrefix: String = "bitcoincash") -> String? {
        let expectedPrefix = expectedPrefix.lowercased()
        guard ["bitcoincash", "bitcoincashii", "ecash"].contains(expectedPrefix) else { return nil }
        let address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...126).contains(address.utf8.count),
            address.utf8.allSatisfy({ $0 > 32 && $0 < 127 })
        else { return nil }

        if isValidLegacyBase58(address, expectedPrefix: expectedPrefix) { return address }

        guard let (prefix, payloadString) = splitPrefix(address, expectedPrefix: expectedPrefix),
            let payloadBytes = decodeAndVerify(prefix: prefix, payloadString: payloadString),
            headerValid(payloadBytes)
        else { return nil }

        return "\(prefix):\(payloadString)"
    }

    /// Splits on the first colon. A colon address must use the expected prefix; otherwise the
    /// expected prefix is implied. Whole-address mixed case is invalid.
    private static func splitPrefix(_ address: String, expectedPrefix: String) -> (String, String)? {
        let hasUpper = address.contains { $0.isASCII && $0.isUppercase }
        let hasLower = address.contains { $0.isASCII && $0.isLowercase }
        if hasUpper && hasLower { return nil }
        let lowered = address.lowercased()
        guard let colonIndex = lowered.firstIndex(of: ":") else {
            return (expectedPrefix, lowered)
        }
        let prefix = String(lowered[..<colonIndex])
        guard prefix == expectedPrefix else { return nil }
        return (prefix, String(lowered[lowered.index(after: colonIndex)...]))
    }

    /// Decodes the base32 payload and verifies the 40-bit polymod checksum, returning payload bytes.
    private static func decodeAndVerify(prefix: String, payloadString: String) -> [UInt8]? {
        guard !payloadString.isEmpty, let payload5Bit = decodeBase32Payload(payloadString) else { return nil }
        // Version (2 chunks) + hash + 8 checksum chunks. Min 42, max 112.
        guard payload5Bit.count >= 42 && payload5Bit.count <= 112 else { return nil }
        guard verifyChecksum(prefix: prefix, payload: payload5Bit) else { return nil }
        let data5Bit = Array(payload5Bit.dropLast(8))
        guard let payloadBytes = convertBits(data: data5Bit, fromBits: 5, toBits: 8, pad: false),
            !payloadBytes.isEmpty
        else { return nil }
        return payloadBytes
    }

    /// Version byte per CashAddr: MSB must be 0, type must be P2PKH (0) or P2SH (1), and the
    /// encoded hash length must match the declared size code.
    private static func headerValid(_ payloadBytes: [UInt8]) -> Bool {
        let version = payloadBytes[0]
        guard (version & 0x80) == 0 else { return false }
        let type = (version >> 3) & 0x0f
        guard type == 0 || type == 1 else { return false }
        guard let expectedHashSize = hashSizes[version & 0x07] else { return false }
        return payloadBytes.count - 1 == expectedHashSize
    }

    // MARK: - CashAddr Bit Conversion & Checksum

    private static func isValidLegacyBase58(_ address: String, expectedPrefix: String) -> Bool {
        guard expectedPrefix == "bitcoincash",
            (address.hasPrefix("1") || address.hasPrefix("3"))
                && address.count >= 26 && address.count <= 35 else { return false }
        return MiningInsightsAddress.validated(address) != nil
    }

    /// Decodes the base32 payload using the CashAddr charset: qpzry9x8gf2tvdw0s3jn54khce6mua7l
    private static func decodeBase32Payload(_ payloadString: String) -> [UInt8]? {
        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8)
        var payload5Bit: [UInt8] = []
        payload5Bit.reserveCapacity(payloadString.utf8.count)

        for char in payloadString.utf8 {
            guard let idx = charset.firstIndex(of: char) else { return nil }
            payload5Bit.append(UInt8(idx))
        }
        return payload5Bit
    }

    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1
        let maxAcc = (1 << (fromBits + toBits - 1)) - 1

        for value in data {
            if Int(value) < 0 || (Int(value) >> fromBits) != 0 { return nil }
            acc = ((acc << fromBits) | Int(value)) & maxAcc
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else {
            // Padding bits must be 0 and less than fromBits
            if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
                return nil
            }
        }
        return result
    }

    private static func prefixExpand(_ prefix: String) -> [UInt8] {
        var result: [UInt8] = []
        for char in prefix.utf8 {
            result.append(char & 0x1f)
        }
        result.append(0)
        return result
    }

    private static func polymod(_ values: [UInt8]) -> UInt64 {
        var checksum: UInt64 = 1
        for chunk in values {
            let highBits = UInt8(checksum >> 35)
            checksum = ((checksum & 0x07ffffffff) << 5) ^ UInt64(chunk)
            if (highBits & 0x01) != 0 { checksum ^= 0x98f2bc8e61 }
            if (highBits & 0x02) != 0 { checksum ^= 0x79b76d99e2 }
            if (highBits & 0x04) != 0 { checksum ^= 0xf33e5fb3c4 }
            if (highBits & 0x08) != 0 { checksum ^= 0xae2eabe2a8 }
            if (highBits & 0x10) != 0 { checksum ^= 0x1e4f43e470 }
        }
        return checksum ^ 1
    }

    private static func verifyChecksum(prefix: String, payload: [UInt8]) -> Bool {
        let expanded = prefixExpand(prefix)
        let combined = expanded + payload
        return polymod(combined) == 0
    }
}
