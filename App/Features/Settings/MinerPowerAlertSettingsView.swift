import SwiftUI
import HashFleetCore

struct MinerPowerAlertSettingsView: View {
    let device: MinerDevice
    @State private var model: MinerPowerAlertSettingsModel
    @Environment(\.openURL) private var openURL

    init(device: MinerDevice, preferences: FleetPowerAlertPreferences) {
        self.device = device
        _model = State(initialValue: MinerPowerAlertSettingsModel(deviceID: device.id, preferences: preferences))
    }

    var body: some View {
        FleetSettingsForm {
            policySection
            behaviorSection
            deliverySection
        }
        .tint(FleetTheme.accent)
        .navigationTitle("Power alert")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("powerAlerts.minerPage")
    }

    private var policySection: some View {
        FleetSettingsSection(content: {
            FleetSettingsRow { Text(device.name).fleetFont(.headline) }
            FleetSettingsRow {
                Toggle("Enable power alerts", isOn: $model.isEnabled)
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("powerAlerts.enabled")
            }
            FleetSettingsRow {
                TextField("Alert threshold (W)", text: $model.thresholdText)
                    .keyboardType(.decimalPad)
                    .disabled(model.isSaving)
                    .accessibilityLabel("Alert threshold in watts")
                    .accessibilityIdentifier("powerAlerts.threshold")
            }
            if model.proposedPolicy == nil {
                FleetSettingsRow {
                    Text(MinerPowerAlertPolicy.ValidationError.invalidThreshold.localizedDescription)
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.warning)
                        .accessibilityIdentifier("powerAlerts.validation")
                }
            }
            FleetSettingsRow {
                Button("Save alert settings") {
                    Task { await model.save() }
                }
                .disabled(model.isSaving || model.proposedPolicy == nil || !model.hasChanges)
                .accessibilityIdentifier("powerAlerts.save")
            }
            if model.hasChanges {
                FleetSettingsRow {
                    Text("Changes are not applied until you save.")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                }
            }
            if model.isSaving {
                FleetSettingsRow { ProgressView("Checking notification permission…") }
            }
            if let message = model.savedMessage {
                FleetSettingsRow(showsSeparator: false) {
                    Text(message).fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                        .accessibilityIdentifier("powerAlerts.saved")
                }
            }
            if let error = model.error {
                FleetSettingsRow(showsSeparator: false) {
                    Text(error).fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                        .accessibilityIdentifier("powerAlerts.error")
                }
            }
        }, header: {
            Text("This miner only")
        }, footer: {
            Text("Off by default. Save applies only to this miner. The threshold is in watts. No fan, tuning or hardware protection settings are changed.")
        })
    }

    private var behaviorSection: some View {
        FleetSettingsSection("When an alert is detected") {
            FleetSettingsRow { Text("The first fresh power reading at or above your threshold can alert immediately. "
                + "Missing, invalid, offline and cached readings never trigger alerts.") }
            FleetSettingsRow { Text("One alert per high-power episode. When watts fall back below your threshold "
                + "you get a return-to-normal notification, and the alarm can fire again after "
                + "a 30-minute cooldown, which applies even across app restarts.") }
            FleetSettingsRow { Text("Changing an alert policy begins a new episode, but does not bypass the cooldown.") }
            FleetSettingsRow(showsSeparator: false) {
                Text("The 1–5000 W entry range is not a safe operating recommendation. "
                    + "Follow your miner manufacturer's limits. "
                    + "This alert is not a hardware safety system or automatic shutdown.")
                    .foregroundStyle(FleetTheme.warning)
            }
        }
        .fleetFont(.footnote)
    }

    private var deliverySection: some View {
        FleetSettingsSection("Notification delivery") {
            FleetSettingsRow {
                Text("High-power alarms and their resolutions post as local notifications, including while Fleet is open. Enable High-power alerts under Notifications, too.")
            }
#if os(macOS)
            FleetSettingsRow {
                Text("Hash Fleet continues local monitoring while its window is closed. Quitting the app stops checks. "
                    + "Focus and notification settings may delay or silence delivery.")
            }
#else
            FleetSettingsRow {
                Text("\(FleetDeviceCopy.current.systemName) chooses when background checks run. Checks may be delayed or not run, "
                    + "especially after force-quitting. There is no guaranteed check interval "
                    + "or continuous background protection. Focus and Scheduled Summary may delay delivery.")
            }
#endif
            FleetSettingsRow(showsSeparator: false) { notificationSettingsButton }
        }
        .fleetFont(.footnote)
    }

    @ViewBuilder
    private var notificationSettingsButton: some View {
#if os(macOS)
        Button("Open Notification Settings", systemImage: "arrow.up.forward.app") {
            openURL(FleetNotificationSettingsModel.settingsURL)
        }
        .accessibilityIdentifier("powerAlerts.openSettings")
#else
        Button("Open Settings", systemImage: "arrow.up.forward.app") {
            openURL(FleetNotificationSettingsModel.settingsURL)
        }
        .accessibilityIdentifier("powerAlerts.openSettings")
#endif
    }
}
