import Foundation

/// Local diagnostics contain dates and fixed outcomes only, never miner addresses or readings.
@MainActor
final class FleetBackgroundRefreshDiagnostics {
    enum Request: String, Codable, CaseIterable {
        case refresh, processing
    }

    enum Submission: String, Codable {
        case accepted, unavailable, notPermitted, tooManyRequests, failed

        var explanation: String {
            switch self {
            case .accepted: "Requested; iOS chooses when to run it"
            case .unavailable: "Background scheduling is unavailable"
            case .notPermitted: "Background scheduling is not permitted"
            case .tooManyRequests: "The system has too many pending requests"
            case .failed: "The system could not schedule this request"
            }
        }
    }

    enum Outcome: String, Codable {
        case completeSnapshot, noCompleteSnapshot, cancelled, expired

        var explanation: String {
            switch self {
            case .completeSnapshot: "A complete local snapshot was available"
            case .noCompleteSnapshot: "No complete local snapshot was available; the previous widget reading was kept"
            case .cancelled: "The local check was cancelled"
            case .expired: "iOS ended the available background time"
            }
        }
    }

    struct RequestState: Codable, Equatable {
        let requestedAt: Date
        let submission: Submission
    }

    struct Snapshot: Codable, Equatable {
        var refresh: RequestState?
        var processing: RequestState?
        var runID: UUID?
        var startedAt: Date?
        var finishedAt: Date?
        var outcome: Outcome?
    }

    static let shared = FleetBackgroundRefreshDiagnostics()
    private static let key = "app.hashfleet.background-diagnostics.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var snapshot: Snapshot {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(Snapshot.self, from: data) else { return Snapshot() }
        return value
    }

    func submitted(_ request: Request, result: Submission, at date: Date = .now) {
        var value = snapshot
        let requestState = RequestState(requestedAt: date, submission: result)
        switch request {
        case .refresh: value.refresh = requestState
        case .processing: value.processing = requestState
        }
        save(value)
    }

    @discardableResult
    func began(at date: Date = .now) -> UUID {
        var value = snapshot
        let id = UUID()
        value.runID = id
        value.startedAt = date
        value.finishedAt = nil
        value.outcome = nil
        save(value)
        return id
    }

    func finished(_ id: UUID, outcome: Outcome, at date: Date = .now) {
        var value = snapshot
        // A late completion or expiration must not replace a newer run or its terminal result.
        guard value.runID == id, value.finishedAt == nil else { return }
        value.finishedAt = date
        value.outcome = outcome
        save(value)
    }

    private func save(_ value: Snapshot) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Both background paths use the same completeness and cancellation gate. Publication keeps
/// the observation's timestamp and uses the coordinator's existing sharing and reload policy.
@MainActor
enum FleetBackgroundGlancePublication {
    @discardableResult
    static func publish(
        _ glance: FleetGlance,
        isComplete: Bool,
        expectedDemo: Bool,
        at date: Date = .now,
        using publish: @MainActor (FleetGlance) async -> Void
    ) async -> Bool {
        guard !Task.isCancelled, isComplete, glance.isValid, glance.minerCount > 0,
              glance.isDemo == expectedDemo, !glance.isStale(at: date) else { return false }
        await publish(glance)
        return !Task.isCancelled
    }
}
