import XCTest

/// Dashboard controls must remain independent of the details link and never send settings writes.
@MainActor
final class DashboardCardInteractionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func openOriginalMiner(_ app: XCUIApplication, essentials: Bool = true, extraArguments: [String] = []) {
        // Use the same entry dashboard as the preview, but never enable the detail
        // opt-in. The caller can run these walkthroughs against the untouched source.
        app.launchArguments = numberFirstArguments + (essentials ? ["--ui-test-dashboard-essentials"] : []) + extraArguments
        app.launch()
        let miner = firstNumberFirstMiner(in: app)
        reveal(miner, in: app)
        XCTAssertTrue(miner.label.contains("Little Supra"), miner.label)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Little Supra"].waitForExistence(timeout: 8))
        XCTAssertFalse(minerReading("detail.previewHashrate", in: app).exists)
    }

    func openOriginalMoreReadings(_ app: XCUIApplication) {
        let more = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "More miner readings")).firstMatch
        reveal(more, in: app)
        more.tap()
    }

    func assertRemovedPreviewSections(_ app: XCUIApplication) {
        for id in ["detail.asicTelemetry.disclosure", "detail.poolDiagnostics", "detail.poolsDisclosure",
                   "detail.apiToolsDisclosure", "detail.advancedSection", "detail.endpointExplorer"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].firstMatch.exists, "Unexpected legacy section: \(id)")
        }
        XCTAssertFalse(app.staticTexts["ASIC Registers"].exists)
        XCTAssertFalse(app.staticTexts["Pool connection"].exists)
    }

    func openTuningPreview(
        _ app: XCUIApplication, essentials: Bool, largest: Bool = false, extraArguments: [String] = []
    ) {
        openNumberFirstMinerDetail(app, essentials: essentials, largest: largest,
            extraArguments: ["--preview-number-first-tuning"] + extraArguments)
        let tuning = app.buttons["detail.previewControls.tuning"]
        reveal(tuning, in: app)
        tuning.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["tuning.preview.readings"].waitForExistence(timeout: 5))
    }

    func assertTuningMeasurements(in app: XCUIApplication) {
        for (name, expected) in [("hashrate", "638 GH/s"), ("temperature", "59 °C"),
                                 ("clock", "521 MHz"), ("voltage", "1128 mV")] {
            XCTAssertEqual(app.staticTexts["tuning.preview.readings.\(name)"].label, expected)
        }
    }

    var settingsHubDestinations: [(String, String)] {
        [("general", "General"), ("pools", "Pools"), ("display", "Display"), ("cooling", "Cooling"),
         ("tuning", "Frequency & voltage"), ("restart", "Restart device")]
    }

    func openSettingsHubPreview(
        _ app: XCUIApplication, essentials: Bool, largest: Bool = false, captureEntry: Bool = false,
        extraArguments: [String] = []
    ) {
        openNumberFirstMinerDetail(app, essentials: essentials, largest: largest,
            extraArguments: ["--preview-number-first-settings-hub", "--preview-number-first-cooling"] + extraArguments)
        let settings = app.buttons["detail.previewControls.settings"]
        reveal(settings, in: app)
        assertTapTarget(settings)
        if captureEntry { capture("\(essentials ? "Essentials" : "Full View") Miner settings entry", app) }
        settings.tap()
        XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 5))
    }

    func verifySettingsHubCategories(_ app: XCUIApplication, checks: [(String, String)]) throws {
        for (id, title) in checks {
            let row = app.buttons["settings.preview.\(id)"]
            reveal(row, in: app)
            assertTapTarget(row)
            row.tap()
            let navigationBar = app.navigationBars[title]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5), "Expected \(title)")
            if id == "restart" {
                let send = app.buttons["endpoint.send"]
                reveal(send, in: app)
                XCTAssertFalse(send.isEnabled)
            } else if id == "compatibility" {
                let check = app.buttons["compatibility.check"]
                reveal(check, in: app)
                XCTAssertFalse(check.isEnabled)
            } else if id == "tuning" {
                XCTAssertTrue(app.descendants(matching: .any)["tuningSession.screen"].firstMatch.exists)
            } else if id == "firmware" {
                XCTAssertTrue(app.staticTexts["Demo release example · no install"].exists)
            }
            let back = try XCTUnwrap(navigationBar.buttons.allElementsBoundByIndex.first,
                                     "Native back button is required to return to the hub")
            back.tap()
            XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 5))
        }
    }

    func verifySettingsRestartAppliesInPlace(
        _ app: XCUIApplication, captureName: String = "Essentials Restart from Miner settings"
    ) {
        let restart = app.buttons["settings.preview.restart"]
        reveal(restart, in: app)
        assertTapTarget(restart)
        let result = app.staticTexts["settings.preview.restartResult"]
        XCTAssertFalse(result.exists)
        restart.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "Restart simulated. Nothing sent.")
        assertStayedOnPage("Miner settings", in: app)
        reveal(result, in: app, requireHittable: false)
        capture(captureName, app)
    }

    func openCooling(
        _ app: XCUIApplication, essentials: Bool, largest: Bool = false, extraArguments: [String] = []
    ) {
        openNumberFirstMinerDetail(app, essentials: essentials, largest: largest,
                                   extraArguments: ["--preview-number-first-cooling"] + extraArguments)
        let cooling = app.buttons["detail.previewControls.cooling"]
        reveal(cooling, in: app)
        cooling.tap()
        XCTAssertTrue(app.navigationBars["Cooling"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cooling.commit"].waitForExistence(timeout: 5))
    }

    func stepCooling(_ field: String, in app: XCUIApplication, increasing: Bool, to value: Int) {
        let button = app.buttons["cooling.\(field).\(increasing ? "increase" : "decrease")"]
        reveal(button, in: app)
        assertTapTarget(button)
        button.tap()
        let reading = app.staticTexts["cooling.\(field).value"]
        XCTAssertTrue(reading.label.contains(": \(value) "), reading.label)
    }

    func openNumberFirstMinerDetail(
        _ app: XCUIApplication, essentials: Bool, largest: Bool, extraArguments: [String] = []
    ) {
        app.launchArguments = numberFirstArguments + ["--preview-number-first-detail"]
            + (essentials ? ["--ui-test-dashboard-essentials"] : [])
            + ["-UIPreferredContentSizeCategoryName", largest ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            + extraArguments
        app.launch()
        let miner = firstNumberFirstMiner(in: app)
        reveal(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Little Supra"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["detail.previewHashrate"].firstMatch.waitForExistence(timeout: 5))
    }

    func assertNumberFirstMinerReadings(_ app: XCUIApplication) -> XCUIElement {
        let rate = app.descendants(matching: .any)["detail.previewHashrate"].firstMatch
        let temperature = app.descendants(matching: .any)["detail.hero.temperature"].firstMatch
        let power = app.descendants(matching: .any)["detail.hero.power"].firstMatch
        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["detail.previewDemoNotice"].firstMatch.exists)
        XCTAssertEqual(rate.value as? String, "638 GH/s")
        XCTAssertEqual(temperature.value as? String, "59 degrees Celsius")
        XCTAssertEqual(power.value as? String, "12.4 watts")
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertTrue((chart.value as? String ?? "").contains("Last minute"))
        XCTAssertLessThan(rate.frame.maxY, min(temperature.frame.minY, power.frame.minY))
        XCTAssertLessThan(max(temperature.frame.maxY, power.frame.maxY), chart.frame.minY)
        return chart
    }

    var minerQuickActions: [(id: String, title: String)] {
        [("identify", "Identify device"), ("pause", "Pause mining"),
         ("resume", "Resume mining"), ("restart", "Restart device")]
    }

    func minerReading(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    func assertRestoredShareReadings(_ app: XCUIApplication) {
        let expected = [("accepted", "Accepted, 13,926"), ("rejected", "Rejected, 3"),
                        ("rejectedPercentage", "Rejected share rate, 0.02%")]
        let temperature = minerReading("detail.hero.temperature", in: app)
        for (id, label) in expected {
            let share = minerReading("detail.shares.\(id)", in: app)
            XCTAssertEqual(share.label, label)
            XCTAssertLessThan(share.frame.maxY, temperature.frame.minY)
        }
        XCTAssertTrue(app.staticTexts["2× BM1368"].exists)
        XCTAssertEqual(minerReading("detail.uptime", in: app).label, "Uptime 2d 20h 17m 0s")
        XCTAssertTrue(minerReading("detail.sampleAge", in: app).exists)
    }

    func verifyOneTapMinerQuickActions(_ app: XCUIApplication) {
        let result = app.staticTexts["detail.previewControls.result"]
        XCTAssertFalse(result.exists, "Opening the screen must not perform an action")
        for (id, title) in minerQuickActions {
            let applied = applyPreviewQuickAction(id, in: app)
            reveal(applied, in: app, requireHittable: false)
            capture("Essentials \(title) applied in place", app)
        }
    }

    func captureMinerQuickActionRoutes(_ app: XCUIApplication, mode: String) {
        for (id, title) in minerQuickActions {
            let button = app.buttons["detail.quick.\(id)"]
            reveal(button, in: app)
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Demo mode: writes are locked and explorer requests never contact a device."].exists)
            let send = app.buttons["endpoint.send"]
            XCTAssertTrue(send.exists)
            XCTAssertFalse(send.isEnabled)
            capture("\(mode) \(title)", app)
            app.navigationBars[title].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Little Supra"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["detail.previewControls.result"].exists)
        }
    }

    func applyPreviewQuickAction(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let text = ["identify": "Device signal simulated. Nothing sent.", "pause": "Mining paused in demo. Nothing sent.",
                    "resume": "Mining resumed in demo. Nothing sent.", "restart": "Restart simulated. Nothing sent."]
        let button = app.buttons["detail.quick.\(id)"]
        reveal(button, in: app)
        assertTapTarget(button)
        button.tap()
        let results = app.staticTexts.matching(identifier: "detail.previewControls.result")
        let result = results.firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, text[id])
        XCTAssertEqual(results.count, 1, "Show just the latest action result")
        assertStayedOnPage("Little Supra", in: app)
        return result
    }

    func assertStayedOnPage(_ title: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars[title].exists)
        for (_, actionTitle) in minerQuickActions {
            XCTAssertFalse(app.navigationBars[actionTitle].exists)
        }
        XCTAssertFalse(app.buttons["endpoint.send"].exists)
        XCTAssertFalse(app.navigationBars["Review before sending"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func chooseSoloOption(_ title: String, id: String, in app: XCUIApplication) {
        app.buttons["dashboard.soloOptions"].tap()
        let action = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, title)).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), "Missing Solo odds menu action \(title)")
        action.tap()
    }

    @discardableResult
    func assertCompactPreviewLayout(in app: XCUIApplication, largestType: Bool) -> CGFloat {
        let chartHeading = app.staticTexts["Hashrate trend"].firstMatch
        let fleetHeading = app.staticTexts["Fleet hashrate"].firstMatch
        let rate = app.descendants(matching: .any)["dashboard.fleetHashrate"].firstMatch
        let notice = app.staticTexts["dashboard.bitsy"].firstMatch
        let exit = app.buttons["dashboard.exitDemo"]
        let miners = app.staticTexts["Your miners"]
        let minerCount = app.staticTexts["3 sample miners"]
        let sort = app.buttons["dashboard.minerDisplay"]
        XCTAssertTrue(chartHeading.waitForExistence(timeout: 10))
        for element in [fleetHeading, rate, notice, exit, miners, minerCount, sort] {
            XCTAssertTrue(element.exists)
        }
        for heading in [fleetHeading, chartHeading] {
            XCTAssertGreaterThan(heading.frame.height, largestType ? 19 : 16)
            XCTAssertLessThanOrEqual(heading.frame.height, largestType ? 21 : 19,
                                     "The preview headings should stay compact without losing all type scaling")
        }
        XCTAssertLessThanOrEqual(rate.frame.height, largestType ? 60 : 55,
                                 "The number and its unit should share a compact line")
        assertSingleRow(left: notice.frame, right: exit.frame)
        assertSingleRow(left: miners.frame.union(minerCount.frame), right: sort.frame)
        // AX can report the same edge as 180 and 179.9999999999999 after coordinate conversion.
        let noticeOverlap = exit.frame.maxY - fleetHeading.frame.minY
        XCTAssertLessThanOrEqual(noticeOverlap, 0.000_001, "The demo notice must not overlap the fleet heading")
        XCTAssertLessThan(rate.frame.maxY, chartHeading.frame.minY)
        XCTAssertLessThan(chartHeading.frame.maxY, miners.frame.minY)
        return chartHeading.frame.height
    }

    func assertSingleRow(left: CGRect, right: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(left.maxX, right.minX, file: file, line: line)
        XCTAssertEqual(left.midY, right.midY, accuracy: 2, file: file, line: line)
    }

    func assertRangeBarLayout(in app: XCUIApplication, range: XCUIElement, history: XCUIElement) {
        let heading = app.staticTexts["Hashrate trend"].firstMatch
        let caption = app.staticTexts["Simulated · SHA-256 · TH/s"].firstMatch
        XCTAssertTrue(heading.exists && caption.exists)
        assertTapTarget(range)
        assertTapTarget(history)
        let recentFrame = range.frame
        let historyFrame = history.frame
        let both = recentFrame.union(historyFrame)
        XCTAssertGreaterThanOrEqual(both.width, app.frame.width * 0.75, "The control should fill the chart card")
        XCTAssertLessThanOrEqual(heading.frame.maxY, both.minY)
        XCTAssertLessThanOrEqual(both.maxY, caption.frame.minY)
        XCTAssertEqual(recentFrame.width, historyFrame.width, accuracy: 1)
        XCTAssertEqual(recentFrame.midY, historyFrame.midY, accuracy: 1)
        XCTAssertLessThanOrEqual(recentFrame.maxX, historyFrame.minX)
        XCTAssertLessThanOrEqual(both.height, 46, "Two range controls should fit in one compact tap row")
    }

    var numberFirstArguments: [String] {
        ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion", "--preview-number-first"]
    }

    func firstNumberFirstMiner(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
    }

    func assertTapTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, element.debugDescription, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43.99, element.identifier, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 43.99, element.identifier, file: file, line: line)
    }

    func auditOverview(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .textClipped]) { issue in
            // On iOS 27 the hit-region audit also reports short static labels. Only exempt
            // the identified, noninteractive captions. Still check their contrast and clipping.
            let staticCaptionIDs = ["dashboard.bitsy", "dashboard.hashrateSource", "dashboard.fleetStatus",
                                    "dashboard.fleetPowerChip", "dashboard.refreshMode"]
            if issue.auditType == .hitRegion, let element = issue.element, element.elementType == .staticText,
               staticCaptionIDs.contains(element.identifier) || element.label == "3 of 3 online"
                || element.label.hasPrefix("Simulated hashrate history · ") {
                return true
            }
            print("Overview audit: \(issue.element?.elementType.rawValue ?? 0) \(issue.element?.identifier ?? "") "
                  + "\(issue.element?.label ?? "") \(issue.compactDescription): \(issue.detailedDescription)")
            return false
        }
    }
}
