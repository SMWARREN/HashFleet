import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Tests evaluating the pools configuration sections in MinerSettingsView across
/// fallback pool state, password modes (.replace, .clear), DigiByte SHA-256 warning, and protocol.
@Suite("Miner Settings Pools Section Evaluation", .serialized)
@MainActor
struct MinerSettingsPoolsSectionEvaluationTests {
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

    private func makeStore(fallback: Bool) -> (FleetStore, MinerDevice, UserDefaults, String) {
        let suite = "app.hashfleet.mac.settingspools.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let fleet = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        let device = MinerDevice(name: "PoolRig", address: "192.168.1.130")
        fleet.devices = [device]

        let raw: [String: JSONValue] = [
            "hostname": .string("PoolRig"),
            "isUsingFallbackStratum": .bool(fallback),
            "primaryPoolIndex": .integer(0),
            "secondaryPoolIndex": .integer(1),
            "stratumURL": .string("us1.solopool.org"),
            "stratumPort": .integer(8004),
            "stratumUser": .string("dgb1qwallet.worker1"),
            "stratumProtocol": .string("SV1"),
            "pools": .array([
                .object([
                    "id": .integer(0),
                    "url": .string("us1.solopool.org"),
                    "port": .integer(8004),
                    "user": .string("dgb1qwallet.worker1")
                ])
            ])
        ]

        fleet.snapshots[device.id] = MinerSnapshot(
            info: MinerInfo(raw: raw),
            previousInfo: nil,
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

    @Test func evaluatePoolsPageWithFallbackAndDGBPort() {
        let (fleet, device, defaults, suite) = makeStore(fallback: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = MinerSettingsView(device: device, store: fleet, initialCategory: .pools)
        settings.load()
        settings.poolPort = "8004"
        settings.poolPasswordMode = .replace
        settings.poolPassword = "secretpassword"
        evaluate(settings.poolsPage)

        // Clear password mode
        settings.poolPasswordMode = .clear
        evaluate(settings.poolsPage)

        // SV2 protocol
        settings.poolProtocol = "SV2"
        evaluate(settings.pools)
    }
}
