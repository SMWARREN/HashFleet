import Foundation
import SQLite3
#if canImport(AppKit)
import AppKit
import SwiftUI
#endif

extension CelebrationPersistenceRegressionTests {
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

extension FleetCelebrationQueueStorage {
    func acknowledgeHeadAndPauseSafely() {
        do { try acknowledgeHeadAndPause() } catch { preconditionFailure("\(error)") }
    }
}
