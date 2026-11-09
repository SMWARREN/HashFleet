import Foundation
import Testing
@testable import HashFleet

struct FleetReportSnapshotTests {
    @Test func emptyFleetHasUnknownTotalsNotZero() {
        let report = FleetReportFixtures.report([])
        #expect(report.miners.isEmpty)
        #expect(report.onlineCount == 0)
        #expect(report.offlineCount == 0)
        #expect(report.currentCount == 0)
        #expect(report.hashrate.value == nil)
        #expect(report.power.value == nil)
        #expect(report.power.coverage == "0 of 0 fresh online miners")
    }

    @Test func subtotalsExcludeStaleCachedOfflineAndUnconfirmedReadings() {
        let report = FleetReportFixtures.report([
            FleetReportFixtures.miner(id: 1, hashrate: 1_000, power: 20),
            FleetReportFixtures.miner(id: 2, hashrate: nil, power: 0),
            FleetReportFixtures.miner(id: 3, freshness: .stale, hashrate: 9_000, power: 90),
            FleetReportFixtures.miner(id: 4, freshness: .cached, hashrate: 9_000, power: 90),
            FleetReportFixtures.miner(id: 5, connection: .offline, hashrate: 9_000, power: 90),
            FleetReportFixtures.miner(id: 6, connection: .unknown, hashrate: 9_000, power: 90)
        ])
        #expect(report.onlineCount == 4)
        #expect(report.offlineCount == 1)
        #expect(report.unconfirmedCount == 1)
        #expect(report.currentCount == 2)
        #expect(report.nonFreshCount == 2)
        #expect(report.hashrate.value == 1_000)
        #expect(report.hashrate.reporting == 1)
        #expect(report.hashrate.coverage == "1 of 2 fresh online miners")
        #expect(report.power.value == 20)
        #expect(report.power.reporting == 2, "A measured zero is valid, unlike an absent field")
    }

    @Test func invalidAndOverflowMetricsNeverBecomeTotals() {
        let report = FleetReportFixtures.report([
            FleetReportFixtures.miner(id: 1, hashrate: .infinity, power: -1),
            FleetReportFixtures.miner(id: 2, hashrate: .nan, power: .nan)
        ])
        #expect(report.hashrate.value == nil)
        #expect(report.power.reporting == 0)
        let overflow = FleetReportFixtures.report([
            FleetReportFixtures.miner(id: 1, hashrate: .greatestFiniteMagnitude),
            FleetReportFixtures.miner(id: 2, hashrate: .greatestFiniteMagnitude)
        ])
        #expect(overflow.hashrate.value == nil)
        #expect(FleetReportSnapshot.number(.nan) == "Not reported")
        #expect(FleetReportSnapshot.number(-1) == "Not reported")
        #expect(FleetReportSnapshot.number(0) == "0.0")
        #expect(FleetReportSnapshot.formattedHashrate(nil) == "Not reported")
        #expect(FleetReportSnapshot.formattedHashrate(-1) == "Not reported")
        #expect(FleetReportSnapshot.formattedHashrate(.nan) == "Not reported")
        #expect(FleetReportSnapshot.formattedHashrate(.infinity) == "Not reported")
        #expect(FleetReportSnapshot.formattedHashrate(750) == "750 GH/s")
        #expect(FleetReportSnapshot.formattedHashrate(1_000) == "1.00 TH/s")
        #expect(FleetReportSnapshot.formattedHashrate(2_500) == "2.50 TH/s")
    }

    @Test func freshnessUsesCaptureTimeBoundaryAndRejectsFutureSkew() {
        let now = FleetReportFixtures.date
        typealias Freshness = FleetReportSnapshot.Freshness
        #expect(Freshness.classify(observedAt: now, capturedAt: now, isCached: false) == .fresh)
        #expect(Freshness.classify(observedAt: now.addingTimeInterval(-120), capturedAt: now, isCached: false) == .fresh)
        #expect(Freshness.classify(observedAt: now.addingTimeInterval(-121), capturedAt: now, isCached: false) == .stale)
        #expect(Freshness.classify(observedAt: now.addingTimeInterval(60), capturedAt: now, isCached: false) == .fresh)
        #expect(Freshness.classify(observedAt: now.addingTimeInterval(61), capturedAt: now, isCached: false) == .clockSkew)
        #expect(Freshness.classify(observedAt: nil, capturedAt: now, isCached: false) == .unknown)
        #expect(Freshness.classify(observedAt: now, capturedAt: now, isCached: true) == .cached)
    }

    @Test func timestampsAreExplicitUTCAndUnknownStaysUnknown() {
        #expect(FleetReportSnapshot.timestamp(FleetReportFixtures.date) == "2023-11-14T22:13:20Z")
        #expect(FleetReportSnapshot.timestamp(nil) == "Unknown")
        #expect(FleetReportSnapshot.timestamp(Date(timeIntervalSince1970: .infinity)) == "Unknown")
        #expect(FleetReportSnapshot.scopeNote.contains("not a daily report"))
        #expect(FleetReportSnapshot.scopeNote.contains("No history"))
    }

    @Test func powerFreshnessRejectsMissingStaleFutureAndNonFiniteObservationTimes() {
        let now = FleetReportFixtures.date
        #expect(FleetReportSnapshot.isFreshPowerObservation(observedAt: now, capturedAt: now))
        #expect(FleetReportSnapshot.isFreshPowerObservation(observedAt: now.addingTimeInterval(-120), capturedAt: now))
        #expect(!FleetReportSnapshot.isFreshPowerObservation(observedAt: now.addingTimeInterval(-121), capturedAt: now))
        #expect(!FleetReportSnapshot.isFreshPowerObservation(observedAt: now.addingTimeInterval(1), capturedAt: now))
        #expect(!FleetReportSnapshot.isFreshPowerObservation(observedAt: nil, capturedAt: now))
        #expect(!FleetReportSnapshot.isFreshPowerObservation(observedAt: Date(timeIntervalSince1970: .infinity), capturedAt: now))
    }
}

enum FleetReportFixtures {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)

    static func report(_ miners: [FleetReportSnapshot.Miner], isDemo: Bool = false) -> FleetReportSnapshot {
        FleetReportSnapshot(capturedAt: date, isDemo: isDemo, miners: miners)
    }

    static func miner(
        id: Int = 1,
        connection: FleetReportSnapshot.Connection = .online,
        freshness: FleetReportSnapshot.Freshness = .fresh,
        hashrate: Double? = 1_000,
        power: Double? = 20
    ) -> FleetReportSnapshot.Miner {
        .init(
            id: id, connection: connection, freshness: freshness, observedAt: date,
            hashrateGHs: hashrate, powerWatts: power, temperatureCelsius: 52,
            fanRPM: 3_000, uptimeSeconds: 600
        )
    }
}
