import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// AddMinerView discovery card with an injected offline scan runner. The runner returns fixed
/// candidates from a plan built with fixed hosts. No network interface is read and no socket opens.
/// Covers the scanning card, the candidate count, Stop Scan, Add All, and local-network copy.
@Suite("Add miner discovery fixture evaluation", .serialized)
@MainActor
struct AddMinerDiscoveryFixtureTests {
    private func makeStore() -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.discoveryfixture.\(UUID().uuidString)"
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

    /// Fixed plan over two hosts. The plan is a plain value, so nothing about the device network is read.
    private func fixedPlan() -> MinerDiscoveryScanPlan {
        MinerDiscoveryScanPlan(localAddress: "192.168.1.2", hosts: ["192.168.1.10", "192.168.1.11"])
    }

    private func candidate(_ address: String, name: String) -> MinerDiscoveryCandidate {
        MinerDiscoveryCandidate(address: address, name: name, model: "BM1370", firmwareFamily: nil, detectedFamily: "bitaxe")
    }

    @Test func evaluateDiscoveryCardWhileScanningWithCandidates() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let found = [candidate("192.168.1.10", name: "Gamma"), candidate("192.168.1.11", name: "Alpha")]
        let coordinator = MinerDiscoveryCoordinator(
            planProvider: { fixedPlan() },
            runner: { _, progress in
                progress(found, 2)
                // Hold the scan open so the card stays in its scanning state while it renders.
                try await Task.sleep(for: .seconds(30))
                return found
            }
        )
        let localNetwork = LocalNetworkAuthorization(defaults: UserDefaults(suiteName: "app.hashfleet.mac.lna.discovery.\(UUID().uuidString)")!)
        localNetwork.markDenied()
        coordinator.start()
        // Let the fake runner report its first batch before the view is laid out.
        try? await Task.sleep(for: .milliseconds(200))
        evaluate(AddMinerView(store: store, discovery: coordinator, localNetwork: localNetwork))
        evaluate(AddMinerView(store: store, discovery: coordinator, localNetwork: localNetwork), width: 420, height: 1400)
        coordinator.cancel()
    }

    @Test func evaluateLocalNetworkDeniedCopy() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let localNetwork = LocalNetworkAuthorization(defaults: UserDefaults(suiteName: "app.hashfleet.mac.lna.denied.\(UUID().uuidString)")!)
        localNetwork.markDenied()
        evaluate(AddMinerView(store: store, localNetwork: localNetwork))
    }
}
