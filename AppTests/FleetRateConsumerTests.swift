import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Synthetic readings exercise rendered units without contacting a miner or changing preferences.
@MainActor
struct FleetRateConsumerTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test(arguments: [
        (0.00000213909, "2.14 kH/s"),
        (0.5, "500 MH/s"),
        (750.0, "750 GH/s"),
        (22_100.0, "22.10 TH/s")
    ])
    func tickerAndSavedSummaryUseTheSameAdaptiveUnit(rateGHs: Double, expected: String) throws {
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        let snapshot = MinerSnapshot(info: MinerInfo(raw: ["hashRate": .number(rateGHs)]), updatedAt: now)
        let ticker = FleetStatusTickerModel(devices: [device], snapshots: [device.id: snapshot])
        let item = try #require(ticker.items.first)
        #expect(item.segments == [expected])

        let glance = FleetGlance(
            updatedAt: now, onlineCount: 1, minerCount: 1,
            hashrateGHs: rateGHs, powerWatts: 10, isDemo: false
        )
        let summary = FleetSystemSummaryFormatter.format(glance, now: now)
        #expect(summary.contains(expected))
        if rateGHs < 1 {
            #expect(!summary.contains("GH/s"))
        }
        #expect(!summary.contains(device.address))
    }

    @Test
    func hashrateDropTextScalesBothReadingsIndependently() throws {
        let event = try #require(metricEvent(before: 3_000, current: 500))
        #expect(event.kind == .hashrateDrop)
        #expect(event.detail == "Hashrate fell from 3.00 TH/s to 500 GH/s.")
    }

    @Test
    func cpuHashrateDropTextDoesNotBecomeZeroGigahashes() throws {
        let event = try #require(metricEvent(before: 0.000004, current: 0.000002))
        #expect(event.kind == .hashrateDrop)
        #expect(event.detail == "Hashrate fell from 4.00 kH/s to 2.00 kH/s.")
        #expect(!event.detail.contains("GH/s"))
    }

    @Test
    func stoppedHashrateRetainsThePreviousReadingUnit() throws {
        let event = try #require(metricEvent(before: 3_000, current: 0))
        #expect(event.kind == .hashrateStopped)
        #expect(event.detail.contains("3.00 TH/s"))
        #expect(event.detail.contains("to zero"))
    }

    @Test
    func efficiencyAlertUsesTheSameJoulesPerTerahashScaleAsTheDashboard() throws {
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        let previous = MinerFleetStateObservation(isOnline: true, hashrate: 500, power: 20, observedAt: now)
        let current = MinerInfo(raw: ["hashRate": .number(450), "power": .number(24)])
        let event = try #require(MinerMetricAlertEvent.detect(
            device: device, previous: previous, current: current, occurredAt: now
        ))
        #expect(event.kind == .efficiencyDrop)
        #expect(event.detail == "Efficiency worsened from 40 J/TH to 53.3 J/TH.")
        #expect(!event.detail.contains("J/GH"))
    }

    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidBaselinesCannotCreateCredibleRateAlerts(before: Double) {
        #expect(metricEvent(before: before, current: 0) == nil)
    }

    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidCurrentRatesDoNotBecomeZeroRateAlerts(current: Double) {
        #expect(metricEvent(before: 3_000, current: current) == nil)
    }

    @Test
    func powerSpikeAlertFormatsBothReadingsInWatts() throws {
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        let previous = MinerFleetStateObservation(isOnline: true, hashrate: 1_000, power: 15.0, observedAt: now)
        let current = MinerInfo(raw: ["hashRate": .number(1_000), "power": .number(30.0)])
        let event = try #require(MinerMetricAlertEvent.detect(
            device: device, previous: previous, current: current, occurredAt: now
        ))
        #expect(event.kind == .powerSpike)
        #expect(event.detail == "Power rose from 15 W to 30 W.")
    }

    @Test
    func steadyOrImprovedMetricsDoNotProduceAlerts() {
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        let previous = MinerFleetStateObservation(isOnline: true, hashrate: 1_000, power: 20.0, observedAt: now)

        // Steady hashrate and power
        let steady = MinerInfo(raw: ["hashRate": .number(1_000), "power": .number(20.0)])
        #expect(MinerMetricAlertEvent.detect(device: device, previous: previous, current: steady, occurredAt: now) == nil)

        // Faster hashrate
        let faster = MinerInfo(raw: ["hashRate": .number(1_500), "power": .number(20.0)])
        #expect(MinerMetricAlertEvent.detect(device: device, previous: previous, current: faster, occurredAt: now) == nil)

        // Small drop below 25% threshold
        let minorDrop = MinerInfo(raw: ["hashRate": .number(900), "power": .number(20.0)])
        #expect(MinerMetricAlertEvent.detect(device: device, previous: previous, current: minorDrop, occurredAt: now) == nil)

        // Reduced power
        let lowerPower = MinerInfo(raw: ["hashRate": .number(1_000), "power": .number(15.0)])
        #expect(MinerMetricAlertEvent.detect(device: device, previous: previous, current: lowerPower, occurredAt: now) == nil)
    }

    private func metricEvent(before: Double, current: Double) -> MinerMetricAlertEvent? {
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        let previous = MinerFleetStateObservation(isOnline: true, hashrate: before, power: nil, observedAt: now)
        return MinerMetricAlertEvent.detect(
            device: device, previous: previous,
            current: MinerInfo(raw: ["hashRate": .number(current)]), occurredAt: now
        )
    }
}
