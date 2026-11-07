import Foundation
import Testing
@testable import HashFleetCore

@Suite("Miner difficulty facade tests")
struct MinerDifficultyTests {
    @Test(arguments: [Double(Int64.max), Double(UInt64.max), Double.greatestFiniteMagnitude,
                      Double(Int64.min).nextDown])
    func finiteDifficultyOutsideInt64DoesNotTrap(value: Double) {
        let info = MinerInfo(raw: ["bestDiff": .number(value), "bestSessionDiff": .number(value)])
        #expect(Double(info.bestDiff) == value)
        #expect(Double(info.bestSessionDiff) == value)
    }

    @Test func presentsExactIntegerDifficultyWithoutFloatingPointLoss() {
        let largeInt: Int64 = 9_007_199_254_740_993
        let info = MinerInfo(raw: [
            "bestDiff": .integer(largeInt),
            "bestSessionDiff": .unsignedInteger(18_446_744_073_709_551_615)
        ])
        #expect(info.bestDiff == "9007199254740993")
        #expect(info.bestSessionDiff == "18446744073709551615")
    }

    @Test func presentsStandardIntegerNumbers() {
        let info = MinerInfo(raw: [
            "bestDiff": .integer(123456),
            "bestSessionDiff": .number(5000000)
        ])
        #expect(info.bestDiff == "123456")
        #expect(info.bestSessionDiff == "5000000")
    }

    @Test func preservesHumanReadableFormattedStrings() {
        let info = MinerInfo(raw: [
            "bestDiff": .string("1.25G"),
            "bestSessionDiff": .string(" 3.45M \n")
        ])
        #expect(info.bestDiff == "1.25G")
        #expect(info.bestSessionDiff == "3.45M")
    }

    @Test func formatsFractionalNumbers() {
        let info = MinerInfo(raw: [
            "bestDiff": .number(1234.56),
            "bestSessionDiff": .number(0.125)
        ])
        #expect(info.bestDiff == "1234.56")
        #expect(info.bestSessionDiff == "0.125")
    }

    @Test func rejectsBooleanNullAndNonfiniteValues() {
        let nonfiniteCases: [JSONValue] = [
            .bool(true),
            .bool(false),
            .null,
            .number(.nan),
            .number(.infinity),
            .number(-.infinity),
            .object(["nested": .integer(1)]),
            .array([.integer(1)])
        ]

        for invalid in nonfiniteCases {
            let info = MinerInfo(raw: [
                "bestDiff": invalid,
                "bestSessionDiff": invalid
            ])
            #expect(info.bestDiff == "", "Expected empty string for invalid value: \(invalid)")
            #expect(info.bestSessionDiff == "", "Expected empty string for invalid value: \(invalid)")
        }
    }

    @Test func missingFieldProducesEmptyString() {
        let info = MinerInfo(raw: [:])
        #expect(info.bestDiff == "")
        #expect(info.bestSessionDiff == "")
    }
}
