import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension FleetNotificationDeliveryTests {
    func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "app.hashfleet.delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    /// Distinct raw values keep each event distinct under the journal's observation dedupe, and the
    /// ascending timestamps keep the journal's chronological order equal to creation order.
    func recordEvent(
        _ device: MinerDevice, _ raw: String, order: Int,
        kind: MinerBestShareEvent.Kind = .allTime
    ) -> FleetNotificationEvent {
        .bestShare(MinerBestShareEvent(
            deviceID: device.id, minerName: device.name, kind: kind, displayValue: raw, rawValue: raw,
            occurredAt: Date().addingTimeInterval(TimeInterval(order - 600))))
    }

    /// Journal only, as a previous launch would have left it.
    func journal(_ events: [FleetNotificationEvent], in store: FleetStore) {
        for event in events { store.enqueueNotification(event) }
    }

    /// Journal and drain queue, as real detection does.
    func detect(_ events: [FleetNotificationEvent], in store: FleetStore) {
        journal(events, in: store)
        for case .bestShare(let share) in events { store.pendingBestShareEvents.append(share) }
    }

    func entry(for event: FleetNotificationEvent, in store: FleetStore) -> FleetNotificationInboxEntry? {
        store.notificationInbox.first { $0.id == event.id }
    }

    @Test func declinedHandoffKeepsAMarkerAndALaterAcceptanceClearsIt() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let event = recordEvent(device, "2M", order: 0)
            detect([event], in: store)

            var offered: [UUID] = []
            var markerDuringHandoff: [Bool?] = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                markerDuringHandoff.append(store.notificationInbox.first { $0.id == offeredEvent.id }?.inAppAcceptancePending)
                return false
            })
            #expect(offered == [event.id])
            #expect(markerDuringHandoff == [true], "The marker is durable before the handoff is attempted.")
            let declined = try #require(entry(for: event, in: store))
            #expect(declined.systemDelivered, "Active delivery never also pushes the event.")
            #expect(declined.inAppDelivered == false, "A declined handoff is not a shown popup.")
            #expect(declined.inAppAcceptancePending == true)
            #expect(store.undeliveredSystemNotificationEntries.isEmpty)

            // Nothing fresh is queued, so this empty consume must retry the older marked entry.
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [event.id])
            let accepted = try #require(entry(for: event, in: store))
            #expect(accepted.inAppDelivered && accepted.systemDelivered)
            #expect(accepted.inAppAcceptancePending != true, "Acceptance clears the marker.")

            // Accepted records are never offered again.
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty)
        }
    }

    @Test func declinedHandoffSurvivesStoreReconstructionAndRetriesFromTheSameDefaults() throws {
        try withDefaults { defaults in
            let first = FleetStore(defaults: defaults)
            try first.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(first.devices.first)
            let event = recordEvent(device, "2M", order: 0)
            detect([event], in: first)
            FleetNotificationDelivery.consume(from: first, isActive: true, acceptInApp: { _ in false })

            // A relaunch builds a new store from the same defaults. The marker must have been persisted.
            let second = FleetStore(defaults: defaults)
            let restored = try #require(entry(for: event, in: second))
            #expect(restored.inAppAcceptancePending == true)
            #expect(restored.systemDelivered && !restored.inAppDelivered)

            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: second, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [event.id])

            // And the acceptance is itself durable: a third store has nothing left to retry.
            let third = FleetStore(defaults: defaults)
            let settled = try #require(entry(for: event, in: third))
            #expect(settled.inAppDelivered && settled.inAppAcceptancePending != true)
            offered = []
            FleetNotificationDelivery.consume(from: third, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: third, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty)
        }
    }

    @Test func inboxEntryWithoutAnAcceptanceMarkerStillDecodes() throws {
        let device = MinerDevice(name: "Desk", address: "desk.local")
        let event = recordEvent(device, "2M", order: 0)
        let legacy = FleetNotificationInboxEntry(event: event, systemDelivered: true, inAppDelivered: false)

        // Entries written by the previous build have exactly the three original keys.
        let encoded = try JSONEncoder().encode([legacy])
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        object[0].removeValue(forKey: "inAppAcceptancePending")
        #expect(Set(object[0].keys) == ["event", "systemDelivered", "inAppDelivered"])
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode([FleetNotificationInboxEntry].self, from: legacyData)
        #expect(decoded.count == 1)
        #expect(decoded[0].event == event && decoded[0].systemDelivered && !decoded[0].inAppDelivered)
        #expect(decoded[0].inAppAcceptancePending == nil)
        #expect(decoded[0] == legacy)

        // A marked entry round-trips.
        var marked = legacy
        marked.inAppAcceptancePending = true
        let markedRoundTrip = try JSONDecoder().decode(
            [FleetNotificationInboxEntry].self, from: JSONEncoder().encode([marked]))
        #expect(markedRoundTrip == [marked] && markedRoundTrip[0].inAppAcceptancePending == true)

        // The real store restores a legacy journal from defaults without inventing a marker.
        try withDefaults { defaults in
            let seed = FleetStore(defaults: defaults)
            try seed.add(name: "Desk", address: "192.168.1.10")
            let seeded = try #require(seed.devices.first)
            let seededEvent = recordEvent(seeded, "3M", order: 1)
            let entryOnDisk = FleetNotificationInboxEntry(event: seededEvent, systemDelivered: true, inAppDelivered: false)
            var json = try #require(JSONSerialization.jsonObject(
                with: JSONEncoder().encode([entryOnDisk])) as? [[String: Any]])
            json[0].removeValue(forKey: "inAppAcceptancePending")
            defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: FleetStore.notificationInboxStorageKey)

            let reopened = FleetStore(defaults: defaults)
            let restored = try #require(entry(for: seededEvent, in: reopened))
            #expect(restored.inAppAcceptancePending == nil)
            #expect(restored.systemDelivered && !restored.inAppDelivered)
        }
    }

    @Test func historicalSuppressedEntriesAreNeverResurrectedByAcceptanceRetry() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)

            // History 1: delivered or intentionally suppressed by an older build.
            let legacy = recordEvent(device, "2M", order: 0)
            journal([legacy], in: store)
            let legacyIndex = try #require(store.notificationInbox.firstIndex { $0.id == legacy.id })
            store.notificationInbox[legacyIndex].systemDelivered = true
            store.persistNotificationInbox()

            // History 2: suppressed by the user's preference through the real delivery path.
            store.preferences.bestShareNotificationsEnabled = false
            let suppressed = recordEvent(device, "3M", order: 1)
            detect([suppressed], in: store)
            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty)
            let suppressedEntry = try #require(entry(for: suppressed, in: store))
            #expect(suppressedEntry.systemDelivered && !suppressedEntry.inAppDelivered)
            #expect(suppressedEntry.inAppAcceptancePending != true)

            // Re-enabling the preference and a fresh record must offer only the fresh record.
            store.preferences.bestShareNotificationsEnabled = true
            let fresh = recordEvent(device, "4M", order: 2)
            detect([fresh], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [fresh.id])
            for old in [legacy, suppressed] {
                let kept = try #require(entry(for: old, in: store))
                #expect(!kept.inAppDelivered && kept.inAppAcceptancePending != true, "History stays history.")
            }
        }
    }

    @Test func firstDeclinedHandoffBlocksLaterRecordsAndPreservesFIFO() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            let c = recordEvent(device, "4M", order: 2)
            detect([a, b, c], in: store)

            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return false
            })
            #expect(offered == [a.id], "After the first decline no later record may be handed off.")
            #expect(entry(for: a, in: store)?.inAppAcceptancePending == true)
            for waiting in [b, c] { #expect(entry(for: waiting, in: store)?.inAppDelivered == false) }

            // A fresh record arriving while the oldest is still declined waits behind all of them.
            let d = recordEvent(device, "5M", order: 3)
            detect([d], in: store)
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return false
            })
            #expect(offered == [a.id], "The retry stops at the oldest declined record, fresh record included.")
            for waiting in [b, c, d] { #expect(entry(for: waiting, in: store)?.inAppDelivered == false) }

            // Once storage accepts, every record is handed off exactly once in the original order.
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [a.id, b.id, c.id, d.id])
            for event in [a, b, c, d] {
                let settled = try #require(entry(for: event, in: store))
                #expect(settled.inAppDelivered && settled.inAppAcceptancePending != true)
            }
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty)
        }
    }

    @Test func declinedFreshRecordIsRetriedBeforeAnyLaterFreshRecord() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let first = recordEvent(device, "2M", order: 0)
            detect([first], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })

            let second = recordEvent(device, "3M", order: 1)
            detect([second], in: store)
            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [first.id, second.id], "Older marked entries are retried before fresh ones.")
        }
    }

    @Test func replayRetriesOnlyExplicitlyMarkedEntriesInOrder() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let historical = recordEvent(device, "2M", order: 0)
            let firstMarked = recordEvent(device, "3M", order: 1)
            let secondMarked = recordEvent(device, "4M", order: 2)
            journal([historical, firstMarked, secondMarked], in: store)
            for index in store.notificationInbox.indices {
                store.notificationInbox[index].systemDelivered = true
                if store.notificationInbox[index].id != historical.id {
                    store.notificationInbox[index].inAppAcceptancePending = true
                }
            }
            store.persistNotificationInbox()

            // Inactive replay never offers an in-app handoff.
            var offered: [UUID] = []
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: false, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty)

            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return false
            })
            #expect(offered == [firstMarked.id], "A decline stops the replay so FIFO holds.")
            #expect(entry(for: firstMarked, in: store)?.inAppAcceptancePending == true)

            offered = []
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == [firstMarked.id, secondMarked.id])
            for event in [firstMarked, secondMarked] {
                let settled = try #require(entry(for: event, in: store))
                #expect(settled.inAppDelivered && settled.inAppAcceptancePending != true)
            }
            let untouched = try #require(entry(for: historical, in: store))
            #expect(!untouched.inAppDelivered && untouched.inAppAcceptancePending != true)
        }
    }

    @Test func backgroundPostedEventsAreNeverReplayedInTheApp() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let event = recordEvent(device, "2M", order: 0)
            detect([event], in: store)

            var posted = 0
            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postBestShare: { _ in posted += 1 },
                acceptInApp: { offeredEvent in
                    offered.append(offeredEvent.id)
                    return true
                })
            #expect(posted == 1 && offered.isEmpty)
            let pushed = try #require(entry(for: event, in: store))
            #expect(pushed.systemDelivered && pushed.inAppDelivered && pushed.inAppAcceptancePending != true)

            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered.isEmpty, "A pushed event is never celebrated a second time.")
            #expect(posted == 1)
        }
    }

    @Test func acceptedHandoffMarksBothChannelsAndIsNeverRepeated() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let events = [recordEvent(device, "2M", order: 0), recordEvent(device, "3M", order: 1, kind: .session)]
            detect(events, in: store)
            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true,
                postBestShare: { _ in Issue.record("Pushed while the app was open") },
                acceptInApp: { offeredEvent in
                    offered.append(offeredEvent.id)
                    return true
                })
            #expect(offered == events.map(\.id))
            for event in events {
                let settled = try #require(entry(for: event, in: store))
                #expect(settled.systemDelivered && settled.inAppDelivered && settled.inAppAcceptancePending != true)
            }
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { offeredEvent in
                offered.append(offeredEvent.id)
                return true
            })
            #expect(offered == events.map(\.id))
        }
    }

}
