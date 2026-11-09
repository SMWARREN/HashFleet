import SwiftUI
import HashFleetCore

struct FleetTemperatureAlertsView: View {
    let devices: [MinerDevice]
    let preferences: FleetTemperatureAlertPreferences
    var isDemo = false

    var body: some View {
        FleetSettingsForm {
            if isDemo {
                FleetSettingsSection {
                    FleetSettingsRow(showsSeparator: false) {
                        Text("Demo telemetry never triggers temperature alerts. Configure your saved real miners here.")
                            .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                    }
                }
            }
            FleetSettingsSection(content: {
                if devices.isEmpty {
                    FleetSettingsRow(showsSeparator: false) {
                        ContentUnavailableView("No miners yet", systemImage: "thermometer.medium",
                            description: Text("Add a miner to configure its temperature alert."))
                    }
                }
                ForEach(devices) { device in
                    FleetSettingsRow {
                        NavigationLink {
                            MinerTemperatureAlertSettingsView(device: device, preferences: preferences)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name).foregroundStyle(FleetTheme.ink)
                                Text(summary(for: device.id))
                                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("temperatureAlerts.miner.\(device.id.uuidString)")
                    }
                }
            }, header: {
                Text("Per-miner alerts")
            }, footer: {
                Text("Every miner starts with alerts off. Thresholds are local app preferences, "
                    + "not firmware controls. Temperature checks and notification delivery are best effort, "
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
        .navigationTitle("Temperature alerts")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("temperatureAlerts.fleetPage")
    }

    private func summary(for deviceID: UUID) -> String {
        let policy = preferences.policy(for: deviceID)
        guard policy.isEnabled else { return "Off" }
        return "On · \(policy.thresholdCelsius.formatted(.number.precision(.fractionLength(0...1)))) °C"
    }
}
