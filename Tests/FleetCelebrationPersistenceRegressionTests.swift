import Foundation
import SQLite3
#if canImport(AppKit)
import AppKit
import SwiftUI
#endif

// MARK: - Durable FIFO celebration queue regression checks
//
// Standalone executable. It compiles the REAL production FleetCelebrationQueue.swift and
// FleetCelebrationQueueStorage.swift plus the real FleetCelebration model (see
// Scripts/tests/... in the report for the exact extraction command). Nothing here fakes or
// reimplements the queue. Checks use unconditional `precondition` so they stay active under -O.
// All databases live in a unique temporary directory that this program deletes at the end.

@main
struct CelebrationPersistenceRegressionTests {
    static let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fleet-celebration-persistence-\(UUID().uuidString)", isDirectory: true)

    @MainActor
    static func main() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        print("Running durable celebration queue regression checks (active preconditions)...")
        let checks: [(String, () throws -> Void)] = [
            ("ephemeralInitKeepsLegacyBehavior", ephemeralInitKeepsLegacyBehavior),
            ("emptyQueueIsIdempotentAndSafe", emptyQueueIsIdempotentAndSafe),
            ("reopenRestoresExactRecordPausedAndResume", reopenRestoresExactRecordPausedAndResume),
            ("acknowledgedRecordsStayDeduplicatedAfterReopen", acknowledgedRecordsStayDeduplicatedAfterReopen),
            ("pausedQueueStillIngestsTwentyUniqueRecordsInOrder", pausedQueueStillIngestsTwentyUniqueRecordsInOrder),
            ("acknowledgeAndPauseIsOneTransaction", acknowledgeAndPauseIsOneTransaction),
            ("sessionOptOutClearsEveryPageAndKeepsOrder", sessionOptOutClearsEveryPageAndKeepsOrder),
            ("tenThousandRecordsStayFIFOWithBoundedCache", tenThousandRecordsStayFIFOWithBoundedCache),
            ("lockedDatabaseFailsClosedAndLeavesPriorStateIntact", lockedDatabaseFailsClosedAndLeavesPriorStateIntact),
            ("nonDatabaseFileIsRejectedWithoutModification", nonDatabaseFileIsRejectedWithoutModification),
            ("foreignAndNewerSchemaAreRejectedWithoutModification", foreignAndNewerSchemaAreRejectedWithoutModification),
            ("malformedVersionOneDatabasesAreRejectedUnchanged", malformedVersionOneDatabasesAreRejectedUnchanged),
            ("unreadableOldestRecordBlocksFIFOAndIsPreserved", unreadableOldestRecordBlocksFIFOAndIsPreserved),
            ("unavailableQueueFailsClosed", unavailableQueueFailsClosed),
            ("handlesAreClosedAndNoStatementsLeak", handlesAreClosedAndNoStatementsLeak),
            ("queriesUseIndexes", queriesUseIndexes)
        ]
        for (name, check) in checks {
            let start = Date()
            try check()
            print(String(format: "PASS: %@ (%.2fs)", name, Date().timeIntervalSince(start)))
        }
        #if canImport(AppKit)
        let hostingStart = Date()
        queueStateInvalidatesRealHostedSwiftUIState()
        print(String(format: "PASS: queueStateInvalidatesRealHostedSwiftUIState (%.2fs)", Date().timeIntervalSince(hostingStart)))
        #endif
        print("All durable celebration queue regression checks passed with active preconditions.")
    }

    // MARK: Helpers

    static func makeURL(_ name: String = "queue") -> URL {
        root.appendingPathComponent("\(name)-\(UUID().uuidString).sqlite3")
    }

    static func record(_ name: String, _ kind: FleetCelebration.Kind = .bestShareSession,
                       viewMinerAvailable: Bool = true) -> FleetCelebration {
        var celebration = FleetCelebration(kind: kind, deviceID: UUID(), minerName: name,
                                           value: "2.00M", detail: "Detail for \(name)")
        celebration.viewMinerAvailable = viewMinerAvailable
        return celebration
    }

    static func persistent(_ url: URL) throws -> FleetCelebrationQueue {
        try FleetCelebrationQueue(storageURL: url)
    }

    static func fileBytes(_ url: URL) -> Data { (try? Data(contentsOf: url)) ?? Data() }

    /// A second, independent SQLite connection used to cause genuine busy failures and to
    /// inspect the file the production queue wrote.
    final class Probe {
        var db: OpaquePointer?
        init(_ url: URL) {
            precondition(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        }
        deinit { sqlite3_close(db) }
        func exec(_ sql: String) -> Int32 { sqlite3_exec(db, sql, nil, nil, nil) }
        func scalar(_ sql: String) -> Int64 {
            var stmt: OpaquePointer?
            precondition(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
            defer { sqlite3_finalize(stmt) }
            precondition(sqlite3_step(stmt) == SQLITE_ROW)
            return sqlite3_column_int64(stmt, 0)
        }
        func plan(_ sql: String) -> String {
            var stmt: OpaquePointer?
            precondition(sqlite3_prepare_v2(db, "EXPLAIN QUERY PLAN " + sql, -1, &stmt, nil) == SQLITE_OK)
            defer { sqlite3_finalize(stmt) }
            var lines: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                lines.append(sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "")
            }
            return lines.joined(separator: " | ")
        }
    }

    // MARK: Checks

    static func ephemeralInitKeepsLegacyBehavior() throws {
        var queue = FleetCelebrationQueue()
        let first = record("Workshop"), second = record("Office"), allTime = record("Garage", .bestShareAllTime)
        precondition(queue.present(first) && queue.present(second) && queue.present(allTime))
        precondition(queue.current == first)
        precondition(queue.pending == [second, allTime])
        precondition(queue.pendingCount == 2 && queue.unacknowledgedCount == 3 && queue.bufferedCount == 3)
        // Repeating a current or pending ID is accepted but creates no duplicate.
        for _ in 0..<3 { precondition(queue.present(first) && queue.present(second)) }
        precondition(queue.unacknowledgedCount == 3)
        precondition(queue.dismiss() && queue.current == second)
        precondition(queue.dismiss() && queue.current == allTime)
        precondition(queue.dismiss() && queue.current == nil && queue.pending.isEmpty)
        precondition(queue.dismiss() && queue.current == nil)
        precondition(queue.storageError == nil)
        // A second ephemeral queue shares nothing with the first.
        let other = FleetCelebrationQueue()
        precondition(other.unacknowledgedCount == 0 && other.current == nil)
        // The ephemeral queue still remembers an acknowledgement within its own lifetime.
        precondition(queue.present(first) && queue.current == nil)
    }

    static func emptyQueueIsIdempotentAndSafe() throws {
        let url = makeURL()
        var queue = try persistent(url)
        for _ in 0..<3 {
            precondition(queue.dismiss() && queue.removeSessionBests() && queue.resume() && queue.acknowledgeAndPause() == true)
            precondition(queue.resume())
        }
        precondition(queue.current == nil && queue.pending.isEmpty)
        precondition(queue.unacknowledgedCount == 0 && queue.pendingCount == 0 && queue.bufferedCount == 0)
        precondition(queue.storageError == nil)
        // acknowledgeAndPause on an empty queue still records the pause, then resume clears it.
        var again = try persistent(makeURL())
        precondition(again.acknowledgeAndPause() && again.isPaused)
        precondition(again.resume() && !again.isPaused)
    }

    static func reopenRestoresExactRecordPausedAndResume() throws {
        let url = makeURL()
        let real = record("Workshop", .blockFound, viewMinerAvailable: false)
        let waiting = record("Office", .bestShareAllTime)
        do {
            var queue = try persistent(url)
            precondition(queue.present(real) && queue.present(waiting))
            precondition(queue.current == real)
            precondition(queue.pause())
            precondition(queue.isPaused && queue.current == nil)
            precondition(queue.unacknowledgedCount == 2)
            precondition(queue.pendingCount == 2, "A paused queue counts its head as waiting.")
        }
        do {
            var queue = try persistent(url)
            precondition(queue.isPaused, "Pause must survive relaunch.")
            precondition(queue.current == nil)
            precondition(queue.pendingCount == 2 && queue.unacknowledgedCount == 2)
            precondition(queue.pending == [real, waiting])
            precondition(queue.resume() && !queue.isPaused)
            let restored = queue.current
            precondition(restored == real, "The exact record must be restored, including its original ID.")
            precondition(restored?.id == real.id && restored?.deviceID == real.deviceID)
            precondition(restored?.viewMinerAvailable == false)
            precondition(restored?.kind == .blockFound && restored?.value == real.value && restored?.detail == real.detail)
            precondition(queue.pendingCount == 1 && queue.pending == [waiting])
        }
        do {
            // Resume was durable too.
            var queue = try persistent(url)
            precondition(!queue.isPaused && queue.current == real)
            precondition(queue.dismiss() && queue.current == waiting)
        }
        do {
            var queue = try persistent(url)
            precondition(queue.current == waiting, "A visible but unacknowledged record returns after relaunch.")
            precondition(queue.dismiss() && queue.current == nil)
        }
    }

    static func acknowledgedRecordsStayDeduplicatedAfterReopen() throws {
        let url = makeURL()
        let shown = record("Workshop")
        do {
            var queue = try persistent(url)
            precondition(queue.present(shown) && queue.dismiss() && queue.current == nil)
        }
        var queue = try persistent(url)
        precondition(queue.present(shown), "Repeat of an acknowledged ID is accepted as already handled.")
        precondition(queue.current == nil && queue.unacknowledgedCount == 0 && queue.bufferedCount == 0)
        // A dismiss through Delivery replay of a pending record is also deduplicated.
        let pendingOne = record("Office")
        precondition(queue.present(pendingOne) && queue.present(pendingOne) && queue.unacknowledgedCount == 1)
        let probe = Probe(url)
        precondition(probe.scalar("SELECT COUNT(*) FROM records") == 2, "Tombstones are retained, not purged.")
    }

    static func pausedQueueStillIngestsTwentyUniqueRecordsInOrder() throws {
        let url = makeURL()
        var queue = try persistent(url)
        let existing = record("Existing", .bestShareAllTime)
        precondition(queue.present(existing) && queue.pause())
        let incoming = (0..<20).map { record("New \($0)", $0 % 2 == 0 ? .bestShareAllTime : .blockFound) }
        for item in incoming { precondition(queue.present(item)) }
        precondition(queue.current == nil, "Paused ingestion must not show anything.")
        precondition(queue.unacknowledgedCount == 21 && queue.pendingCount == 21)
        precondition(queue.pending == [existing] + incoming)
        precondition(queue.bufferedCount <= 33)
        // Reopen while paused, then resume and drain in exact FIFO order.
        queue = try persistent(url)
        precondition(queue.isPaused && queue.unacknowledgedCount == 21)
        precondition(queue.resume())
        var seen: [UUID] = []
        while let current = queue.current {
            seen.append(current.id)
            precondition(queue.pendingCount == queue.unacknowledgedCount - 1)
            precondition(queue.dismiss())
        }
        precondition(seen == ([existing] + incoming).map(\.id))
        precondition(queue.unacknowledgedCount == 0)
    }

    static func acknowledgeAndPauseIsOneTransaction() throws {
        let url = makeURL()
        var queue = try persistent(url)
        let first = record("Workshop"), second = record("Office")
        precondition(queue.present(first) && queue.present(second))
        precondition(queue.acknowledgeAndPause())
        precondition(queue.isPaused && queue.current == nil)
        precondition(queue.unacknowledgedCount == 1 && queue.pendingCount == 1)
        // Both effects are visible together after reopening.
        var reopened = try persistent(url)
        precondition(reopened.isPaused && reopened.current == nil && reopened.pending == [second])
        precondition(reopened.dismiss(), "Dismissing while paused never acknowledges a hidden record.")
        precondition(reopened.unacknowledgedCount == 1)
        precondition(reopened.resume() && reopened.current == second)

        // Failure leaves BOTH effects undone: lock the file so the transaction cannot start.
        let failureURL = makeURL()
        var failing = try persistent(failureURL)
        let head = record("Head")
        precondition(failing.present(head))
        let lock = Probe(failureURL)
        precondition(lock.exec("BEGIN IMMEDIATE") == SQLITE_OK)
        precondition(failing.acknowledgeAndPause() == false)
        precondition(failing.storageError != nil)
        precondition(!failing.isPaused && failing.current == head && failing.unacknowledgedCount == 1)
        precondition(lock.exec("ROLLBACK") == SQLITE_OK)
        precondition(failing.acknowledgeAndPause() && failing.isPaused && failing.unacknowledgedCount == 0)
        precondition(failing.storageError == nil)
    }

    static func sessionOptOutClearsEveryPageAndKeepsOrder() throws {
        let url = makeURL()
        var queue = try persistent(url)
        // 300 records: far more than one 33-record page. Session records are 2 of every 3.
        var survivors: [FleetCelebration] = []
        var sessionCount = 0
        for index in 0..<300 {
            let kind: FleetCelebration.Kind = index % 3 == 0 ? (index % 6 == 0 ? .bestShareAllTime : .blockFound) : .bestShareSession
            let item = record("Miner \(index)", kind)
            precondition(queue.present(item))
            if kind == .bestShareSession { sessionCount += 1 } else { survivors.append(item) }
        }
        precondition(queue.unacknowledgedCount == 300 && queue.bufferedCount <= 33)
        precondition(queue.removeSessionBests())
        precondition(queue.unacknowledgedCount == survivors.count, "\(sessionCount) session records must be gone from every page.")
        precondition(queue.bufferedCount <= 33)
        precondition(queue.current == survivors[0])
        precondition(queue.pending == Array(survivors[1..<min(survivors.count, 33)]))
        precondition(queue.removeSessionBests() && queue.unacknowledgedCount == survivors.count, "Idempotent.")
        // Late session records for already-removed IDs stay suppressed.
        queue = try persistent(url)
        var drained: [UUID] = []
        while let current = queue.current { drained.append(current.id); precondition(queue.dismiss()) }
        precondition(drained == survivors.map(\.id), "FIFO order of surviving records must be preserved.")
        precondition(drained.count == 100)
        // A session opt-out leaves a current all-time/block record on screen.
        var keep = try persistent(makeURL())
        let block = record("Studio", .blockFound)
        precondition(keep.present(block) && keep.present(record("Garage")) && keep.present(record("Attic", .bestShareAllTime)))
        precondition(keep.removeSessionBests() && keep.current == block && keep.pendingCount == 1)
        // A current session record is dismissed and the next surviving one is shown.
        var current = try persistent(makeURL())
        let session = record("Workshop"), allTime = record("Office", .bestShareAllTime)
        precondition(current.present(session) && current.present(record("Attic")) && current.present(allTime))
        precondition(current.removeSessionBests() && current.current == allTime && current.pendingCount == 0)
    }

    static func tenThousandRecordsStayFIFOWithBoundedCache() throws {
        let url = makeURL("large")
        var queue = try persistent(url)
        let count = 10_000
        var ids: [UUID] = []
        ids.reserveCapacity(count)
        var maxBuffered = 0
        let enqueueStart = Date()
        for index in 0..<count {
            let kind: FleetCelebration.Kind = [.bestShareAllTime, .blockFound, .bestShareSession][index % 3]
            let item = record("Bulk \(index)", kind)
            ids.append(item.id)
            precondition(queue.present(item))
            maxBuffered = max(maxBuffered, queue.bufferedCount)
            if index % 997 == 0 { precondition(queue.unacknowledgedCount == index + 1) }
        }
        let enqueueSeconds = Date().timeIntervalSince(enqueueStart)
        precondition(queue.unacknowledgedCount == count && queue.pendingCount == count - 1)
        precondition(maxBuffered <= 33 && queue.bufferedCount == 33, "The cache is one page, not the queue.")
        precondition(queue.pending.count == 32 && queue.pending.first?.id == ids[1])
        print(String(format: "  enqueued %d records in %.2fs (%.3f ms each), max buffered %d", count, enqueueSeconds,
                     enqueueSeconds * 1000 / Double(count), maxBuffered))

        // Reopen: nothing is lost, memory stays bounded, order is intact.
        queue = try persistent(url)
        precondition(queue.unacknowledgedCount == count && queue.bufferedCount == 33)
        precondition(queue.current?.id == ids[0])

        // Drain every record in FIFO order, checking the bound and counts at each step.
        let drainStart = Date()
        var worst: TimeInterval = 0
        for index in 0..<count {
            guard let current = queue.current else { preconditionFailure("Queue ended early at \(index)") }
            precondition(current.id == ids[index], "FIFO violated at \(index)")
            precondition(queue.unacknowledgedCount == count - index)
            precondition(queue.bufferedCount <= 33)
            let step = Date()
            precondition(queue.dismiss())
            worst = max(worst, Date().timeIntervalSince(step))
        }
        let drainSeconds = Date().timeIntervalSince(drainStart)
        precondition(queue.current == nil && queue.unacknowledgedCount == 0 && queue.bufferedCount == 0)
        print(String(format: "  drained %d records in %.2fs (%.3f ms each), worst single dismiss %.1f ms", count, drainSeconds,
                     drainSeconds * 1000 / Double(count), worst * 1000))
        // Acknowledged IDs stay suppressed after the drain and a relaunch.
        queue = try persistent(url)
        precondition(queue.present(record("Bulk fresh")))
        precondition(queue.unacknowledgedCount == 1)
        let probe = Probe(url)
        precondition(probe.scalar("SELECT COUNT(*) FROM records") == Int64(count + 1))
    }

}
