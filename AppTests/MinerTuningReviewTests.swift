import SwiftUI
import Testing
@testable import HashFleet

@Suite("Compact tuning review", .serialized) @MainActor
struct MinerTuningReviewTests {
    @Test(arguments: [CGFloat(320), CGFloat(430), CGFloat(768)])
    func easyReviewShowsBothChangedFieldsBesideSafetyAndApply(width: CGFloat) async throws {
        let rendered = try await FleetViewRenderHarness.render(
            review(summary: "Frequency: 500 → 510 MHz\nVoltage: 1100 → 1125 mV"),
            width: width, height: 650
        )
        #expect(rendered.visibleText.contains("Frequency"))
        #expect(rendered.visibleText.contains("Voltage"))
        #expect(rendered.visibleText.contains("hardware risks"))
        #expect(rendered.visibleText.contains("Apply tuning change"))
        #expect(rendered.visibleText.contains("no changes are sent"))
        #expect(!rendered.visibleText.contains("coreVoltage"), "Raw JSON is optional detail, not a second Easy review screen")
    }

    @Test func restrictionStaysVisibleEvenWhenVoltageControlsAreCollapsed() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            review(restriction: "Gamma 601a: lower the staged voltage.", beyondReference: true),
            width: 390, height: 700
        )
        #expect(rendered.visibleText.contains("lower the staged voltage"))
        #expect(!rendered.visibleText.contains("Above firmware reference"))
    }

    @Test func aboveReferenceWarningAndReadOnlyStatusDoNotDisappear() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            review(beyondReference: true, demo: false, offline: true), width: 390, height: 700
        )
        #expect(rendered.visibleText.contains("Above firmware reference"))
        #expect(rendered.visibleText.contains("Read only"))
        #expect(rendered.visibleText.contains("reconnect to apply"))
    }

    @Test func verificationFailureIsNotPresentedAsSuccess() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            review(error: "Readback pending"), width: 390, height: 700
        )
        #expect(rendered.visibleText.contains("Readback pending"))
        #expect(!rendered.visibleText.contains("Verified"))
    }

    @Test func verifiedStatusRemainsInTheCompactReview() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            review(status: "Verified frequency change"), width: 390, height: 700
        )
        #expect(rendered.visibleText.contains("Verified frequency change"))
    }

    @Test func advancedStillShowsTheExactPayloadAndEmptyDraftExplanation() async throws {
        let payload = try await FleetViewRenderHarness.render(
            review(mode: .advanced, json: "frequency: 510"), width: 390, height: 600
        )
        #expect(payload.visibleText.contains("One settings update"))
        #expect(payload.visibleText.contains("frequency: 510"))
        let empty = try await FleetViewRenderHarness.render(
            review(mode: .advanced, json: nil, demo: false), width: 390, height: 600
        )
        #expect(empty.visibleText.contains("Change a value"))
        #expect(empty.visibleText.contains("One confirmation"))
    }

    private func review(
        mode: MinerTuningControlMode = .easy,
        summary: String = "Frequency: 500 → 510 MHz",
        json: String? = "frequency: 510",
        restriction: String? = nil,
        beyondReference: Bool = false,
        demo: Bool = true,
        offline: Bool = false,
        error: String? = nil,
        status: String? = nil
    ) -> some View {
        MinerTuningReview(
            mode: mode, summary: summary, stagedJSON: json,
            riskAcknowledged: .constant(false), isBeyondReference: beyondReference,
            voltageRestriction: restriction, isDemo: demo, isOffline: offline,
            isApplying: false, canApply: false, error: error, statusMessage: status,
            onReview: {}
        )
    }
}
