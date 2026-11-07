import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Miner tuning payloads")
struct MinerTuningTests {
    @Test func reportedConfiguredValuesPopulateUnselectedDrafts() {
        let info = MinerInfo(raw: [
            "frequency": .number(525.5), "actualFrequency": .number(524.2),
            "coreVoltage": .number(1200), "coreVoltageActual": .number(1190),
            "autofanspeed": .integer(1), "manualFanSpeed": .integer(72),
            "temptarget": .integer(58), "minFanSpeed": .integer(30),
            "overheat_mode": .integer(1), "overclockEnabled": .integer(1)
        ])
        let draft = MinerTuningDraft(info: info)
        #expect(draft.frequency == "525.5")
        #expect(draft.coreVoltage == "1200")
        #expect(draft.automaticFan)
        #expect(draft.manualFanSpeed == "72")
        #expect(draft.temperatureTarget == "58")
        #expect(draft.minimumFanSpeed == "30")
        #expect(!draft.includeFrequency)
        #expect(!draft.includeCoreVoltage)
    }

    @Test func missingValuesAreNotFabricatedFromMeasurementsOrDefaults() {
        let draft = MinerTuningDraft(
            info: MinerInfo(raw: [
                "actualFrequency": .number(500), "coreVoltageActual": .number(1200),
                "defaultFrequency": .number(450), "defaultVoltage": .number(1100)
            ])
        )
        #expect(draft.frequency.isEmpty)
        #expect(draft.coreVoltage.isEmpty)
        #expect(MinerTuningDraft().frequency.isEmpty)
    }

    @Test(arguments: [JSONValue.null, .bool(true), .string("NaN"), .number(.infinity), .number(-1), .number(65_536)])
    func malformedReportedValuesDoNotBecomeDrafts(_ value: JSONValue) {
        let draft = MinerTuningDraft(info: MinerInfo(raw: ["frequency": value, "coreVoltage": value]))
        #expect(draft.frequency.isEmpty)
        #expect(draft.coreVoltage.isEmpty)
    }

    @Test func riskAcknowledgementAndAnExplicitSelectionAreRequired() {
        var draft = MinerTuningDraft()
        draft.frequency = "500"
        draft.includeFrequency = true
        #expect(throws: MinerTuningError.riskAcknowledgementRequired) {
            try draft.payload(riskAcknowledged: false)
        }
        draft.includeFrequency = false
        #expect(throws: MinerTuningError.noFieldsSelected) {
            try draft.payload(riskAcknowledged: true)
        }
    }

    @Test func integerTelemetryDraftsNeverSilentlyTruncateOrInventDefaults() {
        #expect(MinerTuningDraft.integerDraft(from: .number(80)) == "80")
        #expect(MinerTuningDraft.integerDraft(from: .string("60.0")) == "60")
        #expect(MinerTuningDraft.integerDraft(from: .integer(-1)) == "-1")
        #expect(MinerTuningDraft.integerDraft(from: .number(60.5)).isEmpty)
        #expect(MinerTuningDraft.integerDraft(from: .number(.infinity)).isEmpty)
        #expect(MinerTuningDraft.integerDraft(from: .bool(true)).isEmpty)
        #expect(MinerTuningDraft.integerDraft(from: nil).isEmpty)
    }

    @Test func frequencyOnlyOmitsVoltageAndAllProtectionFlags() throws {
        var draft = MinerTuningDraft()
        draft.includeFrequency = true
        draft.frequency = " 525.5 "
        draft.coreVoltage = "invalid unused draft"
        let payload = try draft.payload(riskAcknowledged: true)
        #expect(payload == .object(["frequency": .number(525.5)]))
        #expect(payload["coreVoltage"] == nil)
        #expect(payload["overheat_mode"] == nil)
        #expect(payload["overclockEnabled"] == nil)
        #expect(payload["autofanspeed"] == nil)
    }

    @Test func voltageOnlyOmitsFrequencyAndUsesAnInteger() throws {
        var draft = MinerTuningDraft()
        draft.includeCoreVoltage = true
        draft.coreVoltage = "1200"
        draft.frequency = "NaN"
        #expect(try draft.payload(riskAcknowledged: true) == .object(["coreVoltage": .integer(1200)]))
    }

    @Test func combinedPayloadContainsExactlyTheTwoSelectedFields() throws {
        var draft = MinerTuningDraft()
        draft.includeFrequency = true
        draft.includeCoreVoltage = true
        draft.frequency = "500.25"
        draft.coreVoltage = "1150"
        let payload = try draft.payload(riskAcknowledged: true)
        let fields = try #require(payload.objectValue)
        #expect(Set(fields.keys) == Set(["frequency", "coreVoltage"]))
        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)
        #expect(decoded["frequency"]?.doubleValue == 500.25)
        #expect(decoded["coreVoltage"]?.intValue == 1150)
    }

    @Test func workspacePayloadCombinesClockVoltageAndAutomaticCooling() throws {
        var draft = MinerTuningDraft()
        draft.includeFrequency = true
        draft.frequency = "525.5"
        draft.includeCoreVoltage = true
        draft.coreVoltage = "1100"
        draft.includeCooling = true
        draft.automaticFan = true
        draft.temperatureTarget = "58"
        draft.includeMinimumFanSpeed = true
        draft.minimumFanSpeed = "30"

        let fields = try #require(try draft.payload(riskAcknowledged: true).objectValue)
        #expect(Set(fields.keys) == [
            "frequency", "coreVoltage", "autofanspeed", "temptarget", "minFanSpeed"
        ])
        #expect(fields["autofanspeed"] == .integer(1))
        #expect(fields["temptarget"] == .integer(58))
        #expect(fields["minFanSpeed"] == .integer(30))
    }

    @Test func workspacePayloadCombinesManualFanWithFrequencyWithoutInventingTarget() throws {
        var draft = MinerTuningDraft()
        draft.includeFrequency = true
        draft.frequency = "680"
        draft.includeCooling = true
        draft.automaticFan = false
        draft.manualFanSpeed = "85"
        draft.temperatureTarget = "invalid unused"

        let fields = try #require(try draft.payload(riskAcknowledged: true).objectValue)
        #expect(Set(fields.keys) == ["frequency", "autofanspeed", "manualFanSpeed"])
        #expect(fields["autofanspeed"] == .integer(0))
        #expect(fields["manualFanSpeed"] == .integer(85))
        #expect(fields["temptarget"] == nil)
    }

    @Test func minimumFanRequiresAutomaticFanMode() {
        var draft = MinerTuningDraft()
        draft.includeMinimumFanSpeed = true
        draft.minimumFanSpeed = "30"
        draft.automaticFan = false
        #expect(throws: (any Error).self) { try draft.payload(riskAcknowledged: true) }
    }

    @Test(arguments: [
        "", " ", "NaN", "nan", "inf", "Infinity", "-Infinity", "1e3", "1e309", "+500", "-1", "0", "0.5", "65535.01",
        "65536", "500MHz", "500,5", ".5", "500.", "500\n600", "１２３", "500,\"overheat_mode\":0",
        String(repeating: "9", count: 100)
    ])
    func invalidFrequencyIsRejected(_ input: String) {
        #expect(throws: (any Error).self) { try MinerTuningDraft.frequencyValue(input) }
    }

    @Test(arguments: ["1", "500", "525.5", "65535"])
    func supportedFrequencyEncodingDoesNotInventPhysicalSafeLimits(_ input: String) throws {
        #expect(try MinerTuningDraft.frequencyValue(input) == Double(input))
    }

    @Test(arguments: [
        "", "NaN", "inf", "1e3", "1200.5", "1200.0", "+1200", "-1", "0", "65536", "999999999999999999999999", "1_200",
        "1,200"
    ])
    func invalidCoreVoltageIsRejected(_ input: String) {
        var draft = MinerTuningDraft()
        draft.includeCoreVoltage = true
        draft.coreVoltage = input
        #expect(throws: (any Error).self) { try draft.payload(riskAcknowledged: true) }
    }

    @Test func automaticCoolingIncludesOnlyModeAndTarget() throws {
        let payload = try MinerTuningDraft.coolingPayload(
            automatic: true,
            manualSpeed: "invalid unused",
            target: "60"
        )
        #expect(payload == .object(["autofanspeed": .integer(1), "temptarget": .integer(60)]))
        #expect(payload["manualFanSpeed"] == nil)
        #expect(payload["overheat_mode"] == nil)
    }

    @Test func manualCoolingIncludesOnlyModeAndSpeed() throws {
        let payload = try MinerTuningDraft.coolingPayload(
            automatic: false,
            manualSpeed: "80",
            target: "invalid unused"
        )
        #expect(payload == .object(["autofanspeed": .integer(0), "manualFanSpeed": .integer(80)]))
        #expect(payload["temptarget"] == nil)
        #expect(payload["overheat_mode"] == nil)
    }

    @Test(arguments: ["34", "67", "0", "100", "60.5", "NaN", "Infinity", ""])
    func thermalTargetUsesAuditedFirmwareBoundsNotIncorrectSchema(_ input: String) {
        #expect(throws: (any Error).self) {
            try MinerTuningDraft.coolingPayload(automatic: true, manualSpeed: "80", target: input)
        }
    }

    @Test(arguments: ["-1", "101", "80.5", "NaN", ""])
    func manualFanRejectsInvalidInput(_ input: String) {
        #expect(throws: (any Error).self) {
            try MinerTuningDraft.coolingPayload(automatic: false, manualSpeed: input, target: "60")
        }
    }

    @Test func tuningSessionUsesReportedChipCountAndFlagsOverReferenceValues() throws {
        let reference = try MinerTuningReference(json: .object([
            "ASICModel": .string("BM1372/BM1373"),
            "asicCount": .integer(2),
            "defaultFrequency": .number(680),
            "frequencyOptions": .array([.number(327), .number(550), .number(680)]),
            "defaultVoltage": .number(1100)
        ]))

        #expect(reference.chipCount == 2)
        #expect(MinerTuningSessionMath.chipCount(reference: reference, info: nil) == 2)
        #expect(MinerTuningSessionMath.referenceMaximum(reference) == 680)
        #expect(!MinerTuningSessionMath.isBeyondReference(680, reference: reference))
        #expect(MinerTuningSessionMath.isBeyondReference(681, reference: reference))
    }

    @Test func tuningSessionFallsBackToAuditedBoardCountAndKeepsOverclickInsideWireBounds() throws {
        let info = MinerInfo(raw: ["boardVersion": .string("1201")])
        #expect(MinerTuningSessionMath.chipCount(reference: nil, info: info) == 2)

        let range = MinerTuningSessionMath.controlRange(
            current: 680,
            reference: try MinerTuningReference(json: .object([
                "defaultFrequency": .number(680),
                "frequencyOptions": .array([.number(327), .number(680)])
            ]))
        )
        #expect(range.lowerBound == 480)
        #expect(range.upperBound == 880)
        #expect(MinerTuningSessionMath.stepped(65_534, by: 10) == 65_535)
        #expect(MinerTuningSessionMath.stepped(1, by: -10) == 1)
    }

    @Test func tuningSessionCoreReadingsMapReportedTelemetryWithoutInventingValues() {
        let readings = MinerTuningSessionMath.coreReadings(
            count: 3,
            primaryTemperature: 54,
            secondaryTemperature: 55.5,
            voltageMillivolts: 1_125
        )

        #expect(readings == [
            MinerTuningCoreReading(number: 1, temperatureCelsius: 54, voltageMillivolts: 1_125),
            MinerTuningCoreReading(number: 2, temperatureCelsius: 55.5, voltageMillivolts: 1_125),
            MinerTuningCoreReading(number: 3, temperatureCelsius: nil, voltageMillivolts: 1_125)
        ])
    }

    @Test func tuningSessionCoreReadingsKeepInvalidAndMissingTelemetryUnknown() {
        let readings = MinerTuningSessionMath.coreReadings(
            count: 2,
            primaryTemperature: -1,
            secondaryTemperature: .infinity,
            voltageMillivolts: nil
        )

        #expect(readings.count == 2)
        #expect(readings.allSatisfy { $0.temperatureCelsius == nil && $0.voltageMillivolts == nil })
        #expect(MinerTuningSessionMath.coreReadings(
            count: 0,
            primaryTemperature: 50,
            secondaryTemperature: 51,
            voltageMillivolts: 1_100
        ).isEmpty)
    }

    @Test func tuningSessionFrequencyPayloadContainsOnlyTheBoardFrequency() throws {
        #expect(
            try MinerTuningSessionMath.frequencyPayload(680.5, riskAcknowledged: true)
                == .object(["frequency": .number(680.5)])
        )
    }

    @Test func tuningSessionFrequencyPayloadRequiresRiskAndWireBounds() {
        #expect(throws: MinerTuningError.riskAcknowledgementRequired) {
            try MinerTuningSessionMath.frequencyPayload(680, riskAcknowledged: false)
        }
        #expect(throws: (any Error).self) {
            try MinerTuningSessionMath.frequencyPayload(0, riskAcknowledged: true)
        }
        #expect(throws: (any Error).self) {
            try MinerTuningSessionMath.frequencyPayload(.infinity, riskAcknowledged: true)
        }
        #expect(throws: (any Error).self) {
            try MinerTuningSessionMath.frequencyPayload(65_536, riskAcknowledged: true)
        }
    }

}

extension MinerTuningTests {
    @Test func tuningSessionCombinedPayloadKeepsOnlySelectedFieldsAndIntegerVoltage() throws {
        let payload = try MinerTuningSessionMath.tuningPayload(
            frequency: 680.5, coreVoltage: 1125, riskAcknowledged: true
        )
        #expect(payload == .object(["frequency": .number(680.5), "coreVoltage": .integer(1125)]))
        guard case .number(680.5) = payload["frequency"],
            case .integer(1125) = payload["coreVoltage"] else {
            Issue.record("Frequency must be a number and voltage must be an integer JSON value.")
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(payload)
        let json = try #require(String(bytes: encoded, encoding: .utf8))
        #expect(json == "{\"coreVoltage\":1125,\"frequency\":680.5}")
    }

    @Test func tuningSessionUnifiedPayloadOmitsUnselectedFields() throws {
        #expect(try MinerTuningSessionMath.tuningPayload(
            frequency: 525.25, coreVoltage: nil, riskAcknowledged: true
        ) == .object(["frequency": .number(525.25)]))
        #expect(try MinerTuningSessionMath.tuningPayload(
            frequency: nil, coreVoltage: 1100, riskAcknowledged: true
        ) == .object(["coreVoltage": .integer(1100)]))
    }

    @Test func tuningSessionUnifiedPayloadRequiresSelectionAndAcknowledgement() {
        for acknowledged in [false, true] {
            #expect(throws: MinerTuningError.noFieldsSelected) {
                try MinerTuningSessionMath.tuningPayload(
                    frequency: nil, coreVoltage: nil, riskAcknowledged: acknowledged
                )
            }
        }
        for (frequency, voltage): (Double?, Double?) in [(680, 1100), (680, nil), (nil, 1100)] {
            #expect(throws: MinerTuningError.riskAcknowledgementRequired) {
                try MinerTuningSessionMath.tuningPayload(
                    frequency: frequency, coreVoltage: voltage, riskAcknowledged: false
                )
            }
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, 0, -1, 65_536, 1125.5, .greatestFiniteMagnitude])
    func tuningSessionUnifiedPayloadRejectsInvalidVoltage(_ voltage: Double) {
        do {
            _ = try MinerTuningSessionMath.tuningPayload(
                frequency: 680, coreVoltage: voltage, riskAcknowledged: true
            )
            Issue.record("Invalid voltage was accepted: \(voltage)")
        } catch MinerTuningError.invalidInput {
            // Expected shared draft validation, not a conversion trap or another error.
        } catch {
            Issue.record("Expected invalidInput, received \(error)")
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, 0, -1, 65_536, .greatestFiniteMagnitude])
    func tuningSessionUnifiedPayloadRejectsInvalidFrequency(_ frequency: Double) {
        do {
            _ = try MinerTuningSessionMath.tuningPayload(
                frequency: frequency, coreVoltage: 1100, riskAcknowledged: true
            )
            Issue.record("Invalid frequency was accepted: \(frequency)")
        } catch MinerTuningError.invalidInput {
            // Expected shared draft validation.
        } catch {
            Issue.record("Expected invalidInput, received \(error)")
        }
    }

    @Test(arguments: [1.0, 65_535.0])
    func tuningSessionUnifiedPayloadAcceptsWireEndpointsWithoutInventingSafeLimits(_ value: Double) throws {
        #expect(try MinerTuningSessionMath.tuningPayload(
            frequency: value, coreVoltage: value, riskAcknowledged: true
        ) == .object(["frequency": .number(value), "coreVoltage": .integer(Int64(value))]))
    }

    @Test func tuningSessionVoltageStepsRoundAndClampOnlyToWireBounds() {
        #expect(MinerTuningSessionMath.wireVoltageBounds == 1.0...65_535.0)
        #expect(MinerTuningSessionMath.steppedVoltage(1100, by: 5) == 1105)
        #expect(MinerTuningSessionMath.steppedVoltage(1100.4, by: 1) == 1101)
        #expect(MinerTuningSessionMath.steppedVoltage(1100.5, by: 1) == 1102)
        #expect(MinerTuningSessionMath.steppedVoltage(1, by: -10) == 1)
        #expect(MinerTuningSessionMath.steppedVoltage(65_534, by: 10) == 65_535)
        #expect(MinerTuningSessionMath.steppedVoltage(1100, by: 1000) == 2100)
    }

    @Test func tuningSessionVoltageRangeWidensForReferenceOptionsAndDefaults() throws {
        #expect(MinerTuningSessionMath.voltageControlRange(current: 1100, reference: nil) == 950...1250)
        let reference = try MinerTuningReference(json: .object([
            "voltageOptions": .array([.number(1500), .number(800), .number(1100)]),
            "defaultVoltage": .number(1600)
        ]))
        #expect(MinerTuningSessionMath.voltageControlRange(current: 1100, reference: reference) == 800...1600)
        let lowerDefault = try MinerTuningReference(json: .object(["defaultVoltage": .number(700)]))
        #expect(MinerTuningSessionMath.voltageControlRange(current: 1100, reference: lowerDefault) == 700...1250)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1, 0, 1, 65_535, 65_536])
    func tuningSessionVoltageRangeIsAlwaysNonemptyAndWithinWireBounds(_ current: Double) {
        let range = MinerTuningSessionMath.voltageControlRange(current: current, reference: nil)
        #expect(range.lowerBound.isFinite)
        #expect(range.upperBound.isFinite)
        #expect(range.lowerBound <= range.upperBound)
        #expect(MinerTuningSessionMath.wireVoltageBounds.contains(range.lowerBound))
        #expect(MinerTuningSessionMath.wireVoltageBounds.contains(range.upperBound))
    }

    @Test func tuningSessionVoltageReferenceMaximumIsAdvisoryAndFallsBackOnlyWithoutOptions() throws {
        let reference = try MinerTuningReference(json: .object([
            "voltageOptions": .array([.number(1000), .number(1150), .number(1100)]),
            "defaultVoltage": .number(1200)
        ]))
        #expect(MinerTuningSessionMath.voltageReferenceMaximum(reference) == 1150)
        #expect(!MinerTuningSessionMath.isVoltageBeyondReference(1150, reference: reference))
        #expect(MinerTuningSessionMath.isVoltageBeyondReference(1151, reference: reference))
        let fallback = try MinerTuningReference(json: .object(["defaultVoltage": .number(1200)]))
        #expect(MinerTuningSessionMath.voltageReferenceMaximum(fallback) == 1200)
        let empty = try MinerTuningReference(json: .object([:]))
        #expect(MinerTuningSessionMath.voltageReferenceMaximum(empty) == nil)
        #expect(MinerTuningSessionMath.voltageReferenceMaximum(nil) == nil)
        #expect(!MinerTuningSessionMath.isVoltageBeyondReference(65_535, reference: nil))
        #expect(try MinerTuningSessionMath.tuningPayload(
            frequency: nil, coreVoltage: 1201, riskAcknowledged: true
        ) == .object(["coreVoltage": .integer(1201)]))
    }

    @Test func tuningSessionChangedFieldsUsesFrequencyToleranceAndExactVoltage() {
        let unchanged = MinerTuningSessionMath.changedFields(
            configuredFrequency: 680, configuredVoltage: 1100, frequency: 680.005, coreVoltage: 1100
        )
        #expect(!unchanged.frequency)
        #expect(!unchanged.coreVoltage)
        let changed = MinerTuningSessionMath.changedFields(
            configuredFrequency: 680, configuredVoltage: 1100, frequency: 680.02, coreVoltage: 1100.001
        )
        #expect(changed.frequency)
        #expect(changed.coreVoltage)
        let boundary = MinerTuningSessionMath.changedFields(
            configuredFrequency: 0, configuredVoltage: 1100, frequency: 0.01, coreVoltage: 1100
        )
        #expect(!boundary.frequency)
        let decreased = MinerTuningSessionMath.changedFields(
            configuredFrequency: 680, configuredVoltage: 1100, frequency: 679.98, coreVoltage: 1099
        )
        #expect(decreased.frequency)
        #expect(decreased.coreVoltage)
    }

    @Test func tuningSessionChangedFieldsTreatsEachMissingConfiguredValueAsChanged() {
        let bothMissing = MinerTuningSessionMath.changedFields(
            configuredFrequency: nil, configuredVoltage: nil, frequency: 680, coreVoltage: 1100
        )
        #expect(bothMissing.frequency)
        #expect(bothMissing.coreVoltage)
        let missingFrequency = MinerTuningSessionMath.changedFields(
            configuredFrequency: nil, configuredVoltage: 1100, frequency: 680, coreVoltage: 1100
        )
        #expect(missingFrequency.frequency)
        #expect(!missingFrequency.coreVoltage)
        let missingVoltage = MinerTuningSessionMath.changedFields(
            configuredFrequency: 680, configuredVoltage: nil, frequency: 680, coreVoltage: 1100
        )
        #expect(!missingVoltage.frequency)
        #expect(missingVoltage.coreVoltage)
    }
}

extension MinerTuningTests {
    @Test func setpointCleanTelemetryUpdatesWithoutStagingWrites() {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 525, configuredVoltage: 1100, reference: nil)
        state.observe(configuredFrequency: 530, configuredVoltage: 1105, reference: nil)
        #expect(state.frequency == 530 && state.frequencyBaseline == 530)
        #expect(state.coreVoltage == 1105 && state.voltageBaseline == 1105)
        #expect(!state.hasChanges && state.payload == nil)
    }

    @Test func setpointDirtyFieldsAndRangeBaselinesSurviveTelemetryAndDefaults() throws {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 525, configuredVoltage: 1100, reference: nil)
        state.editFrequency(535)
        state.editVoltage(1110)
        let before = state
        let reference = try MinerTuningReference(json: .object([
            "defaultFrequency": .number(700), "defaultVoltage": .integer(1200)
        ]))
        state.observe(configuredFrequency: 540, configuredVoltage: 1120, reference: reference)
        #expect(state == before)
        state.observe(configuredFrequency: nil, configuredVoltage: nil, reference: reference)
        #expect(state == before)
        #expect(state.frequencyBaseline == 525 && state.voltageBaseline == 1100)
        #expect(state.payload == .object(["frequency": .number(535), "coreVoltage": .integer(1110)]))
    }

    @Test func setpointTelemetryDriftNeverIncludesUntouchedField() {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 525, configuredVoltage: 1100, reference: nil)
        state.editFrequency(535)
        state.observe(configuredFrequency: 530, configuredVoltage: 1125, reference: nil)
        #expect(state.frequency == 535 && state.frequencyBaseline == 525)
        #expect(state.coreVoltage == 1125 && !state.voltageEdited)
        #expect(state.payload == .object(["frequency": .number(535)]))
        state.restore(configuredFrequency: 530, configuredVoltage: 1125, reference: nil)
        state.editVoltage(1130)
        state.observe(configuredFrequency: 540, configuredVoltage: 1120, reference: nil)
        #expect(state.frequency == 540 && !state.frequencyEdited)
        #expect(state.voltageBaseline == 1125)
        #expect(state.payload == .object(["coreVoltage": .integer(1130)]))
    }

    @Test func setpointMissingFieldsAreIndependentAndUnloadedEditsAreIgnored() {
        var state = MinerTuningSetpointState()
        state.editFrequency(535)
        state.editVoltage(1110)
        #expect(state == MinerTuningSetpointState())
        state.observe(configuredFrequency: 525, configuredVoltage: nil, reference: nil)
        state.editFrequency(535)
        #expect(state.coreVoltage == nil && state.voltageBaseline == nil)
        #expect(state.payload == .object(["frequency": .number(535)]))
        state.restore(configuredFrequency: nil, configuredVoltage: 1100, reference: nil)
        state.editVoltage(1105)
        #expect(state.frequency == nil && state.frequencyBaseline == nil)
        #expect(state.payload == .object(["coreVoltage": .integer(1105)]))
    }

    @Test func setpointDefaultsStayPreviewOnlyUntilTheirOwnExplicitEdit() throws {
        var state = MinerTuningSetpointState()
        let reference = try MinerTuningReference(json: .object([
            "defaultFrequency": .number(500.5), "defaultVoltage": .integer(1100)
        ]))
        state.observe(configuredFrequency: nil, configuredVoltage: nil, reference: reference)
        #expect(state.frequency == 500.5 && state.coreVoltage == 1100)
        #expect(!state.hasChanges && state.payload == nil)
        state.editFrequency(501.5)
        #expect(state.payload == .object(["frequency": .number(501.5)]))
        state.restore(configuredFrequency: nil, configuredVoltage: nil, reference: reference)
        state.editVoltage(1105)
        #expect(state.payload == .object(["coreVoltage": .integer(1105)]))
        state.restore(configuredFrequency: 525, configuredVoltage: 1125, reference: reference)
        #expect(state.frequency == 525 && state.coreVoltage == 1125)
        state.observe(configuredFrequency: .nan, configuredVoltage: .infinity, reference: reference)
        #expect(state.frequency == 500.5 && state.coreVoltage == 1100)
        #expect(!state.hasChanges && state.payload == nil)
    }

    @Test func setpointRestoreAndReturningToBaselineClearAllEdits() {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 525.5, configuredVoltage: 1143, reference: nil)
        state.editFrequency(526.5)
        state.editVoltage(1148)
        state.editFrequency(525.505)
        state.editVoltage(1143)
        #expect(!state.frequencyEdited && !state.voltageEdited && state.payload == nil)
        state.editFrequency(527)
        state.restore(configuredFrequency: 530.5, configuredVoltage: 1145, reference: nil)
        #expect(state.frequency == 530.5 && state.frequencyBaseline == 530.5)
        #expect(state.coreVoltage == 1145 && state.voltageBaseline == 1145)
        #expect(!state.hasChanges && state.payload == nil)
        state.restore(configuredFrequency: nil, configuredVoltage: nil, reference: nil)
        #expect(state == MinerTuningSetpointState())
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, 0, -1, 65_536, .greatestFiniteMagnitude])
    func setpointMalformedTelemetryAndEditsCannotCreatePayloads(_ value: Double) {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: value, configuredVoltage: value, reference: nil)
        #expect(state == MinerTuningSetpointState())
        state.observe(configuredFrequency: 525, configuredVoltage: 1100, reference: nil)
        state.editFrequency(535)
        state.editVoltage(1110)
        let before = state
        state.editFrequency(value)
        state.editVoltage(value)
        #expect(state == before)
    }

    @Test func setpointFractionalVoltageIsNeverLoadedOrRoundedIntoPayload() throws {
        var state = MinerTuningSetpointState()
        let reference = try MinerTuningReference(json: .object(["defaultVoltage": .number(1100.5)]))
        state.observe(configuredFrequency: 525, configuredVoltage: 1125.5, reference: reference)
        #expect(state.coreVoltage == nil && state.voltageBaseline == nil)
        state.observe(configuredFrequency: 525, configuredVoltage: 1143, reference: nil)
        state.editVoltage(1148.5)
        #expect(!state.hasChanges && state.coreVoltage == 1143)
        state.editVoltage(1148)
        let payload = try #require(state.payload)
        let data = try JSONEncoder().encode(payload)
        let json = try #require(String(bytes: data, encoding: .utf8))
        #expect(json == "{\"coreVoltage\":1148}")
    }
}
