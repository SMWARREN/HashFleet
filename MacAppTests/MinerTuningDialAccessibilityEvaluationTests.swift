import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Tests evaluating MinerTuningDial with accessibility sizes (grid layout for step buttons)
/// and DialRing shape evaluation.
@Suite("Miner Tuning Dial Accessibility Evaluation", .serialized)
@MainActor
struct MinerTuningDialAccessibilityTests {
    private func evaluate<V: View>(_ view: V, width: CGFloat = 800, height: CGFloat = 1000) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private struct AccessibilityTuningHost: View {
        @State private var frequency = 525.0
        @State private var voltage = 1060.0

        var body: some View {
            let frequencyDial = MinerTuningDial(
                title: "Frequency",
                unit: "MHz",
                setpoint: $frequency,
                range: 325...725,
                liveValue: 521.4,
                configuredValue: 500,
                referenceMaximum: 575,
                referenceOptions: [400, 425, 450, 485, 500, 525, 550, 575],
                accessibilityPrefix: "tuningSession.master",
                valueIdentifier: "tuningSession.frequencyValue"
            )

            let voltageDial = MinerTuningDial(
                title: "Core voltage",
                unit: "mV",
                setpoint: $voltage,
                range: 910...1210,
                liveValue: 1052,
                configuredValue: 1060,
                referenceMaximum: 1150,
                referenceOptions: [1000, 1060, 1100, 1150],
                step: 5,
                coarseStep: 25,
                accessibilityPrefix: "tuningSession.voltage",
                valueIdentifier: "tuningSession.voltageValue"
            )

            VStack(spacing: 16) {
                MinerTuningDialPair(frequency: frequencyDial, voltage: voltageDial)
                frequencyDial
                voltageDial
            }
            .environment(\.dynamicTypeSize, .accessibility3)
        }
    }

    @Test func evaluateTuningDialAccessibilityGrid() {
        evaluate(AccessibilityTuningHost())
        evaluate(AccessibilityTuningHost(), width: 420, height: 1200)
    }
}
