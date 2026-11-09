import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@MainActor
struct FleetActivityDeliveryTests {
    @Test(arguments: [false, true], [false, true])
    func sessionOptOutDoesNotMuteAllTimeOrDuplicateDelivery(isActive: Bool, sessionEnabled: Bool) throws {
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        let store = fixture.store
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        store.devices = [device]
        store.preferences.bestShareNotificationsEnabled = true
        store.preferences.sessionBestNotificationsEnabled = sessionEnabled
        let events = [MinerBestShareEvent.Kind.allTime, .session].map { kind in
            MinerBestShareEvent(deviceID: device.id, minerName: device.name, kind: kind,
                displayValue: "2M", rawValue: "2M", occurredAt: .now)
        }
        store.pendingBestShareEvents = events
        store.notificationInbox = events.map {
            FleetNotificationInboxEntry(event: .bestShare($0), systemDelivered: false, inAppDelivered: false)
        }
        var posted: [MinerBestShareEvent.Kind] = []
        var shown: [MinerBestShareEvent.Kind] = []
        for _ in 0..<2 {
            FleetNotificationDelivery.consume(from: store, isActive: isActive,
                postBestShare: { posted.append($0.kind) },
                presentInApp: { if case .bestShare(let event) = $0 { shown.append(event.kind) } })
        }
        let expected: [MinerBestShareEvent.Kind] = sessionEnabled ? [.allTime, .session] : [.allTime]
        if isActive {
            #expect(posted.isEmpty)
            // Both kinds reach the same illustrated record presentation, never a record toast.
            #expect(shown == expected)
        } else {
            #expect(posted == expected)
            #expect(shown.isEmpty)
        }
        #expect(store.pendingBestShareEvents.isEmpty)
        #expect(store.undeliveredSystemNotificationEntries.isEmpty)
    }

    @Test func disabledSessionJournalIsConsumedWithoutReplayingWhenReenabled() throws {
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        let store = fixture.store
        let device = MinerDevice(name: "Fixture", address: "fixture.invalid")
        store.devices = [device]
        store.preferences.bestShareNotificationsEnabled = true
        store.preferences.sessionBestNotificationsEnabled = false
        let event = MinerBestShareEvent(deviceID: device.id, minerName: device.name, kind: .session,
            displayValue: "2M", rawValue: "2M", occurredAt: .now)
        store.notificationInbox = [FleetNotificationInboxEntry(event: .bestShare(event),
            systemDelivered: false, inAppDelivered: false)]
        FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true,
            presentInApp: { _ in Issue.record("An opted-out session must not replay") })
        #expect(store.undeliveredSystemNotificationEntries.isEmpty)
        store.preferences.sessionBestNotificationsEnabled = true
        FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true,
            presentInApp: { _ in Issue.record("Re-enabling must not resurrect a suppressed session") })
    }
}
