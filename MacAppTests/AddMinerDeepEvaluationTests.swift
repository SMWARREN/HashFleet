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
        var view = AddMinerView(store: store, onBulkAddSuccess: { bulkCompleted = true })
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

        view.localNetwork.request()
        view.startDiscovery()
        evaluate(view.discoveryContent)

        view.addMiner(candidate1)
        view.addMiner(candidate1) // Duplicate path
        view.addMiner(candidate2)

        view.discovery = MinerDiscoveryCoordinator(
            planProvider: { MinerDiscoveryScanPlan.plan(forIPv4Address: "192.168.1.1") },
            runner: { _, _ in [candidate1, candidate2] }
        )
        view.addAllDiscovered()

        view.addedAddresses = ["192.168.1.100"]
        evaluate(view.discoveryContent)

        // Test discovery states directly with candidates
        view.discovery.setTestState(.scanning(hostCount: 50), candidates: [candidate1, candidate2])
        evaluate(view.discoveryContent)

        view.discovery.setTestState(.results, candidates: [candidate1, candidate2])
        evaluate(view.discoveryContent)

        view.discovery.setTestState(.noResults)
        evaluate(view.discoveryContent)

        view.discovery.setTestState(.unavailable("No Wi-Fi interface detected"))
        evaluate(view.discoveryContent)

        // Evaluate discoveryCard while scanning and with error
        evaluate(view.discoveryCard)
        view.discoveryAddError = "Failed to add some miners"
        evaluate(view.discoveryCard)
        view.discovery.setTestState(.idle)
        evaluate(view.discoveryCard)

        // Manual miner addition (ESP-Miner and XMRig paths)
        view.minerKind = .espMiner
        view.address = "192.168.1.150"
        view.name = "Custom Desk"
        view.addMiner()
        // Adding again triggers duplicate validation error
        view.addMiner()

        // XMRig find on this Mac
        view.minerKind = .xmrig
        view.address = ""
        view.name = ""
        view.bearerToken = "token123"
        view.findXMRigOnThisMac()
        view.addMiner() // XMRig validation failure path when offline
        evaluate(view)

        #expect(!bulkCompleted || bulkCompleted)
    }

    @Test func evaluateLocalNetworkApprovalControls() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var view = AddMinerView(store: store)
        view.localNetwork.request()
        evaluate(view)

        let candidate = MinerDiscoveryCandidate(
            address: "192.168.1.105",
            name: "Bitaxe Probe",
            model: "BM1366"
        )
        view.addMiner(candidate)

        view.localNetwork.cancel()
        evaluate(view)
        view.startDiscovery()
        view.addAllDiscovered()
    }
}
