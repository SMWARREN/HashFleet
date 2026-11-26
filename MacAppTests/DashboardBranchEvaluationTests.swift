import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Hosts dashboard states the existing evaluation suite does not build: a mixed SHA-256 and
/// XMRig fleet, reported miner alerts, and both dashboard widths. Off-screen only. No network.
@Suite("Dashboard branch evaluation", .serialized)
@MainActor
struct DashboardBranchEvaluationTests {
    private func evaluate<V: View>(_ view: V, width: CGFloat, height: CGFloat = 1400) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private func store() -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.dashbranch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let fleet = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        return (fleet, defaults, suite)
    }

    private func snap(_ name: String, error: String? = nil, fields: [String: JSONValue]) -> MinerSnapshot {
        MinerSnapshot(
            info: MinerInfo(raw: fields), previousInfo: nil, error: error, updatedAt: Date(),
            completeSnapshotAt: Date(), powerObservedAt: Date(), history: [],
            isCached: false, isReconnecting: false
        )
    }

    @Test func evaluateMixedFleetWithAlertsAtBothWidths() {
        let (fleet, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        let asic = MinerDevice(name: "Gamma", address: "192.168.1.20", kind: .espMiner)
        let cpu = MinerDevice(name: "Mac CPU", address: "127.0.0.1", kind: .xmrig)
        let quiet = MinerDevice(name: "Quiet", address: "192.168.1.21", kind: .espMiner)
        fleet.devices = [asic, cpu, quiet]
        fleet.snapshots[asic.id] = snap("Gamma", fields: [
            "hostname": .string("Gamma"), "hashRate": .number(1000), "power": .number(18),
            "miningPaused": .bool(true), "overheat_mode": .bool(true),
            "power_fault": .string("sag"), "isUsingFallbackStratum": .bool(true),
            "fallbackStratumURL": .string("backup.pool")
        ])
        fleet.snapshots[cpu.id] = snap("Mac CPU", fields: [
            "hostname": .string("Mac CPU"), "hashRate": .number(4.2), "power": .number(28)
        ])
        fleet.snapshots[quiet.id] = snap("Quiet", error: "timed out", fields: ["hostname": .string("Quiet")])
        for mode in FleetPreferences.DashboardMode.allCases {
            fleet.preferences.dashboardMode = mode
            for width in [420.0, 900.0, 1280.0] {
                evaluate(
                    DashboardView(store: fleet, startupReady: true, onToggleSidebar: {}, onSelectSidebarDestination: { _ in }),
                    width: width
                )
            }
        }
    }

    @Test func evaluateEmptyAndStartupDashboard() {
        let (fleet, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        evaluate(DashboardView(store: fleet, startupReady: false), width: 900)
        evaluate(DashboardView(store: fleet, startupReady: true), width: 420, height: 800)
        fleet.loadDemo()
        evaluate(DashboardView(store: fleet, startupReady: true), width: 1280)
    }
}
