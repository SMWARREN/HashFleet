import Foundation
import Testing
import UIKit
import UserNotifications
@testable import HashFleet

/// Test-notification delivery flow tests, split from FleetNotificationSettingsTests for
/// type_body_length. Shares the same Fixture harness and behavior contract.
@Suite("Notification settings: test delivery") @MainActor
struct FleetNotificationTestDeliveryTests {
    @MainActor private final class Fixture {
        let suite = "app.hashfleet.notification-settings.tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let preferences: FleetPreferences
        var access = FleetNotificationSettingsModel.Access(authorization: .notDetermined)
        var background: UIBackgroundRefreshStatus = .available
        var requestCount = 0
        var readCount = 0
        var grant = true
        var requestError: Error?
        var pendingRequest: CheckedContinuation<Bool, Error>?
        var suspendRequest = false
        var postCount = 0
        var postError: Error?
        var suspendPost = false
        var pendingPost: CheckedContinuation<Void, Error>?

        init(explicitOptOut: Bool = true) {
            defaults = UserDefaults(suiteName: suite)!
            preferences = FleetPreferences(defaults: defaults)
            if explicitOptOut {
                // These permission tests deliberately exercise saved opt-outs, not old defaults.
                preferences.bestShareNotificationsEnabled = false
                preferences.sessionBestNotificationsEnabled = false
            }
        }

        func cleanup() { defaults.removePersistentDomain(forName: suite) }

        func model() -> FleetNotificationSettingsModel {
            FleetNotificationSettingsModel(
                preferences: preferences,
                readAccess: {
                    self.readCount += 1
                    return self.access
                },
                requestAccess: {
                    self.requestCount += 1
                    if let error = self.requestError { throw error }
                    if self.suspendRequest {
                        return try await withCheckedThrowingContinuation { self.pendingRequest = $0 }
                    }
                    self.access = .init(authorization: self.grant ? .authorized : .denied)
                    return self.grant
                },
                readBackgroundStatus: { self.background },
                postTestNotification: {
                    self.postCount += 1
                    if let error = self.postError { throw error }
                    if self.suspendPost {
                        try await withCheckedThrowingContinuation { self.pendingPost = $0 }
                    }
                }
            )
        }
    }
    @Test(arguments: [UNAuthorizationStatus.authorized, .provisional, .ephemeral])
    func testNotificationUsesPostingRouteWithBothAlertsOff(authorization: UNAuthorizationStatus) async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.access = .init(authorization: authorization)
        let model = fixture.model()
        await model.sendTestNotification()
        #expect(fixture.postCount == 1)
        #expect(fixture.requestCount == 0)
        #expect(model.testNotificationState == .queued)
        #expect(!model.isSelected(.blockFound))
        #expect(!model.isSelected(.bestShare))
        #expect(!model.isRequesting)
    }

    @Test(arguments: [false, true], [false, true])
    func testNotificationPreservesEverySavedAlertCombination(blockEnabled: Bool, bestShareEnabled: Bool) async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.preferences.blockNotificationsEnabled = blockEnabled
        fixture.preferences.bestShareNotificationsEnabled = bestShareEnabled
        fixture.access = .init(authorization: .authorized)
        let model = fixture.model()
        await model.sendTestNotification()
        #expect(fixture.postCount == 1)
        #expect(model.isSelected(.blockFound) == blockEnabled)
        #expect(model.isSelected(.bestShare) == bestShareEnabled)
        let saved = FleetPreferences(defaults: fixture.defaults)
        #expect(saved.blockNotificationsEnabled == blockEnabled)
        #expect(saved.bestShareNotificationsEnabled == bestShareEnabled)
    }

    @Test(arguments: [false, true], [false, true])
    func testNotificationPreservesSessionAndGlobalChoices(globalEnabled: Bool, sessionEnabled: Bool) async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.preferences.bestShareNotificationsEnabled = globalEnabled
        fixture.preferences.sessionBestNotificationsEnabled = sessionEnabled
        fixture.access = .init(authorization: .authorized)
        await fixture.model().sendTestNotification()
        let saved = FleetPreferences(defaults: fixture.defaults)
        #expect(fixture.postCount == 1)
        #expect(saved.bestShareNotificationsEnabled == globalEnabled)
        #expect(saved.sessionBestNotificationsEnabled == sessionEnabled)
    }

    @Test func testNotificationPreservesFreshDefaultSelections() async {
        let fixture = Fixture(explicitOptOut: false)
        defer { fixture.cleanup() }
        #expect(fixture.preferences.bestShareNotificationsEnabled)
        #expect(fixture.preferences.sessionBestNotificationsEnabled)
        await fixture.model().sendTestNotification()
        #expect(fixture.postCount == 1)
        let saved = FleetPreferences(defaults: fixture.defaults)
        #expect(saved.bestShareNotificationsEnabled)
        #expect(saved.sessionBestNotificationsEnabled)
        #expect(!saved.blockNotificationsEnabled)
    }

    @Test func testNotificationRequestsPermissionThenPostsWithoutOptingIntoAlerts() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model()
        await model.sendTestNotification()
        #expect(fixture.requestCount == 1)
        #expect(fixture.postCount == 1)
        #expect(model.access?.authorization == .authorized)
        #expect(model.testNotificationState == .queued)
        #expect(!model.isSelected(.blockFound))
        #expect(!model.isSelected(.bestShare))
    }

    @Test func deniedTestNotificationExplainsSettingsRecoveryWithoutPostingOrErasingChoices() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.access = .init(authorization: .denied)
        fixture.preferences.bestShareNotificationsEnabled = true
        let model = fixture.model()
        await model.sendTestNotification()
        #expect(fixture.requestCount == 0)
        #expect(fixture.postCount == 0)
        #expect(model.testNotificationState == .blocked)
        #expect(model.testNotificationState.message?.contains("Open Settings") == true)
        #expect(model.isSelected(.bestShare))
        #expect(!model.isSelected(.blockFound))
        #expect(!model.isRequesting)
    }

    @Test func decliningTestPermissionDoesNotPostOrEnableAlerts() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.grant = false
        let model = fixture.model()
        await model.sendTestNotification()
        #expect(fixture.requestCount == 1)
        #expect(fixture.postCount == 0)
        #expect(model.access?.authorization == .denied)
        #expect(model.testNotificationState == .blocked)
        #expect(!model.isSelected(.blockFound))
        #expect(!model.isSelected(.bestShare))
    }

    @Test func testNotificationRechecksRevokedPermissionInsteadOfTrustingCachedAccess() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.access = .init(authorization: .authorized)
        let model = fixture.model()
        await model.refresh()
        fixture.access = .init(authorization: .denied)
        await model.sendTestNotification()
        #expect(fixture.postCount == 0)
        #expect(model.testNotificationState == .blocked)
    }

    @Test func testPermissionFailureIsActionableAndCanBeRetried() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.requestError = NSError(domain: "test", code: 1)
        let model = fixture.model()
        await model.sendTestNotification()
        #expect(fixture.postCount == 0)
        #expect(model.testNotificationState == .failed)
        #expect(model.testNotificationState.message?.contains("Try again") == true)
        #expect(!model.isRequesting)
        fixture.requestError = nil
        await model.sendTestNotification()
        #expect(model.testNotificationState == .queued)
        #expect(fixture.postCount == 1)
    }

    @Test func testPostingFailureNeverClaimsSuccessAndAllowsRetry() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.access = .init(authorization: .authorized)
        fixture.postError = NSError(domain: "test", code: 2)
        let model = fixture.model()
        await model.sendTestNotification()
        #expect(model.testNotificationState == .failed)
        #expect(!model.isRequesting)
        #expect(!model.isSelected(.blockFound))
        #expect(!model.isSelected(.bestShare))
        fixture.postError = nil
        await model.sendTestNotification()
        #expect(fixture.postCount == 2)
        #expect(model.testNotificationState == .queued)
    }

    @Test func pendingTestSubmissionPreventsDuplicatePostsAndCompetingPermissionRequests() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.access = .init(authorization: .authorized)
        fixture.suspendPost = true
        let model = fixture.model()
        let first = Task { await model.sendTestNotification() }
        while fixture.pendingPost == nil { await Task.yield() }
        #expect(model.isRequesting)
        #expect(model.testNotificationState == .sending)
        await model.sendTestNotification()
        await model.setEnabled(true, for: .blockFound)
        #expect(fixture.postCount == 1)
        #expect(fixture.requestCount == 0)
        #expect(!model.isSelected(.blockFound))
        fixture.pendingPost?.resume()
        await first.value
        #expect(model.testNotificationState == .queued)
        #expect(!model.isRequesting)
    }

    @Test func cancellingTestWhilePermissionIsPendingDoesNotPost() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.suspendRequest = true
        let model = fixture.model()
        let task = Task { await model.sendTestNotification() }
        while fixture.pendingRequest == nil { await Task.yield() }
        task.cancel()
        fixture.access = .init(authorization: .authorized)
        fixture.pendingRequest?.resume(returning: true)
        await task.value
        #expect(fixture.postCount == 0)
        #expect(model.testNotificationState == .idle)
        #expect(!model.isRequesting)
        #expect(!model.isSelected(.blockFound))
        #expect(!model.isSelected(.bestShare))
    }

    @Test func returningFromIOSSettingsNeverAutomaticallySendsATest() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.access = .init(authorization: .denied)
        let model = fixture.model()
        await model.sendTestNotification()
        fixture.access = .init(authorization: .authorized)
        await model.refresh()
        #expect(fixture.postCount == 0)
        await model.sendTestNotification()
        #expect(fixture.postCount == 1)
        #expect(model.testNotificationState == .queued)
    }

    @Test func testFeedbackDistinguishesSubmissionFromDeliveryAndMiningMonitoring() {
        let message = FleetNotificationSettingsModel.TestNotificationState.queued.message
        #expect(message?.contains("five seconds from now") == true)
        #expect(message?.contains("Leave the app or lock your \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")") == true)
        #expect(message?.localizedCaseInsensitiveContains("check Notification Center") == true)
        #expect(message?.contains("silence or delay") == true)
        #expect(message?.contains("not miner connectivity or background refresh") == true)
        #expect(message?.contains("delivered") == false)
        #expect(FleetNotificationSettingsModel.TestNotificationState.idle.message == nil)
        #expect(FleetNotificationSettingsModel.Access(authorization: .notDetermined).explanation.contains("Testing never changes your saved alert choices"))
    }

    @Test func existingAlertAccessibilityIdentifiersRemainStable() {
        #expect(FleetNotificationSettingsModel.Alert.blockFound.identifier == "preferences.blockNotifications")
        #expect(FleetNotificationSettingsModel.Alert.bestShare.identifier == "preferences.bestShareNotifications")
    }
}
