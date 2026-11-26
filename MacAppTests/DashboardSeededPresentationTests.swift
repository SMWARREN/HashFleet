import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// DashboardView presentation branches seeded through the DEBUG initializer, with MinerFixtures.
/// Covers the remove-miner alert, the tuning and XMRig navigation destinations, the miner settings
/// route, and the search bar. Offline only: no refresh runs, no request is sent, and no socket opens.
@Suite("Dashboard seeded presentation evaluation", .serialized)
@MainActor
struct DashboardSeededPresentationTests {
    private func makeStore(devices: [MinerDevice], snapshots: [UUID: MinerSnapshot]) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.dashseed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        store.devices = devices
        store.snapshots = snapshots
        return (store, defaults, suite)
    }

    private func evaluate<V: View>(_ view: V, width: CGFloat = 1200, height: CGFloat = 1000) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    @Test func evaluateDashboardRemoveAlertPresented() {
        let target = MinerFixtures.device(name: "Gamma")
        let (store, defaults, suite) = makeStore(
            devices: [target],
            snapshots: [target.id: MinerFixtures.snapshot(MinerFixtures.healthyFields())]
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = MiningInsightsStore()
        evaluate(DashboardView(store: store, insights: insights, startupReady: true, seededRemoval: target))
    }

    @Test func evaluateDashboardTuningAndXMRigDestinations() {
        let tuning = MinerFixtures.device(name: "Tune", kind: .espMiner)
        let xmrig = MinerFixtures.device(name: "Box", kind: .xmrig, family: "xmrig")
        let (store, defaults, suite) = makeStore(
            devices: [tuning, xmrig],
            snapshots: [
                tuning.id: MinerFixtures.snapshot(MinerFixtures.healthyFields()),
                xmrig.id: MinerFixtures.snapshot(MinerFixtures.healthyFields(family: "xmrig"))
            ]
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = MiningInsightsStore()
        evaluate(DashboardView(store: store, insights: insights, startupReady: true, seededTuningDevice: tuning))
        evaluate(DashboardView(store: store, insights: insights, startupReady: true, seededXMRigDevice: xmrig))
    }

    @Test func evaluateDashboardSettingsRouteAndSearch() {
        let miner = MinerFixtures.device(name: "Settings Rig")
        let (store, defaults, suite) = makeStore(
            devices: [miner],
            snapshots: [miner.id: MinerFixtures.snapshot(MinerFixtures.faultedFields())]
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = MiningInsightsStore()
        let route = DashboardMinerSettingsRoute(device: miner, category: .pools)
        evaluate(DashboardView(store: store, insights: insights, startupReady: true, seededSettings: route))
        evaluate(DashboardView(
            store: store, insights: insights, startupReady: true,
            showsSearch: true, searchText: "Settings"
        ), width: 420, height: 900)
    }

    @Test func evaluateDashboardSheetsSeeded() {
        let (store, defaults, suite) = makeStore(devices: [], snapshots: [:])
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = MiningInsightsStore()
        evaluate(DashboardView(store: store, insights: insights, startupReady: true, showingAddMiner: true))
        evaluate(DashboardView(store: store, insights: insights, startupReady: true, showingSettings: true))
        evaluate(DashboardView(store: store, insights: insights, startupReady: true, showingSupport: true))
        evaluate(DashboardView(store: store, insights: insights, startupReady: true, showingAbout: true))
    }
}
