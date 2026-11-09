import Testing
import Foundation
import HashFleetCore
@testable import HashFleet

@Suite("Miner diagnostics model tests")
struct MinerDiagnosticsTests {

    // MARK: - Electrical & Clocks Tests

    @Test func electricalClocksDistinguishConfiguredFromMeasuredClocksAndVoltages() {
        let raw: [String: JSONValue] = [
            "frequency": .number(525),
            "actualFrequency": .number(518.5),
            "coreVoltage": .number(1200),
            "coreVoltageActual": .number(1194),
            "voltage": .number(5150),
            "nominalVoltage": .number(5),
            "current": .number(2450),
            "power": .number(12.6),
            "hashRate": .number(450.0)
        ]
        let model = MinerDiagnosticsModel(raw: raw)

        #expect(model.electrical.configuredFrequencyMHz == 525)
        #expect(model.electrical.actualFrequencyMHz == 518.5)
        #expect(model.electrical.configuredCoreVoltageMV == 1200)
        #expect(model.electrical.actualCoreVoltageMV == 1194)
        #expect(model.electrical.inputVoltageMV == 5150)
        #expect(model.electrical.nominalVoltageV == 5)
        #expect(model.electrical.currentMilliamps == 2450)
        #expect(model.electrical.powerWatts == 12.6)

        // Energy estimate: 12.6 * 24 / 1000 = 0.3024 kWh/day
        let energy = model.electrical.dailyEnergyEstimateKWh
        #expect(energy != nil)
        if let energy {
            #expect(abs(energy - 0.3024) < 1e-6)
        }

        // Efficiency: 12.6 / (450 / 1000) = 28 J/TH
        let eff = model.electrical.efficiencyJoulesPerTerahash
        #expect(eff != nil)
        if let eff {
            #expect(abs(eff - 28.0) < 1e-4)
        }
    }

    @Test func energyCalculationReturnsNilForNilZeroOrNegativePower() {
        #expect(MinerDiagnosticsModel.computeDailyEnergyKWh(powerWatts: nil) == nil)
        #expect(MinerDiagnosticsModel.computeDailyEnergyKWh(powerWatts: -5.0) == nil)
        #expect(MinerDiagnosticsModel.computeDailyEnergyKWh(powerWatts: .nan) == nil)
        #expect(MinerDiagnosticsModel.computeDailyEnergyKWh(powerWatts: .infinity) == nil)
        #expect(MinerDiagnosticsModel.computeDailyEnergyKWh(powerWatts: 0) == 0.0)
        #expect(MinerDiagnosticsModel.computeDailyEnergyKWh(powerWatts: 1000) == 24.0)
    }

    // MARK: - Thermal & Fan Sentinel Tests

    @Test func thermalSentinelNegativeOneIsUnavailableNotHealthyZero() {
        let raw: [String: JSONValue] = [
            "temp": .number(-1),
            "temp2": .number(-1),
            "vrTemp": .number(-1),
            "fan2rpm": .number(-1)
        ]
        let model = MinerDiagnosticsModel(raw: raw)

        #expect(model.thermal.primaryChipTempCelsius == nil)
        #expect(model.thermal.secondaryChipTempCelsius == nil)
        #expect(model.thermal.isSecondaryTempAvailable == false)
        #expect(model.thermal.vrTempCelsius == nil)
        #expect(model.thermal.isVRTempAvailable == false)
        #expect(model.thermal.fan2RPM == nil)
        #expect(model.thermal.isFan2Available == false)
    }

    @Test func thermalValidReadingsAreParsedAccurately() {
        let raw: [String: JSONValue] = [
            "temp": .number(58.5),
            "temp2": .number(61.2),
            "vrTemp": .number(48.0),
            "fanspeed": .number(75),
            "fanrpm": .number(4200),
            "fan2rpm": .number(4150),
            "temptarget": .number(65),
            "minFanSpeed": .number(20)
        ]
        let model = MinerDiagnosticsModel(raw: raw)

        #expect(model.thermal.primaryChipTempCelsius == 58.5)
        #expect(model.thermal.secondaryChipTempCelsius == 61.2)
        #expect(model.thermal.isSecondaryTempAvailable == true)
        #expect(model.thermal.vrTempCelsius == 48.0)
        #expect(model.thermal.isVRTempAvailable == true)
        #expect(model.thermal.fanSpeedPercent == 75)
        #expect(model.thermal.fan1RPM == 4200)
        #expect(model.thermal.fan2RPM == 4150)
        #expect(model.thermal.isFan2Available == true)
        #expect(model.thermal.targetTempCelsius == 65)
        #expect(model.thermal.minFanSpeedPercent == 20)
    }

    @Test func fan2ZeroRPMIsRenderedHonestlyRatherThanTreatedAsMissing() {
        // Audit rule: Fan 2 returning 0 means stopped or unpopulated EMC2302 channel, not an absent key.
        let raw: [String: JSONValue] = [
            "fan2rpm": .integer(0)
        ]
        let model = MinerDiagnosticsModel(raw: raw)
        #expect(model.thermal.fan2RPM == 0)
        #expect(model.thermal.isFan2Available == true)
        #expect(MinerDiagnosticsModel.formatFanRPM(model.thermal.fan2RPM) == "0 RPM (or stopped)")
    }

    // MARK: - Stringified & Numeric Tolerant Parsing

    @Test func stringifiedAndIntegerValuesAreParsedSafely() {
        let raw: [String: JSONValue] = [
            "frequency": .string(" 550 "),
            "actualFrequency": .string("548.2"),
            "coreVoltage": .integer(1250),
            "coreVoltageActual": .string("1245"),
            "power": .string("14.5"),
            "temp": .string("62.3"),
            "sharesAccepted": .string("1042"),
            "sharesRejected": .integer(3),
            "bestDiff": .integer(16384),
            "bestSessionDiff": .string("32768")
        ]
        let model = MinerDiagnosticsModel(raw: raw)

        #expect(model.electrical.configuredFrequencyMHz == 550)
        #expect(model.electrical.actualFrequencyMHz == 548.2)
        #expect(model.electrical.configuredCoreVoltageMV == 1250)
        #expect(model.electrical.actualCoreVoltageMV == 1245)
        #expect(model.electrical.powerWatts == 14.5)
        #expect(model.thermal.primaryChipTempCelsius == 62.3)
        #expect(model.hashrate.sharesAccepted == 1042)
        #expect(model.hashrate.sharesRejected == 3)
        #expect(model.pool.bestDiff == "16384")
        #expect(model.pool.bestSessionDiff == "32768")
    }

    // MARK: - Hashrate Averaging Windows & Error Percentage

    @Test func hashrateAveragingWindowsAndAsicErrorRatesAreExtracted() {
        let raw: [String: JSONValue] = [
            "hashRate": .number(480.5),
            "hashRate_1m": .number(475.2),
            "hashRate_10m": .number(460.0),
            "hashRate_1h": .number(455.8),
            "expectedHashrate": .number(500.0),
            "errorPercentage": .number(0.12),
            "sharesAccepted": .integer(980),
            "sharesRejected": .integer(20),
            "sharesPending": .integer(5)
        ]
        let model = MinerDiagnosticsModel(raw: raw)

        #expect(model.hashrate.currentHashrateGHs == 480.5)
        #expect(model.hashrate.hashrate1mGHs == 475.2)
        #expect(model.hashrate.hashrate10mGHs == 460.0)
        #expect(model.hashrate.hashrate1hGHs == 455.8)
        #expect(model.hashrate.expectedHashrateGHs == 500.0)
        #expect(model.hashrate.asicErrorPercentage == 0.12)
        #expect(model.hashrate.sharesAccepted == 980)
        #expect(model.hashrate.sharesRejected == 20)
        #expect(model.hashrate.sharesPending == 5)

        // Rejected share % = 20 / 1000 * 100 = 2.0%
        let rejPct = model.hashrate.rejectedSharePercentage
        #expect(rejPct != nil)
        if let rejPct {
            #expect(abs(rejPct - 2.0) < 1e-4)
        }
    }

    // MARK: - Pool Diagnostics & Rejection Reasons

    @Test func poolDiagnosticsExtractResponseTimeBatchAndRejectionReasons() {
        let reasons: [JSONValue] = [
            .object(["message": .string("Job not found"), "count": .integer(14)]),
            .object(["message": .string("Zero count share"), "count": .integer(0)]),
            .string("Stale share")
        ]
        let raw: [String: JSONValue] = [
            "stratumURL": .string("stratum+tcp://pool.braiins.com:3333"),
            "stratumPort": .integer(3333),
            "stratumProtocol": .string("SV2"),
            "stratumTLS": .bool(true),
            "fallbackStratumURL": .string("stratum+tcp://backup.braiins.com:3333"),
            "fallbackStratumPort": .integer(3333),
            "fallbackStratumProtocol": .string("SV1"),
            "fallbackStratumTLS": .bool(false),
            "isUsingFallbackStratum": .integer(0),
            "responseTime": .number(34.8),
            "responseShareBatch": .integer(4),
            "poolDifficulty": .number(16384),
            "poolConnectionInfo": .string("IPv4"),
            "sharesRejectedReasons": .array(reasons)
        ]
        let model = MinerDiagnosticsModel(raw: raw)

        #expect(model.pool.activeConnectionTitle == "Pool · primary")
        #expect(model.pool.activeConnectionURL == "stratum+tcp://pool.braiins.com:3333")
        #expect(model.pool.primaryPort == 3333)
        #expect(model.pool.primaryProtocol == "SV2")
        #expect(model.pool.primaryTLS == true)
        #expect(model.pool.fallbackURL == "stratum+tcp://backup.braiins.com:3333")
        #expect(model.pool.fallbackProtocol == "SV1")
        #expect(model.pool.fallbackTLS == false)
        #expect(model.pool.responseTimeMs == 34.8)
        #expect(model.pool.responseShareBatch == 4)
        #expect(model.pool.poolDifficulty == 16384)
        #expect(model.pool.poolConnectionInfo == "IPv4")

        // Rejection reasons: genuine 0 is preserved without coercing to 1, missing count is 0
        #expect(model.pool.rejectionReasons.count == 3)
        #expect(model.pool.rejectionReasons[0] == ShareRejectionReason(message: "Job not found", count: 14))
        #expect(model.pool.rejectionReasons[1] == ShareRejectionReason(message: "Zero count share", count: 0))
        #expect(model.pool.rejectionReasons[2] == ShareRejectionReason(message: "Stale share", count: 0))
    }

    @Test func poolSlotsAreResolvedByIDMatchingActivePool() {
        let raw: [String: JSONValue] = [
            "pools": .array([
                .object(["id": .integer(3), "url": .string("stratum+tcp://pool3.com:3333")]),
                .object(["id": .integer(1), "url": .string("stratum+tcp://pool1.com:3333")])
            ]),
            "primaryPoolIndex": .integer(1),
            "secondaryPoolIndex": .integer(3),
            "isUsingFallbackStratum": .integer(1)
        ]
        let model = MinerDiagnosticsModel(raw: raw)
        #expect(model.pool.activeConnectionTitle == "Pool · fallback in use")
        #expect(model.pool.activeConnectionURL == "stratum+tcp://pool3.com:3333")
        #expect(model.pool.primaryURL == "stratum+tcp://pool1.com:3333")
    }

    @Test func poolURLSanitizationStripsAllUserInfoQueryAndFragment() {
        let withFullUserInfo = "stratum+tcp://user123:supersecretpassword@pool.com:3333?diff=16#tag"
        let sanitized = MinerDiagnosticsModel.sanitizeStratumURL(withFullUserInfo)
        #expect(sanitized == "stratum+tcp://pool.com:3333")
        #expect(sanitized?.contains("user123") == false)
        #expect(sanitized?.contains("supersecretpassword") == false)
        #expect(sanitized?.contains("?") == false)
        #expect(sanitized?.contains("#") == false)

        let bareUserHost = "alice:secret@solo.ckpool.org:3333"
        let bareSanitized = MinerDiagnosticsModel.sanitizeStratumURL(bareUserHost)
        #expect(bareSanitized == "solo.ckpool.org:3333")

        let withoutPassword = "stratum+tcp://pool.com:3333"
        #expect(MinerDiagnosticsModel.sanitizeStratumURL(withoutPassword) == withoutPassword)
    }

    @Test func poolConnectionInfoSanitizesSensitiveData() {
        #expect(MinerDiagnosticsModel.sanitizeConnectionInfo("IPv4") == "IPv4")
        #expect(MinerDiagnosticsModel.sanitizeConnectionInfo("TLS v1.3") == "TLS v1.3")
        #expect(MinerDiagnosticsModel.sanitizeConnectionInfo("secret_internal_token_here_with_long_dump") == nil)
    }

}
