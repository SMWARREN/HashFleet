import Foundation

/// Limits shared by the store and the setup transfer.
public enum WatchFleetLimits {
    /// Maximum number of unique miner endpoints kept on the Watch.
    public static let maximumMiners = 16
    /// Maximum length of a miner display name.
    public static let maximumNameLength = 48
}

/// Why a miner name or address was rejected. Messages are safe to show directly in the UI.
public enum WatchMinerValidationError: Error, Equatable, Sendable, LocalizedError {
    case emptyName
    case nameTooLong
    case invalidName
    case emptyAddress
    case malformedAddress
    case unsupportedScheme
    case credentialsNotAllowed
    case pathNotAllowed
    case invalidPort
    case notLocalAddress

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name for this miner."
        case .nameTooLong: "Use a shorter name (up to \(WatchFleetLimits.maximumNameLength) characters)."
        case .invalidName: "The name can't contain control characters."
        case .emptyAddress: "Enter the miner's local address, like 192.168.1.50."
        case .malformedAddress: "That address isn't valid. Try something like 192.168.1.50."
        case .unsupportedScheme: "Only http:// and https:// addresses are supported."
        case .credentialsNotAllowed: "Remove the user name or password from the address."
        case .pathNotAllowed: "Use just the miner's address, without a path, query or fragment."
        case .invalidPort: "The port must be a number from 1 to 65535."
        case .notLocalAddress: "Only local network addresses work, like 192.168.x.x, 10.x.x.x, 172.16-31.x.x or a .local name."
        }
    }
}

/// A miner stored on the Watch.
///
/// The address is validated and normalized to `scheme://host[:port]` with the default port and any root slash
/// removed. Only private IPv4 addresses, unqualified host names and `.local` names are allowed.
public struct WatchMiner: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    /// Normalized, credential-free endpoint such as `http://192.168.1.50` or `http://miner.local:8080`.
    public let address: String

    public init(id: UUID = UUID(), name: String, address: String) throws {
        self.id = id
        self.name = try WatchEndpoint.normalizedName(name)
        self.address = try WatchEndpoint.normalize(address).description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, address
    }

    /// Decoding revalidates, so a damaged or hostile payload can never produce an unsafe miner.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let address = try container.decode(String.self, forKey: .address)
        do {
            try self.init(id: id, name: name, address: address)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid miner.")
            )
        }
    }
}

/// A parsed, normalized miner endpoint.
struct WatchEndpoint: Equatable, Sendable, CustomStringConvertible {
    enum Scheme: String, Sendable {
        case http, https

        var defaultPort: Int { self == .http ? 80 : 443 }
    }

    let scheme: Scheme
    let host: String
    let port: Int?

    var description: String {
        let portPart = port.map { ":\($0)" } ?? ""
        return "\(scheme.rawValue)://\(host)\(portPart)"
    }

    static func normalizedName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WatchMinerValidationError.emptyName }
        guard name.count <= WatchFleetLimits.maximumNameLength else { throw WatchMinerValidationError.nameTooLong }
        let forbidden = CharacterSet.controlCharacters.union(.newlines)
        guard name.unicodeScalars.allSatisfy({ !forbidden.contains($0) }) else {
            throw WatchMinerValidationError.invalidName
        }
        return name
    }

    static func normalize(_ raw: String) throws -> WatchEndpoint {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw WatchMinerValidationError.emptyAddress }
        guard text.utf8.count <= 255, text.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 0x20 && $0.value < 0x7f }) else {
            throw WatchMinerValidationError.malformedAddress
        }

        var scheme = Scheme.http
        var rest = Substring(text)
        if let range = rest.range(of: "://") {
            switch rest[..<range.lowerBound].lowercased() {
            case "http": scheme = .http
            case "https": scheme = .https
            default: throw WatchMinerValidationError.unsupportedScheme
            }
            rest = rest[range.upperBound...]
        }

        // Credentials, encodings and other URL syntax are rejected rather than interpreted.
        if rest.contains("@") { throw WatchMinerValidationError.credentialsNotAllowed }
        if rest.contains(where: { "?#".contains($0) }) { throw WatchMinerValidationError.pathNotAllowed }
        if rest.contains(where: { "\\%[]".contains($0) }) { throw WatchMinerValidationError.malformedAddress }

        let authority: Substring
        if let slash = rest.firstIndex(of: "/") {
            authority = rest[..<slash]
            guard rest[slash...] == "/" else { throw WatchMinerValidationError.pathNotAllowed }
        } else {
            authority = rest
        }
        guard !authority.isEmpty else { throw WatchMinerValidationError.malformedAddress }

        let pieces = authority.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard pieces.count <= 2 else { throw WatchMinerValidationError.malformedAddress }
        let host = pieces[0].lowercased()
        var port: Int?
        if pieces.count == 2 {
            let digits = pieces[1]
            guard !digits.isEmpty, digits.count <= 5, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(digits), (1...65_535).contains(value)
            else { throw WatchMinerValidationError.invalidPort }
            port = value == scheme.defaultPort ? nil : value
        }

        try validateLocalHost(host)
        return WatchEndpoint(scheme: scheme, host: host, port: port)
    }

    private static func validateLocalHost(_ host: String) throws {
        guard !host.isEmpty else { throw WatchMinerValidationError.malformedAddress }
        // Anything made only of digits and dots must be a strict private dotted quad.
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            guard let octets = strictIPv4(host) else { throw WatchMinerValidationError.notLocalAddress }
            guard isPrivate(octets) else { throw WatchMinerValidationError.notLocalAddress }
            return
        }
        guard host.count <= 253 else { throw WatchMinerValidationError.malformedAddress }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy(isValidLabel) else { throw WatchMinerValidationError.malformedAddress }
        guard labels.first != "localhost" else { throw WatchMinerValidationError.notLocalAddress }
        if labels.count == 1 {
            // A leading digit could be read by the resolver as an obfuscated IPv4 (for example 0x7f).
            guard let first = host.first, first.isLetter else { throw WatchMinerValidationError.notLocalAddress }
            return
        }
        guard labels.count >= 2, labels.last == "local" else { throw WatchMinerValidationError.notLocalAddress }
    }

    private static func isValidLabel(_ label: Substring) -> Bool {
        guard (1...63).contains(label.count), label.first != "-", label.last != "-" else { return false }
        return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    private static func strictIPv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [Int] = []
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part == "0" || part.first != "0", let value = Int(part), value <= 255
            else { return nil }
            octets.append(value)
        }
        return octets
    }

    private static func isPrivate(_ octets: [Int]) -> Bool {
        switch (octets[0], octets[1]) {
        case (10, _): true
        case (172, 16...31): true
        case (192, 168): true
        default: false
        }
    }
}
