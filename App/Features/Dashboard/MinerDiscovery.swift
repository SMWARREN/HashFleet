import Foundation
import Observation
import Darwin
import HashFleetCore

struct MinerDiscoveryCandidate: Identifiable, Hashable, Sendable {
    let address: String
    let name: String
    let model: String?

    var id: String { address }
}

enum MinerDiscoveryState: Equatable, Sendable {
    case idle
    case scanning(hostCount: Int)
    case results
    case noResults
    case unavailable(String)
}

/// Coordinates an explicitly requested, read-only local-network scan.
/// It never runs from refresh/polling and cancels all probes when the sheet disappears.
@MainActor @Observable
final class MinerDiscoveryCoordinator {
    /// A scan executor, injectable for tests. It must report each finished batch through
    /// the progress callback (found candidates in that batch, hosts probed so far) and
    /// finally return the complete, unsorted list of candidates.
    typealias ScanProgress = @Sendable ([MinerDiscoveryCandidate], Int) -> Void
    typealias ScanRunner = (MinerDiscoveryScanPlan, @escaping ScanProgress) async throws -> [MinerDiscoveryCandidate]

    private(set) var state: MinerDiscoveryState = .idle
    private(set) var candidates: [MinerDiscoveryCandidate] = []
    /// Hosts probed so far during the current scan, so the UI can show real progress
    /// instead of an indeterminate spinner for up to 254 addresses.
    private(set) var probedHosts: Int = 0
    private var task: Task<Void, Never>?
    private var scanID: UUID?
    private let planProvider: () -> MinerDiscoveryScanPlan?
    private let runner: ScanRunner

    init(
        planProvider: (() -> MinerDiscoveryScanPlan?)? = nil,
        runner: ScanRunner? = nil
    ) {
        self.planProvider = planProvider ?? { MinerDiscoveryScanPlan.current() }
        self.runner = runner ?? { plan, progress in
            try await MinerDiscoveryService.scan(plan: plan, onProgress: progress)
        }
    }

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    #if DEBUG
    func setTestState(_ state: MinerDiscoveryState, candidates: [MinerDiscoveryCandidate] = []) {
        self.state = state
        self.candidates = candidates
    }
    #endif

    func start() {
        cancel()
        candidates = []
        probedHosts = 0
        guard let plan = planProvider() else {
            state = .unavailable("A local IPv4 network was not available. Connect to Wi-Fi, then try again.")
            return
        }
        state = .scanning(hostCount: plan.hosts.count)
        let id = UUID()
        scanID = id
        task = Task { [weak self, runner] in
            guard let self else { return }
            do {
                let found = try await runner(plan) { batch, probed in
                    // `self` here is the non-optional let unwrapped above; capturing a weak
                    // var across this concurrent boundary is a Swift 6 error.
                    Task { @MainActor [self] in
                        guard isScanning, scanID == id else { return }
                        // Progressive disclosure: miners appear as soon as their batch
                        // finishes instead of all at once after the whole /24.
                        probedHosts = max(probedHosts, probed)
                        if !batch.isEmpty {
                            candidates = MinerDiscoveryService.sorted(candidates + batch)
                        }
                    }
                }
                guard !Task.isCancelled, scanID == id else { return }
                candidates = MinerDiscoveryService.sorted(found)
                probedHosts = plan.hosts.count
                state = found.isEmpty ? .noResults : .results
            } catch is CancellationError {
                // Dismissal and an explicit retry are expected cancellation paths.
            } catch MinerDiscoveryService.ScanError.networkUnavailable {
                guard !Task.isCancelled, scanID == id else { return }
                state = .unavailable(
                    "Local-network access is unavailable. Check Wi-Fi and Local Network access in Settings, then check access again."
                )
            } catch {
                guard !Task.isCancelled, scanID == id else { return }
                state = .unavailable(
                    "The local-network scan could not finish. You can still enter an address below."
                )
            }
        }
    }

    func cancel() {
        scanID = nil
        task?.cancel()
        task = nil
        if isScanning {
            // Cancelling keeps whatever was already found, including during the retry pass.
            state = candidates.isEmpty ? .idle : .results
        }
    }
}

struct MinerDiscoveryScanPlan: Equatable, Sendable {
    let localAddress: String
    let hosts: [String]

    /// Uses at most one bounded /24 on the active private or link-local IPv4 interface.
    /// It deliberately excludes public/cellular addresses and the phone's own address.
    static func current() -> MinerDiscoveryScanPlan? {
        guard let address = activeLocalIPv4Address() else { return nil }
        return plan(forIPv4Address: address)
    }

    static func plan(forIPv4Address address: String) -> MinerDiscoveryScanPlan? {
        guard let octets = parseIPv4(address), isLocal(octets) else { return nil }
        let prefix = "\(octets[0]).\(octets[1]).\(octets[2])"
        let hosts = (1...254).compactMap { host -> String? in
            guard host != Int(octets[3]) else { return nil }
            return "\(prefix).\(host)"
        }
        return MinerDiscoveryScanPlan(localAddress: address, hosts: hosts)
    }

    private static func parseIPv4(_ address: String) -> [UInt8]? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let values = parts.compactMap { UInt8($0) }
        return values.count == 4 ? values : nil
    }

    private static func isLocal(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else { return false }
        if octets[0] == 10 { return true }
        if octets[0] == 192 && octets[1] == 168 { return true }
        if octets[0] == 172 && (16...31).contains(Int(octets[1])) { return true }
        return octets[0] == 169 && octets[1] == 254
    }

    private static func activeLocalIPv4Address() -> String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let flags = item.pointee.ifa_flags
            guard (flags & UInt32(IFF_UP)) != 0,
                (flags & UInt32(IFF_LOOPBACK)) == 0,
                let name = item.pointee.ifa_name,
                String(cString: name) == "en0",
                let address = item.pointee.ifa_addr,
                Int32(address.pointee.sa_family) == AF_INET,
                let bytes = ipv4Bytes(address),
                isLocal(bytes)
            else { continue }
            return bytes.map(String.init).joined(separator: ".")
        }
        return nil
    }

    private static func ipv4Bytes(_ address: UnsafeMutablePointer<sockaddr>) -> [UInt8]? {
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
            withUnsafeBytes(of: pointer.pointee.sin_addr) { Array($0) }
        }
    }
}

struct MinerDiscoveryService: Sendable {
    enum ScanError: Error { case networkUnavailable }
    private static let batchSize = 32
    private static let requestTimeout: TimeInterval = 1
    private static let fallbackTimeout: TimeInterval = 2.5
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private enum ProbeResult: Sendable {
        case found(MinerDiscoveryCandidate)
        case retry(String)
        case noMatch
    }

    static func scan(
        plan: MinerDiscoveryScanPlan,
        onProgress: (@Sendable ([MinerDiscoveryCandidate], Int) -> Void)? = nil,
        transport injectedTransport: Transport? = nil
    ) async throws -> [MinerDiscoveryCandidate] {
        let initialSession = makeSession(timeout: requestTimeout)
        defer { initialSession.invalidateAndCancel() }
        let initialTransport: Transport = injectedTransport ?? { request in try await initialSession.data(for: request) }

        var candidates: [MinerDiscoveryCandidate] = []
        var retryHosts: [String] = []
        var probedCount = 0
        for batch in batches(plan.hosts) {
            let results = try await probeBatch(batch, transport: initialTransport, timeout: requestTimeout)
            candidates.append(contentsOf: results.found)
            retryHosts.append(contentsOf: results.retry)
            probedCount += batch.count
            onProgress?(results.found, probedCount)
        }
        if !retryHosts.isEmpty {
            // Give every transient miss one retry. A budget spent on early empty addresses
            // can otherwise leave later hosts with the same one-shot behavior as before.
            let retrySession = makeSession(timeout: fallbackTimeout)
            defer { retrySession.invalidateAndCancel() }
            let retryTransport: Transport = injectedTransport ?? { request in try await retrySession.data(for: request) }
            for batch in batches(retryHosts) {
                let results = try await probeBatch(batch, transport: retryTransport, timeout: fallbackTimeout)
                candidates.append(contentsOf: results.found)
                if !results.found.isEmpty { onProgress?(results.found, probedCount) }
            }
        }
        try Task.checkCancellation()
        return sorted(candidates)
    }

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        // The whole probe has a budget, not just the time between response bytes.
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }

    private static func batches(_ hosts: [String]) -> some Sequence<ArraySlice<String>> {
        stride(from: 0, to: hosts.count, by: batchSize).lazy.map { offset in
            hosts[offset..<min(offset + batchSize, hosts.count)]
        }
    }

    private static func probeBatch(
        _ hosts: ArraySlice<String>, transport: @escaping Transport, timeout: TimeInterval
    ) async throws -> (found: [MinerDiscoveryCandidate], retry: [String]) {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: ProbeResult.self) { group in
            for host in hosts {
                group.addTask { try await probe(host: host, transport: transport, timeout: timeout) }
            }
            var found: [MinerDiscoveryCandidate] = []
            var retry: [String] = []
            for try await result in group {
                switch result {
                case .found(let candidate): found.append(candidate)
                case .retry(let host): retry.append(host)
                case .noMatch: break
                }
            }
            try Task.checkCancellation()
            return (found, retry)
        }
    }

    /// Stable ordering for discovery results: numerically by IPv4 address, then by name.
    /// Numeric ordering matters because lexicographic order puts 192.168.1.10 before
    /// 192.168.1.2, which reads as out-of-order to a user comparing against their rack.
    static func sorted(_ candidates: [MinerDiscoveryCandidate]) -> [MinerDiscoveryCandidate] {
        candidates.sorted { lhs, rhs in
            let order = compareAddresses(lhs.address, rhs.address)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func compareAddresses(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = lhs.split(separator: ".").compactMap { Int($0) }
        let r = rhs.split(separator: ".").compactMap { Int($0) }
        guard l.count == 4, r.count == 4 else {
            return lhs.localizedStandardCompare(rhs)
        }
        for index in 0..<4 where l[index] != r[index] {
            return l[index] < r[index] ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    /// Pure response validation shared by the live scan and unit tests. A non-JSON responder or
    /// captive portal can never appear as a miner result.
    static func candidate(host: String, statusCode: Int, contentType: String?, body: Data) -> MinerDiscoveryCandidate? {
        guard statusCode == 200 else { return nil }
        if let contentType, !contentType.lowercased().contains("json") { return nil }
        guard let info = try? JSONDecoder().decode(MinerInfo.self, from: body),
            MinerShapeValidator.isValidInfoShape(.object(info.raw))
        else { return nil }
        let name =
            ["hostname", "fullHostname", "mdnsHostname", "deviceName"]
            .compactMap { info.raw[$0]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "Miner at \(host)"
        let model = ["ASICModel", "asicModel", "deviceModel", "boardVersion"]
            .compactMap { info.raw[$0]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return MinerDiscoveryCandidate(address: host, name: name, model: model)
    }

    private static func probe(host: String, transport: Transport, timeout: TimeInterval) async throws -> ProbeResult {
        try Task.checkCancellation()
        guard let url = URL(string: "http://\(host)/api/system/info") else { return .noMatch }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (body, response) = try await transport(request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, let match = candidate(
                host: host,
                statusCode: http.statusCode,
                contentType: http.value(forHTTPHeaderField: "Content-Type"),
                body: body
            ) else { return .noMatch }
            return .found(match)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where [.notConnectedToInternet, .dataNotAllowed].contains(error.code) {
            // A blocked network is not a successful scan that found zero miners.
            throw ScanError.networkUnavailable
        } catch let error as URLError where [.timedOut, .cannotConnectToHost, .networkConnectionLost].contains(error.code) {
            return .retry(host)
        } catch {
            return .noMatch
        }
    }
}

/// Groups discovered miners by model so a user with several units can find each one without
/// scanning a flat list. Ordering: groups alphabetically by model name, unknown-model miners
/// last; rows inside a group use the numeric-address ordering from `MinerDiscoveryService.sorted`.
enum MinerDiscoveryGrouping {
    static let otherTitle = "Other miners"

    struct Group: Equatable, Sendable {
        let title: String
        let candidates: [MinerDiscoveryCandidate]
    }

    static func groups(for candidates: [MinerDiscoveryCandidate]) -> [Group] {
        var groupsByKey: [String: (title: String, candidates: [MinerDiscoveryCandidate])] = [:]
        for candidate in candidates {
            let model = candidate.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = model.isEmpty ? "" : model.lowercased()
            var group = groupsByKey[key] ?? (model.isEmpty ? otherTitle : model, [])
            group.candidates.append(candidate)
            groupsByKey[key] = group
        }
        return groupsByKey.values
            .map { Group(title: $0.title, candidates: MinerDiscoveryService.sorted($0.candidates)) }
            .sorted { lhs, rhs in
                // Unknown-model devices always sort last so named models stay scannable.
                if lhs.title == otherTitle { return false }
                if rhs.title == otherTitle { return true }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }
}
