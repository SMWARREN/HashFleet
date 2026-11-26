import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Two offline seeded renders with no write and no request:
/// 1. FleetHistoryCard with one SHA-256 and one XMRig device, so the algorithm picker renders.
/// 2. The reviewed cooling page for an XMRig device at accessibility3. Only xmrig takes the reviewed branch,
///    and the environment is set on MinerSettingsView itself, the view that reads dynamicTypeSize.
@Suite("Seeded history algorithm controls and reviewed cooling accessibility", .serialized)
@MainActor
struct SeededHistoryAlgorithmAndReviewedCoolingTests {
    private func evaluate<V: View>(_ view: V, width: CGFloat = 900, height: CGFloat = 1400) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private func makeStore(devices: [MinerDevice], fields: [String: JSONValue])
        -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.histalgo.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        store.devices = devices
        for device in devices { store.snapshots[device.id] = MinerFixtures.snapshot(fields) }
        return (store, defaults, suite)
    }

    @Test func evaluateHistoryAlgorithmControlsWithBothKinds() {
        let esp = MinerFixtures.device(name: "Gamma")
        let xmrig = MinerDevice(name: "Xmrig Host", address: "192.168.1.70", kind: .xmrig, firmwareFamily: "xmrig")
        let (store, defaults, suite) = makeStore(devices: [esp, xmrig], fields: MinerFixtures.healthyFields())
        defer { defaults.removePersistentDomain(forName: suite) }
        // Both kinds are present, so FleetHistoryKind.available returns two entries and the picker renders.
        let card = FleetHistoryCard(
            devices: store.visibleDevices,
            snapshots: store.snapshots,
            isDemo: true,
            initialRecentRange: .oneMinute,
            isCompactDashboard: false,
            dashboardMode: .full,
            numberFirst: false
        )
        evaluate(card)
        evaluate(card.essentialsHistoryControls)
    }

    @Test func evaluateReviewedCoolingPageForXmrigAtAccessibilitySize() {
        let xmrig = MinerDevice(name: "Xmrig Cooling", address: "192.168.1.71", kind: .xmrig, firmwareFamily: "xmrig")
        let (store, defaults, suite) = makeStore(devices: [xmrig], fields: MinerFixtures.healthyFields())
        defer { defaults.removePersistentDomain(forName: suite) }
        // Standard size renders the side-by-side readings, accessibility3 renders them stacked.
        evaluate(MinerSettingsView(device: xmrig, store: store, initialCategory: .cooling), width: 900, height: 1400)
        evaluate(
            MinerSettingsView(device: xmrig, store: store, initialCategory: .cooling)
                .environment(\.dynamicTypeSize, .accessibility3),
            width: 420, height: 1600
        )
    }
}
