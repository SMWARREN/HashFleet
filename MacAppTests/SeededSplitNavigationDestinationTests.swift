import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Pushes offline navigation routes into FleetSplitView's NavigationStack so the destination closures run:
/// the support page, a miner detail route, and a non-tuning miner settings route. The path is a test-owned
/// binding. Each render resolves destinations and sends nothing. The tuning branch and the tour route are
/// excluded because they carry write or state-changing side effects.
@Suite("Seeded split navigation destinations", .serialized)
@MainActor
struct SeededSplitNavigationDestinationTests {
    private func evaluate<V: View>(_ view: V, width: CGFloat = 1200, height: CGFloat = 900) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private func split(path: NavigationPath, store: FleetStore) -> some View {
        FleetSplitView(
            store: store,
            insights: MiningInsightsStore(),
            coordinator: nil,
            startupReady: true,
            fleetPath: .constant(path),
            sidebarSelection: .constant(.overview)
        )
    }

    @Test func evaluateSplitDestinationsForSupportMinerAndSettings() {
        let suite = "app.hashfleet.mac.splitdest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = MinerFixtures.device(name: "Split Rig")
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        store.devices = [device]
        store.snapshots[device.id] = MinerFixtures.snapshot(MinerFixtures.healthyFields())

        var support = NavigationPath()
        support.append(FleetSupportRoute.page)
        evaluate(split(path: support, store: store))

        var detail = NavigationPath()
        detail.append(FleetMinerRoute(deviceID: device.id))
        evaluate(split(path: detail, store: store))

        var settings = NavigationPath()
        settings.append(FleetMinerSettingsRoute(deviceID: device.id, category: .general))
        evaluate(split(path: settings, store: store))
    }
}
