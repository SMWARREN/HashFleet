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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    bestMetricLabels
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    bestMetricLabels
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var bestMetricLabels: some View {
        if let bestShare { bestLabel("Best", value: bestShare) }
        if let bestSessionShare { bestLabel("Session best", value: bestSessionShare) }
    }

    func bestLabel(_ title: String, value: String) -> some View {
        Text("\(title) \(value)")
            .fleetFont(.footnote)
            .foregroundStyle(FleetTheme.secondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .fleetNumericUpdate(value, reduceMotion: reduceMotion)
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

    var powerSummary: some View {
        let reading = snapshot?.info.flatMap { FleetFormat.sensor($0, keys: "power") }
        let value = reading.map { FleetFormat.number($0, decimals: 1) }
        return Text("Power: \(value.map { $0 + " W" } ?? "Not reported")")
            .fleetFont(.subheadline, weight: .medium)
            .foregroundStyle(FleetTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .fleetNumericUpdate(value, reduceMotion: reduceMotion)
            .accessibilityLabel("Power, \(value.map { $0 + " watts" } ?? "not reported")")
    }

    func hardwareReadings(_ info: MinerInfo, includeFan: Bool = true) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                hardwareReadingItems(info, includeFan: includeFan)
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) {
                hardwareReadingItems(info, includeFan: includeFan)
            }
        }
    }

    @ViewBuilder
    private func hardwareReadingItems(_ info: MinerInfo, includeFan: Bool) -> some View {
        hardwareReading("Temperature", reading: FleetFormat.sensor(info, keys: "temp"),
                        unit: " °C", spokenUnit: "degrees Celsius")
        hardwareReading("Power", reading: FleetFormat.sensor(info, keys: "power"),
                        unit: " W", spokenUnit: "watts", decimals: 1)
        if includeFan {
            hardwareReading("Fan speed", reading: FleetFormat.sensor(info, keys: "fanspeed", "fanSpeed"),
                            unit: "%", spokenUnit: "percent")
        }
    }

    var statusBadge: some View {
        FleetMinerStatusBadge(state: presentationState)
    }

    private func hardwareReading(_ title: String, reading: Double?, unit: String, spokenUnit: String,
                                 decimals: Int = 0) -> some View {
        let value = reading.map { FleetFormat.number($0, decimals: decimals) }
        return VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
            Text(value.map { $0 + unit } ?? "Not reported")
                .fleetFont(.subheadline, weight: .semibold)
                .foregroundStyle(FleetTheme.ink)
                .monospacedDigit()
                .fleetNumericUpdate(value, reduceMotion: reduceMotion)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value.map { $0 + " " + spokenUnit } ?? "not reported")")
    }
}
