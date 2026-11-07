import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Easy tuner draft inputs", .serialized) @MainActor
struct MinerTuningEasyControlsTests {
    @Test func controlModesKeepDistinctStablePickerTagsAndLabels() {
        #expect(MinerTuningControlMode.allCases == [.easy, .advanced])
        #expect(MinerTuningControlMode.allCases.map(\.displayName) == ["Easy", "Advanced"])
        #expect(MinerTuningControlMode(rawValue: "Easy") == .easy)
        #expect(MinerTuningControlMode(rawValue: "Advanced") == .advanced)
        #expect(Set(MinerTuningControlMode.allCases.map(\.systemImage)).count == 2)
        #expect(MinerTuningControlMode.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    @Test func reportedConfiguredAndStagedValuesAreExactDistinctOptions() {
        let options = MinerTuningEasyField.frequency.options(
            reported: [680, 327, 550, 550, .nan, .infinity, -1, 0, 65_536],
            configured: 525.5, staged: 525.501
        )
        #expect(options == [327, 525.5, 525.501, 550, 680])
        #expect(MinerTuningEasyField.frequency.options(reported: [], configured: nil, staged: 600) == [600])
    }

    @Test func voltageOptionsKeepOnlyWholeWireValuesWithoutRounding() {
        #expect(MinerTuningEasyField.voltage.options(
            reported: [1100, 1125.5, 1150, .infinity, -1], configured: 1060, staged: 1100
        ) == [1060, 1100, 1150])
    }

    @Test(arguments: [MinerTuningEasyField.frequency, .voltage])
    func malformedReferencesNeverInventOrRoundAnOption(field: MinerTuningEasyField) {
        #expect(field.options(
            reported: [.nan, .infinity, -.infinity, -1, 0, 65_536, .greatestFiniteMagnitude],
            configured: .nan, staged: .infinity
        ).isEmpty)
    }

    @Test(arguments: [1.0, 1.0.nextUp, 525.5000000000001, 65_535.0.nextDown, 65_535.0])
    func frequencyOptionsRoundTripWithoutSnappingToNearbyValues(value: Double) throws {
        let options = MinerTuningEasyField.frequency.options(
            reported: [value, value], configured: value, staged: value
        )
        #expect(options == [value])
        #expect(try MinerTuningEasyField.frequency.value(from: MinerTuningDraft.numericText(value)) == value)
    }

    @Test(arguments: ["1", "500", "525.5", " 680.25 ", "65535"])
    func customFrequencyUsesTheProductionDraftParser(text: String) throws {
        let value = try MinerTuningEasyField.frequency.value(from: text)
        #expect(value == (try MinerTuningDraft.frequencyValue(text)))
    }

    @Test(arguments: ["", " ", "NaN", "inf", "Infinity", "1e3", "+500", "-1", "0", "65535.01", "65536", "500MHz", "500,5", ".5", "500.", "500\n600", "１２３"])
    func invalidCustomFrequencyIsRejectedWithoutProducingAValue(text: String) {
        #expect(throws: (any Error).self) { try MinerTuningEasyField.frequency.value(from: text) }
    }

    @Test(arguments: ["1", "1060", " 1100 ", "1150", "65535"])
    func customVoltageUsesTheSameIntegerParserAsReview(text: String) throws {
        let value = try MinerTuningEasyField.voltage.value(from: text)
        #expect(value == Double(try MinerTuningDraft.integer(text, name: "Core voltage", bounds: 1...65_535)))
    }

    @Test(arguments: ["", "NaN", "inf", "1e3", "1125.5", "1200.0", "+1200", "-1", "0", "65536", "1_200", "1,200"])
    func invalidCustomVoltageIsRejectedWithoutRounding(text: String) {
        #expect(throws: (any Error).self) { try MinerTuningEasyField.voltage.value(from: text) }
    }

    @Test func easyAndAdvancedEditsShareOneDraftWithoutIncludingUntouchedVoltage() throws {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 550, configuredVoltage: 1060, reference: nil)
        state.editFrequency(try MinerTuningEasyField.frequency.value(from: "585.5"))
        // Advanced uses the same setpoint edit method. No control-mode switch owns another draft.
        state.editFrequency(MinerTuningSessionMath.stepped(try #require(state.frequency), by: 10))
        #expect(state.frequency == 595.5)
        #expect(state.coreVoltage == 1060)
        #expect(state.frequencyEdited)
        #expect(!state.voltageEdited)
    }

    @Test func easyVoltageOnlyDraftSurvivesTelemetryWithoutAddingFrequency() throws {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 550, configuredVoltage: 1060, reference: nil)
        state.editVoltage(try MinerTuningEasyField.voltage.value(from: "1100"))
        state.observe(configuredFrequency: 575, configuredVoltage: 1075, reference: nil)

        #expect(state.frequency == 575)
        #expect(!state.frequencyEdited)
        #expect(state.coreVoltage == 1100)
        #expect(state.voltageBaseline == 1060)
        #expect(state.voltageEdited)
        #expect(state.payload == .object(["coreVoltage": .integer(1100)]))

        state.restore(configuredFrequency: 575, configuredVoltage: 1075, reference: nil)
        #expect(!state.hasChanges)
        #expect(state.payload == nil)
        #expect(state.coreVoltage == 1075)
    }

    @Test(arguments: [MinerTuningEasyField.frequency, .voltage])
    func directFieldsRenderWithoutDropdownsOrStagingButtons(field: MinerTuningEasyField) async throws {
        let value = field == .frequency ? 680.25 : 1100.0
        let rendered = try await FleetViewRenderHarness.render(
            MinerTuningEasyControls(title: field == .frequency ? "Frequency" : "Core voltage",
                field: field, setpoint: .constant(value),
                isBeyondReference: false, isRestricted: false, isEnabled: true,
                accessibilityPrefix: "fixture", valueIdentifier: "fixture.value"),
            width: 320, height: 750
        )
        #expect(rendered.recognizes("Draft:"))
        #expect(rendered.recognizes(field.unit))
        #expect(!rendered.recognizes("Common values"))
        #expect(!rendered.recognizes("Use value"))
    }

    @Test func hardwareRestrictionBadgeTakesPriorityOverReferenceWarning() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            MinerTuningEasyControls(title: "Core voltage", field: .voltage, setpoint: .constant(1155),
                isBeyondReference: true,
                isRestricted: true, isEnabled: true, accessibilityPrefix: "fixture",
                valueIdentifier: "fixture.value"), width: 320, height: 750
        )
        #expect(rendered.visibleText.contains("Device limit"))
        #expect(!rendered.visibleText.contains("Over reference"))
    }

    @Test(arguments: [CGFloat(320), CGFloat(430)])
    func realPhoneTunerStartsWithEasyControlsAndKeepsBothModesVisible(width: CGFloat) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.visibleDevices.first)
        let rendered = try await FleetViewRenderHarness.render(
            MinerTuningSessionView(device: device, store: fixture.store), width: width, height: 1100
        )
        #expect(rendered.visibleText.contains("Easy"))
        #expect(rendered.visibleText.contains("Advanced"))
        #expect(rendered.recognizes("Frequency"))
        #expect(rendered.recognizes("Core voltage"))
        #expect(rendered.recognizes("MHz") && rendered.recognizes("mV"))
        #expect(!rendered.recognizes("Common values") && !rendered.recognizes("Use value"))
        #expect(!rendered.visibleText.contains("Valid range"), "Firmware encoding bounds are not advertised as safe settings")
    }

    @Test func missingCurrentValueIsUnknownInsteadOfAZeroDraft() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            MinerTuningEasyControls(title: "Core voltage", field: .voltage, setpoint: .constant(0),
                isBeyondReference: false,
                isRestricted: false, isEnabled: false, accessibilityPrefix: "fixture",
                valueIdentifier: "fixture.value"), width: 320, height: 650
        )
        #expect(rendered.visibleText.lowercased().contains("not reported"))
        #expect(!rendered.visibleText.contains("0 mV"))
        #expect(!rendered.visibleText.contains("Draft: 0"))
    }
}
