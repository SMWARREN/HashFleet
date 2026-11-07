import Foundation
import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

/// Ordering regression for the unified activity surface (2026-11-01). After the display-mode
/// picker was removed, the current per-miner records must always render physically above the
/// recent-notification history, including block-found events, with no mode gating.
///
/// This observes actual captured pixels (word bounding boxes from on-device Vision), not the
/// source order of SwiftUI declarations, so it stays meaningful if the layout is refactored.
/// A single in-memory miner with one injected block-found notification keeps both section
/// anchors inside the popup's capped height instead of being pushed off a scroll view.
@MainActor
struct FleetActivityOrderingTests {
    private let now = Date(timeIntervalSince1970: 1_792_862_000)

    /// Smallest vertical position (top-most) of any recognized word whose text contains `needle`.
    /// Lower `minY` means higher on screen.
    private func topY(containing needle: String, in rendered: FleetRenderedView) -> CGFloat? {
        rendered.recognition.words
            .filter { $0.text.lowercased().contains(needle) }
            .map(\.bounds.minY)
            .min()
    }

    @Test func currentMinerRecordsRenderAboveBlockHistoryWithoutAnyModeGate() async throws {
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        let store = fixture.store
        let device = MinerDevice(name: "Workshop Gamma", address: "fixture.invalid")
        store.devices = [device]
        store.preferences.blockNotificationsEnabled = true
        // A legacy "session best only" selection must no longer hide the notification history.
        store.preferences.activityContentMode = .sessionBest
        let block = MinerBlockFoundEvent(deviceID: device.id, minerName: "Workshop Gamma",
            coinLabel: "BTC", height: 912_345, count: 1, occurredAt: now)
        store.notificationInbox = [FleetNotificationInboxEntry(
            event: .blockFound(block), systemDelivered: true, inAppDelivered: true)]

        let rendered = try await FleetViewRenderHarness.render(
            FleetActivityPopup(store: store), height: 600)

        // Explicitly prove the block-found row rendered: its contiguous title is unique and is
        // not satisfied by the session fallback "Not reported" or the "not a solved-block" copy.
        #expect(rendered.visibleText.lowercased().contains("reported a block"),
            "The injected block-found event must appear in the recent-notification history")

        // "…not a solved-block claim." belongs only to the current session section's description.
        let sessionTop = try #require(topY(containing: "solved", in: rendered),
            "The current session section must be visible regardless of the legacy stored mode")
        // "Recent notifications" is the history header; block history must still appear under it.
        let notificationsTop = try #require(topY(containing: "recent", in: rendered),
            "The notification history header must be visible even under a legacy sessionBest mode")

        // Old UI (sessionBest hid notifications) would never recognize "recent" and fail the
        // #require above; old notifications-first ordering would place "recent" above "solved".
        #expect(sessionTop < notificationsTop,
            "Current miner records must appear above the notification history, not after it")
    }
}
