#if os(iOS)
import AppIntents
import SwiftUI

/// Separates authenticated hardware commands from opt-in, read-only saved summaries.
struct FleetSystemFeaturesView: View {
    let sharesSavedReadings: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        FleetSettingsList {
            FleetSettingsSection("Siri & Shortcuts", footer: "Opening the fleet and reading its summary do not change miner settings. Hardware commands "
                + "require device authentication and a separate confirmation for the selected miner.") {
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .accessibilityIdentifier("systemFeatures.shortcuts")
                Text(
                    "Find Hash Fleet in Shortcuts to open your fleet, read its last saved summary, "
                        + "restart a saved miner, or change its frequency or manual fan speed. "
                        + "You can use these actions with Siri or assign a shortcut to a supported Action button."
                )
                .fleetFont(.subheadline)
                .foregroundStyle(FleetTheme.secondary)
            }
            .listRowBackground(FleetTheme.surface)

            FleetSettingsSection("Confirmed miner controls") {
                FleetSettingsRow { Label("Restart Fleet Miner", systemImage: "arrow.clockwise") }
                FleetSettingsRow { Label("Set Fleet Miner Frequency", systemImage: "speedometer") }
                FleetSettingsRow { Label("Set Fleet Miner Fan Speed", systemImage: "fan") }
                FleetSettingsRow {
                    Text(
                        "Choose a saved miner and the exact MHz or fan percentage in Shortcuts. "
                        + "Siri checks the connection, names the miner and the change, and asks for confirmation before sending. "
                        + "Manual fan speed turns automatic cooling off. "
                        + "Incorrect frequency or cooling settings can overheat or damage hardware."
                    )
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                }
                FleetSettingsRow {
                    Text(
                        "No command runs just because you edit a shortcut. "
                        + "Demo mode blocks hardware commands. Quick confirmation does not skip Siri confirmation. "
                        + "Pool and voltage changes are not exposed here."
                    )
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                }
            }
            .accessibilityIdentifier("systemFeatures.minerControls")
            .listRowBackground(FleetTheme.surface)

            FleetSettingsSection("Your readings stay private", footer: "Manage Share fleet readings in Settings → Widgets. Miner addresses, wallet addresses and credentials are never included.") {
                FleetSettingsRow {
                    LabeledContent(
                    "Saved-reading access",
                    value: sharesSavedReadings ? "Sharing enabled" : "Off"
                    )
                    .accessibilityIdentifier("systemFeatures.sharing")
                }
                FleetSettingsRow(showsSeparator: false) {
                Text(
                    "The summary requires device authentication and uses the same opt-in aggregate cache "
                        + "as widgets: hashrate, power and counts only. "
                        + "It includes the observation time and labels stale or sample readings. "
                        + "It never starts a miner connection."
                )
                .fleetFont(.subheadline)
                .foregroundStyle(FleetTheme.secondary)
                }
            }
            .listRowBackground(FleetTheme.surface)

            if #available(iOS 18, *) {
                FleetSettingsSection("Control Center & Lock Screen", footer: "Opening the app may require unlocking your device. This is an app launcher, not a mining switch.") {
                    FleetSettingsRow(showsSeparator: false) {
                    Label {
                        Text("Open Hash Fleet")
                    } icon: {
                        FleetBrandMark(size: 22)
                    }
                        .fleetFont(.headline)
                    }
                    FleetSettingsRow(showsSeparator: false) {
                    Text(
                        "In Control Center, touch and hold, choose Add a Control, then find Hash Fleet. "
                            + "You can also choose its Open Hash Fleet control "
                            + "while customizing supported Lock Screen controls."
                    )
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
                    }
                    FleetSettingsRow(showsSeparator: false) { openFleetControl }
                }
                .listRowBackground(FleetTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .navigationTitle("Shortcuts & Controls")
        .navigationBarTitleDisplayMode(.inline)
        .fleetPerformanceScreen("Shortcuts & Controls")
    }

    @ViewBuilder private var openFleetControl: some View {
        if #available(iOS 26, *), !reduceTransparency {
            openFleetButton.buttonStyle(.glass)
        } else {
            openFleetButton.buttonStyle(.bordered)
        }
    }

    private var openFleetButton: some View {
        Button(intent: OpenFleetIntent()) {
            Label("Open Hash Fleet", systemImage: "arrow.up.forward.app")
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
        }
        .accessibilityHint("Returns to your fleet without changing miner settings")
        .accessibilityIdentifier("systemFeatures.openFleet")
    }
}

#Preview("Shortcuts & controls") {
    NavigationStack {
        FleetSystemFeaturesView(sharesSavedReadings: false)
    }
}
#endif
