import Foundation

/// Decides whether a candidate host's `/api/system/info` response is genuinely an AxeOS miner, and derives a
/// safe display name for it.
///
/// Identification is deliberately STRICTER than the single-miner validator because discovery auto-adds miners
/// without the user confirming an address. A candidate must carry a typed, non-empty `ASICModel` of the form
/// `BM` followed by digits (or two such models separated by `/`) AND at least one valid Watch telemetry metric
/// (decoded with the shared
/// `WatchMinerInfoDecoder`, so unrelated JSON, HTML, captive portals, wrong types and empty bodies are rejected).
enum WatchDiscoveryIdentification {
    /// Fallback name used when no allow-listed name field yields a safe string.
    static let fallbackName = "AxeOS miner"
    /// Maximum display-name length (mirrors `WatchFleetLimits.maximumNameLength`).
    static let maximumNameLength = WatchFleetLimits.maximumNameLength

    /// Only these keys may supply a display name. Keys that could carry wallets, pools or Wi-Fi secrets are
    /// never consulted.
    static let nameKeys = ["hostname", "fullHostname", "mdnsHostname", "deviceName"]

    private struct Identity: Decodable {
        let asicModel: String?
        let hostname: String?
        let fullHostname: String?
        let mdnsHostname: String?
        let deviceName: String?

        enum CodingKeys: String, CodingKey {
            // AxeOS reports `ASICModel`; accept a lowercase variant defensively.
            case asicModelUpper = "ASICModel"
            case asicModelLower = "asicModel"
            case hostname, fullHostname, mdnsHostname, deviceName
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func string(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
            asicModel = string(.asicModelUpper) ?? string(.asicModelLower)
            hostname = string(.hostname)
            fullHostname = string(.fullHostname)
            mdnsHostname = string(.mdnsHostname)
            deviceName = string(.deviceName)
        }
    }

    /// Returns a safe display name when the data is a genuine miner, else `nil`.
    ///
    /// The caller is responsible for status/content-type/transport checks; this inspects the decoded body only.
    static func minerName(from data: Data) -> String? {
        guard let identity = try? JSONDecoder().decode(Identity.self, from: data) else { return nil }
        guard isValidASICModel(identity.asicModel) else { return nil }
        // Reuse the exact telemetry gate: at least one valid metric must be present.
        guard (try? WatchMinerInfoDecoder.reading(from: data, minerID: UUID(), observedAt: Date())) != nil else {
            return nil
        }
        for candidate in [identity.hostname, identity.fullHostname, identity.mdnsHostname, identity.deviceName] {
            if let safe = sanitizedName(candidate) { return safe }
        }
        return fallbackName
    }

    /// Maximum accepted `ASICModel` length (defends against hostile oversize strings).
    static let maximumModelLength = 32

    /// One or two `BM` + ASCII-digit model identifiers, case-insensitive. Naja firmware actually reports
    /// `BM1372/BM1373`. Empty components, trailing letters, unrelated models and oversize strings are rejected.
    static func isValidASICModel(_ model: String?) -> Bool {
        guard let model else { return false }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...maximumModelLength).contains(trimmed.count) else { return false }
        let models = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(models.count) else { return false }
        return models.allSatisfy { model in
            guard model.prefix(2).lowercased() == "bm" else { return false }
            let digits = model.dropFirst(2)
            return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    /// Trims, strips control characters, and enforces the length limit. Returns `nil` for empty or
    /// control-only names so the caller can fall back safely.
    static func sanitizedName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let forbidden = CharacterSet.controlCharacters.union(.newlines)
        let scalars = raw.unicodeScalars.filter { !forbidden.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count <= maximumNameLength else { return String(cleaned.prefix(maximumNameLength)) }
        return cleaned
    }
}
