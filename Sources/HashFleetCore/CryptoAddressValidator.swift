import CryptoKit
import Foundation

/// Shared local validation logic for Base58Check and SegWit addresses.
enum CryptoAddressValidator {
    static func isValidBase58(_ address: String, validVersionBytes: Set<UInt8>) -> Bool {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
        var bytes = [UInt8]()
        for character in address.utf8 {
            guard let digit = alphabet.firstIndex(of: character) else { return false }
            var carry = digit
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 255)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 255))
                carry >>= 8
            }
        }
        let leadingZeros = address.utf8.prefix(while: { $0 == 49 }).count
        let decoded = Array(repeating: UInt8(0), count: leadingZeros) + bytes.reversed()
        guard decoded.count == 25, validVersionBytes.contains(decoded[0]) else { return false }
        let payload = Data(decoded.prefix(21))
        let checksum = SHA256.hash(data: Data(SHA256.hash(data: payload)))
        return decoded.suffix(4).elementsEqual(checksum.prefix(4))
    }

    static func isValidSegwit(_ address: String, hrp: String) -> Bool {
        guard address == address.lowercased() || address == address.uppercased() else { return false }
        let text = address.lowercased()
        let prefix = hrp + "1"
        guard text.hasPrefix(prefix) else { return false }
        let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8)
        var values = [UInt8]()
        for character in text.utf8.dropFirst(prefix.utf8.count) {
            guard let value = alphabet.firstIndex(of: character) else { return false }
            values.append(UInt8(value))
        }
        guard values.count >= 7, let version = values.first, version <= 16 else { return false }
        let hrpBytes = Array(hrp.utf8)
        let expanded = hrpBytes.map { $0 >> 5 } + [0] + hrpBytes.map { $0 & 31 }
        let checksum = polymod(expanded + values)
        guard checksum == (version == 0 ? 1 : 0x2bc830a3) else { return false }
        var accumulator: UInt32 = 0
        var bitCount = 0
        var program = [UInt8]()
        for value in values.dropFirst().dropLast(6) {
            accumulator = ((accumulator << 5) | UInt32(value)) & 0xfff
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                program.append(UInt8((accumulator >> bitCount) & 255))
            }
        }
        guard bitCount < 5, (accumulator << (8 - bitCount)) & 255 == 0,
              (2...40).contains(program.count) else { return false }
        return version != 0 || program.count == 20 || program.count == 32
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let generators: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = ((checksum & 0x1ffffff) << 5) ^ UInt32(value)
            for index in 0..<5 where (top >> index) & 1 != 0 {
                checksum ^= generators[index]
            }
        }
        return checksum
    }
}
