import Foundation
import HashFleetCore

/// Drafts contain only explicit user-selected fields. Bounds below are wire/storage constraints,
/// not hardware-safe operating limits. Audited ESP-Miner master nvs_config.c, 2026-09-06:
/// frequency TYPE_FLOAT 1...UINT16_MAX, voltage TYPE_U16 1...UINT16_MAX,
/// target 35...66, fan 0...100, timeout -1...UINT16_MAX. Older firmware may differ.
struct MinerTuningDraft: Equatable, Sendable {
    var frequency = ""
    var coreVoltage = ""
    var manualFanSpeed = ""
    var temperatureTarget = ""
    var minimumFanSpeed = ""
    var automaticFan = true
    var includeFrequency = false
    var includeCoreVoltage = false
    var includeCooling = false
    var includeMinimumFanSpeed = false

    init(info: MinerInfo? = nil) {
        if let value = info?.raw["frequency"], let number = value.doubleValue,
            (1...65_535).contains(number) {
            frequency = Self.numericText(number)
        }
        if let value = info?.raw["coreVoltage"]?.doubleValue,
            let integer = Int(exactly: value), (1...65_535).contains(integer) {
            coreVoltage = String(integer)
        }
        automaticFan = info?.raw["autofanspeed"]?.boolValue ?? true
        manualFanSpeed = Self.integerDraft(from: info?.raw["manualFanSpeed"])
        temperatureTarget = Self.integerDraft(from: info?.raw["temptarget"])
        minimumFanSpeed = Self.integerDraft(from: info?.raw["minFanSpeed"])
    }

    func payload(riskAcknowledged: Bool) throws -> JSONValue {
        guard riskAcknowledged else { throw MinerTuningError.riskAcknowledgementRequired }
        guard includeFrequency || includeCoreVoltage || includeCooling else {
            throw MinerTuningError.noFieldsSelected
        }
        var fields: [String: JSONValue] = [:]
        if includeFrequency {
            let freq = try Self.frequencyValue(frequency)
            fields["frequency"] = .number(freq)
        }
        if includeCoreVoltage {
            let volts = try Self.integer(
                coreVoltage,
                name: "Core voltage",
                bounds: 1...65_535
            )
            fields["coreVoltage"] = .integer(Int64(volts))
        }
        if includeCooling {
            guard case .object(let cooling) = try Self.coolingPayload(
                automatic: automaticFan,
                manualSpeed: manualFanSpeed,
                target: temperatureTarget
            ) else { throw MinerTuningError.invalidInput("Cooling payload could not be prepared.") }
            fields.merge(cooling) { _, new in new }
        }
        if includeCooling, includeMinimumFanSpeed {
            guard automaticFan else {
                throw MinerTuningError.invalidInput("Minimum fan speed applies only when automatic fan control is on.")
            }
            guard case .object(let minimum) = try Self.minimumFanSpeedPayload(minimumFanSpeed) else {
                throw MinerTuningError.invalidInput("Minimum fan payload could not be prepared.")
            }
            fields.merge(minimum) { _, new in new }
        }
        // Never automatically enable custom-clock UI or alter overheat/protection state.
        return .object(fields)
    }

    static func frequencyValue(_ text: String) throws -> Double {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.count <= 64,
            input.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
            let value = Double(input), value.isFinite,
            (1...65_535).contains(value),
            Float(value).isFinite
        else {
            throw MinerTuningError.invalidInput(
                "Frequency requires a finite decimal from 1"
                    + " through 65535 MHz. This is an encoding"
                    + " bound, not a safe operating range."
            )
        }
        return value
    }

    static func coolingPayload(automatic: Bool, manualSpeed: String, target: String) throws -> JSONValue {
        var fields: [String: JSONValue] = ["autofanspeed": .integer(automatic ? 1 : 0)]
        if automatic {
            fields["temptarget"] = .integer(Int64(try integer(target, name: "Temperature target", bounds: 35...66)))
        } else {
            let speed = try integer(
                manualSpeed,
                name: "Manual fan speed",
                bounds: 0...100
            )
            fields["manualFanSpeed"] = .integer(Int64(speed))
        }
        return .object(fields)
    }

    // Automatic-mode minimum fan speed, reviewed on its own so
    // a target-temperature change never silently rewrites the fan
    // floor. Audited ESP-Miner master nvs_config.c, 2026-09-06:
    // `minFanSpeed` TYPE_U16 min 0 max 99 (default 25).
    // fan_controller_task.c applies it only as the PID output
    // floor while `autofanspeed` is on; overheat, paused, no-pool
    // and startup states use their own fixed speeds instead.
    // These are firmware input bounds, not a safe airflow
    // recommendation for any particular board.
    static func minimumFanSpeedPayload(
        _ text: String
    ) throws -> JSONValue {
        let speed = try integer(
            text,
            name: "Minimum fan speed",
            bounds: 0...99
        )
        return .object(["minFanSpeed": .integer(Int64(speed))])
    }

    /// Upstream AxeOS statistics choices, in seconds, from `STATS_FREQUENCY_STEPS` in
    /// `edit.component.ts` at ESP-Miner 2943d206f6c8a4b249bc74c820fb56c874ac316d:
    /// `[0, 1, 2, 5, 10, 30, 60, 60 * 2, 60 * 6, 60 * 14, 60 * 28, 60 * 60]`.
    static let statsFrequencySteps = [0, 1, 2, 5, 10, 30, 60, 120, 360, 840, 1680, 3600]

    /// `MAX_STATISTICS_COUNT` in audited statistics_task.h. The task samples every second and thins the
    /// buffer toward a span of this many samples, so retained history is approximate, not guaranteed.
    static let statsHistorySampleCount = 720

    /// Upstream keeps a device-reported value that is not one of its steps instead of snapping it to a
    /// nearby choice. Mirrored here so an existing configuration is never quietly changed.
    static func statsFrequencyOptions(reported: JSONValue?) -> [Int] {
        guard let number = reported?.doubleValue, let value = Int(exactly: number),
            (0...65_535).contains(value), !statsFrequencySteps.contains(value)
        else {
            return statsFrequencySteps
        }
        return (statsFrequencySteps + [value]).sorted()
    }

    /// Audited nvs_config.c: `statsFrequency` is TYPE_U16 with min 0 and max UINT16_MAX. `0` makes
    /// statistics_task free the buffer and stop logging. This is the miner's own on-device history,
    /// separate from the app's optional realtime reading connection.
    static func statsFrequencyPayload(_ seconds: Int?) throws -> JSONValue {
        guard let seconds, (0...65_535).contains(seconds) else {
            throw MinerTuningError.invalidInput(
                "Choose a statistics interval from 0 through 65535"
                    + " seconds. These are audited firmware input bounds."
            )
        }
        return .object(["statsFrequency": .integer(Int64(seconds))])
    }

    static func statsFrequencyLabel(_ seconds: Int) -> String {
        seconds == 0 ? "Disabled" : durationLabel(seconds)
    }

    /// Approximate span of retained on-device history for a given interval. `nil` when logging is off.
    static func statsHistoryLabel(_ seconds: Int) -> String? {
        guard seconds > 0, seconds <= 65_535 else { return nil }
        return durationLabel(seconds * statsHistorySampleCount)
    }

    static func durationLabel(_ seconds: Int) -> String {
        func unit(_ count: Int, _ name: String) -> String { "\(count) \(name)\(count == 1 ? "" : "s")" }
        if seconds >= 86_400, seconds % 86_400 == 0 { return unit(seconds / 86_400, "day") }
        if seconds >= 3_600, seconds % 3_600 == 0 { return unit(seconds / 3_600, "hour") }
        if seconds >= 60, seconds % 60 == 0 { return unit(seconds / 60, "minute") }
        return unit(seconds, "second")
    }

    static func rotationPayload(_ rotation: Int?) throws -> JSONValue {
        guard let rotation, [0, 90, 180, 270].contains(rotation) else {
            throw MinerTuningError.invalidInput("Choose a screen rotation of 0, 90, 180 or 270 degrees.")
        }
        return .object(["rotation": .integer(Int64(rotation))])
    }

    static func inversionPayload(_ inverted: Bool) -> JSONValue {
        .object(["invertscreen": .integer(inverted ? 1 : 0)])
    }

    static func displayTimeoutPayload(_ text: String) throws -> JSONValue {
        .object(["displayTimeout": .integer(Int64(try integer(text, name: "Display timeout", bounds: -1...65_535)))])
    }

    static func integer(_ text: String, name: String, bounds: ClosedRange<Int>) throws -> Int {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.count <= 20,
            input.range(of: "^-?[0-9]+$", options: .regularExpression) != nil,
            let value = Int(input), bounds.contains(value)
        else {
            throw MinerTuningError.invalidInput(
                "\(name) requires a whole number from"
                    + " \(bounds.lowerBound) through \(bounds.upperBound)."
                    + " These are audited firmware input bounds,"
                    + " not a hardware safety recommendation."
            )
        }
        return value
    }

    static func numericText(_ number: Double) -> String {
        if let integer = Int(exactly: number) { return String(integer) }
        return String(number)
    }

    static func integerDraft(from value: JSONValue?) -> String {
        guard let number = value?.doubleValue, let integer = Int(exactly: number) else { return "" }
        return String(integer)
    }
}

enum MinerTuningError: Error, LocalizedError, Equatable {
    case riskAcknowledgementRequired
    case noFieldsSelected
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .riskAcknowledgementRequired: "Acknowledge the tuning risks before reviewing a change."
        case .noFieldsSelected: "Choose frequency, core voltage, or cooling controls to include in this change."
        case .invalidInput(let message): message
        }
    }
}

/// Only fields genuinely returned by GET /api/system/asic. No inferred min/max or safe presets.
struct MinerTuningReference: Equatable, Sendable {
    let model: String?
    let chipCount: Int?
    let defaultFrequency: Double?
    let defaultVoltage: Double?
    let frequencyOptions: [Double]
    let voltageOptions: [Double]

    init(json: JSONValue) throws {
        guard let object = json.objectValue else {
            throw MinerTuningError.invalidInput("ASIC reference response was not a JSON object.")
        }
        if let value = object["ASICModel"], case .string(let name) = value { model = name } else { model = nil }
        chipCount = Self.reportedCount(object["asicCount"] ?? object["chipCount"])
        defaultFrequency = Self.reportedNumber(object["defaultFrequency"])
        defaultVoltage = Self.reportedNumber(object["defaultVoltage"])
        frequencyOptions = object["frequencyOptions"]?.arrayValue?.compactMap { Self.reportedNumber($0) } ?? []
        voltageOptions = object["voltageOptions"]?.arrayValue?.compactMap { Self.reportedNumber($0) } ?? []
    }

    private static func reportedNumber(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .number, .integer, .unsignedInteger:
            guard let number = value.doubleValue, (1...65_535).contains(number) else { return nil }
            return number
        default: return nil
        }
    }

    private static func reportedCount(_ value: JSONValue?) -> Int? {
        guard let number = value?.doubleValue,
            number.isFinite,
            let count = Int(exactly: number),
            (1...128).contains(count)
        else { return nil }
        return count
    }
}

struct MinerTuningCoreReading: Equatable, Sendable {
    let number: Int
    let temperatureCelsius: Double?
    let voltageMillivolts: Double?
}

/// Separates explicit edits from telemetry changes. Firmware defaults are preview-only until edited.
/// Baselines anchor dial ranges and remain fixed while their field has a staged user edit.
struct MinerTuningSetpointState: Equatable {
    private(set) var frequency: Double?
    private(set) var coreVoltage: Double?
    private(set) var frequencyBaseline: Double?
    private(set) var voltageBaseline: Double?
    private(set) var frequencyEdited = false
    private(set) var voltageEdited = false

    init() { }

    var hasChanges: Bool { frequencyEdited || voltageEdited }

    /// Preview only. The caller must independently enforce risk, freshness and device safety gates.
    var payload: JSONValue? {
        guard hasChanges else { return nil }
        return try? MinerTuningSessionMath.tuningPayload(
            frequency: frequencyEdited ? frequency : nil,
            coreVoltage: voltageEdited ? coreVoltage : nil,
            riskAcknowledged: true
        )
    }

    mutating func observe(
        configuredFrequency: Double?, configuredVoltage: Double?, reference: MinerTuningReference?
    ) {
        if !frequencyEdited {
            frequency = MinerTuningSessionMath.validFrequency(configuredFrequency) ?? MinerTuningSessionMath.validFrequency(reference?.defaultFrequency)
            frequencyBaseline = frequency
        }
        if !voltageEdited {
            coreVoltage = MinerTuningSessionMath.validVoltage(configuredVoltage) ?? MinerTuningSessionMath.validVoltage(reference?.defaultVoltage)
            voltageBaseline = coreVoltage
        }
    }

    mutating func editFrequency(_ value: Double) {
        guard let baseline = frequencyBaseline, let value = MinerTuningSessionMath.validFrequency(value) else { return }
        frequency = value
        frequencyEdited = abs(value - baseline) > 0.01
    }

    mutating func editVoltage(_ value: Double) {
        guard let baseline = voltageBaseline, let value = MinerTuningSessionMath.validVoltage(value) else { return }
        coreVoltage = value
        voltageEdited = value != baseline
    }

    /// Discards local edits and reloads the current baseline without constructing a write.
    mutating func restore(
        configuredFrequency: Double?, configuredVoltage: Double?, reference: MinerTuningReference?
    ) {
        frequencyEdited = false
        voltageEdited = false
        observe(configuredFrequency: configuredFrequency, configuredVoltage: configuredVoltage, reference: reference)
    }
}

/// Presentation math for the session controls. These values deliberately describe the UI span and
/// firmware reference ceiling, not a hardware-safe operating range.
enum MinerTuningSessionMath {
    static let wireFrequencyBounds = 1.0...65_535.0

    /// Firmware wire/storage constraints, not a hardware-safe operating range.
    static let wireVoltageBounds = 1.0...65_535.0

    static func validFrequency(_ value: Double?) -> Double? {
        guard let value, value.isFinite, wireFrequencyBounds.contains(value),
            Float(value).isFinite else { return nil }
        return value
    }

    static func validVoltage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, wireVoltageBounds.contains(value),
            Int(exactly: value) != nil else { return nil }
        return value
    }

    static func validMeasuredVoltage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    static func chipCount(reference: MinerTuningReference?, info: MinerInfo?) -> Int? {
        reference?.chipCount ?? MinerCapabilityPresentation.asicCount(info: info)
    }

    static func coreReadings(
        count: Int,
        primaryTemperature: Double?,
        secondaryTemperature: Double?,
        voltageMillivolts: Double?
    ) -> [MinerTuningCoreReading] {
        guard count > 0 else { return [] }
        let temperatures = [primaryTemperature, secondaryTemperature]
        let voltage = validTelemetry(voltageMillivolts)
        return (1...count).map { number in
            let temperature = number <= temperatures.count
                ? validTelemetry(temperatures[number - 1])
                : nil
            return MinerTuningCoreReading(
                number: number,
                temperatureCelsius: temperature,
                voltageMillivolts: voltage
            )
        }
    }

    static func frequencyPayload(_ frequency: Double, riskAcknowledged: Bool) throws -> JSONValue {
        guard frequency.isFinite, wireFrequencyBounds.contains(frequency) else {
            throw MinerTuningError.invalidInput("The selected frequency is outside the firmware encoding range.")
        }
        var draft = MinerTuningDraft()
        draft.frequency = MinerTuningDraft.numericText(frequency)
        draft.includeFrequency = true
        return try draft.payload(riskAcknowledged: riskAcknowledged)
    }

    static func referenceMaximum(_ reference: MinerTuningReference?) -> Double? {
        if let maximum = reference?.frequencyOptions.max() { return maximum }
        return reference?.defaultFrequency
    }

    static func isBeyondReference(_ frequency: Double, reference: MinerTuningReference?) -> Bool {
        guard let maximum = referenceMaximum(reference) else { return false }
        return frequency > maximum
    }

    /// Keeps a slider useful around the reported operating point while allowing deliberate
    /// over-reference clicks. The wire bound is still enforced at both ends.
    static func controlRange(current: Double, reference: MinerTuningReference?) -> ClosedRange<Double> {
        let clampedCurrent = min(max(current, wireFrequencyBounds.lowerBound), wireFrequencyBounds.upperBound)
        let referenceMaximum = self.referenceMaximum(reference) ?? clampedCurrent
        let lower = max(wireFrequencyBounds.lowerBound, clampedCurrent - 200)
        let upper = min(
            wireFrequencyBounds.upperBound,
            max(clampedCurrent + 200, referenceMaximum + 200)
        )
        return lower...max(lower, upper)
    }

    static func stepped(_ frequency: Double, by delta: Double) -> Double {
        min(max(frequency + delta, wireFrequencyBounds.lowerBound), wireFrequencyBounds.upperBound)
    }

    static func steppedVoltage(_ mv: Double, by delta: Double) -> Double {
        clampedVoltage(mv + delta).rounded()
    }

    /// Keeps a useful span around the operating point and includes reported reference values.
    /// Clamping is only to wire bounds, never to an inferred hardware-safe range.
    static func voltageControlRange(current: Double, reference: MinerTuningReference?) -> ClosedRange<Double> {
        let clampedCurrent = clampedVoltage(current)
        var lower = clampedCurrent - 150
        var upper = clampedCurrent + 150
        if let minimum = reference?.voltageOptions.min() { lower = min(lower, minimum) }
        if let maximum = reference?.voltageOptions.max() { upper = max(upper, maximum) }
        if let defaultVoltage = reference?.defaultVoltage {
            lower = min(lower, defaultVoltage)
            upper = max(upper, defaultVoltage)
        }
        let clampedLower = clampedVoltage(lower)
        return clampedLower...max(clampedLower, clampedVoltage(upper))
    }

    static func voltageReferenceMaximum(_ reference: MinerTuningReference?) -> Double? {
        reference?.voltageOptions.max() ?? reference?.defaultVoltage
    }

    static func isVoltageBeyondReference(_ mv: Double, reference: MinerTuningReference?) -> Bool {
        guard let maximum = voltageReferenceMaximum(reference) else { return false }
        return mv > maximum
    }

    static func tuningPayload(
        frequency: Double?,
        coreVoltage: Double?,
        riskAcknowledged: Bool
    ) throws -> JSONValue {
        guard frequency != nil || coreVoltage != nil else { throw MinerTuningError.noFieldsSelected }
        var draft = MinerTuningDraft()
        if let frequency {
            draft.frequency = MinerTuningDraft.numericText(frequency)
            draft.includeFrequency = true
        }
        if let coreVoltage {
            // Preserve fractional/non-finite input for shared validation, never round a payload.
            draft.coreVoltage = MinerTuningDraft.numericText(coreVoltage)
            draft.includeCoreVoltage = true
        }
        return try draft.payload(riskAcknowledged: riskAcknowledged)
    }

    static func changedFields(
        configuredFrequency: Double?,
        configuredVoltage: Double?,
        frequency: Double,
        coreVoltage: Double
    ) -> (frequency: Bool, coreVoltage: Bool) {
        (
            frequency: configuredFrequency.map { !(abs($0 - frequency) <= 0.01) } ?? true,
            coreVoltage: configuredVoltage.map { $0 != coreVoltage } ?? true
        )
    }

    private static func clampedVoltage(_ value: Double) -> Double {
        // A malformed operating point must not produce an invalid slider range.
        guard !value.isNaN else { return wireVoltageBounds.lowerBound }
        return min(max(value, wireVoltageBounds.lowerBound), wireVoltageBounds.upperBound)
    }

    private static func validTelemetry(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
