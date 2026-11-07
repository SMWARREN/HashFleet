import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// A new best share must be detectable from a persisted baseline, not only from an in-memory
/// previous reading, otherwise a background refresh can never raise an alert.
@Suite("Best share alerts")
struct BestShareNotificationTests {
    private let device = MinerDevice(name: "Desk miner", address: "192.168.1.10")

    private func info(best: String, session: String) -> MinerInfo {
        MinerInfo(raw: ["bestDiff": .string(best), "bestSessionDiff": .string(session)])
    }

    @Test func firstObservationIsABaselineAndNeverAlerts() {
        #expect(
            MinerBestShareEvent.detect(
                device: device, previous: nil,
                current: MinerBestShareObservation(info: info(best: "1.2M", session: "900k")),
                occurredAt: .now
            ) == nil
        )
    }

    @Test func persistedBaselineDetectsANewAllTimeRecordAcrossLaunches() throws {
        // Simulates a background refresh: no in-memory previous reading, only stored state.
        let stored = MinerBestShareObservation(bestDiff: "1.2M", bestSessionDiff: "900k")
        let event = try #require(
            MinerBestShareEvent.detect(
                device: device, previous: stored,
                current: MinerBestShareObservation(info: info(best: "3.4M", session: "900k")),
                occurredAt: .now
            )
        )
        #expect(event.kind == .allTime)
        #expect(event.rawValue == "3.4M")
        #expect(event.minerName == "Desk miner")
    }

    @Test func aSessionRecordAlertsWhenTheAllTimeRecordIsUnchanged() throws {
        let event = try #require(
            MinerBestShareEvent.detect(
                device: device,
                previous: MinerBestShareObservation(bestDiff: "5M", bestSessionDiff: "100k"),
                current: MinerBestShareObservation(info: info(best: "5M", session: "250k")),
                occurredAt: .now
            )
        )
        #expect(event.kind == .session)
    }

    @Test func anEqualOrLowerShareDoesNotAlert() {
        let baseline = MinerBestShareObservation(bestDiff: "5M", bestSessionDiff: "250k")
        for (best, session) in [("5M", "250k"), ("4M", "100k")] {
            #expect(
                MinerBestShareEvent.detect(
                    device: device, previous: baseline,
                    current: MinerBestShareObservation(info: info(best: best, session: session)),
                    occurredAt: .now
                ) == nil,
                "\(best)/\(session) is not a new record"
            )
        }
    }

    @Test func unparseableTelemetryIsIgnoredRatherThanTreatedAsARecord() {
        #expect(
            MinerBestShareEvent.detect(
                device: device,
                previous: MinerBestShareObservation(bestDiff: "5M", bestSessionDiff: "250k"),
                current: MinerBestShareObservation(info: info(best: "n/a", session: "")),
                occurredAt: .now
            ) == nil
        )
    }

    @Test func detectIgnoresZeroDifficulty() {
        #expect(
            MinerBestShareEvent.detect(
                device: device,
                previous: MinerBestShareObservation(bestDiff: "5M", bestSessionDiff: "250k"),
                current: MinerBestShareObservation(info: info(best: "0", session: "0")),
                occurredAt: .now
            ) == nil
        )
    }

    @Test func detectSelectsAllTimeWhenBothAllTimeAndSessionIncrease() throws {
        let event = try #require(
            MinerBestShareEvent.detect(
                device: device,
                previous: MinerBestShareObservation(bestDiff: "1M", bestSessionDiff: "500k"),
                current: MinerBestShareObservation(info: info(best: "2M", session: "800k")),
                occurredAt: .now
            )
        )
        #expect(event.kind == .allTime)
        #expect(event.rawValue == "2M")
    }

    @Test func observationRoundTripsThroughPersistence() throws {
        let original = MinerBestShareObservation(info: info(best: "1.2M", session: "900k"))
        let decoded = try JSONDecoder().decode(
            MinerBestShareObservation.self, from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
        #expect(decoded.value(for: .allTime) == "1.2M")
        #expect(decoded.value(for: .session) == "900k")
    }

    @Test func notificationContentNamesTheMinerAndRecordWithoutLeakingIdentity() {
        let event = MinerBestShareEvent(
            deviceID: device.id, minerName: "Desk miner", kind: .allTime,
            displayValue: "3.4M", rawValue: "3.4M", occurredAt: .now
        )
        let payload = FleetBestShareNotificationContent(event: event)
        #expect(payload.title == "New best share from Desk miner")
        #expect(payload.body.contains("3.4M"))
        #expect(payload.body.contains("all-time"))
        #expect(payload.identifier.hasPrefix("app.hashfleet.best-share."))
        // No wallet address, worker name, or pool URL belongs in a notification payload.
        for secret in ["192.168.1.10", "bc1", "stratum"] {
            #expect(!payload.body.contains(secret) && !payload.title.contains(secret))
        }
    }

    @Test @MainActor func requestedBestShareDefaultsAreOnAndExplicitOptOutPersists() {
        let suite = "app.hashfleet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FleetPreferences(defaults: defaults)
        // Requested installation default changed. Explicit existing opt-outs still win.
        #expect(preferences.bestShareNotificationsEnabled)
        #expect(preferences.sessionBestNotificationsEnabled)
        #expect(preferences.blockNotificationsEnabled == false)
        preferences.bestShareNotificationsEnabled = false
        #expect(FleetPreferences(defaults: defaults).bestShareNotificationsEnabled == false)
    }

    @Test @MainActor func bothRecordKindsUseTheSameIllustratedPopupWithDistinctLabels() throws {
        let allTime = MinerBestShareEvent(
            deviceID: device.id, minerName: device.name, kind: .allTime,
            displayValue: "3.40M", rawValue: "3.4M", occurredAt: .now)
        let session = MinerBestShareEvent(
            deviceID: device.id, minerName: device.name, kind: .session,
            displayValue: "1.20M", rawValue: "1.2M", occurredAt: .now)
        let highScore = try #require(FleetCelebration(.bestShare(allTime)))
        let sessionBest = try #require(FleetCelebration(.bestShare(session)))
        #expect(highScore.kind == .bestShareAllTime)
        #expect(highScore.eyebrow == "NEW HIGH SCORE")
        #expect(sessionBest.kind == .bestShareSession)
        #expect(sessionBest.eyebrow == "SESSION BEST")
        #expect(sessionBest.value == "1.20M")
        #expect(sessionBest.deviceID == device.id)
        #expect(!sessionBest.isBlock)
    }
}

/// A fleet refresh can detect milestones on several miners in one pass. Posting only the
/// `latest*` event would silently drop every other miner's notification.
@Suite("Multi-miner notification delivery")
@MainActor
struct PendingNotificationEventTests {
    private func store() -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (FleetStore(defaults: defaults), defaults, suite)
    }

    private func event(_ name: String) -> MinerBestShareEvent {
        MinerBestShareEvent(
            deviceID: UUID(), minerName: name, kind: .allTime,
            displayValue: "1M", rawValue: "1M", occurredAt: .now
        )
    }

    private func blockEvent(_ name: String) -> MinerBlockFoundEvent {
        MinerBlockFoundEvent(
            deviceID: UUID(), minerName: name, coinLabel: "BTC",
            height: 900_000, count: 1, occurredAt: .now
        )
    }

    @Test func drainReturnsEveryQueuedEventNotJustTheLatest() {
        let (fleet, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        fleet.pendingBestShareEvents = [event("One"), event("Two"), event("Three")]
        fleet.pendingBlockFoundEvents = [blockEvent("One"), blockEvent("Two")]

        let drained = fleet.drainPendingNotificationEvents()
        #expect(drained.bestShares.map(\.minerName) == ["One", "Two", "Three"])
        #expect(drained.blocksFound.map(\.minerName) == ["One", "Two"])
    }

    @Test func drainClearsTheQueueSoEventsAreNeverDeliveredTwice() {
        let (fleet, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        fleet.pendingBestShareEvents = [event("One")]
        fleet.pendingBlockFoundEvents = [blockEvent("One")]

        #expect(fleet.drainPendingNotificationEvents().bestShares.count == 1)
        let second = fleet.drainPendingNotificationEvents()
        #expect(second.bestShares.isEmpty)
        #expect(second.blocksFound.isEmpty)
        #expect(fleet.pendingBestShareEvents.isEmpty)
        #expect(fleet.pendingBlockFoundEvents.isEmpty)
    }

    @Test func anEmptyQueueDrainsCleanly() {
        let (fleet, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        let drained = fleet.drainPendingNotificationEvents()
        #expect(drained.bestShares.isEmpty && drained.blocksFound.isEmpty)
    }

    @Test func enteringDemoDiscardsQueuedEventsSoDemoDataNeverNotifies() {
        let (fleet, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        fleet.pendingBestShareEvents = [event("Real miner")]
        fleet.pendingBlockFoundEvents = [blockEvent("Real miner")]
        fleet.loadDemo()
        #expect(fleet.pendingBestShareEvents.isEmpty)
        #expect(fleet.pendingBlockFoundEvents.isEmpty)
    }

    @Test func leavingDemoAlsoDiscardsQueuedEvents() {
        let (fleet, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        fleet.loadDemo()
        fleet.pendingBestShareEvents = [event("Demo miner")]
        fleet.clearDemo()
        #expect(fleet.pendingBestShareEvents.isEmpty)
    }
}
