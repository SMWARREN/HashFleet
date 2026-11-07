import Foundation
import Testing
import UIKit
import UserNotifications
@testable import HashFleet

@Suite("Notification settings") @MainActor
struct FleetNotificationSettingsTests {
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

        init() {
            defaults = UserDefaults(suiteName: suite)!
            preferences = FleetPreferences(defaults: defaults)
            // Permission transitions start from explicit opt-outs, not application defaults.
            // Fresh default choices are covered separately below and in the preference suite.
            preferences.bestShareNotificationsEnabled = false
            preferences.sessionBestNotificationsEnabled = false
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

    @Test func openingSettingsReadsPermissionWithoutPromptingOrChangingSavedChoices() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model()
        #expect(model.access == nil)
        await model.refresh()
        #expect(model.access?.title == "Permission not requested")
        #expect(fixture.requestCount == 0)
        #expect(!model.isSelected(.blockFound))
        #expect(!model.isSelected(.bestShare))
    }

    @Test func readingPermissionPreservesFreshBestShareDefaultsWithoutPrompting() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.defaults.removePersistentDomain(forName: fixture.suite)
        let preferences = FleetPreferences(defaults: fixture.defaults)
        let model = FleetNotificationSettingsModel(preferences: preferences,
            readAccess: {
                fixture.readCount += 1
                return .init(authorization: .notDetermined)
            },
            requestAccess: {
                fixture.requestCount += 1
                return true
            })
        await model.refresh()
        #expect(model.isSelected(.bestShare))
        #expect(model.isSelected(.sessionBestShare))
        #expect(!model.isEnabled(.bestShare))
        #expect(!model.isEnabled(.sessionBestShare))
        #expect(fixture.requestCount == 0)
        #expect(!model.isSelected(.blockFound))
    }

    @Test(arguments: FleetNotificationSettingsModel.Alert.allCases)
    func deniedPermissionLeavesToggleOffAndExplainsRecovery(alert: FleetNotificationSettingsModel.Alert) async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        if alert == .sessionBestShare { fixture.preferences.bestShareNotificationsEnabled = true }
        fixture.access = .init(authorization: .denied)
        let model = fixture.model()
        await model.setEnabled(true, for: alert)
        #expect(!model.isSelected(alert))
        #expect(!model.isEnabled(alert))
        #expect(model.access?.title == "Blocked in Settings")
        #expect(model.access?.explanation.contains("Allow Notifications") == true)
        #expect(model.deliveryNote(for: alert)?.contains("Use Open Settings") == true)
        #expect(fixture.requestCount == 0, "A denied permission must lead to Settings, not another ineffective prompt")
    }

    @Test(arguments: FleetNotificationSettingsModel.Alert.allCases)
    func grantingPermissionOnlyEnablesTheChosenAlert(alert: FleetNotificationSettingsModel.Alert) async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        if alert == .sessionBestShare { fixture.preferences.bestShareNotificationsEnabled = true }
        let model = fixture.model()
        await model.setEnabled(true, for: alert)
        #expect(model.isEnabled(alert))
        #expect(fixture.requestCount == 1)
        for other in FleetNotificationSettingsModel.Alert.allCases where other != alert {
            #expect(model.isSelected(other) == (alert == .sessionBestShare && other == .bestShare),
                "Granting session delivery requires an explicitly enabled master, not a hidden opt-in")
        }
        #expect(!model.isRequesting)
    }

    @Test func decliningSystemPromptImmediatelyShowsBlockedState() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.grant = false
        let model = fixture.model()
        await model.setEnabled(true, for: .bestShare)
        #expect(!model.isSelected(.bestShare))
        #expect(model.access?.authorization == .denied)
        #expect(model.access?.title == "Blocked in Settings")
    }

    @Test(arguments: [UNAuthorizationStatus.authorized, .provisional, .ephemeral])
    func existingPermissionEnablesWithoutAnotherPrompt(authorization: UNAuthorizationStatus) async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.access = .init(authorization: authorization)
        let model = fixture.model()
        await model.setEnabled(true, for: .blockFound)
        #expect(model.isEnabled(.blockFound))
        #expect(fixture.requestCount == 0)
    }

    @Test func returningFromSettingsRefreshesRevocationAndRestorationWithoutLosingChoices() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.preferences.blockNotificationsEnabled = true
        fixture.access = .init(authorization: .authorized)
        let model = fixture.model()
        await model.refresh()
        #expect(model.isEnabled(.blockFound))
        fixture.access = .init(authorization: .denied)
        await model.refresh()
        #expect(!model.isEnabled(.blockFound))
        #expect(model.isSelected(.blockFound), "Revocation must not destroy a saved opt-in")
        #expect(model.deliveryNote(for: .blockFound)?.contains("Selected, but blocked by system notification settings") == true)
        fixture.access = .init(authorization: .authorized)
        await model.refresh()
        #expect(model.isEnabled(.blockFound))
        #expect(!model.isSelected(.bestShare), "Restoring permission must not opt in another alert")
        #expect(model.deliveryNote(for: .blockFound) == nil)
        #expect(fixture.requestCount == 0)
    }

    @Test func turningOffARevokedSavedChoiceDoesNotRequestPermission() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.preferences.blockNotificationsEnabled = true
        fixture.access = .init(authorization: .denied)
        let model = fixture.model()
        await model.setEnabled(false, for: .blockFound)
        #expect(!model.isSelected(.blockFound))
        #expect(fixture.requestCount == 0)
        #expect(fixture.readCount == 0)
    }

    @Test func requestErrorsLeaveAnActionableMessageAndAllowRetry() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.requestError = NSError(domain: "test", code: 1)
        let model = fixture.model()
        await model.setEnabled(true, for: .bestShare)
        #expect(!model.isSelected(.bestShare))
        #expect(model.error?.contains("Try again or open Settings") == true)
        #expect(!model.isRequesting)
        fixture.requestError = nil
        await model.setEnabled(true, for: .bestShare)
        #expect(model.error == nil)
        #expect(model.isEnabled(.bestShare))
    }

    @Test func pendingPermissionDoesNotAllowOverlappingPromptsOrOverwriteAnOptOut() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.suspendRequest = true
        let model = fixture.model()
        let task = Task { await model.setEnabled(true, for: .blockFound) }
        while fixture.pendingRequest == nil { await Task.yield() }
        #expect(model.isRequesting)
        await model.setEnabled(true, for: .bestShare)
        #expect(fixture.requestCount == 1)
        await model.setEnabled(false, for: .blockFound)
        fixture.access = .init(authorization: .authorized)
        fixture.pendingRequest?.resume(returning: true)
        await task.value
        #expect(!model.isSelected(.blockFound))
        #expect(!model.isSelected(.bestShare))
        #expect(!model.isRequesting)
    }

    @Test func cancellingAPendingRequestDoesNotOptIn() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.suspendRequest = true
        let model = fixture.model()
        let task = Task { await model.setEnabled(true, for: .bestShare) }
        while fixture.pendingRequest == nil { await Task.yield() }
        task.cancel()
        fixture.access = .init(authorization: .authorized)
        fixture.pendingRequest?.resume(returning: true)
        await task.value
        #expect(!model.isSelected(.bestShare))
        #expect(!model.isRequesting)
    }

    @Test func olderLifecycleReadCannotOverwriteAuthorizationResult() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        var readCount = 0
        var pendingRead: CheckedContinuation<FleetNotificationSettingsModel.Access, Never>?
        let model = FleetNotificationSettingsModel(
            preferences: fixture.preferences,
            readAccess: {
                readCount += 1
                if readCount == 1 {
                    return await withCheckedContinuation { pendingRead = $0 }
                }
                return .init(authorization: .authorized)
            },
            requestAccess: { Issue.record("Existing permission should not request access"); return false },
            readBackgroundStatus: { .available }
        )
        let oldRefresh = Task { await model.refresh() }
        while pendingRead == nil { await Task.yield() }
        await model.setEnabled(true, for: .blockFound)
        #expect(model.isEnabled(.blockFound))
        pendingRead?.resume(returning: .init(authorization: .denied))
        await oldRefresh.value
        #expect(model.access?.authorization == .authorized)
        #expect(model.isEnabled(.blockFound))
    }

    @Test func quietAndTemporaryPermissionAreNotDescribedAsFullDelivery() {
        let quiet = FleetNotificationSettingsModel.Access(authorization: .provisional)
        #expect(quiet.title == "Quiet delivery only")
        #expect(quiet.explanation.contains("without a banner or sound"))
        let temporary = FleetNotificationSettingsModel.Access(authorization: .ephemeral)
        #expect(temporary.title == "Temporary permission")
        #expect(temporary.explanation.contains("expire"))
    }

    @Test func disabledBannersAndSoundsHaveSpecificSystemGuidance() {
        let bannersOff = FleetNotificationSettingsModel.Access(authorization: .authorized, alertsEnabled: false)
        #expect(bannersOff.title == "Banners and alerts are off")
        #expect(bannersOff.explanation.contains("Enable banners"))
        let soundOff = FleetNotificationSettingsModel.Access(authorization: .authorized, soundsEnabled: false)
        #expect(soundOff.title == "Allowed without sound")
        #expect(soundOff.explanation.contains("sounds are off"))
        #expect(soundOff.explanation.contains("Focus and Scheduled Summary"))
        #expect(soundOff.permitsNotifications, "Silent authorization is still usable, but must be explained")
    }

    @Test func backgroundRestrictionsAndRecoveryAreRefreshedFromSystemState() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model()
        fixture.background = .denied
        await model.refresh()
        #expect(model.backgroundTitle == "Background App Refresh is unavailable")
        #expect(model.backgroundDetail.contains("Low Power Mode"))
        fixture.background = .restricted
        await model.refresh()
        #expect(model.backgroundTitle == "Background App Refresh is restricted")
        #expect(model.backgroundDetail.contains("Opening Hash Fleet still refreshes"))
        fixture.background = .available
        await model.refresh()
        #expect(model.backgroundTitle == "Background checks are best effort")
        #expect(model.backgroundDetail.contains("delay or skip"))
    }

    @Test func settingsLinkHasAManualFallbackIfIOSCannotOpenIt() {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model()
        #expect(FleetNotificationSettingsModel.settingsURL.absoluteString == UIApplication.openSettingsURLString)
        model.settingsDidOpen(false)
        #expect(model.error?.contains("Open Settings manually") == true)
        model.settingsDidOpen(true)
        #expect(model.error == nil)
    }

    @Test func explanationsCoverTriggersFrequencyBaselinesAndDeliveryLimits() {
        typealias Model = FleetNotificationSettingsModel
        #expect(Model.Alert.blockFound.explanation.contains("block counter increase"))
        #expect(Model.Alert.blockFound.explanation.contains("high-difficulty share alone does not qualify"))
        #expect(Model.Alert.bestShare.explanation.contains("all-time or session"))
        #expect(Model.Alert.bestShare.explanation.contains("all-time record takes priority"))
        #expect(Model.frequencyExplanation.contains("baseline and does not alert"))
        #expect(Model.frequencyExplanation.contains("Unchanged readings do not alert again"))
        #expect(Model.frequencyExplanation.contains("several miners may arrive together after a gap"))
        #expect(!Model.frequencyExplanation.contains("only the latest detected event"))
        #expect(Model.backgroundExplanation.contains("no guaranteed check interval or instant delivery"))
        #expect(Model.connectionExplanation.contains("local network or a working VPN"))
        #expect(Model.foregroundExplanation.contains("instead of as a system notification"))
        #expect(Model.foregroundExplanation.contains("without repeating events already delivered as system notifications"))
        #expect(Model.Alert.sessionBestShare.explanation.contains("keep only all-time record alerts"))
        #expect(Model.foregroundExplanation.contains("stay until dismissed"))
        #expect(Model.Alert.sessionBestShare.explanation.contains("not a brief toast"))
    }

    @Test func allAlertCasesHaveUniqueTitlesIdentifiersAndExplanations() {
        typealias Model = FleetNotificationSettingsModel
        let cases = Model.Alert.allCases
        #expect(cases.count == 6)

        let titles = Set(cases.map(\.title))
        #expect(titles.count == 6)

        let identifiers = Set(cases.map(\.identifier))
        #expect(identifiers.count == 6)

        for alert in cases {
            #expect(!alert.title.isEmpty)
            #expect(!alert.identifier.isEmpty)
            #expect(!alert.explanation.isEmpty)
        }
    }

    @Test func isSelectedAndSaveCoversAllAlertCases() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.access = .init(authorization: .authorized)
        let model = fixture.model()

        for alert in FleetNotificationSettingsModel.Alert.allCases {
            #expect(!model.isSelected(alert))
            await model.setEnabled(true, for: alert)
            #expect(model.isSelected(alert))
            await model.setEnabled(false, for: alert)
            #expect(!model.isSelected(alert))
        }
    }

    @Test func notDeterminedAccessReturnsNilDeliveryNote() {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.access = .init(authorization: .notDetermined)
        fixture.preferences.bestShareNotificationsEnabled = true
        let model = fixture.model()
        for alert in FleetNotificationSettingsModel.Alert.allCases {
            #expect(model.deliveryNote(for: alert) == nil)
        }
    }

    @Test func sessionChoiceSurvivesGlobalOptOutButCannotBypassIt() async {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.access = .init(authorization: .authorized)
        let model = fixture.model()
        await model.setEnabled(true, for: .sessionBestShare)
        #expect(model.isSelected(.sessionBestShare))
        #expect(!model.isSelected(.bestShare))
        #expect(!model.isEnabled(.sessionBestShare))
        #expect(model.deliveryNote(for: .sessionBestShare)?.contains("master control") == true)
        await model.setEnabled(true, for: .bestShare)
        #expect(model.isEnabled(.sessionBestShare))
        await model.setEnabled(false, for: .sessionBestShare)
        #expect(model.isEnabled(.bestShare))
        #expect(!model.isEnabled(.sessionBestShare))
        #expect(fixture.requestCount == 0)
    }
}
