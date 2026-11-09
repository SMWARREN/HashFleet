import Foundation
import Testing
@testable import HashFleetCore

@Suite("One channel per block across app and push extension")
struct FleetSharedStoreChannelTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "app.hashfleet.channel-tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func aBlockCanBeAnnouncedOnlyOnce() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = FleetSharedStore.blockKey(deviceID: UUID(), count: 3)
        #expect(FleetSharedStore.claimBlockAnnouncement(key, defaults: defaults))
        // Whichever process claims second (app or extension) must stay silent.
        #expect(!FleetSharedStore.claimBlockAnnouncement(key, defaults: defaults))
    }

    @Test func differentBlocksAreIndependent() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = UUID()
        #expect(FleetSharedStore.claimBlockAnnouncement(FleetSharedStore.blockKey(deviceID: device, count: 1), defaults: defaults))
        #expect(FleetSharedStore.claimBlockAnnouncement(FleetSharedStore.blockKey(deviceID: device, count: 2), defaults: defaults))
        #expect(FleetSharedStore.claimBlockAnnouncement(FleetSharedStore.blockKey(deviceID: UUID(), count: 1), defaults: defaults))
    }

    @Test func blockKeysPreferHeightAndUseAQuantizedBootEpochAsFallback() {
        let device = UUID()

        // Pollers can observe the same height with different counters and uptime values.
        #expect(FleetSharedStore.blockKey(
            deviceID: device, count: 1, height: 100, uptimeSeconds: 300
        ) == FleetSharedStore.blockKey(
            deviceID: device, count: 2, height: 100, uptimeSeconds: 301
        ))
        #expect(FleetSharedStore.blockKey(
            deviceID: device, count: 1, height: 100, uptimeSeconds: 300
        ) != FleetSharedStore.blockKey(
            deviceID: device, count: 1, height: 101, uptimeSeconds: 300
        ))

        // Older firmware without height gets a reboot-aware fallback instead of reusing count 1.
        #expect(FleetSharedStore.blockKey(
            deviceID: device, count: 1, uptimeSeconds: 60
        ) != FleetSharedStore.blockKey(
            deviceID: device, count: 1, uptimeSeconds: 120
        ))

        // Flag-only responses remain stable for pollers in the same minute window.
        #expect(FleetSharedStore.blockKey(
            deviceID: device, count: nil, uptimeSeconds: 180
        ) == FleetSharedStore.blockKey(
            deviceID: device, count: nil, uptimeSeconds: 239
        ))
    }

    @Test func sharedObservationChangesBootIdentityAfterReset() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = UUID()
        let first = MinerInfo(raw: [
            "blockFound": .integer(1), "uptimeSeconds": .integer(600)
        ])
        let reset = MinerInfo(raw: [
            "blockFound": .integer(0), "uptimeSeconds": .integer(5)
        ])
        let afterReset = MinerInfo(raw: [
            "blockFound": .integer(1), "uptimeSeconds": .integer(20)
        ])
        let firstIdentity = FleetSharedStore.observeBlock(deviceID: device, info: first, defaults: defaults)
        _ = FleetSharedStore.observeBlock(deviceID: device, info: reset, defaults: defaults)
        let resetIdentity = FleetSharedStore.observeBlock(deviceID: device, info: afterReset, defaults: defaults)

        #expect(firstIdentity?.bootID != resetIdentity?.bootID)
        #expect(FleetSharedStore.blockKey(
            deviceID: device, count: 1, bootID: firstIdentity?.bootID
        ) != FleetSharedStore.blockKey(
            deviceID: device, count: 1, bootID: resetIdentity?.bootID
        ))
    }

    @Test func flagOnlyEventsGetStableDistinctIdentities() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = UUID()
        _ = FleetSharedStore.observeBlock(deviceID: device, info: MinerInfo(raw: [
            "showNewBlock": .bool(false), "uptimeSeconds": .integer(10)
        ]), defaults: defaults)
        let first = FleetSharedStore.observeBlock(deviceID: device, info: MinerInfo(raw: [
            "showNewBlock": .bool(true), "uptimeSeconds": .integer(20)
        ]), defaults: defaults)
        let replay = FleetSharedStore.observeBlock(deviceID: device, info: MinerInfo(raw: [
            "showNewBlock": .bool(true), "uptimeSeconds": .integer(21)
        ]), defaults: defaults)
        _ = FleetSharedStore.observeBlock(deviceID: device, info: MinerInfo(raw: [
            "showNewBlock": .bool(false), "uptimeSeconds": .integer(30)
        ]), defaults: defaults)
        let second = FleetSharedStore.observeBlock(deviceID: device, info: MinerInfo(raw: [
            "showNewBlock": .bool(true), "uptimeSeconds": .integer(40)
        ]), defaults: defaults)

        #expect(first?.eventID != nil)
        #expect(first?.eventID == replay?.eventID)
        #expect(first?.eventID != second?.eventID)
    }

    @Test func counterEventsGetStableDistinctIdentities() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = UUID()
        _ = FleetSharedStore.observeBlock(deviceID: device, info: MinerInfo(raw: [
            "blockFound": .integer(0), "uptimeSeconds": .integer(10)
        ]), defaults: defaults)
        let first = FleetSharedStore.observeBlock(deviceID: device, info: MinerInfo(raw: [
            "blockFound": .integer(1), "uptimeSeconds": .integer(20)
        ]), defaults: defaults)
        let replay = FleetSharedStore.observeBlock(deviceID: device, info: MinerInfo(raw: [
            "blockFound": .integer(1), "uptimeSeconds": .integer(21)
        ]), defaults: defaults)
        let second = FleetSharedStore.observeBlock(deviceID: device, info: MinerInfo(raw: [
            "blockFound": .integer(2), "uptimeSeconds": .integer(30)
        ]), defaults: defaults)

        #expect(first?.eventID != nil)
        #expect(first?.eventID == replay?.eventID)
        #expect(first?.eventID != second?.eventID)
    }

    @Test func appActiveHeartbeatExpiresSoTheExtensionResumes() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        #expect(!FleetSharedStore.isAppActive(now: now, defaults: defaults))
        FleetSharedStore.markAppActive(true, now: now, defaults: defaults)
        #expect(FleetSharedStore.isAppActive(now: now.addingTimeInterval(30), defaults: defaults))
        // A crashed or suspended app stops refreshing; the extension must resume pushing.
        #expect(!FleetSharedStore.isAppActive(
            now: now.addingTimeInterval(FleetSharedStore.appActiveHeartbeat + 1), defaults: defaults))
        FleetSharedStore.markAppActive(true, now: now, defaults: defaults)
        FleetSharedStore.markAppActive(false, now: now, defaults: defaults)
        #expect(!FleetSharedStore.isAppActive(now: now, defaults: defaults))
    }
}
