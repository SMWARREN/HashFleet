import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension FleetNotificationDeliveryTests {
    @Test func legacyVoidCallbackStaysMarkBeforeCallAndReentrantSafe() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let first = recordEvent(device, "2M", order: 0)
            let second = recordEvent(device, "3M", order: 1)
            let third = recordEvent(device, "4M", order: 2)
            // Two entries left by an earlier launch, plus one that detection delivers during the callback.
            journal([first, second], in: store)

            var counts: [UUID: Int] = [:]
            var reentered = false
            @MainActor
            func handoff(_ event: FleetNotificationEvent) {
                counts[event.id, default: 0] += 1
                // The entry is already marked shown before the callback, so re-entry cannot repeat it.
                let alreadyMarkedShown = store.isInAppNotificationDelivered(event)
                #expect(alreadyMarkedShown)
                guard !reentered else { return }
                reentered = true
                detect([third], in: store)
                FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                    from: store, isActive: true, presentInApp: handoff)
                FleetNotificationDelivery.consume(from: store, isActive: true, presentInApp: handoff)
            }
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                from: store, isActive: true, presentInApp: handoff)
            #expect(counts[first.id] == 1 && counts[second.id] == 1 && counts[third.id] == 1)
            #expect(counts.count == 3)
            FleetNotificationDelivery.consume(from: store, isActive: true, presentInApp: handoff)
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                from: store, isActive: true, presentInApp: handoff)
            #expect(counts.values.allSatisfy { $0 == 1 })
        }
    }

    @Test func durableAcceptCallbackReenteringConsumeAndReplayNeitherDuplicatesNorDrains() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            let late = recordEvent(device, "4M", order: 2)
            detect([a, b], in: store)

            var offered: [UUID] = []
            var nestedOffers: [UUID] = []
            var reentered = false
            var stateInsideCallback: (pending: Bool?, shown: Bool)?
            var drainedByReentry = true
            @MainActor
            func accept(_ event: FleetNotificationEvent) -> Bool {
                offered.append(event.id)
                guard !reentered else { return true }
                reentered = true
                let inside = store.notificationInbox.first { $0.id == event.id }
                stateInsideCallback = (inside?.inAppAcceptancePending, inside?.inAppDelivered ?? true)
                // A record detected while the first handoff is in flight, then both entry points re-entered.
                detect([late], in: store)
                FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { nested in
                    nestedOffers.append(nested.id)
                    return true
                })
                FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                    from: store, isActive: true, acceptInApp: { nested in
                        nestedOffers.append(nested.id)
                        return true
                    })
                // The re-entrant call must not have drained the queue of fresh detections.
                drainedByReentry = store.pendingBestShareEvents.isEmpty
                return true
            }

            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            #expect(offered == [a.id, b.id], "Each drained record is offered exactly once, in order.")
            #expect(nestedOffers.isEmpty, "Re-entrant consume/replay must not offer anything.")
            #expect(stateInsideCallback?.pending == true && stateInsideCallback?.shown == false,
                    "During the handoff the record is marked pending and not yet shown.")
            #expect(!drainedByReentry, "Re-entrant consume must not drain fresh detections.")
            #expect(store.pendingBestShareEvents.map(\.id) == [late.id])

            // Once the outer handoff has returned, delivery resumes and the late record is offered once.
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: accept)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            #expect(offered == [a.id, b.id, late.id])
            for event in [a, b, late] {
                let settled = try #require(entry(for: event, in: store))
                #expect(settled.inAppDelivered && settled.systemDelivered && settled.inAppAcceptancePending != true)
            }
        }
    }

    @Test func reenteringDurableCallbackThatDeclinesStillLeavesOneRetryableRecord() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            detect([a, b], in: store)

            var offered: [UUID] = []
            var shouldAccept = false
            @MainActor
            func accept(_ event: FleetNotificationEvent) -> Bool {
                offered.append(event.id)
                // Re-enter while declining. It must not hand anything off, in either direction.
                FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { nested in
                    offered.append(nested.id)
                    return true
                })
                FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                    from: store, isActive: true, acceptInApp: { nested in
                        offered.append(nested.id)
                        return true
                    })
                return shouldAccept
            }
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            #expect(offered == [a.id])
            #expect(entry(for: a, in: store)?.inAppAcceptancePending == true)
            #expect(entry(for: a, in: store)?.inAppDelivered == false)
            #expect(entry(for: b, in: store)?.inAppDelivered == false)

            shouldAccept = true
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            #expect(offered == [a.id, b.id])
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: accept)
            #expect(offered == [a.id, b.id])
        }
    }

    @Test func notificationRouteIsRetainedUntilExplicitlyConsumedAfterAFailedHandoff() throws {
        try withDefaults { defaults in
            let miner = UUID()
            let celebration = FleetCelebration(kind: .blockFound, deviceID: miner, minerName: "Desk",
                                               value: "900,000", detail: "Block found at this height")
            #expect(FleetNotificationRoute.handle(userInfo: celebration.userInfo, defaults: defaults))

            let route = try #require(FleetNotificationRoute.pending(defaults: defaults))
            #expect(route.deviceID == miner)
            #expect(route.celebration == celebration, "The exact record, including its ID, round-trips.")

            // Storage refuses the record: nothing may be consumed, so the tap is not lost.
            let routed = try #require(route.celebration)
            var unavailable = FleetCelebrationQueue(unavailableMessage: "Storage is unavailable.")
            let refused = unavailable.present(routed)
            #expect(refused == false)
            #expect(FleetNotificationRoute.pending(defaults: defaults) == route)
            #expect(FleetNotificationRoute.pending(defaults: defaults) == route, "Peeking is repeatable.")

            // A later successful handoff then consumes it exactly once.
            var queue = FleetCelebrationQueue()
            let accepted = queue.present(routed)
            #expect(accepted)
            #expect(FleetNotificationRoute.consume(defaults: defaults) == route)
            #expect(FleetNotificationRoute.pending(defaults: defaults) == nil)
            #expect(FleetNotificationRoute.consume(defaults: defaults) == nil)
            #expect(queue.current == celebration)
        }
    }

    @Test func notificationRouteWithoutARecordPayloadStillRoutesToTheMiner() throws {
        try withDefaults { defaults in
            let miner = UUID()
            #expect(FleetNotificationRoute.handle(
                userInfo: [FleetCelebration.userInfoDevice: miner.uuidString], defaults: defaults))
            let route = try #require(FleetNotificationRoute.pending(defaults: defaults))
            #expect(route.deviceID == miner && route.celebration == nil)
            #expect(FleetNotificationRoute.consume(defaults: defaults) == route)
            #expect(FleetNotificationRoute.pending(defaults: defaults) == nil)
        }
    }

    // MARK: - Status alerts are never blocked by a declined record handoff

    private func statusEvents(_ device: MinerDevice, order: Int) -> (state: FleetNotificationEvent, power: FleetNotificationEvent) {
        let when = Date().addingTimeInterval(TimeInterval(order - 600))
        return (
            .stateChange(MinerStateChangeEvent(
                deviceID: device.id, minerName: device.name, kind: .offline,
                detail: "Connection refused", occurredAt: when)),
            .power(MinerPowerAlertEvent(
                deviceID: device.id, minerName: device.name, kind: .exceeded,
                watts: 140, thresholdWatts: 100, occurredAt: when)))
    }

    private func enableStatusAlerts(_ store: FleetStore, for device: MinerDevice) throws {
        store.preferences.bestShareNotificationsEnabled = true
        store.preferences.stateChangeNotificationsEnabled = true
        store.preferences.powerAlertNotificationsEnabled = true
        try store.powerAlerts.setPolicy(try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 100), for: device.id)
    }

    private func queueStatus(_ events: (state: FleetNotificationEvent, power: FleetNotificationEvent), in store: FleetStore) {
        journal([events.state, events.power], in: store)
        if case .stateChange(let change) = events.state { store.pendingStateChangeEvents.append(change) }
        if case .power(let power) = events.power { store.pendingPowerAlertEvents.append(power) }
    }

    @Test func declinedRecordNeverBlocksOfflineAndPowerSafetyAlertsInTheSamePass() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            try enableStatusAlerts(store, for: device)
            let record = recordEvent(device, "2M", order: 0)
            let status = statusEvents(device, order: 1)
            detect([record], in: store)
            queueStatus(status, in: store)

            var offered: [UUID] = []
            @MainActor
            func accept(_ event: FleetNotificationEvent) -> Bool {
                offered.append(event.id)
                // Only the durable record queue can decline. Status alerts use the transient surface.
                if case .bestShare = event { return false }
                return true
            }
            FleetNotificationDelivery.consume(from: store, isActive: true,
                postStateChange: { _ in Issue.record("Pushed while the app was open") },
                postPower: { _ in Issue.record("Pushed while the app was open") },
                acceptInApp: accept)

            #expect(Set(offered) == [record.id, status.state.id, status.power.id],
                    "A declined record must not hold back safety alerts in the same pass.")
            #expect(offered.filter { $0 == status.state.id }.count == 1)
            #expect(offered.filter { $0 == status.power.id }.count == 1)

            for event in [status.state, status.power] {
                let settled = try #require(entry(for: event, in: store))
                #expect(settled.systemDelivered && settled.inAppDelivered, "Status alerts are delivered.")
                #expect(settled.inAppAcceptancePending != true)
            }
            let waiting = try #require(entry(for: record, in: store))
            #expect(waiting.inAppAcceptancePending == true && !waiting.inAppDelivered, "The record stays retryable.")

            // The next pass retries only the record. Delivered status alerts are not offered again.
            offered = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { event in
                offered.append(event.id)
                return true
            })
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true, acceptInApp: { event in
                offered.append(event.id)
                return true
            })
            #expect(offered == [record.id])
            let settled = try #require(entry(for: record, in: store))
            #expect(settled.inAppDelivered && settled.inAppAcceptancePending != true)
        }
    }

    @Test func freshStatusAlertReachesTheAppWhileAnOlderRecordIsStillDeclined() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            try enableStatusAlerts(store, for: device)
            let record = recordEvent(device, "2M", order: 0)
            detect([record], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            #expect(entry(for: record, in: store)?.inAppAcceptancePending == true)

            // An offline alert arrives while the older record is still being declined by storage.
            let status = statusEvents(device, order: 1)
            queueStatus(status, in: store)
            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { event in
                offered.append(event.id)
                if case .bestShare = event { return false }
                return true
            })
            #expect(offered.contains(status.state.id) && offered.contains(status.power.id),
                    "The retry loop must still offer status alerts.")
            #expect(offered.filter { $0 == record.id }.count == 1, "The declined record is retried, not duplicated.")
            #expect(entry(for: status.state, in: store)?.inAppDelivered == true)
            #expect(entry(for: status.power, in: store)?.inAppDelivered == true)
            #expect(entry(for: record, in: store)?.inAppAcceptancePending == true)
            #expect(entry(for: record, in: store)?.inAppDelivered == false)
        }
    }

    @Test func alreadyShownEventStillMarksTheSystemChannelWhenAcceptanceIsEnabled() throws {
        try withDefaults { defaults in
            let store = FleetStore(defaults: defaults)
            try store.add(name: "Desk", address: "192.168.1.10")
            let device = try #require(store.devices.first)
            let event = recordEvent(device, "2M", order: 0)
            detect([event], in: store)
            // The record was already shown in the app, but the system channel is not yet marked.
            store.markInAppNotificationDelivered(for: event)
            #expect(entry(for: event, in: store)?.systemDelivered == false)

            var offered: [UUID] = []
            FleetNotificationDelivery.consume(from: store, isActive: true,
                postBestShare: { _ in Issue.record("Pushed while the app was open") },
                acceptInApp: { offeredEvent in
                    offered.append(offeredEvent.id)
                    return true
                })
            #expect(offered.isEmpty, "A record already shown is not offered again.")
            let settled = try #require(entry(for: event, in: store))
            #expect(settled.systemDelivered, "Active delivery keeps its old channel semantics: never pushed later.")
            #expect(settled.inAppDelivered)
            #expect(store.undeliveredSystemNotificationEntries.isEmpty)
        }
    }
}

// The existing synchronous routing tests above remain unchanged. These tests exercise the
// new suspended durable handoff boundary used by both app entry points.
