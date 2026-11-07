import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#endif

/// A miner found by an explicit, read-only local-network scan.
public struct FleetDiscoveryCandidate: Hashable, Sendable {
    public let address: String
    public let name: String
    public let model: String?
    public let info: MinerInfo

    public init(address: String, name: String, model: String? = nil, info: MinerInfo) {
        self.address = address
        self.name = name
        self.model = model
        self.info = info
    }

    public var device: MinerDevice {
        MinerDevice(name: name, address: address, kind: .espMiner, usesAutomaticName: true)
    }
}

/// A bounded private-network scan plan. Discovery never leaves one local /24 or probes the
/// machine's own address.
public struct FleetDiscoveryScanPlan: Equatable, Sendable {
    public let localAddress: String
    public let hosts: [String]

    public init(localAddress: String, hosts: [String]) {
        self.localAddress = localAddress
        self.hosts = hosts
    }

    public static func current() -> FleetDiscoveryScanPlan? {
        guard let address = activeLocalIPv4Address() else { return nil }
        return plan(forIPv4Address: address)
    }

    public static func plan(forIPv4Address address: String) -> FleetDiscoveryScanPlan? {
        guard let octets = parseIPv4(address), isLocal(octets) else { return nil }
        let prefix = "\(octets[0]).\(octets[1]).\(octets[2])"
        let hosts = (1...254).compactMap { host -> String? in
            guard host != Int(octets[3]) else { return nil }
            return "\(prefix).\(host)"
        }
        return FleetDiscoveryScanPlan(localAddress: address, hosts: hosts)
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

    #if canImport(Darwin)
    private static func activeLocalIPv4Address() -> String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        var fallback: String?
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let flags = item.pointee.ifa_flags
            guard (flags & UInt32(IFF_UP)) != 0,
                (flags & UInt32(IFF_LOOPBACK)) == 0,
                let address = item.pointee.ifa_addr,
                Int32(address.pointee.sa_family) == AF_INET,
                let bytes = ipv4Bytes(address),
                isLocal(bytes)
            else { continue }
            let value = bytes.map(String.init).joined(separator: ".")
            let name = item.pointee.ifa_name.map { String(cString: $0) } ?? ""
            if name == "en0" || name == "en1" { return value }
            if fallback == nil && !name.hasPrefix("utun") && !name.hasPrefix("awdl") {
                fallback = value
            }
        }
        return fallback
    }

    private static func ipv4Bytes(_ address: UnsafeMutablePointer<sockaddr>) -> [UInt8]? {
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
            withUnsafeBytes(of: pointer.pointee.sin_addr) { Array($0) }
        }
    }
    #else
    private static func activeLocalIPv4Address() -> String? { nil }
    #endif
}

/// Performs one bounded, read-only GET `/api/system/info` probe per host. It rejects captive
/// portals and unrelated JSON, and never sends a write or retries a failed host.
public enum FleetNetworkDiscovery {
    private static let batchSize = 32
    private static let requestTimeout: TimeInterval = 1
    private static let resourceTimeout: TimeInterval = 8

    public static func scanCurrent() async -> [FleetDiscoveryCandidate] {
        guard let plan = FleetDiscoveryScanPlan.current() else { return [] }
        return await scan(plan: plan)
    }

    public static func scan(
        plan: FleetDiscoveryScanPlan,
        onProgress: (@Sendable ([FleetDiscoveryCandidate], Int) -> Void)? = nil
    ) async -> [FleetDiscoveryCandidate] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var candidates: [FleetDiscoveryCandidate] = []
        var probedCount = 0
        for offset in stride(from: 0, to: plan.hosts.count, by: batchSize) {
            guard !Task.isCancelled else { return sorted(candidates) }
            let end = min(offset + batchSize, plan.hosts.count)
            let batch = Array(plan.hosts[offset..<end])
            let results = await withTaskGroup(of: FleetDiscoveryCandidate?.self) { group in
                for host in batch {
                    group.addTask { await probe(host: host, session: session) }
                }
                var values: [FleetDiscoveryCandidate] = []
                for await candidate in group {
                    if let candidate { values.append(candidate) }
                }
                return values
            }
            candidates.append(contentsOf: results)
            probedCount += batch.count
            onProgress?(sorted(results), probedCount)
        }
        return sorted(candidates)
    }

    /// Pure response validation shared by the live scan and tests.
    public static func candidate(
        host: String,
        statusCode: Int,
        contentType: String?,
        body: Data
    ) -> FleetDiscoveryCandidate? {
        guard statusCode == 200 else { return nil }
        if let contentType, !contentType.lowercased().contains("json") { return nil }
        guard let info = try? JSONDecoder().decode(MinerInfo.self, from: body),
            MinerShapeValidator.isValidInfoShape(.object(info.raw)
            )
        else { return nil }

        let name = ["hostname", "fullHostname", "mdnsHostname", "deviceName"]
            .compactMap { info.raw[$0]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "Miner at \(host)"
        let model = ["ASICModel", "asicModel", "deviceModel", "boardVersion"]
            .compactMap { info.raw[$0]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return FleetDiscoveryCandidate(address: host, name: name, model: model, info: info)
    }

    public static func sorted(_ candidates: [FleetDiscoveryCandidate]) -> [FleetDiscoveryCandidate] {
        candidates.sorted { lhs, rhs in
            let order = compareAddresses(lhs.address, rhs.address)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func probe(host: String, session: URLSession) async -> FleetDiscoveryCandidate? {
        guard !Task.isCancelled, let url = URL(string: "http://\(host)/api/system/info") else {
            return nil
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: requestTimeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (body, response) = try await session.data(for: request, delegate: FleetDiscoveryRedirectBlocker())
            guard !Task.isCancelled, let http = response as? HTTPURLResponse else { return nil }
            return candidate(
                host: host,
                statusCode: http.statusCode,
                contentType: http.value(forHTTPHeaderField: "Content-Type"),
                body: body
            )
        } catch {
            return nil
        }
    }

    private static func compareAddresses(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        guard left.count == 4, right.count == 4 else {
            return lhs.localizedStandardCompare(rhs)
        }
        for index in 0..<4 where left[index] != right[index] {
            return left[index] < right[index] ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }
}

/// Discovery is a bounded one-origin scan. A redirect would otherwise let a response from an
/// unrelated origin be attributed to the original private-network host.
private final class FleetDiscoveryRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
