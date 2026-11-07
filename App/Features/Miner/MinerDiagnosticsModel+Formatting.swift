import Foundation
import HashFleetCore

extension MinerDiagnosticsModel {
    // MARK: - Presentation Formatting Helpers

    public static func formatHashrate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "Not reported" }
        return FleetFormat.hashrateWithUnit(value)
    }

    public static func formatFrequency(_ mhz: Double?) -> String {
        guard let mhz, mhz.isFinite, mhz >= 0 else { return "Not reported" }
        return "\(mhz.formatted(.number.precision(.fractionLength(0...1)))) MHz"
    }

    public static func formatMillivolts(_ mv: Double?) -> String {
        guard let mv, mv.isFinite, mv >= 0 else { return "Not reported" }
        return "\(mv.formatted(.number.precision(.fractionLength(0)))) mV"
    }

    public static func formatVolts(_ volts: Double?) -> String {
        guard let volts, volts.isFinite, volts >= 0 else { return "Not reported" }
        return "\(volts.formatted(.number.precision(.fractionLength(1...2)))) V"
    }

    public static func formatMilliamps(_ ma: Double?) -> String {
        guard let ma, ma.isFinite, ma >= 0 else { return "Not reported" }
        return "\(ma.formatted(.number.precision(.fractionLength(0)))) mA"
    }

    public static func formatWatts(_ watts: Double?) -> String {
        guard let watts, watts.isFinite, watts >= 0 else { return "Not reported" }
        return "\(watts.formatted(.number.precision(.fractionLength(1)))) W"
    }

    public static func formatEnergyKWhPerDay(_ kwh: Double?) -> String {
        guard let kwh, kwh.isFinite, kwh >= 0 else { return "Not reported" }
        return "\(kwh.formatted(.number.precision(.fractionLength(2)))) kWh/day"
    }

    public static func formatTemperature(_ temp: Double?) -> String {
        guard let temp, temp.isFinite, temp >= 0 else { return "Not reported" }
        return "\(temp.formatted(.number.precision(.fractionLength(0...1)))) °C"
    }

    public static func formatFanRPM(_ rpm: Double?) -> String {
        guard let rpm, rpm.isFinite, rpm >= 0 else { return "Not reported" }
        if rpm == 0 {
            return "0 RPM (or stopped)"
        }
        return "\(rpm.formatted(.number.precision(.fractionLength(0)))) RPM"
    }

    public static func formatPercentage(_ pct: Double?, decimals: Int = 2) -> String {
        guard let pct, pct.isFinite, pct >= 0 else { return "Not reported" }
        return "\(pct.formatted(.number.precision(.fractionLength(decimals))))%"
    }

    public static func formatDuration(_ seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return "Not reported" }
        return Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }

    public static func formatHeapBytes(_ bytes: Int?) -> String {
        guard let bytes, bytes >= 0 else { return "Not reported" }
        let kb = Double(bytes) / 1024.0
        return "\(kb.formatted(.number.precision(.fractionLength(1)))) KB"
    }

    /// Parses sharesRejectedReasons without fabricating count 1 when absent or coercing 0 to 1.
    static func parseRejectionReasons(_ value: JSONValue?) -> [ShareRejectionReason] {
        guard let value, let items = value.arrayValue else { return [] }
        var result: [ShareRejectionReason] = []
        for item in items {
            switch item {
            case .object(let dict):
                let msg = dict["message"]?.stringValue ?? dict["reason"]?.stringValue ?? "Unknown rejection"
                // Accept genuine count >= 0, do not coerce 0 -> 1
                let count = dict["count"]?.intValue ?? 0
                result.append(ShareRejectionReason(message: msg, count: max(0, count)))
            case .string(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result.append(ShareRejectionReason(message: trimmed, count: 0))
                }
            default:
                break
            }
        }
        return result
    }
}
