import Foundation

/// Owner-supplied GET inventory, not a discovery probe or an assertion of support.
public enum HarloReadEndpoint: String, CaseIterable, Sendable {
    case info, telemetry, network, pools, fleet, logs

    public var path: String { "/api/" + rawValue }
}

/// Identity evidence applies only to the configured profile. A match is not authentication.
public enum HarloIdentity: Equatable, Sendable {
    case unconfirmed, matchesConfiguredProfile
}

/// Local configuration, NOT a Harlo wire schema. Use only with independently established
/// `/api/info` fields for the target firmware. No profile is installed by default. Values from
/// the response cannot select URLs or field paths, and are never exposed to the caller.
public struct HarloInfoProfile: Sendable {
    public struct Field: Sendable {
        public let keys: [String]
        public let equals: JSONValue

        public init(keys: [String], equals: JSONValue) throws {
            guard !keys.isEmpty, keys.allSatisfy({ !$0.isEmpty }) else { throw HarloReadError.invalidPolicy }
            switch equals {
            case .string(let value) where !value.isEmpty: break
            case .bool(true): break
            case .integer(let version) where (1...65_535).contains(version): break
            default: throw HarloReadError.invalidPolicy
            }
            self.keys = keys
            self.equals = equals
        }

        fileprivate func matches(_ root: JSONValue) -> Bool {
            keys.reduce(Optional(root)) { value, key in value?.objectValue?[key] } == equals
        }
    }

    private let identity: [Field]
    private let advertisements: [HarloReadEndpoint: Field]

    /// All identity discriminators must match. Optional routes also require their own positive
    /// advertisement from this target. A route inventory, mere key presence or 200 is not enough.
    public init(identity: [Field], advertisements: [HarloReadEndpoint: Field]) throws {
        guard !identity.isEmpty, identity.allSatisfy({ if case .string = $0.equals { true } else { false } }),
              advertisements[.info] == nil,
              advertisements.values.allSatisfy({ ad in !identity.contains(where: { $0.keys == ad.keys }) })
        else { throw HarloReadError.invalidPolicy }
        self.identity = identity
        self.advertisements = advertisements
    }

    /// Opt-in match for the original Gamma 601 factory firmware 0.2.101. The captured
    /// `fleet_api_version: 1` advertises fleet API v1 only. The other successful GETs did
    /// not have route advertisements. Do not infer them from the board, build or HTTP 200.
    /// Evidence: Tools/virtual-miners/evidence/harlo-gamma601.md, receipt 30116217jw.
    public static let gamma601V02101: Self = {
        do {
            return try Self(identity: [
                Field(keys: ["firmware"], equals: .string("Harlo-OS-V2")),
                Field(keys: ["version"], equals: .string("0.2.101")),
                Field(keys: ["profile", "id"], equals: .string("bitaxe-gamma-601"))
            ], advertisements: [.fleet: Field(keys: ["fleet_api_version"], equals: .integer(1))])
        } catch {
            preconditionFailure("Invalid built-in Gamma 601 profile")
        }
    }()

    func interpret(_ root: JSONValue) -> (HarloIdentity, Set<HarloReadEndpoint>) {
        guard identity.allSatisfy({ $0.matches(root) }) else { return (.unconfirmed, []) }
        return (.matchesConfiguredProfile, Set(advertisements.compactMap { $1.matches(root) ? $0 : nil }))
    }
}

/// Privacy-preserving projections, not response bodies. Nil is unknown, never a fake zero.
/// An HTTP success alone does not promote a missing measurement to a valid reading.
public enum HarloReadResult: Equatable, Sendable {
    case info(identity: HarloIdentity, advertised: Set<HarloReadEndpoint>)
    case telemetry(hashrateGHs: Double?, powerW: Double?, asicTemperatureC: Double?)
    case network(interfaceCount: Int?)
    case pools(entryCount: Int?)
    /// An opaque group summary, not MinerDevices, candidate hosts or a list of probe targets.
    case fleet(reportedEntryCount: Int?)
    /// No log bytes, even when the response is non-JSON, binary or an unfamiliar shape.
    case logsWithheld
}

// Static consumer evidence, not a device capture: in the HarloLabs bitaxe-gamma-601 0.2.101
// OTA (SHA-256 74a9c0b3f8f4bd75839d0309be08f7836fd4a4f10840fa2cdd887e6b4555b627),
// dashboard JS assigns /api/telemetry to live (byte 704118), uses these numeric fields, and
// reads network.interfaces (646611), pools.pools (630626), fleet.devices (689270). The
// separate original-firmware lab capture is the evidence for gamma601V02101 above.
// Unknown strings, keys, objects and arrays never become output or error text.
extension HarloReadResult {
    static func project(_ endpoint: HarloReadEndpoint, body: Data, profile: HarloInfoProfile?) -> Self {
        if endpoint == .logs { return .logsWithheld }
        let root = try? JSONDecoder().decode(JSONValue.self, from: body)
        let object = root?.objectValue
        func reading(_ key: String) -> Double? {
            switch object?[key] {
            case let .number(n) where n.isFinite: return n
            case let .integer(n): return Double(n)
            case let .unsignedInteger(n): return Double(n)
            default: return nil
            }
        }
        switch endpoint {
        case .info:
            let (identity, advertised) = root.flatMap { profile?.interpret($0) } ?? (.unconfirmed, [])
            return .info(identity: identity, advertised: advertised)
        case .telemetry:
            return .telemetry(hashrateGHs: reading("hashrate_ghs"), powerW: reading("device_power_w"),
                              asicTemperatureC: reading("asic_temp_c"))
        case .network: return .network(interfaceCount: object?["interfaces"]?.arrayValue?.count)
        case .pools: return .pools(entryCount: object?["pools"]?.arrayValue?.count)
        case .fleet: return .fleet(reportedEntryCount: object?["devices"]?.arrayValue?.count)
        case .logs: return .logsWithheld
        }
    }
}
