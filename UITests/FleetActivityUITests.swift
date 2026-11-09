import XCTest
import UIKit

/// Demo-only acceptance for the restored navigation and quiet popup control.
/// The earlier activity-menu scenarios are superseded by the user's explicit removal request.
@MainActor
final class FleetActivityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOriginalHeaderShowsFullTitleAndHasNoAddedActivityMenus() {
        let app = launchDemo()
        defer { app.terminate() }
        let title = app.staticTexts["dashboard.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Hash Fleet")
        let requiredWidth = ("Hash Fleet" as NSString).size(withAttributes: [
            .font: UIFont.preferredFont(forTextStyle: .headline)
        ]).width
        XCTAssertGreaterThanOrEqual(title.frame.width + 1, requiredWidth,
                                    "The title must have room to draw without an ellipsis")
        XCTAssertTrue(app.buttons["dashboard.addMiner"].isHittable)
        XCTAssertFalse(element("dashboard.activity", app).exists)
        capture("Restored original header with full Hash Fleet title", app)

        app.buttons["dashboard.settingsMenu"].tap()
        XCTAssertTrue(app.buttons["App settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Refresh fleet"].exists)
        XCTAssertTrue(app.buttons["About"].exists)
        XCTAssertTrue(app.buttons["Feature tour"].exists)
        XCTAssertFalse(app.buttons["Fleet activity"].exists)
        XCTAssertFalse(element("dashboard.activityDisplayMenu", app).exists)
        XCTAssertFalse(element("dashboard.sessionAlerts", app).exists)
        capture("Original settings menu without the added activity controls", app)
    }

    func testQuietSessionPopupOptOutPreservesOtherAlertsAndCanBeReenabledInSettings() {
        let app = launchDemo()
        defer { app.terminate() }
        openNotificationControls(app)
        let preview = app.buttons["notifications.previewSessionBest"]
        reveal(preview, in: app)
        preview.tap()
        let optOut = app.buttons["celebration.disableSessionAlerts"]
        waitUntilHittable(optOut)
        XCTAssertEqual(optOut.label, "Turn off session-best alerts")
        XCTAssertTrue(app.buttons["celebration.viewMiner"].isHittable)
        XCTAssertTrue(app.buttons["celebration.dismiss"].isHittable)
        capture("Quiet session-only opt-out on the illustrated popup", app)
        optOut.tap()
        XCTAssertTrue(optOut.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["App settings"].exists)
        XCTAssertTrue(preview.isHittable, "Opting out returns to the same Settings position")
        assertAlertChoices(app, session: "0")
        XCTAssertFalse(element("preferences.activityContentMode", app).exists)

        relaunchPreservingStorage(app)
        openNotificationControls(app)
        let session = app.switches["preferences.sessionBestNotifications"]
        reveal(session, in: app)
        XCTAssertEqual(session.value as? String, "0")
        let nativeSwitch = session.switches.firstMatch
        XCTAssertTrue(nativeSwitch.exists && nativeSwitch.isEnabled)
        reveal(nativeSwitch, in: app)
        waitUntilHittable(nativeSwitch)
        nativeSwitch.tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: session)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        capture("Session alerts re-enabled inside the existing App settings", app)

        relaunchPreservingStorage(app)
        openNotificationControls(app)
        assertAlertChoices(app, session: "1")
    }

    func testScheduledSummariesStayInlineOffAndDisabledInDemo() {
        let app = launchDemo()
        defer { app.terminate() }
        openNotificationControls(app)
        let summary = app.switches["notifications.remote.enabled"]
        let viewport = app.frame.insetBy(dx: 0, dy: 64)
        for _ in 0..<18 {
            if summary.exists && viewport.contains(summary.frame) { break }
            app.swipeUp()
        }
        XCTAssertTrue(summary.exists)
        XCTAssertEqual(summary.value as? String, "0")
        XCTAssertFalse(summary.isEnabled, "Demo and automated runs must not enroll with the real service")
        XCTAssertTrue(app.staticTexts["notifications.remote.demoNotice"].exists)
        XCTAssertTrue(app.navigationBars["App settings"].exists)
        XCTAssertFalse(app.navigationBars["Notifications"].exists)
        XCTAssertFalse(app.buttons["notifications.remote.companion"].exists)
        XCTAssertFalse(app.buttons["notifications.remote.manage"].exists)
        XCTAssertFalse(app.buttons["Manage schedules on hashfleet.app"].exists)
        XCTAssertFalse(app.buttons["Create LAN companion config"].exists)
        capture("APNs summaries remain inline, off and restricted in demo", app)
    }

    func testLargestTextSessionOptOutRemainsReachableWithoutNewTopBarControls() {
        let app = launchDemo(extra: ["--ui-test-celebration=session",
                                     "-UIPreferredContentSizeCategoryName",
                                     "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        assertAccessibleSessionOptOut(app, screenshot: "Session popup at largest Dynamic Type")
    }

    func testDesktopStyleLargestTextSessionOptOutRemainsReachable() {
        let app = launchDemo(extra: ["--ui-test-desktop-layout", "--ui-test-celebration=session",
                                     "-UIPreferredContentSizeCategoryName",
                                     "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        assertAccessibleSessionOptOut(app, screenshot: "Desktop-style session popup at largest text")
    }

    private func assertAccessibleSessionOptOut(_ app: XCUIApplication, screenshot: String) {
        let title = app.staticTexts["celebration.eyebrow"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "SESSION BEST")
        let optOut = app.buttons["celebration.disableSessionAlerts"]
        reveal(optOut, in: app)
        let readableViewport = app.frame.insetBy(dx: 0, dy: 64)
        for _ in 0..<5 where !readableViewport.contains(optOut.frame) {
            app.swipeUp()
        }
        waitUntilHittable(optOut)
        XCTAssertTrue(readableViewport.contains(optOut.frame),
                      "The entire opt-out must be visible, not just a hittable clipped edge")
        XCTAssertGreaterThanOrEqual(optOut.frame.height, 44)
        XCTAssertLessThanOrEqual(optOut.frame.height, 88,
                                "The quiet opt-out must not balloon into a screen-filling control")
        XCTAssertLessThanOrEqual(app.buttons["celebration.viewMiner"].frame.height, 110)
        XCTAssertLessThanOrEqual(app.staticTexts["celebration.detail"].frame.height, 140,
                                "The short description must not become a screen-filling paragraph")
        XCTAssertFalse(element("dashboard.activity", app).exists)
        capture(screenshot, app)
        optOut.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        waitUntilHittable(app.buttons["dashboard.settingsMenu"])
        let dashboardTitle = app.staticTexts["dashboard.title"]
        XCTAssertEqual(dashboardTitle.label, "Hash Fleet")
        XCTAssertLessThanOrEqual(dashboardTitle.frame.height, 32,
                                "Navigation chrome must not grow to an unusable size")
        capture("Readable original header after the largest-text popup", app)
    }

    private func openNotificationControls(_ app: XCUIApplication) {
        openFleetSettings(in: app)
        let group = app.buttons["monitoring.notifications"]
        reveal(group, in: app)
        group.tap()
        XCTAssertTrue(app.navigationBars["App settings"].exists)
        XCTAssertFalse(app.navigationBars["Notifications"].exists)
    }

    private func assertAlertChoices(_ app: XCUIApplication, session: String) {
        let expected = [
            ("preferences.blockNotifications", "0"),
            ("preferences.bestShareNotifications", "1"),
            ("preferences.sessionBestNotifications", session),
            ("preferences.disconnectNotifications", "0"),
            ("preferences.metricAlertNotifications", "0"),
            ("preferences.powerAlertNotifications", "0")
        ]
        for (identifier, value) in expected {
            let control = app.switches[identifier]
            reveal(control, in: app)
            XCTAssertEqual(control.value as? String, value, "Only the session choice may change")
        }
    }

    private func launchDemo(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 10))
        return app
    }

    private func relaunchPreservingStorage(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-preserve-storage"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 10))
    }

    private func reveal(_ control: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 {
            if control.exists && control.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(control.exists && control.isHittable, "Expected a reachable control: \(control)")
    }

    private func waitUntilHittable(_ control: XCUIElement) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
