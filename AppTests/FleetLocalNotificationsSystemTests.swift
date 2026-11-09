import Foundation
import Testing
import UserNotifications
import HashFleetCore
@testable import HashFleet

/// Closes the loop that FleetNotificationDeliveryTests leaves open: those tests only verify the
/// in-memory dispatch decision through injected closures, never that a real notification request
/// reaches UNUserNotificationCenter. This suite calls FleetLocalNotifications.post(_:) directly,
/// the same entry point FleetNotificationDelivery.consume uses in production, and inspects the
/// live system notification center's pending request queue, exactly what iOS Notification Center,
/// Lock Screen, and banner presentation are driven from.
@Suite("Real UNUserNotificationCenter delivery", .serialized)
@MainActor
struct FleetLocalNotificationsSystemTests {
    private let center = UNUserNotificationCenter.current()

    /// requestAuthorization() shows a blocking system prompt the first time it runs on a fresh
    /// simulator, which would hang CI. This checks the *current* authorization status instead,
    /// so the suite only exercises real delivery once a human (or a provisioned test device/
    /// simulator) has already granted permission, and otherwise records the constraint rather
    /// than a false pass or an indefinite hang.
    private func requireAuthorization() async -> Bool {
        FleetLocalNotifications.setup()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    private func drainPending() async {
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier })
    }

    private func pendingRequest(identifier: String) async -> UNNotificationRequest? {
        if let match = await center.pendingNotificationRequests().first(where: { $0.identifier == identifier }) {
            return match
        }
        // A request with no trigger (the case for every FleetLocalNotifications.post call) is
        // delivered immediately rather than staying in the pending queue, so the real signal
        // that iOS actually processed it is the delivered-notifications list.
        return await center.deliveredNotifications().first { $0.request.identifier == identifier }?.request
    }

    @Test func blockFoundEventReachesTheRealNotificationCenter() async throws {
        try #require(await requireAuthorization(), "Notification permission was not granted on this simulator/device; run the app once and tap Allow, then re-run this suite.")
        await drainPending()
        let event = MinerBlockFoundEvent(
            deviceID: UUID(), minerName: "Real Delivery Miner", coinLabel: "BTC",
            height: 901_234, count: 1, occurredAt: .now
        )
        FleetLocalNotifications.post(event)
        // UNUserNotificationCenter.add is asynchronous internally; poll briefly for the
        // request to land rather than assuming a fixed delay.
        var request: UNNotificationRequest?
        for _ in 0..<20 {
            request = await pendingRequest(identifier: FleetBlockNotificationContent(event: event).identifier)
            if request != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(request != nil, "A block-found event must produce a real UNNotificationRequest, not just an in-memory dispatch decision.")
        #expect(request?.content.title.isEmpty == false)
        #expect(request?.content.title.contains("Real Delivery Miner") == true)
        #expect(request?.content.categoryIdentifier == "app.hashfleet.block")
        await drainPending()
    }

    @Test func bestShareEventReachesTheRealNotificationCenter() async throws {
        try #require(await requireAuthorization(), "Notification permission was not granted on this simulator/device; run the app once and tap Allow, then re-run this suite.")
        await drainPending()
        let event = MinerBestShareEvent(
            deviceID: UUID(), minerName: "Real Delivery Miner", kind: .allTime,
            displayValue: "3M", rawValue: "3M", occurredAt: .now
        )
        FleetLocalNotifications.post(event)
        var request: UNNotificationRequest?
        for _ in 0..<20 {
            request = await pendingRequest(identifier: FleetBestShareNotificationContent(event: event).identifier)
            if request != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(request != nil, "A best-share event must produce a real UNNotificationRequest.")
        await drainPending()
    }

    @Test func offlineEventReachesTheRealNotificationCenterWithTimestampAndMinerName() async throws {
        try #require(await requireAuthorization(), "Notification permission was not granted on this simulator/device; run the app once and tap Allow, then re-run this suite.")
        await drainPending()
        let occurredAt = Date()
        let event = MinerStateChangeEvent(
            deviceID: UUID(), minerName: "Garage Bitaxe", kind: .offline,
            detail: "Connection timed out", occurredAt: occurredAt
        )
        FleetLocalNotifications.post(event)
        var request: UNNotificationRequest?
        for _ in 0..<20 {
            request = await pendingRequest(identifier: FleetStateChangeNotificationContent(event: event).identifier)
            if request != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(request != nil, "An offline transition must produce a real UNNotificationRequest.")
        #expect(request?.content.title.contains("Garage Bitaxe") == true, "The disconnect notification title must name which miner disconnected.")
        #expect(request?.content.body.contains("Connection lost") == true, "The disconnect notification body must state when it disconnected.")
        #expect(request?.content.body.contains("Connection timed out") == true, "The disconnect notification body must include the disconnect reason.")
        #expect(request?.content.badge == 1, "Offline is time-sensitive and should carry a badge.")
        await drainPending()
    }

    @Test func powerAlertEventReachesTheRealNotificationCenter() async throws {
        try #require(await requireAuthorization(), "Notification permission was not granted on this simulator/device; run the app once and tap Allow, then re-run this suite.")
        await drainPending()
        let event = MinerPowerAlertEvent(
            deviceID: UUID(), minerName: "Garage Bitaxe", kind: .exceeded,
            watts: 3200, thresholdWatts: 3000, occurredAt: .now
        )
        FleetLocalNotifications.post(event)
        var request: UNNotificationRequest?
        for _ in 0..<20 {
            request = await pendingRequest(identifier: FleetPowerAlertNotificationContent(event: event).identifier)
            if request != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(request != nil, "A power-threshold event must produce a real UNNotificationRequest.")
        await drainPending()
    }

    @Test func temperatureAlertEventReachesTheRealNotificationCenter() async throws {
        try #require(await requireAuthorization(), "Notification permission was not granted on this simulator/device; run the app once and tap Allow, then re-run this suite.")
        await drainPending()
        let event = MinerTemperatureAlertEvent(
            deviceID: UUID(), minerName: "Thermal Miner", temperatureCelsius: 85,
            thresholdCelsius: 75, occurredAt: .now
        )
        FleetLocalNotifications.post(event)
        var request: UNNotificationRequest?
        for _ in 0..<20 {
            request = await pendingRequest(identifier: FleetTemperatureAlertNotificationContent(event: event).identifier)
            if request != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(request != nil, "A temperature-threshold event must produce a real UNNotificationRequest.")
        #expect(request?.content.title.contains("Thermal Miner") == true)
        #expect(request?.content.body.contains("85 °C") == true)
        await drainPending()
    }

    @Test func metricAlertEventReachesTheRealNotificationCenter() async throws {
        try #require(await requireAuthorization(), "Notification permission was not granted on this simulator/device; run the app once and tap Allow, then re-run this suite.")
        await drainPending()
        let event = MinerMetricAlertEvent(
            deviceID: UUID(), minerName: "Metric Miner", kind: .hashrateDrop,
            title: "Hashrate drop on Metric Miner",
            detail: "Hashrate fell 40% below recent baseline.", occurredAt: .now
        )
        FleetLocalNotifications.post(event)
        var request: UNNotificationRequest?
        for _ in 0..<20 {
            request = await pendingRequest(identifier: FleetMetricAlertNotificationContent(event: event).identifier)
            if request != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(request != nil, "A metric alert event must produce a real UNNotificationRequest.")
        #expect(request?.content.title.contains("Metric Miner") == true)
        #expect(request?.content.body.contains("Hashrate fell") == true)
        await drainPending()
    }

    @Test func statusNotificationsAreClearedForSpecificDevice() async throws {
        try #require(await requireAuthorization(), "Notification permission was not granted on this simulator/device; run the app once and tap Allow, then re-run this suite.")
        await drainPending()
        let deviceID = UUID()
        let identifiers = FleetLocalNotifications.statusNotificationIdentifiers(for: deviceID)
        #expect(!identifiers.isEmpty)
        let powerEvent = MinerPowerAlertEvent(
            deviceID: deviceID, minerName: "Desk Rig", kind: .exceeded,
            watts: 200, thresholdWatts: 150, occurredAt: .now
        )
        FleetLocalNotifications.post(powerEvent)
        let powerID = FleetPowerAlertNotificationContent(event: powerEvent).identifier
        var request: UNNotificationRequest?
        for _ in 0..<20 {
            request = await pendingRequest(identifier: powerID)
            if request != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(request != nil)
        FleetLocalNotifications.removeStatusNotifications(for: deviceID)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await pendingRequest(identifier: powerID) == nil)
        await drainPending()
    }

    @Test func recoveryReplacesTheOfflineAlertInTheRealNotificationCenter() async throws {
        try #require(await requireAuthorization(), "Notification permission was not granted on this simulator/device; run the app once and tap Allow, then re-run this suite.")
        await drainPending()
        let deviceID = UUID()
        let offline = MinerStateChangeEvent(
            deviceID: deviceID, minerName: "Garage Bitaxe", kind: .offline,
            detail: "Connection timed out", occurredAt: .now)
        let recovered = MinerStateChangeEvent(
            deviceID: deviceID, minerName: "Garage Bitaxe", kind: .backOnline, occurredAt: .now)
        let identifier = FleetStateChangeNotificationContent(event: offline).identifier
        FleetLocalNotifications.post(offline)
        FleetLocalNotifications.post(recovered)

        // iOS keeps one request per identifier. After recovery exactly one notification exists
        // for this miner and it is the "back online" message, not a lingering disconnect.
        var matching: [UNNotificationRequest] = []
        for _ in 0..<40 {
            let pending = await center.pendingNotificationRequests().filter { $0.identifier == identifier }
            let delivered = await center.deliveredNotifications()
                .map(\.request).filter { $0.identifier == identifier }
            matching = pending + delivered
            if matching.count == 1, matching.first?.content.body.contains("Reconnected") == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(matching.count == 1, "Offline and recovery for one miner must occupy a single notification.")
        #expect(matching.first?.content.body.contains("Reconnected") == true,
                "The surviving notification must be the recovery, not the stale offline alert.")
        #expect(matching.first?.content.badge == 0, "Recovery must clear the badge the offline alert set.")
        await drainPending()
    }

    @Test func sessionAndAllTimeBestsUseDistinctForegroundCategories() async throws {
        try #require(await requireAuthorization(), "Notification permission was not granted on this simulator/device; run the app once and tap Allow, then re-run this suite.")
        await drainPending()
        let deviceID = UUID()
        let session = MinerBestShareEvent(
            deviceID: deviceID, minerName: "Desk", kind: .session,
            displayValue: "2M", rawValue: "2M", occurredAt: .now)
        let allTime = MinerBestShareEvent(
            deviceID: deviceID, minerName: "Desk", kind: .allTime,
            displayValue: "3M", rawValue: "3M", occurredAt: .now)
        FleetLocalNotifications.post(session)
        FleetLocalNotifications.post(allTime)
        var sessionRequest: UNNotificationRequest?
        var allTimeRequest: UNNotificationRequest?
        for _ in 0..<40 {
            sessionRequest = await pendingRequest(identifier: FleetBestShareNotificationContent(event: session).identifier)
            allTimeRequest = await pendingRequest(identifier: FleetBestShareNotificationContent(event: allTime).identifier)
            if sessionRequest != nil, allTimeRequest != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(sessionRequest?.content.categoryIdentifier == FleetNotificationDelegate.sessionBestCategory)
        #expect(allTimeRequest?.content.categoryIdentifier == "app.hashfleet.bestShare")
        await drainPending()
    }

    @Test func foregroundOfflineUsesOnlyInAppAndBackgroundRecoveryUsesOnlyTheSystem() async throws {
        try #require(await requireAuthorization(), "Notification permission must be granted for the real delivery-path test.")
        await drainPending()
        let suite = "app.hashfleet.real-delivery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FleetStore(defaults: defaults)
        store.preferences.stateChangeNotificationsEnabled = true
        try store.add(name: "Surface Test Miner", address: "surface-test.local")
        let device = try #require(store.devices.first)
        store.recordSuccessfulInfo(MinerInfo(raw: ["hashRate": .number(500)]), for: device.id, at: .now)
        _ = store.drainPendingNotificationEvents()

        store.recordFailedInfo("Connection timed out", for: device.id)
        var presented: [FleetNotificationEvent] = []
        FleetNotificationDelivery.consume(from: store, isActive: true,
                                          presentInApp: { presented.append($0) })
        let event = try #require(presented.first, "The foreground outage must reach the in-app surface.")
        guard case .stateChange(let offline) = event else {
            Issue.record("The foreground surface received the wrong alert type.")
            await drainPending()
            return
        }
        #expect(offline.kind == .offline)
        #expect(presented.count == 1)
        let identifier = FleetStateChangeNotificationContent(event: offline).identifier
        try await Task.sleep(for: .milliseconds(150))
        #expect(await pendingRequest(identifier: identifier) == nil,
                "A foreground banner must not also queue an iOS notification.")

        FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store)
        #expect(await pendingRequest(identifier: identifier) == nil,
                "Returning to the background must not replay an already-shown foreground alert.")

        store.recordSuccessfulInfo(MinerInfo(raw: ["hashRate": .number(500)]), for: device.id, at: .now)
        FleetNotificationDelivery.consume(from: store, isActive: false,
                                          presentInApp: { _ in Issue.record("Background recovery appeared in-app.") })
        var requests: [UNNotificationRequest] = []
        for _ in 0..<40 {
            let pending = await center.pendingNotificationRequests().filter { $0.identifier == identifier }
            let delivered = await center.deliveredNotifications().map(\.request)
                .filter { $0.identifier == identifier }
            requests = pending + delivered
            if requests.count == 1, requests.first?.content.body.contains("Reconnected") == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(requests.count == 1, "The background recovery must reach the real system exactly once.")
        #expect(requests.first?.content.body.contains("Reconnected") == true)
        #expect(presented.count == 1, "The background event must not add a second in-app banner.")
        await drainPending()
    }
}
