import SwiftUI

/// The icon and title convey the same state, without requiring the status color.
struct FleetMinerStatusBadge: View {
    let state: FleetMinerPresentationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Native Mac re-renders a forever-repeating phase animation at the display refresh rate for
    /// every card, which with four miners measured as the largest remaining idle CPU cost on
    /// Overview. The Mac keeps the Live badge steady and pulses only on a real status change,
    /// matching the miner page. iOS keeps its breathing Live badge.
    static func breathesWhileLive(isNativeMac: Bool) -> Bool { !isNativeMac }

    private static var breathesWhileLive: Bool {
        #if os(macOS)
        breathesWhileLive(isNativeMac: true)
        #else
        breathesWhileLive(isNativeMac: false)
        #endif
    }

    var body: some View {
        let badge = HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(state.color)
                .accessibilityHidden(true)
            Text(state.title)
                .foregroundStyle(FleetTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fleetFont(.footnote, weight: .semibold)
        .accessibilityElement(children: .combine)
        Group {
            if state == .live && !reduceMotion && Self.breathesWhileLive {
                badge.phaseAnimator([1.0, 1.1, 1.0]) { content, scale in
                    content.scaleEffect(scale, anchor: .trailing)
                        .shadow(color: state.color.opacity(max(0, (scale - 1) * 2.2)), radius: 7)
                } animation: { _ in .easeInOut(duration: 1.3) }
            } else {
                badge
            }
        }
        .fleetStatusTransitionPulse(isOnline: state.isOperational, color: state.color, reduceMotion: reduceMotion)
        .contentTransition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state)
    }

    private var symbol: String {
        switch state {
        case .sample: "sparkles"
        case .loading, .connecting, .reconnecting: "clock"
        case .live: "bolt.circle"
        case .online: "checkmark.circle"
        case .stale, .unreachable: "exclamationmark.triangle"
        }
    }
}
