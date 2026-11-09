import Foundation
import Darwin
import HashFleetCore

/// Minimal local connection metadata, separate from the aggregate-only widget cache.
struct FleetWidgetRefreshTarget: Codable, Hashable, Sendable {
    let id: UUID
    let baseURL: URL
    let expectedMAC: String

    init(id: UUID, baseURL: URL, expectedMAC: String) {
        self.id = id
        self.baseURL = baseURL
        self.expectedMAC = FleetScheduledCheckTarget.normalizedMAC(expectedMAC) ?? expectedMAC
    }

    var scheduledTarget: FleetScheduledCheckTarget {
        FleetScheduledCheckTarget(id: id, name: "Miner", baseURL: baseURL, expectedMAC: expectedMAC)
    }
    var isValid: Bool { scheduledTarget.isValid }

    var endpointKey: String {
        let scheme = baseURL.scheme?.lowercased() ?? ""
        let host = baseURL.host?.lowercased() ?? ""
        let port = baseURL.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }
}

/// Fixed outcomes only. Never persist raw firmware or localized network error descriptions.
enum FleetWidgetRefreshOutcome: String, Codable, Sendable {
    case refreshed, unavailable, needsSetup, busy, cancelled, timedOut

    var widgetMessage: String? {
        switch self {
        case .refreshed: nil
        case .unavailable: "Refresh failed · saved reading"
        case .needsSetup: "Open app to prepare refresh"
        case .busy: "Try refresh again shortly"
        case .cancelled: "Refresh stopped · saved reading"
        case .timedOut: "Refresh timed out · saved reading"
        }
    }
}

struct FleetWidgetRefreshConfiguration: Codable, Equatable, Sendable {
    let version: Int
    let generation: UUID
    let createdAt: Date
    var renewedAt: Date
    var expiresAt: Date
    let targets: [FleetWidgetRefreshTarget]
    // Missing in existing payloads means manual-only consent. Rotate on each new auto opt-in.
    var automaticRefreshGeneration: UUID?

    func isEnabled(at now: Date) -> Bool {
        // A clock rollback must not turn a future renewal into extended local-read permission.
        isValid && now.timeIntervalSince1970.isFinite && now >= createdAt.addingTimeInterval(-5)
            && now >= renewedAt.addingTimeInterval(-5) && now < expiresAt
    }

    var isValid: Bool {
        version == 1 && Self.validTargets(targets)
            && [createdAt, renewedAt, expiresAt].allSatisfy { $0.timeIntervalSince1970.isFinite }
            && createdAt <= renewedAt && renewedAt < expiresAt
            && expiresAt.timeIntervalSince(renewedAt) <= 24 * 60 * 60
    }

    static func validTargets(_ targets: [FleetWidgetRefreshTarget]) -> Bool {
        (1...16).contains(targets.count) && targets.allSatisfy(\.isValid)
            && Set(targets.map(\.id)).count == targets.count
            && Set(targets.map(\.endpointKey)).count == targets.count
            && Set(targets.compactMap { FleetScheduledCheckTarget.normalizedMAC($0.expectedMAC) }).count == targets.count
    }
}

struct FleetWidgetRefreshLease: Codable, Equatable, Sendable {
    let id: UUID
    let generation: UUID
    let startedAt: Date
    let expiresAt: Date
    var automaticRefreshGeneration: UUID?
}

struct FleetWidgetRefreshState: Codable, Equatable, Sendable {
    var configuration: FleetWidgetRefreshConfiguration
    var glance: FleetGlance?
    var lastOutcome: FleetWidgetRefreshOutcome?
    var lastAttemptAt: Date?
    var lease: FleetWidgetRefreshLease?
    var cooldownUntil: Date?

    var isValid: Bool {
        guard configuration.isValid else { return false }
        if let glance {
            guard glance.isValid, !glance.isDemo, glance.minerCount == configuration.targets.count,
                  glance.onlineCount == glance.minerCount, glance.updatedAt >= configuration.createdAt else { return false }
        }
        for date in [lastAttemptAt, cooldownUntil].compactMap({ $0 }) {
            guard date.timeIntervalSince1970.isFinite else { return false }
        }
        if let lease {
            guard lease.generation == configuration.generation,
                  lease.startedAt.timeIntervalSince1970.isFinite, lease.expiresAt.timeIntervalSince1970.isFinite,
                  lease.startedAt >= configuration.createdAt, lease.expiresAt > lease.startedAt,
                  lease.expiresAt.timeIntervalSince(lease.startedAt) <= 15 else { return false }
            if let automatic = lease.automaticRefreshGeneration,
               automatic != configuration.automaticRefreshGeneration { return false }
        }
        return true
    }
}

/// One bounded atomic state file, protected by one fixed flock inode shared by app and extension.
/// No network work occurs under the lock. Revocation never removes the lock file.
struct FleetWidgetRefreshStorage: Sendable {
    static let stateFilename = "fleet-widget-refresh-v1.json"
    static let lockFilename = "fleet-widget-refresh-v1.lock"
    static let maximumBytes = 65_536
    private let directory: URL?

    static var shared: Self {
        Self(directory: FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: FleetGlanceStorage.appGroup))
    }
    init(directory: URL?) { self.directory = directory?.isFileURL == true ? directory : nil }
    var isAvailable: Bool { directory != nil }

    func load() -> FleetWidgetRefreshState? {
        withLock { read(at: $0) } ?? nil
    }

    @discardableResult
    func configure(targets: [FleetWidgetRefreshTarget], now: Date, automatically: Bool = false) -> Bool {
        guard FleetWidgetRefreshConfiguration.validTargets(targets), now.timeIntervalSince1970.isFinite else { return false }
        let sorted = targets.sorted { $0.id.uuidString < $1.id.uuidString }
        return withLock { url in
            if var old = read(at: url), old.configuration.targets == sorted, old.configuration.isEnabled(at: now) {
                // Foreground live frames must not rotate generation or write the file at frame cadence.
                let consentChanged = updateAutomaticConsent(in: &old, enabled: automatically)
                let shouldRenew = now.timeIntervalSince(old.configuration.renewedAt) >= 60 * 60
                guard consentChanged || shouldRenew else { return true }
                if shouldRenew {
                    old.configuration.renewedAt = now
                    old.configuration.expiresAt = now.addingTimeInterval(24 * 60 * 60)
                }
                return write(old, at: url)
            }
            // Random generation prevents ABA after revoke/re-enable with the very same targets.
            let config = FleetWidgetRefreshConfiguration(version: 1, generation: UUID(), createdAt: now,
                renewedAt: now, expiresAt: now.addingTimeInterval(24 * 60 * 60), targets: sorted,
                automaticRefreshGeneration: automatically ? UUID() : nil)
            return write(FleetWidgetRefreshState(configuration: config), at: url)
        } ?? false
    }

    /// Changes only automatic consent, never prepares identities or extends their lifetime.
    @discardableResult
    func setAutomaticRefreshEnabled(_ enabled: Bool, now: Date) -> Bool {
        withLock { url in
            guard var state = read(at: url), !enabled || state.configuration.isEnabled(at: now) else { return false }
            guard updateAutomaticConsent(in: &state, enabled: enabled) else { return true }
            return write(state, at: url)
        } ?? false
    }

    private func updateAutomaticConsent(in state: inout FleetWidgetRefreshState, enabled: Bool) -> Bool {
        guard (state.configuration.automaticRefreshGeneration != nil) != enabled else { return false }
        state.configuration.automaticRefreshGeneration = enabled ? UUID() : nil
        // Invalidate an automatic read in flight without cancelling an authenticated manual read.
        if state.lease?.automaticRefreshGeneration != nil { state.lease = nil }
        return true
    }

    @discardableResult
    func revoke() -> Bool {
        guard isAvailable else { return true }
        return withLock { url in
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                return true
            } catch { return false }
        } ?? false
    }

    fileprivate enum Claim {
        case acquired(FleetWidgetRefreshConfiguration, FleetWidgetRefreshLease)
        case declined(FleetWidgetRefreshOutcome)
    }

    fileprivate func claim(at now: Date, automatically: Bool) -> Claim {
        withLock { url in
            guard var state = read(at: url), state.configuration.isEnabled(at: now) else { return .declined(.needsSetup) }
            guard !automatically || state.configuration.automaticRefreshGeneration != nil else { return .declined(.needsSetup) }
            if state.lease.map({ now < $0.expiresAt }) == true
                || state.cooldownUntil.map({ now < $0 }) == true { return .declined(.busy) }
            let lease = FleetWidgetRefreshLease(id: UUID(), generation: state.configuration.generation,
                startedAt: now, expiresAt: now.addingTimeInterval(15),
                automaticRefreshGeneration: automatically ? state.configuration.automaticRefreshGeneration : nil)
            state.lease = lease
            state.cooldownUntil = now.addingTimeInterval(15)
            guard write(state, at: url) else { return .declined(.unavailable) }
            return .acquired(state.configuration, lease)
        } ?? .declined(.unavailable)
    }

    fileprivate func finish(
        lease: FleetWidgetRefreshLease, glance: FleetGlance?, outcome: FleetWidgetRefreshOutcome, now: Date
    ) -> FleetWidgetRefreshOutcome {
        withLock { url in
            // Never create a missing payload here. This is the opt-out/reconfiguration barrier.
            guard var state = read(at: url), state.configuration.generation == lease.generation,
                  state.lease?.id == lease.id, state.configuration.isEnabled(at: now) else { return .needsSetup }
            if let automatic = lease.automaticRefreshGeneration,
               automatic != state.configuration.automaticRefreshGeneration { return .needsSetup }
            guard now < lease.expiresAt, now >= lease.startedAt.addingTimeInterval(-5) else { return .timedOut }
            let finalOutcome: FleetWidgetRefreshOutcome = Task.isCancelled ? .cancelled : outcome
            if finalOutcome == .refreshed {
                guard let glance, glance.isValid, !glance.isDemo,
                      glance.updatedAt >= lease.startedAt, glance.updatedAt <= now.addingTimeInterval(5),
                      glance.minerCount == state.configuration.targets.count,
                      glance.onlineCount == glance.minerCount else { return .unavailable }
                // Never let an older lease move the observation clock backward.
                if state.glance.map({ glance.updatedAt >= $0.updatedAt }) ?? true { state.glance = glance }
            }
            state.lease = nil
            state.cooldownUntil = now.addingTimeInterval(15)
            state.lastOutcome = finalOutcome
            state.lastAttemptAt = now
            return write(state, at: url) ? finalOutcome : .unavailable
        } ?? .unavailable
    }

    private func withLock<T>(_ operation: (URL) -> T) -> T? {
        guard let directory else { return nil }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return nil }
        let lock = directory.appendingPathComponent(Self.lockFilename)
        // Never wait indefinitely on an extension suspended while holding this short I/O lock.
        // O_EXLOCK atomically acquires a flock-semantics lock. Closing releases it.
        let flags = O_CREAT | O_RDWR | O_NOFOLLOW | O_EXLOCK | O_NONBLOCK | O_CLOEXEC
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(25))
        var fd = Darwin.open(lock.path, flags, 0o600)
        while fd < 0, [EWOULDBLOCK, EAGAIN, EINTR].contains(errno), ContinuousClock.now < deadline {
            Darwin.usleep(1_000)
            fd = Darwin.open(lock.path, flags, 0o600)
        }
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        return operation(directory.appendingPathComponent(Self.stateFilename))
    }

    private func read(at url: URL) -> FleetWidgetRefreshState? {
        // Read at most cap+1 bytes, not Data(contentsOf:) followed by a post-allocation size check.
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumBytes + 1), data.count <= Self.maximumBytes,
              let state = try? JSONDecoder().decode(FleetWidgetRefreshState.self, from: data), state.isValid else { return nil }
        return state
    }

    private func write(_ state: FleetWidgetRefreshState, at url: URL) -> Bool {
        guard state.isValid, let data = try? JSONEncoder().encode(state), data.count <= Self.maximumBytes else { return false }
        do {
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(values)
            return true
        } catch { return false }
    }
}

/// Cancellation is structured and cooperative. The production reader has its own bounded request
/// and response limits. Injected readers must honor cancellation too, never detached network tasks.
struct FleetWidgetRefreshRunner: Sendable {
    typealias Read = @Sendable (FleetScheduledCheckTarget) async throws -> FleetScheduledCheckReading
    private let storage: FleetWidgetRefreshStorage
    private let read: Read
    private let now: @Sendable () -> Date
    private let timeout: Duration

    init(storage: FleetWidgetRefreshStorage, read: @escaping Read = { try await FleetScheduledCheckReader().read($0) },
         now: @escaping @Sendable () -> Date = { Date() }, timeout: Duration = .seconds(10)) {
        self.storage = storage
        self.read = read
        self.now = now
        self.timeout = min(max(timeout, .milliseconds(1)), .seconds(10))
    }

    func refresh(
        automatically: Bool = false,
        publish: @Sendable (FleetActivityRefreshPublication) async -> Void = { _ in }
    ) async -> FleetWidgetRefreshOutcome {
        guard !Task.isCancelled else { return .cancelled }
        let configuration: FleetWidgetRefreshConfiguration
        let lease: FleetWidgetRefreshLease
        switch storage.claim(at: now(), automatically: automatically) {
        case .declined(let outcome): return outcome
        case .acquired(let config, let claimed): configuration = config; lease = claimed
        }
        var glance: FleetGlance?
        var outcome: FleetWidgetRefreshOutcome
        do {
            let readings = try await withThrowingTaskGroup(of: [ObservedReading].self) { group in
                group.addTask { try await readAll(configuration.targets) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw RefreshFailure.timedOut
                }
                defer { group.cancelAll() }
                return try await group.next() ?? []
            }
            try Task.checkCancellation()
            guard readings.count == configuration.targets.count,
                  let first = readings.map(\.startedAt).min() else { throw RefreshFailure.incomplete }
            let rate = readings.reduce(0) { $0 + ($1.value.hashRateGHs ?? .nan) }
            let power = readings.reduce(0) { $0 + ($1.value.powerW ?? .nan) }
            let result = FleetGlance(updatedAt: first, onlineCount: readings.count, minerCount: readings.count,
                hashrateGHs: rate, powerWatts: power, isDemo: false)
            guard result.isValid else { throw RefreshFailure.incomplete }
            glance = result
            outcome = .refreshed
        } catch is CancellationError { outcome = .cancelled } catch RefreshFailure.timedOut { outcome = .timedOut } catch { outcome = .unavailable }
        let finished = storage.finish(lease: lease, glance: glance, outcome: outcome, now: now())
        if finished == .refreshed, let glance, !Task.isCancelled {
            let publication = FleetActivityRefreshPublication(generation: configuration.generation, glance: glance,
                automaticRefreshGeneration: lease.automaticRefreshGeneration)
            if publication.isAuthorized(in: storage, at: now()) {
                await publish(publication)
            }
        }
        return finished
    }

    private struct ObservedReading: Sendable {
        let startedAt: Date
        let value: FleetScheduledCheckReading
    }
    private enum RefreshFailure: Error { case timedOut, incomplete }

    private func readAll(_ targets: [FleetWidgetRefreshTarget]) async throws -> [ObservedReading] {
        try await withThrowingTaskGroup(of: ObservedReading.self) { group in
            var next = 0
            func enqueue(_ target: FleetWidgetRefreshTarget) {
                group.addTask {
                    try Task.checkCancellation()
                    let start = now()
                    let value = try await read(target.scheduledTarget)
                    try Task.checkCancellation()
                    guard let rate = value.hashRateGHs, rate.isFinite, rate >= 0,
                          let power = value.powerW, power.isFinite, power >= 0 else { throw RefreshFailure.incomplete }
                    return ObservedReading(startedAt: start, value: value)
                }
            }
            while next < min(4, targets.count) { enqueue(targets[next]); next += 1 }
            var result: [ObservedReading] = []
            do {
                while let item = try await group.next() {
                    result.append(item)
                    if next < targets.count { enqueue(targets[next]); next += 1 }
                }
            } catch {
                group.cancelAll()
                throw error
            }
            return result
        }
    }
}
