import Foundation

/// Record popups stay until acknowledged. A second miner's record waits rather than replacing
/// the popup the user is still reading, and waiting records keep strict FIFO order.
///
/// Every queue is backed by `FleetCelebrationQueueStorage` (SQLite):
/// - `init()` is ephemeral: a private in-memory database that touches no app state. Existing
///   unit tests and previews use it.
/// - `init(storageURL:)` is durable. Unacknowledged records, acknowledgement tombstones (which
///   suppress a repeat delivery after a crash) and the Review-later pause survive relaunch.
/// - `init(unavailableMessage:)` is fail-closed: it shows nothing, accepts nothing and surfaces
///   the message. It is what a caller uses when durable storage cannot be opened. There is
///   deliberately no silent fallback to a volatile queue.
///
/// Copies of the struct SHARE one storage object, so a copy sees the same records. Use one
/// owner. The store is not thread-safe. In the app, FleetCelebrationQueueWorker owns it
/// off MainActor. Compiler isolation is not imposed on this primitive so existing synchronous
/// storage tests keep compiling. Never transfer its shared storage between actors.
struct FleetCelebrationQueue {
    private let storage: FleetCelebrationQueueStorage?
    private let unavailable: String?

    /// Advances on every mutation attempt, including failed ones and no-ops. The struct otherwise
    /// holds only constant references, so a mutation through SwiftUI `@State` would leave its
    /// stored bytes unchanged and SwiftUI would not re-render. A changed stored value makes the
    /// write-back count as a change, which is how a failed mutation's `storageError` shows up too.
    private(set) var revision: UInt64 = 0

    /// Ephemeral in-memory queue. Shares nothing with disk.
    init() {
        // An in-memory SQLite database cannot fail to open short of memory exhaustion.
        if let storage = try? FleetCelebrationQueueStorage(location: .memory) {
            self.storage = storage
            unavailable = nil
        } else {
            storage = nil
            unavailable = "The in-memory celebration queue could not be created."
        }
    }

    /// Durable queue stored in a SQLite file at `storageURL`. Throws, without modifying an
    /// existing file, when it is not a usable celebration queue database.
    init(storageURL: URL) throws {
        storage = try FleetCelebrationQueueStorage(location: .file(storageURL))
        unavailable = nil
    }

    /// Durable queue, the same as `init(storageURL:)`.
    static func persistent(at url: URL) throws -> FleetCelebrationQueue {
        try FleetCelebrationQueue(storageURL: url)
    }

    /// Fail-closed queue for when storage cannot be opened.
    init(unavailableMessage: String) {
        storage = nil
        unavailable = unavailableMessage
    }

    // MARK: State

    /// The visible oldest unacknowledged record, or nil when paused, empty, unavailable, or the
    /// oldest record cannot be read.
    var current: FleetCelebration? {
        guard let storage, !storage.isPaused else { return nil }
        storage.ensureFresh()
        return storage.page.first
    }

    /// Review later: delivery is paused until `resume()`. Persisted.
    var isPaused: Bool { storage?.isPaused ?? false }

    /// Every record that has not been acknowledged, including the visible one.
    var unacknowledgedCount: Int { storage?.pendingTotal ?? 0 }

    /// Records still waiting. Excludes the record on screen, but includes the head while paused
    /// because nothing is on screen then.
    var pendingCount: Int {
        let visible = current == nil ? 0 : 1
        return max(0, unacknowledgedCount - visible)
    }

    /// At most the first 32 waiting records, in FIFO order, for small queues and tests. Use
    /// `pendingCount` for the real total: this array is a bounded cache page, not the queue.
    var pending: [FleetCelebration] {
        guard let storage else { return [] }
        storage.ensureFresh()
        return storage.isPaused ? Array(storage.page.prefix(FleetCelebrationQueueStorage.pageSize - 1))
            : Array(storage.page.dropFirst())
    }

    /// Records held in memory (at most 33), for diagnostics.
    var bufferedCount: Int { storage?.page.count ?? 0 }

    /// A user-facing description of the last storage problem, if any. Nil when healthy.
    var storageError: String? {
        guard let storage else { return unavailable }
        storage.ensureFresh()
        return storage.statusMessage
    }

    // MARK: Mutations

    /// Adds a record. True when it was durably enqueued, or when its ID is already pending or
    /// was already acknowledged. False when storage failed, so nothing was accepted.
    @discardableResult
    mutating func present(_ celebration: FleetCelebration) -> Bool {
        perform { _ = try $0.enqueue(celebration) }
    }

    /// Acknowledges the visible record. A no-op while paused or empty.
    @discardableResult
    mutating func dismiss() -> Bool {
        perform { try $0.acknowledgeHead() }
    }

    /// Hides the queue (Review later) without acknowledging anything.
    @discardableResult
    mutating func pause() -> Bool {
        perform { try $0.setPaused(true) }
    }

    @discardableResult
    mutating func resume() -> Bool {
        perform { try $0.setPaused(false) }
    }

    /// For View miner: acknowledges the visible record and pauses, atomically, so waiting
    /// records do not cover the miner page.
    @discardableResult
    mutating func acknowledgeAndPause() -> Bool {
        perform { try $0.acknowledgeHeadAndPause() }
    }

    /// An explicit session-only opt-out also clears records already waiting to be shown, on
    /// every page. Other kinds keep their current presentation and FIFO order.
    @discardableResult
    mutating func removeSessionBests() -> Bool {
        perform { _ = try $0.removeSessionBests() }
    }

    private mutating func perform(_ body: (FleetCelebrationQueueStorage) throws -> Void) -> Bool {
        revision &+= 1
        guard let storage else { return false }
        do {
            try body(storage)
            return true
        } catch {
            storage.note(error)
            return false
        }
    }
}
