import Foundation
import Security

/// Stores XMRig bearer tokens outside UserDefaults and the persisted miner model.
/// `MinerDevice` keeps only the opaque account reference returned by this store.
enum MinerCredentialStore {
    private static let service = "app.hashfleet.xmrig-api"

    static func save(token: String, reference: String = UUID().uuidString) throws -> String {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return reference }
        let data = Data(value.utf8)
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
        SecItemDelete(key as CFDictionary)
        var item = key
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw MinerCredentialError.keychain(status) }
        return reference
    }

    static func token(for reference: String?) -> String? {
        guard let reference, !reference.isEmpty else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(reference: String?) {
        guard let reference, !reference.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum MinerCredentialError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain:
            "The XMRig access token could not be stored securely."
        }
    }
}
