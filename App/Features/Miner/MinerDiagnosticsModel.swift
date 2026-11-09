import Foundation
import HashFleetCore

/// An individual reason why a pool rejected submitted shares.
public struct ShareRejectionReason: Equatable, Hashable, Sendable {
    public let message: String
    public let count: Int

    public init(message: String, count: Int) {
        self.message = message
        self.count = count
    }
}

/// Pure presentation facade extracting comprehensive diagnostic telemetry from `MinerInfo.raw`.
///
/// Designed according to AxeOS firmware telemetry audits (2026-09-06):
/// - Wire units and meanings are preserved honestly (clocks in MHz, voltages in mV,
///   current in mA, power in W, hashrate in GH/s).
/// - Configured versus measured values are explicitly distinguished.
/// - Sentinels (e.g. -1 for uninitialized/unavailable temperatures) are never rendered
///   as valid measurements or healthy zero.
/// - Fan 2 returning 0 RPM is rendered honestly as 0 RPM rather than claiming missing hardware.
/// - Energy is computed locally as `power * 24 / 1000` (kWh/day) and labeled explicitly
///   as a continuous draw estimate, not an energy meter.
/// - Current telemetry reflects low-voltage DC regulator sensors; mains circuit safety is never derived from it.
/// - Passwords and raw secrets are never parsed or exposed in friendly diagnostics.
public struct MinerDiagnosticsModel: Equatable, Sendable {

    // MARK: - Electrical & Clocks Diagnostics

    public struct ElectricalAndClocks: Equatable, Sendable {
        public let configuredFrequencyMHz: Double?
        public let actualFrequencyMHz: Double?
        public let configuredCoreVoltageMV: Double?
        public let actualCoreVoltageMV: Double?
        public let inputVoltageMV: Double?
        public let nominalVoltageV: Double?
        public let currentMilliamps: Double?
        public let powerWatts: Double?
        public let dailyEnergyEstimateKWh: Double?
        public let efficiencyJoulesPerTerahash: Double?

        public static let mainsCurrentDisclaimer = "Low-voltage regulator telemetry only (not mains current). "
            + "Does not verify AC circuit capacity or electrical safety."
        public static let energyEstimateDisclaimer = "Continuous draw estimate (W × 24h / 1,000). "
            + "Not an actual energy meter or utility billing measurement."
    }

    // MARK: - Thermal & Cooling Diagnostics

    public struct ThermalAndCooling: Equatable, Sendable {
        public let primaryChipTempCelsius: Double?
        public let secondaryChipTempCelsius: Double?
        public let isSecondaryTempAvailable: Bool
        public let vrTempCelsius: Double?
        public let isVRTempAvailable: Bool
        public let fanSpeedPercent: Double?
        public let fan1RPM: Double?
        public let fan2RPM: Double?
        public let isFan2Available: Bool
        public let targetTempCelsius: Double?
        public let minFanSpeedPercent: Double?
    }

    // MARK: - Hashrate & Performance Diagnostics

    public struct HashrateAndPerformance: Equatable, Sendable {
        public let currentHashrateGHs: Double?
        public let hashrate1mGHs: Double?
        public let hashrate10mGHs: Double?
        public let hashrate1hGHs: Double?
        public let expectedHashrateGHs: Double?
        public let asicErrorPercentage: Double?
        public let rejectedSharePercentage: Double?
        public let sharesAccepted: Int?
        public let sharesRejected: Int?
        public let sharesPending: Int?
    }

    // MARK: - Pool & Connection Diagnostics

    public struct PoolAndConnection: Equatable, Sendable {
        public let activeConnectionTitle: String
        public let activeConnectionURL: String
        public let isUsingFallback: Bool?
        public let primaryURL: String?
        public let primaryPort: Int?
        public let primaryProtocol: String?
        public let primaryTLS: Bool?
        public let fallbackURL: String?
        public let fallbackPort: Int?
        public let fallbackProtocol: String?
        public let fallbackTLS: Bool?
        public let responseTimeMs: Double?
        public let responseShareBatch: Int?
        public let poolDifficulty: Double?
        public let bestDiff: String?
        public let bestSessionDiff: String?
        public let poolConnectionInfo: String?
        public let rejectionReasons: [ShareRejectionReason]
    }

    // MARK: - System & Firmware Diagnostics

    public struct SystemAndFirmware: Equatable, Sendable {
        public let sessionUptimeSeconds: Int?
        public let totalUptimeSeconds: Int?
        public let freeHeapBytes: Int?
        public let cpuUsagePercent: Double?
        public let wifiRSSI: Double?
        public let wifiSSID: String?
        public let resetReason: String?
        public let runningPartition: String?
        public let firmwareVersion: String?
        public let axeOSVersion: String?
        public let boardVersion: String?
    }

    // MARK: - Top-level properties

    public let electrical: ElectricalAndClocks
    public let thermal: ThermalAndCooling
    public let hashrate: HashrateAndPerformance
    public let pool: PoolAndConnection
    public let system: SystemAndFirmware

    // MARK: - Initializers

    public init(info: MinerInfo) {
        self.init(raw: info.raw)
    }

    public init(raw: [String: JSONValue]) {
        let currentHash = Self.parsePositiveDouble(raw, keys: "hashRate", "hashrate")
        self.electrical = Self.parseElectrical(raw: raw, currentHashrateGHs: currentHash)
        self.thermal = Self.parseThermal(raw: raw)
        self.hashrate = Self.parseHashrate(raw: raw, currentHashrateGHs: currentHash)
        self.pool = Self.parsePool(raw: raw)
        self.system = Self.parseSystem(raw: raw)
    }

    // MARK: - Calculation Helpers

    /// Computes local 24-hour energy consumption estimate: `(powerWatts / 1000.0) * 24.0` (kWh/day).
    /// Avoids overflow by scaling to kW first, checks finiteness.
    public static func computeDailyEnergyKWh(powerWatts: Double?) -> Double? {
        guard let powerWatts, powerWatts.isFinite, powerWatts >= 0 else { return nil }
        let kw = powerWatts / 1_000.0
        let kwh = kw * 24.0
        return kwh.isFinite ? kwh : nil
    }
}
