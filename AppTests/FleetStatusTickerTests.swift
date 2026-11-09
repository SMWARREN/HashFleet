import Foundation
import Testing
@testable import HashFleet
import HashFleetCore

/// Pure model tests: states the ticker must render from reported data, and cursor selection.
@MainActor
struct FleetStatusTickerTests {

    private let id = UUID()

    private func device(_ name: String) -> MinerDevice {
        MinerDevice(id: id, name: name, address: "http://10.0.0.42")
    }

    private func onlineSnapshot(_ raw: [String: JSONValue]) -> MinerSnapshot {
        var snapshot = MinerSnapshot()
        snapshot.info = MinerInfo(raw: raw)
        snapshot.updatedAt = Date()
        return snapshot
    }

    private func offlineSnapshot() -> MinerSnapshot {
        MinerSnapshot(info: nil, error: "Could not connect to http://10.0.0.42", updatedAt: Date(), history: [])
    }

    // MARK: - Model states

    @Test func emptyFleetProducesNoItems() {
        let model = FleetStatusTickerModel(devices: [], snapshots: [:])
        #expect(model.items.isEmpty)
    }

    @Test func missingSnapshotIsConnectingNotOffline() {
        // The miner was never polled; claiming "offline" would fabricate a failure.
        let model = FleetStatusTickerModel(devices: [device("Garage")], snapshots: [:])
        let item = model.items.first!
        #expect(item.status == .connecting)
        #expect(item.segments.isEmpty)
        #expect(item.summary.contains("Garage"))
        #expect(item.summary.lowercased().contains("connecting"))
        #expect(!item.summary.lowercased().contains("offline"))
        #expect(!item.summary.contains("10.0.0.42"))
    }

    @Test func errorSnapshotIsOfflineAndHidesRawErrorText() {
        // Connection error strings can embed hosts or URLs; the ticker must never show them.
        let model = FleetStatusTickerModel(devices: [device("Bench")], snapshots: [id: offlineSnapshot()])
        let item = model.items.first!
        #expect(item.status == .offline)
        #expect(!item.summary.contains("10.0.0.42"))
        #expect(!item.summary.contains("Could not connect"))
    }

    @Test(arguments: [false, true])
    func pendingCheckHidesOldErrorAndDoesNotPresentPreviousMetricsAsLive(hadError: Bool) throws {
        var snapshot = onlineSnapshot(["hashRate": .number(512), "power_fault": .string("Old fault")])
        if hadError { snapshot.error = "Could not connect to http://10.0.0.42" }
        snapshot.isReconnecting = true
        let model = FleetStatusTickerModel(devices: [device("Bench")], snapshots: [id: snapshot])
        let item = try #require(model.items.first)
        #expect(item.status == .reconnecting)
        #expect(item.summary.contains("reconnecting"))
        #expect(item.summary.contains("offline") == false)
        #expect(item.summary.contains("10.0.0.42") == false)
        #expect(item.segments.isEmpty)
        #expect(item.notices.isEmpty)
    }

    @Test func infoWithoutErrorIsOnlineEvenWithNoMetrics() {
        let model = FleetStatusTickerModel(devices: [device("Shed")], snapshots: [id: onlineSnapshot([:])])
        let item = model.items.first!
        #expect(item.status == .online)
        #expect(!item.summary.lowercased().contains("offline"))
    }

    @Test func partialReadingsOmitMissingMetrics() {
        // Hashrate only: no power, no shares, no best share placeholders.
        let model = FleetStatusTickerModel(
            devices: [device("Shed")],
            snapshots: [id: onlineSnapshot(["hashRate": .number(512)])]
        )
        let item = model.items.first!
        #expect(item.isOnline)
        #expect(item.segments == ["512 GH/s"])
        #expect(!item.summary.contains("W"))
        #expect(!item.summary.contains("Accepted"))
        #expect(!item.summary.contains("Best"))
    }

    @Test func zeroHashrateIsARealReading() {
        let model = FleetStatusTickerModel(
            devices: [device("Bench")],
            snapshots: [id: onlineSnapshot(["hashRate": .number(0)])]
        )
        #expect(model.items.first!.segments == ["0 GH/s"])
    }

    @Test func fullReadingIncludesAllSegments() {
        let raw: [String: JSONValue] = [
            "hashRate": .number(512.5),
            "power": .integer(14),
            "sharesAccepted": .integer(1234),
            "bestDiff": .string("18.4G")
        ]
        let model = FleetStatusTickerModel(devices: [device("Garage")], snapshots: [id: onlineSnapshot(raw)])
        let item = model.items.first!
        #expect(item.isOnline)
        #expect(item.segments.contains("512.5 GH/s"))
        #expect(item.segments.contains("14 W"))
        #expect(item.segments.contains { $0.hasPrefix("Accepted ") })
        #expect(item.segments.contains("Best 18.40G"))
        #expect(item.notices.isEmpty)
    }

    // MARK: - Reported cautions

    @Test func fallbackStaysInPoolDetailsNotTheMarquee() {
        let raw: [String: JSONValue] = ["hashRate": .number(100), "isUsingFallbackStratum": .integer(1)]
        let model = FleetStatusTickerModel(devices: [device("A")], snapshots: [id: onlineSnapshot(raw)])
        #expect(model.items.first!.notices.isEmpty)
        #expect(!model.items.first!.summary.lowercased().contains("fallback"))
    }

    @Test func pauseAndOverheatNoticesAreReported() {
        let raw: [String: JSONValue] = [
            "hashRate": .number(0),
            "miningPaused": .bool(true),
            "overheat_mode": .bool(true)
        ]
        let model = FleetStatusTickerModel(devices: [device("A")], snapshots: [id: onlineSnapshot(raw)])
        let item = model.items.first!
        #expect(item.notices.contains("Mining paused"))
        #expect(item.notices.contains("Overheat protection active"))
    }

    @Test func faultNoticeNeverEchoesFirmwareMessage() {
        let raw: [String: JSONValue] = [
            "hashRate": .number(100),
            "power_fault": .string("VBUS collapsed at http://10.0.0.99/api")
        ]
        let model = FleetStatusTickerModel(devices: [device("A")], snapshots: [id: onlineSnapshot(raw)])
        let item = model.items.first!
        #expect(item.notices.contains("Power fault reported"))
        #expect(!item.summary.contains("VBUS"))
        #expect(!item.summary.contains("10.0.0.99"))
    }

    // MARK: - Demo

    @Test func demoReadingsAreLabelledSimulated() {
        let model = FleetStatusTickerModel(
            devices: [device("Bench")],
            snapshots: [id: onlineSnapshot(["hashRate": .number(512)])],
            isDemo: true
        )
        let item = model.items.first!
        #expect(item.isSimulated)
        #expect(item.summary.hasPrefix("Simulated:"))
    }

    @Test func liveReadingsAreNotLabelledSimulated() {
        let model = FleetStatusTickerModel(
            devices: [device("Bench")],
            snapshots: [id: onlineSnapshot(["hashRate": .number(512)])]
        )
        #expect(model.items.first!.isSimulated == false)
    }

    // MARK: - Share counts

    @Test(arguments: [
        ("sharesAccepted", JSONValue.integer(42)), ("sharesAccepted", JSONValue.unsignedInteger(7)),
        ("sharesAccepted", JSONValue.string("99"))
    ])
    func exactIntegerShareCountsAreShown(key: String, value: JSONValue) {
        let model = FleetStatusTickerModel(
            devices: [device("A")],
            snapshots: [id: onlineSnapshot([key: value])]
        )
        #expect(model.items.first!.segments.contains { $0.hasPrefix("Accepted ") })
    }

    @Test(arguments: [JSONValue.number(3.9), .number(-1), .bool(true)])
    func fractionalNegativeAndBoolShareCountsAreHidden(payload: JSONValue) {
        let model = FleetStatusTickerModel(
            devices: [device("A")],
            snapshots: [id: onlineSnapshot(["sharesAccepted": payload])]
        )
        #expect(!model.items.first!.segments.contains { $0.hasPrefix("Accepted") })
    }

    // MARK: - Privacy

    @Test func summaryNeverLeaksPoolsHostsOrCredentials() {
        let raw: [String: JSONValue] = [
            "hashRate": .number(512),
            "stratumURL": .string("eusolo.ckpool.org"),
            "stratumUser": .string("bc1qexamplewalletaddress.worker"),
            "stratumPassword": .string("x"),
            "hostname": .string("bitaxe-9f2a")
        ]
        let model = FleetStatusTickerModel(devices: [device("Bench")], snapshots: [id: onlineSnapshot(raw)])
        let summary = model.items.first!.summary
        for secret in ["eusolo.ckpool.org", "bc1qexamplewalletaddress.worker", "bitaxe-9f2a"] {
            #expect(!summary.contains(secret))
        }
        #expect(FleetStatusTickerModel.assertsPrivacy(from: MinerInfo(raw: raw), into: summary))
    }

    @Test(arguments: ["hashRate", "hashrate"])
    func acceptsBothHashrateKeys(_ key: String) {
        let model = FleetStatusTickerModel(
            devices: [device("A")],
            snapshots: [id: onlineSnapshot([key: .number(250)])]
        )
        #expect(model.items.first!.segments.first == "250 GH/s")
    }

    // MARK: - Cursor selection

    @Test func cursorAdvancesAndWraps() {
        var cursor = FleetTickerCursor()
        cursor.advance(itemCount: 3)
        cursor.advance(itemCount: 3)
        #expect(cursor.selected(itemCount: 3) == 2)
        cursor.advance(itemCount: 3)
        #expect(cursor.selected(itemCount: 3) == 0)
    }

    @Test func cursorManualSelectionClamps() {
        var cursor = FleetTickerCursor()
        cursor.select(9, itemCount: 2)
        #expect(cursor.selected(itemCount: 2) == 1)
        cursor.select(-4, itemCount: 2)
        #expect(cursor.selected(itemCount: 2) == 0)
    }

    @Test func cursorHandlesEmptyAndShrinkingFleets() {
        var cursor = FleetTickerCursor()
        #expect(cursor.selected(itemCount: 0) == nil)
        cursor.advance(itemCount: 0)
        #expect(cursor.selected(itemCount: 0) == nil)
        (0..<5).forEach { _ in cursor.advance(itemCount: 5) }
        // The fleet shrank to 2 miners; the cursor must still land on a real item.
        #expect(cursor.selected(itemCount: 2)! < 2)
    }
    @Test func marqueeClockFreezesResumesAndResetsWithoutLosingPausePosition() {
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        var clock = FleetMarqueeClock()
        clock.setRunning(true, at: origin)
        clock.setRunning(false, at: origin.addingTimeInterval(3))
        #expect(clock.elapsed(at: origin.addingTimeInterval(8)) == 3)
        #expect(clock.remaining(in: 12, at: origin.addingTimeInterval(8)) == 9)
        clock.setRunning(false, at: origin.addingTimeInterval(9))
        #expect(clock.elapsed(at: origin.addingTimeInterval(10)) == 3)
        clock.setRunning(true, at: origin.addingTimeInterval(10))
        #expect(clock.elapsed(at: origin.addingTimeInterval(12)) == 5)
        #expect(clock.remaining(in: 12, at: origin.addingTimeInterval(12)) == 7)
        #expect(clock.remaining(in: 12, at: origin.addingTimeInterval(30)) == 0)
        clock.reset(at: origin.addingTimeInterval(12))
        #expect(clock.elapsed(at: origin.addingTimeInterval(13)) == 1)
    }

    @Test func marqueeClockPreservesPhysicalOffsetWhenReadingWidthChanges() {
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        let oldWidth: CGFloat = 300
        let newWidth: CGFloat = 420
        let gap: CGFloat = 30
        let speed = 30.0
        let sampleDate = origin.addingTimeInterval(5)
        var clock = FleetMarqueeClock()
        clock.setRunning(true, at: origin)

        let oldOffset = FleetMarqueeLayout.offset(
            elapsed: clock.elapsed(at: sampleDate),
            copyWidth: oldWidth,
            gap: gap,
            pixelsPerSecond: speed
        )
        clock.preserveOffset(
            from: oldWidth,
            to: newWidth,
            gap: gap,
            at: sampleDate,
            pixelsPerSecond: speed
        )
        let newOffset = FleetMarqueeLayout.offset(
            elapsed: clock.elapsed(at: sampleDate),
            copyWidth: newWidth,
            gap: gap,
            pixelsPerSecond: speed
        )

        #expect(abs(oldOffset - newOffset) < 0.001)
        #expect(clock.isRunning)
    }

    // MARK: - Hardware fault and empty notice handling

    @Test func hardwareFaultNoticeIsReportedAndHidesMessageText() {
        let raw: [String: JSONValue] = [
            "hashRate": .number(250),
            "hardware_fault": .string("ASIC chain 0 communication lost on spi://10.0.0.1")
        ]
        let model = FleetStatusTickerModel(devices: [device("Bench")], snapshots: [id: onlineSnapshot(raw)])
        let item = model.items.first!
        #expect(item.notices.contains("Hardware fault reported"))
        #expect(!item.summary.contains("ASIC chain"))
        #expect(!item.summary.contains("spi://"))
        #expect(!item.summary.contains("10.0.0.1"))
    }

    @Test func emptyAndNullNoticesAreIgnored() {
        let raw: [String: JSONValue] = [
            "hashRate": .number(300),
            "hardware_fault": .string("   \n\t  "),
            "power_fault": .null
        ]
        let model = FleetStatusTickerModel(devices: [device("Bench")], snapshots: [id: onlineSnapshot(raw)])
        let item = model.items.first!
        #expect(item.notices.isEmpty)
    }

    @Test func booleanFlagNoticesRequireTruthyValue() {
        let raw: [String: JSONValue] = [
            "hashRate": .number(300),
            "miningPaused": .bool(false),
            "overheat_mode": .bool(false)
        ]
        let model = FleetStatusTickerModel(devices: [device("Bench")], snapshots: [id: onlineSnapshot(raw)])
        let item = model.items.first!
        #expect(item.notices.isEmpty)
    }

    @Test func mixedFleetPreservesDeviceOrderAndStatus() {
        let dev1 = MinerDevice(name: "Online Miner", address: "10.0.0.1")
        let dev2 = MinerDevice(name: "Connecting Miner", address: "10.0.0.2")
        let dev3 = MinerDevice(name: "Offline Miner", address: "10.0.0.3")

        let snap1 = onlineSnapshot(["hashRate": .number(600), "power": .integer(15)])
        let snap3 = offlineSnapshot()

        let model = FleetStatusTickerModel(
            devices: [dev1, dev2, dev3],
            snapshots: [dev1.id: snap1, dev3.id: snap3]
        )

        #expect(model.items.count == 3)
        #expect(model.items[0].id == dev1.id)
        #expect(model.items[0].status == .online)
        #expect(model.items[0].segments == ["600 GH/s", "15 W"])
        #expect(model.items[1].id == dev2.id)
        #expect(model.items[1].status == .connecting)
        #expect(model.items[2].id == dev3.id)
        #expect(model.items[2].status == .offline)
    }

}
