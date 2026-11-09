import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Parity additions from docs/SWARM-SETTINGS-PARITY.md.
/// Firmware evidence, ESP-Miner 2943d206f6c8a4b249bc74c820fb56c874ac316d:
/// - `main/nvs_config.c`: `minFanSpeed` TYPE_U16 min 0 max 99 default 25;
///   `statsFrequency` TYPE_U16 min 0 max UINT16_MAX.
/// - `main/tasks/fan_controller_task.c`: minimum applies only as the PID output floor in the
///   `autofanspeed` branch; overheat/paused/no-pool/startup use fixed speeds.
/// - `main/tasks/statistics_task.c` and `statistics_task.h`: `0` frees the buffer,
///   `MAX_STATISTICS_COUNT` is 720.
/// - `edit.component.ts`: `STATS_FREQUENCY_STEPS` and its keep-unknown-reported-value behavior.
@Suite("Swarm parity settings payloads")
struct MinerSwarmSettingsTests {
    // MARK: statsFrequency

    @Test func statsFrequencyStepsMatchUpstreamExactly() {
        #expect(MinerTuningDraft.statsFrequencySteps == [0, 1, 2, 5, 10, 30, 60, 120, 360, 840, 1680, 3600])
        #expect(MinerTuningDraft.statsHistorySampleCount == 720)
    }

    @Test func statsFrequencyPayloadCarriesOnlyThatField() throws {
        let payload = try MinerTuningDraft.statsFrequencyPayload(60)
        #expect(payload == .object(["statsFrequency": .integer(60)]))
        #expect(payload["overheat_mode"] == nil)
        #expect(payload["autofanspeed"] == nil)
        #expect(payload["minFanSpeed"] == nil)
        #expect(payload["displayTimeout"] == nil)
        #expect(try MinerTuningDraft.statsFrequencyPayload(0) == .object(["statsFrequency": .integer(0)]))
        #expect(try MinerTuningDraft.statsFrequencyPayload(65_535) == .object(["statsFrequency": .integer(65_535)]))
    }

    @Test func everyUpstreamStepEncodesToItsExactSecondsValue() throws {
        for seconds in MinerTuningDraft.statsFrequencySteps {
            #expect(try MinerTuningDraft.statsFrequencyPayload(seconds)["statsFrequency"] == .integer(Int64(seconds)))
        }
    }

    @Test(arguments: [Int?.none, -1, 65_536, Int.max, Int.min])
    func statsFrequencyRejectsUnselectedOrOutOfRangeValues(_ seconds: Int?) {
        #expect(throws: (any Error).self) { try MinerTuningDraft.statsFrequencyPayload(seconds) }
    }

    @Test func reportedStatsFrequencyIsPreservedInsteadOfSnappedToAStep() {
        #expect(MinerTuningDraft.statsFrequencyOptions(reported: .integer(45)).contains(45))
        #expect(
            MinerTuningDraft.statsFrequencyOptions(reported: .integer(45)) == [
                0, 1, 2, 5, 10, 30, 45, 60, 120, 360, 840, 1680, 3600
            ]
        )
        #expect(
            MinerTuningDraft.statsFrequencyOptions(reported: .integer(60)) == MinerTuningDraft.statsFrequencySteps
        )
        #expect(MinerTuningDraft.statsFrequencyOptions(reported: .number(65_535)).last == 65_535)
    }

    @Test(arguments: [
        JSONValue.null, .bool(true), .string("NaN"), .number(.infinity), .number(.nan),
        .number(45.5), .number(-1), .number(65_536), .array([]), .object([:])
    ])
    func malformedReportedStatsValuesDoNotAddPickerChoices(_ value: JSONValue) {
        #expect(MinerTuningDraft.statsFrequencyOptions(reported: value) == MinerTuningDraft.statsFrequencySteps)
        #expect(MinerTuningDraft.statsFrequencyOptions(reported: nil) == MinerTuningDraft.statsFrequencySteps)
    }

    @Test func statsLabelsDescribeIntervalsWithoutInventingFirmwareBehavior() {
        #expect(MinerTuningDraft.statsFrequencyLabel(0) == "Disabled")
        #expect(MinerTuningDraft.statsFrequencyLabel(1) == "1 second")
        #expect(MinerTuningDraft.statsFrequencyLabel(30) == "30 seconds")
        #expect(MinerTuningDraft.statsFrequencyLabel(60) == "1 minute")
        #expect(MinerTuningDraft.statsFrequencyLabel(3_600) == "1 hour")
        #expect(MinerTuningDraft.statsHistoryLabel(0) == nil)
        #expect(MinerTuningDraft.statsHistoryLabel(65_536) == nil)
        // 720 samples at each interval.
        #expect(MinerTuningDraft.statsHistoryLabel(1) == "12 minutes")
        #expect(MinerTuningDraft.statsHistoryLabel(5) == "1 hour")
        #expect(MinerTuningDraft.statsHistoryLabel(120) == "1 day")
    }

    // MARK: minFanSpeed

    @Test func minimumFanSpeedPayloadCarriesOnlyThatField() throws {
        let payload = try MinerTuningDraft.minimumFanSpeedPayload("25")
        #expect(payload == .object(["minFanSpeed": .integer(25)]))
        #expect(payload["autofanspeed"] == nil)
        #expect(payload["temptarget"] == nil)
        #expect(payload["manualFanSpeed"] == nil)
        #expect(payload["overheat_mode"] == nil)
    }

    @Test(arguments: ["0", "1", "25", "50", "98", "99", " 25 "])
    func minimumFanSpeedAcceptsTheAuditedZeroThroughNinetyNineRange(_ input: String) throws {
        let expected = Int64(input.trimmingCharacters(in: .whitespaces))!
        #expect(try MinerTuningDraft.minimumFanSpeedPayload(input) == .object(["minFanSpeed": .integer(expected)]))
    }

    @Test(arguments: [
        "", " ", "-1", "100", "101", "25.0", "25.5", "NaN", "nan", "inf", "Infinity",
        "1e1", "+25", "25%", "２５", "25,\"overheat_mode\":0", "25\n30",
        String(repeating: "9", count: 30)
    ])
    func minimumFanSpeedRejectsInvalidOrOutOfRangeInput(_ input: String) {
        #expect(throws: (any Error).self) { try MinerTuningDraft.minimumFanSpeedPayload(input) }
    }

    @Test func minimumFanSpeedUpperBoundIsNinetyNineNotOneHundred() throws {
        // manualFanSpeed allows 100; minFanSpeed does not. Do not unify these bounds.
        #expect(throws: (any Error).self) { try MinerTuningDraft.minimumFanSpeedPayload("100") }
        let manual = try MinerTuningDraft.coolingPayload(automatic: false, manualSpeed: "100", target: "60")
        #expect(manual == .object(["autofanspeed": .integer(0), "manualFanSpeed": .integer(100)]))
    }

    @Test func existingCoolingBuilderIsUnchangedAndNeverEmitsAMinimum() throws {
        let automatic = try MinerTuningDraft.coolingPayload(automatic: true, manualSpeed: "80", target: "60")
        #expect(automatic == .object(["autofanspeed": .integer(1), "temptarget": .integer(60)]))
        #expect(automatic["minFanSpeed"] == nil)
        let manual = try MinerTuningDraft.coolingPayload(automatic: false, manualSpeed: "80", target: "60")
        #expect(manual["minFanSpeed"] == nil)
    }

    // MARK: reported-value fidelity

    @Test func reportedCoolingAndStatsValuesSurviveAsDraftsWithoutInventedDefaults() {
        let info = MinerInfo(raw: [
            "minFanSpeed": .integer(35), "statsFrequency": .integer(45),
            "temptarget": .integer(58), "manualFanSpeed": .integer(90)
        ])
        #expect(MinerTuningDraft.integerDraft(from: info.raw["minFanSpeed"]) == "35")
        #expect(MinerTuningDraft.integerDraft(from: info.raw["statsFrequency"]) == "45")
        // No firmware default (25 for minFanSpeed) is fabricated when the field is absent.
        #expect(MinerTuningDraft.integerDraft(from: MinerInfo(raw: [:]).raw["minFanSpeed"]).isEmpty)
    }

    @Test(arguments: [JSONValue.null, .bool(true), .string("NaN"), .number(.infinity), .number(.nan), .number(35.5)])
    func malformedReportedMinimumFanValuesDoNotBecomeDrafts(_ value: JSONValue) {
        #expect(MinerTuningDraft.integerDraft(from: value).isEmpty)
    }

    @Test func payloadsRoundTripThroughJSONEncodingAsIntegers() throws {
        for payload in [
            try MinerTuningDraft.minimumFanSpeedPayload("25"),
            try MinerTuningDraft.statsFrequencyPayload(3_600)
        ] {
            let decoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(payload))
            #expect(decoded == payload)
            let text = try payload.prettyPrinted()
            #expect(!text.contains("."))
            #expect(!text.contains("overheat"))
        }
    }
}
