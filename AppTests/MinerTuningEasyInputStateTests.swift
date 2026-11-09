import Testing
@testable import HashFleet

struct MinerTuningEasyInputStateTests {
    @Test(arguments: [MinerTuningEasyField.frequency, .voltage])
    func invalidInputCannotCommitAndSurvivesTelemetry(field: MinerTuningEasyField) {
        var input = MinerTuningEasyInputState()
        input.reset(value: 550)
        input.edit("65536", field: field)
        #expect(input.error != nil)
        #expect(input.commit(field: field) == nil)
        input.receive(value: 575, isFocused: false)
        #expect(input.text == "65536")
        #expect(input.error != nil)
        input.reset(value: 575)
        #expect(input.text == "575" && input.error == nil)
    }

    @Test func focusProtectsPartialEntryAndCommitKeepsExactFractionalFrequency() {
        var input = MinerTuningEasyInputState()
        input.reset(value: 550)
        input.edit("612.", field: .frequency)
        input.receive(value: 575, isFocused: true)
        #expect(input.text == "612." && input.error != nil)
        #expect(input.commit(field: .frequency) == nil)
        input.edit("612.5", field: .frequency)
        input.receive(value: 600, isFocused: true)
        #expect(input.text == "612.5")
        #expect(input.commit(field: .frequency) == 612.5)
        #expect(input.error == nil)
        input.receive(value: 622.5, isFocused: false)
        #expect(input.text == "622.5")
    }

    @Test func fractionalVoltageNeverRoundsAndCorrectionNeedsNoExtraStagingAction() {
        var input = MinerTuningEasyInputState()
        input.reset(value: 1100)
        input.edit("1125.5", field: .voltage)
        #expect(input.commit(field: .voltage) == nil)
        input.edit("1125", field: .voltage)
        #expect(input.error == nil)
        #expect(input.commit(field: .voltage) == 1125)
    }

    @Test func emptyInputIsNotZeroAndExplicitResetClearsTheError() {
        var input = MinerTuningEasyInputState()
        input.reset(value: nil)
        #expect(input.text.isEmpty && input.error == nil)
        input.edit("", field: .frequency)
        #expect(input.commit(field: .frequency) == nil)
        #expect(input.error != nil)
        input.reset(value: 500)
        #expect(input.text == "500" && input.error == nil)
    }

    @Test func untouchedFocusDoesNotStageAStaleReadingAndPendingTextSurvivesBlurRace() {
        var input = MinerTuningEasyInputState()
        input.reset(value: 500)
        input.receive(value: 525, isFocused: true)
        #expect(input.text == "500")
        #expect(input.commit(field: .frequency) == nil)
        input.receive(value: 525, isFocused: false)
        #expect(input.text == "525")
        input.edit("612.5", field: .frequency)
        input.receive(value: 550, isFocused: false)
        #expect(input.text == "612.5")
        #expect(input.commit(field: .frequency) == 612.5)
        #expect(input.commit(field: .frequency) == nil)
    }

    @Test func keystrokesDoNotAlterTheNumericDraftUntilCommit() throws {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 500, configuredVoltage: 1150, reference: nil)
        var input = MinerTuningEasyInputState()
        input.reset(value: state.frequency)
        for text in ["", "6", "61", "612", "612.", "612.5"] { input.edit(text, field: .frequency) }
        #expect(state.payload == nil)
        let committedFrequency = input.commit(field: .frequency)
        state.editFrequency(try #require(committedFrequency))
        #expect(state.payload == .object(["frequency": .number(612.5)]))
        #expect(!state.voltageEdited)
    }
}
