import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Renders MinerCompatibilityView for every capability summary branch by seeding fixed reports through
/// the DEBUG-only MinerCapabilitiesStore.seedReportForTesting seam. No probe or network request is made.
@Suite("Seeded compatibility summary evaluation", .serialized)
@MainActor
struct SeededCompatibilitySummaryTests {
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

    private func makeStore(_ device: MinerDevice) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.compat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        store.devices = [device]
        store.snapshots[device.id] = MinerFixtures.snapshot(MinerFixtures.healthyFields())
        return (store, defaults, suite)
    }

    @Test func evaluateEveryCompatibilitySummaryBranch() {
        let device = MinerFixtures.device(name: "Compat Rig")
        let info = MinerInfo(raw: MinerFixtures.healthyFields())
        let asic = JSONValue.object(["ASICModel": .string("BM1370")])
        let reports: [MinerCapabilityReport] = [
            // Unchecked: no report yet, so the view renders its not-checked summary.
            MinerCapabilityReport(),
            // Read failed: the check is incomplete, not unsupported.
            MinerCapabilityReport(infoStatus: .failed(message: "timeout"), asicStatus: .notChecked),
            // Both reads supported.
            MinerCapabilityReport(info: info, asic: asic, infoStatus: .supported, asicStatus: .supported),
            // Only system info supported.
            MinerCapabilityReport(info: info, infoStatus: .supported, asicStatus: .unsupported(statusCode: 404)),
            // Only the ASIC read supported.
            MinerCapabilityReport(asic: asic, infoStatus: .unsupported(statusCode: 404), asicStatus: .supported),
            // Neither read implemented by the firmware.
            MinerCapabilityReport(
                infoStatus: .unsupported(statusCode: 501), asicStatus: .unsupported(statusCode: 405)
            ),
        ]
        for report in reports {
            let (store, defaults, suite) = makeStore(device)
            defer { defaults.removePersistentDomain(forName: suite) }
            store.capabilities.seedReportForTesting(report, id: device.id)
            evaluate(MinerCompatibilityView(device: device, store: store, insights: nil))
        }
    }
}
