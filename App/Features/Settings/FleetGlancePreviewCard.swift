import SwiftUI

/// Non-interactive preview of the shared aggregate snapshot, matching the widget
/// and Live Activity layouts. It renders the same values the extensions receive
/// and never opens a miner connection.
struct FleetGlancePreviewCard: View {
    let glance: FleetGlance
    /// Live Activity previews add the compact power and miner columns.
    var showsDetails: Bool
    /// A fixed reference date is useful for deterministic preview and boundary validation.
    var referenceDate: Date?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.redactionReasons) private var redactionReasons

    var presentation: FleetGlancePresentation {
        FleetGlancePresentation(glance: glance, isStale: glance.isStale(at: referenceDate ?? Date()))
    }

    private var summary: String {
        redactionReasons.isEmpty
            ? presentation.accessibilitySummary
            : presentation.redactedAccessibilitySummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(presentation.badge)
                    .font(FleetTheme.mono(12).weight(.semibold))
                    .foregroundStyle(FleetTheme.panelAccent)
                Spacer(minLength: 8)
                FleetBrandMark(size: 26)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.rate)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(FleetTheme.panelInk)
                Text(presentation.rateUnit)
                    .fleetFont(.subheadline, weight: .medium, design: .rounded)
                    .foregroundStyle(FleetTheme.panelSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if showsDetails {
                detailColumns
            } else {
                Label(
                    "\(glance.minerCount) \(glance.isDemo ? "sample miners" : "miners")",
                    systemImage: "fan"
                )
                .fleetFont(.subheadline)
                .foregroundStyle(FleetTheme.panelSecondary)
            }
            Text(presentation.status)
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if presentation.hasMiners {
                Label(glance.updatedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .fleetFont(.caption2, design: .monospaced)
                    .foregroundStyle(FleetTheme.panelSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FleetTheme.soloSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FleetTheme.controlBorder.opacity(0.45))
        )
        .privacySensitive(presentation.hasMiners)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview. \(summary)")
        .accessibilityIdentifier("monitoring.glancePreview")
    }

    @ViewBuilder private var detailColumns: some View {
        let miners = detail(
            value: "\(glance.minerCount)",
            caption: glance.isDemo ? "sample miners" : "miners",
            symbol: "fan"
        )
        let watts = detail(value: "\(presentation.power) W", caption: "power", symbol: "bolt")
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                miners
                if presentation.hasMiners { watts }
            }
        } else {
            HStack(spacing: 18) {
                miners
                if presentation.hasMiners { watts }
            }
        }
    }

    private func detail(value: String, caption: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.panelAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .fleetFont(.subheadline, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(FleetTheme.panelInk)
                Text(caption)
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.panelSecondary)
            }
        }
    }
}

#Preview("Glance preview") {
    VStack(spacing: 16) {
        FleetGlancePreviewCard(
            glance: FleetGlance(
                updatedAt: Date(),
                onlineCount: 3,
                minerCount: 3,
                hashrateGHs: 3_020,
                powerWatts: 51,
                isDemo: true
            ),
            showsDetails: false
        )
        FleetGlancePreviewCard(
            glance: FleetGlance(
                updatedAt: Date(),
                onlineCount: 3,
                minerCount: 3,
                hashrateGHs: 3_020,
                powerWatts: 51,
                isDemo: true
            ),
            showsDetails: true
        )
    }
    .padding()
    .background(FleetTheme.canvas)
}
