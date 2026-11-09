import XCTest

/// Demo-only navigation coverage. Never enters checkout or touches a real miner.
@MainActor
final class DeveloperSupportUITests: XCTestCase {
    func testSupportIsDiscoverableFromPhoneMenuAndCanBeReopened() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()
        for _ in 0..<2 {
            dashboardSettingsMenu(in: app).tap()
            let support = app.buttons["dashboard.openSupport"]
            XCTAssertTrue(support.waitForExistence(timeout: 5))
            support.tap()
            XCTAssertTrue(app.navigationBars["Support Hash Fleet"].waitForExistence(timeout: 5))
            let done = app.buttons["support.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            XCTAssertTrue(done.isHittable)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Phone Support page from menu"
            attachment.lifetime = .keepAlways
            add(attachment)
            done.tap()
            XCTAssertTrue(dashboardSettingsMenu(in: app).isHittable)
        }
    }

    func testSessionCelebrationSupportOpensInternalPageWithoutStorefront() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-celebration=session"]
        app.launch()
        let support = app.buttons["celebration.support"]
        XCTAssertTrue(support.waitForExistence(timeout: 10))
        for _ in 0..<5 where !support.isHittable { app.swipeUp() }
        XCTAssertTrue(support.isHittable)
        support.tap()
        XCTAssertTrue(app.navigationBars["Support Hash Fleet"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground, "Internal Support navigation must not launch checkout")
        XCTAssertTrue(app.buttons["support.done"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Session celebration opens internal Support page"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSessionCelebrationKeepsPrimaryActionsReachable() {
        checkCelebration(kind: "session")
    }

    func testBlockCelebrationKeepsPrimaryActionsReachable() {
        checkCelebration(kind: "block")
    }

    private func checkCelebration(kind: String) {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-celebration=\(kind)"]
        app.launch()
        let screen = app.descendants(matching: .any)["celebration.screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        let eyebrow = app.staticTexts["celebration.eyebrow"]
        XCTAssertTrue(eyebrow.waitForExistence(timeout: 5))
        XCTAssertEqual(eyebrow.label, kind == "block" ? "BLOCK FOUND" : "SESSION BEST")
        let miner = app.buttons["celebration.viewMiner"]
        XCTAssertTrue(miner.waitForExistence(timeout: 5))
        let dismiss = app.buttons["celebration.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        for _ in 0..<5 where !dismiss.isHittable { app.swipeUp() }
        XCTAssertTrue(dismiss.isHittable, "Optional support must never hide the keep-mining action")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Phone \(kind) celebration primary controls"
        attachment.lifetime = .keepAlways
        add(attachment)
        dismiss.tap()
        XCTAssertTrue(screen.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dashboardSettingsMenu(in: app).isHittable)
    }
}
