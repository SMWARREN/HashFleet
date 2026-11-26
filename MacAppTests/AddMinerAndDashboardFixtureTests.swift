import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Add-miner and dashboard branches driven by MinerFixtures: XMRig kind, validation errors,
/// already-present candidates, and dashboard sheet routes. Offline only. No discovery scan,
/// no request, no socket. Discovery coordinators are never started.
@Suite("Add miner and dashboard fixture branches", .serialized)
@MainActor
struct AddMinerAndDashboardFixtureTests {
    private func makeStore() -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.addfixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
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

    @Test func evaluateAddMinerXMRigKindWithValidationError() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        evaluate(AddMinerView(
            store: store, minerKind: .xmrig, name: "Xmrig Box", address: "10.0.0.9",
            bearerToken: "secret-token", validationError: "XMRig API did not respond."
        ))
        evaluate(AddMinerView(
            store: store, minerKind: .xmrig, name: "", address: "", bearerToken: "",
            isValidating: true
        ), width: 420, height: 1400)
    }

    @Test func evaluateAddMinerAlreadyPresentAndDiscoveryError() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing = MinerFixtures.device(name: "Existing", kind: .espMiner)
        store.devices = [existing]
        store.snapshots[existing.id] = MinerFixtures.snapshot(MinerFixtures.healthyFields())
        evaluate(AddMinerView(
            store: store, name: "Existing", address: existing.address,
            discoveryAddError: "Already in your fleet."
        ))
        evaluate(AddMinerView(
            store: store, isManualExpanded: true, addedAddresses: [existing.address]
        ), width: 420, height: 1400)
    }

    @Test func evaluateDashboardWithFaultedAndSparseMiners() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let faulted = MinerFixtures.device(name: "Faulted", family: "bitaxe")
        let sparse = MinerFixtures.device(name: "Sparse", family: "bitaxe")
        store.devices = [faulted, sparse]
        store.snapshots[faulted.id] = MinerFixtures.snapshot(MinerFixtures.faultedFields())
        store.snapshots[sparse.id] = MinerFixtures.snapshot(MinerFixtures.sparseFields(), error: "timed out")
        evaluate(DashboardView(store: store, startupReady: true, onToggleSidebar: {}, onSelectSidebarDestination: { _ in }))
        evaluate(DashboardView(store: store, startupReady: false), width: 420, height: 900)
    }
}
