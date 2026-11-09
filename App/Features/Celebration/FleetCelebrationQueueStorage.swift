import Foundation
import SQLite3

/// Failures the durable celebration store can surface. None of them is ever answered by
/// truncating, deleting or replacing an existing database file.
enum FleetCelebrationQueueStorageError: Error, Equatable, LocalizedError {
    /// The file exists, is not empty, and does not begin with the SQLite header.
    case notADatabase
    /// A valid SQLite file that was not created by this queue. It is left untouched.
    case foreignDatabase
    /// Written by a newer build. Opening it with this schema could lose information.
    case unsupportedSchema(Int)
    case integrityCheckFailed(String)
    case sqlite(operation: String, code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .notADatabase: "The celebration queue file is not a SQLite database. It was left unchanged."
        case .foreignDatabase: "The celebration queue file belongs to another database. It was left unchanged."
        case .unsupportedSchema(let version): "The celebration queue uses unsupported schema version \(version)."
        case .integrityCheckFailed(let detail): "The celebration queue failed its integrity check: \(detail)"
        case .sqlite(let operation, let code, let message): "Celebration queue \(operation) failed (SQLite \(code)): \(message)"
        }
    }
}

/// Durable FIFO storage for celebrations that have not been acknowledged yet.
///
/// Records live in one SQLite table keyed by event UUID, ordered by a monotonically assigned
/// `seq` (AUTOINCREMENT, so a sequence number is never reused). Acknowledged records keep their
/// UUID as a payload-free tombstone so a repeat delivery after a crash or relaunch cannot show
/// the same popup twice. Row states: 0 pending, 1 acknowledged tombstone. A pending row whose
/// payload cannot be decoded is retained byte for byte and blocks delivery (fail closed).
///
/// Memory is bounded: only the first ``pageSize`` pending records are cached, and counts are
/// maintained incrementally instead of being recomputed from the table. Every mutation is a
/// single `BEGIN IMMEDIATE` transaction, and cached state changes only after `COMMIT` succeeds.
///
/// A store is single-owner and not thread-safe. The app uses it from the main actor.
final class FleetCelebrationQueueStorage {
    enum Location: Equatable {
        /// Private, ephemeral database. Touches no app state.
        case memory
        case file(URL)
    }

    /// Head record plus up to 32 waiting ones.
    static let pageSize = 33
    static let schemaVersion = 1

    let location: Location
    private var db: OpaquePointer?

    // Bounded cache.
    private(set) var page: [FleetCelebration] = []
    private var pageSequences: [Int64] = []
    private var needsRefresh = false

    /// Pending, deliverable records (state 0). Excludes acknowledged rows.
    private(set) var pendingTotal = 0
    private var hasUnreadableRecord = false
    private(set) var isPaused = false
    private(set) var lastError: String?

    init(location: Location) throws {
        self.location = location
        let path: String
        switch location {
        case .memory:
            path = ":memory:"
        case .file(let url):
            path = url.path
            try Self.validateExistingFileHeader(url)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openCode = sqlite3_open_v2(path, &handle, flags, nil)
        db = handle
        guard openCode == SQLITE_OK else { throw error("open", openCode) }
        // From here a throw runs deinit, which closes the handle.
        try execute("PRAGMA busy_timeout = 250")
        // Read-only validation comes first: switching a foreign file to WAL would rewrite its header.
        let needsSchema = try validateSchema()
        let check = try query("PRAGMA quick_check(1)") { Self.text($0, 0) }.first ?? "no result"
        guard check == "ok" else { throw FleetCelebrationQueueStorageError.integrityCheckFailed(check) }
        if case .file = location {
            let mode = try query("PRAGMA journal_mode = WAL") { Self.text($0, 0) }.first ?? ""
            guard mode.lowercased() == "wal" else {
                throw FleetCelebrationQueueStorageError.sqlite(
                    operation: "journal mode", code: SQLITE_ERROR, message: "WAL unavailable (\(mode))")
            }
            try execute("PRAGMA synchronous = FULL")
        }
        if needsSchema { try createSchema() }
        isPaused = try query("SELECT value FROM meta WHERE key = 'paused'") { sqlite3_column_int64($0, 0) }.first == 1
        pendingTotal = try Int(query("SELECT COUNT(*) FROM records WHERE state = 0") { sqlite3_column_int64($0, 0) }[0])
        try refreshPage()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    /// Statements that were prepared and not yet finalized. Always zero between calls.
    var openStatementCount: Int {
        guard let db else { return 0 }
        var count = 0
        var statement = sqlite3_next_stmt(db, nil)
        while let current = statement {
            count += 1
            statement = sqlite3_next_stmt(db, current)
        }
        return count
    }

    // MARK: Reads

    /// Retries a refresh that failed after an otherwise committed mutation.
    func ensureFresh() {
        guard needsRefresh else { return }
        do {
            try refreshPage()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Mutations

    /// True when the record was newly enqueued. False when its ID already exists in any state.
    func enqueue(_ celebration: FleetCelebration) throws -> Bool {
        let payload = try Self.encode(celebration)
        var inserted = false
        try transaction {
            try run("""
                INSERT INTO records (id, kind, state, payload) VALUES (?, ?, 0, ?)
                ON CONFLICT(id) DO NOTHING
                """, [.text(celebration.id.uuidString), .text(celebration.kind.rawValue), .blob(payload)])
            inserted = sqlite3_changes(db) == 1
        }
        if inserted {
            pendingTotal += 1
            // Only a short cache can gain this record, so memory stays bounded.
            if page.count < Self.pageSize || needsRefresh { refreshAfterCommit() }
        }
        lastError = nil
        return inserted
    }

    /// Acknowledges the visible head. No-op when paused or empty.
    func acknowledgeHead() throws {
        guard !isPaused, let seq = pageSequences.first else { return }
        try acknowledge(sequence: seq, pause: false)
    }

    func setPaused(_ paused: Bool) throws {
        guard paused != isPaused else { return }
        try transaction { try writePaused(paused) }
        isPaused = paused
        lastError = nil
    }

    /// One transaction: acknowledge the visible head (if any) and pause delivery.
    func acknowledgeHeadAndPause() throws {
        if isPaused { return }
        try acknowledge(sequence: pageSequences.first, pause: true)
    }

    /// Tombstones every pending session-best record on every page, keeping the order of the rest.
    @discardableResult
    func removeSessionBests() throws -> Int {
        var removed = 0
        try transaction {
            // Payload bytes are kept: a pending row that failed to decode must never be destroyed,
            // and one bulk statement cannot tell which rows those are.
            try run("""
                UPDATE records SET state = 1
                WHERE state = 0 AND kind = ?
                """, [.text(FleetCelebration.Kind.bestShareSession.rawValue)])
            removed = Int(sqlite3_changes(db))
        }
        guard removed > 0 else { lastError = nil; return 0 }
        pendingTotal -= removed
        refreshAfterCommit()
        if !needsRefresh { lastError = nil }
        return removed
    }

    private func acknowledge(sequence: Int64?, pause: Bool) throws {
        var acked = 0
        try transaction {
            if let sequence {
                try run("UPDATE records SET state = 1, payload = NULL WHERE seq = ? AND state = 0", [.int(sequence)])
                acked = Int(sqlite3_changes(db))
            }
            if pause { try writePaused(true) }
        }
        if pause { isPaused = true }
        pendingTotal -= acked
        if acked > 0 { refreshAfterCommit() }
        if !needsRefresh { lastError = nil }
    }

    private func writePaused(_ paused: Bool) throws {
        try run("INSERT INTO meta (key, value) VALUES ('paused', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [.int(paused ? 1 : 0)])
    }

    /// Records a failure for display. The caller's prior state is intact: the transaction rolled back.
    func note(_ error: Error) {
        lastError = error.localizedDescription
    }

    // MARK: Page refresh

    /// Loads up to `pageSize` pending records through the partial index, stopping at the first
    /// one that cannot be decoded. That record is never skipped, deleted or rewritten: it stays
    /// the oldest pending record, `isBlockedByUnreadableRecord` becomes true once it reaches the
    /// head, and nothing behind it is promoted ahead of it, so FIFO is never faked.
    private func refreshPage() throws {
        needsRefresh = true
        let batch = try query("""
            SELECT seq, id, kind, payload FROM records WHERE state = 0 ORDER BY seq LIMIT ?
            """, [.int(Int64(Self.pageSize))]) { stmt -> (Int64, String, String, Data?) in
            let length = Int(sqlite3_column_bytes(stmt, 3))
            let data = sqlite3_column_blob(stmt, 3).map { Data(bytes: $0, count: length) }
            return (sqlite3_column_int64(stmt, 0), Self.text(stmt, 1), Self.text(stmt, 2), data)
        }
        var celebrations: [FleetCelebration] = []
        var sequences: [Int64] = []
        var unreadable = false
        for (seq, id, kind, data) in batch {
            guard let data, let celebration = Self.decode(data),
                  celebration.id.uuidString == id, celebration.kind.rawValue == kind else {
                unreadable = true
                break
            }
            celebrations.append(celebration)
            sequences.append(seq)
        }
        page = celebrations
        pageSequences = sequences
        hasUnreadableRecord = unreadable
        needsRefresh = false
    }

    /// Used after a COMMIT already succeeded. A refresh failure must not turn a durable
    /// mutation into a reported failure, so the cache fails closed (empty) and retries later.
    private func refreshAfterCommit() {
        do {
            try refreshPage()
        } catch {
            page = []
            pageSequences = []
            needsRefresh = true
            lastError = error.localizedDescription
        }
    }

    /// Set while the oldest undelivered record is unreadable and nothing may be shown.
    var isBlockedByUnreadableRecord: Bool { hasUnreadableRecord && page.isEmpty }

    var statusMessage: String? {
        if isBlockedByUnreadableRecord {
            return "The oldest saved celebration cannot be read. It was kept unchanged and later records wait behind it."
        }
        return lastError
    }

    // MARK: Payload

    static func encode(_ celebration: FleetCelebration) throws -> Data {
        let object: [String: Any] = [
            "version": 1,
            "userInfo": celebration.userInfo,
            "viewMinerAvailable": celebration.viewMinerAvailable
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func decode(_ data: Data) -> FleetCelebration? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] as? Int == 1,
              let userInfo = object["userInfo"] as? [String: String],
              // The ID must be stored explicitly: the model would invent a random one.
              userInfo[FleetCelebration.userInfoID] != nil,
              var celebration = FleetCelebration(userInfo: userInfo),
              let viewMinerAvailable = object["viewMinerAvailable"] as? Bool else { return nil }
        celebration.viewMinerAvailable = viewMinerAvailable
        return celebration
    }

    // MARK: Schema

    private static let schemaObjects: [(type: String, name: String, sql: String)] = [
        ("table", "meta", "CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL) WITHOUT ROWID"),
        ("table", "records", """
        CREATE TABLE records (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            state INTEGER NOT NULL,
            payload BLOB
        )
        """),
        ("index", "records_pending", "CREATE INDEX records_pending ON records (seq) WHERE state = 0"),
        ("index", "records_pending_kind", "CREATE INDEX records_pending_kind ON records (kind, seq) WHERE state = 0")
    ]

    /// Read-only. Returns true for a brand-new empty database that needs the schema created.
    private func validateSchema() throws -> Bool {
        let version = try Int(query("PRAGMA user_version") { sqlite3_column_int64($0, 0) }[0])
        let objectCount = try Int(query("SELECT COUNT(*) FROM sqlite_master") { sqlite3_column_int64($0, 0) }[0])
        switch version {
        case 0:
            guard objectCount == 0 else { throw FleetCelebrationQueueStorageError.foreignDatabase }
            return true
        case Self.schemaVersion:
            try validateCurrentSchema()
            return false
        default:
            throw FleetCelebrationQueueStorageError.unsupportedSchema(version)
        }
    }

    /// Strict and read-only: every object must be exactly what `createSchema` writes. A database
    /// that merely carries the right table names (wrong columns, missing indexes, extra triggers,
    /// invalid pause value, invalid row state) is foreign and is rejected before any pragma or
    /// statement could modify it.
    private func validateCurrentSchema() throws {
        let objects = try query("""
            SELECT type, name, sql FROM sqlite_master
            WHERE name NOT LIKE 'sqlite_autoindex_%' AND name <> 'sqlite_sequence'
            ORDER BY name
            """) { stmt -> String in
            Self.text(stmt, 0) + "|" + Self.text(stmt, 1) + "|" + Self.text(stmt, 2)
        }
        let expected = Self.schemaObjects.sorted { $0.name < $1.name }.map { $0.type + "|" + $0.name + "|" + $0.sql }
        guard objects == expected else {
            throw FleetCelebrationQueueStorageError.foreignDatabase
        }
        let columns = try query("PRAGMA table_info(records)") {
            "\(Self.text($0, 1)):\(Self.text($0, 2)):\(sqlite3_column_int($0, 3)):\(sqlite3_column_int($0, 5))"
        }
        guard columns == ["seq:INTEGER:0:1", "id:TEXT:1:0", "kind:TEXT:1:0", "state:INTEGER:1:0", "payload:BLOB:0:0"] else {
            throw FleetCelebrationQueueStorageError.foreignDatabase
        }
        let meta = try query("PRAGMA table_info(meta)") {
            "\(Self.text($0, 1)):\(Self.text($0, 2)):\(sqlite3_column_int($0, 3)):\(sqlite3_column_int($0, 5))"
        }
        guard meta == ["key:TEXT:1:1", "value:INTEGER:1:0"] else { throw FleetCelebrationQueueStorageError.foreignDatabase }
        let badMeta = try query("SELECT COUNT(*) FROM meta WHERE key <> 'paused' OR value NOT IN (0, 1) OR typeof(value) <> 'integer'") {
            sqlite3_column_int64($0, 0)
        }
        let badRows = try query("SELECT COUNT(*) FROM records WHERE state NOT IN (0, 1) OR typeof(state) <> 'integer' OR typeof(id) <> 'text' OR typeof(kind) <> 'text'") {
            sqlite3_column_int64($0, 0)
        }
        guard badMeta == [0], badRows == [0] else { throw FleetCelebrationQueueStorageError.foreignDatabase }
    }

    private func createSchema() throws {
        try transaction {
            for object in Self.schemaObjects { try run(object.sql) }
            try run("PRAGMA user_version = \(Self.schemaVersion)")
        }
    }

    private static func validateExistingFileHeader(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw FleetCelebrationQueueStorageError.sqlite(
                operation: "read", code: SQLITE_CANTOPEN, message: "Cannot read \(url.lastPathComponent)")
        }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 16)) ?? Data()
        // An empty file is a brand-new database. Anything else must be SQLite already.
        guard header.isEmpty || header == Data("SQLite format 3\0".utf8) else {
            throw FleetCelebrationQueueStorageError.notADatabase
        }
    }

    // MARK: SQLite plumbing

    private enum Bind {
        case int(Int64)
        case text(String)
        case blob(Data)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func error(_ operation: String, _ code: Int32) -> FleetCelebrationQueueStorageError {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database handle"
        return .sqlite(operation: operation, code: code, message: message)
    }

    private func execute(_ sql: String) throws {
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw error(sql, code) }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            // The failed attempt must leave the previous durable state intact.
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private func prepare(_ sql: String, _ binds: [Bind]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw error(sql, code)
        }
        for (offset, bind) in binds.enumerated() {
            let index = Int32(offset + 1)
            let bindCode: Int32
            switch bind {
            case .int(let value): bindCode = sqlite3_bind_int64(statement, index, value)
            case .text(let value): bindCode = sqlite3_bind_text(statement, index, value, -1, Self.transient)
            case .blob(let value):
                bindCode = value.withUnsafeBytes {
                    sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), Self.transient)
                }
            }
            guard bindCode == SQLITE_OK else {
                let failure = error(sql, bindCode)
                sqlite3_finalize(statement)
                throw failure
            }
        }
        return statement
    }

    private func run(_ sql: String, _ binds: [Bind] = []) throws {
        let statement = try prepare(sql, binds)
        defer { sqlite3_finalize(statement) }
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW { code = sqlite3_step(statement) }
        guard code == SQLITE_DONE else { throw error(sql, code) }
    }

    private func query<T>(_ sql: String, _ binds: [Bind] = [], _ map: (OpaquePointer) -> T) throws -> [T] {
        let statement = try prepare(sql, binds)
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW { results.append(map(statement)) } else if code == SQLITE_DONE { return results } else {
                throw error(sql, code)
            }
        }
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }
}
