import XCTest

extension RealModeControlUITests {
    func testPauseReviewStaysInFrontAndRequiresExplicitConfirmation() throws {
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        // The fixture deliberately serves HTTP rather than a live WebSocket. Its fallback
        // banner changes the dashboard layout, so don't tap the card while that row is appearing.
        let fallback = app.descendants(matching: .any)["dashboard.errorSummary"].firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 10))
        assertBecomesOnline(miner)
        revealTelemetryControl(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5),
                      "Tapping the visible fixture card must enter miner detail")
        let pause = app.buttons["detail.quick.pause"]
        revealTelemetryControl(pause, in: app)
        pause.tap()

        let requestForm = app.navigationBars["Pause mining"]
        XCTAssertTrue(requestForm.waitForExistence(timeout: 5), "Pause must bring the request form to the foreground")
        let review = app.buttons["endpoint.send"]
        reveal(review, in: app)
        review.tap()
        let reviewBar = app.navigationBars["Review before sending"]
        XCTAssertTrue(reviewBar.waitForExistence(timeout: 5))
        let cancel = reviewBar.buttons["confirmation.cancel"]
        XCTAssertTrue(cancel.isHittable, "The review must own the interactive foreground")
        let method = app.descendants(matching: .any)["confirmation.methodAndPath"].firstMatch
        reveal(method, in: app)
        XCTAssertEqual(method.label, "POST /api/system/pause")
        XCTAssertTrue(app.staticTexts["No request body"].exists)
        XCTAssertTrue(app.staticTexts["This stops mining on this device until you resume."].exists)
        XCTAssertFalse(review.isHittable, "The underlying request form must not receive taps through the sheet")
        assertNoWrites(server, for: 0.5)
        let receipt = XCTAttachment(screenshot: app.screenshot())
        receipt.name = "Full View - exact Pause review in front"
        receipt.lifetime = .keepAlways
        add(receipt)

        cancel.tap()
        XCTAssertTrue(reviewBar.waitForNonExistence(timeout: 5))
        XCTAssertTrue(requestForm.exists)
        assertNoWrites(server, for: 0.5)
        reveal(review, in: app)
        review.tap()
        XCTAssertTrue(reviewBar.waitForExistence(timeout: 5))
        let acknowledgement = app.switches["confirmation.understood"]
        reveal(acknowledgement, in: app)
        XCTAssertEqual(acknowledgement.value as? String, "0", "Cancel must discard the previous review state")
        let send = app.buttons["confirmation.apply"]
        reveal(send, in: app)
        XCTAssertFalse(send.isEnabled)
        reveal(acknowledgement, in: app, direction: .down)
        acknowledgement.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(acknowledgement.value as? String, "1")
        reveal(send, in: app)
        XCTAssertFalse(send.isEnabled, "Acknowledgement alone must never authorize a write")
        let token = app.textFields["confirmation.token"]
        reveal(token, in: app)
        token.tap()
        token.typeText("APPLY")
        assertApplyRevealedWithoutScrolling(send, in: app)
        XCTAssertTrue(send.isEnabled)
        assertNoWrites(server, for: 0.5)
        send.tap()
        XCTAssertTrue(reviewBar.waitForNonExistence(timeout: 5))
        let completion = app.alerts["Request accepted"]
        XCTAssertTrue(completion.waitForExistence(timeout: 10), "Result must appear after the review, not behind it")
        completion.buttons["OK"].tap()
        XCTAssertTrue(requestForm.exists)
        let actual = try XCTUnwrap(server.writes.first)
        XCTAssertEqual(actual.method, "POST")
        XCTAssertEqual(actual.path, "/api/system/pause")
        XCTAssertTrue(actual.body.isEmpty)
        XCTAssertEqual(server.writes.count, 1)
    }

    func testEssentialsPauseShowsPlainForegroundReviewAndExactRequestOnDemand() throws {
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server,
                                              extraArguments: ["--ui-test-dashboard-essentials"])
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.errorSummary"].firstMatch.waitForExistence(timeout: 10))
        assertBecomesOnline(miner)
        revealTelemetryControl(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        let pause = app.buttons["detail.quick.pause"]
        revealTelemetryControl(pause, in: app)
        pause.tap()
        let review = app.buttons["endpoint.send"]
        reveal(review, in: app)
        review.tap()
        let bar = app.navigationBars["Review before sending"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertTrue(bar.buttons["confirmation.cancel"].isHittable)
        XCTAssertFalse(review.isHittable)
        XCTAssertTrue(app.staticTexts["Pause mining?"].exists)
        XCTAssertTrue(app.staticTexts["This stops mining on this device until you resume."].exists)
        let method = app.descendants(matching: .any)["confirmation.methodAndPath"].firstMatch
        XCTAssertFalse(method.exists)
        let details = app.buttons["confirmation.showExactRequest"]
        reveal(details, in: app)
        XCTAssertEqual(details.value as? String, "Collapsed")
        recordScreenshot("Essentials - plain Pause review in front", app: app)
        details.tap()
        reveal(method, in: app)
        XCTAssertEqual(method.label, "POST /api/system/pause")
        XCTAssertTrue(app.staticTexts["No request body"].exists)
        recordScreenshot("Essentials - exact Pause request expanded", app: app)
        bar.buttons["confirmation.cancel"].tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
        assertNoWrites(server, for: 0.5)
    }
}
