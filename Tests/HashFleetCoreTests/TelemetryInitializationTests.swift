import Foundation
import XCTest
import GRDB
import SQLite3
@testable import HashFleetCore

@MainActor
final class TelemetryInitializationTests: XCTestCase {
    private enum OpeningFailure: Error { case expected, mainThread }
    private final class Heartbeat {
        var last = ProcessInfo.processInfo.systemUptime
        var maximumGap = 0.0
        var ticks = 0
        func tick() {
            let now = ProcessInfo.processInfo.systemUptime
            maximumGap = max(maximumGap, now - last)
            last = now
            ticks += 1
        }
    }

    private final class OpenHandshake: @unchecked Sendable {
        private let lock = NSLock()
        private var started = false
        private var released = false
        private let releaseSemaphore = DispatchSemaphore(value: 0)

        func signalStarted() {
            lock.lock()
            started = true
            lock.unlock()
        }

        var isStarted: Bool {
            lock.lock()
            defer { lock.unlock() }
            return started
        }

        func waitForRelease(timeout: TimeInterval = 2.0) -> Bool {
            releaseSemaphore.wait(timeout: .now() + timeout) == .success
        }

        func release() {
            lock.lock()
            defer { lock.unlock() }
            guard !released else { return }
            released = true
            releaseSemaphore.signal()
        }
    }

    func testDelayedOpeningDoesNotBlockMainActorAndSharesOneReadyQueue() async throws {
        let handshake = OpenHandshake()
        defer { handshake.release() }
        let database = MinerTelemetryDatabase(opening: {
            guard !Thread.isMainThread else { throw OpeningFailure.mainThread }
            handshake.signalStarted()
            guard handshake.waitForRelease(timeout: 2.0) else { throw OpeningFailure.expected }
            return try DatabaseQueue()
        })
        async let first = database.preparedQueue()
        async let second = database.preparedQueue()

        var progressTicks = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 2.0
        while !handshake.isStarted && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertTrue(handshake.isStarted, "Opening must start on a background thread")

        for _ in 0..<10 {
            progressTicks += 1
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertGreaterThanOrEqual(progressTicks, 10, "MainActor must make progress while opening is blocked")

        handshake.release()

        let (a, b) = await (first, second)
        let queue = try XCTUnwrap(a)
        XCTAssertTrue(queue === b, "Concurrent callers must await the same opener, not create separate stores")
        let again = await database.preparedQueue()
        XCTAssertTrue(queue === again)
        let tables = try await queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
        }
        XCTAssertTrue(Set(["miner_readings", "achievement_events", "connectivity_events", "pool_switches"]).isSubset(of: Set(tables)))
    }

    func testLockedSchemaInitializationKeepsMainActorResponsiveAndFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hashfleet-telemetry-init-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("isolated.sqlite").path
        var configuration = Configuration()
        configuration.busyMode = .timeout(0.25)
        let queue = try DatabaseQueue(path: path, configuration: configuration)
        try await queue.write { db in try db.execute(sql: "CREATE TABLE observation_marker (id INTEGER)") }
        var lock: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &lock), SQLITE_OK)
        defer { sqlite3_close(lock) }
        XCTAssertEqual(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        defer { sqlite3_exec(lock, "ROLLBACK", nil, nil, nil) }
        let beat = Heartbeat()
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                beat.tick()
                do { try await Task.sleep(for: .milliseconds(5)) } catch { break }
            }
        }
        defer { heartbeat.cancel() }
        try await Task.sleep(for: .milliseconds(20))
        let before = beat.ticks
        let start = ProcessInfo.processInfo.systemUptime
        let database = MinerTelemetryDatabase(opening: { queue })
        let prepared = await database.preparedQueue()
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertNil(prepared)
        XCTAssertGreaterThanOrEqual(elapsed, 0.20, "The actual SQLite busy wait must have occurred")
        XCTAssertGreaterThan(beat.ticks - before, 10)
        XCTAssertLessThan(beat.maximumGap, 0.10)
        do {
            try await database.clearAllDataChecked()
            XCTFail("Failed schema setup must not permit checked operations")
        } catch MinerTelemetryDatabaseError.unavailable { }
        print("Telemetry locked schema: elapsed=\(elapsed)s ticks=\(beat.ticks - before) maximumGap=\(beat.maximumGap)s")
    }

    func testBufferedReadingsSurviveOpeningAndAnAwaitedFlush() async throws {
        let database = MinerTelemetryDatabase(opening: {
            Thread.sleep(forTimeInterval: 0.15)
            return try DatabaseQueue()
        })
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for index in 0..<5 {
            database.recordReading(minerId: "isolated", timestamp: start.addingTimeInterval(Double(index)), reading: .init(hashrate: Double(index)))
        }
        let firstFlush = Task { @MainActor in await database.flushReadings() }
        try await Task.sleep(for: .milliseconds(30))
        for index in 5..<7 {
            database.recordReading(minerId: "isolated", timestamp: start.addingTimeInterval(Double(index)), reading: .init(hashrate: Double(index)))
        }
        await firstFlush.value
        await database.flushReadings()
        let samples = await database.getHashrateReadings(minerId: "isolated", since: start.addingTimeInterval(-1), until: start.addingTimeInterval(10))
        XCTAssertEqual(samples.map(\.hashrate), (0..<7).map(Double.init))
        XCTAssertTrue(database.pendingReadings.isEmpty)
    }

    func testOpeningFailureRefusesCheckedOperationsAndRetainsBufferedReadings() async {
        let database = MinerTelemetryDatabase(opening: { throw OpeningFailure.expected })
        database.recordReading(minerId: "isolated", reading: .init(hashrate: 123))
        await database.flushReadings()
        XCTAssertEqual(database.pendingReadings.count, 1)
        let prepared = await database.preparedQueue()
        XCTAssertNil(prepared)
        do {
            try await database.clearAllDataChecked()
            XCTFail("Unavailable initialization must not acknowledge a successful delete")
        } catch MinerTelemetryDatabaseError.unavailable {
            XCTAssertEqual(database.pendingReadings.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellingAWaiterDoesNotDiscardSharedInitialization() async throws {
        let database = MinerTelemetryDatabase(opening: {
            Thread.sleep(forTimeInterval: 0.05)
            return try DatabaseQueue()
        })
        let waiter = Task { @MainActor in await database.preparedQueue() }
        waiter.cancel()
        let cancelledResult = await waiter.value
        let subsequentResult = await database.preparedQueue()
        XCTAssertNotNil(cancelledResult)
        XCTAssertTrue(cancelledResult === subsequentResult)
        try await database.clearAllDataChecked()
    }
}
