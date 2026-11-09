#if os(iOS)
import SwiftUI
import HashFleetCore
import HashFleetWatchCore

struct FleetWatchSettingsPage: View {
    let store: FleetStore
    @State private var setup = FleetWatchSetupCoordinator.shared

    private var eligibleMiners: [WatchMiner] {
        FleetWatchSetupSelection(devices: store.savedDevices, isDemo: store.isDemo).miners
    }

    var body: some View {
        FleetSettingsForm {
            FleetSettingsSection(header: AnyView(Text("Independent Watch app"))) {
                Text("Your miners, even when your phone is off.")
                    .fleetFont(.headline)
                Text("Hash Fleet on Apple Watch keeps its own miner list and reads miners directly over your local Wi-Fi. Your iPhone is optional after setup.")
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FleetSettingsSection(
                header: AnyView(Text("Optional one-time setup")),
                footer: AnyView(Text("Confirm Import on your Watch. This adds missing local miners only. It never deletes existing Watch entries or changes any miner settings."))
            ) {
                if store.isDemo {
                    Text("Exit demo before sending your real miners. You can explore sample data separately on the Watch.")
                        .fleetFont(.subheadline)
                } else {
                    ForEach(eligibleMiners) { miner in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(miner.name).fleetFont(.headline)
                            Text(miner.address).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                        }
                        .privacySensitive()
                    }
                    if store.savedDevices.count != eligibleMiners.count {
                        Text("Only credential-free local ESP-Miner addresses are supported. XMRig, credential-protected and nonlocal entries are not sent.")
                            .fleetFont(.footnote)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                    if eligibleMiners.isEmpty {
                        Text("Add a supported local miner to Fleet, or enter its address directly on your Watch.")
                            .fleetFont(.subheadline)
                    }
                    Button {
                        setup.send(eligibleMiners)
                    } label: {
                        Label("Send \(eligibleMiners.count) miners to Watch", systemImage: "applewatch")
                    }
                    .disabled(!setup.canSend || eligibleMiners.isEmpty || eligibleMiners.count > 16)
                    .accessibilityIdentifier("monitoring.watch.send")
                }
                Text(setup.status)
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("monitoring.watch.status")
            }

            FleetSettingsSection(header: AnyView(Text("Connection and privacy"))) {
                Text("Keep the Watch on a Wi-Fi network that can reach your miners. Cellular alone cannot reach private home-network addresses. No cloud relay or public miner access is configured.")
                Text("The Watch refreshes while its app is active. When unreachable, it retains the last reading and its real time. Stale does not mean the miner is confirmed offline.")
                Text("This setup sends names and local addresses only. Pool credentials, wallet addresses, Wi-Fi secrets and miner settings are never transferred.")
            }
            .fleetFont(.footnote)
            .foregroundStyle(FleetTheme.secondary)
        }
        .navigationTitle("Apple Watch")
        .task { setup.start() }
        .accessibilityIdentifier("monitoring.watch.page")
    }
}
#endif
