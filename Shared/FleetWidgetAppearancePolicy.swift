import HashFleetCore
import Foundation

/// Pure policy governing widget and live activity appearance, tinting modes, and accessibility labels.
/// Keeps formatting and appearance decisions deterministic and decoupled from SwiftUI views for testability.
enum FleetWidgetAppearancePolicy {

    /// Determines the semantic role for accenting in tinted widget rendering.
    enum ElementRole: Sendable, Equatable {
        case brandLogo
        case badge
        case primaryMetric
        case secondaryMetric
        case label
        case timestamp
    }

    /// Determines whether an element should opt into accented rendering in tinted/accented widget modes.
    /// In iOS 18+ tinted mode:
    /// - Primary metrics, brand marks, and status badges are accented to maintain visual hierarchy.
    /// - Static labels, timestamps, and secondary captions remain desaturated / unaccented for clarity.
    static func isAccentable(role: ElementRole) -> Bool {
        switch role {
        case .brandLogo, .badge, .primaryMetric:
            return true
        case .secondaryMetric, .label, .timestamp:
            return false
        }
    }

    /// Formats efficiency in Joules per Terahash (J/TH), derived purely from existing aggregate figures:
    /// efficiency (J/TH) = powerWatts / hashrateTHs = (powerWatts * 1000) / hashrateGHs.
    /// Returns nil if hashrate is non-positive or unavailable, never inventing fake numbers.
    static func formatEfficiency(hashrateGHs: Double, powerWatts: Double) -> String? {
        guard hashrateGHs > 0, powerWatts >= 0,
              hashrateGHs.isFinite, powerWatts.isFinite else {
            return nil
        }
        let jPerTH = (powerWatts * 1000.0) / hashrateGHs
        guard jPerTH.isFinite, jPerTH >= 0, jPerTH < 100_000 else {
            return nil
        }
        return jPerTH.formatted(.number.precision(.fractionLength(jPerTH >= 100 ? 0 : 1)))
    }

    /// Determines whether the snapshot needs a prominent stale warning or reduced metric presentation.
    static func requiresStaleTreatment(isStale: Bool, hasMiners: Bool) -> Bool {
        isStale && hasMiners
    }

    /// Safe accessibility summary string for widget or supplemental live activity.
    static func accessibilitySummary(
        glance: FleetGlance,
        isStale: Bool,
        isRedacted: Bool
    ) -> String {
        guard glance.isValid && glance.minerCount > 0 else {
            return "Hash Fleet. No cached fleet. Open the app to connect a miner."
        }
        if isRedacted {
            return "Hash Fleet. Fleet readings are hidden for privacy. Open the app to view your fleet."
        }

        let mode = glance.isDemo
            ? "Demo sample data. No hardware connected. "
            : ""
        let age = isStale
            ? "Stale snapshot. Background refresh is"
            + " best-effort; open the app for an"
            + " immediate refresh. "
            : ""
        let rateLabel = glance.isDemo
            ? "SAMPLE HASHRATE"
            : (isStale ? "LAST KNOWN HASHRATE" : "FLEET HASHRATE")

        let rate = FleetFormat.hashrateWithUnit(glance.hashrateGHs)

        let power = glance.powerWatts.formatted(.number.precision(.fractionLength(0)))
        let status = glance.isDemo
            ? "Sample data \u{00B7} no connection"
            : (isStale
               ? "Last known \u{00B7} open app to refresh"
               : "\(glance.onlineCount) of \(glance.minerCount) online")

        let dateStr = glance.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(mode)\(age)\(rateLabel), \(rate). \(power) watts. \(status). Updated \(dateStr)."
    }
}
