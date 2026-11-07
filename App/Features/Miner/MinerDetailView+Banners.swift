import SwiftUI
import HashFleetCore

/// Reported-fault banner for MinerDetailView. Kept separate so each detail file stays
/// under the 400-line file-length threshold; identifiers and wording are unchanged.
extension MinerDetailView {
    /// Only genuine reported fault flags, shown once and never derived from temperatures or model
    /// names. Absent flags stay silent rather than implying a healthy or unsupported device.
    func faultBanner(_ alerts: MinerReportedAlerts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(alerts.messages, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .fleetFont(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isNoticeSilenced {
                Label("Notice silenced on dashboard for 4 hours", systemImage: "bell.slash.fill")
                    .fleetFont(.caption, weight: .medium)
                    .foregroundStyle(FleetTheme.secondary)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("detail.notice.silencedStatus")
            } else {
                Button {
                    MinerNoticeSnoozeStore.snooze(for: device.id, defaults: store.defaults)
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2)) {
                        isNoticeSilenced = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.slash")
                            .fleetFont(.caption, weight: .semibold)
                        Text("Silence miner notice for 4 hours")
                            .fleetFont(.caption, weight: .semibold)
                    }
                    .foregroundStyle(FleetTheme.warning)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Silence miner notice for 4 hours")
                .accessibilityHint("The notice can appear again after four hours.")
                .accessibilityIdentifier("detail.notice.snooze")
            }
            Text("Reported by the miner itself. This app does not clear or change fault state.")
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
        }
        .foregroundStyle(FleetTheme.warning)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fleetCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.reportedFaults")
    }
}
