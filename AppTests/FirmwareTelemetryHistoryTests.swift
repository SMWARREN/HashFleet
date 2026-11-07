import Foundation
import Testing
@testable import HashFleet

@Suite struct FirmwareTelemetryHistoryTests {
    private let domain = FirmwareTelemetryDomainSample(
        chipIndex: 0, domainIndex: 0, hashrateGHs: 120, nominalHashrateGHs: 140
    )

    @Test func recordsOnlyDistinctObservedSamplesAndBoundsHistory() {
        var history = FirmwareTelemetryHistory(capacity: 3)
        let start = Date(timeIntervalSince1970: 1_000)
        for offset in 0..<4 {
            history.record(domains: [domain], observedAt: start.addingTimeInterval(Double(offset)),
                           identity: "miner-A", firmware: "1.0", uptimeSeconds: 100 + offset)
        }
        history.record(domains: [domain], observedAt: start.addingTimeInterval(3),
                       identity: "miner-A", firmware: "1.0", uptimeSeconds: 103)
        #expect(history.samples.count == 3)
        #expect(history.samples.last?.values[domain.id] == 120)
    }

    @Test func rejectsNonfiniteAndOutOfOrderTimestampsAndClampsCapacity() {
        var history = FirmwareTelemetryHistory(capacity: 10_000)
        let now = Date(timeIntervalSince1970: 5_000)
        history.record(domains: [domain], observedAt: now, identity: "miner-A", firmware: "1.0", uptimeSeconds: 1)
        history.record(domains: [domain], observedAt: Date(timeIntervalSince1970: .nan),
                       identity: "miner-A", firmware: "1.0", uptimeSeconds: 2)
        history.record(domains: [domain], observedAt: now.addingTimeInterval(-1),
                       identity: "miner-A", firmware: "1.0", uptimeSeconds: 2)
        #expect(history.samples.count == 1)

        for offset in 1...305 {
            history.record(domains: [domain], observedAt: now.addingTimeInterval(Double(offset)),
                           identity: "miner-A", firmware: "1.0", uptimeSeconds: offset + 1)
        }
        #expect(history.samples.count == 300)
    }

    @Test func samplingPolicyExcludesCachedFailedReconnectingAndStaleSnapshots() {
        let date = Date(timeIntervalSince1970: 8_000)
        #expect(FirmwareTelemetryHistory.mayRecordSample(
            observedAt: date, isCached: false, hasError: false, isReconnecting: false, isStale: false
        ))
        #expect(!FirmwareTelemetryHistory.mayRecordSample(
            observedAt: date, isCached: true, hasError: false, isReconnecting: false, isStale: false
        ))
        #expect(!FirmwareTelemetryHistory.mayRecordSample(
            observedAt: date, isCached: false, hasError: true, isReconnecting: false, isStale: false
        ))
        #expect(!FirmwareTelemetryHistory.mayRecordSample(
            observedAt: date, isCached: false, hasError: false, isReconnecting: true, isStale: false
        ))
        #expect(!FirmwareTelemetryHistory.mayRecordSample(
            observedAt: date, isCached: false, hasError: false, isReconnecting: false, isStale: true
        ))
        #expect(!FirmwareTelemetryHistory.mayRecordSample(
            observedAt: nil, isCached: false, hasError: false, isReconnecting: false, isStale: false
        ))
    }

    @Test(arguments: [
        FirmwareTelemetryHistory.ResetReason.identityChanged,
        .firmwareChanged,
        .uptimeRewound,
        .topologyChanged
    ])
    func resetsWhenSampleContinuityBreaks(_ reason: FirmwareTelemetryHistory.ResetReason) {
        var history = FirmwareTelemetryHistory()
        let now = Date(timeIntervalSince1970: 1_000)
        history.record(domains: [domain], observedAt: now, identity: "miner-A", firmware: "1.0", uptimeSeconds: 100)
        let identity = reason == .identityChanged ? "miner-B" : "miner-A"
        let firmware = reason == .firmwareChanged ? "2.0" : "1.0"
        let uptime = reason == .uptimeRewound ? 1 : 101
        let domains = reason == .topologyChanged
            ? [FirmwareTelemetryDomainSample(chipIndex: 0, domainIndex: 1, hashrateGHs: 80, nominalHashrateGHs: nil)]
            : [domain]
        history.record(domains: domains, observedAt: now.addingTimeInterval(1), identity: identity,
                       firmware: firmware, uptimeSeconds: uptime)
        #expect(history.resetReason == reason)
        #expect(history.samples.count == 1)
    }

    @Test func missingAndNonFiniteDomainValuesDoNotCreateSyntheticSamples() {
        var history = FirmwareTelemetryHistory()
        history.record(domains: [], observedAt: Date(), identity: "miner-A", firmware: nil, uptimeSeconds: nil)
        history.record(domains: [FirmwareTelemetryDomainSample(
            chipIndex: 0, domainIndex: 0, hashrateGHs: .infinity, nominalHashrateGHs: nil
        )], observedAt: Date().addingTimeInterval(1), identity: "miner-A", firmware: nil, uptimeSeconds: nil)
        #expect(history.samples.isEmpty)
    }
}
