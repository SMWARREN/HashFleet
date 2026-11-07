import HashFleetCore
import Foundation

/// Modern firmware replaces each supplied slot even when it is nested in PATCH /api/system.
/// Preserve the complete GET schema audited in esp-miner-ref/system_api_json.c, not its
/// compatibility mirrors or guessed defaults. Passwords use the firmware's keep sentinel.
enum MinerPoolSettings {
    static let roles: [MinerSetting] = [
        .init(key: "primaryPoolIndex", title: "Primary slot", category: .pools, input: .integer(0, 7), hint: "Choose a configured slot ID shown above. This changes the preferred pool."),
        .init(key: "secondaryPoolIndex", title: "Backup slot", category: .pools, input: .integer(0, 7), hint: "Choose a configured slot ID. Editing a slot alone does not change its role.")
    ]
    static let basic: [MinerSetting] = [
        .init(key: "stratumURL", title: "Pool host", category: .pools, input: .poolHost, hint: "Hostname only. All reported TLS and advanced options are retained."),
        .init(key: "stratumPort", title: "Pool port", category: .pools, input: .integer(1, 65535), hint: "Port from 1 through 65535."),
        .init(key: "stratumUser", title: "Worker / wallet", category: .pools, input: .text, hint: "Pool username or wallet.worker. Confirm the wallet belongs to the pool's coin."),
        .init(key: "stratumPassword", title: "Pool password", category: .pools, input: .password, hint: "Type a replacement; an empty value clears it. Esc keeps the existing password."),
        .init(key: "stratumProtocol", title: "Protocol", category: .pools, input: .protocolName, hint: "SV1 or SV2. Existing TLS and SV2 authentication settings are retained.")
    ]
    static let configurationKeys: Set<String> = [
        "id", "stratumURL", "stratumPort", "stratumUser", "stratumProtocol",
        "stratumSuggestedDifficulty", "stratumExtranonceSubscribe", "stratumTLS", "stratumCert",
        "stratumDecodeCoinbase", "stratumV2ChannelType", "stratumV2AuthorityPubkey", "stratumV2RequireAuth"
    ]

    static func exactID(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .integer, .unsignedInteger, .number:
            guard let number = value.doubleValue, let id = Int(exactly: number), (0...7).contains(id) else { return nil }
            return id
        default: return nil
        }
    }

    static func slots(_ info: MinerInfo) throws -> [Int: [String: JSONValue]] {
        guard let entries = info.raw["pools"]?.arrayValue else {
            throw SettingsError.message("Pool slots were not fully reported. Refresh the miner before editing pools.")
        }
        var result: [Int: [String: JSONValue]] = [:]
        for entry in entries {
            guard let fields = entry.objectValue, let id = exactID(fields["id"]), result[id] == nil else {
                throw SettingsError.message("Pool slot IDs are missing, invalid or duplicated. No pool changes can be sent.")
            }
            result[id] = fields
        }
        return result
    }

    static func fields(slot: Int) -> [MinerSetting] {
        basic.map { item in
            MinerSetting(key: "pool:\(slot):\(item.key)", title: item.title, category: .pools, input: item.input, hint: item.hint)
        } + roles
    }

    static func location(_ key: String) -> (id: Int, field: String)? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "pool", let id = Int(parts[1]), (0...7).contains(id),
            String(id) == parts[1], basic.contains(where: { $0.key == parts[2] }) else { return nil }
        return (id, String(parts[2]))
    }

    private static func number(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .integer, .unsignedInteger, .number: return value.doubleValue
        default: return nil
        }
    }

    private static func complete(_ fields: [String: JSONValue], slot: Int) throws -> [String: JSONValue] {
        let keys = Set(fields.keys).subtracting(["stratumPassword"])
        guard keys == configurationKeys else {
            throw SettingsError.message("Slot \(slot) has missing or unfamiliar connection options. Its full configuration cannot be preserved; refresh or edit it in the miner's web interface.")
        }
        for key in ["stratumURL", "stratumPort", "stratumUser", "stratumProtocol"] {
            guard let field = basic.first(where: { $0.key == key }), let value = fields[key] else {
                throw SettingsError.message("Slot \(slot) is incomplete.")
            }
            if key == "stratumPort" {
                guard let port = number(value), (1...65535).contains(port), Int(exactly: port) != nil else {
                    throw SettingsError.message("Slot \(slot) has an invalid port.")
                }
            } else {
                guard case .string(let text) = value, !text.isEmpty, text.utf8.count <= 255 else {
                    throw SettingsError.message("Slot \(slot) has an invalid \(field.title.lowercased()).")
                }
                // Keep already-reported host strings exactly; only newly entered hosts are normalized/validated.
                if key == "stratumProtocol", !["SV1", "SV2"].contains(text) {
                    throw SettingsError.message("Slot \(slot) uses an unknown protocol.")
                }
            }
        }
        guard let difficulty = number(fields["stratumSuggestedDifficulty"]), (0...1e18).contains(difficulty),
            let tls = number(fields["stratumTLS"]), [0.0, 1, 2].contains(tls) else {
            throw SettingsError.message("Slot \(slot) has invalid difficulty or TLS settings.")
        }
        for key in ["stratumExtranonceSubscribe", "stratumDecodeCoinbase", "stratumV2RequireAuth"] {
            guard fields[key] == .bool(true) || fields[key] == .bool(false)
                || number(fields[key]) == 0 || number(fields[key]) == 1 else {
                throw SettingsError.message("Slot \(slot) has an invalid connection flag.")
            }
        }
        guard case .string(let cert) = fields["stratumCert"], cert.utf8.count <= 3000,
            case .string(let authority) = fields["stratumV2AuthorityPubkey"], authority.utf8.count <= 128,
            case .string(let channel) = fields["stratumV2ChannelType"], ["standard", "extended"].contains(channel) else {
            throw SettingsError.message("Slot \(slot) has incomplete TLS or SV2 settings.")
        }
        return fields.filter { configurationKeys.contains($0.key) }
    }

    static func payload(changes: [String: JSONValue], info: MinerInfo) throws -> [String: JSONValue] {
        var payload = changes.filter { location($0.key) == nil }
        let affected = Set(changes.keys.compactMap { location($0)?.id })
        let roleChanges = roles.filter { changes[$0.key] != nil }
        guard !affected.isEmpty || !roleChanges.isEmpty else { return payload }
        let inventory = try slots(info)
        for role in roleChanges {
            guard let id = exactID(changes[role.key]), let slot = inventory[id],
                case .string(let host) = slot["stratumURL"], !host.isEmpty,
                case .string(let worker) = slot["stratumUser"], !worker.isEmpty,
                let port = number(slot["stratumPort"]), (1...65535).contains(port), Int(exactly: port) != nil else {
                throw SettingsError.message("\(role.title) must refer to a configured slot with a host, port and worker.")
            }
        }
        var entries: [JSONValue] = []
        for id in affected.sorted() {
            guard let original = inventory[id] else { throw SettingsError.message("Slot \(id) is no longer configured. Reopen settings.") }
            var slot = try complete(original, slot: id)
            slot["stratumPassword"] = .string("*****")
            for (key, value) in changes {
                if let location = location(key), location.id == id { slot[location.field] = value }
            }
            entries.append(.object(slot))
        }
        if !entries.isEmpty { payload["pools"] = .array(entries) }
        return payload
    }

    static func checkBaseline(changes: [String: JSONValue], original: MinerInfo, fresh: MinerInfo) throws {
        var ids = Set(changes.keys.compactMap { location($0)?.id })
        for role in roles where changes[role.key] != nil {
            if let id = exactID(changes[role.key]) { ids.insert(id) }
        }
        guard !ids.isEmpty else { return }
        let before = try slots(original), now = try slots(fresh)
        for id in ids {
            // Never compare or forward a reported password. The keep sentinel preserves the latest
            // stored secret, even if another client changes it while this form is open.
            guard before[id]?.filter({ $0.key != "stratumPassword" }) == now[id]?.filter({ $0.key != "stratumPassword" }) else {
                throw SettingsError.message("Slot \(id) changed since you opened settings. Nothing was sent; reopen settings to review fresh values.")
            }
        }
    }

    static func matches(_ payload: [String: JSONValue], original: MinerInfo, readback: MinerInfo) -> Bool {
        let expected = payload["pools"]?.arrayValue ?? []
        let selectedRoles = roles.compactMap { exactID(payload[$0.key]) }
        guard !expected.isEmpty || !selectedRoles.isEmpty else { return true }
        guard let inventory = try? slots(readback) else { return false }
        let updatedIDs = Set(expected.compactMap { exactID($0["id"]) })
        if let before = try? slots(original) {
            for id in selectedRoles where !updatedIDs.contains(id) {
                guard before[id]?.filter({ $0.key != "stratumPassword" }) == inventory[id]?.filter({ $0.key != "stratumPassword" }) else { return false }
            }
        } else { return false }
        return expected.allSatisfy { entry in
            guard let values = entry.objectValue, let id = exactID(values["id"]),
                let observed = inventory[id], let configuration = try? complete(observed, slot: id) else { return false }
            return configurationKeys.allSatisfy { key in
                if let a = number(values[key]), let b = number(configuration[key]) { return a == b }
                if ["stratumExtranonceSubscribe", "stratumDecodeCoinbase", "stratumV2RequireAuth"].contains(key) {
                    return values[key]?.boolValue == configuration[key]?.boolValue
                }
                return values[key] == configuration[key]
            }
        }
    }
}
