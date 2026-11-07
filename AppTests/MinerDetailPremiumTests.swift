import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Premium instrument-panel behaviors on the miner detail screen: honest snapshot freshness,
/// reported-average hashrate trend, and calm factual attention notes.
struct MinerDetailPremiumTests {

    // MARK: - Snapshot freshness

    @Test func freshnessSummaryRoundsDownAndNeverNegative() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Future timestamps (clock skew) clamp to zero instead of showing a negative age.
        let skew = MinerSnapshotFreshness(updatedAt: now.addingTimeInterval(30), now: now)
        #expect(skew?.ageSeconds == 0)
        #expect(skew?.summary == "Updated just now")

        let seconds = MinerSnapshotFreshness(updatedAt: now.addingTimeInterval(-42), now: now)
        #expect(seconds?.summary == "Updated 42 s ago")
        #expect(seconds?.isStale == false)

        let minutes = MinerSnapshotFreshness(updatedAt: now.addingTimeInterval(-5 * 60 - 10), now: now)
        #expect(minutes?.summary == "Updated 5 min ago")
        #expect(minutes?.isStale == true)

        let hours = MinerSnapshotFreshness(updatedAt: now.addingTimeInterval(-3 * 3_600), now: now)
        #expect(hours?.summary == "Updated 3 h ago")
    }

    @Test func freshnessNilWithoutSnapshotTimestamp() {
        #expect(MinerSnapshotFreshness(updatedAt: nil, now: Date()) == nil)
    }

    @Test func freshnessStalenessThresholdAndAccessibility() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let freshEdge = MinerSnapshotFreshness(
            updatedAt: now.addingTimeInterval(-MinerSnapshotFreshness.staleAfterSeconds), now: now)
        #expect(freshEdge?.isStale == false)
        #expect(freshEdge?.accessibilityLabel.contains("stale") == false)

        let stale = MinerSnapshotFreshness(
            updatedAt: now.addingTimeInterval(-MinerSnapshotFreshness.staleAfterSeconds - 1), now: now)
        #expect(stale?.isStale == true)
        #expect(stale?.accessibilityLabel.contains("Snapshot may be stale.") == true)
    }

    // MARK: - Hashrate trend

    @Test func trendRequiresBothReportedAverages() {
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: nil, baseline1h: 500) == nil)
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 500, baseline1h: nil) == nil)
        // A zero baseline has no defined relative direction; never invent one.
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 10, baseline1h: 0) == nil)
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: .nan, baseline1h: 500) == nil)
    }

    @Test func trendDetectsRisingSteadyFalling() {
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 550, baseline1h: 500) == .rising)
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 450, baseline1h: 500) == .falling)
        // Within the tolerance band the averages read as steady, not jittering.
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 505, baseline1h: 500) == .steady)
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 495, baseline1h: 500) == .steady)
    }

    @Test func trendComesFromReportedRawKeys() {
        let model = MinerDiagnosticsModel(raw: [
            "hashRate_1m": .number(525),
            "hashRate_1h": .number(500)
        ])
        #expect(model.hashrateTrend == .rising)
        let sparse = MinerDiagnosticsModel(raw: ["hashRate": .number(500)])
        #expect(sparse.hashrateTrend == nil)
    }

    // MARK: - Attention notes

    @Test func attentionNotesEmptyWhenKeyReadingsReported() {
        let model = MinerDiagnosticsModel(raw: [
            "hashRate": .number(500),
            "temp": .number(65),
            "fanrpm": .number(3_000),
            "sharesAccepted": .number(1_000),
            "sharesRejected": .number(0)
        ])
        #expect(model.attentionNotes.isEmpty)
    }

    @Test func attentionNotesReportMissingReadingsWithoutVerdicts() {
        let model = MinerDiagnosticsModel(raw: [:])
        let notes = model.attentionNotes
        #expect(notes.contains("Hashrate was not reported in the latest reading."))
        #expect(notes.contains("Chip temperature was not reported by the firmware."))
        // Missing fan tach silently absent: absence is not evidence of failure.
        #expect(notes.contains(where: { $0.contains("0 RPM") }) == false)
    }

    @Test func attentionNotesZeroFanAndRejectedShares() {
        let model = MinerDiagnosticsModel(raw: [
            "hashRate": .number(500),
            "temp": .number(65),
            "fanrpm": .number(0),
            "sharesAccepted": .number(99),
            "sharesRejected": .number(1)
        ])
        let notes = model.attentionNotes
        #expect(notes.contains("Primary fan reported 0 RPM (stopped, or tach unavailable)."))
        #expect(notes.contains(where: { $0.hasPrefix("The pool rejected 1 share(s)") }))
    }
}
