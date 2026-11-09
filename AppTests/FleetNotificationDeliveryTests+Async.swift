import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension FleetNotificationDeliveryTests {
    @MainActor private final class AcceptanceGate {
        var entered = false
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            entered = true
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }

    private func withAsyncStore(_ body: (FleetStore) async throws -> Void) async rethrows {
        let suite = "app.hashfleet.async-delivery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(FleetStore(defaults: defaults))
    }

    @Test func suspendedDurableHandoffKeepsJournalPendingAndSafetyAlertsImmediate() async throws {
        try await withAsyncStore { store in
            try store.add(name: "Desk", address: "127.0.0.1")
            store.preferences.bestShareNotificationsEnabled = true
            store.preferences.stateChangeNotificationsEnabled = true
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            detect([a, b], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            let gate = AcceptanceGate()
            var offered: [UUID] = []
            let pump = FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { event in
                offered.append(event.id)
                if event.id == a.id { await gate.wait() }
                return true
            }
            for _ in 0..<100 where !gate.entered { try await Task.sleep(for: .milliseconds(5)) }
            #expect(gate.entered)
            #expect(offered == [a.id])
            #expect(entry(for: a, in: store)?.inAppDelivered == false)
            #expect(entry(for: a, in: store)?.inAppAcceptancePending == true)
            let c = recordEvent(device, "4M", order: 2)
            detect([c], in: store)
            let alert = MinerStateChangeEvent(deviceID: device.id, minerName: device.name,
                kind: .offline, detail: "controlled safety alert", occurredAt: .now)
            store.pendingStateChangeEvents.append(alert)
            var safetyShown = false
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { event in
                if case .stateChange = event { safetyShown = true; return true }
                return false
            })
            let samePump = FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { _ in
                Issue.record("A second writer ran while the first handoff was suspended")
                return true
            }
            #expect(safetyShown && offered == [a.id])
            #expect(entry(for: c, in: store)?.inAppDelivered == false)
            gate.open()
            await pump.value
            await samePump.value
            #expect(offered == [a.id, b.id, c.id])
            for event in [a, b, c] {
                #expect(entry(for: event, in: store)?.inAppDelivered == true)
                #expect(entry(for: event, in: store)?.inAppAcceptancePending != true)
            }
        }
    }

    @Test func failedAsyncCommitStopsAtOldestAndRetriesBeforeNewRecords() async throws {
        try await withAsyncStore { store in
            try store.add(name: "Desk", address: "127.0.0.1")
            store.preferences.bestShareNotificationsEnabled = true
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            detect([a, b], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            var declined: [UUID] = []
            await FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { event in
                declined.append(event.id)
                return false
            }.value
            #expect(declined == [a.id])
            #expect(entry(for: a, in: store)?.inAppAcceptancePending == true)
            #expect(entry(for: a, in: store)?.inAppDelivered == false)
            #expect(entry(for: b, in: store)?.inAppDelivered == false)
            let c = recordEvent(device, "4M", order: 2)
            detect([c], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            let queue = FleetCelebrationQueueController(isTesting: true, arguments: [])
            var committed: [UUID] = []
            await FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { event in
                guard let record = FleetCelebration(event) else { return false }
                #expect(entry(for: event, in: store)?.inAppDelivered == false)
                let result = await queue.submit(.present(record, sessionEnabled: true)).value
                #expect(result.accepted)
                #expect(entry(for: event, in: store)?.inAppDelivered == false,
                        "The journal must still be pending until the commit callback returns")
                committed.append(event.id)
                return result.accepted
            }.value
            #expect(committed == [a.id, b.id, c.id])
            #expect(queue.unacknowledgedCount == 3 && queue.current?.id == a.id)
            for event in [a, b, c] { #expect(entry(for: event, in: store)?.inAppDelivered == true) }
            _ = await queue.submit(.close).value
            FleetNotificationDelivery.consume(from: store, isActive: false,
                postBestShare: { _ in Issue.record("An accepted foreground record was pushed again") })
        }
    }

    @Test func asyncCommitRechecksOptOutAndRemovedDevicesAfterSuspension() async throws {
        try await withAsyncStore { store in
            try store.add(name: "Desk", address: "127.0.0.1")
            store.preferences.bestShareNotificationsEnabled = true
            let device = try #require(store.devices.first)
            let a = recordEvent(device, "2M", order: 0)
            let b = recordEvent(device, "3M", order: 1)
            detect([a, b], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            var offered: [UUID] = []
            await FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { event in
                offered.append(event.id)
                await Task.yield()
                store.preferences.bestShareNotificationsEnabled = false
                return true
            }.value
            #expect(offered == [a.id])
            #expect(entry(for: b, in: store)?.inAppAcceptancePending != true)
            store.preferences.bestShareNotificationsEnabled = true
            let c = recordEvent(device, "4M", order: 2)
            detect([c], in: store)
            FleetNotificationDelivery.consume(from: store, isActive: true, acceptInApp: { _ in false })
            store.remove(device)
            await FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store) { _ in
                Issue.record("Removed miner reached durable acceptance")
                return true
            }.value
            #expect(entry(for: c, in: store)?.inAppAcceptancePending != true)
        }
    }
}
