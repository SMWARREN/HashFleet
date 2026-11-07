import XCTest
import UIKit

/// Demo-only acceptance of the native monitoring hierarchy. No device requests or writes.
@MainActor
final class NativeOverviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureDashboardAndMinerBaseline() throws {
        let app = launchDemo()
        defer { app.terminate() }
        capture("dashboard-top", app: app)
        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS %@", "Workshop Gamma")
        ).firstMatch
        reveal(miner, app: app)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Workshop Gamma"].waitForExistence(timeout: 8))
        capture("miner-detail-top", app: app)
    }

    func testVisibleTrendRangesSelectionAndMinerReturn() throws {
        let app = launchDemo()
        defer { app.terminate() }
        let chart = element("dashboard.historyChart", app)
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertTrue(chart.isHittable, "The trend must be visible without expanding a disclosure")
        XCTAssertFalse(app.buttons["dashboard.historyDisclosure"].exists)
        capture("overview-visible-trend", app: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["dashboard.historySelection.timestamp"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["dashboard.historySelection.rate"].label.contains("TH/s"))
        for id in ["weekly", "monthly", "yearly"] {
            app.chooseSavedHistoryWindow(id)
            XCTAssertTrue(app.staticTexts["No readings in this time window yet."].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["dashboard.historySelection.clear"].exists)
        }
        app.buttons["dashboard.historyRange.oneMinute"].tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let search = app.textFields["dashboard.search"].firstMatch
        reveal(search, app: app)
        search.tap()
        search.typeText("Workshop Gamma\n")
        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS %@", "Workshop Gamma")
        ).firstMatch
        reveal(miner, app: app)
        let display = app.buttons["dashboard.minerDisplay"]
        reveal(display, app: app)
        display.tap()
        let sort = app.buttons["Hashrate"].firstMatch
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        sort.tap()
        display.tap()
        let compact = app.buttons["Compact cards"].firstMatch
        XCTAssertTrue(compact.waitForExistence(timeout: 5))
        compact.tap()
        XCTAssertTrue(app.buttons["Expand Workshop Gamma card"].waitForExistence(timeout: 5))
        reveal(miner, app: app)
        let listY = miner.frame.minY
        capture("filtered-compact-miner-list", app: app)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Workshop Gamma"].waitForExistence(timeout: 8))
        XCTAssertTrue(element("detail.history", app).waitForExistence(timeout: 5))
        let detailChart = element("dashboard.historyChart", app)
        reveal(detailChart, app: app)
        XCTAssertFalse(app.staticTexts["1-minute average per-miner reading"].exists,
                       "Individual detail should not repeat the fleet breakdown summary")
        XCTAssertFalse(element("dashboard.historyLegend", app).exists,
                       "Individual detail should not show a one-miner legend")
        XCTAssertFalse(app.staticTexts["Recorded samples only. Gaps over 5 minutes are not connected."].exists,
                       "Individual detail should keep the chart focused")
        capture("miner-detail-trend", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Workshop Gamma")
        XCTAssertEqual(miner.frame.minY, listY, accuracy: 12, "Return must retain the filtered list position")
    }

    func testCPUTrendStaysSeparateAndNeverInventsSensors() throws {
        let app = launchDemo(extraArguments: ["--ui-testing-mixed-fleet"])
        defer { app.terminate() }
        XCTAssertTrue(element("dashboard.fleetHashrate", app).label.contains("SHA-256"))
        XCTAssertTrue(element("dashboard.cpuHashrate", app).label.contains("2.10 kH/s"))
        let source = app.buttons["dashboard.historyKind.cpu"]
        reveal(source, app: app)
        source.tap()
        let chart = element("dashboard.historyChart", app)
        reveal(chart, app: app)
        XCTAssertTrue((chart.value as? String ?? "").contains("1 miners"))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        let rate = app.staticTexts["dashboard.historySelection.rate"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        XCTAssertTrue(rate.label.contains("kH/s"), rate.label)
        XCTAssertFalse(rate.label.contains("TH/s"), rate.label)
        capture("cpu-only-chart-axis", app: app)
        app.chooseSavedHistoryWindow("weekly")
        XCTAssertTrue(app.staticTexts["No readings in this time window yet."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["7d · H/s"].exists, "An empty CPU window must not imply an ASIC-scale reading")
        app.buttons["dashboard.historyRange.oneMinute"].tap()
        let search = app.textFields["dashboard.search"].firstMatch
        reveal(search, app: app)
        search.tap()
        search.typeText("Sample CPU\n")
        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS %@", "Sample CPU")
        ).firstMatch
        reveal(miner, app: app)
        XCTAssertFalse(miner.label.contains("0 W"))
        XCTAssertFalse(miner.label.contains("0°C"))
        miner.tap()
        XCTAssertTrue(app.navigationBars["Sample CPU"].waitForExistence(timeout: 8))
        XCTAssertTrue(element("detail.history", app).waitForExistence(timeout: 5))
        reveal(element("dashboard.historyChart", app), app: app)
        XCTAssertFalse(app.staticTexts["0°C"].exists)
        XCTAssertFalse(app.staticTexts["0 W"].exists)
        capture("cpu-detail-honest-sensors", app: app)
    }

    func testLightLargestTextKeepsRangesAndMinerSearchReachable() throws {
        let app = launchDemo(extraArguments: ["--ui-test-light-appearance", "-UIPreferredContentSizeCategoryName",
                                              "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        XCTAssertTrue((app.buttons["dashboard.settingsMenu"].value as? String ?? "").contains("Light"))
        let minimumTapTarget = 44.0 - 0.01
        for id in ["oneMinute"] {
            let range = app.buttons["dashboard.historyRange.\(id)"]
            reveal(range, app: app)
            XCTAssertGreaterThanOrEqual(range.frame.height, minimumTapTarget)
            XCTAssertGreaterThanOrEqual(range.frame.width, minimumTapTarget)
            XCTAssertGreaterThanOrEqual(range.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(range.frame.maxX, app.frame.maxX)
        }
        let recent = app.buttons["dashboard.historyRange.oneMinute"]
        XCTAssertTrue(recent.exists, "The newest data-backed range must remain reachable at largest text")
        app.chooseSavedHistoryWindow("yearly")
        XCTAssertTrue(app.staticTexts["No readings in this time window yet."].waitForExistence(timeout: 5))
        capture("light-largest-text-empty-yearly-range", app: app)
        reveal(recent, app: app)
        recent.tap()
        let chart = element("dashboard.historyChart", app)
        reveal(chart, app: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        let selected = app.staticTexts["dashboard.historySelection.rate"]
        reveal(selected, app: app)
        XCTAssertTrue(selected.label.contains("TH/s"))
        let clear = app.buttons["dashboard.historySelection.clear"]
        reveal(clear, app: app)
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
        clear.tap()
        XCTAssertTrue(element("dashboard.soloOddsWindows", app).exists)
        for window in ["day", "month", "year"] {
            let control = app.buttons["dashboard.soloOddsWindow.\(window)"]
            reveal(control, app: app)
            XCTAssertGreaterThanOrEqual(control.frame.height, minimumTapTarget)
            XCTAssertGreaterThanOrEqual(control.frame.width, minimumTapTarget)
            control.tap()
        }
        let search = app.textFields["dashboard.search"].firstMatch
        reveal(search, app: app)
        search.tap()
        search.typeText("Workshop Gamma\n")
        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS %@", "Workshop Gamma")
        ).firstMatch
        reveal(miner, app: app)
        capture("light-largest-text-filtered-miners", app: app)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Workshop Gamma"].waitForExistence(timeout: 8))
    }

    func testSystemReduceMotionKeepsNativeChartInspectionUsable() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        addTeardownBlock { settings.terminate() }
        let accessibility = settings.buttons["Accessibility"].firstMatch
        XCTAssertTrue(accessibility.waitForExistence(timeout: 15), "Settings must finish exposing its real controls")
        reveal(accessibility, app: settings)
        accessibility.tap()
        let motion = settings.buttons["Motion"].firstMatch
        reveal(motion, app: settings)
        motion.tap()
        let reduceMotion = settings.switches["Reduce Motion"].firstMatch
        XCTAssertTrue(reduceMotion.waitForExistence(timeout: 5))
        let wasEnabled = reduceMotion.value as? String == "1"
        addTeardownBlock {
            settings.activate()
            if (reduceMotion.value as? String == "1") != wasEnabled {
                reduceMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            }
            let restored = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", wasEnabled ? "1" : "0"), object: reduceMotion
            )
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed, "Restore the owned simulator setting")
        }
        if !wasEnabled {
            reduceMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let turnedOn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: reduceMotion)
        XCTAssertEqual(XCTWaiter.wait(for: [turnedOn], timeout: 5), .completed)
        capture("owned-simulator-system-reduce-motion-on", app: settings)
        let enabled = NSPredicate { _, _ in UIAccessibility.isReduceMotionEnabled }
        expectation(for: enabled, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        let app = launchDemo()
        addTeardownBlock { app.terminate() }
        let chart = element("dashboard.historyChart", app)
        reveal(chart, app: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["dashboard.historySelection.timestamp"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["dashboard.historySelection.rate"].label.contains("TH/s"))
        capture("system-reduce-motion-native-chart-selection", app: app)
        app.buttons["dashboard.historySelection.clear"].tap()
        XCTAssertFalse(app.buttons["dashboard.historySelection.clear"].exists)
    }

    func testGoldFleetTrendKeepsIndividualInspectionAvailable() throws {
        let app = launchDemo()
        addTeardownBlock { app.terminate() }
        let mode = app.buttons["dashboard.historyDisplay"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertEqual(mode.value as? String, "Fleet total")
        let chart = element("dashboard.historyChart", app)
        reveal(chart, app: app)
        XCTAssertTrue((chart.value as? String ?? "").contains("3 miners"))
        XCTAssertFalse(element("dashboard.historyLegend", app).exists)
        capture("website-style-gold-fleet-default", app: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        let selected = app.staticTexts["dashboard.historySelection.rate"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.label.contains("TH/s"))
        let total = try XCTUnwrap(Double(selected.label.components(separatedBy: " ").first ?? ""))
        XCTAssertGreaterThan(total, 2.8)
        XCTAssertLessThan(total, 3.3)
        capture("website-style-gold-fleet-inspection", app: app)
        reveal(mode, app: app)
        mode.tap()
        let individual = app.buttons["Individual miners"].firstMatch
        XCTAssertTrue(individual.waitForExistence(timeout: 5))
        individual.tap()
        XCTAssertTrue(app.staticTexts["1-minute average per-miner reading"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("dashboard.historyLegend", app).exists)
        XCTAssertFalse(app.buttons["dashboard.historySelection.clear"].exists)
        capture("individual-miner-breakdown", app: app)
        mode.tap()
        app.buttons["Fleet total"].firstMatch.tap()
        XCTAssertEqual(mode.value as? String, "Fleet total")
        XCTAssertFalse(element("dashboard.historyLegend", app).exists)
    }

    func testWebsiteRangesAndMinerControlsMatchRequestedHierarchy() throws {
        let app = launchDemo()
        defer { app.terminate() }
        let bitsy = element("dashboard.bitsy", app)
        let hashNumbers = element("dashboard.fleetHashrate", app)
        let history = element("dashboard.history", app)
        XCTAssertTrue(bitsy.waitForExistence(timeout: 5))
        XCTAssertTrue(hashNumbers.waitForExistence(timeout: 5))
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertLessThan(bitsy.frame.maxY, hashNumbers.frame.minY, "Bitsy belongs above the hash numbers")
        XCTAssertLessThan(hashNumbers.frame.maxY, history.frame.minY, "Hash numbers belong above the history chart")
        XCTAssertLessThanOrEqual(history.frame.height, 170,
                                 "The history card should stay compact beneath live hashrate")
        let compactChart = element("dashboard.historyChart", app)
        XCTAssertTrue(compactChart.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(compactChart.frame.height, 100,
                                 "The history graph should not grow into a second hero card")
        let odds = element("dashboard.chains", app)
        XCTAssertTrue(odds.waitForExistence(timeout: 5))
        XCTAssertLessThan(history.frame.maxY, odds.frame.minY, "Solo odds belongs below the history chart")
        XCTAssertTrue(element("dashboard.historyRanges", app).exists, "Data-backed recent ranges share one control group")
        let oneMinute = app.buttons["dashboard.historyRange.oneMinute"]
        XCTAssertTrue(oneMinute.exists, "A phone dashboard with no user-selected range should expose 1m")
        XCTAssertTrue(oneMinute.isSelected, "The phone dashboard should start on the 1m range")
        capture("website-ranges-data-backed", app: app)
        XCTAssertFalse(app.buttons["dashboard.historyRange.weekly"].exists, "Longer history belongs in the secondary menu")
        XCTAssertTrue(element("dashboard.soloOddsWindows", app).exists)
        for window in ["day", "month", "year"] {
            let control = app.buttons["dashboard.soloOddsWindow.\(window)"]
            reveal(control, app: app)
            XCTAssertTrue(control.exists)
            // Keep the visual chip compact while preserving the standard native hit target.
            let minimumTapTarget = 44.0 - 0.01
            XCTAssertGreaterThanOrEqual(control.frame.width, minimumTapTarget)
            XCTAssertGreaterThanOrEqual(control.frame.height, minimumTapTarget)
            control.tap()
        }
        let minimumTapTarget = 44.0 - 0.01
        XCTAssertGreaterThanOrEqual(oneMinute.frame.width, minimumTapTarget)
        XCTAssertGreaterThanOrEqual(oneMinute.frame.height, minimumTapTarget)
        oneMinute.tap()
        XCTAssertTrue(app.staticTexts["1m · TH/s"].waitForExistence(timeout: 5))
        let chart = element("dashboard.historyChart", app)
        reveal(chart, app: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["dashboard.historySelection.clear"].waitForExistence(timeout: 5))
        app.chooseSavedHistoryWindow("weekly")
        XCTAssertFalse(app.buttons["dashboard.historySelection.clear"].exists)
        let search = app.textFields["dashboard.search"].firstMatch
        reveal(search, app: app)
        search.tap()
        search.typeText("Workshop Gamma\n")
        let best = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH 'Best reported share difficulty'")
        ).firstMatch
        let sessionBest = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH 'Session best reported share difficulty'")
        ).firstMatch
        reveal(best, app: app)
        reveal(sessionBest, app: app)
        XCTAssertEqual(best.frame.minY, sessionBest.frame.minY, accuracy: 2,
                       "Best and session best should remain on one line")
        XCTAssertGreaterThan(sessionBest.frame.minX, best.frame.maxX,
                             "Session best should follow Best on the same line")
        let controls = app.buttons["Controls for Workshop Gamma"]
        reveal(controls, app: app)
        let settingsPrefix = "dashboard.card.settings."
        let minerID = String(controls.identifier.dropFirst(settingsPrefix.count))
        let expand = app.buttons["dashboard.card.expand.\(minerID)"]
        reveal(expand, app: app)
        let status = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.status.'")
        ).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Sample"), "Demo readings must not be labeled Live")
        XCTAssertGreaterThanOrEqual(controls.frame.minY, status.frame.maxY,
                                   "The arrow and controls column must stay below the status row")
        XCTAssertGreaterThanOrEqual(controls.frame.maxX, status.frame.maxX,
                                   "Controls should remain on the card's trailing edge")
        XCTAssertLessThanOrEqual(expand.frame.minY, controls.frame.minY,
                                 "The arrow must stay above the compact Controls button")
        XCTAssertGreaterThanOrEqual(controls.frame.height, 44.0 - 0.01)
        capture("miner-status-with-independent-controls", app: app)
        controls.tap()
        XCTAssertTrue(app.buttons["Cooling"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pools"].exists)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].exists, "Opening Controls must not activate the sibling miner link")
    }

    func testWideOverviewAndDetailKeepChartsWithinVisibleBounds() {
        let app = launchDemo()
        addTeardownBlock { app.terminate() }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.frame.width > app.frame.height },
            object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed,
                       "The overview must enter the wide layout before checking chart bounds.")
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        let chart = element("dashboard.historyChart", app)
        reveal(chart, app: app)
        XCTAssertGreaterThanOrEqual(chart.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(chart.frame.maxX, app.frame.maxX)
        XCTAssertTrue((chart.value as? String ?? "").contains("3 miners"),
                      "The wide chart must expose its fleet aggregate accessibility summary")
        capture("wide-overview-history-bounds", app: app)
        let search = app.textFields["dashboard.search"].firstMatch
        reveal(search, app: app)
        search.tap()
        search.typeText("Workshop Gamma\n")
        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS %@", "Workshop Gamma")
        ).firstMatch
        reveal(miner, app: app)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Workshop Gamma"].firstMatch.waitForExistence(timeout: 8))
        let history = element("detail.history", app)
        reveal(history, app: app)
        let detailChart = element("dashboard.historyChart", app)
        XCTAssertGreaterThanOrEqual(detailChart.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(detailChart.frame.maxX, app.frame.maxX)
        capture("wide-miner-recorded-history", app: app)
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launchDemo(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Hash Fleet"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Demo · simulated readings"].waitForExistence(timeout: 5))
        return app
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<22 {
            if element.exists && element.isHittable { return }
            let above = element.exists && element.frame.maxY < app.navigationBars.firstMatch.frame.maxY
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.3 : 0.7))
                .press(forDuration: 0.01, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.7 : 0.3)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable native control: \(element)")
    }
}
