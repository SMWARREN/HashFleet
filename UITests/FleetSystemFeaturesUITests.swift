import XCTest

@MainActor
final class FleetSystemFeaturesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSystemFeaturesShowsOptInAndReturnsToFleetInBothAppearances() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        for light in [false, true] {
            app.launchArguments = ["--ui-testing"]
            if light { app.launchArguments.append("--ui-test-light-appearance") }
            app.launch()
            XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 10))
            openFleetSettings(in: app)
            let features = app.buttons["monitoring.systemFeatures"]
            for _ in 0..<6 where !features.isHittable { app.swipeUp() }
            XCTAssertTrue(features.waitForExistence(timeout: 5))
            XCTAssertTrue(features.isHittable)
            features.tap()
            XCTAssertTrue(app.navigationBars["Shortcuts & Controls"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Hash Fleet shortcuts"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["HashFleet shortcuts"].exists)
            let sharing = app.descendants(matching: .any)["systemFeatures.sharing"].firstMatch
            for _ in 0..<5 where !sharing.isHittable { app.swipeUp() }
            XCTAssertTrue(sharing.waitForExistence(timeout: 5))
            let sharingDescription = "\(sharing.label) \(sharing.value as? String ?? "")"
            XCTAssertTrue(sharingDescription.contains("Off"),
                          "System entry points must not enable sharing: \(sharingDescription)")
            let openFleet = app.descendants(matching: .any)["systemFeatures.openFleet"].firstMatch
            for _ in 0..<5 where !openFleet.isHittable { app.swipeUp() }
            XCTAssertTrue(openFleet.isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = light ? "System features light" : "System features dark"
            shot.lifetime = .keepAlways
            add(shot)
            openFleet.tap()
            XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
            // No tab bar in this app shell; the dashboard toolbar menu proves we are back on the fleet.
            XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }
}
