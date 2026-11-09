import HashFleetCore
import Foundation

/// Shared saved-reading copy and units for in-app previews, widgets and Live Activities.
/// This policy never loads storage or connects to a miner.
struct FleetGlancePresentation: Sendable {
    let glance: FleetGlance
    let isStale: Bool
    var refreshMessage: String?

    var hasMiners: Bool { glance.isValid && glance.minerCount > 0 }
    var badge: String {
        guard hasMiners else { return "GET STARTED" }
        if glance.isDemo { return isStale ? "DEMO · STALE" : "DEMO" }
        return isStale ? "STALE" : "RECENT"
    }
    var rateLabel: String {
        if glance.isDemo { return "SAMPLE HASHRATE" }
        return isStale ? "LAST KNOWN HASHRATE" : "FLEET HASHRATE"
    }
    var status: String {
        guard hasMiners else { return "Open Hash Fleet to connect" }
        if glance.isDemo { return "Sample data · no connection" }
        if isStale { return "Last known · open app to refresh" }
        return "\(glance.onlineCount) of \(glance.minerCount) online"
    }
    var rate: String {
        guard hasMiners else { return "—" }
        return FleetFormat.hashrate(glance.hashrateGHs)
    }
    var rateUnit: String {
        guard hasMiners else { return "" }
        return FleetFormat.hashrateUnit(glance.hashrateGHs)
    }
    var power: String {
        guard hasMiners else { return "—" }
        return FleetFormat.number(glance.powerWatts)
    }
    var efficiencyJPerTH: String? {
        guard hasMiners else { return nil }
        return FleetWidgetAppearancePolicy.formatEfficiency(
            hashrateGHs: glance.hashrateGHs,
            powerWatts: glance.powerWatts
        )
    }
    var accessibilitySummary: String {
        let reading = FleetWidgetAppearancePolicy.accessibilitySummary(
            glance: glance, isStale: isStale, isRedacted: false)
        guard hasMiners, !glance.isDemo, let refreshMessage else { return reading }
        // The visible footer's fixed outcome must also be spoken when child labels are ignored.
        return "\(reading) \(refreshMessage)."
    }
    var redactedAccessibilitySummary: String {
        FleetWidgetAppearancePolicy.accessibilitySummary(glance: glance, isStale: isStale, isRedacted: true)
    }
}
