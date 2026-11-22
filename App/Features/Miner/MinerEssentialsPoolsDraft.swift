import Foundation
import HashFleetCore

/// The two ordinary firmware roles, not the positions in the reported array.
enum MinerPoolRole: String, CaseIterable, Identifiable {
    case primary, fallback

    var id: Self { self }
    var title: String { self == .primary ? "Primary pool" : "Fallback pool" }
    var indexKey: String { self == .primary ? "primaryPoolIndex" : "secondaryPoolIndex" }
    var prefix: String { self == .primary ? "stratum" : "fallbackStratum" }

    var other: Self { self == .primary ? .fallback : .primary }
}

struct MinerPoolConnection: Equatable {
    var server: String
    var port: String
    var worker: String

    init(_ fields: [String: JSONValue], prefix: String) {
        server = fields[prefix + "URL"]?.stringValue ?? ""
        port = fields[prefix + "Port"]?.intValue.flatMap { $0 > 0 ? String($0) : nil } ?? ""
        worker = fields[prefix + "User"]?.stringValue ?? ""
    }

    var address: String {
        guard !server.isEmpty else { return "Not configured" }
        guard !port.isEmpty else { return server }
        let host = server.contains(":") && !server.hasPrefix("[") ? "[\(server)]" : server
        return "\(host):\(port)"
    }
}

/// A snapshot suitable for constructing or checking a single reviewed settings write.
/// Never retain plaintext passwords from Info, and never infer an assignment or missing advanced field.
struct MinerEssentialsPoolBaseline: Equatable {
    static let keepPassword = "*****"
    private static let connectionSuffixes = ["URL", "Port", "User"]
    private static let modernRequired: Set<String> = [
        "id", "stratumURL", "stratumPort", "stratumUser", "stratumPassword", "stratumProtocol",
        "stratumSuggestedDifficulty", "stratumExtranonceSubscribe", "stratumTLS", "stratumCert",
        "stratumDecodeCoinbase", "stratumShareWarning", "stratumV2ChannelType",
        "stratumV2AuthorityPubkey", "stratumV2RequireAuth"
    ]
    private static let rotationKeys: Set<String> = ["rotationEnabled", "rotationWeight"]

    let role: MinerPoolRole
    let connection: MinerPoolConnection
    private let recordID: Int?
    private let otherRole: JSONValue?
    private let fields: [String: JSONValue]

    static func reportedConnection(_ role: MinerPoolRole, raw: [String: JSONValue]) -> MinerPoolConnection? {
        if let id = raw[role.indexKey].flatMap(exactInteger),
           let record = raw["pools"]?.arrayValue?.first(where: { $0["id"].flatMap(exactInteger) == id })?.objectValue {
            return .init(record, prefix: "stratum")
        }
        guard case .string? = raw[role.prefix + "URL"] else { return nil }
        return .init(raw, prefix: role.prefix)
    }

    init?(role: MinerPoolRole, raw: [String: JSONValue]) {
        self.role = role
        if raw["pools"] != nil || raw[MinerPoolRole.primary.indexKey] != nil
            || raw[MinerPoolRole.fallback.indexKey] != nil || raw["activePoolIndex"] != nil {
            guard let pools = raw["pools"]?.arrayValue,
                  let target = raw[role.indexKey].flatMap(Self.exactInteger), target >= 0,
                  let otherRole = raw[role.other.indexKey],
                  let otherID = Self.exactInteger(otherRole), target != otherID else { return nil }
            let ids = pools.compactMap { $0["id"].flatMap(Self.exactInteger) }
            guard ids.count == pools.count, Set(ids).count == ids.count,
                  let record = pools.first(where: { $0["id"].flatMap(Self.exactInteger) == target })?.objectValue,
                  Self.knownRecord(record) else { return nil }
            self.recordID = target
            self.otherRole = otherRole
            var safeRecord = record
            safeRecord["stratumPassword"] = .string(Self.keepPassword)
            self.fields = safeRecord
            self.connection = .init(safeRecord, prefix: "stratum")
        } else {
            let prefix = role.prefix
            guard case .string? = raw[prefix + "URL"], let port = raw[prefix + "Port"].flatMap(Self.exactInteger),
                  (0...65535).contains(port), case .string? = raw[prefix + "User"] else { return nil }
            self.recordID = nil
            self.otherRole = nil
            self.fields = raw.filter { $0.key.hasPrefix(prefix) && !$0.key.lowercased().contains("password") }
            self.connection = .init(raw, prefix: prefix)
        }
    }

    private static func exactInteger(_ value: JSONValue) -> Int? {
        switch value {
        case .integer, .unsignedInteger, .number: value.doubleValue.flatMap(Int.init(exactly:))
        default: nil
        }
    }

    private static func knownRecord(_ fields: [String: JSONValue]) -> Bool {
        let keys = Set(fields.keys)
        guard keys == modernRequired || keys == modernRequired.union(rotationKeys),
              let port = fields["stratumPort"].flatMap(exactInteger), (1...65535).contains(port),
              let tls = fields["stratumTLS"].flatMap(exactInteger), (0...2).contains(tls),
              case .string(let server)? = fields["stratumURL"], !server.isEmpty,
              case .string(let worker)? = fields["stratumUser"], !worker.isEmpty,
              let protocolName = fields["stratumProtocol"]?.stringValue, ["SV1", "SV2"].contains(protocolName),
              let difficulty = fields["stratumSuggestedDifficulty"]?.doubleValue,
              (0...1e18).contains(difficulty) else { return false }
        for key in ["stratumCert", "stratumPassword", "stratumV2ChannelType", "stratumV2AuthorityPubkey"] {
            guard case .string? = fields[key] else { return false }
        }
        for key in ["stratumExtranonceSubscribe", "stratumDecodeCoinbase", "stratumShareWarning", "stratumV2RequireAuth"] {
            guard case .bool? = fields[key] else { return false }
        }
        if !keys.isDisjoint(with: rotationKeys) {
            guard case .bool? = fields["rotationEnabled"],
                  let weight = fields["rotationWeight"].flatMap(exactInteger), weight > 0 else { return false }
        }
        return true
    }

    func plan(for draft: MinerPoolConnection, password: String) throws -> MinerEssentialsPoolChange? {
        let server = draft.server == connection.server ? connection.server : draft.server.trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = draft.port.trimmingCharacters(in: .whitespacesAndNewlines)
        let worker = draft.worker == connection.worker ? connection.worker : draft.worker.trimmingCharacters(in: .whitespacesAndNewlines)
        if server != connection.server, !Self.isHost(server) { throw FormError.server }
        guard let port = Int(portText), (1...65535).contains(port),
              portText.utf8.allSatisfy({ (48...57).contains($0) }) else { throw FormError.port }
        guard !server.isEmpty else { throw FormError.server }
        guard Self.isCredential(worker), !worker.isEmpty else { throw FormError.worker }
        guard Self.isCredential(password), password != Self.keepPassword else { throw FormError.password }
        guard !needsPassword(for: server) || !password.isEmpty else { throw FormError.newPassword }

        let updated = [JSONValue.string(server), .integer(Int64(port)), .string(worker)]
        let previous = [connection.server, connection.port, connection.worker]
        let values = [server, String(port), worker]
        let selected = Self.connectionSuffixes.indices.filter { previous[$0] != values[$0] }
        guard !selected.isEmpty || !password.isEmpty else { return nil }
        let prefix = recordID == nil ? role.prefix : "stratum"
        let changes = Dictionary(uniqueKeysWithValues: selected.map { (prefix + Self.connectionSuffixes[$0], updated[$0]) })
        let passwordChange = password.isEmpty ? [:] : [prefix + "Password": JSONValue.string(password)]
        let entries = changes.merging(passwordChange) { _, new in new }
        let payload: JSONValue
        if recordID != nil {
            payload = .object(["pools": .array([.object(fields.merging(entries) { _, new in new })])])
        } else {
            payload = .object(entries)
        }
        return .init(baseline: self, payload: payload, expected: fields.merging(changes) { _, new in new },
                     address: MinerPoolConnection(Dictionary(uniqueKeysWithValues: zip(Self.connectionSuffixes.map { prefix + $0 }, updated)), prefix: prefix).address,
                     changesWorker: selected.contains(2), changesPassword: !password.isEmpty,
                     changesConnection: !selected.isEmpty)
    }

    func needsPassword(for server: String) -> Bool {
        guard server != connection.server else { return false }
        return server.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(connection.server.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
    }

    func matches(_ change: MinerEssentialsPoolChange, raw: [String: JSONValue]) -> Bool {
        guard let current = Self(role: role, raw: raw) else { return false }
        return current.recordID == recordID && current.otherRole == otherRole && current.fields == change.expected
    }

    private static func isCredential(_ value: String) -> Bool {
        value.utf8.count <= 255 && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func isHost(_ value: String) -> Bool {
        if value.utf8.count > 253 || value.isEmpty { return false }
        let host = value.hasSuffix(".") ? value.dropLast() : value[...]
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return !labels.isEmpty && labels.allSatisfy { part in
            !part.isEmpty && part.utf8.count <= 63 && part.first != "-" && part.last != "-"
                && part.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
        }
    }

    enum FormError: LocalizedError {
        case server, port, worker, password, newPassword

        var errorDescription: String? {
            switch self {
            case .server: "Enter a hostname or IPv4 address without a prefix, path, or port."
            case .port: "Enter a port from 1 to 65535."
            case .worker: "Enter a worker name or wallet of up to 255 bytes, without line breaks."
            case .password: "Enter a password of up to 255 bytes, without line breaks or the placeholder *****."
            case .newPassword: "Enter the new server’s password or the placeholder your pool specifies."
            }
        }
    }
}

struct MinerEssentialsPoolChange {
    let baseline: MinerEssentialsPoolBaseline
    let payload: JSONValue
    fileprivate let expected: [String: JSONValue]
    let address: String
    let changesWorker: Bool
    let changesPassword: Bool
    let changesConnection: Bool
}
