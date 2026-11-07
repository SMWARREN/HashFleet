import XCTest

@MainActor
final class LiveActivityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSampleActivityStartsAndEndsWithoutSharingRealWidgetData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "--live-activity-ui-test"]
        app.launch()
        defer { app.terminate() }
        openFleetSettings(in: app)
        XCTAssertTrue(app.navigationBars["App settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["monitoring.widgetSharing"].exists,
                       "Settings root should offer focused destinations, not every control.")
        let widgets = app.buttons["monitoring.widgets"]
        XCTAssertTrue(widgets.waitForExistence(timeout: 5))
        widgets.tap()
        XCTAssertTrue(app.navigationBars["Widgets"].waitForExistence(timeout: 5))
        let sharing = app.switches["monitoring.widgetSharing"]
        XCTAssertTrue(sharing.waitForExistence(timeout: 5))
        XCTAssertEqual(sharing.value as? String, "0")
        app.navigationBars["Widgets"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["App settings"].waitForExistence(timeout: 5))
        let activity = app.buttons["monitoring.liveActivity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.tap()
        XCTAssertTrue(app.navigationBars["Live Activity"].waitForExistence(timeout: 5))
        let stop = app.buttons["monitoring.stopActivity"]
        if stop.exists { reveal(stop, in: app); stop.tap() }
        let start = app.buttons["monitoring.startActivity"]
        reveal(start, in: app)
        start.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 10),
                      "ActivityKit must report a started activity, not merely a successful button tap.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Sample Live Activity started"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        let island = XCTAttachment(screenshot: XCUIApplication(bundleIdentifier: "com.apple.springboard").screenshot())
        island.name = "Sample Live Activity on Home Screen"
        island.lifetime = .keepAlways
        add(island)
        app.activate()
        reveal(stop, in: app)
        stop.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(stop.exists)
        app.navigationBars["Live Activity"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(widgets.waitForExistence(timeout: 5))
        widgets.tap()
        XCTAssertTrue(sharing.waitForExistence(timeout: 5))
        XCTAssertEqual(sharing.value as? String, "0",
                       "Starting and ending a sample activity must not enable widget sharing.")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
}
