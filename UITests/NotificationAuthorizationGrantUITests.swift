import XCTest

/// Provisions real notification authorization on an isolated simulator through the app's normal
/// settings action and the actual system prompt. This never changes the host Mac's permission.
/// Running it again still verifies permission and test-request scheduling instead of silently
/// succeeding when launch-time permission requests are intentionally disabled for UI tests.
@MainActor
final class NotificationAuthorizationGrantUITests: XCTestCase {
    func testGrantsRealNotificationAuthorizationForSubsequentSystemDeliveryTests() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]

        let interruption = addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(interruption) }

        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 8))
        openFleetSettings(in: app)
        let notifications = app.buttons["monitoring.notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        notifications.tap()
        XCTAssertTrue(app.navigationBars["App settings"].exists)
        XCTAssertFalse(app.navigationBars["Notifications"].exists)

        let sendTest = app.buttons["preferences.sendTestNotification"]
        for _ in 0..<5 {
            if sendTest.exists && sendTest.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(sendTest.waitForExistence(timeout: 5))
        XCTAssertTrue(sendTest.isHittable)
        sendTest.tap()
        // A later interaction lets XCTest handle the real authorization interruption if needed.
        app.navigationBars["App settings"].tap()

        let scheduled = app.staticTexts.containing(NSPredicate(
            format: "label BEGINSWITH %@", "Test scheduled for five seconds from now."
        )).firstMatch
        XCTAssertTrue(scheduled.waitForExistence(timeout: 10),
                      "The real settings action must successfully schedule a test, not merely launch the app.")

        // Scheduling alone can also work with provisional permission. Require the authorized
        // explanation so the subsequent real-system suite's stronger precondition is exercised.
        let authorized = app.staticTexts.containing(NSPredicate(
            format: "label BEGINSWITH %@", "Permission is granted, not a delivery guarantee."
        )).firstMatch
        for _ in 0..<5 {
            if authorized.exists && authorized.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(authorized.waitForExistence(timeout: 5),
                      "iOS must actually report authorization for the app on this simulator.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Real simulator notification permission after test scheduling"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
