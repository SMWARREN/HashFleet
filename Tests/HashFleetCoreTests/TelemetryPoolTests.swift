import Foundation
import Dispatch
import XCTest
import GRDB
import SQLite3
@testable import HashFleetCore

@MainActor
final class TelemetryPoolTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashfleet-telemetry-pool-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func open(_ url: URL) async throws -> (MinerTelemetryDatabase, DatabasePool) {
        let database = MinerTelemetryDatabase(opening: {
            // The exact production pool factory must never open on the UI thread.
            guard !Thread.isMainThread else { throw PoolTestError.mainThread }
            return try MinerTelemetryDatabase.makePersistentPool(at: url)
        })
        let writer = await database.preparedQueue()
        let pool = try XCTUnwrap(writer as? DatabasePool)
        return (database, pool)
    }

    func testLegacyQueueFileKeepsSchemaAndDataAcrossPoolReopen() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("miner_telemetry.db")
        let legacyQueue = try DatabaseQueue(path: url.path)
        let legacy = MinerTelemetryDatabase(databaseQueue: legacyQueue)
        legacy.recordReading(minerId: "fixture", timestamp: Date(timeIntervalSince1970: 100),
                             reading: MinerReadingInput(hashrate: 1200, power: 25))
        await legacy.flushReadings()
        let schemaBefore = try await legacyQueue.read { db in
            try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name")
        }
        let journalBefore = try await legacyQueue.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        XCTAssertEqual(journalBefore, "delete")
        try legacyQueue.close()

        let (database, pool) = try await open(url)
        let schemaAfter = try await pool.read { db in
            try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name")
        }
        XCTAssertEqual(schemaBefore, schemaAfter)
        XCTAssertEqual(pool.configuration.maximumReaderCount, 2)
        let pragmas = try await pool.writeWithoutTransaction { db in
            (try String.fetchOne(db, sql: "PRAGMA journal_mode"),
             try Int.fetchOne(db, sql: "PRAGMA synchronous"))
        }
        XCTAssertEqual(pragmas.0, "wal")
        XCTAssertEqual(pragmas.1, 2, "Keep FULL commit durability instead of GRDB's WAL NORMAL default")
        database.recordReading(minerId: "fixture", timestamp: Date(timeIntervalSince1970: 101),
                               reading: MinerReadingInput(hashrate: 1300))
        await database.flushReadings()
        XCTAssertTrue(database.pendingReadings.isEmpty)
        try pool.close()

        let (reopened, reopenedPool) = try await open(url)
        defer { try? reopenedPool.close() }
        let readings = await reopened.getHashrateReadings(
            minerId: "fixture", since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(readings.map(\.hashrate), [1200, 1300])
        let repeatedReady = await reopened.preparedQueue()
        XCTAssertTrue(reopenedPool === repeatedReady)
    }

    func testHeldReaderDoesNotBlockSecondReaderOrTelemetryCommit() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (database, pool) = try await open(root.appendingPathComponent("isolated.sqlite"))
        defer { try? pool.close() }
        database.recordReading(minerId: "fixture", timestamp: Date(timeIntervalSince1970: 100),
                               reading: MinerReadingInput(hashrate: 1200))
        await database.flushReadings()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let heldReader = Task.detached {
            try await pool.read { db in
                let before = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM miner_readings")
                entered.signal()
                let released = release.wait(timeout: .now() + 5) == .success
                let after = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM miner_readings")
                return (before, after, released)
            }
        }
        let didEnter: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: entered.wait(timeout: .now() + 5) == .success)
            }
        }
        XCTAssertTrue(didEnter)
        // These actual API calls must finish BEFORE releasing the first reader.
        let secondRead = await database.getHashrateReadings(minerId: "fixture", since: .distantPast)
        XCTAssertEqual(secondRead.map(\.hashrate), [1200])
        database.recordReading(minerId: "fixture", timestamp: Date(timeIntervalSince1970: 101),
                               reading: MinerReadingInput(hashrate: 1300))
        await database.flushReadings()
        XCTAssertTrue(database.pendingReadings.isEmpty)
        let committedCount = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM miner_readings")
        }
        XCTAssertEqual(committedCount, 2)
        release.signal()
        let snapshot = try await heldReader.value
        XCTAssertTrue(snapshot.2, "A queued/blocked read or write must not pass by waiting for the test's safety timeout")
        XCTAssertEqual(snapshot.0, 1)
        XCTAssertEqual(snapshot.1, 1, "The held reader must retain its pre-write snapshot")
        let freshRead = await database.getHashrateReadings(minerId: "fixture", since: .distantPast)
        XCTAssertEqual(freshRead.map(\.hashrate), [1200, 1300])
    }

    func testExternalWriterLockRetainsBatchAndRetryCommitsExactlyOnce() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("isolated.sqlite")
        let (database, pool) = try await open(url)
        defer { try? pool.close() }
        var lock: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &lock), SQLITE_OK)
        defer { sqlite3_close(lock) }
        XCTAssertEqual(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        defer { sqlite3_exec(lock, "ROLLBACK", nil, nil, nil) }
        database.recordReading(minerId: "fixture", reading: MinerReadingInput(hashrate: 42))
        await database.flushReadings()
        XCTAssertEqual(database.pendingReadings.count, 1)
        let lockedRead = await database.getHashrateReadings(minerId: "fixture", since: .distantPast)
        XCTAssertTrue(lockedRead.isEmpty)
        XCTAssertEqual(sqlite3_exec(lock, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        await database.flushReadings()
        await database.flushReadings()
        XCTAssertTrue(database.pendingReadings.isEmpty)
        let recovered = await database.getHashrateReadings(minerId: "fixture", since: .distantPast)
        XCTAssertEqual(recovered.map(\.hashrate), [42])
    }

    func testFailedPooledDeleteRollsBackAndRetainsPendingBatch() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (database, pool) = try await open(root.appendingPathComponent("isolated.sqlite"))
        defer { try? pool.close() }
        database.recordReading(minerId: "fixture", reading: MinerReadingInput(hashrate: 10))
        await database.flushReadings()
        try await pool.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_delete BEFORE DELETE ON miner_readings BEGIN SELECT RAISE(ABORT, 'test rejection'); END")
        }
        database.recordReading(minerId: "fixture", reading: MinerReadingInput(hashrate: 20))
        do {
            try await database.clearAllDataChecked()
            XCTFail("The real delete failure must propagate")
        } catch {}
        XCTAssertEqual(database.pendingReadings.count, 1)
        let retained = await database.getHashrateReadings(minerId: "fixture", since: .distantPast)
        XCTAssertEqual(retained.map(\.hashrate), [10])
        try await pool.write { db in try db.execute(sql: "DROP TRIGGER reject_delete") }
        try await database.clearAllDataChecked()
        XCTAssertTrue(database.pendingReadings.isEmpty)
        let cleared = await database.getHashrateReadings(minerId: "fixture", since: .distantPast)
        XCTAssertTrue(cleared.isEmpty)
    }

    func testCorruptFileFailsClosedWithoutReplacingOriginalBytes() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("corrupt.sqlite")
        let original = Data(repeating: 0x55, count: 4096)
        try original.write(to: url, options: .withoutOverwriting)
        let database = MinerTelemetryDatabase(opening: {
            try MinerTelemetryDatabase.makePersistentPool(at: url)
        })
        let writer = await database.preparedQueue()
        XCTAssertNil(writer)
        database.recordReading(minerId: "fixture", reading: MinerReadingInput(hashrate: 5))
        await database.flushReadings()
        XCTAssertEqual(database.pendingReadings.count, 1)
        do {
            try await database.clearAllDataChecked()
            XCTFail("Unavailable storage must not report successful deletion")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDiskSizeIncludesOwnedWALSidecarsAndMemoryStoreIsZero() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("isolated.sqlite")
        let (database, pool) = try await open(url)
        defer { try? pool.close() }
        database.recordReading(minerId: "fixture", reading: MinerReadingInput(hashrate: 12))
        await database.flushReadings()
        let sizes = try [url.path, url.path + "-wal", url.path + "-shm"].map { path in
            try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64)
        }
        XCTAssertGreaterThan(sizes[1], 0)
        let actual = await database.getDatabaseSize()
        XCTAssertEqual(actual, sizes.reduce(0, +))
        let inMemory = MinerTelemetryDatabase(inMemory: true)
        let memorySize = await inMemory.getDatabaseSize()
        XCTAssertEqual(memorySize, 0)
    }

    private enum PoolTestError: Error { case mainThread }
}
