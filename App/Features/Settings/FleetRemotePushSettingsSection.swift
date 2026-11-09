import SwiftUI

/// Native-only controls in the existing Notifications group, shared by iOS and the primary Mac app.
struct FleetRemotePushSettingsSection: View {
    @State private var model = FleetRemotePushCoordinator.shared
    @State private var confirmDisconnect = false

    var body: some View {
        Section {
            Toggle("Scheduled miner summaries", isOn: Binding(
                get: { model.settings.enabled },
                set: { value in Task { await model.setEnabled(value) } }
            ))
            .disabled(!model.canConnect || model.isWorking || model.isRequestingPermission)
            .accessibilityIdentifier("notifications.remote.enabled")

            MonitoringNoteRow(symbol: "network", title: "Your device checks the miners",
                message: "When you opt in, hashfleet.app sends a scheduled Apple Push request. "
                    + "This device then attempts a short, read-only check of the selected miners. "
                    + "Only the push token, opaque miner IDs and schedule settings go to the service. "
                    + "Names, LAN addresses and miner readings stay on this device.")

            if !model.canConnect {
                Text("Cloud enrollment and scheduled LAN checks are disabled in demos and automated tests.")
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                    .accessibilityIdentifier("notifications.remote.demoNotice")
            }

            if model.settings.enabled {
                ForEach(model.settings.miners) { miner in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(miner.name, isOn: Binding(
                            get: { model.settings.miners.first(where: { $0.id == miner.id })?.enabled ?? false },
                            set: { model.updateSchedule(id: miner.id, enabled: $0) }
                        ))
                        Picker("Request an update", selection: Binding(
                            get: { model.settings.miners.first(where: { $0.id == miner.id })?.intervalMinutes ?? 60 },
                            set: { model.updateSchedule(id: miner.id, interval: $0) }
                        )) {
                            ForEach(FleetRemoteMinerSchedule.intervals, id: \.self) { minutes in
                                Text(FleetRemoteMinerSchedule.title(for: minutes)).tag(minutes)
                            }
                        }
                        .disabled(!miner.enabled)
                        if miner.enabled {
                            Text(model.preparationStatus(id: miner.id))
                                .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                    .disabled(model.isWorking || !model.canConnect)
                    .accessibilityIdentifier("notifications.remote.miner.\(miner.id)")
                }
                Button("Save schedules and refresh status") { Task { await model.sync() } }
                    .frame(minHeight: 44)
                    .disabled(model.isWorking || !model.canConnect)
                    .accessibilityIdentifier("notifications.remote.save")
            }

            Text(model.message)
                .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("notifications.remote.status")
            if model.isWorking { ProgressView("Syncing notification settings…") }

            if model.isEnrolled || model.requiresReconnect {
                Button("Disconnect and delete server settings", role: .destructive) { confirmDisconnect = true }
                    .frame(minHeight: 44)
                    .disabled(model.isWorking || !model.canConnect)
                    .accessibilityIdentifier("notifications.remote.disconnect")
            }
        } header: {
            Text("Scheduled push summaries")
        } footer: {
            Text("Off by default, starting with hourly requests when enabled. No separate companion is needed. "
                + "This device must be able to reach the miners, usually on their Wi-Fi, and have Local Network "
                + "and notification permission. Apple controls delivery and the short check window, so updates "
                + "are best effort, not guaranteed hourly monitoring. An unsuccessful check does not prove "
                + "a miner is offline. A push already accepted by Apple may still appear after you turn this off.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(FleetTheme.surface)
        .confirmationDialog("Disconnect this installation?", isPresented: $confirmDisconnect) {
            Button("Delete this installation’s server settings", role: .destructive) {
                Task { await model.disconnect() }
            }
        } message: {
            Text("Removes its push token and schedules. Your local fleet, hardware, local alerts and other users are untouched.")
        }
    }
}
