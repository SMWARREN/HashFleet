import Foundation
import HashFleetCore

/// The measurements and configured baselines are never replaced by a local edit or confirmation.
struct MinerTuningPreviewDraft {
    enum Field: String, CaseIterable, Identifiable {
        case frequency, coreVoltage
        var id: Self { self }
        var title: String { self == .frequency ? "Frequency" : "Core voltage" }
        var unit: String { self == .frequency ? "MHz" : "mV" }
        var step: Double { self == .frequency ? 1 : 5 }
        private var input: MinerTuningEasyField { self == .frequency ? .frequency : .voltage }

        func value(_ text: String) -> Double? { try? input.value(from: text) }

        func formatted(_ value: Double?) -> String {
            value.map { "\(MinerTuningDraft.numericText($0)) \(unit)" } ?? "Not reported"
        }
    }

    struct Change: Equatable, Identifiable {
        let field: Field
        let old: Double
        let new: Double
        var id: Field { field }
    }

    struct Review: Equatable, Identifiable {
        let id = UUID()
        let changes: [Change]
        let payload: JSONValue
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.changes == rhs.changes && lhs.payload == rhs.payload }
    }

    let configured: [Field: Double]
    private(set) var text: [Field: String] = [:]

    static func configuration(from info: MinerInfo) -> [Field: Double] {
        let frequency = MinerTuningSessionMath.validFrequency(info.raw["frequency"]?.doubleValue)
        // Canaan reports a measured chip average, not a writable core-voltage setpoint.
        let family = info.raw["firmwareFamily"]?.stringValue?.lowercased()
        let voltage = family == "canaan" ? nil : MinerTuningSessionMath.validVoltage(info.raw["coreVoltage"]?.doubleValue)
        return [.frequency: frequency, .coreVoltage: voltage].compactMapValues { $0 }
    }

    init(info: MinerInfo) {
        configured = Self.configuration(from: info)
        reset()
    }

    var fields: [Field] { Field.allCases.filter { configured[$0] != nil } }

    func value(for field: Field) -> Double? { text[field].flatMap(field.value) }
    func next(_ field: Field, direction: Double) -> Double? {
        guard let value = value(for: field) else { return nil }
        let next = value + field.step * direction
        return field.value(MinerTuningDraft.numericText(next))
    }

    mutating func edit(_ field: Field, _ value: String) {
        guard configured[field] != nil else { return }
        text[field] = value
    }

    mutating func reset() { text = configured.mapValues(MinerTuningDraft.numericText) }

    var review: Review? {
        guard fields.allSatisfy({ value(for: $0) != nil }) else { return nil }
        let changes = fields.compactMap { field -> Change? in
            guard let old = configured[field], let new = value(for: field), old != new else { return nil }
            return Change(field: field, old: old, new: new)
        }
        // The draft contains changed fields only. The apply service validates it before transmission.
        guard let payload = try? MinerTuningSessionMath.tuningPayload(
            frequency: changes.first { $0.field == .frequency }?.new,
            coreVoltage: changes.first { $0.field == .coreVoltage }?.new, riskAcknowledged: true
        ) else { return nil }
        return Review(changes: changes, payload: payload)
    }
}

/// Infers neither measurements from setpoints nor setpoints from measurements.
struct MinerTuningPreviewReadings {
    let clock: Double?
    let voltage: Double?
    let hashrate: Double?
    let temperature: Double?

    init(info: MinerInfo) {
        clock = MinerTuningSessionMath.validFrequency(info.raw["actualFrequency"]?.doubleValue)
        voltage = MinerTuningSessionMath.validMeasuredVoltage(info.raw["coreVoltageActual"]?.doubleValue)
        hashrate = FleetFormat.sensor(info, keys: "hashRate", "hashrate")
        temperature = FleetFormat.sensor(info, keys: "temp", allowNegative: true)
    }
}
