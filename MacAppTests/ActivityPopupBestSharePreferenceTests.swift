import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Renders FleetActivityPopup with best-share alerts on and off, using an isolated defaults suite and the
/// demo store. The toggle and notice are plain preference state. Nothing is delivered and no alert is sent.
@Suite("Activity popup best-share preference states", .serialized)
@MainActor
struct ActivityPopupBestSharePreferenceTests {
    private func evaluate<V: View>(_ view: V, width: CGFloat = 420, height: CGFloat = 1400) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private func makeDemoStore(bestShareEnabled: Bool) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.activitypop.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        store.loadDemo()
        store.preferences.bestShareNotificationsEnabled = bestShareEnabled
        return (store, defaults, suite)
    }

    @Test func evaluateActivityPopupWithBestShareAlertsOn() {
        let (store, defaults, suite) = makeDemoStore(bestShareEnabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.preferences.bestShareNotificationsEnabled)
        evaluate(FleetActivityPopup(store: store))
    }

    @Test func evaluateActivityPopupWithBestShareAlertsOff() {
        let (store, defaults, suite) = makeDemoStore(bestShareEnabled: false)
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!store.preferences.bestShareNotificationsEnabled)
        // The off state disables the session toggle and shows the enable-in-Preferences notice.
        evaluate(FleetActivityPopup(store: store))
    }
}
