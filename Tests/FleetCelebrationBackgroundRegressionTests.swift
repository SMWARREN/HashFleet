import Foundation
import SQLite3

/// Standalone checks of the real actor/controller, queue and SQLite storage, with active
/// preconditions under -O. Every database is inside the newly created argument directory.
@main
@MainActor
struct CelebrationBackgroundRegressionTests {
    static func main() async throws {
        precondition(CommandLine.arguments.count == 2)
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        precondition(!FileManager.default.fileExists(atPath: root.path))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try await responsiveness(root.appendingPathComponent("locked.sqlite"))
        await orderingAndReopen(root.appendingPathComponent("ordered.sqlite"))
        try await failedOpen(root.appendingPathComponent("foreign.sqlite"))
        print("PASS: all background celebration storage checks")
    }

    static func record(_ value: String, session: Bool = false) -> FleetCelebration {
        FleetCelebration(kind: session ? .bestShareSession : .bestShareAllTime,
                         deviceID: UUID(), minerName: value, value: value, detail: "isolated test")
    }

    static func check(_ operation: Task<FleetCelebrationQueueController.Result, Never>, accepted: Bool = true) async {
        let result = await operation.value
        precondition(result.accepted == accepted)
    }

    @MainActor final class Pulse {
        var count = 0
        var gap = 0.0
        var last = ProcessInfo.processInfo.systemUptime
        func tick() {
            let now = ProcessInfo.processInfo.systemUptime
            gap = max(gap, now - last)
            last = now
            count += 1
        }
    }

    static func responsiveness(_ url: URL) async throws {
        let owner = FleetCelebrationQueueController(storageURL: url)
        precondition(!FileManager.default.fileExists(atPath: url.path), "Initializer must not open SQLite")
        precondition(owner.current == nil && owner.storageError == nil)
        let first = record("first"), second = record("second")
        await check(owner.submit(.present(first, sessionEnabled: true)))
        var lock: OpaquePointer?
        precondition(sqlite3_open_v2(url.path, &lock, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK)
        defer { sqlite3_exec(lock, "ROLLBACK", nil, nil, nil); sqlite3_close(lock) }
        precondition(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        let pulse = Pulse()
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                pulse.tick()
                // Read every presentation property during contention. None may perform I/O.
                _ = owner.current
                _ = owner.pendingCount
                _ = owner.unacknowledgedCount
                _ = owner.isPaused
                _ = owner.storageError
                do { try await Task.sleep(for: .milliseconds(5)) } catch { break }
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        let before = pulse.count
        let start = ProcessInfo.processInfo.systemUptime
        await check(owner.submit(.present(second, sessionEnabled: true)), accepted: false)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let ticks = pulse.count - before
        heartbeat.cancel()
        await heartbeat.value
        precondition(ticks > 0 && pulse.gap < 0.100, "SQLite blocked MainActor")
        precondition(owner.current?.id == first.id && owner.unacknowledgedCount == 1)
        precondition(sqlite3_exec(lock, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        await check(owner.submit(.present(second, sessionEnabled: true)))
        precondition(owner.unacknowledgedCount == 2)
        await check(owner.submit(.close))
        print("PASS: contention heartbeat ticks=\(ticks) maxGap=\(pulse.gap)s write=\(elapsed)s; failed acceptance and retry preserved")
    }

    static func orderingAndReopen(_ url: URL) async {
        let owner = FleetCelebrationQueueController(storageURL: url)
        let records = (0..<60).map { record("\($0)", session: $0 % 3 == 0) }
        // Submit without awaiting, then await in reverse: submission order, not wait order,
        // must determine SQLite FIFO. Cancelling a waiter must not discard an accepted record.
        let writes = records.map { owner.submit(.present($0, sessionEnabled: true)) }
        writes[20].cancel()
        for write in writes.reversed() { await check(write) }
        precondition(owner.current?.id == records[0].id && owner.unacknowledgedCount == 60)
        precondition(owner.snapshot.pending.count <= 32)
        let firstDismiss = owner.submit(.dismiss(records[0].id))
        let repeatedTap = owner.submit(.dismiss(records[0].id))
        await check(firstDismiss)
        let stale = await repeatedTap.value
        precondition(stale.staleAction && !stale.accepted && owner.current?.id == records[1].id)
        await check(owner.submit(.pause(records[1].id)))
        precondition(owner.isPaused && owner.current == nil && owner.unacknowledgedCount == 59)
        await check(owner.submit(.close))
        await check(owner.submit(.refresh))
        precondition(owner.isPaused && owner.unacknowledgedCount == 59)
        await check(owner.submit(.resume(sessionEnabled: true)))
        precondition(owner.current?.id == records[1].id)
        await check(owner.submit(.acknowledgeAndPause(records[1].id)))
        precondition(owner.isPaused && owner.unacknowledgedCount == 58)
        await check(owner.submit(.removeSessionBests))
        let expected = Array(records.dropFirst(2).filter { $0.kind != .bestShareSession })
        precondition(owner.unacknowledgedCount == expected.count)
        await check(owner.submit(.resume(sessionEnabled: false)))
        for item in expected {
            precondition(owner.current?.id == item.id)
            await check(owner.submit(.dismiss(item.id)))
        }
        precondition(owner.current == nil && owner.unacknowledgedCount == 0)
        await check(owner.submit(.close))
        await check(owner.submit(.present(records[1], sessionEnabled: true)))
        precondition(owner.unacknowledgedCount == 0, "Acknowledged ID was resurrected")
        await check(owner.submit(.present(record("disabled session", session: true), sessionEnabled: false)))
        precondition(owner.unacknowledgedCount == 0)
        await check(owner.submit(.close))
        print("PASS: submission FIFO, cancelled waiter, bounded page, stale tap, pause/reopen, atomic view-miner, cross-page opt-out, durable dedup")
    }

    static func failedOpen(_ url: URL) async throws {
        let bytes = Data("not a SQLite database".utf8)
        try bytes.write(to: url, options: .withoutOverwriting)
        let owner = FleetCelebrationQueueController(storageURL: url)
        await check(owner.submit(.present(record("must not accept"), sessionEnabled: true)), accepted: false)
        precondition(owner.current == nil && owner.storageError != nil)
        let retained = try Data(contentsOf: url)
        precondition(retained == bytes)
        await check(owner.submit(.close))
        print("PASS: corrupt input preserved and durable acceptance refused")
    }
}
