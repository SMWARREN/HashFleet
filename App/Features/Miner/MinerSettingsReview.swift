import SwiftUI
import HashFleetCore

struct MinerSettingsReview: Identifiable, Hashable {
    struct Change: Hashable {
        let key: String
        let title: String
        let previousValue: String
        let value: String
    }

    let id = UUID()
    let payload: JSONValue
    let changes: [Change]

    var message: String {
        let lines = changes.map {
            "• \($0.title): \($0.previousValue) → \($0.value)"
        }.joined(separator: "\n")
        return "Hash Fleet will prepare one reviewed settings change:"
            + "\n\(lines)\n\n"
            + "Nothing is sent while you edit. Review the exact request"
            + " before confirming the change."
    }

    init(
        original: MinerInfo?,
        hostname: String,
        statsFrequency: Int?,
        autoFan: Bool,
        temperatureTarget: String
    ) throws {
        var fields: [String: JSONValue] = [:]
        var changes: [Change] = []
        let originalRaw = original?.raw ?? [:]

        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHostname.isEmpty, trimmedHostname != original?.hostname {
            guard trimmedHostname.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil else {
                throw MinerTuningError.invalidInput("Device name may contain only letters, digits and hyphens.")
            }
            fields["hostname"] = .string(trimmedHostname)
            changes.append(
                Change(
                    key: "hostname",
                    title: "Device name",
                    previousValue: original.map { $0.hostname.isEmpty ? "Not reported" : $0.hostname }
                        ?? "Not reported",
                    value: trimmedHostname
                )
            )
        }

        if let statsFrequency,
            (0...65_535).contains(statsFrequency),
            originalRaw["statsFrequency"]?.intValue != statsFrequency {
            fields["statsFrequency"] = .integer(Int64(statsFrequency))
            changes.append(
                Change(
                    key: "statsFrequency",
                    title: "On-device history",
                    previousValue: originalRaw["statsFrequency"]?.intValue
                        .map { MinerTuningDraft.statsFrequencyLabel($0) } ?? "Not reported",
                    value: MinerTuningDraft.statsFrequencyLabel(statsFrequency)
                )
            )
        }

        let originalAutoFan = originalRaw["autofanspeed"]?.boolValue ?? true
        if autoFan != originalAutoFan {
            fields["autofanspeed"] = .integer(autoFan ? 1 : 0)
            changes.append(
                Change(
                    key: "autofanspeed",
                    title: "Automatic fan control",
                    previousValue: originalRaw["autofanspeed"]?.boolValue
                        .map { $0 ? "On" : "Off" } ?? "Not reported",
                    value: autoFan ? "On" : "Off"
                )
            )
        }

        if autoFan, !temperatureTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let target = try MinerTuningDraft.integer(temperatureTarget, name: "Temperature target", bounds: 35...66)
            if originalRaw["temptarget"]?.intValue != target {
                fields["temptarget"] = .integer(Int64(target))
                changes.append(
                    Change(
                        key: "temptarget",
                        title: "Temperature target",
                        previousValue: originalRaw["temptarget"]?.intValue
                            .map { "\($0) °C" } ?? "Not reported",
                        value: "\(target) °C"
                    )
                )
            }
        }

        guard !fields.isEmpty else {
            throw MinerTuningError.invalidInput("No changes yet. Adjust a value before reviewing.")
        }
        self.payload = .object(fields)
        self.changes = changes
    }
}
