import Foundation
import Testing
@testable import HashFleet

struct FleetCelebrationQueueTests {
    private func popup(_ name: String, kind: FleetCelebration.Kind = .bestShareSession) -> FleetCelebration {
        FleetCelebration(kind: kind, deviceID: UUID(), minerName: name,
                         value: "2.00M", detail: "New best share this session")
    }

    @Test func aSecondMinerWaitsUntilTheCurrentIllustrationIsAcknowledged() {
        var queue = FleetCelebrationQueue()
        let first = popup("Workshop")
        let second = popup("Office")
        let allTime = popup("Garage", kind: .bestShareAllTime)
        queue.present(first)
        queue.present(second)
        queue.present(allTime)
        #expect(queue.current == first)
        #expect(queue.pending == [second, allTime])
        queue.dismiss()
        #expect(queue.current == second)
        queue.dismiss()
        #expect(queue.current == allTime)
        queue.dismiss()
        #expect(queue.current == nil && queue.pending.isEmpty)
        queue.dismiss()
        #expect(queue.current == nil)
    }

    @Test func repeatedCurrentOrQueuedEventsDoNotCreateDuplicatePopups() {
        var queue = FleetCelebrationQueue()
        let session = popup("Workshop")
        let block = popup("Office", kind: .blockFound)
        for _ in 0..<3 {
            queue.present(session)
            queue.present(block)
        }
        #expect(queue.current == session)
        #expect(queue.pending == [block])
    }

    @Test func statusWarningsAreNotConvertedIntoCelebrations() {
        let warning = FleetNotificationEvent.stateChange(MinerStateChangeEvent(
            deviceID: UUID(), minerName: "Workshop", kind: .offline,
            detail: "Fixture timeout", occurredAt: .now))
        #expect(FleetCelebration(warning) == nil)
    }

    @Test func sessionOptOutSkipsCurrentAndWaitingSessionsButKeepsOtherRecordsInOrder() {
        var queue = FleetCelebrationQueue()
        let session = popup("Workshop")
        let waitingSession = popup("Office")
        let allTime = popup("Garage", kind: .bestShareAllTime)
        let block = popup("Studio", kind: .blockFound)
        [session, waitingSession, allTime, popup("Attic"), block].forEach { queue.present($0) }

        queue.removeSessionBests()
        #expect(queue.current == allTime)
        #expect(queue.pending == [block])
        queue.dismiss()
        #expect(queue.current == block)
        queue.dismiss()
        #expect(queue.current == nil && queue.pending.isEmpty)
    }

    @Test func sessionOptOutDoesNotDismissACurrentAllTimeRecordOrBlock() {
        for kind in [FleetCelebration.Kind.bestShareAllTime, .blockFound] {
            var queue = FleetCelebrationQueue()
            let current = popup("Workshop", kind: kind)
            let block = popup("Office", kind: .blockFound)
            queue.present(current)
            queue.present(popup("Garage"))
            queue.present(block)
            queue.removeSessionBests()
            #expect(queue.current == current)
            #expect(queue.pending == [block])
        }
    }

    @Test func sessionOptOutCanEmptyASessionOnlyQueueAndIsIdempotent() {
        var queue = FleetCelebrationQueue()
        queue.present(popup("Workshop"))
        queue.present(popup("Office"))
        queue.removeSessionBests()
        #expect(queue.current == nil && queue.pending.isEmpty)
        queue.removeSessionBests()
        #expect(queue.current == nil && queue.pending.isEmpty)
    }
}
