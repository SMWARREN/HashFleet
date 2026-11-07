import Foundation
import Testing
@testable import HashFleet

struct FleetTourContentTests {
    @Test func everyLessonTargetsARealScreenAndHasUniqueIdentity() {
        let steps = FleetGuidedDemoStep.all
        #expect(steps.count == 17)
        #expect(Set(steps.map(\.id)).count == steps.count)
        #expect(steps.first?.id == "overview")
        #expect(steps.last?.id == "complete")
        #expect(Set(steps.map(\.screen)).count == 9)
        #expect(steps.filter { $0.tapTitle != nil }.count == 8)
        #expect(steps.allSatisfy { !$0.target.isEmpty && !$0.title.isEmpty && !$0.instruction.isEmpty })
    }
    @Test func sampleCopyDoesNotPromiseRealChangesOrNotificationDelivery() {
        let copy = Dictionary(uniqueKeysWithValues: FleetGuidedDemoStep.all.map { ($0.id, $0.instruction) })
        #expect(copy["chooseDGB"]?.contains("Nothing changes outside this demo") == true)
        #expect(copy["energy"]?.contains("not an actual bill") == true)
        #expect(copy["openAlerts"]?.contains("ask for permission") == true)
        #expect(copy["previewReport"]?.contains("never opens a share") == true)
        #expect(copy["complete"]?.contains("back on the fleet you left") == true)
    }
}

@MainActor
struct FleetTourPresentationTests {
    @Test func firstLaunchDismissalAndSuppressionPersistIndependently() throws {
        let name = "tour-policy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = FleetPreferences(defaults: defaults)
        let bestShareBefore = preferences.bestShareNotificationsEnabled
        let sessionBefore = preferences.sessionBestNotificationsEnabled
        #expect(preferences.shouldShowFeatureTour)
        preferences.suppressFeatureTour = true
        #expect(!FleetPreferences(defaults: defaults).shouldShowFeatureTour)
        #expect(!preferences.hasSeenFeatureTour)
        preferences.suppressFeatureTour = false
        #expect(FleetPreferences(defaults: defaults).shouldShowFeatureTour)
        preferences.hasSeenFeatureTour = true
        let reopened = FleetPreferences(defaults: defaults)
        #expect(reopened.hasSeenFeatureTour)
        #expect(!reopened.shouldShowFeatureTour)
        #expect(!reopened.suppressFeatureTour)
        #expect(!reopened.blockNotificationsEnabled)
        #expect(reopened.bestShareNotificationsEnabled == bestShareBefore)
        #expect(reopened.sessionBestNotificationsEnabled == sessionBefore)
    }
}
