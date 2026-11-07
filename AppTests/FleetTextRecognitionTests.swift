import Foundation
import SwiftUI
import Testing

struct FleetTextRecognitionGeometryTests {
    private func line(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 80, _ height: CGFloat = 20) -> FleetOCRLine {
        FleetOCRLine(text: text, bounds: CGRect(x: x, y: y, width: width, height: height))
    }

    private func result(_ words: [FleetOCRLine]) -> FleetRecognizedText {
        FleetRecognizedText(accurate: "", characters: "", lineAccurate: "", words: words,
                            wrappedAccurate: [], wrappedCharacters: [])
    }

    @Test func readingOrderUsesRowsRatherThanTileTraversal() {
        let lines = [line("right bottom", 200, 100), line("left top", 0, 0),
                     line("left bottom", 0, 100), line("right top", 200, 1)]
        #expect(FleetTextRecognition.text(lines) == "left top right top left bottom right bottom")
    }

    @Test func paragraphOrderDoesNotInsertCenteredIconInsideWrappedCopy() {
        let observations = [line("High risk: verify board and image", 30, 0, 300),
                            line("compatibility", 30, 28, 120), line("A", 0, 14, 20)]
        #expect(FleetTextRecognition.paragraphText(observations) == "High risk: verify board and image compatibility A")
        #expect(FleetTextRecognition.text(observations) != FleetTextRecognition.paragraphText(observations))
    }

    @Test func refinementTargetsBoundedNumericAndMixedAlphabetObservations() {
        #expect(FleetTextRecognition.needsLineRefinement("9.20M"))
        #expect(FleetTextRecognition.needsLineRefinement("\u{0421}\u{043E}p\u{0443} SOL address"))
        #expect(FleetTextRecognition.needsLineRefinement(String(repeating: "1", count: 40)))
        #expect(!FleetTextRecognition.needsLineRefinement(String(repeating: "1", count: 41)))
        #expect(!FleetTextRecognition.needsLineRefinement("Copy SOL address"))
        #expect(!FleetTextRecognition.needsLineRefinement("\u{0421}\u{043E}\u{0443}"))
        #expect(!FleetTextRecognition.needsLineRefinement("\u{00B0}C"))
        #expect(!FleetTextRecognition.needsLineRefinement(""))
    }

    @Test func ambiguousLettersAreNeverReplacedWithExpectedCopy() {
        let observed = "\u{0421}\u{043E}p\u{0443} SOL address"
        let recognition = FleetRecognizedText(
            accurate: observed, characters: "opy SOL address", lineAccurate: "",
            words: [], wrappedAccurate: [], wrappedCharacters: [])
        #expect(recognition.contains(observed))
        #expect(!recognition.contains("Copy SOL address"))
    }

    @Test func wrapsJoinOnlyAdjacentAlignedSingleColumnLines() {
        let previous = line("PATCH /api/system/", 10, 0, 180)
        #expect(FleetTextRecognition.wrappedTokens([previous, line("settings", 10, 28)]) == ["PATCH /api/system/settings"])
        #expect(FleetTextRecognition.wrappedTokens([previous, line("settings", 10, 28), line("another column", 230, 28)]).isEmpty)
        #expect(FleetTextRecognition.wrappedTokens([previous, line("settings", 230, 28)]).isEmpty)
        #expect(FleetTextRecognition.wrappedTokens([previous, line("settings", 10, 80)]).isEmpty)
        #expect(FleetTextRecognition.wrappedTokens([previous, line("set tings", 10, 28)]) == ["PATCH /api/system/set tings"])
    }

    @Test func metricRequiresExactWordsAndSameRowWithVisibleGap() {
        let value = line("2.40", 0, 0, 60, 30)
        #expect(result([value, line("TH/s", 68, 10, 40)]).containsMetric(value: "2.40", unit: "TH/s"))
        for invalid in [line("TH/S", 68, 10, 40), line("GH/s", 68, 10, 40), line("TH/s", 60, 10, 40),
                        line("TH/s", 400, 10, 40), line("TH/s", 68, 80, 40), line("TH/s", -60, 10, 40)] {
            #expect(!result([value, invalid]).containsMetric(value: "2.40", unit: "TH/s"))
        }
        #expect(!result([line("2.40TH/s", 0, 0, 110)]).containsMetric(value: "2.40", unit: "TH/s"))
        #expect(!result([line("12.40", 0, 0, 60, 30), line("TH/s", 68, 10, 40)]).containsMetric(value: "2.40", unit: "TH/s"))
        #expect(!result([]).containsMetric(value: "2.40", unit: "TH/s"))
    }
}

@Suite(.serialized) @MainActor
struct FleetTextRecognitionPixelTests {
    @Test(arguments: ["TH/s", "TH/S", "GH/s"])
    func realUnitGlyphsAreNotCaseFoldedOrSubstituted(_ unit: String) async throws {
        let rendered = try await FleetViewRenderHarness.render(
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("2.40").font(.system(size: 42, weight: .bold, design: .rounded))
                Text(unit).font(.system(size: 17, weight: .medium, design: .monospaced))
            }.foregroundStyle(.white).padding().background(Color.black))
        #expect(rendered.recognizesMetric("2.40", unit: unit))
        #expect(rendered.recognizesMetric("2.40", unit: "TH/s") == (unit == "TH/s"))
        #expect(!rendered.recognizesMetric("12.40", unit: unit))
    }

    @Test(arguments: ["38 W", "38W"])
    func realPowerSpacingIsNotInvented(_ copy: String) async throws {
        let rendered = try await FleetViewRenderHarness.render(
            Text(copy).font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white).padding().background(Color.black))
        #expect(rendered.recognizesMetric("38", unit: "W") == (copy == "38 W"), "Raw recognition: \(rendered.recognition)")
    }

    @Test func hiddenPixelsCannotBeRecoveredFromAccessibilityMetadata() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            VStack {
                Text("Actual public heading").accessibilityLabel("2.40 TH/s")
                Text("2.40 TH/s").hidden()
            }.foregroundStyle(.white).padding().background(Color.black))
        #expect(rendered.recognizes("Actual public heading"))
        #expect(!rendered.recognizes("2.40"))
        #expect(!rendered.recognizesMetric("2.40", unit: "TH/s"))
    }
}
