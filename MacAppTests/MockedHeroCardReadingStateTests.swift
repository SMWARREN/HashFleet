import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Renders FleetHeroCard from mocked FleetMetricTotal values, covering the reading caption states
/// (no reporting miners, partial reporting, complete reporting) and the loading and compact layouts.
/// Every input is a plain value. No store, network, socket, or write is involved.
@Suite("Mocked hero card reading states", .serialized)
@MainActor
struct MockedHeroCardReadingStateTests {
    private func evaluate<V: View>(_ view: V, width: CGFloat = 900, height: CGFloat = 1000) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    @Test func evaluateHeroCardReadingCaptionStates() {
        // Online miners present, none reported a hashrate: the "no reading" caption renders.
        let noReport = FleetMetricTotal(value: 0, reporting: 0, online: 3)
        // Some reported but not all: the partial caption renders.
        let partial = FleetMetricTotal(value: 240, reporting: 2, online: 3)
        // Everyone reported: no caption.
        let complete = FleetMetricTotal(value: 540, reporting: 3, online: 3)
        let power = FleetMetricTotal(value: 1_120, reporting: 3, online: 3)

        for hashrate in [noReport, partial, complete] {
            evaluate(FleetHeroCard(
                hashrate: hashrate,
                power: power,
                onlineCount: hashrate.online,
                deviceCount: 3,
                isDemo: false,
                isRefreshing: false,
                isInitialLoading: false,
                realtimeMonitoring: true,
                liveConnectionCount: 2,
                liveFallbackCount: 1
            ))
        }
    }

    @Test func evaluateHeroCardLoadingCompactAndAccessibility() {
        let partial = FleetMetricTotal(value: 240, reporting: 2, online: 3)
        let power = FleetMetricTotal(value: 1_120, reporting: 3, online: 3)
        // Initial loading hides the caption. Compact and number-first switch the layout.
        evaluate(FleetHeroCard(
            hashrate: partial,
            power: power,
            onlineCount: 3,
            deviceCount: 3,
            isDemo: false,
            isRefreshing: true,
            isInitialLoading: true,
            realtimeMonitoring: false,
            liveConnectionCount: 0,
            liveFallbackCount: 3,
            sourceTitle: "SHA-256",
            compact: true,
            numberFirst: true
        ))
        evaluate(
            FleetHeroCard(
                hashrate: partial,
                power: power,
                onlineCount: 3,
                deviceCount: 3,
                isDemo: true,
                isRefreshing: false,
                isInitialLoading: false,
                realtimeMonitoring: true,
                liveConnectionCount: 1,
                liveFallbackCount: 0,
                sourceTitle: "XMRig",
                compact: false,
                numberFirst: false
            ).environment(\.dynamicTypeSize, .accessibility3),
            width: 420, height: 1400
        )
    }
}
