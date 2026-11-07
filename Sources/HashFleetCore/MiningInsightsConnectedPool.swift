import Foundation

/// Pure resolution of a miner's explicitly reported active CKPool account. This performs no I/O.
/// The caller must separately require a currently connected miner and honor its public-data opt-out.
public struct ConnectedPoolLookup: Hashable, Sendable {
    public let address: String
    public let poolHost: String
    public let slotID: Int?
    public let isUsingFallback: Bool

    public static func resolve(info: MinerInfo) -> ConnectedPoolLookup? {
        // A configured primary without an explicit active/fallback flag is not proof it is in use.
        guard info.raw["activePoolIndex"] != nil || info.raw["isUsingFallbackStratum"]?.boolValue != nil
        else { return nil }
        let fallback = info.raw["isUsingFallbackStratum"]?.boolValue == true
        // Int??: outer nil means the reported index is unusable; inner nil means legacy legacy path.
        guard let index = slotIndex(info: info, fallback: fallback),
            let entry = poolEntry(info: info, fallback: fallback, index: index),
            let hostText = entry.hostText,
            let username = entry.username,
            let host = allowlistedHost(hostText),
            let address = addressFromUsername(username)
        else { return nil }
        return ConnectedPoolLookup(address: address, poolHost: host, slotID: index, isUsingFallback: fallback)
    }

    /// The slot index the miner explicitly reports as in use, from the active index or the
    /// fallback flag's implied primary/secondary index.
    private static func slotIndex(info: MinerInfo, fallback: Bool) -> Int?? {
        if info.raw["activePoolIndex"] != nil {
            guard let slot = ConfiguredMiningPool.reportedActiveSlotID(info: info) else { return .none }
            return .some(slot)
        }
        let indexKey = fallback ? "secondaryPoolIndex" : "primaryPoolIndex"
        guard let reported = info.raw[indexKey] else { return .some(nil) }
        guard let parsed = MiningInsightsParser.integer(reported), (0...7).contains(parsed)
        else { return .none }
        return .some(parsed)
    }

    /// Host and stratum username for the active slot index, matching by reported ID only.
    private static func poolEntry(
        info: MinerInfo,
        fallback: Bool,
        index: Int?
    ) -> (hostText: String?, username: String?)? {
        if let rawPools = info.raw["pools"] {
            guard let pools = rawPools.arrayValue, let index else { return nil }
            guard
                ConfiguredMiningPool.resolve(info: info).contains(where: {
                    $0.id == "slot-\(index)" && $0.isActive == true
                })
            else { return nil }
            // Match by reported ID, never by ordering or by searching for any configured CKPool account.
            let matches = pools.compactMap(\.objectValue).filter { MiningInsightsParser.integer($0["id"]) == index }
            guard matches.count == 1, let selected = matches.first else { return nil }
            return (string(selected["url"]) ?? string(selected["stratumURL"]),
                string(selected["user"]) ?? string(selected["stratumUser"]))
        }
        if info.raw["activePoolIndex"] != nil { return nil }
        if fallback {
            return (string(info.raw["fallbackStratumURL"]), string(info.raw["fallbackStratumUser"]))
        }
        return (
            string(info.raw["stratumURL"]) ?? string(info.raw["poolURL"]),
            string(info.raw["stratumUser"])
        )
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case .string(let text) = value, !text.isEmpty else { return nil }
        return text
    }

    private static func allowlistedHost(_ text: String) -> String? {
        guard text == text.trimmingCharacters(in: .whitespacesAndNewlines),
            text.utf8.allSatisfy({ $0 > 32 && $0 < 127 }), !text.contains("%"), !text.contains("\\")
        else { return nil }
        let raw = text.contains("://") ? text : "stratum+tcp://" + text
        guard let url = URLComponents(string: raw),
            ["stratum+tcp", "stratum+ssl", "stratum+tls"].contains(url.scheme?.lowercased() ?? ""),
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
            url.path.isEmpty, let host = url.host?.lowercased(),
            ["stratum.ckpool.org", "solo.ckpool.org"].contains(host),
            url.port.map({ (1...65_535).contains($0) }) ?? true
        else { return nil }
        return host
    }

    private static func addressFromUsername(_ username: String) -> String? {
        // The optional worker suffix stays local. No worker name or password is returned.
        guard username.utf8.count <= 256, username.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { return nil }
        let pieces = username.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = pieces.first else { return nil }
        if pieces.count == 2 {
            let suffix = pieces[1]
            guard !suffix.isEmpty,
                suffix.utf8.allSatisfy({
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                        || $0 == 45 || $0 == 95 || $0 == 46
                })
            else { return nil }
        }
        return MiningInsightsAddress.validated(String(first))
    }
}
