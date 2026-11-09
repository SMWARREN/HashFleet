import Foundation

public struct MinerDevice: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case espMiner
        case xmrig
    }

    public var id: UUID
    public var name: String
    public var address: String
    public var kind: Kind
    /// Nil preserves compatibility with saved fleets created before local naming preferences.
    public var usesAutomaticName: Bool?

    /// Optional reference to a credential stored securely in the Keychain.
    /// Token data should never be stored directly in this struct.
    public var keychainCredentialReference: String?

    public init(id: UUID = UUID(), name: String, address: String, kind: Kind = .espMiner, usesAutomaticName: Bool? = nil, keychainCredentialReference: String? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.kind = kind
        self.usesAutomaticName = usesAutomaticName
        self.keychainCredentialReference = keychainCredentialReference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.address = try container.decode(String.self, forKey: .address)
        self.kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .espMiner
        self.usesAutomaticName = try container.decodeIfPresent(Bool.self, forKey: .usesAutomaticName)
        self.keychainCredentialReference = try container.decodeIfPresent(String.self, forKey: .keychainCredentialReference)
    }

    /// Accepts host-only addresses, optionally with HTTP(S), a port and a root slash.
    /// Never resolves the hostname or probes the device. IPv6 literals must use brackets.
    public func validatedURL() throws -> URL {
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = input.contains("://") ? input : "http://" + input
        guard !input.isEmpty,
            !input.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)
            }),
            !input.contains("\\"), !input.contains("%"),
            var components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil,
            components.path.isEmpty || components.path == "/",
            let host = components.host, !host.isEmpty,
            components.port.map({ (1...65_535).contains($0) }) ?? true,
            Self.isValidHost(host)
        else {
            throw MinerAPIError.invalidAddress(address)
        }
        // URLComponents permits empty ports, which are not intentional host-only input.
        let authority =
            candidate.components(separatedBy: "://").last?.split(separator: "/", omittingEmptySubsequences: false)
            .first ?? ""
        guard !authority.hasSuffix(":") else { throw MinerAPIError.invalidAddress(address) }
        components.scheme = scheme
        components.host = host.lowercased()
        if (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        components.path = ""
        guard let url = components.url else { throw MinerAPIError.invalidAddress(address) }
        return url
    }

    private static func isValidHost(_ host: String) -> Bool {
        if host.hasPrefix("[") && host.hasSuffix("]") {
            return isIPv6(String(host.dropFirst().dropLast()))
        }
        guard !host.contains(":"), host.utf8.count <= 253 else { return false }
        let normalized = host.hasSuffix(".") ? String(host.dropLast()) : host
        if normalized.allSatisfy({ $0.isNumber || $0 == "." }) { return isIPv4(normalized) }
        return normalized.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy {
                    (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
                }
        }
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4
            && parts.allSatisfy { part in
                !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) } && part.count <= 3
                    && (part.count == 1 || part.first != "0") && Int(part).map { (0...255).contains($0) } == true
            }
    }

    private static func isIPv6(_ host: String) -> Bool {
        guard host.contains(":"), !host.contains(":::") else { return false }
        let compressed = host.components(separatedBy: "::")
        guard compressed.count <= 2 else { return false }
        if compressed.count == 1 && (host.hasPrefix(":") || host.hasSuffix(":")) { return false }
        let parts = host.split(separator: ":", omittingEmptySubsequences: true)
        var count = 0
        for (index, part) in parts.enumerated() {
            if part.contains(".") {
                guard index == parts.count - 1, !host.hasSuffix(":"), isIPv4(String(part)) else { return false }
                count += 2
            } else {
                guard part.count <= 4,
                    part.utf8.allSatisfy({
                        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                    })
                else { return false }
                count += 1
            }
        }
        return compressed.count == 2 ? count < 8 : count == 8
    }
}
