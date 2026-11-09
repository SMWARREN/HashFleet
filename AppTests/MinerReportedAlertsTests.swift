import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension MinerReportedStateTests {
    // MARK: - MinerReportedAlerts Tests

    @Test func alertsNilWhenNoFaultsOrAlertsReported() {
        let info = MinerInfo(raw: [
            "miningPaused": .bool(false),
            "overheat_mode": .integer(0),
            "isUsingFallbackStratum": .integer(0),
            "temp": .number(85.0),
            "ASICModel": .string("BM1366")
        ])
        #expect(MinerReportedAlerts(info: info) == nil)
    }

    @Test func alertsExplicitMiningPausedNotice() throws {
        let info = MinerInfo(raw: [
            "miningPaused": .bool(true)
        ])
        let alerts = try #require(MinerReportedAlerts(info: info))
        #expect(alerts.messages.count == 1)
        #expect(alerts.messages[0].contains("Mining is paused by the miner"))
    }

    @Test func alertsDoesNotInferPauseFromTemperatureOrModel() {
        // Even with extreme temperature or missing fields, pause is NEVER inferred without explicit miningPaused
        let info = MinerInfo(raw: [
            "temp": .number(115.0),
            "ASICModel": .string("BM1370"),
            "hashRate": .number(0)
        ])
        #expect(MinerReportedAlerts(info: info) == nil)
    }

    @Test func alertsOverheatModeReportsThrottlingNotice() throws {
        let info = MinerInfo(raw: [
            "overheat_mode": .integer(1)
        ])
        let alerts = try #require(MinerReportedAlerts(info: info))
        #expect(alerts.messages.count == 1)
        #expect(alerts.messages[0].contains("Overheat protection is active"))
    }

    @Test func alertsPowerAndHardwareFaultMessages() throws {
        let info = MinerInfo(raw: [
            "power_fault": .string("Under-voltage lockout triggered"),
            "hardware_fault": .string("ASIC chain communication timeout")
        ])
        let alerts = try #require(MinerReportedAlerts(info: info))
        #expect(alerts.messages.count == 2)
        #expect(alerts.messages[0] == "Power fault reported: Under-voltage lockout triggered")
        #expect(alerts.messages[1] == "Hardware fault reported: ASIC chain communication timeout")
    }

    @Test func alertsEmptyFaultStringsIgnored() {
        let info = MinerInfo(raw: [
            "power_fault": .string("   \n"),
            "hardware_fault": .null
        ])
        #expect(MinerReportedAlerts(info: info) == nil)
    }

    @Test func alertsFallbackPoolUsesMayResetWording() throws {
        let info = MinerInfo(raw: [
            "isUsingFallbackStratum": .bool(true),
            "fallbackStratumURL": .string("stratum+tcp://backup.pool.com:3333")
        ])
        let alerts = try #require(MinerReportedAlerts(info: info))
        #expect(alerts.messages.count == 1)
        #expect(alerts.messages[0].contains("Mining on the fallback pool (stratum+tcp://backup.pool.com:3333)"))
        #expect(alerts.messages[0].contains("Share statistics may reset when switching pools."))
        #expect(!alerts.messages[0].contains("Share statistics reset when the pool changed."))
    }

    @Test func alertsMultipleActiveAlertsOrderedConsistently() throws {
        let info = MinerInfo(raw: [
            "miningPaused": .integer(1),
            "overheat_mode": .integer(1),
            "power_fault": .string("Voltage drop"),
            "hardware_fault": .string("SPI error"),
            "isUsingFallbackStratum": .integer(1),
            "fallbackStratumURL": .string("stratum+tcp://fallback.com")
        ])
        let alerts = try #require(MinerReportedAlerts(info: info))
        #expect(alerts.messages.count == 5)
        #expect(alerts.messages[0].contains("Mining is paused"))
        #expect(alerts.messages[1].contains("Overheat protection"))
        #expect(alerts.messages[2].contains("Power fault reported: Voltage drop"))
        #expect(alerts.messages[3].contains("Hardware fault reported: SPI error"))
        #expect(alerts.messages[4].contains("Mining on the fallback pool"))
    }

    @Test func minerNoticeSnoozeExpiresAfterFourHours() {
        let suite = "app.hashfleet.notice-snooze-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let deviceID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        MinerNoticeSnoozeStore.snooze(for: deviceID, at: now, defaults: defaults)

        #expect(MinerNoticeSnoozeStore.isSnoozed(for: deviceID, at: now, defaults: defaults))
        #expect(
            MinerNoticeSnoozeStore.isSnoozed(
                for: deviceID,
                at: now.addingTimeInterval(MinerNoticeSnoozeStore.duration - 1),
                defaults: defaults
            )
        )
        #expect(
            !MinerNoticeSnoozeStore.isSnoozed(
                for: deviceID,
                at: now.addingTimeInterval(MinerNoticeSnoozeStore.duration + 1),
                defaults: defaults
            )
        )

        defaults.removePersistentDomain(forName: suite)
    }
}
