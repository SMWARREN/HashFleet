import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Tests evaluating the "Since previous sample" comparison card and branches in MinerDetailView+Metrics.
/// Completely offline: uses in-memory MinerSnapshot with previousInfo set to drive comparisons
/// for chip temp, VR temp, and fan speed across decreased, increased, and unchanged directions.
@Suite("Seeded Previous Sample Comparison Evaluation", .serialized)
@MainActor
struct SeededPreviousSampleComparisonTests {
    private func evaluate<V: View>(_ view: V, width: CGFloat = 800, height: CGFloat = 1200) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private func makeStore(
        currentFields: [String: JSONValue],
        previousFields: [String: JSONValue]
    ) throws -> (FleetStore, MinerDevice, UserDefaults, String) {
        let suite = "app.hashfleet.mac.previoussample.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let fleet = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        let device = MinerDevice(name: "Rig Alpha", address: "192.168.1.120", kind: .espMiner)
        fleet.devices = [device]

        let currentInfo = MinerInfo(raw: currentFields)
        let previousInfo = MinerInfo(raw: previousFields)

        fleet.snapshots[device.id] = MinerSnapshot(
            info: currentInfo,
            previousInfo: previousInfo,
            error: nil,
            updatedAt: Date(),
            completeSnapshotAt: Date(),
            powerObservedAt: Date(),
            history: [],
            isCached: false,
            isReconnecting: false
        )
        return (fleet, device, defaults, suite)
    }

    @Test func evaluateCoolingComparisonCardAndBranches() throws {
        // Temperature increased (warning color), VR temp decreased (positive color), Fan unchanged (secondary color)
        let currentFields: [String: JSONValue] = [
            "hostname": .string("Rig Alpha"),
            "hashRate": .number(1200),
            "power": .number(20),
            "temp": .number(62),       // was 55 -> increased (+7)
            "vrTemp": .number(50),     // was 58 -> decreased (-8)
            "fanspeed": .number(70),   // was 70 -> unchanged
            "voltage": .number(5000),
            "frequency": .number(550),
            "coreVoltage": .number(1150)
        ]

        let previousFields: [String: JSONValue] = [
            "hostname": .string("Rig Alpha"),
            "hashRate": .number(1190),
            "power": .number(19.5),
            "temp": .number(55),
            "vrTemp": .number(58),
            "fanspeed": .number(70)
        ]

        let (fleet, device, defaults, suite) = try makeStore(
            currentFields: currentFields,
            previousFields: previousFields
        )
        defer { defaults.removePersistentDomain(forName: suite) }

        let insights = MiningInsightsStore()
        let detail = MinerDetailView(device: device, store: fleet, insights: insights)

        // Evaluate the direct cooling comparison view
        evaluate(detail.coolingComparison(MinerInfo(raw: currentFields)))
        evaluate(detail.coolingCard(MinerInfo(raw: currentFields)))
        evaluate(detail.metrics(MinerInfo(raw: currentFields), diagnostics: MinerDiagnosticsModel(info: MinerInfo(raw: currentFields))))

        // Also evaluate decreased temp (positive color) and increased fan
        let currentFields2: [String: JSONValue] = [
            "hostname": .string("Rig Alpha"),
            "temp": .number(48),       // was 55 -> decreased (-7)
            "vrTemp": .number(60),     // was 58 -> increased (+2)
            "fanspeed": .number(85)    // was 70 -> increased (+15)
        ]
        let (fleet2, device2, defaults2, suite2) = try makeStore(
            currentFields: currentFields2,
            previousFields: previousFields
        )
        defer { defaults2.removePersistentDomain(forName: suite2) }

        let detail2 = MinerDetailView(device: device2, store: fleet2, insights: insights)
        evaluate(detail2.coolingComparison(MinerInfo(raw: currentFields2)))
        evaluate(detail2.coolingCard(MinerInfo(raw: currentFields2)))
    }
}
