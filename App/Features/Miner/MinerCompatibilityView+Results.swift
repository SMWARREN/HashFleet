import SwiftUI
import HashFleetCore

/// Result, status and identity rows for MinerCompatibilityView. Split for file length;
/// wording and identifiers are unchanged.
extension MinerCompatibilityView {
    func resultSection(_ report: MinerCapabilityReport) -> some View {
            Section {
                statusRow(
                    title: "System info",
                    subtitle: "GET /api/system/info · telemetry and settings forms",
                    status: report.infoStatus,
                    id: "compatibility.infoStatus"
                )
                statusRow(
                    title: "ASIC configuration",
                    subtitle: "GET /api/system/asic · device-reported tuning references",
                    status: report.asicStatus,
                    id: "compatibility.asicStatus"
                )
                LabeledContent("Checked") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(report.checkedAt, format: .dateTime.day().month().hour().minute().second())
                        HStack(spacing: 3) {
                            Text(report.checkedAt, style: .relative)
                            Text("ago")
                        }
                        .foregroundStyle(FleetTheme.secondary)
                    }
                    .multilineTextAlignment(.trailing)
                }
                .fleetFont(.callout)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("compatibility.checkedAt")
                Text("From this check, not live. Check again after firmware changes.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            } header: {
                Text("What this miner answered")
            }
            .listRowBackground(FleetTheme.surface)
        }

        func statusRow(title: String, subtitle: String, status: MinerProbeStatus, id: String) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).fleetFont(.callout, weight: .medium).foregroundStyle(FleetTheme.ink)
                    Spacer(minLength: 12)
                    Label(status.friendlyTitle, systemImage: status.symbol)
                        .fleetFont(.caption, weight: .semibold)
                        .foregroundStyle(status.tint)
                        .multilineTextAlignment(.trailing)
                }
                Text(subtitle).fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                if let detail = status.friendlyDetail {
                    Text(detail)
                        .fleetFont(.caption)
                        .foregroundStyle(status.isFailed ? FleetTheme.warning : FleetTheme.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 3)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(id)
        }

        // MARK: - Identity

        func identitySection(info: MinerInfo?, asic: JSONValue?) -> some View {
            Section {
                identityRow("ASIC model", value: MinerCapabilityPresentation.asicModel(info: info, asic: asic))
                identityRow(
                    "Device model",
                    value: MinerCapabilityPresentation.text(asic?["deviceModel"])
                        ?? MinerCapabilityPresentation.text(info?.raw["deviceModel"])
                )
                identityRow("Board version", value: MinerCapabilityPresentation.boardVersion(info: info, asic: asic))
                identityRow("Firmware version", value: MinerCapabilityPresentation.firmwareVersion(info: info))
                identityRow("AxeOS / web UI", value: MinerCapabilityPresentation.axeOSVersion(info: info))
                identityRow("ESP-IDF framework", value: MinerCapabilityPresentation.text(info?.raw["idfVersion"]))
                identityRow("Hostname", value: MinerCapabilityPresentation.hostname(info: info))
                Text("Values are reported by this device. Missing fields do not mean unsupported hardware.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            } header: {
                Text(store.isDemo ? "Sample identity" : "Reported identity")
            }
            .listRowBackground(FleetTheme.surface)
        }

        func identityRow(_ title: String, value: String?) -> some View {
            LabeledContent(title) {
                Text(value ?? MinerCapabilityPresentation.notReported)
                    .foregroundStyle(value == nil ? FleetTheme.secondary : FleetTheme.ink)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .fleetFont(.callout)
        }

        // MARK: - Raw payloads
}
