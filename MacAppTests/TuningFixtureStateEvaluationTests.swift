import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Tuning preview and session states driven by MinerFixtures: faulted readings, sparse readings,
/// stale cached snapshots, and the review and applied flows. Offline only. No request is sent.
@Suite("Tuning fixture-state evaluation", .serialized)
@MainActor
struct TuningFixtureStateEvaluationTests {
    private func makeStore() -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.tuningfixture.\(UUID().uuidString)"
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

    private func seed(_ store: FleetStore, _ miner: MinerDevice, _ snapshot: MinerSnapshot) {
        store.devices = [miner]
        store.snapshots[miner.id] = snapshot
    }

    @Test func evaluateTuningSessionForFaultedMiner() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device()
        seed(store, miner, MinerFixtures.snapshot(MinerFixtures.faultedFields()))
        evaluate(MinerTuningSessionView(device: miner, store: store))
        evaluate(MinerTuningSessionView(device: miner, store: store), width: 420, height: 1400)
    }

    @Test func evaluateTuningSessionForSparseMiner() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device()
        seed(store, miner, MinerFixtures.snapshot(MinerFixtures.sparseFields()))
        evaluate(MinerTuningSessionView(device: miner, store: store))
    }

    @Test func evaluateTuningSessionForCachedAndErroredSnapshot() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device()
        seed(store, miner, MinerFixtures.snapshot(
            MinerFixtures.healthyFields(), error: "timed out", isCached: true
        ))
        evaluate(MinerTuningSessionView(device: miner, store: store))
    }

    @Test func evaluateTuningPreviewReviewAndAppliedStates() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device()
        let info = MinerInfo(raw: MinerFixtures.faultedFields())
        seed(store, miner, MinerFixtures.snapshot(MinerFixtures.faultedFields()))
        let review = MinerTuningPreviewDraft.Review(
            changes: [
                MinerTuningPreviewDraft.Change(field: .frequency, old: 525, new: 500),
                MinerTuningPreviewDraft.Change(field: .coreVoltage, old: 1060, new: 1040)
            ],
            payload: .object(["frequency": .number(500), "coreVoltage": .number(1040)])
        )
        evaluate(MinerTuningPreview(
            mode: .full, device: miner, store: store, info: info, isDemo: false, canEdit: true,
            insights: nil, applied: review, review: review, showsInlineAdvanced: true, showsFullAdvanced: true
        ))
        evaluate(MinerTuningPreview(
            mode: .essentials, device: miner, store: store, info: info, isDemo: true, canEdit: false,
            insights: nil, error: "Reading is stale. Refresh before applying."
        ), width: 420, height: 1400)
    }

    @Test func evaluateTuningPreviewSparseReadingsFallbacks() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device()
        let info = MinerInfo(raw: MinerFixtures.sparseFields())
        seed(store, miner, MinerFixtures.snapshot(MinerFixtures.sparseFields()))
        evaluate(MinerTuningPreview(
            mode: .full, device: miner, store: store, info: info, isDemo: false, canEdit: true, insights: nil
        ))
    }
}
