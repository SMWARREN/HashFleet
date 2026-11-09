import Foundation

/// Validates mainnet DigiByte (DGB) Base58Check and SegWit Bech32 addresses locally.
/// This is path validation for a deliberate public lookup, not wallet ownership verification.
public enum DigiByteAddress {
    public static func validated(_ input: String) -> String? {
        let address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (14...90).contains(address.utf8.count), address.utf8.allSatisfy({ $0 < 128 }) else { return nil }
        if address.lowercased().hasPrefix("dgb1") {
            return validSegwit(address) ? address.lowercased() : nil
        }
        return validBase58(address) ? address : nil
    }

    /// DGB mainnet: version byte 0x1e (30) for P2PKH ("D" prefix), 0x3f (63) for P2SH ("S" prefix).
    private static func validBase58(_ address: String) -> Bool {
        guard (26...35).contains(address.count), address.first == "D" || address.first == "S" else { return false }
        return CryptoAddressValidator.isValidBase58(address, validVersionBytes: [30, 63])
    }

    /// DigiByte SegWit: "dgb1" human-readable prefix with Bech32/Bech32m encoding.
    private static func validSegwit(_ address: String) -> Bool {
        CryptoAddressValidator.isValidSegwit(address, hrp: "dgb")
    }
}
