import Foundation

/// Stable presentation primitives shared by the app, widgets, Mac companion, and CLI.
///
/// The formatter intentionally stays in HashFleetCore so each surface uses the same units,
/// missing-value policy, and locale-independent numeric presentation.
public enum FleetFormat: Sendable {
    /// Reads the first finite, non-negative sensor value under the supplied firmware keys.
    public static func sensor(
        _ info: MinerInfo,
        keys: String...,
        allowNegative: Bool = false
    ) -> Double? {
        keys.lazy.compactMap { info.raw[$0]?.doubleValue }
            .first { $0.isFinite && (allowNegative || $0 >= 0) }
    }

    public static func measurement(_ value: Double?, unit: String, decimals: Int = 0) -> String {
        guard let value else { return "Not reported" }
        return "\(number(value, decimals: decimals)) \(unit)"
    }

    /// Selects the best unit scale for a given GH/s value.
    public static func hashrateDisplayUnit(forGHs ghs: Double) -> HashrateUnit {
        guard ghs.isFinite, ghs > 0 else { return .gigaHashesPerSecond }

        var selectedUnit = HashrateUnit.hashesPerSecond
        let units = HashrateUnit.allCases

        for unit in units {
            selectedUnit = unit
            let val = ghs * unit.multiplierFromGHs
            // Max fraction digits is 2 for all units (MH/GH 0...2, others 2)
            let roundingFactor = 100.0
            let roundedVal = (val * roundingFactor).rounded() / roundingFactor

            if roundedVal < 1000.0 {
                break
            }
            if unit == units.last {
                break
            }
        }

        return selectedUnit
    }

    /// Selects the best unit scale for an exact H/s value.
    public static func hashrateDisplayUnit(forHashesPerSecond hs: Double) -> HashrateUnit {
        guard hs.isFinite, hs > 0 else { return .hashesPerSecond }

        var selectedUnit = HashrateUnit.hashesPerSecond
        let units = HashrateUnit.allCases

        for unit in units {
            selectedUnit = unit
            let val = hs * unit.multiplierFromHs
            let roundingFactor = 100.0
            let roundedVal = (val * roundingFactor).rounded() / roundingFactor

            if roundedVal < 1000.0 {
                break
            }
            if unit == units.last {
                break
            }
        }

        return selectedUnit
    }

    /// Formats a value stored in GH/s using an automatically selected scale.
    public static func hashrate(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        let unit = hashrateDisplayUnit(forGHs: value)
        return unit.formattedValue(fromGHs: value)
    }

    public static func hashrateUnit(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "GH/s" }
        return hashrateDisplayUnit(forGHs: value).rawValue
    }

    /// Formats GH/s together with its scaled unit, without attaching a unit to invalid input.
    public static func hashrateWithUnit(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        return "\(hashrate(value)) \(hashrateUnit(value))"
    }

    /// Formats an exact H/s value together with its scaled unit without destructive GH/s normalization.
    public static func hashrateWithUnit(hashesPerSecond: Double) -> String {
        guard hashesPerSecond.isFinite, hashesPerSecond >= 0 else { return "—" }
        let unit = hashrateDisplayUnit(forHashesPerSecond: hashesPerSecond)
        let scaledValue = unit.value(fromHashesPerSecond: hashesPerSecond)
        return "\(unit.formatScaleValue(scaledValue)) \(unit.rawValue)"
    }

    public static func number(_ value: Double, decimals: Int = 0) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(decimals)))
    }

    public static func integer(_ value: Int) -> String {
        value.formatted(
            .number
                .grouping(.automatic)
                .locale(Locale(identifier: "en_US"))
        )
    }

    public static func integer(_ value: Int64) -> String {
        value.formatted(
            .number
                .grouping(.automatic)
                .locale(Locale(identifier: "en_US"))
        )
    }

    /// Block heights are identifiers, so they remain ungrouped and copyable.
    public static func blockHeight(_ value: Int) -> String {
        String(value)
    }
}
