import Foundation
import Testing
@testable import HashFleet

@Suite("Miner tuning draft boundary invariants")
struct MinerTuningDraftBoundaryTests {
    @Test func dirtyStagingSurvivesWhenTelemetryUpdatesWithIdenticalValues() {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 600, configuredVoltage: 1100, reference: nil)

        state.editFrequency(610)
        #expect(state.hasChanges)
        #expect(state.frequencyEdited)

        let payloadBefore = state.payload
        state.observe(configuredFrequency: 600, configuredVoltage: 1100, reference: nil)
        #expect(state.hasChanges)
        #expect(state.payload == payloadBefore)
        #expect(state.frequency == 610)
    }

    @Test func dirtyStagingClearedByRestoreEvenWhenTelemetryIsIdentical() {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 600, configuredVoltage: 1100, reference: nil)
        state.editFrequency(610)

        state.restore(configuredFrequency: 600, configuredVoltage: 1100, reference: nil)
        #expect(!state.hasChanges)
        #expect(state.payload == nil)
        #expect(state.frequency == 600)
    }

    @Test func restoreMaintainsValidBaselinesWhenTelemetryIsMissing() {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 600, configuredVoltage: 1100, reference: nil)
        state.editFrequency(610)

        state.restore(configuredFrequency: nil, configuredVoltage: nil, reference: nil)
        #expect(!state.hasChanges)
        #expect(state.frequency == nil)
        #expect(state.frequencyBaseline == nil)
    }

    @Test func editingToBaselineExactlyClearsDirtyFlag() {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 600, configuredVoltage: 1100, reference: nil)

        state.editFrequency(610)
        #expect(state.frequencyEdited)

        state.editFrequency(600)
        #expect(!state.frequencyEdited)
        #expect(!state.hasChanges)
        #expect(state.payload == nil)
    }

    @Test func floatPrecisionEdgeCasesInEditingAndRestore() {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 600.001, configuredVoltage: 1100, reference: nil)

        state.editFrequency(600.005)
        #expect(!state.frequencyEdited)

        state.editFrequency(600.02)
        #expect(state.frequencyEdited)
    }

    @Test func editFrequencyAndVoltageBoundsCheckDoesNotCrashOrCorruptState() {
        var state = MinerTuningSetpointState()
        state.observe(configuredFrequency: 600, configuredVoltage: 1100, reference: nil)

        let beforeState = state
        state.editFrequency(-1)
        state.editVoltage(.infinity)
        state.editFrequency(.nan)
        state.editVoltage(-500)
        state.editFrequency(65536) // Above wire bound

        #expect(state == beforeState)
        #expect(!state.hasChanges)

        for value in [1.0, 600.25, 65_535] {
            #expect(MinerTuningSessionMath.validFrequency(value) == value)
        }
        let invalidFrequencies: [Double?] = [nil, .nan, .infinity, -Double.infinity, -1, 0, 0.999, 65_536, .greatestFiniteMagnitude]
        for value in invalidFrequencies {
            #expect(MinerTuningSessionMath.validFrequency(value) == nil)
        }

        for value in [1.0, 1_100, 65_535] {
            #expect(MinerTuningSessionMath.validVoltage(value) == value)
        }
        let invalidVoltages: [Double?] = [nil, .nan, .infinity, -Double.infinity, -1, 0, 1_100.5, 65_536, .greatestFiniteMagnitude]
        for value in invalidVoltages {
            #expect(MinerTuningSessionMath.validVoltage(value) == nil)
        }

        for value in [Double.leastNonzeroMagnitude, 1_100.5, 65_536, .greatestFiniteMagnitude] {
            #expect(MinerTuningSessionMath.validMeasuredVoltage(value) == value)
        }
        let invalidMeasuredVoltages: [Double?] = [nil, .nan, .infinity, -Double.infinity, -1, 0]
        for value in invalidMeasuredVoltages {
            #expect(MinerTuningSessionMath.validMeasuredVoltage(value) == nil)
        }
    }
}
