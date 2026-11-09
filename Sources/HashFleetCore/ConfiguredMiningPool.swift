import Foundation

/// Supported coins across pool providers.
public enum MiningPoolCoin: String, Codable, Hashable, Sendable, CaseIterable {
    case btc
    case bch
    case bc2
    case bch2
    case xec
    case dgb

    public var ticker: String { rawValue.uppercased() }

    public var coingeckoID: String {
        switch self {
        case .btc: return "bitcoin"
        case .bch: return "bitcoin-cash"
        case .bc2: return "bitcoinii"
        case .bch2: return "bitcoin-cash-ii"
        case .xec: return "ecash"
        case .dgb: return "digibyte"
        }
    }

    /// The SoloFury API path prefix for this coin:
    /// BCH -> "/api", BTC -> "/api-btc", BC2 -> "/api-bc2", BCH2 -> "/api-bch2", XEC -> "/api-xec"
    public var soloFuryPrefix: String? {
        switch self {
        case .bch: return "/api"
        case .btc: return "/api-btc"
        case .bc2: return "/api-bc2"
        case .bch2: return "/api-bch2"
        case .xec: return "/api-xec"
        case .dgb: return nil
        }
    }

    public static var soloFuryCoins: [Self] { allCases.filter { $0.soloFuryPrefix != nil } }
}

/// Known supported public mining pool providers.
public enum MiningPoolProvider: String, Codable, Hashable, Sendable {
    case ckpool
    case soloFury
    case soloPool
}

/// A parsed configured mining pool slot from miner telemetry.
/// Contains only non-secret identifiers, host, validated wallet address, and optional role/active flags.
public struct ConfiguredMiningPool: Equatable, Hashable, Sendable {
    public let id: String
    public let host: String
    public let coin: MiningPoolCoin?
    public let provider: MiningPoolProvider?
    public let role: String
    public let isActive: Bool?
    public let address: String?
    public let redactedAddress: String?

    /// Display identity is separate from the provider enum that authorizes public API adapters.
    public var providerName: String? {
        switch provider {
        case .ckpool: "CKPool"
        case .soloFury: "SoloFury"
        case .soloPool: "SoloPool"
        case nil: nil
        }
    }

    public init(
        id: String,
        host: String,
        coin: MiningPoolCoin?,
        provider: MiningPoolProvider?,
        role: String,
        isActive: Bool?,
        address: String?,
        redactedAddress: String?
    ) {
        self.id = id
        self.host = host
        self.coin = coin
        self.provider = provider
        self.role = role
        self.isActive = isActive
        self.address = address
        self.redactedAddress = redactedAddress
    }

    // MARK: - Exact Host Allowlist

    private static let solofuryRegions = ["", "pnw-", "eu-", "uk-", "me-", "afr-", "lat-", "asia-", "jp-"]
    private static let solofuryCoins = ["bch", "btc", "bc2", "bch2", "xec"]

    public static let documentedSoloFuryHosts: Set<String> = {
        var hosts = Set<String>()
        for reg in solofuryRegions {
            for coin in solofuryCoins {
                hosts.insert("\(reg)\(coin).solofury.com")
            }
        }
        return hosts
    }()

    public static let documentedCKPoolHosts: Set<String> = [
        "stratum.ckpool.org",
        "solo.ckpool.org"
    ]

    /// Official SHA-256 help-page configurations verified 2026-09-09. Shared hosts require a port.
    public static let documentedSoloPoolHosts: Set<String> = [
        "us1.solopool.org", "eu2.solopool.org", "eu3.solopool.org"
    ]

    // MARK: - Resolver

    /// Resolves all configured pools from `MinerInfo.raw`.
    ///
    /// Rules enforced:
    /// - Reads `pools` array by persistent integer slot `id` (0...7). Rejects missing or non-integer `id`.
    /// - Rejects duplicate slot IDs.
    /// - If `pools` array is present (even if empty or malformed), fails closed: does NOT fall back to legacy fields.
    /// - Uses legacy `stratumURL` / `fallbackStratumURL` only when `pools` key is completely absent from `info.raw`.
    /// - An explicit activePoolIndex takes precedence over primary/fallback routing during rotation.
    /// - Invalid explicit active indices remain unknown, never silently selecting the primary pool.
    public static func resolve(info: MinerInfo) -> [ConfiguredMiningPool] {
        let fallbackFlag = info.raw["isUsingFallbackStratum"]?.boolValue
        let usingFallback = fallbackFlag == true
        let hasFallbackFlag = fallbackFlag != nil

        let primarySlotId = exactSlotID(info.raw["primaryPoolIndex"])
        let secondarySlotId = exactSlotID(info.raw["secondaryPoolIndex"])

        // If `pools` key exists in raw, use slot resolution only
        // (fail closed on malformed array, never fallback to legacy)
        if let rawPoolsValue = info.raw["pools"] {
            guard let poolObjects = rawPoolsValue.arrayValue else {
                return []  // malformed pools value -> fail closed
            }
            return resolveArrayPools(
                poolObjects: poolObjects,
                info: info,
                primarySlotId: primarySlotId,
                secondarySlotId: secondarySlotId
            )
        }

        // An explicit slot cannot be resolved safely without its slot table.
        if info.raw["activePoolIndex"] != nil { return [] }

        // Legacy fallback only when `pools` key was completely absent
        var results: [ConfiguredMiningPool] = []
        let primaryUrl = text(info.raw["stratumURL"]) ?? text(info.raw["poolURL"]) ?? ""
        let primaryUser = text(info.raw["stratumUser"]) ?? ""
        if !primaryUrl.isEmpty || !primaryUser.isEmpty {
            results.append(
                buildPool(
                    id: "legacy-primary",
                    rawUrl: primaryUrl,
                    rawUser: primaryUser,
                    rawPort: info.raw["stratumPort"],
                    role: "Configured primary",
                    isActive: hasFallbackFlag ? !usingFallback : nil
                )
            )
        }

        let fallbackUrl = text(info.raw["fallbackStratumURL"]) ?? ""
        let fallbackUser = text(info.raw["fallbackStratumUser"]) ?? ""
        if !fallbackUrl.isEmpty || !fallbackUser.isEmpty {
            results.append(
                buildPool(
                    id: "legacy-fallback",
                    rawUrl: fallbackUrl,
                    rawUser: fallbackUser,
                    rawPort: info.raw["fallbackStratumPort"],
                    role: "Configured fallback",
                    isActive: hasFallbackFlag ? usingFallback : nil
                )
            )
        }

        return results
    }

    /// Resolves pools from the `pools` array, failing closed on any malformed entry.
    private static func resolveArrayPools(
        poolObjects: [JSONValue],
        info: MinerInfo,
        primarySlotId: Int?,
        secondarySlotId: Int?
    ) -> [ConfiguredMiningPool] {
        var seenIds = Set<Int>()
        var rows: [(slotId: Int, dict: [String: JSONValue])] = []

        for item in poolObjects {
            guard let dict = item.objectValue else { return [] }  // malformed entry -> fail closed
            guard let slotId = exactSlotID(dict["id"]) else {
                return []  // missing or invalid integer id -> fail closed
            }
            guard seenIds.insert(slotId).inserted else {
                return []  // duplicate slot id -> fail closed
            }
            rows.append((slotId, dict))
        }
        let selectedID = reportedActiveSlotID(info: info)
        let verifiedSelectedID = selectedID.flatMap { seenIds.contains($0) ? $0 : nil }

        return rows.map { slotId, dict in
            let rawUrl = text(dict["url"]) ?? text(dict["stratumURL"]) ?? ""
            let rawUser = text(dict["user"]) ?? text(dict["stratumUser"]) ?? ""

            let isActive = verifiedSelectedID.map { $0 == slotId }
            let role: String
            if primarySlotId == slotId && secondarySlotId == slotId {
                role = "Primary & fallback slot \(slotId)"
            } else if let primarySlotId, slotId == primarySlotId {
                role = "Primary slot \(slotId)"
            } else if let secondarySlotId, slotId == secondarySlotId {
                role = "Fallback slot \(slotId)"
            } else {
                role = "Slot \(slotId)"
            }

            return buildPool(
                id: "slot-\(slotId)",
                rawUrl: rawUrl,
                rawUser: rawUser,
                rawPort: dict["port"] ?? dict["stratumPort"],
                role: role,
                isActive: isActive
            )
        }
    }

    // MARK: - Safe URLComponents Host Extraction & Validation
}

extension ConfiguredMiningPool {
    /// Reported routing ID, not an array offset. Callers must also verify it exists in a valid table.
    public static func reportedActiveSlotID(info: MinerInfo) -> Int? {
        if let active = info.raw["activePoolIndex"] {
            return exactSlotID(active)
        }
        guard let fallback = info.raw["isUsingFallbackStratum"]?.boolValue else { return nil }
        return exactSlotID(info.raw[fallback ? "secondaryPoolIndex" : "primaryPoolIndex"])
    }

    public static func extractHost(_ rawUrl: String) -> String? {
        let trimmed = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { return nil }
        guard !trimmed.contains("%"), !trimmed.contains("\\") else { return nil }

        let urlString = trimmed.contains("://") ? trimmed : "stratum+tcp://" + trimmed
        guard let comps = URLComponents(string: urlString) else { return nil }
        guard
            ["stratum+tcp", "stratum+ssl", "stratum+tls", "stratum2+tcp"].contains(comps.scheme?.lowercased() ?? "")
        else { return nil }

        // Reject credentials, query, fragment, and path for recognized account lookup
        guard comps.user == nil, comps.password == nil, comps.query == nil, comps.fragment == nil else { return nil }
        guard comps.path.isEmpty || comps.path == "/" else { return nil }
        guard let host = comps.host?.lowercased(), !host.isEmpty else { return nil }
        guard comps.port.map({ (1...65_535).contains($0) }) ?? true else { return nil }

        return host
    }

    public static func inferProviderAndCoin(host: String?, port: Int? = nil) -> (MiningPoolProvider?, MiningPoolCoin?) {
        guard let host else { return (nil, nil) }
        let lower = host.lowercased()

        // SoloPool shares regional hosts across chains and algorithms. Never infer from host alone.
        if let port {
            if ["us1.solopool.org", "eu2.solopool.org"].contains(lower), [8004, 7004, 9004].contains(port) {
                return (.soloPool, .dgb)
            }
            if ["us1.solopool.org", "eu3.solopool.org"].contains(lower), [8005, 7005, 9005].contains(port) {
                return (nil, .btc)
            }
        }

        // Exact documented CKPool hosts
        if documentedCKPoolHosts.contains(lower) {
            return (.ckpool, .btc)
        }

        // Exact documented SoloFury hosts
        if documentedSoloFuryHosts.contains(lower) {
            // Dissect coin from host: <region-><coin>.solofury.com
            let prefixPart = lower.replacingOccurrences(of: ".solofury.com", with: "")
            let coinString: String
            if let dashIdx = prefixPart.lastIndex(of: "-") {
                coinString = String(prefixPart[prefixPart.index(after: dashIdx)...])
            } else {
                coinString = prefixPart
            }
            let coin = MiningPoolCoin(rawValue: coinString)
            return (.soloFury, coin)
        }

        // Unknown or unverified host -> provider and coin are nil
        return (nil, nil)
    }

    // MARK: - Address Validation

    public static func extractAndValidateAddress(rawUser: String, coin: MiningPoolCoin?) -> String? {
        let trimmed = rawUser.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...256).contains(trimmed.utf8.count), trimmed.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            return nil
        }

        let pieces = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = pieces.first, !first.isEmpty else { return nil }
        if pieces.count == 2 {
            let suffix = pieces[1]
            guard !suffix.isEmpty,
                suffix.utf8.allSatisfy({
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                        || $0 == 45 || $0 == 95 || $0 == 46
                })
            else { return nil }
        }

        let addressCandidate = String(first)

        guard let coin else {
            return nil  // unverified coin -> do not validate or send address
        }

        return validateAddress(addressCandidate, coin: coin)
    }

    /// Chain formats from SoloFury's official reference/faq.md, verified 2026-09-07.
    /// Bitcoin II uses Bitcoin-style addresses. Bitcoin Cash II's prefix is bitcoincashii, not bitcoincash.
    static func validateAddress(_ address: String, coin: MiningPoolCoin) -> String? {
        switch coin {
        case .btc, .bc2: MiningInsightsAddress.validated(address)
        case .bch: CashAddress.validated(address, expectedPrefix: "bitcoincash")
        case .bch2: CashAddress.validated(address, expectedPrefix: "bitcoincashii")
        case .xec: CashAddress.validated(address, expectedPrefix: "ecash")
        case .dgb: DigiByteAddress.validated(address)
        }
    }

    private static func exactSlotID(_ value: JSONValue?) -> Int? {
        guard let number = value?.doubleValue, let id = Int(exactly: number), (0...7).contains(id) else { return nil }
        return id
    }

    private static func text(_ value: JSONValue?) -> String? {
        guard case .string(let text) = value else { return nil }
        return text
    }

    public static func redactAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }

    private static func buildPool(
        id: String,
        rawUrl: String,
        rawUser: String,
        rawPort: JSONValue? = nil,
        role: String,
        isActive: Bool?
    ) -> ConfiguredMiningPool {
        let host = extractHost(rawUrl)
        let embeddedPort = URLComponents(string: rawUrl.contains("://") ? rawUrl : "stratum+tcp://" + rawUrl)?.port
        let reportedPort = rawPort?.doubleValue.flatMap { Int(exactly: $0) }.flatMap {
            (1...65_535).contains($0) ? $0 : nil
        }
        // Conflicting or malformed explicit port metadata cannot authorize a chain identity.
        let port =
            rawPort == nil ? embeddedPort : (embeddedPort == nil || embeddedPort == reportedPort ? reportedPort : nil)
        let (provider, coin) = inferProviderAndCoin(host: host, port: port)
        let parsedAddress = extractAndValidateAddress(rawUser: rawUser, coin: coin)
        let redacted = parsedAddress.map { redactAddress($0) }

        return ConfiguredMiningPool(
            id: id,
            host: host ?? (rawUrl.isEmpty ? "Not reported" : "Unrecognized pool host"),
            coin: coin,
            provider: provider,
            role: role,
            isActive: isActive,
            address: parsedAddress,
            redactedAddress: redacted
        )
    }
}
