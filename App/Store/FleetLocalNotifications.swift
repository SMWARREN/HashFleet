import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications
import os
import HashFleetCore

/// Notification delegate ensuring notifications are presented on-screen even when app is active/foreground.
final class FleetNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = FleetNotificationDelegate()

    /// Every record uses the app-wide illustrated celebration, including session records.
    static let sessionBestCategory = "app.hashfleet.sessionBest"
    static let fullScreenCelebratedCategories: Set<String> = [
        "app.hashfleet.block", "app.hashfleet.bestShare", sessionBestCategory
    ]

    /// Foreground presentation. A milestone goes straight to Notification Center only when an
    /// in-app surface is actually showing it; otherwise it banners so it is never silently lost.
    /// Status alerts (offline, power, metric) always banner. The badge is never applied while the
    /// app is open, since it would otherwise stick until the next launch.
    static func foregroundPresentation(
        forCategory category: String, dashboardBannerVisible _: Bool,
        celebrationVisible: Bool = false
    ) -> UNNotificationPresentationOptions {
        if fullScreenCelebratedCategories.contains(category) && celebrationVisible {
            return [.list]
        }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundPresentation(
            forCategory: notification.request.content.categoryIdentifier,
            dashboardBannerVisible: FleetInAppSurface.dashboardBannerVisible,
            celebrationVisible: FleetInAppSurface.celebrationVisible))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let openedMiner = response.actionIdentifier != UNNotificationDismissActionIdentifier
            && FleetNotificationRoute.handle(userInfo: userInfo)
        if !openedMiner { FleetSystemNavigation.request() }
        completionHandler()
    }
}

/// Whether app-wide milestone surfaces are actually visible. The notification delegate can be
/// called off the main thread, so visibility is lock-protected rather than assumed from category.
enum FleetInAppSurface {
    private static let visible = OSAllocatedUnfairLock(initialState: false)
    private static let celebration = OSAllocatedUnfairLock(initialState: false)

    static var dashboardBannerVisible: Bool {
        get { visible.withLock { $0 } }
        set { visible.withLock { $0 = newValue } }
    }

    static var celebrationVisible: Bool {
        get { celebration.withLock { $0 } }
        set { celebration.withLock { $0 = newValue } }
    }
}

/// Notification delivery is deliberately separate from telemetry detection. The detector accepts
/// only an explicit counter increase or firmware notification flag, while this helper owns iOS
/// permission and keeps wallet addresses, worker names, and pool URLs out of the payload.
struct FleetBlockNotificationContent: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String

    init(event: MinerBlockFoundEvent) {
        identifier = "app.hashfleet.block-found.\(event.id.uuidString)"
        title = "Block found by \(event.minerName)"
        let coin = event.coinLabel.map { "\($0) · " } ?? ""
        let height = event.height.map { " at height \(FleetFormat.blockHeight($0))" } ?? ""
        body = "\(coin)The miner explicitly reported a found block\(height)."
    }
}

/// A new personal-best share. This is mining progress rather than block proof, so it is worded
/// as a record and kept separate from the block-found alert.
struct FleetBestShareNotificationContent: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String

    init(event: MinerBestShareEvent) {
        identifier = "app.hashfleet.best-share.\(event.id.uuidString)"
        title = "New best share from \(event.minerName)"
        body = "\(event.displayValue) is a new \(event.kind.title) record."
    }
}

/// Connectivity transitions (offline / back online) are worded as status so they are clearly
/// distinct from milestone alerts. The timestamp tells the user exactly when the miner dropped
/// or recovered, even when the notification is delivered later in the background.
struct FleetStateChangeNotificationContent: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String

    init(event: MinerStateChangeEvent) {
        // One slot per miner: "back online" replaces the "offline" alert instead of leaving a
        // stale disconnect sitting in Notification Center after the miner has recovered.
        identifier = "app.hashfleet.state-change.\(event.deviceID.uuidString)"
        title = "\(event.minerName) \(event.kind.title)"
        let timestamp = event.occurredAt.formatted(date: .abbreviated, time: .shortened)
        switch event.kind {
        case .offline:
            let detail = event.detail.map { ": \($0)." } ?? "."
            body = "Connection lost at \(timestamp)\(detail) Last known readings stay visible."
        case .backOnline:
            body = "Reconnected at \(timestamp). The miner is responding again and readings have resumed."
        }
    }
}

/// A significant dashboard metric change relative to the miner's own baseline.
struct FleetMetricAlertNotificationContent: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String

    init(event: MinerMetricAlertEvent) {
        // One slot per miner and metric, so a flapping reading updates a single alert.
        identifier = "app.hashfleet.metric-alert.\(event.deviceID.uuidString).\(event.kind.rawValue)"
        title = event.title
        body = event.detail
    }
}

@MainActor
enum FleetLocalNotifications {
    private static let center = UNUserNotificationCenter.current()

    static func setup() {
        center.delegate = FleetNotificationDelegate.shared
        // Register the block-found category used by FleetLocalNotifications.post(_: MinerBlockFoundEvent).
        let blockCategory = UNNotificationCategory(
            identifier: "app.hashfleet.block",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let bestShareCategory = UNNotificationCategory(
            identifier: "app.hashfleet.bestShare",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let sessionBestCategory = UNNotificationCategory(
            identifier: FleetNotificationDelegate.sessionBestCategory,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let summaryCategory = UNNotificationCategory(identifier: "app.hashfleet.summary", actions: [], intentIdentifiers: [])
        center.setNotificationCategories([blockCategory, bestShareCategory, sessionBestCategory, summaryCategory])
    }

    static func clearBadge() {
        center.setBadgeCount(0)
    }

    /// Identifiers of every per-miner status slot, matching the notification content types.
    static func statusNotificationIdentifiers(for deviceID: UUID) -> [String] {
        let id = deviceID.uuidString
        return ["app.hashfleet.state-change.\(id)", "app.hashfleet.temperature-alert.\(id)",
                "app.hashfleet.power-alert.\(id)"]
            + ["hashrateStopped", "hashrateDrop", "powerSpike", "efficiencyDrop"]
                .map { "app.hashfleet.metric-alert.\(id).\($0)" }
    }

    static func removeStatusNotifications(for deviceID: UUID) {
        let identifiers = statusNotificationIdentifiers(for: deviceID)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    static func requestAuthorization() async -> Bool {
        setup()
        return await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    static func post(_ event: MinerBlockFoundEvent) {
        let payload = FleetBlockNotificationContent(event: event)
        let celebration = FleetCelebration(event)
        post(
            identifier: payload.identifier,
            title: "🎉 " + payload.title,
            body: payload.body + " Tap to celebrate.",
            badge: 1,
            interruptionLevel: .timeSensitive,
            categoryIdentifier: "app.hashfleet.block",
            userInfo: celebration.userInfo,
            attachmentArt: .fleetCluster
        )
    }

    static func post(_ event: MinerBestShareEvent) {
        let payload = FleetBestShareNotificationContent(event: event)
        let celebration = FleetCelebration(event)
        post(
            identifier: payload.identifier,
            title: "🏆 " + payload.title,
            body: payload.body + " Tap to see your high score.",
            interruptionLevel: .active,
            categoryIdentifier: event.kind == .allTime
                ? "app.hashfleet.bestShare" : FleetNotificationDelegate.sessionBestCategory,
            userInfo: celebration.userInfo,
            attachmentArt: .brand
        )
    }

    static func post(_ event: MinerStateChangeEvent) {
        let payload = FleetStateChangeNotificationContent(event: event)
        post(
            identifier: payload.identifier,
            title: payload.title,
            body: payload.body,
            // Recovery explicitly clears the badge the offline alert set, since the badge is
            // app-wide state that replacing the notification alone does not reset.
            badge: event.kind == .offline ? 1 : 0,
            interruptionLevel: event.kind == .offline ? .timeSensitive : .active,
            userInfo: [FleetCelebration.userInfoDevice: event.deviceID.uuidString]
        )
    }

    static func post(_ event: MinerTemperatureAlertEvent) {
        let payload = FleetTemperatureAlertNotificationContent(event: event)
        post(identifier: payload.identifier, title: payload.title, body: payload.body,
             userInfo: [FleetCelebration.userInfoDevice: event.deviceID.uuidString],
             attachmentArt: .minerCooling)
    }

    static func post(_ event: MinerPowerAlertEvent) {
        let payload = FleetPowerAlertNotificationContent(event: event)
        post(identifier: payload.identifier, title: payload.title, body: payload.body,
             userInfo: [FleetCelebration.userInfoDevice: event.deviceID.uuidString])
    }

    static func post(_ event: MinerMetricAlertEvent) {
        let payload = FleetMetricAlertNotificationContent(event: event)
        post(identifier: payload.identifier, title: payload.title, body: payload.body,
             userInfo: [FleetCelebration.userInfoDevice: event.deviceID.uuidString])
    }

    /// Scheduling success is not proof of display. Leave the app or lock the phone within five seconds.
    static func postTestNotification() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            post(
                identifier: "app.hashfleet.notification-test",
                title: "Hash Fleet test notification",
                body: "This is a test notification, not a block-found or best-share alert. "
                    + "Your miners and alert preferences have not changed.",
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            ) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func post(
        identifier: String,
        title: String,
        body: String,
        trigger: UNNotificationTrigger? = nil,
        badge: NSNumber? = nil,
        interruptionLevel: UNNotificationInterruptionLevel? = nil,
        categoryIdentifier: String? = nil,
        userInfo: [String: String] = [:],
        attachmentArt: FleetArtLoop? = nil,
        completion: (@Sendable (Error?) -> Void)? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let badge { content.badge = badge }
        if let interruptionLevel { content.interruptionLevel = interruptionLevel }
        if let categoryIdentifier { content.categoryIdentifier = categoryIdentifier }
        if !userInfo.isEmpty { content.userInfo = userInfo }
        if let attachmentArt, let attachment = FleetNotificationArt.attachment(for: attachmentArt) {
            content.attachments = [attachment]
        }
        center.add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger),
            withCompletionHandler: completion
        )
    }
}
