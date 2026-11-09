import Foundation
import HashFleetCore

/// Presentation identity only, never a capability or tuning decision.
/// Board families follow docs/MODEL-CAPABILITY-MATRIX.md's pinned firmware table.
enum MinerDisplayName {
    static func automatic(info: MinerInfo?, address: String) -> String {
        let raw = info?.raw ?? [:]
        if let reported = clean(raw["deviceModel"]?.stringValue),
            !["bitaxe", "bitax", "unknown"].contains(reported.lowercased()) {
            return reported
        }
        let asic = clean(raw["ASICModel"]?.stringValue ?? raw["asicModel"]?.stringValue)?.uppercased()
        let board = clean(raw["boardVersion"]?.stringValue)
        if let board, let family = boards[board], (asic.map { family.matches(asic: $0) } ?? true) {
            return family.name
        }
        // An ASIC string alone cannot distinguish Gamma, Duo, Turbo and Hex boards.
        // It also cannot prove the vendor: other open-source miners report the same
        // ASIC models. The ASIC alone is the only evidenced identity, so only add
        // the "Bitaxe" label when the device itself hints at it via its hostname.
        if let asic {
            if let hostHint = clean(raw["hostname"]?.stringValue)?.lowercased(),
                hostHint.contains("bitax") {
                return "Bitaxe · \(asic)"
            }
            return asic
        }
        if let host = clean(raw["hostname"]?.stringValue), !["bitaxe", "bitax"].contains(host.lowercased()) {
            return host
        }
        return (try? MinerDevice(name: "", address: address).validatedURL())?.host ?? "Miner"
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64,
            !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return trimmed
    }

    private struct Family: Sendable {
        let name: String
        let asics: Set<String>

        /// Firmware may report a single ASIC ("BM1373") or a combined dual-chip
        /// string ("BM1372/BM1373"). Split on non-alphanumeric separators and
        /// accept the board when any reported token matches a known ASIC.
        func matches(asic: String) -> Bool {
            let tokens = asic.uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            return tokens.contains { asics.contains($0) }
        }
    }
    private static let boards: [String: Family] = {
        var result: [String: Family] = [:]
        for (name, asics, versions) in [
            ("Max", ["BM1397"], ["2.2", "102"]),
            ("Ultra", ["BM1366"], ["0.11", "201", "202", "203", "204", "205", "207"]),
            ("Hex", ["BM1366"], ["302", "303"]),
            ("Supra", ["BM1368"], ["400", "401", "402", "403"]),
            ("Gamma", ["BM1370"], ["600", "601", "602", "603"]),
            ("Gamma Duo", ["BM1370"], ["650"]),
            ("Gamma Turbo", ["BM1370"], ["801"]),
            ("Gamma Hex", ["BM1370"], ["1300"]),
            ("Supra Hex", ["BM1368"], ["701", "702"]),
            ("Naja Duo", ["BM1372", "BM1373"], ["1201"])
        ] {
            for version in versions { result[version] = Family(name: name, asics: Set(asics)) }
        }
        return result
    }()
}
