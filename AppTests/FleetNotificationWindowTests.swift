import SwiftUI
import Testing
import UIKit
import HashFleetCore
@testable import HashFleet

@Suite("App-wide foreground notification layer")
@MainActor
struct FleetNotificationWindowTests {
    @Test func allFourTemperatureWarningsAreRetainedUntilAcknowledged() {
        let center = FleetInAppAlertCenter()
        let events = (1...4).map { index in
            MinerTemperatureAlertEvent(deviceID: UUID(), minerName: "Sample \(index)",
                temperatureCelsius: 80, thresholdCelsius: 75, occurredAt: .now)
        }
        events.forEach { center.present(FleetInAppAlert(.temperature($0))) }
        #expect(center.alerts.count == 3 && center.pendingAlertCount == 1)
        #expect(center.alerts.allSatisfy { $0.requiresAcknowledgement })
        center.dismiss(events.last!.id)
        #expect(center.pendingAlertCount == 0)
        #expect(center.alerts.contains { $0.id == events.first!.id })
    }

    @Test func emptyWindowPassesThroughToolbarAndContentTouches() {
        let window = FleetNotificationWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        #expect(!window.handles(CGPoint(x: 200, y: 40)))
        #expect(!window.handles(CGPoint(x: 200, y: 500)))
        #expect(window.hitTest(CGPoint(x: 200, y: 500), with: nil) == nil)
    }

    @Test func onlyBannerRegionInterceptsTouches() {
        let window = FleetNotificationWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.interactiveRegions = [CGRect(x: 16, y: 110, width: 368, height: 90)]
        #expect(window.handles(CGPoint(x: 200, y: 150)))
        #expect(!window.handles(CGPoint(x: 200, y: 70)), "Toolbar must remain usable")
        #expect(!window.handles(CGPoint(x: 200, y: 500)), "Sheet content must remain usable")
        window.interactiveRegions = []
        #expect(!window.handles(CGPoint(x: 200, y: 150)), "Dismissed banners release their hit regions")
    }

    @Test func celebrationOwnsTouchesOnlyWhileVisible() {
        let window = FleetNotificationWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.capturesAllTouches = true
        #expect(window.handles(CGPoint(x: 200, y: 500)))
        window.capturesAllTouches = false
        #expect(!window.handles(CGPoint(x: 200, y: 500)))
    }

    @Test func alertWindowAttachesToSceneWithoutTakingKeyboardFocus() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.keyWindow
        let coordinator = FleetNotificationWindowHost<EmptyView>.Coordinator()
        defer { coordinator.detach() }
        coordinator.update(content: AnyView(EmptyView()), isEnabled: true, capturesAllTouches: false)
        coordinator.attach(to: scene)
        let window = try #require(coordinator.window)
        #expect(window.windowScene === scene)
        #expect(window.frame == scene.coordinateSpace.bounds)
        #expect(window.bounds.width > 0 && window.bounds.height > 0)
        #expect(window.windowLevel > .alert)
        #expect(!window.isHidden)
        #expect(!window.isKeyWindow)
        #expect(scene.keyWindow === originalKeyWindow)
        coordinator.update(content: AnyView(EmptyView()), isEnabled: false, capturesAllTouches: false)
        #expect(window.isHidden, "Backgrounding must hide the notification window")
        coordinator.detach()
        #expect(coordinator.window == nil)
        #expect(window.rootViewController == nil)
    }

    @Test func sessionRecordsUseAppWideDeliveryWithoutADashboard() throws {
        let suite = "app.hashfleet.global-alert-test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        store.preferences.bestShareNotificationsEnabled = true
        let miner = MinerDevice(name: "Sample miner", address: "sample.local")
        store.devices.append(miner)
        let event = MinerBestShareEvent(deviceID: miner.id, minerName: miner.name, kind: .session,
                                       displayValue: "2M", rawValue: "2M", occurredAt: .now)
        store.enqueueNotification(.bestShare(event))
        store.pendingBestShareEvents.append(event)
        let center = FleetInAppAlertCenter()
        var popups = FleetCelebrationQueue()
        FleetNotificationDelivery.consume(from: store, isActive: true,
            postBestShare: { _ in Issue.record("Foreground event must not also push") },
            presentInApp: {
                if let celebration = FleetCelebration($0) { popups.present(celebration) } else { center.present(FleetInAppAlert($0)) }
            })
        #expect(center.alerts.isEmpty, "Session records must not use the brief notification toast.")
        #expect(popups.current?.id == event.id)
        #expect(popups.current?.kind == .bestShareSession)
        #expect(popups.current?.minerName == miner.name)
        #expect(store.isInAppNotificationDelivered(.bestShare(event)))
        FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store, isActive: true,
            presentInApp: { _ in Issue.record("Returning to the app must not duplicate the record") })
        #expect(popups.current?.id == event.id, "The popup stays until the user acknowledges it.")
        popups.dismiss()
        #expect(popups.current == nil)
    }
}
