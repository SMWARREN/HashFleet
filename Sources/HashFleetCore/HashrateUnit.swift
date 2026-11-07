import Foundation

/// Defines standard hashrate magnitudes and formatting policies for the Hash Fleet.
public enum HashrateUnit: String, Sendable, CaseIterable, Comparable {
    case hashesPerSecond = "H/s"
    case kiloHashesPerSecond = "kH/s"
    case megaHashesPerSecond = "MH/s"
    case gigaHashesPerSecond = "GH/s"
    case teraHashesPerSecond = "TH/s"
    case petaHashesPerSecond = "PH/s"
    case exaHashesPerSecond = "EH/s"

    private var ordinal: Int {
        switch self {
        case .hashesPerSecond: return 0
        case .kiloHashesPerSecond: return 1
        case .megaHashesPerSecond: return 2
        case .gigaHashesPerSecond: return 3
        case .teraHashesPerSecond: return 4
        case .petaHashesPerSecond: return 5
        case .exaHashesPerSecond: return 6
        }
    }

    public static func < (lhs: HashrateUnit, rhs: HashrateUnit) -> Bool {
        return lhs.ordinal < rhs.ordinal
    }

    /// The multiplier required to convert a value from GH/s to this unit.
    public var multiplierFromGHs: Double {
        switch self {
        case .hashesPerSecond: return 1_000_000_000.0
        case .kiloHashesPerSecond: return 1_000_000.0
        case .megaHashesPerSecond: return 1_000.0
        case .gigaHashesPerSecond: return 1.0
        case .teraHashesPerSecond: return 1.0 / 1_000.0
        case .petaHashesPerSecond: return 1.0 / 1_000_000.0
        case .exaHashesPerSecond: return 1.0 / 1_000_000_000.0
        }
    }

    /// The multiplier required to convert a value from H/s to this unit.
    public var multiplierFromHs: Double {
        switch self {
        case .hashesPerSecond: return 1.0
        case .kiloHashesPerSecond: return 1.0 / 1_000.0
        case .megaHashesPerSecond: return 1.0 / 1_000_000.0
        case .gigaHashesPerSecond: return 1.0 / 1_000_000_000.0
        case .teraHashesPerSecond: return 1.0 / 1_000_000_000_000.0
        case .petaHashesPerSecond: return 1.0 / 1_000_000_000_000_000.0
        case .exaHashesPerSecond: return 1.0 / 1_000_000_000_000_000_000.0
        }
    }

    /// Converts a value stored in GH/s to this unit's magnitude.
    public func value(fromGHs ghs: Double) -> Double {
        return ghs * multiplierFromGHs
    }

    /// Converts a value stored in H/s to this unit's magnitude.
    public func value(fromHashesPerSecond hs: Double) -> Double {
        return hs * multiplierFromHs
    }

    /// Formats a value stored in GH/s into a localized numeric string for this unit.
    /// Does not append the unit suffix.
    public func formattedValue(fromGHs ghs: Double) -> String {
        return formatScaleValue(value(fromGHs: ghs))
    }

    /// Formats an already-scaled magnitude value into a localized numeric string for this unit.
    public func formatScaleValue(_ val: Double) -> String {
        guard val.isFinite, val >= 0 else { return "—" }

        let formatStyle = FloatingPointFormatStyle<Double>.number
            .grouping(.automatic)
            .locale(Locale(identifier: "en_US_POSIX"))

        // Exact zero formatting legacy rules
        if val == 0 {
            if self == .gigaHashesPerSecond {
                return "0"
            } else {
                return "0.00"
            }
        }

        // Scientific fallback for enormously large finite numbers or infinitesimally small values
        if val >= 1e15 || (val > 0 && val < 1e-8) {
            return val.formatted(.number.notation(.scientific).locale(Locale(identifier: "en_US_POSIX")))
        }

        // Precision rules
        // MH/GH use 0...2 fraction digits; others use exactly 2
        var precisionDef: FloatingPointFormatStyle<Double>.Configuration.Precision
        switch self {
        case .megaHashesPerSecond, .gigaHashesPerSecond:
            precisionDef = .fractionLength(0...2)
        default:
            precisionDef = .fractionLength(2)
        }

        var formatted = val.formatted(formatStyle.precision(precisionDef))

        // If rounded to zero despite being > 0, expand to scientific notation
        // (This catches values between 1e-8 and whatever threshold normal rounding zeroes out)
        if val > 0 && (formatted == "0" || formatted == "0.0" || formatted == "0.00") {
            formatted = val.formatted(.number.notation(.scientific).locale(Locale(identifier: "en_US_POSIX")))
        }

        return formatted
    }
}
