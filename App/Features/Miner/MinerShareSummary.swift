import Foundation
import HashFleetCore

/// Pure presentation data for the accepted/rejected share statistics shown for one miner.
///
/// Share counters are read from the raw Info payload so a missing field remains missing rather
/// than becoming MinerInfo's convenience fallback of zero. `errorPercentage` is the firmware's
/// reported ASIC error percentage. It is intentionally kept separate from the calculated rejected
/// share percentage because rejected shares are not hardware errors.
struct MinerShareSummary: Equatable, Sendable {
    struct Metric: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let value: String
    }

    let sharesAccepted: Int?
    let sharesRejected: Int?
    let rejectedSharePercentage: Double?
    let firmwareErrorPercentage: Double?

    init(info: MinerInfo) {
        self.init(raw: info.raw)
    }

    init(raw: [String: JSONValue]) {
        let accepted = Self.parseNonNegativeInteger(raw["sharesAccepted"])
        let rejected = Self.parseNonNegativeInteger(raw["sharesRejected"])

        self.sharesAccepted = accepted
        self.sharesRejected = rejected
        self.rejectedSharePercentage = Self.rejectedPercentage(accepted: accepted, rejected: rejected)
        self.firmwareErrorPercentage = Self.parsePercentage(raw["errorPercentage"])
    }

    /// Rows intended for a compact detail-screen presentation. Firmware errors are included only
    /// when the firmware explicitly reports a valid `errorPercentage` field.
    var metrics: [Metric] {
        var result = [
            Metric(id: "accepted", title: "Accepted", value: acceptedDisplay),
            Metric(id: "rejected", title: "Rejected", value: rejectedDisplay),
            Metric(id: "rejectedPercentage", title: "Rejected share rate", value: rejectedSharePercentageDisplay)
        ]
        if let firmwareErrorPercentageDisplay {
            result.append(
                Metric(id: "firmwareErrors", title: "Firmware errors", value: firmwareErrorPercentageDisplay)
            )
        }
        return result
    }

    var acceptedDisplay: String {
        sharesAccepted.map(Self.formatInteger) ?? "Not reported"
    }

    var rejectedDisplay: String {
        sharesRejected.map(Self.formatInteger) ?? "Not reported"
    }

    /// Displays `No shares yet` only when both counters were explicitly reported as zero.
    var rejectedSharePercentageDisplay: String {
        if sharesAccepted == 0, sharesRejected == 0 {
            return "No shares yet"
        }
        return rejectedSharePercentage.map(Self.formatPercentage) ?? "Not reported"
    }

    /// Nil means the firmware did not report a valid `errorPercentage`, so the row should be omitted.
    var firmwareErrorPercentageDisplay: String? {
        firmwareErrorPercentage.map(Self.formatPercentage)
    }

    private static func parseNonNegativeInteger(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }

        let parsed: Int?
        switch value {
        case .integer(let raw):
            parsed = Int(exactly: raw)
        case .unsignedInteger(let raw):
            parsed = Int(exactly: raw)
        case .number(let raw):
            guard raw.isFinite, raw >= 0, raw.rounded(.towardZero) == raw else { return nil }
            parsed = Int(exactly: raw)
        case .string(let raw):
            parsed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        case .array, .bool, .null, .object:
            return nil
        }

        guard let parsed, parsed >= 0 else { return nil }
        return parsed
    }

    private static func parsePercentage(_ value: JSONValue?) -> Double? {
        guard let value, let parsed = value.doubleValue,
            parsed.isFinite, parsed >= 0, parsed <= 100
        else {
            return nil
        }
        return parsed
    }

    private static func rejectedPercentage(accepted: Int?, rejected: Int?) -> Double? {
        guard let accepted, let rejected else { return nil }
        let (total, overflow) = accepted.addingReportingOverflow(rejected)
        guard !overflow, total > 0 else { return nil }

        let percentage = Double(rejected) / Double(total) * 100
        guard percentage.isFinite, percentage >= 0, percentage <= 100 else { return nil }
        return percentage
    }

    private static func formatInteger(_ value: Int) -> String {
        value.formatted()
    }

    private static func formatPercentage(_ value: Double) -> String {
        guard value > 0, value < 0.01 else {
            return "\(value.formatted(.number.precision(.fractionLength(2))))%"
        }
        return "<0.01%"
    }
}
