import SwiftUI

struct FleetWidgetSettingsPage: View {
    let store: FleetStore
    @Bindable var coordinator: FleetGlanceCoordinator

    var body: some View {
        FleetSettingsForm {
            FleetSettingsSection(
                footer: "Shares only hashrate, power and counts. Local widget refresh is a separate, optional permission below."
            ) {
                Toggle(
                    "Share fleet readings",
                    isOn: Binding(
                        get: { coordinator.sharesWithWidgets },
                        set: { coordinator.setWidgetSharing($0, glance: store.glance) }
                    )
                )
                .accessibilityIdentifier("monitoring.widgetSharing")
            }

            FleetSettingsSection {
                Toggle("Allow widget refresh", isOn: Binding(
                    get: { coordinator.allowsWidgetRefresh },
                    set: { coordinator.setWidgetRefreshEnabled($0,
                        devices: store.visibleDevices, snapshots: store.snapshots, isDemo: store.isDemo) }
                ))
                .disabled(!coordinator.sharesWithWidgets || store.isDemo || !coordinator.widgetStorageAvailable)
                .accessibilityIdentifier("monitoring.widgetRefresh")
                Toggle("Refresh automatically", isOn: Binding(
                    get: { coordinator.allowsAutomaticWidgetRefresh },
                    set: { coordinator.setAutomaticWidgetRefreshEnabled($0,
                        devices: store.visibleDevices, snapshots: store.snapshots, isDemo: store.isDemo) }
                ))
                .disabled(!coordinator.allowsWidgetRefresh || store.isDemo || !coordinator.widgetStorageAvailable)
                .accessibilityIdentifier("monitoring.automaticWidgetRefresh")
                Text(coordinator.widgetRefreshStatus)
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityIdentifier("monitoring.widgetRefreshStatus")
            } header: {
                Text("Optional local refresh")
            } footer: {
                Text("""
                    Off by default. Allow widget refresh enables reads when you tap Refresh. Refresh automatically \
                    additionally allows reads when iOS runs the widget, without tapping. iOS controls the schedule, \
                    not a continuous live feed. Shares local IP addresses and MAC identity pins with the bundled \
                    widget, never names or credentials. No uploads or miner setting changes. Requires a recent \
                    foreground connection and Local Network permission in Hash Fleet.
                    """)
            }

            FleetSettingsSection {
                FleetGlancePreviewCard(glance: store.glance, showsDetails: false)
            } header: {
                Text("Widget preview")
            } footer: {
                Text("A clean, at-a-glance view of your fleet.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            FleetSettingsSection {
                MonitoringNoteRow(
                    symbol: "lock.shield",
                    title: "Privacy",
                    message: "Saved readings contain only fleet aggregates. Optional local refresh also shares local IP "
                        + "addresses and MAC identity pins with the bundled widget. Never miner names or credentials.",
                    tint: FleetTheme.accent
                )
            }

            if !coordinator.widgetStorageAvailable {
                FleetSettingsSection {
                    Label(
                        "Widget sharing needs App Group setup in this build.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
                    DisclosureGroup("Setup details") {
                        Text(
                            "Enable the same App Group for the app and widget extension "
                                + "in Xcode Signing & Capabilities. The source documentation includes the setup steps."
                        )
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                    }
                }
            }

            FleetSettingsSection {
                DisclosureGroup {
                    Text("Touch and hold the Home Screen. Choose Edit → Add Widget, then search for Hash Fleet.")
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                        .padding(.vertical, 4)
                } label: {
                    MonitoringDestinationLabel(
                        title: "Add to Home Screen",
                        subtitle: "Instructions for adding the widget to your \(FleetDeviceCopy.current.name) Home Screen.",
                        symbol: FleetDeviceCopy.current.symbol
                    )
                }
                DisclosureGroup {
                    Text("Touch and hold the Lock Screen, choose Customize, then add a Hash Fleet widget.")
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                        .padding(.vertical, 4)
                } label: {
                    MonitoringDestinationLabel(
                        title: "Add to Lock Screen",
                        subtitle: "Instructions for adding the widget to your Lock Screen.",
                        symbol: FleetDeviceCopy.current.symbol
                    )
                }
            } header: {
                Text("Add widgets")
            }

            FleetSettingsSection {
                MonitoringNoteRow(
                    symbol: "info.circle",
                    title: nil,
                    message: "Saved snapshots, not live streaming. \(FleetDeviceCopy.current.systemName) controls refresh timing.",
                    tint: FleetTheme.secondary
                )
                DisclosureGroup("How readings stay fresh") {
                    Text(
                        "Widgets use your latest saved aggregate snapshot, not a continuous connection. "
                            + "When sharing is enabled, Hash Fleet asks \(FleetDeviceCopy.current.systemName) for a best-effort local background refresh "
                            + "about every 15 minutes. \(FleetDeviceCopy.current.systemName) controls timing and may delay it. "
                            + "Readings become stale after 60 seconds; opening Hash Fleet starts an immediate "
                            + "in-app refresh. Realtime miner readings stay inside Fleet while it is open, "
                            + "and the timeline itself never connects to miners. If you separately enable local widget refresh, "
                            + "tapping Refresh makes one bounded read-only attempt on your local network. Unlock is required. "
                            + "A failed or incomplete attempt keeps the last saved reading and its original time."
                    )
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(MonitoringErrorAlert(coordinator: coordinator))
    }
}
