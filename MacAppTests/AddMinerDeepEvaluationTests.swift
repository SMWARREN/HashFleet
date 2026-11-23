import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

@Suite("Add Miner Deep Evaluation", .serialized)
@MainActor
struct AddMinerDeepEvaluationTests {
    private func makeStore() -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.addminerdeep.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let session = URLSession(configuration: .ephemeral)
        let store = FleetStore(defaults: defaults, session: session)
        return (store, defaults, suite)
    }

    private func evaluate<V: View>(_ view: V, width: CGFloat = 800, height: CGFloat = 1200) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    @Test func evaluateAddMinerFormAndDiscoveryStates() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var bulkCompleted = false
        let view = AddMinerView(store: store, onBulkAddSuccess: { bulkCompleted = true })
        evaluate(view)

        let candidate1 = MinerDiscoveryCandidate(
            address: "192.168.1.100",
            name: "Bitaxe Test",
            model: "BM1366"
        )
        let candidate2 = MinerDiscoveryCandidate(
            address: "192.168.1.101",
            name: "Bitaxe Two",
            model: "BM1370"
        )

        view.discovery.start()
        evaluate(view.discoveryContent)

        view.addedAddresses = ["192.168.1.100"]
        evaluate(view.discoveryContent)

        #expect(!bulkCompleted)
    }

    @Test func evaluateLocalNetworkApprovalControls() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let view = AddMinerView(store: store)
        view.localNetwork.request()
        evaluate(view)

        view.localNetwork.cancel()
        evaluate(view)
    }
}
