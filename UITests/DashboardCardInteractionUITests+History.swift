import XCTest

/// History window pager, connection-error, empty-state, and legacy artifact coverage
/// for DashboardCardInteractionUITests.
extension DashboardCardInteractionUITests {
    func testMinerConnectionErrorIsVisibleOnDashboardAndCard() throws {
        let server = try LoopbackMinerServer()
        server.setInfoResponse(status: 503, json: #"{"error":"Fixture unavailable"}"#)
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        addFixture(address, in: app)

        let summary = app.descendants(matching: .any)["dashboard.errorSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(summary.label.contains("Fleet attention"), summary.label)
        XCTAssertTrue(summary.label.contains("unreachable"), summary.label)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 5))
        XCTAssertTrue(miner.label.contains("Unreachable"), miner.label)
        let error = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.error.'"))
            .firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(error.label.contains("Connection error"), error.label)
        XCTAssertTrue(server.writes.isEmpty)
        capture("Dashboard exposes miner connection error", app)
    }

    func testHistoryWindowPagerSupportsDailyWeeklyMonthlyYearlyWindows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["dashboard.historyDisclosure"].exists)
        XCTAssertTrue(app.buttons["dashboard.historyRange.oneMinute"].waitForExistence(timeout: 5))
        app.buttons["dashboard.historyRange.oneMinute"].tap()

        let display = app.buttons["dashboard.historyDisplay"]
        reveal(display, in: app)
        display.tap()
        let individual = app.buttons["Individual miners"]
        XCTAssertTrue(individual.waitForExistence(timeout: 5))
        individual.tap()
        XCTAssertEqual(display.value as? String, "Individual miners")

        let daily = app.staticTexts["1-minute average per-miner reading"]
        reveal(daily, in: app)
        expectText(containing: "1m · TH/s", in: app)
        expectText(containing: "1-minute average", in: app)

        // Demo telemetry intentionally stays in-memory and does not seed the persistent
        // historical database. Use the accessible timeframe controls and verify the
        // empty-window state for periods without stored readings.
        app.chooseSavedHistoryWindow("weekly")
        expectText(containing: "7d · GH/s", in: app)
        expectText(containing: "No readings in this time window yet.", in: app)

        app.chooseSavedHistoryWindow("monthly")
        expectText(containing: "30d · GH/s", in: app)
        expectText(containing: "No readings in this time window yet.", in: app)

        app.chooseSavedHistoryWindow("yearly")
        expectText(containing: "365d · GH/s", in: app)
        expectText(containing: "No readings in this time window yet.", in: app)
        capture("History window pager reaches every timeframe", app)
    }

    func testHistoryWindowShowsEmptySelectedWindowAndEmptyReadingHistory() throws {
        let staleApp = XCUIApplication()
        staleApp.launchArguments = ["--ui-testing", "--demo", "--ui-testing-history-stale-daily"]
        staleApp.launch()
        defer { staleApp.terminate() }

        XCTAssertTrue(staleApp.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        XCTAssertTrue(staleApp.buttons["dashboard.historyRange.oneMinute"].waitForExistence(timeout: 5))
        XCTAssertTrue(staleApp.staticTexts["No readings in this time window yet."].waitForExistence(timeout: 5))

        // The empty-window placeholder page is shorter than the pager, so a swipe over
        // it is not reliably delivered to the page gesture. Reveal and use the accessible
        // page control, which is also the reliable VoiceOver path.
        staleApp.chooseSavedHistoryWindow("weekly")
        XCTAssertTrue(staleApp.staticTexts["7d · GH/s"].waitForExistence(timeout: 5))
        XCTAssertTrue(staleApp.staticTexts["No readings in this time window yet."].exists)
        staleApp.terminate()

        let emptyApp = XCUIApplication()
        emptyApp.launchArguments = ["--ui-testing", "--demo", "--ui-testing-history-empty"]
        emptyApp.launch()
        defer { emptyApp.terminate() }

        XCTAssertTrue(emptyApp.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        XCTAssertTrue(emptyApp.buttons["dashboard.historyRange.oneMinute"].waitForExistence(timeout: 5))
        let emptyWindow = emptyApp.staticTexts["No readings in this time window yet."]
        XCTAssertTrue(emptyWindow.waitForExistence(timeout: 5))
        XCTAssertFalse(emptyApp.staticTexts["Your history will appear here over time."].exists)
        reveal(emptyWindow, in: emptyApp)
        XCTAssertTrue(emptyWindow.isHittable)
        capture("History empty selected-window state", emptyApp)
    }

    func testDashboardDoesNotExposeLegacyCharacterVisualArtifacts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["AxePet"].exists)
        XCTAssertFalse(app.images["AxePet"].exists)
        XCTAssertFalse(app.images["character"].exists)
        XCTAssertFalse(app.otherElements["MinerCharacterProfile"].exists)
        XCTAssertFalse(app.staticTexts["character"].exists)

        let miners = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'"))
        XCTAssertTrue(miners.firstMatch.waitForExistence(timeout: 5))
        capture("Dashboard without legacy character visual artifacts", app)
    }

    private func expectText(containing fragment: String, in app: XCUIApplication) {
        let match = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5))
    }
}
