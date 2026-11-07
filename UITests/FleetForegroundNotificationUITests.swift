import XCTest

/// Deterministic synthetic alerts: no miner reads, settings writes, or system permissions.
@MainActor
final class FleetForegroundNotificationUITests: XCTestCase {
    func testTappingBannerAboveSheetOpensMinerAndLeavesSheetsReusable() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-in-app-alert",
                               "--ui-test-notification-delay=7"]
        app.launch()
        let addMiner = app.buttons["dashboard.addMiner"]
        XCTAssertTrue(addMiner.waitForExistence(timeout: 10))
        addMiner.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let banner = app.descendants(matching: .any)["inAppAlert.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 12))
        banner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 3), "Opening the alert must dismiss its covering sheet")
        XCTAssertTrue(banner.waitForNonExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(addMiner.waitForExistence(timeout: 5))
        addMiner.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "The sheet binding must remain reusable after alert navigation")
        cancel.tap()
    }

    func testBannerStaysVisibleAndDismissibleAboveAddMinerSheet() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-in-app-alert",
                               "--ui-test-notification-delay=7"]
        app.launch()
        let addMiner = app.buttons["dashboard.addMiner"]
        XCTAssertTrue(addMiner.waitForExistence(timeout: 10))
        addMiner.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let banner = app.descendants(matching: .any)["inAppAlert.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 12))
        XCTAssertTrue(banner.isHittable, "The banner must be above the presented sheet, not behind it")
        XCTAssertTrue(cancel.isHittable, "A banner must not block unrelated sheet controls")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Foreground alert above Add Miner sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Dismiss alert"].firstMatch.tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 3))
        XCTAssertTrue(cancel.isHittable, "Dismissing the alert must leave the current sheet usable")
        cancel.tap()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].isHittable)
    }

    func testCelebrationShowsAboveSheetAndReturnsToTheSameScreen() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-celebration=bestShare",
                               "--ui-test-notification-delay=7"]
        app.launch()
        let addMiner = app.buttons["dashboard.addMiner"]
        XCTAssertTrue(addMiner.waitForExistence(timeout: 10))
        addMiner.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let celebration = app.descendants(matching: .any)["celebration.screen"]
        XCTAssertTrue(celebration.waitForExistence(timeout: 12))
        let dismiss = app.buttons["celebration.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        XCTAssertTrue(dismiss.isHittable, "A high-score celebration must be visible above an open sheet")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "High score celebration above Add Miner sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
        dismiss.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable, "Closing the celebration must return to the screen being used")
        cancel.tap()
    }

    func testBannerRemainsVisibleOnPushedMinerDetail() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-in-app-alert",
                               "--ui-test-notification-delay=7"]
        app.launch()
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.miner.")).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 10))
        miner.tap()
        let banner = app.descendants(matching: .any)["inAppAlert.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 12))
        XCTAssertTrue(banner.isHittable, "Changing to miner detail must not hide a foreground alert")
        app.buttons["Dismiss alert"].firstMatch.tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 3))
    }
}
