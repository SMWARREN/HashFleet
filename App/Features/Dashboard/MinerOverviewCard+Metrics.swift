import SwiftUI
import HashFleetCore

/// Secondary metric presentations for MinerOverviewCard: skeleton placeholders, best-share,
/// power and status summaries, and the small metric row builder.
extension MinerOverviewCard {
    var skeletonSecondaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if compact {
                FleetLoadingSkeleton(width: 60, height: 14, cornerRadius: 3, label: "Loading power")
            }
            FleetLoadingSkeleton(width: 80, height: 14, cornerRadius: 3, label: "Loading difficulty")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.bestRow.\(device.id.uuidString)")
    }

    var skeletonMetricsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { skeletonMetricItems }
            VStack(alignment: .leading, spacing: 12) { skeletonMetricItems }
        }
    }

    @ViewBuilder private var skeletonMetricItems: some View {
        FleetLoadingSkeleton(width: 68, height: 14, cornerRadius: 3, label: "Loading temperature")
        FleetLoadingSkeleton(width: 68, height: 14, cornerRadius: 3, label: "Loading power")
        FleetLoadingSkeleton(width: 58, height: 14, cornerRadius: 3, label: "Loading fan speed")
    }

    @ViewBuilder
    var bestSummary: some View {
        if bestShare != nil || bestSessionShare != nil {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                bestMetricLabels
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
        }
    }

    @ViewBuilder
    private var bestMetricLabels: some View {
        if let bestShare { bestLabel("Best", value: bestShare) }
        if let bestSessionShare { bestLabel("Session best", value: bestSessionShare) }
    }

    func bestLabel(_ title: String, value: String) -> some View {
        Label {
            Text("\(title) \(value)")
                .fleetNumericUpdate(value, reduceMotion: reduceMotion)
                .minimumScaleFactor(0.72)
        } icon: {
            Image(systemName: "trophy")
        }
        .fleetFont(.caption2, design: .monospaced)
        .foregroundStyle(FleetTheme.accent)
        .lineLimit(1)
        .accessibilityLabel("\(title) reported share difficulty, \(value)")
    }

    var bestShare: String? {
        guard let info = snapshot?.info else { return nil }
        return MiningDifficultyFormat.short(info.raw["bestDiff"])
    }

    var bestSessionShare: String? {
        guard let info = snapshot?.info else { return nil }
        return MiningDifficultyFormat.short(info.raw["bestSessionDiff"])
    }

    @ViewBuilder
    var powerSummary: some View {
        if let info = snapshot?.info,
            let power = FleetFormat.sensor(info, keys: "power") {
            let value = "\(FleetFormat.number(power, decimals: 1)) W"
            Label {
                Text(value).fleetNumericUpdate(value, reduceMotion: reduceMotion)
            } icon: {
                Image(systemName: "bolt")
            }
            .fleetFont(.caption2, design: .monospaced)
            .foregroundStyle(FleetTheme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityLabel("Power, \(FleetFormat.number(power, decimals: 1)) watts")
        }
    }

    /// True only for presentations that read as a working, connected miner. This is the
    /// sole driver of the one-shot status pulse, so ordinary telemetry refreshes that keep
    /// the same online state never animate the dot.
    var isMinerOnline: Bool {
        presentationState.isOperational
    }

    @ViewBuilder
    var statusBadge: some View {
        FleetMinerStatusBadge(state: presentationState)
    }

    func smallMetric(_ title: String, value: String, symbol: String) -> some View {
        Label {
            Text(value).fleetNumericUpdate(value, reduceMotion: reduceMotion)
        } icon: {
            Image(systemName: symbol)
        }
        .fleetFont(.caption, design: .monospaced)
        .foregroundStyle(FleetTheme.secondary)
        .accessibilityLabel("\(title), \(value)")
    }
}
