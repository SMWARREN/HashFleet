import XCTest

/// Native read-only acceptance coverage. Every launch resets app.hashfleet.ui-tests via
/// HashFleetApp's --ui-testing path. --demo uses sample miners and local insight/pool data.
/// The guided production screens are protected by FleetTourView. Tests require every
/// exposed underlying control to be non-hittable and interactive controls to be disabled.
/// Only coach/spotlight navigation is tapped. No share, hardware, permission, wallet,
/// discovery, or Live Activity action is invoked by this suite.
@MainActor
final class ReadOnlyFeatureCoverageUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testEveryGuidedLessonHasExactContentProgressAndProtectedUnderlyingScreen() {
        let app = launchSampleFleet()
        defer { app.terminate() }
        openTour(app)

        for (offset, lesson) in lessons.enumerated() {
            assertLesson(lesson, position: offset + 1, app: app)
            if lesson.id == "chooseDGB" {
                XCTAssertFalse(sampleSummary(app).contains("DGB"))
            } else if lesson.id == "coinResult" {
                XCTAssertTrue(sampleSummary(app).contains("DGB"), sampleSummary(app))
            }
            if lesson.id == "complete" {
                XCTAssertFalse(app.buttons["tour.next"].exists)
                tap(app.buttons["tour.done"])
            } else if lesson.action != nil {
                tap(app.buttons["tour.tapTarget"])
            } else {
                tap(app.buttons["tour.next"])
            }
        }

        XCTAssertTrue(element("tour.view", app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        // Reopening creates a fresh sandbox, not the DGB practice state left at completion.
        openTour(app)
        assertLesson(lessons[0], position: 1, app: app)
        XCTAssertFalse(sampleSummary(app).contains("DGB"))
        tap(app.buttons["tour.close"])
        XCTAssertTrue(element("tour.view", app).waitForNonExistence(timeout: 5))
    }

    func testChooserAndBackResetPracticeCoinsAndRenderPDFWithoutSharing() {
        let app = launchSampleFleet()
        defer { app.terminate() }
        openFleetSettings(in: app)
        XCTAssertTrue(app.navigationBars["App settings"].waitForExistence(timeout: 5))
        let tourEntry = app.buttons["monitoring.featureTour"]
        reveal(tourEntry, app)
        tap(tourEntry)
        assertLesson(lessons[0], position: 1, app: app)

        jump(to: "coinResult", app: app)
        XCTAssertTrue(sampleSummary(app).contains("DGB"))
        tap(app.buttons["tour.back"])
        assertLesson(lessons[5], position: 6, app: app)
        XCTAssertFalse(sampleSummary(app).contains("DGB"), "Back must reset the practice selection.")
        tap(app.buttons["tour.tapTarget"])
        assertLesson(lessons[6], position: 7, app: app)
        XCTAssertTrue(sampleSummary(app).contains("DGB"))

        // Direct PDF selection covers goTo's render branch without visiting the report action first.
        jump(to: "pdf", app: app)
        tap(app.buttons["tour.back"])
        assertLesson(lessons[12], position: 13, app: app)
        tap(app.buttons["tour.tapTarget"])
        assertLesson(lessons[13], position: 14, app: app)
        jump(to: "appearance", app: app)
        jump(to: "alerts", app: app)
        jump(to: "overview", app: app)
        XCTAssertFalse(app.buttons["tour.back"].isEnabled)
        tap(app.buttons["tour.close"])
        XCTAssertTrue(element("tour.view", app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(tourEntry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["App settings"].exists)
    }

    func testReportCapturesStoredSampleAndPreviewsPDFWithoutExport() {
        let app = launchSampleFleet()
        defer { app.terminate() }
        openSettingsRoute("monitoring.reports", title: "Fleet Reports", app: app)
        // SwiftUI Label exposes its icon and text with this identifier. Query the text,
        // not the first .any match, which may be the flask image rather than the copy.
        let demo = app.staticTexts.matching(identifier: "fleetReport.demo").firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        XCTAssertEqual(demo.label, "Demo / simulated readings")
        XCTAssertTrue(element("fleetReport.capturedAt", app).exists)
        XCTAssertFalse(element("fleetReport.empty", app).exists)
        let capture = app.buttons["fleetReport.capture"]
        reveal(capture, app)
        tap(capture)
        XCTAssertTrue(element("fleetReport.capturedAt", app).waitForExistence(timeout: 5))
        let preview = app.buttons["fleetReport.previewPDF"]
        reveal(preview, app)
        tap(preview)
        XCTAssertTrue(app.navigationBars["Snapshot PDF"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("fleetReport.pdfPreview", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tour.done"].exists, "Normal PDF preview is not the tour overlay.")
        tap(app.navigationBars["Snapshot PDF"].buttons["Done"])
        XCTAssertTrue(element("fleetReport.pdfPreview", app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Fleet Reports"].exists)
        XCTAssertFalse(app.staticTexts["fleetReport.exportError"].exists)
    }

    func testEnergyReadingsStayEstimatesAndMissingRateIsNotAZeroBill() {
        let app = launchSampleFleet()
        defer { app.terminate() }
        openSettingsRoute("monitoring.energy", title: "Electricity estimates", app: app)
        XCTAssertTrue(app.textFields["energy.rateField"].waitForExistence(timeout: 5))
        let coverage = element("energy.coverageLabel", app)
        reveal(coverage, app)
        XCTAssertTrue(coverage.label.contains("miners have fresh power readings."))
        let dailyCost = element("energy.dailyCostValue", app)
        reveal(dailyCost, app)
        XCTAssertTrue(accessibleText(dailyCost).contains("Set your rate"), dailyCost.debugDescription)
        let energy = element("energy.dailyKWhValue", app)
        XCTAssertTrue(accessibleText(energy).contains("kWh"), energy.debugDescription)
        let disclaimer = element("energy.disclaimerLabel", app)
        reveal(disclaimer, app)
        XCTAssertTrue(disclaimer.label.contains("not metered consumption, bills, mining revenue or profit"))
        XCTAssertFalse(app.staticTexts["energy.feedback"].exists, "Reading estimates must not save a rate.")
    }

    func testAchievementFiltersDoNotInventMilestonesForSampleMiners() {
        let app = launchSampleFleet()
        defer { app.terminate() }
        openSettingsRoute("monitoring.achievements", title: "Mining Achievements", app: app)
        let empty = app.staticTexts["No achievements yet"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertTrue(element("achievements.bitsy", app).exists)
        for filter in ["Blocks Found", "Best Shares", "All"] {
            tap(app.navigationBars["Mining Achievements"].buttons["Filter"])
            tap(app.buttons[filter])
            XCTAssertTrue(empty.waitForExistence(timeout: 5), "Unexpected demo milestone under \(filter).")
            XCTAssertTrue(app.navigationBars["Mining Achievements"].exists)
        }
    }

    func testDemoNetworkAndPoolHubExposeSampleDataWithoutWalletLookup() {
        let app = launchSampleFleet()
        defer { app.terminate() }
        let details = app.buttons["dashboard.networkDetails"]
        reveal(details, app)
        tap(details)
        XCTAssertTrue(app.navigationBars["Network insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo · not live"].waitForExistence(timeout: 5))
        let networkData = app.buttons["insights.poolNetworks"]
        reveal(networkData, app)
        tap(networkData)
        XCTAssertTrue(app.navigationBars["Pool network data"].waitForExistence(timeout: 5))
        let counts = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'insights.poolNetwork.' AND identifier ENDSWITH '.counts'")
        ).firstMatch
        reveal(counts, app)
        XCTAssertTrue(accessibleText(counts).contains("10 / 20"), counts.debugDescription)
        tap(app.navigationBars["Pool network data"].buttons.element(boundBy: 0))
        XCTAssertTrue(app.navigationBars["Network insights"].waitForExistence(timeout: 5))
        let hub = app.buttons["insights.poolHub"]
        reveal(hub, app, towardTop: true)
        tap(hub)
        XCTAssertTrue(app.navigationBars["Connected pool stats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample pool data. No internet requests."].waitForExistence(timeout: 5))
        let card = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'poolHub.card.'")
        ).firstMatch
        reveal(card, app)
        XCTAssertTrue(card.exists)
        XCTAssertFalse(element("poolHub.disabled", app).exists)
        XCTAssertFalse(element("poolHub.empty", app).exists)
    }

    // Source of truth: FleetGuidedDemoSteps.all. Titles and instruction fragments are asserted
    // independently of identifiers, so a wrong destination cannot pass by exposing a shell ID.
    private struct Lesson {
        let id: String
        let title: String
        let instruction: String
        let action: String?
        let hiddenControl: String
    }

    private var lessons: [Lesson] {
        [
            Lesson(id: "overview", title: "Meet your fleet", instruction: "These are sample miners.", action: nil, hiddenControl: "dashboard.networkDetails"),
            Lesson(id: "history", title: "View hashrate over time", instruction: "daily, weekly, monthly", action: nil, hiddenControl: "dashboard.networkDetails"),
            Lesson(id: "openMiner", title: "Open a miner", instruction: "highlighted miner card", action: "Open the sample miner", hiddenControl: "dashboard.networkDetails"),
            Lesson(id: "cooling", title: "Check temperature and cooling", instruction: "fan speed and RPM", action: nil, hiddenControl: "detail.cooling.settings"),
            Lesson(id: "openCoins", title: "Choose what the dashboard shows",
                   instruction: "not which coins a miner actually mines", action: "Open Coins to show",
                   hiddenControl: "dashboard.networkDetails"),
            Lesson(id: "chooseDGB", title: "Try a display choice", instruction: "Nothing changes outside this demo.", action: "Turn on DigiByte in the demo", hiddenControl: "coinSelection.DGB"),
            Lesson(id: "coinResult", title: "See your choice take effect", instruction: "DGB now shows up once", action: nil, hiddenControl: "dashboard.networkDetails"),
            Lesson(id: "openPreferences", title: "Find display settings", instruction: "switch between light and dark mode", action: "Open Preferences", hiddenControl: "monitoring.fleet"),
            Lesson(id: "appearance", title: "Choose your appearance", instruction: "Light, Dark, or System", action: nil, hiddenControl: "preferences.appearance"),
            Lesson(id: "openEnergy", title: "Find your fleet tools", instruction: "running-cost tool", action: "Open Electricity estimates", hiddenControl: "monitoring.energy"),
            Lesson(id: "energy", title: "Understand the estimate", instruction: "0.15 USD per kWh", action: nil, hiddenControl: "energy.save"),
            Lesson(id: "openReports", title: "Find snapshot reports", instruction: "never contact your miners", action: "Open Fleet reports", hiddenControl: "monitoring.reports"),
            Lesson(id: "previewReport", title: "Preview before you share", instruction: "never opens a share sheet", action: "Preview the sample fleet PDF", hiddenControl: "fleetReport.previewPDF"),
            Lesson(id: "pdf", title: "Here's the actual report", instruction: "anonymous sample readings", action: nil, hiddenControl: "fleetReport.pdfPreview"),
            Lesson(id: "openAlerts", title: "Set up alerts from Settings",
                   instruction: "demo won't ask for permission", action: "Expand Notifications and banners", hiddenControl: "monitoring.notifications"),
            Lesson(id: "alerts", title: "Know where to test delivery", instruction: "iOS permission and background timing", action: nil, hiddenControl: "preferences.sendTestNotification"),
            Lesson(id: "complete", title: "Ready for your own fleet", instruction: "fleet you left", action: nil, hiddenControl: "dashboard.networkDetails")
        ]
    }

    private func launchSampleFleet() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        return app
    }

    private func openTour(_ app: XCUIApplication) {
        tap(app.buttons["dashboard.settingsMenu"])
        tap(app.buttons["dashboard.featureTour"])
        XCTAssertTrue(element("tour.view", app).waitForExistence(timeout: 5))
    }

    private func openSettingsRoute(_ id: String, title: String, app: XCUIApplication) {
        openFleetSettings(in: app)
        XCTAssertTrue(app.navigationBars["App settings"].waitForExistence(timeout: 5))
        let destination = app.buttons[id]
        reveal(destination, app)
        tap(destination)
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    private func jump(to id: String, app: XCUIApplication) {
        guard let index = lessons.firstIndex(where: { $0.id == id }) else {
            XCTFail("No sourced lesson named \(id)")
            return
        }
        tap(app.buttons["tour.chooser"])
        let choice = app.buttons["tour.jump.\(id)"]
        reveal(choice, app)
        XCTAssertEqual(choice.label, lessons[index].title)
        tap(choice)
        assertLesson(lessons[index], position: index + 1, app: app)
    }

    private func assertLesson(_ lesson: Lesson, position: Int, app: XCUIApplication) {
        let title = app.staticTexts["tour.step.\(lesson.id)"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Missing \(lesson.id)")
        XCTAssertEqual(title.label, lesson.title)
        XCTAssertEqual(app.staticTexts["tour.progress"].label, "\(position)/17")
        XCTAssertTrue(app.staticTexts["tour.instruction"].label.contains(lesson.instruction))
        XCTAssertEqual(app.buttons["tour.back"].isEnabled, position > 1)
        let highlight = element(lesson.action == nil ? "tour.highlight" : "tour.tapTarget", app)
        XCTAssertTrue(highlight.waitForExistence(timeout: 10), "No production target for \(lesson.id)")
        XCTAssertTrue(sampleSummary(app).contains("sample miners. Display coins:"), sampleSummary(app))
        XCTAssertGreaterThan(highlight.frame.width, 10)
        XCTAssertGreaterThan(highlight.frame.height, 10)
        if let action = lesson.action {
            XCTAssertEqual(highlight.label, action)
            XCTAssertTrue(highlight.isEnabled)
        } else {
            XCTAssertFalse(app.buttons["tour.tapTarget"].exists)
        }
        // Scope protection to the tour, not its obscured presenting dashboard/settings sheet.
        // SwiftUI's native Form can expose a disabled switch in XCTest even when its ancestor
        // is accessibilityHidden. Existence alone does not establish that it can be operated.
        let root = element("tour.view", app)
        for identifier in [lesson.hiddenControl, "fleetReport.sharePDF", "preferences.sendTestNotification"] {
            assertUnderlyingControlIsProtected(identifier, root: root)
        }
    }

    private func assertUnderlyingControlIsProtected(_ identifier: String, root: XCUIElement) {
        let interactiveTypes: [XCUIElement.ElementType] = [
            .button, .switch, .slider, .textField, .textView, .segmentedControl
        ]
        let controls = root.descendants(matching: .any).matching(identifier: identifier)
        for control in controls.allElementsBoundByIndex {
            XCTAssertFalse(control.isHittable,
                           "The tour must prevent touches reaching \(identifier): \(control.debugDescription)")
            if interactiveTypes.contains(control.elementType) {
                XCTAssertFalse(control.isEnabled,
                               "An exposed production control must remain disabled: \(control.debugDescription)")
            }
        }
    }

    private func sampleSummary(_ app: XCUIApplication) -> String {
        element("tour.sampleBanner", app).value as? String ?? ""
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func accessibleText(_ element: XCUIElement) -> String {
        ([element.label, element.value as? String ?? ""] +
         element.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
    }

    private func tap(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, element.debugDescription)
        element.tap()
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Unreachable read-only destination: \(element)")
    }
}
