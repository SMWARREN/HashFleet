import Foundation

/// Tunable, validated bounds for a discovery scan. All fields are immutable and sanitized in `init`: times are
/// finite, positive and capped (request ~1s, per-host <=1.5s, overall <=60s), concurrency is clamped to 1...8,
/// and the byte cap is at least 1 and never above the shared 256 KiB ceiling. Non-finite inputs fall back to the
/// safe defaults rather than trapping.
struct WatchDiscoveryPolicy: Sendable, Equatable {
    /// Per-request idle timeout (~1s).
    let requestTimeout: TimeInterval
    /// Hard wall-clock deadline for a single host probe (<=1.5s).
    let perHostDeadline: TimeInterval
    /// Overall budget for the whole scan (<=60s).
    let overallBudget: TimeInterval
    /// Maximum concurrent probes (1...8).
    let maxConcurrent: Int
    /// Maximum bytes read from any one host (1...256 KiB).
    let maximumResponseBytes: Int

    init(
        requestTimeout: TimeInterval = 1.0,
        perHostDeadline: TimeInterval = 1.5,
        overallBudget: TimeInterval = 60,
        maxConcurrent: Int = 8,
        maximumResponseBytes: Int = WatchMinerHTTPClient.maximumResponseBytes
    ) {
        func safeTime(_ value: TimeInterval, cap: TimeInterval, fallback: TimeInterval) -> TimeInterval {
            guard value.isFinite, value > 0 else { return fallback }
            return min(value, cap)
        }
        self.requestTimeout = safeTime(requestTimeout, cap: 1.0, fallback: 1.0)
        self.perHostDeadline = safeTime(perHostDeadline, cap: 1.5, fallback: 1.5)
        self.overallBudget = safeTime(overallBudget, cap: 60, fallback: 60)
        self.maxConcurrent = max(1, min(maxConcurrent, 8))
        self.maximumResponseBytes = max(1, min(maximumResponseBytes, WatchMinerHTTPClient.maximumResponseBytes))
    }

    static let `default` = WatchDiscoveryPolicy()
}

/// Finds miners on the local Wi-Fi subnet by probing each candidate host once for `/api/system/info`.
///
/// It needs none of the desktop database, GRDB or WebSocket stack. Every probe is a single bounded, read-only,
/// redirect-refusing `GET`; no host is probed more than once; the whole scan is capped in time and concurrency by
/// a real task-group budget timer; and cancellation tears the session and in-flight tasks down promptly. No fixed
/// fleet IPs are ever used and nothing outside the interface's own mask is probed.
public struct WatchLocalMinerDiscovery: WatchMinerDiscovering {
    private let interfaceProvider: any WatchNetworkInterfaceProviding
    private let injectedSession: URLSession?
    private let policy: WatchDiscoveryPolicy

    /// Production discovery: real interface enumeration and a fresh bounded ephemeral session per scan.
    public init() {
        self.interfaceProvider = WatchSystemInterfaceProvider()
        self.injectedSession = nil
        self.policy = .default
    }

    /// Test/injection seam. A supplied session (for a `URLProtocol` stub) is never invalidated here; a session
    /// created internally is always torn down when the scan ends.
    init(
        interfaceProvider: any WatchNetworkInterfaceProviding,
        session: URLSession? = nil,
        policy: WatchDiscoveryPolicy = .default
    ) {
        self.interfaceProvider = interfaceProvider
        self.injectedSession = session
        self.policy = policy
    }

    /// One task-group outcome: either a finished probe or the overall budget timer firing.
    private enum Outcome: Sendable {
        case probe(host: UInt32, miner: WatchMiner?)
        case deadline
    }

    public func scan(
        onProgress: @escaping @Sendable (WatchDiscoveryProgress) async -> Void
    ) async throws -> WatchDiscoveryResult {
        try Task.checkCancellation()

        guard let interface = interfaceProvider.localInterface() else {
            throw WatchDiscoveryError.noLocalWiFi
        }
        let plan: WatchDiscoveryPlan
        do {
            plan = try WatchDiscoveryPlan(ipv4: interface.address, netmask: interface.netmask)
        } catch let error as WatchDiscoveryError {
            throw error
        } catch {
            throw WatchDiscoveryError.invalidPlan
        }

        let candidates = plan.hosts.map { (host: $0, address: WatchDiscoveryPlan.dottedQuad($0)) }
        let total = candidates.count
        let isPartial = plan.isPartialSubnet

        // A plan with no hosts (e.g. /31 or /32) is a valid, immediately-complete empty scan.
        guard total > 0 else {
            return WatchDiscoveryResult(
                miners: [], completedHosts: 0, totalHosts: 0,
                isPartialSubnet: isPartial, reachedTimeLimit: false
            )
        }

        let ownsSession = injectedSession == nil
        let session = injectedSession ?? WatchSecureHTTP.ephemeralSession(
            requestTimeout: policy.requestTimeout,
            resourceTimeout: policy.perHostDeadline,
            maximumConnectionsPerHost: policy.maxConcurrent
        )
        defer { if ownsSession { session.invalidateAndCancel() } }

        let transport = WatchHTTPTransport(session: session, maximumResponseBytes: policy.maximumResponseBytes)
        let policy = self.policy

        var discovered: [UInt32: WatchMiner] = [:]
        var completed = 0
        var reachedTimeLimit = false

        func snapshot() -> [WatchMiner] { discovered.keys.sorted().compactMap { discovered[$0] } }

        try await withThrowingTaskGroup(of: Outcome.self) { group in
            // Returning from a task group WAITS for children; it does not cancel them. Cancel explicitly so a
            // normal finish (or an early break) tears down the budget timer and any in-flight probes promptly.
            defer { group.cancelAll() }

            // A real timer task bounds the WHOLE scan independently of when individual probes finish. On caller
            // cancellation the sleep throws CancellationError, which we rethrow so it is never mistaken for the
            // budget firing.
            group.addTask {
                do { try await Task.sleep(for: .seconds(policy.overallBudget)) } catch { throw CancellationError() }
                return .deadline
            }

            var next = 0
            func launchNextProbe() {
                guard next < candidates.count else { return }
                let candidate = candidates[next]
                next += 1
                group.addTask {
                    let miner = try await Self.probe(
                        address: candidate.address, transport: transport, policy: policy
                    )
                    return .probe(host: candidate.host, miner: miner)
                }
            }

            for _ in 0..<policy.maxConcurrent { launchNextProbe() }

            loop: while let outcome = try await group.next() {
                // A caller cancellation must stop the loop before any further progress callback or launch.
                try Task.checkCancellation()
                switch outcome {
                case .deadline:
                    // Our own budget fired: stop launching, keep what we have (defer cancels the rest).
                    reachedTimeLimit = true
                    break loop
                case let .probe(host, miner):
                    completed += 1
                    if let miner { discovered[host] = miner }
                    await onProgress(WatchDiscoveryProgress(
                        miners: snapshot(), completedHosts: completed,
                        totalHosts: total, isPartialSubnet: isPartial
                    ))
                    // All candidates done: finish immediately rather than waiting on the budget timer.
                    if completed == total { break loop }
                    launchNextProbe()
                }
            }
        }

        // Only a genuine caller cancellation reaches here as a throw (above it would have propagated already).
        try Task.checkCancellation()
        return WatchDiscoveryResult(
            miners: snapshot(), completedHosts: completed, totalHosts: total,
            isPartialSubnet: isPartial, reachedTimeLimit: reachedTimeLimit
        )
    }

    /// Probes one host. Returns a validated `WatchMiner` when the response is a genuine miner, `nil` otherwise.
    /// Re-throws `CancellationError` so a cancelled scan stops promptly; all other failures mean "no miner here"
    /// (a non-answering, slow, or permission-blocked host is simply not discovered, never a false positive, and
    /// never silently equated with "offline").
    private static func probe(
        address: String,
        transport: WatchHTTPTransport,
        policy: WatchDiscoveryPolicy
    ) async throws -> WatchMiner? {
        guard let url = URL(string: "http://\(address):80/api/system/info") else { return nil }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: policy.requestTimeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, http) = try await transport.load(request, deadline: policy.perHostDeadline)
            // Discovery auto-adds, so be strict: exactly 200 and a JSON content type (or none).
            guard http.statusCode == 200, contentTypeAcceptable(http) else { return nil }
            guard let name = WatchDiscoveryIdentification.minerName(from: data) else { return nil }
            // The discovered endpoint is re-validated as a private local endpoint before it can ever be added.
            return try? WatchMiner(name: name, address: "http://\(address)")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return nil
        }
    }

    /// Accepts an absent content type, exactly `application/json`, or a structured `application/<subtype>+json`
    /// token with a non-empty subtype; everything else (HTML captive portals, `text/plain`, a bare `+json`, etc.)
    /// is rejected. Parameters after `;` are ignored.
    static func contentTypeAcceptable(_ http: HTTPURLResponse) -> Bool {
        guard let raw = http.value(forHTTPHeaderField: "Content-Type") else { return true }
        let mime = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        if mime == "application/json" { return true }
        guard mime.hasPrefix("application/"), mime.hasSuffix("+json") else { return false }
        // Require a non-empty subtype between "application/" and "+json".
        let subtype = mime.dropFirst("application/".count).dropLast("+json".count)
        return !subtype.isEmpty
    }
}
