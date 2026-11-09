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
struct FleetCelebrationPersistenceRegressionTests {
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

    static func lockedDatabaseFailsClosedAndLeavesPriorStateIntact() throws {
        let url = makeURL()
        var queue = try persistent(url)
        let kept = record("Kept")
        precondition(queue.present(kept))
        let lock = Probe(url)
        precondition(lock.exec("BEGIN IMMEDIATE") == SQLITE_OK)
        let rejected = record("Rejected")
        precondition(queue.present(rejected) == false, "A failed write must not report acceptance.")
        precondition(queue.storageError != nil)
        precondition(queue.dismiss() == false && queue.pause() == false && queue.removeSessionBests() == false)
        precondition(queue.current == kept && queue.unacknowledgedCount == 1 && !queue.isPaused)
        precondition(lock.exec("ROLLBACK") == SQLITE_OK)
        precondition(lock.scalar("SELECT COUNT(*) FROM records") == 1, "The rejected record was not written.")
        // Same instance recovers once the lock clears, and the rejected record can be retried.
        precondition(queue.present(rejected))
        precondition(queue.storageError == nil)
        precondition(queue.unacknowledgedCount == 2 && queue.pending == [rejected])
        precondition(queue.dismiss() && queue.current == rejected)
    }

    static func nonDatabaseFileIsRejectedWithoutModification() throws {
        let url = makeURL("garbage")
        let bytes = Data("this is not sqlite at all, but it is precious".utf8)
        try bytes.write(to: url)
        do {
            _ = try persistent(url)
            preconditionFailure("A non-SQLite file must not be opened as a queue.")
        } catch let error as FleetCelebrationQueueStorageError {
            precondition(error == .notADatabase)
        }
        precondition(fileBytes(url) == bytes, "The rejected file must be byte-for-byte unchanged.")
        precondition(!FileManager.default.fileExists(atPath: url.path + "-wal"))
        // A truncated SQLite header with garbage after it is also not trusted.
        let damaged = makeURL("damaged")
        var damagedBytes = Data("SQLite format 3\0".utf8)
        damagedBytes.append(Data(repeating: 0xFF, count: 4096))
        try damagedBytes.write(to: damaged)
        do {
            _ = try persistent(damaged)
            preconditionFailure("A damaged database must not open as a queue.")
        } catch {}
        precondition(fileBytes(damaged) == damagedBytes, "The damaged file must be unchanged.")
        // A directory path or unwritable location throws instead of falling back to memory.
        do {
            _ = try persistent(root)
            preconditionFailure("A directory is not a database.")
        } catch {}
    }

    static func foreignAndNewerSchemaAreRejectedWithoutModification() throws {
        let foreign = makeURL("foreign")
        do {
            let probeDB = try seedDatabase(foreign, statements: ["CREATE TABLE unrelated (x INTEGER)", "INSERT INTO unrelated VALUES (7)"])
            _ = probeDB
        }
        let before = fileBytes(foreign)
        do {
            _ = try persistent(foreign)
            preconditionFailure("A foreign database must not be adopted.")
        } catch let error as FleetCelebrationQueueStorageError {
            precondition(error == .foreignDatabase)
        }
        precondition(fileBytes(foreign) == before)

        let newer = makeURL("newer")
        _ = try seedDatabase(newer, statements: ["PRAGMA user_version = 99"])
        let newerBefore = fileBytes(newer)
        do {
            _ = try persistent(newer)
            preconditionFailure("A newer schema must not be opened.")
        } catch let error as FleetCelebrationQueueStorageError {
            precondition(error == .unsupportedSchema(99))
        }
        precondition(fileBytes(newer) == newerBefore)
    }

    /// Version-1 files that carry the right table names but are not this queue's schema. Each must
    /// be rejected with every byte (and any WAL/SHM sidecar absence) unchanged, before WAL is enabled.
    static func malformedVersionOneDatabasesAreRejectedUnchanged() throws {
        let goodMeta = "CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL) WITHOUT ROWID"
        let goodRecords = """
            CREATE TABLE records (
                seq INTEGER PRIMARY KEY AUTOINCREMENT,
                id TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL,
                state INTEGER NOT NULL,
                payload BLOB
            )
            """
        let indexes = ["CREATE INDEX records_pending ON records (seq) WHERE state = 0",
                       "CREATE INDEX records_pending_kind ON records (kind, seq) WHERE state = 0"]
        let cases: [(String, [String])] = [
            ("wrong columns", ["CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL) WITHOUT ROWID",
                               "CREATE TABLE records (a TEXT, b TEXT)", "PRAGMA user_version = 1"]),
            ("missing payload column", [goodMeta, "CREATE TABLE records (seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, state INTEGER NOT NULL)",
                                        "PRAGMA user_version = 1"]),
            ("missing indexes", [goodMeta, goodRecords, "PRAGMA user_version = 1"]),
            ("wrong meta shape", ["CREATE TABLE meta (k TEXT, v TEXT)", goodRecords, indexes[0], indexes[1], "PRAGMA user_version = 1"]),
            ("extra trigger", [goodMeta, goodRecords, indexes[0], indexes[1],
                               "CREATE TRIGGER sneaky AFTER INSERT ON records BEGIN DELETE FROM records; END", "PRAGMA user_version = 1"]),
            ("invalid pause value", [goodMeta, goodRecords, indexes[0], indexes[1],
                                     "INSERT INTO meta VALUES ('paused', 7)", "PRAGMA user_version = 1"]),
            ("unknown meta key", [goodMeta, goodRecords, indexes[0], indexes[1],
                                  "INSERT INTO meta VALUES ('surprise', 1)", "PRAGMA user_version = 1"]),
            ("invalid row state", [goodMeta, goodRecords, indexes[0], indexes[1],
                                   "INSERT INTO records (id, kind, state, payload) VALUES ('x', 'k', 9, NULL)", "PRAGMA user_version = 1"])
        ]
        for (name, statements) in cases {
            let url = makeURL("malformed")
            _ = try seedDatabase(url, statements: statements)
            let before = fileBytes(url)
            do {
                _ = try persistent(url)
                preconditionFailure("Malformed version-1 database accepted: \(name)")
            } catch let error as FleetCelebrationQueueStorageError {
                precondition(error == .foreignDatabase, "\(name): unexpected error \(error)")
            }
            precondition(fileBytes(url) == before, "\(name): file changed")
            precondition(!FileManager.default.fileExists(atPath: url.path + "-wal"), "\(name): WAL created")
            precondition(!FileManager.default.fileExists(atPath: url.path + "-shm"), "\(name): SHM created")
        }
        // The exact healthy schema is still accepted, including rows written by a prior open.
        let healthy = makeURL("healthy")
        do {
            var queue = try persistent(healthy)
            precondition(queue.present(record("A")) && queue.pause())
        }
        let reopened = try persistent(healthy)
        precondition(reopened.isPaused && reopened.unacknowledgedCount == 1)
    }

    @discardableResult
    static func seedDatabase(_ url: URL, statements: [String]) throws -> Bool {
        var db: OpaquePointer?
        precondition(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK)
        defer { sqlite3_close(db) }
        for statement in statements { precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK) }
        return true
    }

    static func unreadableOldestRecordBlocksFIFOAndIsPreserved() throws {
        let url = makeURL()
        let later = record("Later")
        do {
            var queue = try persistent(url)
            precondition(queue.present(record("Oldest")))
            precondition(queue.present(later))
        }
        let garbage = "{ not json"
        let probe = Probe(url)
        precondition(probe.exec("UPDATE records SET payload = x'" + Data(garbage.utf8).map { String(format: "%02x", $0) }.joined()
                                + "' WHERE seq = (SELECT MIN(seq) FROM records)") == SQLITE_OK)
        let garbledBefore = probe.scalar("SELECT length(payload) FROM records WHERE seq = (SELECT MIN(seq) FROM records)")
        var queue = try persistent(url)
        precondition(queue.current == nil, "The later record must NOT be promoted past an unreadable older one.")
        precondition(queue.storageError != nil, "The blockage is surfaced to the user interface.")
        precondition(queue.unacknowledgedCount == 2 && queue.pendingCount == 2)
        precondition(queue.dismiss() && queue.unacknowledgedCount == 2, "Nothing is acknowledged while blocked.")
        precondition(queue.removeSessionBests() == true)
        // Both rows are session records here, so the bulk opt-out tombstones the later one and
        // the unreadable one alike, but never deletes bytes.
        precondition(probe.scalar("SELECT COUNT(*) FROM records") == 2)
        precondition(probe.scalar("SELECT length(payload) FROM records WHERE seq = (SELECT MIN(seq) FROM records)") == garbledBefore,
                     "The unreadable bytes are retained.")

        // With a non-session unreadable head the block persists across relaunch.
        let blockURL = makeURL()
        do {
            var seeded = try persistent(blockURL)
            precondition(seeded.present(record("Oldest", .blockFound)) && seeded.present(record("Next", .blockFound)))
        }
        let blockProbe = Probe(blockURL)
        precondition(blockProbe.exec("UPDATE records SET payload = x'7b' WHERE seq = (SELECT MIN(seq) FROM records)") == SQLITE_OK)
        for _ in 0..<2 {
            let reopened = try persistent(blockURL)
            precondition(reopened.current == nil && reopened.storageError != nil && reopened.unacknowledgedCount == 2)
        }
        precondition(blockProbe.scalar("SELECT COUNT(*) FROM records WHERE state = 0") == 2)
    }

    static func unavailableQueueFailsClosed() throws {
        var queue = FleetCelebrationQueue(unavailableMessage: "Storage is unavailable.")
        precondition(queue.present(record("Workshop")) == false)
        precondition(queue.current == nil && queue.pending.isEmpty && queue.unacknowledgedCount == 0 && queue.pendingCount == 0)
        precondition(queue.dismiss() == false && queue.pause() == false && queue.resume() == false)
        precondition(queue.acknowledgeAndPause() == false && queue.removeSessionBests() == false)
        precondition(queue.storageError == "Storage is unavailable.")
        precondition(queue.bufferedCount == 0 && !queue.isPaused)
    }

    static func handlesAreClosedAndNoStatementsLeak() throws {
        let url = makeURL()
        weak var weakStorage: FleetCelebrationQueueStorage?
        let descriptorsBefore = openDescriptorCount()
        do {
            let storage = try FleetCelebrationQueueStorage(location: .file(url))
            weakStorage = storage
            let enqueued = try storage.enqueue(record("A"))
            precondition(enqueued)
            storage.acknowledgeHeadAndPauseSafely()
            precondition(storage.openStatementCount == 0, "Every prepared statement is finalized.")
        }
        precondition(weakStorage == nil, "The storage object is released.")
        // Apple's SQLite keeps the -wal file after a clean close, so prove closure by file descriptors.
        precondition(openDescriptorCount() == descriptorsBefore, "SQLite handle must be closed (descriptor leak).")
        // The file can be removed and recreated cleanly.
        try FileManager.default.removeItem(at: url)
        let queue = try persistent(url)
        precondition(queue.unacknowledgedCount == 0)
        // Open failure paths must not leak a handle either: reopening many times keeps working.
        for _ in 0..<200 {
            let bad = makeURL("bad")
            try Data("nope".utf8).write(to: bad)
            _ = try? FleetCelebrationQueueStorage(location: .file(bad))
            try FileManager.default.removeItem(at: bad)
        }
        let beforeCycles = openDescriptorCount()
        for _ in 0..<50 {
            var cycled = try persistent(makeURL("cycle"))
            precondition(cycled.present(record("Cycle")) && cycled.dismiss())
        }
        precondition(openDescriptorCount() == beforeCycles, "Opening and releasing queues must not leak descriptors.")
        // Rejected opens (garbage files) must not leak descriptors either.
        let beforeRejects = openDescriptorCount()
        for _ in 0..<50 {
            let junk = makeURL("junk")
            try Data("nope".utf8).write(to: junk)
            _ = try? FleetCelebrationQueueStorage(location: .file(junk))
        }
        let foreignURL = makeURL("foreign-leak")
        _ = try seedDatabase(foreignURL, statements: ["CREATE TABLE unrelated (x)"])
        for _ in 0..<50 { _ = try? FleetCelebrationQueueStorage(location: .file(foreignURL)) }
        precondition(openDescriptorCount() == beforeRejects, "Failed opens must close their handle.")
    }

    #if canImport(AppKit)
    /// Records what the hosted view's body actually rendered after each queue mutation.
    @MainActor
    final class RenderProbe {
        var snapshots: [String] = []
        var apply: (((inout FleetCelebrationQueue) -> Void) -> Void)?
        var last: String { snapshots.last ?? "<none>" }
    }

    /// The queue struct holds only references, so its stored bytes never change on mutation.
    /// This hosts it in a real `@State` inside a real `NSHostingView`, the way the App does, and
    /// requires the body to re-run with new values after every kind of mutation, including a
    /// failed one that only changes `storageError`.
    @MainActor
    static func queueStateInvalidatesRealHostedSwiftUIState() {
        struct Harness: View {
            let probe: RenderProbe
            @State private var queue: FleetCelebrationQueue
            init(probe: RenderProbe, queue: FleetCelebrationQueue) {
                self.probe = probe
                _queue = State(initialValue: queue)
            }
            var body: some View {
                let snapshot = [
                    "current=\(queue.current?.minerName ?? "nil")",
                    "paused=\(queue.isPaused)",
                    "pending=\(queue.pendingCount)",
                    "unacked=\(queue.unacknowledgedCount)",
                    "error=\(queue.storageError == nil ? "none" : "set")"
                ].joined(separator: " ")
                probe.snapshots.append(snapshot)
                return VStack {
                    Text(queue.current?.minerName ?? "none")
                    Text("\(queue.pendingCount) more waiting")
                    Text(queue.storageError ?? "healthy")
                }
                .frame(width: 300, height: 200)
                .onAppear {
                    probe.apply = { mutation in mutation(&queue) }
                }
            }
        }

        let url = makeURL("hosted")
        guard let queue = try? FleetCelebrationQueue(storageURL: url) else { preconditionFailure("queue open failed") }
        let probe = RenderProbe()
        let host = NSHostingView(rootView: Harness(probe: probe, queue: queue))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        func pump() {
            let deadline = Date().addingTimeInterval(0.25)
            while Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
            host.layoutSubtreeIfNeeded()
        }
        func mutate(_ expected: String, _ message: String, _ mutation: (inout FleetCelebrationQueue) -> Void) {
            let before = probe.snapshots.count
            guard let apply = probe.apply else { preconditionFailure("The hosted view never appeared") }
            apply(mutation)
            pump()
            precondition(probe.snapshots.count > before, "\(message): the body never re-ran after mutation")
            precondition(probe.last == expected, "\(message): rendered '\(probe.last)' but expected '\(expected)'")
        }

        pump()
        precondition(probe.last == "current=nil paused=false pending=0 unacked=0 error=none", "initial render: \(probe.last)")
        let first = record("Alpha"), second = record("Beta"), third = record("Gamma")
        mutate("current=Alpha paused=false pending=0 unacked=1 error=none", "present first") { _ = $0.present(first) }
        mutate("current=Alpha paused=false pending=1 unacked=2 error=none", "present second") { _ = $0.present(second) }
        mutate("current=nil paused=true pending=2 unacked=2 error=none", "pause") { _ = $0.pause() }
        mutate("current=nil paused=true pending=3 unacked=3 error=none", "ingest while paused") { _ = $0.present(third) }
        mutate("current=Alpha paused=false pending=2 unacked=3 error=none", "resume") { _ = $0.resume() }
        mutate("current=Beta paused=false pending=1 unacked=2 error=none", "dismiss") { _ = $0.dismiss() }
        mutate("current=nil paused=true pending=1 unacked=1 error=none", "acknowledgeAndPause") { _ = $0.acknowledgeAndPause() }
        mutate("current=Gamma paused=false pending=0 unacked=1 error=none", "resume after acknowledgeAndPause") { _ = $0.resume() }

        // A failed mutation changes only storageError. It must still re-render.
        let lock = Probe(url)
        precondition(lock.exec("BEGIN IMMEDIATE") == SQLITE_OK)
        mutate("current=Gamma paused=false pending=0 unacked=1 error=set", "failed present surfaces error") {
            precondition($0.present(record("Rejected")) == false)
        }
        precondition(lock.exec("ROLLBACK") == SQLITE_OK)
        mutate("current=Gamma paused=false pending=1 unacked=2 error=none", "recovery clears error and counts the retried record") {
            precondition($0.present(record("Recovered")))
        }
        mutate("current=Gamma paused=false pending=2 unacked=3 error=none", "later record counted") { _ = $0.present(record("Delta")) }
    }
    #endif

    static func openDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
    }

    static func queriesUseIndexes() throws {
        let url = makeURL()
        var queue = try persistent(url)
        precondition(queue.present(record("A")))
        let probe = Probe(url)
        let head = probe.plan("SELECT seq, id, kind, payload FROM records WHERE state = 0 ORDER BY seq LIMIT 33")
        precondition(head.contains("records_pending"), "Head page must use the pending partial index: \(head)")
        precondition(!head.contains("SCAN records") || head.contains("USING"), "No full table scan: \(head)")
        let bulk = probe.plan("UPDATE records SET state = 1 WHERE state = 0 AND kind = 'bestShareSession'")
        precondition(bulk.contains("records_pending_kind"), "Session opt-out must use the kind index: \(bulk)")
        let byID = probe.plan("INSERT INTO records (id, kind, state, payload) VALUES ('x', 'k', 0, NULL) ON CONFLICT(id) DO NOTHING")
        _ = byID
        let ack = probe.plan("UPDATE records SET state = 1 WHERE seq = 1 AND state = 0")
        precondition(ack.contains("PRIMARY KEY") || ack.contains("rowid"), "Acknowledgement is a key lookup: \(ack)")
        queue.pause()
    }
}

private extension FleetCelebrationQueueStorage {
    func acknowledgeHeadAndPauseSafely() {
        do { try acknowledgeHeadAndPause() } catch { preconditionFailure("\(error)") }
    }
}
