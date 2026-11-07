import XCTest

/// Shared launch, scroll, and assertion helpers for MinerCardInteractionUITests.
extension MinerCardInteractionUITests {
    func launchDemo(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"] + extraArguments
        app.launch()
        assertNoLegacyModeSelector(in: app)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        return app
    }

    func openFirstMiner(_ app: XCUIApplication) {
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        // Lazy grid rows at large text sizes are created only as the user scrolls to them.
        reveal(miner, app)
        tapVisible(miner, app)
        XCTAssertTrue(app.buttons["detail.quick.tuning"].waitForExistence(timeout: 5))
    }

    func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func assertIndependentHeader(_ disclosure: XCUIElement, settings: XCUIElement) {
        XCTAssertTrue(disclosure.isHittable)
        XCTAssertTrue(settings.isHittable)
        XCTAssertLessThanOrEqual(disclosure.frame.maxX, settings.frame.minX,
                                 "Disclosure hit area must not swallow the nearby settings route.")
    }

    func waitForValue(_ value: String, on element: XCUIElement) {
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 3), .completed)
    }

    func toggle(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    func reveal(_ element: XCUIElement, _ app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<20 {
            if element.exists && element.isHittable { return }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        capture("Unreachable card interaction target", app)
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable element: \(element)")
    }

    /// A large Dynamic Type miner row can exceed the viewport. Tap its visible content rather
    /// than its offscreen center, which might land on the tab bar.
    func tapVisible(_ element: XCUIElement, _ app: XCUIApplication) {
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let bottom = app.windows.firstMatch.frame.maxY - 8
        let viewport = CGRect(x: 0, y: top, width: app.frame.width, height: max(0, bottom - top))
        let visible = element.frame.intersection(viewport)
        XCTAssertFalse(visible.isNull || visible.isEmpty)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
    }

    func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The previous sample and genuine faults must survive a failed refresh too.
    func assertRefreshFailureKeepsTelemetry(app: XCUIApplication, server: LoopbackMinerServer) {
        server.setInfoResponse(status: 503, json: #"{"error":"Fixture unavailable"}"#)
        app.navigationBars.buttons["Refresh"].tap()
        let error = element("detail.telemetryError", app)
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["LAST KNOWN HASHRATE"].exists)
        XCTAssertTrue(element("detail.sampleAge", app).exists)
        XCTAssertTrue(element("detail.reportedFaults", app).exists)
    }

    /// Stale cached cooling settings remain readable, but the review route is locked and
    /// cannot advance toward a write while the miner is unreachable.
    func verifyStaleCoolingReviewLock(app: XCUIApplication, server: LoopbackMinerServer) {
        let settings = app.buttons["detail.cooling.settings"]
        reveal(settings, app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Cooling"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Temperature target (°C)"].value as? String, "60")
        let review = app.buttons["Review cooling change"]
        reveal(review, app)
        XCTAssertFalse(review.isEnabled, "Stale telemetry must lock review before any write path.")
        XCTAssertTrue(server.writes.isEmpty)
        let unexpectedWrite = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !server.writes.isEmpty }, object: nil)
        unexpectedWrite.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedWrite], timeout: 1), .completed)
        XCTAssertTrue(server.writes.isEmpty, "Opening stale cached settings must never write to the miner.")
    }
}
