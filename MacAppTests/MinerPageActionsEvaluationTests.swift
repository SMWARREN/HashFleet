import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Presses the controls on the firmware pages so their action handlers, confirmation dialogs and
/// result branches execute. Every handler bails before a request because the snapshot has no
/// writable identity, so nothing is sent to a miner.
@Suite("Miner page actions evaluation", .serialized)
@MainActor
struct MinerPageActionsEvaluationTests {
    private func store(family: String, fields: [String: JSONValue]) -> (FleetStore, MinerDevice, UserDefaults, String) {
        let suite = "app.hashfleet.mac.pageactions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let fleet = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        fleet.preferences.dashboardMode = .full
        let device = MinerDevice(name: family, address: "192.168.1.77", firmwareFamily: family)
        fleet.devices = [device]
        fleet.snapshots[device.id] = MinerSnapshot(
            info: MinerInfo(raw: fields), previousInfo: nil, error: nil, updatedAt: Date(),
            completeSnapshotAt: Date(), powerObservedAt: Date(), history: [],
            isCached: false, isReconnecting: false
        )
        return (fleet, device, defaults, suite)
    }

    /// Hosts a view, lays it out, and invokes every button and toggle so their closures run.
    private func exercise<V: View>(_ view: V, width: CGFloat = 900, height: CGFloat = 1800) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        pressControls(in: host)
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private func pressControls(in view: NSView) {
        var visited = Set<ObjectIdentifier>()
        func walk(_ element: NSAccessibilityElement) {
            let id = ObjectIdentifier(element)
            guard visited.insert(id).inserted else { return }
            if element.accessibilityRole() == .button || element.accessibilityRole() == .checkBox {
                element.accessibilityPerformAction(.press)
            }
            for child in element.accessibilityChildren() ?? [] {
                if let element = child as? NSAccessibilityElement { walk(element) }
            }
        }
        if let root = view as? NSAccessibilityElement { walk(root) }
        for child in view.accessibilityChildren() ?? [] {
            if let element = child as? NSAccessibilityElement { walk(element) }
        }
    }

    @Test func exerciseHarloAndFirmwareActions() {
        let harloFields: [String: JSONValue] = [
            "hostname": .string("Harlo"), "firmwareFamily": .string("harloos"),
            "fault_notice_pending": .bool(true), "fault_notice_title": .string("Thermal"),
            "fault_notice_reason": .string("ASIC"), "fault_notice_id": .string("n1"),
            "asic_fan_c": .integer(60), "asic_shutdown_c": .integer(80),
            "vr_fan_c": .integer(70), "vr_shutdown_c": .integer(90), "rating_w": .integer(120)
        ]
        let (harlo, device, defaults, suite) = store(family: "harloos", fields: harloFields)
        defer { defaults.removePersistentDomain(forName: suite) }
        exercise(MinerHarloToolsPage(device: device, store: harlo))
        exercise(MinerFirmwareExtrasPage(device: device, store: harlo))

        for family in ["bitaxe", "nerdqaxe", "warpaxe", "axeforge"] {
            let (fleet, miner, minerDefaults, minerSuite) = store(family: family, fields: [
                "hostname": .string(family), "firmwareFamily": .string(family),
                "overclockEnabled": .integer(0), "useNTP": .integer(1), "overheat_temp": .integer(70),
                "flipscreen": .bool(false), "autoscreenoff": .bool(true)
            ])
            defer { minerDefaults.removePersistentDomain(forName: minerSuite) }
            fleet.preferences.dashboardMode = .essentials
            exercise(MinerFirmwareExtrasPage(device: miner, store: fleet))
        }
    }

    @Test func exerciseAvalonAndEndpointActions() {
        let (fleet, device, defaults, suite) = store(family: "canaan", fields: [
            "hostname": .string("Avalon"), "firmwareFamily": .string("canaan"),
            "deviceModel": .string("Avalon A10"), "workmode": .integer(1), "power_fault": .string("sag")
        ])
        defer { defaults.removePersistentDomain(forName: suite) }
        exercise(MinerAvalonControlsPage(device: device, store: fleet))
        fleet.preferences.dashboardMode = .essentials
        exercise(MinerAvalonControlsPage(device: device, store: fleet))
        for endpoint in [MinerEndpoint.settings, .restart, .updatePool(1), .logs] {
            exercise(MinerEndpointView(device: device, store: fleet, endpoint: endpoint, onWriteCompleted: {}))
        }
    }

    @Test func exerciseTickerPauseAndStaticLayout() {
        let suite = "app.hashfleet.mac.tickeractions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fleet = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        fleet.devices = (0..<6).map { MinerDevice(name: "Rig \($0)", address: "10.0.0.\($0)") }
        for device in fleet.devices {
            fleet.snapshots[device.id] = MinerSnapshot(
                info: MinerInfo(raw: ["hostname": .string(device.name), "hashRate": .number(500), "power": .number(15)]),
                previousInfo: nil, error: nil, updatedAt: Date(), completeSnapshotAt: Date(),
                powerObservedAt: Date(), history: [], isCached: false, isReconnecting: false
            )
        }
        exercise(FleetStatusTicker(fleet: fleet), width: 1100, height: 90)
        exercise(FleetStatusTicker(fleet: fleet).dynamicTypeSize(.accessibility3), width: 700, height: 400)
    }
}
