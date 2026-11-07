import Foundation

/// Validates mainnet Base58Check and SegWit Bech32/Bech32m addresses locally.
/// This is path validation for a deliberate public lookup, not wallet ownership verification.
public enum MiningInsightsAddress {
    public static func validated(_ input: String) -> String? {
        let address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (14...90).contains(address.utf8.count), address.utf8.allSatisfy({ $0 < 128 }) else { return nil }
        if address.lowercased().hasPrefix("bc1") {
            return validSegwit(address) ? address.lowercased() : nil
        }
        return validBase58(address) ? address : nil
    }

    private static func validBase58(_ address: String) -> Bool {
        guard (26...35).contains(address.count), address.first == "1" || address.first == "3" else { return false }
        return CryptoAddressValidator.isValidBase58(address, validVersionBytes: [0, 5])
    }

    private static func validSegwit(_ address: String) -> Bool {
        CryptoAddressValidator.isValidSegwit(address, hrp: "bc")
    }
}
