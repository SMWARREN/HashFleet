import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

@Suite("Direct Save Evaluation", .serialized)
@MainActor
struct DirectSaveEvaluationTests {
    private func makeStore(demo: Bool = true) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.directsave.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        if demo { store.loadDemo() }
        return (store, defaults, suite)
    }

    private func evaluate<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 1200)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    @Test func directSaveGuardBranchesAndDisplayButtons() throws {
        let (demoStore, demoDefaults, demoSuite) = makeStore(demo: true)
        defer { demoDefaults.removePersistentDomain(forName: demoSuite) }
        guard let demoDevice = demoStore.devices.first else { return }
        let insights = MiningInsightsStore()
        let identity = MinerInlineActionState.Identity(mac: "aa:bb", firmware: "v1")
        let demo = MinerSettingsView(device: demoDevice, store: demoStore, insights: insights)
        demo.saveDirectly(.object(["hostname": .string("Desk")]))
        demo.saveDirectly(.object(["rotation": .integer(90)]), displaySetting: .rotation)
        demo.saveDirectly(.object(["coreVoltage": .integer(1100)]))
        demo.saveDirectly(.object([:]))
        demo.restartAfterDisplaySave(identity)
        for setting in [MinerDisplaySetting.rotation, .colors, .timeout] {
            evaluate(demo.displaySaveButton("Save", setting: setting) {
                .object([setting.rawValue: .integer(1)])
            })
        }

        let (liveStore, liveDefaults, liveSuite) = makeStore(demo: false)
        defer { liveDefaults.removePersistentDomain(forName: liveSuite) }
        try liveStore.add(name: "Direct Rig", address: "192.168.1.77")
        guard let liveDevice = liveStore.devices.first else { return }
        let live = MinerSettingsView(device: liveDevice, store: liveStore, insights: insights)
        live.saveDirectly(.object(["hostname": .string("Desk")]))
        live.saveDirectly(.object(["invertscreen": .bool(true)]), displaySetting: .colors)
        live.restartAfterDisplaySave(identity)
        for setting in [MinerDisplaySetting.rotation, .colors, .timeout] {
            evaluate(live.displaySaveButton("Save", setting: setting) {
                throw MinerToolError.message("bad draft")
            })
        }

        let info = MinerInfo(raw: ["invertscreen": .bool(true), "rotation": .integer(1)])
        #expect(MinerDisplaySetting.colors.matches(.object(["invertscreen": .bool(true)]), in: info))
        #expect(!MinerDisplaySetting.colors.matches(.object(["invertscreen": .bool(false)]), in: info))
        #expect(!MinerDisplaySetting.timeout.matches(.object(["displayTimeout": .string("x")]), in: info))
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .restart, payload: .object(["hostname": .string("a")])))
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: .string("x")))
    }
}
