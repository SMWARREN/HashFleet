import Foundation
import Observation

/// The presentation owner only reads snapshots. Connection creation, transactions, recovery
/// reads and connection teardown belong to the worker, never to a SwiftUI getter.
@MainActor @Observable
final class FleetCelebrationQueueController {
    struct Snapshot: Sendable, Equatable {
        var current: FleetCelebration?
        var pending: [FleetCelebration] = []
        var unacknowledgedCount = 0
        var isPaused = false
        var storageError: String?
        var pendingCount: Int { max(0, unacknowledgedCount - (current == nil ? 0 : 1)) }
    }

    enum Command: Sendable {
        case refresh
        case close
        case present(FleetCelebration, sessionEnabled: Bool)
        case dismiss(UUID)
        case pause(UUID)
        case acknowledgeAndPause(UUID)
        case resume(sessionEnabled: Bool)
        case removeSessionBests
    }

    struct Result: Sendable {
        let accepted: Bool
        let staleAction: Bool
        let snapshot: Snapshot
    }

    private(set) var snapshot = Snapshot()
    @ObservationIgnored private let worker: FleetCelebrationQueueWorker
    @ObservationIgnored private var tail: Task<Result, Never>?
    @ObservationIgnored private var sequence: UInt64 = 0

    init(isTesting: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) {
        worker = FleetCelebrationQueueWorker(configuration: .application(isTesting, arguments))
    }

    init(storageURL: URL) {
        worker = FleetCelebrationQueueWorker(configuration: .file(storageURL))
    }

    var current: FleetCelebration? { snapshot.current }
    var pendingCount: Int { snapshot.pendingCount }
    var unacknowledgedCount: Int { snapshot.unacknowledgedCount }
    var isPaused: Bool { snapshot.isPaused }
    var storageError: String? { snapshot.storageError }

    /// Submission order is established synchronously on MainActor, not by actor task scheduling.
    /// A caller cancelling its wait does not undo a durable acknowledgement already submitted.
    @discardableResult
    func submit(_ command: Command, completion: (@MainActor (Result) -> Void)? = nil) -> Task<Result, Never> {
        let previous = tail
        sequence &+= 1
        let ticket = sequence
        let task = Task { @MainActor [self] in
            if let previous { _ = await previous.value }
            let result = await worker.perform(command)
            snapshot = result.snapshot
            if ticket == sequence { tail = nil }
            completion?(result)
            return result
        }
        tail = task
        return task
    }
}

/// No connection or mutable queue object crosses this isolation boundary. Each command has
/// no suspension point, so its head check, transaction and returned snapshot are indivisible
/// with respect to the next command. The existing SQLite transaction/durability policy is intact.
actor FleetCelebrationQueueWorker {
    enum Configuration: Sendable {
        case application(Bool, [String])
        case file(URL)
    }
    private let configuration: Configuration
    private var queue: FleetCelebrationQueue?

    init(configuration: Configuration) { self.configuration = configuration }

    func perform(_ command: FleetCelebrationQueueController.Command) -> FleetCelebrationQueueController.Result {
        if case .close = command {
            queue = nil
            return .init(accepted: true, staleAction: false, snapshot: .init())
        }
        openQueueIfNeeded()
        var accepted = false
        var stale = false
        switch command {
        case .refresh:
            accepted = true
        case .close:
            preconditionFailure("Close is handled before opening storage")
        case let .present(event, sessionEnabled):
            if !sessionEnabled, event.kind == .bestShareSession {
                accepted = true
            } else if sessionEnabled || queue!.removeSessionBests() {
                accepted = queue!.present(event)
            }
        case .dismiss(let id), .pause(let id), .acknowledgeAndPause(let id):
            if queue!.current?.id != id {
                stale = true
            } else {
                switch command {
                case .dismiss: accepted = queue!.dismiss()
                case .pause: accepted = queue!.pause()
                case .acknowledgeAndPause: accepted = queue!.acknowledgeAndPause()
                default: break
                }
            }
        case .resume(let sessionEnabled):
            if sessionEnabled || queue!.removeSessionBests() { accepted = queue!.resume() }
        case .removeSessionBests:
            accepted = queue!.removeSessionBests()
        }
        // These getters may retry failed reads. All of them stay on this actor.
        let current = queue!.current
        let pending = queue!.pending
        let error = queue!.storageError
        let snapshot = FleetCelebrationQueueController.Snapshot(
            current: current, pending: pending, unacknowledgedCount: queue!.unacknowledgedCount,
            isPaused: queue!.isPaused, storageError: error)
        return .init(accepted: accepted, staleAction: stale, snapshot: snapshot)
    }

    private func openQueueIfNeeded() {
        if queue == nil {
            switch configuration {
            case let .application(testing, arguments):
                queue = FleetCelebrationQueueFactory.make(isTesting: testing, arguments: arguments)
            case .file(let url):
                do {
                    queue = try FleetCelebrationQueue(storageURL: url)
                } catch {
                    queue = FleetCelebrationQueue(unavailableMessage: "Record queue storage is unavailable: \(error.localizedDescription)")
                }
            }
        }
    }
}
