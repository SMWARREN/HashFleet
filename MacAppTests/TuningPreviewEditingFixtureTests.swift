import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Tuning preview editing states seeded through the existing DEBUG draft argument.
/// Edited drafts are built as plain values from MinerFixtures, so no request, socket, or write occurs.
/// Covers invalid-value entry, a changed draft with reset, and a pending review with its payload.
@Suite("Tuning preview editing fixture evaluation", .serialized)
@MainActor
struct TuningPreviewEditingFixtureTests {
    private func makeStore() -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.tuningedit.\(UUID().uuidString)"
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

    @Test func evaluateTuningPreviewChangedDraftWithInvalidValue() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device()
        let info = MinerInfo(raw: MinerFixtures.healthyFields())
        store.devices = [miner]
        store.snapshots[miner.id] = MinerFixtures.snapshot(MinerFixtures.healthyFields())

        // A valid change, then an invalid entry, so both the reset action and the
        // "Enter a valid" caption render.
        var changed = MinerTuningPreviewDraft(info: info)
        changed.edit(.frequency, "550")
        var invalid = changed
        invalid.edit(.coreVoltage, "abc")

        evaluate(MinerTuningPreview(
            mode: .full, device: miner, store: store, info: info, isDemo: false, canEdit: true,
            insights: nil, draft: changed
        ))
        evaluate(MinerTuningPreview(
            mode: .essentials, device: miner, store: store, info: info, isDemo: false, canEdit: true,
            insights: nil, draft: invalid, error: "Voltage must be a whole number."
        ), width: 420, height: 1400)
    }

    @Test func evaluateTuningPreviewPendingReviewPayload() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = MinerFixtures.device()
        let info = MinerInfo(raw: MinerFixtures.healthyFields())
        store.devices = [miner]
        store.snapshots[miner.id] = MinerFixtures.snapshot(MinerFixtures.healthyFields())

        var edited = MinerTuningPreviewDraft(info: info)
        edited.edit(.frequency, "500")
        edited.edit(.coreVoltage, "1040")
        let review = MinerTuningPreviewDraft.Review(
            changes: [
                MinerTuningPreviewDraft.Change(field: .frequency, old: 525, new: 500),
                MinerTuningPreviewDraft.Change(field: .coreVoltage, old: 1060, new: 1040)
            ],
            payload: .object(["frequency": .number(500), "coreVoltage": .number(1040)])
        )
        evaluate(MinerTuningPreview(
            mode: .full, device: miner, store: store, info: info, isDemo: false, canEdit: true,
            insights: nil, draft: edited, review: review
        ))
    }
}
