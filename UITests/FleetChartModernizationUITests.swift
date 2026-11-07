import XCTest

/// UI tests verifying native chart selection, legend scrubbing, deselection, and window paging.
@MainActor
final class FleetChartModernizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testChartTapSelectionAndClearLifecycle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))

        XCTAssertFalse(app.buttons["dashboard.historyDisclosure"].exists)
        XCTAssertTrue(app.buttons["dashboard.historyRange.oneMinute"].waitForExistence(timeout: 5))
        showIndividualHistory(in: app)

        // Reveal the history section content
        let dailyHeader = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '1-minute average'")).firstMatch
        reveal(dailyHeader, in: app)
        XCTAssertTrue(dailyHeader.waitForExistence(timeout: 5))

        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        reveal(chart, in: app)
        XCTAssertTrue(chart.waitForExistence(timeout: 5))

        let legend = app.descendants(matching: .any)["dashboard.historyLegend"]
        XCTAssertTrue(legend.waitForExistence(timeout: 5))

        // Tap on the chart plot area (inset from margins) to select nearest valid point
        let chartPoint = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        chartPoint.tap()

        // Verify selected rate and timestamp appear
        let selectionRate = app.staticTexts["dashboard.historySelection.rate"]
        XCTAssertTrue(selectionRate.waitForExistence(timeout: 4))
        let selectionTime = app.staticTexts["dashboard.historySelection.timestamp"]
        XCTAssertTrue(selectionTime.exists)

        let selectedScreenshot = XCTAttachment(screenshot: app.screenshot())
        selectedScreenshot.name = "Interactive chart selected reading"
        selectedScreenshot.lifetime = .keepAlways
        add(selectedScreenshot)

        // Clear selection
        let clearBtn = app.buttons["dashboard.historySelection.clear"]
        XCTAssertTrue(clearBtn.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(clearBtn.frame.width, 44)
        XCTAssertGreaterThanOrEqual(clearBtn.frame.height, 44)
        let dailyControl = app.buttons["1m history"]
        XCTAssertTrue(dailyControl.exists)
        XCTAssertLessThanOrEqual(dailyControl.frame.maxY, legend.frame.minY,
                                 "Range controls must stay above, not overlap selected miner readings")
        reveal(legend, in: app)
        let legendScreenshot = XCTAttachment(screenshot: app.screenshot())
        legendScreenshot.name = "Selected legend and separate page controls"
        legendScreenshot.lifetime = .keepAlways
        add(legendScreenshot)
        reveal(clearBtn, in: app)
        clearBtn.tap()

        // Verify unselected summary returns
        XCTAssertFalse(clearBtn.exists)
        XCTAssertTrue(staticText(containing: "1-minute average", in: app).waitForExistence(timeout: 3))
    }

    func testChartPagingAcrossWindowsWorksUnselected() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))

        XCTAssertFalse(app.buttons["dashboard.historyDisclosure"].exists)
        XCTAssertTrue(app.buttons["dashboard.historyRange.oneMinute"].waitForExistence(timeout: 5))
        showIndividualHistory(in: app)

        let dailyHeader = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '1-minute average'")).firstMatch
        reveal(dailyHeader, in: app)
        XCTAssertTrue(dailyHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(staticText(containing: "1m · TH/s", in: app).waitForExistence(timeout: 5))

        // Start the swipe in the summary header, outside the chart plot's tap/selection
        // gesture. This exercises the parent timeframe pager without colliding with scrub.
        let dailyPage = app.descendants(matching: .any)["dashboard.historyWindow.daily"].firstMatch
        XCTAssertTrue(dailyPage.waitForExistence(timeout: 5))
        reveal(dailyPage, in: app)

        dailyPage.swipeLeft()
        XCTAssertTrue(staticText(containing: "7d · GH/s", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(staticText(containing: "No readings in this time window yet.", in: app).exists)

        app.chooseSavedHistoryWindow("monthly")
        XCTAssertTrue(staticText(containing: "30d · GH/s", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(staticText(containing: "No readings in this time window yet.", in: app).exists)
    }

    func testChartScrubbingUpdatesSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))

        XCTAssertFalse(app.buttons["dashboard.historyDisclosure"].exists)
        XCTAssertTrue(app.buttons["dashboard.historyRange.oneMinute"].waitForExistence(timeout: 5))
        showIndividualHistory(in: app)

        let dailyHeader = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '1-minute average'")).firstMatch
        reveal(dailyHeader, in: app)
        XCTAssertTrue(dailyHeader.waitForExistence(timeout: 5))

        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        reveal(chart, in: app)
        XCTAssertTrue(chart.waitForExistence(timeout: 5))

        // Tap at 35% across the plot area
        let startCoord = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        startCoord.tap()

        let clearBtn = app.buttons["dashboard.historySelection.clear"]
        XCTAssertTrue(clearBtn.waitForExistence(timeout: 4))

        let initialTime = app.staticTexts["dashboard.historySelection.timestamp"].label
        XCTAssertFalse(initialTime.isEmpty)

        // Drag/scrub to 75% across the plot area
        let endCoord = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        startCoord.press(forDuration: 0.2, thenDragTo: endCoord)

        // Verify selection is still visible
        XCTAssertTrue(clearBtn.exists)
        let newTimeLabel = app.staticTexts["dashboard.historySelection.timestamp"]
        XCTAssertTrue(newTimeLabel.waitForExistence(timeout: 3))

        // Verify timestamp updated from scrubbing
        let newTime = newTimeLabel.label
        XCTAssertNotEqual(newTime, initialTime,
                          "Scrubbing should update selected timestamp from \(initialTime) to a new sample")

        // Verify parent TabView did NOT swipe to weekly: heading must remain on the selected 1m range
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '1m'")).firstMatch.exists,
                      "Scrubbing must not trigger parent TabView page swipe")
    }

    private func showIndividualHistory(in app: XCUIApplication) {
        let daily = app.buttons["dashboard.historyRange.oneMinute"]
        reveal(daily, in: app)
        daily.tap()
        let mode = app.buttons["dashboard.historyDisplay"]
        reveal(mode, in: app)
        mode.tap()
        let individual = app.buttons["Individual miners"].firstMatch
        XCTAssertTrue(individual.waitForExistence(timeout: 5))
        individual.tap()
        XCTAssertEqual(mode.value as? String, "Individual miners")
    }

    private func staticText(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS '\(fragment)'")).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            let isAboveViewport = element.exists && element.frame.maxY < app.navigationBars.firstMatch.frame.maxY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: isAboveViewport ? 0.35 : 0.65))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: isAboveViewport ? 0.65 : 0.35))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable card control: \(element)")
    }
}
