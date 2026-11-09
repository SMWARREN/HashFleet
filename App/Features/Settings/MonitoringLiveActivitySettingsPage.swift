import SwiftUI

struct FleetLiveActivitySettingsPage: View {
    let store: FleetStore
    @Bindable var coordinator: FleetGlanceCoordinator

    var body: some View {
        FleetSettingsForm {
            FleetSettingsSection {
                // The proposal leads with the status as a single prominent readout rather than a
                // plain row, and moves the start control out into its own full-width button.
                FleetSettingsRow(showsSeparator: false) {
                HStack(spacing: 14) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .fleetFont(.title2)
                        .foregroundStyle(FleetTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(FleetTheme.accent.opacity(0.08), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status").fleetFont(.subheadline).foregroundStyle(FleetTheme.secondary)
                        Text(coordinator.hasLiveActivity ? "Started" : "Not running")
                            .fleetFont(.title3, weight: .semibold)
                            .foregroundStyle(FleetTheme.ink)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                }
                FleetSettingsRow(showsSeparator: false) {
                Text("Local readings from your miners. No remote service is required.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                }
            }
            .listRowBackground(FleetTheme.surface)

            if store.isDemo {
                FleetSettingsSection {
                    FleetSettingsRow(showsSeparator: false) {
                    Label("Sample readings only. No hardware is connected in demo mode.", systemImage: "sparkles")
                        .fleetFont(.subheadline)
                        .foregroundStyle(FleetTheme.accent)
                    }
                }
                .listRowBackground(FleetTheme.surface)
            }

            FleetSettingsSection(
                header: AnyView(Text("Preview (Lock Screen)")),
                footer: AnyView(Text("A compact view on your Lock Screen.")),
                surface: Color.clear,
                contentInsets: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0),
                listRowInsets: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0),
                hidesListRowSeparators: true) {
                FleetSettingsRow(showsSeparator: false) {
                FleetGlancePreviewCard(glance: store.glance, showsDetails: true)
                }
            }

            FleetSettingsSection(header: nil, footer: footerView) {
                if coordinator.hasLiveActivity {
                    FleetSettingsRow(showsSeparator: false) {
                    Button("End Live Activity", role: .destructive) {
                        Task { await coordinator.stop() }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(coordinator.isChangingActivity)
                    .accessibilityIdentifier("monitoring.stopActivity")
                    }
                } else {
                    FleetSettingsRow(showsSeparator: false) {
                    Button {
                        Task { await coordinator.start(store.glance) }
                    } label: {
                        Label(
                            store.isDemo ? "Start sample Live Activity" : "Start Live Activity",
                            systemImage: "play.fill"
                        )
                        .fleetFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FleetTheme.accent)
                    .foregroundStyle(FleetTheme.buttonInk)
                    .disabled(store.visibleDevices.isEmpty || coordinator.isChangingActivity)
                    .accessibilityIdentifier("monitoring.startActivity")
                    }
                }
                if coordinator.isChangingActivity {
                    ProgressView("Updating Live Activity…")
                }
            }

            FleetSettingsSection {
                FleetSettingsRow(showsSeparator: false) {
                MonitoringNoteRow(
                    symbol: "clock",
                    message: "Updates with new app readings or a successful local widget refresh. Saved readings become stale after one minute."
                )
                MonitoringNoteRow(
                    symbol: "lock.shield",
                    message: "Requires system permission. You can turn this off anytime in Settings."
                )
                }
                FleetSettingsRow(showsSeparator: false) {
                DisclosureGroup("What appears on my Lock Screen?") {
                    Text(
                        "Hashrate, reported power and fleet counts appear on your Lock Screen "
                            + "and supported Dynamic Island. Miner addresses and credentials are never included."
                    )
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                }
                }
                FleetSettingsRow(showsSeparator: false) {
                DisclosureGroup("Availability and privacy") {
                    Text(
                        "Allow Live Activities for Hash Fleet in Settings. \(FleetDeviceCopy.current.systemName) may end them automatically. "
                            + "Hash Fleet does not use push notifications or continuous background monitoring "
                            + "to update readings."
                    )
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                }
                }
            }
            .listRowBackground(FleetTheme.surface)

            FleetSettingsSection(header: AnyView(Text("Updates on your Wi-Fi"))) {
                FleetSettingsRow {
                    MonitoringNoteRow(symbol: "wifi", message:
                        "While the app is open, monitoring reads your miners directly on their local network. Allow "
                            + "Local Network access and keep the miners reachable. Nothing needs to be sent to a cloud relay.")
                }
                FleetSettingsRow {
                    MonitoringNoteRow(symbol: "arrow.clockwise", message:
                        "For a manual update without opening the app, enable widget sharing and local widget refresh "
                            + "in Widgets, then start a new Live Activity. Tap Refresh on the widget and unlock when asked. "
                            + "A successful complete read updates that matching activity too.")
                }
                FleetSettingsRow {
                    MonitoringNoteRow(symbol: "moon", message:
                        "When the app is backgrounded or the phone is locked, iOS does not keep local monitoring running "
                            + "continuously just because Wi-Fi is connected. Automatic background refresh is occasional and "
                            + "system-controlled, not a live timer.")
                }
                FleetSettingsRow(showsSeparator: false) {
                    MonitoringNoteRow(symbol: "clock.badge.exclamationmark", message:
                        "If a refresh cannot complete, the last reading and its time stay visible. Stale means the "
                            + "reading is old, not that your miner is confirmed offline. Return to the miner network and "
                            + "refresh for a new observation.")
                }
            }
            .accessibilityIdentifier("monitoring.localUpdateExplanation")
        }
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .navigationTitle("Live Activity")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(MonitoringErrorAlert(coordinator: coordinator))
    }

    private var footerView: AnyView {
        AnyView(Text(
            store.visibleDevices.isEmpty
                ? "Connect a miner in Fleet to get started."
                : "Starts only when you choose. Ending an activity never pauses your miners."
        ))
    }
}
