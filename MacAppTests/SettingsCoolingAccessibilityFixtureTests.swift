import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Settings cooling page rendered at accessibility Dynamic Type sizes, which switches the
/// reading layout to its stacked form, and the cooling proposal button. The review button
/// is rendered but never pressed: its action opens a review sheet, and the write path (saveLiveCooling)
/// is intentionally not exercised offline. No request, no socket.
@Suite("Settings cooling accessibility fixture evaluation", .serialized)
@MainActor
struct SettingsCoolingAccessibilityFixtureTests {
    private func makeStore() -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.settingscool.\(UUID().uuidString)"
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

    @Test func evaluateCoolingPageAtAccessibilityTypeSize() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device(name: "Cool Rig")
        store.devices = [miner]
        store.snapshots[miner.id] = MinerFixtures.snapshot(MinerFixtures.healthyFields())
        // Accessibility sizes take the stacked branch in coolingReading.
        evaluate(
            MinerSettingsView(device: miner, store: store, initialCategory: .cooling)
                .environment(\.dynamicTypeSize, .accessibility3),
            width: 420, height: 1600
        )
    }

    @Test func evaluateCoolingPageAtStandardTypeSize() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device(name: "Cool Rig")
        store.devices = [miner]
        store.snapshots[miner.id] = MinerFixtures.snapshot(MinerFixtures.faultedFields())
        evaluate(MinerSettingsView(device: miner, store: store, initialCategory: .cooling))
    }
}
