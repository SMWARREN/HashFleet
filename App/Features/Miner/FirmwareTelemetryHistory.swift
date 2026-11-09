import Foundation

/// A single domain reading as observed in one real miner snapshot.
struct FirmwareTelemetryDomainSample: Equatable, Identifiable, Sendable {
    let chipIndex: Int
    let domainIndex: Int
    let hashrateGHs: Double
    let nominalHashrateGHs: Double?

    var id: String { "\(chipIndex):\(domainIndex)" }
}

/// In-memory, per-detail-screen history. It deliberately has no persistence or sampling timer:
/// only caller-supplied snapshots can add a point.
struct FirmwareTelemetryHistory: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        let observedAt: Date
        let values: [String: Double]
    }

    private(set) var samples: [Sample] = []
    private(set) var domainIDs: [String] = []
    private(set) var resetReason: ResetReason?

    enum ResetReason: Equatable, Sendable {
        case identityChanged
        case firmwareChanged
        case uptimeRewound
        case topologyChanged
    }

    private var identity: String?
    private var firmware: String?
    private var uptime: Int?
    private var lastObservedAt: Date?
    private let capacity: Int

    init(capacity: Int = 30) {
        self.capacity = min(300, max(2, capacity))
    }

    static func mayRecordSample(
        observedAt: Date?,
        isCached: Bool,
        hasError: Bool,
        isReconnecting: Bool,
        isStale: Bool
    ) -> Bool {
        guard let observedAt, observedAt.timeIntervalSince1970.isFinite else { return false }
        return !isCached && !hasError && !isReconnecting && !isStale
    }

    mutating func record(
        domains: [FirmwareTelemetryDomainSample],
        observedAt: Date,
        identity: String,
        firmware: String?,
        uptimeSeconds: Int?
    ) {
        guard observedAt.timeIntervalSince1970.isFinite else { return }
        if let lastObservedAt, observedAt < lastObservedAt { return }
        let topology = domains.map(\.id).sorted()
        var reason: ResetReason?
        if let prior = self.identity, prior != identity {
            reason = .identityChanged
        } else if let prior = self.firmware, let firmware, prior != firmware {
            reason = .firmwareChanged
        } else if let prior = self.uptime, let uptimeSeconds, uptimeSeconds < prior {
            reason = .uptimeRewound
        } else if !domainIDs.isEmpty && topology != domainIDs {
            reason = .topologyChanged
        }

        if let reason {
            samples.removeAll(keepingCapacity: true)
            lastObservedAt = nil
            resetReason = reason
        } else {
            resetReason = nil
        }
        self.identity = identity
        self.firmware = firmware ?? self.firmware
        self.uptime = uptimeSeconds
        domainIDs = topology

        // Snapshot identity is the observation timestamp. Never duplicate a point from repeated
        // SwiftUI evaluations or unchanged HTTP responses.
        guard observedAt != lastObservedAt else { return }
        var values: [String: Double] = [:]
        for domain in domains where domain.hashrateGHs.isFinite && domain.hashrateGHs >= 0 {
            values[domain.id] = domain.hashrateGHs
        }
        guard !values.isEmpty else { return }
        samples.append(Sample(observedAt: observedAt, values: values))
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        lastObservedAt = observedAt
    }
}
