import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Renders the dashboard empty-search card through the existing DEBUG seeds. A search string that
/// matches no miner makes filteredDevices empty, so the card renders. No request, no socket.
@Suite("Seeded tuning mode and dashboard empty search evaluation", .serialized)
@MainActor
struct SeededModeAndEmptySearchTests {
    private func makeStore(devices: [MinerDevice] = [], snapshots: [UUID: MinerSnapshot] = [:])
        -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.modeempty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        store.devices = devices
        store.snapshots = snapshots
        return (store, defaults, suite)
    }

    private func evaluate<V: View>(_ view: V, width: CGFloat = 900, height: CGFloat = 1600) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    @Test func evaluateDashboardEmptySearchCard() {
        let miner = MinerFixtures.device(name: "Gamma")
        let (store, defaults, suite) = makeStore(
            devices: [miner],
            snapshots: [miner.id: MinerFixtures.snapshot(MinerFixtures.healthyFields())]
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = MiningInsightsStore()
        // The search string matches no miner, so filteredDevices is empty and the card renders.
        evaluate(DashboardView(
            store: store, insights: insights, startupReady: true,
            showsSearch: true, searchText: "zzz-no-such-miner"
        ))
    }
}
