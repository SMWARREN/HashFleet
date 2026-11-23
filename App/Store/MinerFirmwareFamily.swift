import Foundation
import HashFleetCore

/// Which open-source firmware project a miner belongs to.
///
/// The app speaks the ESP-Miner/AxeOS HTTP API, which several hardware families share. They do
/// **not** share a release feed: offering a NerdQAxe owner a Bitaxe ESP-Miner build is wrong and
/// potentially harmful. Identification is evidence-based from reported telemetry only. When the
/// evidence is absent the family is `unknown` and no release feed is offered at all, matching the
/// codebase rule that an unverified reading is never presented as a verified one.
enum MinerFirmwareFamily: String, Codable, Equatable, Sendable, CaseIterable {
    case bitaxe
    case nerdqaxe
    case bitfortun
    case axeForge

    /// Human-readable project name for UI copy.
    var displayName: String {
        switch self {
        case .bitaxe: "Bitaxe ESP-Miner"
        case .nerdqaxe: "NerdQAxe ESP-Miner"
        case .bitfortun: "Bitfortun BS-1 firmware"
        case .axeForge: "AxeForge"
        }
    }

    var releaseFeedURL: URL {
        switch self {
        case .bitaxe:
            URL(string: "https://api.github.com/repos/bitaxeorg/ESP-Miner/releases?per_page=20")!
        case .nerdqaxe:
            URL(string: "https://api.github.com/repos/shufps/ESP-Miner-NerdQAxePlus/releases?per_page=20")!
        case .bitfortun:
            URL(string: "https://api.github.com/repos/liaojinguu/bitfortun-BS-1/releases?per_page=20")!
        case .axeForge:
            URL(string: "https://api.github.com/repos/IsSasoriDev/AxeForge/releases?per_page=20")!
        }
    }

    /// Whether the pinned upstream registrar serves `/api/ws/live`. Only ESP-Miner does. NerdQAxe and
    /// Bitfortun register only the text log socket `/api/ws`, and AxeForge registers no WebSocket.
    /// Monitoring must poll HTTP for the others instead of expecting a live stream.
    var supportsLiveWebSocket: Bool {
        self == .bitaxe
    }

    /// Identifies the family from reported telemetry. Returns nil when nothing in the response
    /// names a known project, rather than guessing a default.
    static func identify(from info: MinerInfo?) -> MinerFirmwareFamily? {
        guard let info else { return nil }
        // Board and device model are the strongest signals, then hostname, then the version
        // strings, which some builds tag with the project name.
        let evidence = [
            info.boardVersion,
            info.raw["deviceModel"]?.stringValue ?? "",
            info.raw["board"]?.stringValue ?? "",
            info.hostname,
            info.version,
            info.axeOSVersion
        ]
        for value in evidence {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Check the more specific projects first. "nerdqaxe" contains "axe", and the Bitfortun
            // board names ("BitfortunAxe") contain "axe" too, and AxeForge's BS-1 profile is named
            // "Bitfortun BS-1".
            if trimmed.localizedCaseInsensitiveContains("axeforge") {
                return .axeForge
            }
            if trimmed.localizedCaseInsensitiveContains("bitfortun") {
                return .bitfortun
            }
            if trimmed.localizedCaseInsensitiveContains("nerdqaxe")
                || trimmed.localizedCaseInsensitiveContains("nerdoctaxe") {
                return .nerdqaxe
            }
            if trimmed.localizedCaseInsensitiveContains("bitaxe") {
                return .bitaxe
            }
        }
        return nil
    }
}
