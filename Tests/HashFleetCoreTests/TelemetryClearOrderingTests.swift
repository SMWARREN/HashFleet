import Foundation
import Dispatch
import XCTest
import GRDB
@testable import HashFleetCore

@MainActor
final class TelemetryClearOrderingTests: XCTestCase {
    func testCancelledWaiterDoesNotOrphanFIFOOrAllowOvertaking() async {
        let database = MinerTelemetryDatabase(inMemory: true)
        await database.acquireReadingsMutation()
        var acquired: [Int] = []
        var first: Task<Void, Never>?
        var second: Task<Void, Never>?
        // Each task resumes its starter before awaiting the gate. MainActor does not
        // yield between those statements, so the waiter is registered before we resume.
        await withCheckedContinuation { started in
            first = Task { @MainActor in
                started.resume()
                await database.acquireReadingsMutation()
                defer { database.releaseReadingsMutation() }
                acquired.append(1)
            }
        }
        await withCheckedContinuation { started in
            second = Task { @MainActor in
                started.resume()
                await database.acquireReadingsMutation()
                defer { database.releaseReadingsMutation() }
                acquired.append(2)
            }
        }
        first?.cancel()
        XCTAssertTrue(acquired.isEmpty)
        database.releaseReadingsMutation()
        await first?.value
        await second?.value
        XCTAssertEqual(acquired, [1, 2])
        await database.acquireReadingsMutation()
        acquired.append(3)
        database.releaseReadingsMutation()
        XCTAssertEqual(acquired, [1, 2, 3])
    }

    func testFailedDeleteRetainsPendingReadingsAndReleasesGate() async throws {
        let writer = try DatabaseQueue()
        defer { try? writer.close() }
        let database = MinerTelemetryDatabase(databaseQueue: writer)
        database.recordReading(minerId: "fixture", timestamp: Date(timeIntervalSince1970: 100),
                               reading: MinerReadingInput(hashrate: 10))
        await database.flushReadings()
        database.recordReading(minerId: "fixture", timestamp: Date(timeIntervalSince1970: 101),
                               reading: MinerReadingInput(hashrate: 20))
        try await writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_delete BEFORE DELETE ON miner_readings BEGIN
                    SELECT RAISE(ABORT, 'intentional delete failure');
                END
                """)
        }
        do {
            try await database.clearAllDataChecked()
            XCTFail("The real SQLite trigger must reject DELETE")
        } catch {
            XCTAssertTrue(String(describing: error).contains("intentional delete failure"))
        }
        XCTAssertEqual(database.pendingReadings.count, 1)
        try await writer.write { db in try db.execute(sql: "DROP TRIGGER reject_delete") }
        await database.flushReadings()
        let readings = await database.getHashrateReadings(minerId: "fixture", since: .distantPast)
        XCTAssertEqual(readings.map(\.hashrate), [10, 20])
        try await database.clearAllDataChecked()
        let remaining = try await writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM miner_readings")
        }
        XCTAssertEqual(remaining, 0)
    }

    func testClearBeforeFlushDoesNotResurrectBufferedQueueReadings() async throws {
        let writer = try DatabaseQueue()
        defer { try? writer.close() }
        let database = MinerTelemetryDatabase(databaseQueue: writer)
        try await assertClearBeforeFlush(database, writer: writer)
    }

    func testClearBeforeFlushDoesNotResurrectBufferedPoolReadings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashfleet-clear-ordering-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("isolated.sqlite")
        let database = MinerTelemetryDatabase(opening: {
            try MinerTelemetryDatabase.makePersistentPool(at: url)
        })
        let prepared = await database.preparedQueue()
        let writer = try XCTUnwrap(prepared as? DatabasePool)
        defer { try? writer.close() }
        try await assertClearBeforeFlush(database, writer: writer)
    }

    private func assertClearBeforeFlush(
        _ database: MinerTelemetryDatabase, writer: any DatabaseWriter
    ) async throws {
        database.recordReading(minerId: "fixture", timestamp: Date(timeIntervalSince1970: 100),
                               reading: MinerReadingInput(hashrate: 10))
        await database.flushReadings()
        XCTAssertTrue(database.pendingReadings.isEmpty)

        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        try await writer.write { db in
            db.add(function: DatabaseFunction("hold_test_delete", argumentCount: 0, pure: false) { _ in
                entered.signal()
                return release.wait(timeout: .now() + 10) == .success ? 1 : 0
            })
            try db.execute(sql: """
                CREATE TRIGGER hold_delete BEFORE DELETE ON miner_readings BEGIN
                    SELECT CASE WHEN hold_test_delete() = 0
                        THEN RAISE(ABORT, 'test delete gate timed out') END;
                END
                """)
        }

        // This reading predates the clear request, but is still only in memory.
        database.recordReading(minerId: "fixture", timestamp: Date(timeIntervalSince1970: 101),
                               reading: MinerReadingInput(hashrate: 20))
        XCTAssertEqual(database.pendingReadings.count, 1)
        let clearing = Task { @MainActor in try await database.clearAllDataChecked() }
        let didEnter: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: entered.wait(timeout: .now() + 5) == .success)
            }
        }
        XCTAssertTrue(didEnter, "The real DELETE must be blocked before the competing flush starts")
        let flushing = Task { @MainActor in await database.flushReadings() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !database.isFlushingReadings && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(database.isFlushingReadings, "Flush must enter while clear is suspended")
        release.signal()
        let clearResult = await clearing.result
        await flushing.value
        try clearResult.get()

        XCTAssertTrue(database.pendingReadings.isEmpty)
        let remaining = try await writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM miner_readings")
        }
        XCTAssertEqual(remaining, 0, "The pre-clear buffered reading must not be inserted after DELETE")
        // The order gate must not leave later, genuinely new readings stuck.
        database.recordReading(minerId: "fixture", timestamp: Date(timeIntervalSince1970: 102),
                               reading: MinerReadingInput(hashrate: 30))
        await database.flushReadings()
        let newReadings = await database.getHashrateReadings(minerId: "fixture", since: .distantPast)
        XCTAssertEqual(newReadings.map(\.hashrate), [30])
    }
}
