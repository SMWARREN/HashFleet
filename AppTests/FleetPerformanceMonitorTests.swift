import Foundation
import SwiftUI
import Testing
@testable import HashFleet

@Suite(.serialized) @MainActor
struct FleetPerformanceMonitorTests {

    @Test func differentScreensNeverShareTheirTimingSamples() throws {
        let monitor = FleetPerformanceMonitor(processArguments: [], drivesDisplayLink: false)
        monitor.enabled = true
        let fleet = monitor.claimScreen("Fleet")
        for index in 0...120 {
            let timestamp = 100 + Double(index) / 60
            monitor.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + 1 / 60, duration: 1 / 120)
        }
        let miner = monitor.claimScreen("Miner")
        #expect(monitor.accumulator.computeSummary() == nil)
        for index in 0...60 {
            let timestamp = 200 + Double(index) / 30
            monitor.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + 1 / 30, duration: 1 / 120)
        }
        monitor.releaseScreen(miner)
        let fleetSummary = try #require(monitor.screenReports["Fleet"])
        let minerSummary = try #require(monitor.screenReports["Miner"])
        #expect(abs(fleetSummary.callbackFPS - 60) < 0.01)
        #expect(abs(minerSummary.callbackFPS - 30) < 0.01)
        #expect(fleetSummary.maxGapMs < 17)
        #expect(minerSummary.maxGapMs < 34)
        #expect(monitor.accumulator.samples.count == 120)
        monitor.releaseScreen(fleet)
        monitor.enabled = false
    }

    @Test func disabledAndInactiveSamplingIsSuppressed() {
        let monitor = FleetPerformanceMonitor(processArguments: [], drivesDisplayLink: false)
        _ = monitor.claimScreen("Fleet")
        func feed(_ base: Double) {
            for index in 0...60 {
                let timestamp = base + Double(index) / 60
                monitor.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + 1 / 60, duration: 1 / 60)
            }
        }
        feed(10)
        #expect(monitor.screenReports.isEmpty)
        monitor.enabled = true
        feed(20)
        let count = monitor.accumulator.samples.count
        monitor.setActive(false)
        feed(100)
        #expect(monitor.accumulator.samples.count == count)
        monitor.setActive(true)
        feed(200)
        #expect((monitor.accumulator.computeSummary()?.maxGapMs ?? 0) < 17)
        monitor.enabled = false
    }

    @Test func invalidTimestampCannotPoisonCadenceOrTrapPercentiles() throws {
        var accumulator = CadenceAccumulator()
        for value in [Double.nan, Double.infinity, -Double.infinity, -1] {
            accumulator.recordFrame(timestamp: value, targetTimestamp: value + 0.02, duration: 0.02)
        }
        #expect(accumulator.computeSummary() == nil)
        accumulator.recordFrame(timestamp: 10, targetTimestamp: 10.02, duration: 0.02)
        accumulator.recordFrame(timestamp: 10.02, targetTimestamp: 10.04, duration: 0.02)
        let summary = try #require(accumulator.computeSummary())
        #expect(summary.callbackFPS.isFinite)
        #expect(abs(summary.callbackFPS - 50) < 0.01)
    }

    @Test func percentileUsesNearestRankRatherThanTheNextSample() throws {
        var accumulator = CadenceAccumulator()
        var timestamp = 100.0
        accumulator.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + 0.02, duration: 0.02)
        for index in 1...20 {
            timestamp += Double(index) / 1000
            accumulator.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + 0.02, duration: 0.02)
        }
        let summary = try #require(accumulator.computeSummary())
        #expect(abs(summary.p95GapMs - 19) < 0.001)
        #expect(abs(summary.maxGapMs - 20) < 0.001)
    }

    // MARK: - Cadence Accumulator Tests (Pure Math & Diagnostics)

    @Test func regular60HzCadence() throws {
        var accumulator = CadenceAccumulator(maxSamples: 100)
        let interval: CFTimeInterval = 1.0 / 60.0  // ~0.016667s
        var timestamp: CFTimeInterval = 100.0

        for _ in 0..<60 {
            let nextTarget = timestamp + interval
            accumulator.recordFrame(timestamp: timestamp, targetTimestamp: nextTarget, duration: interval)
            timestamp += interval
        }

        let summaryValue = try #require(accumulator.computeSummary())

        #expect(summaryValue.totalSamples == 59)
        #expect(abs(summaryValue.callbackFPS - 60.0) < 0.5)
        #expect(abs(summaryValue.averageFrameMs - 16.666) < 0.2)
        #expect(abs(summaryValue.p95GapMs - 16.666) < 0.2)
        #expect(abs(summaryValue.maxGapMs - 16.666) < 0.2)
        #expect(summaryValue.slowGapsCount == 0)
    }

    @Test func regular120HzCadence() throws {
        var accumulator = CadenceAccumulator(maxSamples: 200)
        let interval: CFTimeInterval = 1.0 / 120.0  // ~0.008333s
        var timestamp: CFTimeInterval = 200.0

        for _ in 0..<120 {
            let nextTarget = timestamp + interval
            accumulator.recordFrame(timestamp: timestamp, targetTimestamp: nextTarget, duration: interval)
            timestamp += interval
        }

        let summaryValue = try #require(accumulator.computeSummary())

        #expect(summaryValue.totalSamples == 119)
        #expect(abs(summaryValue.callbackFPS - 120.0) < 0.5)
        #expect(abs(summaryValue.averageFrameMs - 8.333) < 0.2)
        #expect(abs(summaryValue.p95GapMs - 8.333) < 0.2)
        #expect(abs(summaryValue.maxGapMs - 8.333) < 0.2)
        #expect(summaryValue.slowGapsCount == 0)
    }

    @Test func adaptiveCadenceWithThermalOrPowerThrottling() throws {
        // CADisplayLink dynamically shifts targetTimestamp - timestamp due to ProMotion,
        // thermal mitigation, or low power mode.
        var accumulator = CadenceAccumulator(maxSamples: 100)
        var timestamp: CFTimeInterval = 300.0

        // 30 frames at 120Hz
        let interval120 = 1.0 / 120.0
        for _ in 0..<30 {
            accumulator.recordFrame(
                timestamp: timestamp, targetTimestamp: timestamp + interval120, duration: interval120
            )
            timestamp += interval120
        }

        // 30 frames at 60Hz (system reduced rate)
        let interval60 = 1.0 / 60.0
        for _ in 0..<30 {
            accumulator.recordFrame(
                timestamp: timestamp, targetTimestamp: timestamp + interval60, duration: interval120
            )
            timestamp += interval60
        }

        let summaryValue = try #require(accumulator.computeSummary())

        #expect(summaryValue.totalSamples == 59)
        // Average should be between 60 and 120 FPS
        #expect(summaryValue.callbackFPS > 60.0 && summaryValue.callbackFPS < 120.0)
        // Max gap should correspond to ~16.6ms
        #expect(abs(summaryValue.maxGapMs - 16.666) < 0.5)
        #expect(summaryValue.slowGapsCount == 0)
    }

    @Test func slowGapsDetection() throws {
        var accumulator = CadenceAccumulator(maxSamples: 100)
        let interval: CFTimeInterval = 1.0 / 60.0
        var timestamp: CFTimeInterval = 400.0

        // 10 normal frames
        for _ in 0..<10 {
            accumulator.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + interval, duration: interval)
            timestamp += interval
        }

        // 1 dropped/slow gap (e.g. 55ms pause due to main thread hitch)
        let hitchInterval: CFTimeInterval = 0.055
        timestamp += hitchInterval - interval
        accumulator.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + interval, duration: interval)

        let summaryValue = try #require(accumulator.computeSummary())

        #expect(summaryValue.slowGapsCount == 1)
        #expect(abs(summaryValue.maxGapMs - 55.0) < 0.1)
        #expect(accumulator.totalSlowGaps == 1)
    }

    @Test func boundedSamplesCapacity() throws {
        let capacity = 25
        var accumulator = CadenceAccumulator(maxSamples: capacity)
        let interval: CFTimeInterval = 1.0 / 60.0
        var timestamp: CFTimeInterval = 500.0

        for _ in 0..<100 {
            accumulator.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + interval, duration: interval)
            timestamp += interval
        }

        #expect(accumulator.samples.count == capacity)
        let summary = try #require(accumulator.computeSummary())
        #expect(summary.totalSamples == capacity)
    }

    @Test func baselineResetAvoidsSpuriousGaps() throws {
        var accumulator = CadenceAccumulator(maxSamples: 100)
        let interval: CFTimeInterval = 1.0 / 60.0
        var timestamp: CFTimeInterval = 600.0

        accumulator.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + interval, duration: interval)
        timestamp += interval
        accumulator.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + interval, duration: interval)

        // Simulate app pause or screen transition of 10 seconds
        timestamp += 10.0
        accumulator.resetBaseline()

        // Next frame sets new baseline
        accumulator.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + interval, duration: interval)
        timestamp += interval
        // Following frame calculates gap from new baseline
        accumulator.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + interval, duration: interval)

        let summaryValue = try #require(accumulator.computeSummary())

        // Max gap should still be ~16.6ms, never 10 seconds
        #expect(summaryValue.maxGapMs < 20.0)
        #expect(summaryValue.slowGapsCount == 0)
    }

    // MARK: - Monitor Screen Stack & Lifecycle Ownership

    @Test func screenTokenStackAndDisappearUnwinding() {
        let monitor = FleetPerformanceMonitor(processArguments: [], drivesDisplayLink: false)

        #expect(monitor.activeScreen == "Unknown")

        // User navigates: Fleet -> Miner -> Settings
        let tokenFleet = monitor.claimScreen("Fleet")
        #expect(monitor.activeScreen == "Fleet")

        let tokenMiner = monitor.claimScreen("Miner")
        #expect(monitor.activeScreen == "Miner")

        let tokenSettings = monitor.claimScreen("Settings")
        #expect(monitor.activeScreen == "Settings")

        // Pop Settings: back to Miner
        monitor.releaseScreen(tokenSettings)
        #expect(monitor.activeScreen == "Miner")

        // Pop Miner: back to Fleet
        monitor.releaseScreen(tokenMiner)
        #expect(monitor.activeScreen == "Fleet")

        // Pop Fleet: back to Unknown
        monitor.releaseScreen(tokenFleet)
        #expect(monitor.activeScreen == "Unknown")
    }

    @Test func stackedScreensWithIdenticalLabelsMaintainUniqueTokens() {
        let monitor = FleetPerformanceMonitor(processArguments: [], drivesDisplayLink: false)

        let token1 = monitor.claimScreen("Fleet")
        let token2 = monitor.claimScreen("Fleet")

        #expect(token1.id != token2.id)
        #expect(monitor.activeScreen == "Fleet")

        // Release top instance
        monitor.releaseScreen(token2)
        #expect(monitor.activeScreen == "Fleet")

        // Release first instance
        monitor.releaseScreen(token1)
        #expect(monitor.activeScreen == "Unknown")
    }

    // MARK: - Launch Arguments and State

    @Test func launchArgumentDetection() {
        let monitorOff = FleetPerformanceMonitor(processArguments: ["--demo"], drivesDisplayLink: false)
        #expect(monitorOff.enabled == false)

        let monitorOn = FleetPerformanceMonitor(
            processArguments: ["--ui-testing", "--frame-pacing"],
            drivesDisplayLink: false
        )
        #expect(monitorOn.enabled == true)
        monitorOn.enabled = false  // Cleanup
    }

    @Test func setActiveLifecycle() {
        let monitor = FleetPerformanceMonitor(processArguments: [], drivesDisplayLink: false)
        monitor.enabled = true

        monitor.setActive(false)
        // While inactive, recordFrame does not crash
        monitor.recordFrame(timestamp: 100.0, targetTimestamp: 100.016, duration: 0.016)

        monitor.setActive(true)
        #expect(monitor.enabled == true)
        monitor.enabled = false
    }

    @Test func resetClearsReportsAndMetrics() {
        let monitor = FleetPerformanceMonitor(processArguments: [], drivesDisplayLink: false)
        monitor.enabled = true
        _ = monitor.claimScreen("Pools")

        // Feed frames to trigger publication
        let interval = 1.0 / 60.0
        var timestamp: CFTimeInterval = 1000.0
        for _ in 0..<70 {
            monitor.recordFrame(timestamp: timestamp, targetTimestamp: timestamp + interval, duration: interval)
            timestamp += interval
        }

        #expect(monitor.screenReports["Pools"] != nil)
        #expect(monitor.displayMetrics != nil)

        monitor.reset()
        #expect(monitor.screenReports.isEmpty)
        #expect(monitor.displayMetrics == nil)
        monitor.enabled = false
    }

    @Test func screenReportStructPropertiesAndEquality() {
        let report = FleetPerformanceMonitor.ScreenReport(
            screen: "Dashboard",
            callbackFPS: 60.0,
            averageFrameMs: 16.6,
            p95GapMs: 17.0,
            maxGapMs: 22.0,
            slowGapsCount: 1,
            totalSamples: 120,
            lastUpdated: 100.0
        )
        #expect(report.id == "Dashboard")
        #expect(report.screen == "Dashboard")
        #expect(report.callbackFPS == 60.0)
        #expect(report.slowGapsCount == 1)
        #expect(report.totalSamples == 120)
    }

    @Test func fleetPerformanceOverlayInitialization() {
        let overlay = FleetPerformanceOverlay()
        _ = overlay
    }
}
