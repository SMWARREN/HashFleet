import SwiftUI
import HashFleetCore

struct MinerTemperatureAlertSettingsView: View {
    let device: MinerDevice
    @State private var model: MinerTemperatureAlertSettingsModel
    @Environment(\.openURL) private var openURL

    init(device: MinerDevice, preferences: FleetTemperatureAlertPreferences) {
        self.device = device
        _model = State(initialValue: MinerTemperatureAlertSettingsModel(deviceID: device.id, preferences: preferences))
    }

    var body: some View {
        FleetSettingsForm {
            policySection
            behaviorSection
            deliverySection
        }
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .navigationTitle("Temperature alert")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("temperatureAlerts.minerPage")
    }

    private var policySection: some View {
        FleetSettingsSection(
            header: AnyView(Text("This miner only")),
            footer: AnyView(Text("""
                Off by default. Save applies only to this miner. The threshold is in Celsius even if other \
                displays use different units. No fan, tuning or hardware protection settings are changed.
                """))
        ) {
            FleetSettingsRow { Text(device.name).fleetFont(.headline) }
            FleetSettingsRow {
            Toggle("Enable temperature alerts", isOn: $model.isEnabled)
                .disabled(model.isSaving)
                .accessibilityIdentifier("temperatureAlerts.enabled")
            }
            FleetSettingsRow {
            TextField("Alert threshold (°C)", text: $model.thresholdText)
                .keyboardType(.decimalPad)
                .disabled(model.isSaving)
                .accessibilityLabel("Alert threshold in degrees Celsius")
                .accessibilityIdentifier("temperatureAlerts.threshold")
            }
            if model.proposedPolicy == nil {
                Text(MinerTemperatureAlertPolicy.ValidationError.invalidThreshold.localizedDescription)
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.warning)
                    .accessibilityIdentifier("temperatureAlerts.validation")
            }
            FleetSettingsRow { Button("Save alert settings") {
                Task { await model.save() }
            }
            .disabled(model.isSaving || model.proposedPolicy == nil || !model.hasChanges)
            .accessibilityIdentifier("temperatureAlerts.save") }
            if model.hasChanges {
                Text("Changes are not applied until you save.")
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
            }
            if model.isSaving { ProgressView("Checking notification permission…") }
            if let message = model.savedMessage {
                Text(message).fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                    .accessibilityIdentifier("temperatureAlerts.saved")
            }
            if let error = model.error {
                Text(error).fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                    .accessibilityIdentifier("temperatureAlerts.error")
            }
        }
        .listRowBackground(FleetTheme.surface)
    }

    private var behaviorSection: some View {
        FleetSettingsSection("When an alert is detected") {
            Text("The first fresh primary-chip reading at or above your threshold can alert immediately. "
                + "Missing, invalid, offline and cached readings never trigger alerts.")
            Text("One alert per hot episode. A fresh reading at least 5 °C below your threshold rearms it. "
                + "Another hot reading can alert only after a 30-minute cooldown, which applies even "
                + "across app restarts.")
            Text("Changing an alert policy begins a new episode, but does not bypass the cooldown.")
            Text("The 30–110 °C entry range is not a safe operating recommendation. "
                + "Follow your miner manufacturer's limits. "
                + "This alert is not a hardware safety system or automatic shutdown.")
                .foregroundStyle(FleetTheme.warning)
        }
        .fleetFont(.footnote)
        .listRowBackground(FleetTheme.surface)
    }

    private var deliverySection: some View {
        FleetSettingsSection("Notification delivery") {
#if os(macOS)
            Text("Local notifications require permission and a reachable miner. Hash Fleet continues monitoring while its window is closed; quitting the app stops checks.")
#else
            Text("While Fleet is open, detected heat warnings stay in the app. Away from the app, local notifications are best effort and require system permission and a reachable miner.")
            Text("\(FleetDeviceCopy.current.systemName) chooses when background checks run. Checks may be delayed or not run, "
                + "especially after force-quitting. There is no guaranteed check interval "
                + "or continuous background protection. Focus and Scheduled Summary may delay delivery.")
#endif
            notificationSettingsButton
        }
        .fleetFont(.footnote)
        .listRowBackground(FleetTheme.surface)
    }

    @ViewBuilder
    private var notificationSettingsButton: some View {
#if os(macOS)
        Button("Open Notification Settings", systemImage: "arrow.up.forward.app") {
            openURL(FleetNotificationSettingsModel.settingsURL)
        }
        .accessibilityIdentifier("temperatureAlerts.openSettings")
#else
        Button("Open Settings", systemImage: "arrow.up.forward.app") {
            openURL(FleetNotificationSettingsModel.settingsURL)
        }
        .accessibilityIdentifier("temperatureAlerts.openSettings")
#endif
    }
}
