import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Miner share summary tests")
struct MinerShareSummaryTests {
    @Test func normalCountsIncludeCalculatedRejectedRate() {
        let summary = MinerShareSummary(
            info: MinerInfo(raw: [
                "sharesAccepted": .integer(980),
                "sharesRejected": .integer(20)
            ])
        )

        #expect(summary.sharesAccepted == 980)
        #expect(summary.sharesRejected == 20)
        #expect(summary.rejectedSharePercentage == 2.0)
        #expect(summary.acceptedDisplay == "980")
        #expect(summary.rejectedDisplay == "20")
        #expect(summary.rejectedSharePercentageDisplay == "2.00%")
    }

    @Test func zeroCountsShowNoSharesYetInsteadOfAZeroRate() {
        let summary = MinerShareSummary(raw: [
            "sharesAccepted": .integer(0),
            "sharesRejected": .integer(0)
        ])

        #expect(summary.rejectedSharePercentage == nil)
        #expect(summary.rejectedSharePercentageDisplay == "No shares yet")
        #expect(summary.metrics.map(\.id) == ["accepted", "rejected", "rejectedPercentage"])
    }

    @Test func missingCountKeepsCountMissingAndMakesRateUnavailable() {
        let summary = MinerShareSummary(raw: ["sharesRejected": .integer(4)])

        #expect(summary.sharesAccepted == nil)
        #expect(summary.sharesRejected == 4)
        #expect(summary.rejectedSharePercentage == nil)
        #expect(summary.acceptedDisplay == "Not reported")
        #expect(summary.rejectedSharePercentageDisplay == "Not reported")
    }

    @Test func negativeCountsAreInvalidRatherThanClampedToZero() {
        let summary = MinerShareSummary(raw: [
            "sharesAccepted": .integer(-1),
            "sharesRejected": .integer(2)
        ])

        #expect(summary.sharesAccepted == nil)
        #expect(summary.sharesRejected == 2)
        #expect(summary.rejectedSharePercentage == nil)
    }

    @Test func fractionalShareCountsAreNotAcceptedAsIntegerCounters() {
        let summary = MinerShareSummary(raw: [
            "sharesAccepted": .number(3.5),
            "sharesRejected": .string("2.25")
        ])

        #expect(summary.sharesAccepted == nil)
        #expect(summary.sharesRejected == nil)
        #expect(summary.rejectedSharePercentage == nil)
    }

    @Test func largeExactIntegerCountsRemainExact() {
        let summary = MinerShareSummary(raw: [
            "sharesAccepted": .integer(Int64.max),
            "sharesRejected": .integer(0)
        ])

        #expect(summary.sharesAccepted == Int.max)
        #expect(summary.sharesRejected == 0)
        #expect(summary.rejectedSharePercentage == 0.0)
    }

    @Test func tinyNonzeroRatesAreNotRoundedToDisplayedZero() {
        let summary = MinerShareSummary(raw: [
            "sharesAccepted": .integer(1_000_000),
            "sharesRejected": .integer(1),
            "errorPercentage": .number(0.001)
        ])

        #expect(summary.rejectedSharePercentage != nil)
        #expect(summary.rejectedSharePercentageDisplay == "<0.01%")
        #expect(summary.firmwareErrorPercentageDisplay == "<0.01%")
    }

    @Test func overflowingTotalMakesRateUnavailableButPreservesValidCounts() {
        let summary = MinerShareSummary(raw: [
            "sharesAccepted": .integer(Int64.max),
            "sharesRejected": .integer(Int64.max)
        ])

        #expect(summary.sharesAccepted == Int.max)
        #expect(summary.sharesRejected == Int.max)
        #expect(summary.rejectedSharePercentage == nil)
        #expect(summary.rejectedSharePercentageDisplay == "Not reported")
    }

    @Test func firmwareErrorPercentageIsSeparateFromRejectedShareRate() {
        let summary = MinerShareSummary(raw: [
            "sharesAccepted": .integer(90),
            "sharesRejected": .integer(10),
            "errorPercentage": .number(0.12)
        ])

        #expect(summary.rejectedSharePercentage == 10.0)
        #expect(summary.firmwareErrorPercentage == 0.12)
        #expect(summary.firmwareErrorPercentageDisplay == "0.12%")
        #expect(summary.metrics.last?.id == "firmwareErrors")
        #expect(summary.metrics.last?.title == "Firmware errors")
    }

    @Test(arguments: [
        JSONValue.number(-0.1),
        JSONValue.number(100.1),
        JSONValue.string("101"),
        JSONValue.string("-1"),
        JSONValue.null
    ])
    func invalidFirmwareErrorPercentageIsOmitted(_ value: JSONValue) {
        let summary = MinerShareSummary(raw: ["errorPercentage": value])

        #expect(summary.firmwareErrorPercentage == nil)
        #expect(summary.firmwareErrorPercentageDisplay == nil)
        #expect(summary.metrics.map(\.id) == ["accepted", "rejected", "rejectedPercentage"])
    }

    @Test func rejectedSharesAreNotPresentedAsFirmwareErrors() {
        let summary = MinerShareSummary(raw: [
            "sharesAccepted": .integer(99),
            "sharesRejected": .integer(1),
            "errorPercentage": .number(101)
        ])

        #expect(summary.rejectedSharePercentage == 1.0)
        #expect(summary.firmwareErrorPercentage == nil)
        #expect(summary.metrics.contains(where: { $0.id == "firmwareErrors" }) == false)
    }
}
