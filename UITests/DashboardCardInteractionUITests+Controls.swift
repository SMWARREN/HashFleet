import XCTest

extension DashboardCardInteractionUITests {
    func openCockpit(in app: XCUIApplication, fromMinerDetail: Bool = false) {
        if fromMinerDetail {
            XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
            let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
            reveal(miner, in: app)
            miner.tap()
            let tuning = app.buttons["detail.quick.tuning"]
            XCTAssertTrue(tuning.waitForExistence(timeout: 5))
            reveal(tuning, in: app)
            tuning.tap()
            XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
            selectAdvancedTuningControls(in: app)
            return
        }
        let controls = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")
        ).firstMatch
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        // At accessibility text sizes the first lazy miner card begins below the viewport.
        reveal(controls, in: app)
        XCTAssertTrue(controls.exists)
        capture("Visible dashboard Controls before opening cockpit", app)
        print("CONTROLS_FRAME=\(controls.frame) TAB_BAR_FRAME=\(app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .zero)")
        // SwiftUI exposes nested buttons for a Menu. Touch the visible capsule center,
        // rather than letting XCTest choose an activation point on its outer AX wrapper.
        controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let session = fleetTuningSessionMenuItem(in: app)
        XCTAssertTrue(session.waitForExistence(timeout: 5), app.debugDescription)
        session.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        selectAdvancedTuningControls(in: app)
    }

    func reviewCockpit(in app: XCUIApplication) {
        app.buttons["tuningSession.jump.apply"].tap()
        XCTAssertTrue(app.staticTexts["tuningSession.payload"].waitForExistence(timeout: 5))
    }

    func numericReading(_ element: XCUIElement) throws -> Double {
        XCTAssertTrue(element.exists, element.description)
        return try XCTUnwrap(Double(element.label.split(separator: " ").first.map(String.init) ?? ""))
    }

    func cockpitPayload(in app: XCUIApplication) throws -> [String: Any] {
        let data = Data(app.staticTexts["tuningSession.payload"].label.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testCollapsedCardKeepsMissingHashrateAndReportedFaultVisible() throws {
        let server = try LoopbackMinerServer()
        let pausedJSON = #"{"ASICModel":"BM1370","hostname":"paused-fixture","miningPaused":true,"# +
            #""temp":51,"power":20,"fanspeed":40}"#
        server.setInfoResponse(status: 200, json: pausedJSON)
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        addFixture(address, in: app)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        let reportedPredicate = NSPredicate(format: "label CONTAINS 'Mining paused'")
        let reported = XCTNSPredicateExpectation(predicate: reportedPredicate, object: miner)
        XCTAssertEqual(XCTWaiter.wait(for: [reported], timeout: 10), .completed)
        let expansion = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.expand.'")).firstMatch
        reveal(expansion, in: app)
        expansion.tap()
        waitForValue("Collapsed", on: expansion)
        XCTAssertTrue(miner.label.contains("Not reported"), miner.label)
        XCTAssertTrue(miner.label.contains("Mining paused"), miner.label)
        XCTAssertFalse(miner.label.contains("Updated"), "Per-miner freshness belongs in the dashboard hero")
        XCTAssertTrue(miner.label.contains("Online"), miner.label)
        XCTAssertFalse(miner.label.contains("Temperature"), miner.label)
        let dashboardMode = app.descendants(matching: .any).matching(identifier: "dashboard.refreshMode").firstMatch
        XCTAssertTrue(dashboardMode.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(dashboardMode.label.contains("Updated"), dashboardMode.label)
        XCTAssertTrue(server.writes.isEmpty)
        capture("Collapsed paused miner does not hide missing telemetry or faults", app)
    }

    func testLargestTextKeepsExpansionAndSettingsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        let expansion = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.expand.'")).firstMatch
        reveal(expansion, in: app)
        let id = String(expansion.identifier.dropFirst("dashboard.card.expand.".count))
        expansion.tap()
        waitForValue("Collapsed", on: expansion)
        let settings = app.buttons["dashboard.card.settings.\(id)"]
        reveal(settings, in: app)
        XCTAssertGreaterThanOrEqual(settings.frame.width, 44)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        capture("Largest text card controls remain reachable", app)
        settings.tap()
        let cooling = app.buttons["dashboard.card.settingsRoute.cooling"]
        XCTAssertTrue(cooling.waitForExistence(timeout: 5))
        cooling.tap()
        XCTAssertTrue(app.navigationBars["Cooling"].waitForExistence(timeout: 5))
    }

    internal func addFixture(_ address: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 10))
        app.buttons["dashboard.addMiner"].tap()
        let addressField = app.textFields["addMiner.address"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
        addressField.tap()
        addressField.typeText(address + "\n")
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
    }

    func waitForValue(_ value: String, on element: XCUIElement) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    internal func reveal(_ element: XCUIElement, in app: XCUIApplication, requireHittable: Bool = true) {
        revealFleetControl(element, in: app, requireHittable: requireHittable)
    }

    func captureSettled(_ name: String, _ app: XCUIApplication) {
        // The numeric content transition runs after the value is already correct in AX.
        // Let its short spring settle so retained screenshots show digits, not motion blur.
        let settledAt = Date().addingTimeInterval(0.6)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Date() >= settledAt
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 2), .completed)
        capture(name, app)
    }

    internal func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func hashrateJSON(_ rate: Int) -> String {
        #"{"hostname":"Gamma","ASICModel":"BM1370","hashRate":\#(rate),"power":19,"# +
            #""temp":45,"fanspeed":40,"bestDiff":"18.4G","bestSessionDiff":"1.2G","# +
            #""stratumURL":"solo.ckpool.org","isUsingFallbackStratum":false}"#
    }
}
