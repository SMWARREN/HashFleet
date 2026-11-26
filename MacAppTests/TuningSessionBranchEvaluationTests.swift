import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Offline evaluation of tuning session branches: review presentation, inline advanced disclosure,
/// and busy/expanded bindings. Uses mock fleet fixtures only. No request is sent and no socket is opened.
@Suite("Tuning session branch evaluation", .serialized)
@MainActor
struct TuningSessionBranchEvaluationTests {
    private func makeStore() -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.tuningbranch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        return (store, defaults, suite)
    }

    private func evaluate<V: View>(_ view: V, width: CGFloat = 900, height: CGFloat = 1600) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private func fields() -> [String: JSONValue] {
        [
            "hostname": .string("Rig"), "firmwareFamily": .string("bitaxe"),
            "ASICModel": .string("BM1370"), "deviceModel": .string("Gamma"),
            "version": .string("2.12.0"), "macAddr": .string("aa:bb:cc:dd:ee:ff"),
            "frequency": .number(525), "coreVoltage": .number(1060),
            "temp": .number(62), "vrTemp": .number(55), "power": .number(14),
            "fanspeed": .number(60), "manualFanSpeed": .number(60), "minFanSpeed": .number(20),
            "autofanspeed": .bool(false), "temptarget": .number(65),
            "hashRate": .number(900), "expectedHashrate": .number(950),
            "sharesAccepted": .integer(120), "sharesRejected": .integer(2),
            "uptimeSeconds": .integer(3600), "wifiRSSI": .integer(-55)
        ]
    }

    private func device(_ store: FleetStore) -> MinerDevice {
        let miner = MinerDevice(name: "Rig", address: "192.168.1.40", kind: .espMiner, firmwareFamily: "bitaxe")
        store.devices = [miner]
        store.snapshots[miner.id] = MinerSnapshot(
            info: MinerInfo(raw: fields()), previousInfo: nil, error: nil, updatedAt: Date(),
            completeSnapshotAt: Date(), powerObservedAt: Date(),
            history: [], isCached: false, isReconnecting: false
        )
        return miner
    }

    @Test func evaluateTuningSessionReviewPresentationBinding() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = device(store)
        // Drive the review sheet binding both ways so its open and dismissed closures run.
        evaluate(MinerTuningSessionView(device: miner, store: store, reviewPresentation: .constant(true)))
        evaluate(MinerTuningSessionView(device: miner, store: store, reviewPresentation: .constant(false)))
    }

    @Test func evaluateTuningSessionInlineAdvancedBindings() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = device(store)
        var jumped = false
        let inline = MinerTuningSessionView.InlineAdvanced(
            isExpanded: .constant(true),
            isBusy: .constant(false),
            jumpToReview: { jumped = true }
        )
        evaluate(MinerTuningSessionView(device: miner, store: store, inlineAdvanced: inline))
        let busy = MinerTuningSessionView.InlineAdvanced(
            isExpanded: .constant(false),
            isBusy: .constant(true),
            jumpToReview: {}
        )
        evaluate(MinerTuningSessionView(device: miner, store: store, inlineAdvanced: busy), width: 420, height: 1400)
        #expect(!jumped)
    }

    @Test func evaluateTuningSessionWithInsightsStore() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = device(store)
        let insights = MiningInsightsStore()
        evaluate(MinerTuningSessionView(device: miner, store: store, insights: insights))
        evaluate(MinerTuningSessionView(device: miner, store: store, insights: insights, reviewPresentation: .constant(true)))
    }
}
