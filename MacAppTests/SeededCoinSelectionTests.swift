import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Renders FleetCoinSelectionView in its automatic and choose-coins states. FleetPreferences is built on a
/// test-only UserDefaults suite, and the view only edits that in-memory preference. It touches no miner,
/// makes no request, and opens no socket.
@Suite("Seeded coin selection evaluation", .serialized)
@MainActor
struct SeededCoinSelectionTests {
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

    private func makePreferences() -> (FleetPreferences, UserDefaults, String) {
        let suite = "app.hashfleet.mac.coins.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (FleetPreferences(defaults: defaults), defaults, suite)
    }

    @Test func evaluateCoinSelectionAutomaticState() {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        // dashboardCoins is nil by default, which is the automatic state with the toggle on.
        #expect(preferences.dashboardCoins == nil)
        evaluate(FleetCoinSelectionView(preferences: preferences, automaticCoins: [.btc, .bch]))
    }

    @Test func evaluateCoinSelectionChooseCoinsState() {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        preferences.dashboardCoins = [.btc, .bch]
        evaluate(FleetCoinSelectionView(preferences: preferences, automaticCoins: [.btc, .bch]))
        evaluate(
            FleetCoinSelectionView(preferences: preferences, automaticCoins: [.btc, .bch]),
            width: 420, height: 1400
        )
    }
}
