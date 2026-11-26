import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// MinerDetailView identity disclosure, expanded through the DEBUG seed. The detail rows read
/// fixture values only. Offline: no request, no socket, and the address is a placeholder.
@Suite("Miner detail identity fixture evaluation", .serialized)
@MainActor
struct MinerDetailIdentityFixtureTests {
    private func makeStore() -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.detailidentity.\(UUID().uuidString)"
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

    @Test func evaluateDetailIdentityDisclosureExpanded() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device(name: "Identity Rig")
        store.devices = [miner]
        store.snapshots[miner.id] = MinerFixtures.snapshot(MinerFixtures.healthyFields())
        evaluate(MinerDetailView(device: miner, store: store, showsIdentity: true))
        evaluate(MinerDetailView(device: miner, store: store, showsIdentity: true), width: 420, height: 1400)
    }

    @Test func evaluateDetailIdentityDisclosureCollapsed() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device(name: "Identity Rig")
        store.devices = [miner]
        store.snapshots[miner.id] = MinerFixtures.snapshot(MinerFixtures.faultedFields())
        evaluate(MinerDetailView(device: miner, store: store, showsIdentity: false))
    }
}
