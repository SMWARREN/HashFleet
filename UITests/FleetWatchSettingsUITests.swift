import XCTest

@MainActor
final class FleetWatchSettingsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testIndependentWatchGuidancePortraitLandscapeAndLowerContent() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        XCUIDevice.shared.orientation = .portrait
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        app.launch()
        settleOrientation(.portrait, in: app)
        openWatchPage(in: app)
        XCTAssertTrue(app.staticTexts["Your miners, even when your phone is off."].exists)
        XCTAssertFalse(app.buttons["monitoring.watch.send"].exists, "Demo must not export configuration")
        capture("Watch settings portrait")
        inspectLowerContent(in: app)
        capture("Watch settings lower privacy guidance")
        // The page is a sheet: blind full-screen swipe-downs dismiss it, so scroll back only until the intro
        // is hittable and then prove the page is still presented.
        let intro = app.staticTexts["Your miners, even when your phone is off."]
        reveal(intro, in: app, towardTop: true)
        XCTAssertTrue(intro.isHittable, "Could not scroll back to the intro")
        XCTAssertTrue(app.navigationBars["Apple Watch"].exists, "Scrolling back dismissed the Watch page")
        capture("Watch settings after scrolling back")
        XCUIDevice.shared.orientation = .landscapeLeft
        settleOrientation(.landscapeLeft, in: app)
        XCTAssertTrue(app.navigationBars["Apple Watch"].waitForExistence(timeout: 5))
        capture("Watch settings landscape or tablet split layout")
        inspectLowerContent(in: app)
        capture("Watch settings landscape lower guidance")
    }

    func testLargeTextAndEmptySetupDoNotStartPhoneTransfer() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        defer { app.terminate() }
        app.launch()
        settleOrientation(.portrait, in: app)
        openWatchPage(in: app)
        capture("Watch setup accessibility text")
        let send = app.buttons["monitoring.watch.send"]
        reveal(send, in: app)
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled, "Empty UI-test inventory must not transfer real miners")
        capture("Watch setup accessibility action")
        inspectLowerContent(in: app)
        capture("Watch setup accessibility lower guidance")
    }

    private func openWatchPage(in app: XCUIApplication) {
        openFleetSettings(in: app)
        let link = app.buttons["monitoring.watch"]
        reveal(link, in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.isHittable)
        link.tap()
        XCTAssertTrue(app.navigationBars["Apple Watch"].waitForExistence(timeout: 5))
    }

    private func inspectLowerContent(in app: XCUIApplication) {
        for phrase in ["Cellular alone cannot reach", "Stale does not mean", "Pool credentials, wallet addresses"] {
            let text = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", phrase)).firstMatch
            reveal(text, in: app)
            XCTAssertTrue(text.exists && text.isHittable, "Missing reachable guidance: \(phrase)")
        }
    }

    private func settleOrientation(_ orientation: UIDeviceOrientation, in app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation.isLandscape
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let frame = app.frame
                return landscape ? frame.width > frame.height : frame.height > frame.width
            }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<28 where !(target.exists && target.isHittable) {
            let bars = app.navigationBars
            let bar = bars.element(boundBy: max(0, bars.count - 1))
            let frame = app.frame
            let top = bar.exists ? max(frame.minY, bar.frame.maxY) : frame.minY + 60
            let bottom = frame.maxY - 30
            let origin = app.coordinate(withNormalizedOffset: .zero)
            // Dragging up reveals lower content. Dragging down (towardTop) stays inside the content area.
            let from = towardTop ? 0.45 : 0.8
            let to = towardTop ? 0.8 : 0.45
            let start = origin.withOffset(CGVector(dx: frame.width * 0.55, dy: top + (bottom - top) * from))
            let end = origin.withOffset(CGVector(dx: frame.width * 0.55, dy: top + (bottom - top) * to))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
