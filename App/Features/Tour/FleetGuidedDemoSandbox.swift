import Foundation
import Observation
import HashFleetCore

/// Isolated sandbox for the guided feature tour. Everything the tour touches lives behind
/// per-session state so real settings, real miners, and the real network can never be reached,
/// even if a view firing inside the tour accidentally triggers a refresh or a save.
///
/// Isolation layers:
/// 1. A unique private `UserDefaults` suite per sandbox. Nothing reads or writes `.standard`.
/// 2. An ephemeral `URLSession` whose protocol list contains only a deny-all `URLProtocol`.
///    Miner polls, capability probes, firmware checks, and public insight fetches all fail
///    instantly instead of hitting a physical miner or the public network.
/// Fallback safety comes from: `FleetStore.loadDemo()` latching `isDemo` (blocking persistence
/// paths and guardable refresh), `hardwareControlGate` being nil on this store instance (nil is
/// not itself a hardware gate), the deny-all session intercepting any stray request, and scoped
/// per-suite defaults containing all writes.
///
/// The sandbox deliberately creates no app group suites, widgets, notification settings, or
/// permission requests.
@MainActor @Observable
final class FleetGuidedDemoSandbox {
    /// Fully isolated fleet state, loaded with the standard demo fleet fixtures.
    let store: FleetStore
    /// Public-insights state pinned to demo fixtures, on the same deny-all session.
    let insights: MiningInsightsStore

    /// Unique defaults suite for this session. Exposed for tests and cleanup verification.
    let suiteName: String
    /// Number of URL requests this sandbox's session attempted and the deny-all protocol refused.
    var blockedRequestCount: Int {
        SandboxDenyAllURLProtocol.blockedCount(for: sandboxID)
    }

    /// Identifies this sandbox's URL traffic so blocked requests are attributed per session.
    let sandboxID = UUID()

    @ObservationIgnored private let defaults: UserDefaults
    /// Deny-all ephemeral session wiring the fleet and insights stores. Exposed for tests.
    @ObservationIgnored let session: URLSession
    @ObservationIgnored private var cleanedUp = false

    init() {
        let suiteName = "app.hashfleet.tour-sandbox.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            // This is not expected to fail; never fall back to shared defaults silently.
            preconditionFailure("FleetGuidedDemoSandbox could not create a private defaults suite.")
        }
        self.suiteName = suiteName
        self.defaults = defaults

        SandboxDenyAllURLProtocol.register(sandboxID)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SandboxDenyAllURLProtocol.self]
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpAdditionalHeaders = [
            SandboxDenyAllURLProtocol.sandboxHeader: sandboxID.uuidString
        ]
        let session = URLSession(configuration: configuration)
        self.session = session

        let store = FleetStore(defaults: defaults, session: session, hardwareControlGate: nil)
        store.loadDemo()
        store.preferences.hasSeenFeatureTour = true
        store.preferences.suppressFeatureTour = true
        self.store = store

        let insights = MiningInsightsStore(session: session)
        insights.setDemo(true)
        self.insights = insights
    }

    /// Warm the insights store with demo fixtures. Demo refreshes apply local fixture data and
    /// never hit the network, so this is a pure content warm-up.
    func prepare() async {
        guard !cleanedUp else { return }
        await insights.refresh()
    }

    /// Tears down the sandbox. Safe to call more than once; later calls do nothing.
    /// Cancels fleet refresh/live work and insight tasks, invalidates the deny-all session, and
    /// removes only this sandbox's private defaults suite.
    func cleanup() {
        guard !cleanedUp else { return }
        cleanedUp = true
        store.cancelRefresh()
        insights.cancel()
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suiteName)
        SandboxDenyAllURLProtocol.unregister(sandboxID)
    }

    deinit {
        // A missing cleanup must not leak the ephemeral session.
        session.invalidateAndCancel()
    }
}

/// Error intentionally reported for every request attempted inside a tour sandbox.
enum FleetGuidedDemoSandboxError: Error, CustomStringConvertible, Equatable {
    case blockedByTourSandbox

    var description: String {
        "Network access is disabled inside the guided tour sandbox."
    }
}

/// Deny-all protocol installed as the only protocol in a sandbox session. It counts every
/// attempted request per sandbox (via a per-session header tag) and fails it immediately.
final class SandboxDenyAllURLProtocol: URLProtocol, @unchecked Sendable {
    static let sandboxHeader = "X-HashFleet-TourSandbox-ID"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var counters: [UUID: Int] = [:]

    static func register(_ sandboxID: UUID) {
        lock.lock()
        counters[sandboxID] = 0
        lock.unlock()
    }

    static func unregister(_ sandboxID: UUID) {
        lock.lock()
        counters.removeValue(forKey: sandboxID)
        lock.unlock()
    }

    static func blockedCount(for sandboxID: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counters[sandboxID] ?? 0
    }

    private static func recordBlockedRequest(tag: String?) {
        lock.lock()
        if let tag, let sandboxID = UUID(uuidString: tag), counters[sandboxID] != nil {
            counters[sandboxID, default: 0] += 1
        }
        // Untagged or unknown-tag requests still fail, but are not attributed to any sandbox
        // rather than inflating every counter.
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canInit(with task: URLSessionTask) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recordBlockedRequest(tag: request.value(forHTTPHeaderField: Self.sandboxHeader))
        client?.urlProtocol(
            self,
            didFailWithError: URLError(.unknown, userInfo: [
                NSLocalizedDescriptionKey: FleetGuidedDemoSandboxError.blockedByTourSandbox.description
            ])
        )
    }

    override func stopLoading() {}
}
