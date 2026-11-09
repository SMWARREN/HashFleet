import Foundation
import HashFleetCore

/// Standard SV1 endpoints verified 2026-09-07 UTC against:
/// https://solo.ckpool.org/ and https://solofury.com/ and https://solofury.com/start/.
/// No rental ports, SV2 authority keys, password overrides, or executable setup scripts are inferred.
enum SoloPoolPreset: String, CaseIterable, Identifiable, Hashable, Sendable {
    case ckPoolBTC, soloFuryBTC, soloFuryBCH, soloFuryBC2, soloFuryBCH2, soloFuryXEC
    case soloPoolDGB

    var id: String { rawValue }
    var coin: String {
        switch self {
        case .ckPoolBTC, .soloFuryBTC: "BTC"
        case .soloFuryBCH: "BCH"
        case .soloFuryBC2: "BC2"
        case .soloFuryBCH2: "BCH2"
        case .soloFuryXEC: "XEC"
        case .soloPoolDGB: "DGB"
        }
    }
    var title: String {
        let provider: String
        switch self {
        case .ckPoolBTC: provider = "CKPool"
        case .soloPoolDGB: provider = "SoloPool"
        default: provider = "SoloFury"
        }
        return "\(provider) · \(coin)"
    }
    var server: String {
        switch self {
        case .ckPoolBTC: "stratum.ckpool.org"
        case .soloFuryBTC: "btc.solofury.com"
        case .soloFuryBCH: "bch.solofury.com"
        case .soloFuryBC2: "bc2.solofury.com"
        case .soloFuryBCH2: "bch2.solofury.com"
        case .soloFuryXEC: "xec.solofury.com"
        case .soloPoolDGB: "us1.solopool.org"
        }
    }
    var port: Int {
        switch self {
        case .ckPoolBTC: 3333
        case .soloFuryBTC: 6060
        case .soloFuryBCH: 7070
        case .soloFuryBC2: 8080
        case .soloFuryBCH2: 8585
        case .soloFuryXEC: 9090
        case .soloPoolDGB: 8004
        }
    }
    var stratumProtocol: String { "SV1" }
    var documentationURL: URL {
        switch self {
        case .ckPoolBTC:
            URL(string: "https://solo.ckpool.org/")!
        case .soloPoolDGB:
            URL(string: "https://dgb-sha.solopool.org/help")!
        default:
            URL(string: "https://solofury.com/start/")!
        }
    }

    /// Local fields only. Even a same-coin change of provider clears the old address deliberately.
    func draft(previousPreset: SoloPoolPreset?, user: String) -> SoloPoolPresetFields {
        SoloPoolPresetFields(
            server: server,
            port: String(port),
            stratumProtocol: stratumProtocol,
            user: previousPreset == self ? user : ""
        )
    }
}

struct SoloPoolPresetFields: Hashable, Sendable {
    let server: String
    let port: String
    let stratumProtocol: String
    let user: String
}

struct SoloPoolConfiguredSlot: Identifiable, Hashable, Sendable {
    let id: Int
    let serverLabel: String
    let roleLabel: String
    let coin: MiningPoolCoin?
}

/// Reads reported IDs only. It never retains usernames/passwords or mutates MinerInfo.
struct SoloPoolSlotInventory: Hashable, Sendable {
    enum Availability: Hashable, Sendable { case available(Int), full, unknown }
    let slots: [SoloPoolConfiguredSlot]
    let availability: Availability

    var firstEmptySlot: Int? {
        if case .available(let id) = availability { return id }
        return nil
    }

    init(raw: [String: JSONValue]?) {
        guard let raw, let values = raw["pools"]?.arrayValue else {
            slots = []
            availability = .unknown
            return
        }
        let primary = Self.slotID(raw["primaryPoolIndex"])
        let secondary = Self.slotID(raw["secondaryPoolIndex"])
        let resolved = ConfiguredMiningPool.resolve(info: MinerInfo(raw: raw))
        let activeID = resolved.first(where: { $0.isActive == true })?.id
        var occupied = Set<Int>()
        var rows: [SoloPoolConfiguredSlot] = []
        var valid = true
        for value in values {
            guard let object = value.objectValue, let id = Self.slotID(object["id"]),
                occupied.insert(id).inserted
            else { valid = false; continue }
            var roles: [String] = []
            if primary == id { roles.append("Primary") }
            if secondary == id { roles.append("Fallback") }
            if activeID == "slot-\(id)" {
                roles.append("in use")
            }
            let roleLabel =
                roles.isEmpty
                ? "Saved configuration"
                : roles.joined(separator: " \u{00B7} ")
            rows.append(
                SoloPoolConfiguredSlot(
                    id: id,
                    serverLabel: Self.serverLabel(object["stratumURL"] ?? object["url"]),
                    roleLabel: roleLabel,
                    coin: resolved.first(where: { $0.id == "slot-\(id)" })?.coin
                )
            )
        }
        Self.updateOccupiedAndValid(
            raw: raw,
            primary: primary,
            secondary: secondary,
            valid: &valid,
            occupied: &occupied
        )
        slots = rows.sorted { $0.id < $1.id }
        availability = Self.determineAvailability(valid: valid, occupied: occupied)
    }

    private static func updateOccupiedAndValid(
        raw: [String: JSONValue],
        primary: Int?,
        secondary: Int?,
        valid: inout Bool,
        occupied: inout Set<Int>
    ) {
        // Never auto-select a missing but explicitly assigned primary/fallback slot for replacement.
        if raw["primaryPoolIndex"] != nil, primary == nil {
            valid = false
        }
        if raw["secondaryPoolIndex"] != nil, secondary == nil {
            valid = false
        }
        if let primary { occupied.insert(primary) }
        if let secondary { occupied.insert(secondary) }
    }

    private static func determineAvailability(valid: Bool, occupied: Set<Int>) -> Availability {
        if !valid {
            return .unknown
        } else if let empty = (0...7).first(where: {
            !occupied.contains($0)
        }) {
            return .available(empty)
        } else {
            return .full
        }
    }

    private static func slotID(_ value: JSONValue?) -> Int? {
        guard let number = value?.doubleValue,
            let integer = Int(exactly: number),
            (0...7).contains(integer)
        else { return nil }
        return integer
    }

    private static func serverLabel(_ value: JSONValue?) -> String {
        guard case .string(let text) = value, !text.isEmpty else { return "Server not reported" }
        let source = text.contains("://") ? text : "stratum+tcp://" + text
        guard let host = URLComponents(string: source)?.host, !host.isEmpty else { return "Configured server" }
        // Never show embedded userinfo, query, path, or a pool password from telemetry.
        return host
    }
}
