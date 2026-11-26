import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// AddMinerView and DashboardView branches reached with MinerFixtures and no network:
/// XMRig picker and copy, the ESP-Miner discovery card with a seeded candidate state,
/// manual input expansion, and the dashboard with an XMRig miner and a miner pending removal.
/// Discovery is never started. XMRig validation, which performs a real API call, is not invoked.
@Suite("Add miner and dashboard fixture branches batch 2", .serialized)
@MainActor
struct AddMinerDashboardFixtureBatchTwoTests {
    private func makeStore(devices: [MinerDevice] = [], snapshots: [UUID: MinerSnapshot] = [:])
        -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.addbatch2.\(UUID().uuidString)"
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

    @Test func evaluateAddMinerXMRigPickerCopyWithoutValidation() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        // XMRig copy and picker state, with no submission, so no XMRig API request is made.
        evaluate(AddMinerView(store: store, minerKind: .xmrig, name: "Box", address: "10.0.0.9"))
        evaluate(AddMinerView(store: store, minerKind: .xmrig, name: "", address: ""), width: 420, height: 1400)
    }

    @Test func evaluateAddMinerDiscoveryCardWithFleetMembers() {
        let existing = MinerFixtures.device(name: "Existing", kind: .espMiner)
        let (store, defaults, suite) = makeStore(
            devices: [existing],
            snapshots: [existing.id: MinerFixtures.snapshot(MinerFixtures.healthyFields())]
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        evaluate(AddMinerView(
            store: store, name: "Next", address: "192.168.1.99", bearerToken: "",
            isFindingThisMac: true
        ))
        evaluate(AddMinerView(
            store: store, isManualExpanded: true, addedAddresses: [existing.address]
        ), width: 420, height: 1400)
    }

    @Test func evaluateDashboardWithXMRigAndPendingRemoval() {
        let xmrig = MinerFixtures.device(name: "Box", kind: .xmrig, family: "xmrig")
        let asic = MinerFixtures.device(name: "Gamma", kind: .espMiner)
        let (store, defaults, suite) = makeStore(
            devices: [xmrig, asic],
            snapshots: [
                xmrig.id: MinerFixtures.snapshot(MinerFixtures.healthyFields(family: "xmrig")),
                asic.id: MinerFixtures.snapshot(MinerFixtures.faultedFields())
            ]
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        evaluate(DashboardView(store: store, startupReady: true, onToggleSidebar: {}, onSelectSidebarDestination: { _ in }))
        evaluate(DashboardView(store: store, startupReady: true), width: 420, height: 900)
    }
}
