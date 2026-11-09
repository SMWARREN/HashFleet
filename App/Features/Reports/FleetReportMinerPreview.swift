import SwiftUI

struct FleetReportMinerPreview: View {
    let miner: FleetReportSnapshot.Miner

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(miner.label).fleetFont(.headline)
            Text(miner.connection.rawValue).fleetFont(.subheadline)
            Text(miner.freshness.rawValue)
                .fleetFont(.caption)
                .foregroundStyle(miner.isCurrent ? FleetTheme.secondary : FleetTheme.warning)
            Text("Observed: \(FleetReportSnapshot.timestamp(miner.observedAt))")
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            if !miner.isCurrent {
                Text("Last-known / unconfirmed readings. Excluded from subtotals.")
                    .fleetFont(.caption).foregroundStyle(FleetTheme.warning)
            }
            hashrateRow
            metric("Power", value: miner.powerWatts, unit: "W")
            metric("Chip temperature", value: miner.temperatureCelsius, unit: "°C")
            metric("Fan", value: miner.fanRPM, unit: "RPM")
            metric("Uptime", value: miner.uptimeSeconds, unit: "seconds")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fleetReport.miner.\(miner.id)")
    }

    private var hashrateRow: some View {
        LabeledContent("Hashrate", value: FleetReportSnapshot.formattedHashrate(miner.hashrateGHs))
            .fleetFont(.subheadline)
    }

    private func metric(_ title: String, value: Double?, unit: String) -> some View {
        LabeledContent(title, value: FleetReportSnapshot.usable(value).map {
            "\(FleetReportSnapshot.number($0)) \(unit)"
        } ?? "Not reported")
        .fleetFont(.subheadline)
    }
}
