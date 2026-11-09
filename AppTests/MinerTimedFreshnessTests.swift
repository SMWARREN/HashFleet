import Foundation
import Testing
import HashFleetCore
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif

struct MinerTimedFreshnessTests {
    @Test func unchangedSnapshotAgesAndLosesWriteEligibilityWithoutAnotherPoll() {
        let observed = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = MinerSnapshot(info: MinerInfo(raw: ["hostname": .string("fixture")]), updatedAt: observed)
        #expect(MinerSnapshotFreshness(updatedAt: observed, now: observed)?.summary == "Updated just now")
        #expect(MinerWriteAvailability.allows(snapshot, now: observed))
        let later = observed.addingTimeInterval(125)
        #expect(MinerSnapshotFreshness(updatedAt: observed, now: later)?.isStale == true)
        #expect(MinerSnapshotFreshness(updatedAt: observed, now: later)?.accessibilityLabel.contains("stale") == true)
        #expect(MinerWriteAvailability.allows(snapshot, now: observed.addingTimeInterval(180)))
        #expect(!MinerWriteAvailability.allows(snapshot, now: observed.addingTimeInterval(185)))
        #expect(MinerSnapshotFreshness.refreshInterval == 5)
    }

    @Test func completeUnchangedObservationRenewsWritesButNotTheDisplayedValueAge() {
        let observed = Date(timeIntervalSince1970: 1_000_000)
        let now = observed.addingTimeInterval(300)
        var snapshot = MinerSnapshot(info: MinerInfo(raw: ["hostname": .string("fixture")]), updatedAt: observed)
        snapshot.completeSnapshotAt = now
        #expect(MinerWriteAvailability.allows(snapshot, now: now))
        #expect(MinerSnapshotFreshness(updatedAt: snapshot.updatedAt, now: now)?.summary == "Updated 5 min ago")
        #expect(!MinerWriteAvailability.allows(snapshot, now: now.addingTimeInterval(185)))
    }
}
