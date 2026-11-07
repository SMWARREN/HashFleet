import SwiftUI
import HashFleetCore

struct FleetPowerAlertsView: View {
    let devices: [MinerDevice]
    let preferences: FleetPowerAlertPreferences
    var isDemo = false

    var body: some View {
        FleetSettingsForm {
            if isDemo {
                FleetSettingsSection {
                    FleetSettingsRow(showsSeparator: false) {
                        Text("Demo telemetry never triggers power alerts. Configure your saved real miners here.")
                            .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                    }
                }
            }
            FleetSettingsSection(content: {
                if devices.isEmpty {
                    FleetSettingsRow(showsSeparator: false) {
                        ContentUnavailableView("No miners yet", systemImage: "bolt.trianglebadge.exclamationmark",
                            description: Text("Add a miner to configure its power alert."))
                    }
                }
                ForEach(devices) { device in
                    FleetSettingsRow {
                        NavigationLink {
                            MinerPowerAlertSettingsView(device: device, preferences: preferences)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name).foregroundStyle(FleetTheme.ink)
                                Text(summary(for: device.id))
                                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("powerAlerts.miner.\(device.id.uuidString)")
                    }
                }
            }, header: {
                Text("Per-miner alerts")
            }, footer: {
                Text("Every miner starts with alerts off. Thresholds are local app preferences, "
                    + "not firmware controls. Power checks and notification delivery are best effort, "
                    + "not continuous protection.")
            })
            if let error = preferences.persistenceError {
                FleetSettingsSection {
                    FleetSettingsRow(showsSeparator: false) {
                        Text(error).foregroundStyle(FleetTheme.warning).fleetFont(.footnote)
                    }
                }
            }
        }
        .tint(FleetTheme.accent)
        .navigationTitle("Power alerts")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("powerAlerts.fleetPage")
    }

    private func summary(for deviceID: UUID) -> String {
        let policy = preferences.policy(for: deviceID)
        guard policy.isEnabled else { return "Off" }
        return "On · \(policy.thresholdWatts.formatted(.number.precision(.fractionLength(0...1)))) W"
    }
}
