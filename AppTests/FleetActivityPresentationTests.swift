import Foundation
import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

@MainActor
struct FleetActivityPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_792_862_000)

    @Test(arguments: FleetActivityContentMode.allCases)
    func menuContentPersistsIndependentlyOfVisibility(mode: FleetActivityContentMode) throws {
        let suite = "app.hashfleet.activity.menu-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = FleetMenuBarPreferenceStorage(defaults: defaults)
        #expect(storage.loadContentMode() == .notifications)
        #expect(storage.save(.hidden))
        #expect(storage.saveContentMode(mode))
        let reloaded = FleetMenuBarPreferenceStorage(defaults: defaults)
        #expect(reloaded.load() == .hidden)
        #expect(reloaded.loadContentMode() == mode)
        #expect(mode.showsNotifications == (mode != .sessionBest))
        #expect(mode.showsSessionBest == (mode != .notifications))
        defaults.set("unknown-future-mode", forKey: FleetMenuBarPreferenceStorage.contentKey)
        #expect(storage.loadContentMode() == .notifications)
        let unavailable = FleetMenuBarPreferenceStorage(defaults: nil)
        #expect(unavailable.loadContentMode() == .notifications)
        #expect(unavailable.saveContentMode(mode) == false)
    }

    @Test func legacyCompanionRowsDecodeWithoutSessionOrNotifications() throws {
        let row = FleetMenuBarMinerSummary(id: UUID(), name: "Legacy miner", status: .online,
            segments: ["1 TH/s"], notices: [], isSimulated: false)
        let glance = FleetGlance(updatedAt: now, onlineCount: 1, minerCount: 1,
            hashrateGHs: 1000, powerWatts: 20, isDemo: false)
        var payload = try #require(JSONSerialization.jsonObject(with:
            JSONEncoder().encode(FleetMenuBarSnapshot(glance: glance, miners: [row]))) as? [String: Any])
        payload.removeValue(forKey: "notifications")
        var rows = try #require(payload["miners"] as? [[String: Any]])
        rows[0].removeValue(forKey: "sessionBest")
        payload["miners"] = rows
        let decoded = try JSONDecoder().decode(FleetMenuBarSnapshot.self,
            from: JSONSerialization.data(withJSONObject: payload))
        #expect(decoded.notifications == nil)
        #expect(decoded.miners.first?.sessionBest == nil)
        #expect(decoded.reportedHashrate == 1000)
    }

    @Test(arguments: [JSONValue.integer(0), .integer(12345), .string("2.5M")])
    func sessionUsesOnlyTheReportedCurrentSession(value: JSONValue) throws {
        let snapshot = MinerSnapshot(info: MinerInfo(raw: ["bestSessionDiff": value,
            "bestDiff": .string("900G")]), updatedAt: now)
        let expected = try #require(MiningDifficultyFormat.short(value))
        #expect(FleetActivityPresentation.sessionBest(snapshot: snapshot, isDemo: false, now: now) == expected)
    }

    @Test func currentSessionNeverFallsBackToAllTimeOrStalePartialFrames() {
        let info = MinerInfo(raw: ["bestDiff": .string("900G"), "bestSessionDiff": .string("2M")])
        let complete = MinerSnapshot(info: info, updatedAt: now, completeSnapshotAt: now.addingTimeInterval(-60))
        #expect(FleetActivityPresentation.sessionBest(snapshot: complete, isDemo: false, now: now) == nil)
        let allTimeOnly = MinerSnapshot(info: MinerInfo(raw: ["bestDiff": .string("900G")]), updatedAt: now)
        #expect(FleetActivityPresentation.sessionBest(snapshot: allTimeOnly, isDemo: false, now: now) == nil)
        for value in [JSONValue.bool(true), .integer(-1), .string("bad"), .null] {
            let invalid = MinerSnapshot(info: MinerInfo(raw: ["bestSessionDiff": value]), updatedAt: now)
            #expect(FleetActivityPresentation.sessionBest(snapshot: invalid, isDemo: false, now: now) == nil)
        }
        let badSnapshots = [
            MinerSnapshot(info: info),
            MinerSnapshot(info: info, error: "Offline", updatedAt: now),
            MinerSnapshot(info: info, updatedAt: now, isCached: true),
            MinerSnapshot(info: info, updatedAt: now, isReconnecting: true),
            MinerSnapshot(info: info, updatedAt: now.addingTimeInterval(6)),
            MinerSnapshot(info: info, updatedAt: now.addingTimeInterval(-60))
        ]
        for snapshot in badSnapshots {
            #expect(FleetActivityPresentation.sessionBest(snapshot: snapshot, isDemo: false, now: now) == nil)
        }
        #expect(FleetActivityPresentation.sessionBest(snapshot: nil, isDemo: true, now: now) == nil)
        #expect(FleetActivityPresentation.sessionBest(snapshot: MinerSnapshot(info: info), isDemo: true, now: now) == "2.00M")
    }

    @Test func companionNeverShowsAnOfflineSessionAsCurrent() {
        for status in [FleetMenuBarMinerStatus.offline, .reconnecting, .connecting, .online] {
            let row = FleetMenuBarMinerSummary(id: UUID(), name: "Miner", status: status,
                segments: [], notices: [], isSimulated: false, sessionBest: "2M")
            #expect(FleetMenuBarFormat.sessionBest(row, isStale: true) == nil)
            #expect(FleetMenuBarFormat.sessionBest(row, isStale: false) == (status == .online ? "2M" : nil))
        }
    }

    @Test func notificationSummariesAreBoundedPrivateAndRespectSessionOptOut() throws {
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        let store = fixture.store
        let device = MinerDevice(name: "Workshop\nGamma", address: "fixture.invalid")
        store.devices = [device]
        store.preferences.bestShareNotificationsEnabled = true
        store.preferences.sessionBestNotificationsEnabled = false
        func entry(index: Int, kind: MinerBestShareEvent.Kind, deviceID: UUID? = nil) -> FleetNotificationInboxEntry {
            let event = MinerBestShareEvent(deviceID: deviceID ?? device.id,
                minerName: "RAW_SECRET_NAME", kind: kind, displayValue: "RAW_SECRET_VALUE",
                rawValue: "RAW_SECRET_VALUE", occurredAt: now.addingTimeInterval(Double(index)))
            return FleetNotificationInboxEntry(event: .bestShare(event), systemDelivered: true, inAppDelivered: true)
        }
        store.notificationInbox = (0..<12).map { entry(index: $0, kind: .allTime) }
            + [entry(index: 100, kind: .session), entry(index: 101, kind: .allTime, deviceID: UUID())]
        let summaries = FleetActivityPresentation.notifications(from: store)
        #expect(summaries.count == FleetActivityPresentation.notificationLimit)
        #expect(summaries.first?.occurredAt == now.addingTimeInterval(11))
        #expect(summaries.last?.occurredAt == now.addingTimeInterval(4))
        #expect(summaries.allSatisfy { $0.title == "New all-time best share" && $0.minerName == "WorkshopGamma" })
        let encoded = try #require(String(bytes: try JSONEncoder().encode(summaries), encoding: .utf8))
        #expect(encoded.contains("RAW_SECRET") == false)
        #expect(encoded.contains("fixture.invalid") == false)
        store.preferences.sessionBestNotificationsEnabled = true
        #expect(FleetActivityPresentation.notifications(from: store).first?.title == "New session-best share")
        store.preferences.bestShareNotificationsEnabled = false
        #expect(FleetActivityPresentation.notifications(from: store).isEmpty)
    }

    /// Top-most Y of any recognized word containing `needle` (lower = higher on screen).
    private func topY(_ needle: String, in rendered: FleetRenderedView) -> CGFloat? {
        rendered.recognition.words
            .filter { $0.text.lowercased().contains(needle) }
            .map(\.bounds.minY).min()
    }

    /// Unified activity contract (2026-11-01): there is no display-mode picker, and the current
    /// miner records plus the full recent-notification history (including block-found events) are
    /// always visible in miner-first order, regardless of any legacy persisted display mode.
    /// A compact in-memory fixture keeps both section anchors inside the popup's height cap.
    ///
    /// Parametrizing over every legacy mode proves the UI no longer reads the stored mode: the old
    /// UI hid notifications under `.sessionBest` and the session list under `.notifications`, so at
    /// least one argument here would fail against that removed behavior.
    @Test(arguments: FleetActivityContentMode.allCases)
    func actualPopupRendersUnifiedMinerFirstActivity(legacyMode: FleetActivityContentMode) async throws {
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        let store = fixture.store
        let device = MinerDevice(name: "Workshop Gamma", address: "fixture.invalid")
        store.devices = [device]
        store.preferences.activityContentMode = legacyMode
        store.preferences.blockNotificationsEnabled = true
        let block = MinerBlockFoundEvent(deviceID: device.id, minerName: "Workshop Gamma",
            coinLabel: "BTC", height: 912_345, count: 1, occurredAt: now)
        store.notificationInbox = [FleetNotificationInboxEntry(
            event: .blockFound(block), systemDelivered: true, inAppDelivered: true)]

        let rendered = try await FleetViewRenderHarness.render(
            FleetActivityPopup(store: store), height: 600)
        let text = rendered.visibleText.lowercased()

        #expect(rendered.pixelVariation > 8)
        #expect(text.contains("fleet activity"))
        // Both sections are always present, even under a legacy single-section mode.
        #expect(text.contains("session best"))
        #expect(text.contains("recent notifications"))
        // Block-found history is visible (old `.sessionBest` mode hid all notifications).
        // Require the contiguous block row title: the session fallback "Not reported" and the
        // disclaimer "not a solved-block claim" both contain "reported" but never this phrase.
        #expect(text.contains("reported a block"))
        // The removed display-mode selector no longer renders its "Both" label.
        #expect(!text.contains("both"))
        // Miner-first order: the current session records sit above the notification log.
        let sessionTop = try #require(topY("solved", in: rendered),
            "Session section ('…not a solved-block claim.') must be visible")
        let notificationsTop = try #require(topY("recent", in: rendered),
            "Recent-notifications header must be visible")
        #expect(sessionTop < notificationsTop,
            "Current miner records must render above the notification history")
    }
}
