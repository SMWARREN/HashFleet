import SwiftUI

struct AboutView: View {
    let store: FleetStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fleetStandalonePage) private var standalonePage

    private static let heroTagline =
        "A native, open-source companion for the independent miner. Built for Bitaxe and other open-source " +
        "devices running ESP-Miner."
    private static let privacyNote =
        "Use the same local network as your miners, or connect through a trusted VPN. ESP-Miner normally " +
        "uses unencrypted HTTP. Never expose its API directly to the internet."
    private static let publicDataNote =
        "Home shows free public data from mempool.space, Blockchair, CKPool and SoloFury while open. " +
        "These services see your internet IP. Aggregate requests do not send local miner addresses, " +
        "credentials or wallets. Disable external data in Fleet preferences for local-only monitoring."
    private static let poolDataNote =
        "Recognized configured pool slots, including fallback slots, use the public payout address from " +
        "miner settings to request account statistics from that pool. Worker suffixes and passwords stay " +
        "local. The pool overview redacts addresses and lookup data is not saved to disk. Manual CKPool " +
        "lookup is also available. Providers have their own privacy policies and availability limits."
    private static let monitoringNote =
        "When you open Fleet, it fetches a complete read-only snapshot. With Realtime miner readings enabled " +
        "in Fleet preferences, Hash Fleet keeps a live read-only stream when the miner supports it and " +
        "falls back to read-only HTTP when it does not. Turn Realtime off to use open and pull-to-refresh " +
        "snapshots only. Charts retain the latest 360 observations from this session, not permanent " +
        "history. Offline miners are excluded from fleet totals."
    #if os(iOS)
    private static let widgetNote =
        "When widget sharing is enabled, \(FleetDeviceCopy.current.systemName) may grant Hash Fleet a best-effort background refresh for the " +
        "aggregate widget snapshot. It is not continuous monitoring and timing is controlled by \(FleetDeviceCopy.current.systemName). " +
        "WebSocket streams run only while Fleet is open and active with Realtime enabled."
    #endif
    private static let independenceNote =
        "Hash Fleet is an independent community app, not an official Bitaxe or OSMU product. Endpoint " +
        "availability depends on your firmware version. Always back up settings before changing them."

    var body: some View {
        FleetSettingsList {
            FleetSettingsIntroduction(
                title: "Your hash. Your hardware.",
                message: Self.heroTagline,
                identifier: "about.hero"
            ) {
                FleetBrandMark(size: 64)
            }
            FleetSettingsSection {
                FleetSettingsRow(showsSeparator: false) {
                    #if os(macOS)
                    // The workspace owns native destinations. A destination-building link
                    // here re-enters AppKit layout when this settings row is activated.
                    NavigationLink(value: FleetSupportRoute.page) {
                        Label("Support Hash Fleet", systemImage: "heart")
                    }
                    .accessibilityIdentifier("about.support.link")
                    #else
                    NavigationLink {
                        DeveloperSupportView()
                            .environment(\.fleetStandalonePage, true)
                    } label: {
                        Label("Support Hash Fleet", systemImage: "heart")
                    }
                    .accessibilityIdentifier("about.support.link")
                    #endif
                }
            }
            #if os(macOS)
            // A short navigation row must not stretch to the height of its grid neighbour.
            .fleetSectionFullWidth()
            #endif
            FleetSettingsSection("Private by design") {
                FleetSettingsRow {
                    Label("Direct connection to your miners", systemImage: "wifi")
                }
                FleetSettingsRow {
                    Label("No Hash Fleet account or analytics", systemImage: "hand.raised")
                }
                FleetSettingsRow {
                    Label("Miner addresses stay on this device", systemImage: FleetDeviceCopy.current.symbol)
                }
                FleetSettingsRow(showsSeparator: false) {
                    Text(Self.privacyNote)
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
            FleetSettingsSection("Optional public data") {
                FleetSettingsRow {
                    Text(Self.publicDataNote)
                }
                FleetSettingsRow {
                    Text(Self.poolDataNote)
                }
                FleetSettingsRow {
                    Link("mempool.space", destination: URL(string: "https://mempool.space/")!)
                }
                FleetSettingsRow {
                    Link("Blockchair", destination: URL(string: "https://blockchair.com/")!)
                }
                FleetSettingsRow {
                    Link("SoloFury", destination: URL(string: "https://solofury.com/")!)
                }
                FleetSettingsRow(showsSeparator: false) {
                    Link("CKPool", destination: URL(string: "https://solo.ckpool.org/")!)
                }
            }
            FleetSettingsSection("Monitoring") {
                FleetSettingsRow(showsSeparator: false) {
                    Text(Self.monitoringNote)
                }
                #if os(iOS)
                FleetSettingsRow(showsSeparator: false) {
                    Text(Self.widgetNote)
                }
                #endif
            }
            FleetSettingsSection("Explore safely") {
                FleetSettingsRow {
                    Button(
                        store.isDemo ? "Leave demo and restore my fleet" : "Explore a sample fleet",
                        systemImage: "sparkles"
                    ) {
                        if store.isDemo { store.clearDemo() } else { store.loadDemo() }
                    }
                }
                FleetSettingsRow(showsSeparator: false) {
                    Text("Demo readings are sample data. Demo requests and controls are never sent over the network.")
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
            FleetSettingsSection("Open source") {
                FleetSettingsRow {
                    LabeledContent("Version", value: "0.1.0")
                }
                FleetSettingsRow {
                    LabeledContent("License", value: "GPL-3.0")
                }
                FleetSettingsRow {
                    Link(
                        "ESP-Miner firmware & community",
                        destination: URL(string: "https://github.com/bitaxeorg/ESP-Miner")!
                    )
                }
                FleetSettingsRow(showsSeparator: false) {
                    Text(Self.independenceNote)
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
        }
        .fleetFont(.body)
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .navigationTitle("About Hash Fleet")
        // The board uses the compact inline header on every sub-page rather than an iOS large title.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !standalonePage {
                ToolbarItem(placement: FleetToolbarLocation.trailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fleetToolbarButton()
                    .foregroundStyle(FleetTheme.accent)
                    .accessibilityIdentifier("about.done")
                }
                .fleetUnadornedToolbarBackground()
            }
        }
        .fleetPerformanceScreen("About")
    }
}

#Preview("About") {
    NavigationStack { AboutView(store: FleetStore()) }
}
