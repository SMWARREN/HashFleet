import XCTest

/// These native simulator workflows explicitly exercise the Mac layout branch.
/// They are not evidence of a physical Mac WindowServer or native save-panel run.
@MainActor
final class FleetDesktopPresentationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPhoneFleetMenuClosesBeforeOpeningRequestedDestination() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        defer { app.terminate() }
        for (destination, marker) in [
            ("reports", "fleetReport.capture"), ("about", "about.hero"), ("overview", "dashboard.title")
        ] {
            app.launch()
            let menu = app.buttons["dashboard.headerLogoButton"]
            assertHittable(menu)
            menu.tap()
            XCTAssertTrue(app.navigationBars["Fleet Menu"].waitForExistence(timeout: 8))
            let row = app.buttons["sidebar.destination.\(destination)"]
            reveal(row, in: app)
            assertHittable(row)
            row.tap()
            let page = app.descendants(matching: .any).matching(identifier: marker).firstMatch
            assertHittable(page)
            XCTAssertFalse(app.navigationBars["Fleet Menu"].exists, "The menu must not cover the requested screen")
            app.terminate()
        }
    }

    func testDesktopAddMinerFillsWindowAndReturnsToDashboard() throws {
        let app = launchDesktopDemo(orientation: .landscapeLeft)
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let add = app.buttons["dashboard.addMiner"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        XCTAssertTrue(app.textFields["addMiner.address"].waitForExistence(timeout: 8))
        assertFillsWindow(app.navigationBars["Add a miner"], app: app)
        capture("Desktop branch full-window Add Miner", app: app)
        app.buttons["addMiner.dismiss"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["addMiner.address"].exists)
    }

    func testDesktopSettingsFillsWindowAndDismissesWithoutReopening() throws {
        let app = launchDesktopDemo(orientation: .portrait)
        defer { app.terminate() }
        let settings = dashboardSettingsMenu(in: app)
        openFleetSettings(in: app)
        let done = app.buttons["monitoring.settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        assertFillsWindow(app.navigationBars["App settings"], app: app,
                          visibleContent: app.buttons["monitoring.notifications"])
        capture("Desktop branch narrower full-window Settings", app: app)
        done.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        XCTAssertFalse(done.exists)
    }

    func testDesktopAboutFillsWindowAndRestoresInteractiveDashboard() throws {
        let app = launchDesktopDemo(orientation: .landscapeLeft)
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        openFleetAbout(in: app)
        let page = app.navigationBars["About Hash Fleet"]
        assertFillsWindow(page, app: app)
        capture("Desktop branch full-window About", app: app)
        app.buttons["about.done"].tap()
        assertHittable(dashboardSettingsMenu(in: app))
        XCTAssertFalse(page.exists)
    }

    func testDesktopAchievementsCoverFillsWindowAndRestoresDashboard() throws {
        let app = launchDesktopDemo(orientation: .landscapeLeft)
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let open = app.buttons["milestones.openAchievements"]
        reveal(open, in: app)
        assertHittable(open)
        open.tap()
        let page = app.navigationBars["Mining Achievements"]
        assertFillsWindow(page, app: app)
        capture("Desktop branch full-window Achievements", app: app)
        page.buttons["Done"].tap()
        assertHittable(dashboardSettingsMenu(in: app))
        XCTAssertFalse(page.exists)
    }

    func testDesktopNestedGuideFillsWindowAndPreservesSettings() throws {
        let app = launchDesktopDemo(orientation: .portrait)
        defer { app.terminate() }
        openFleetSettings(in: app)
        let guide = app.buttons["monitoring.featureTour"]
        reveal(guide, in: app)
        assertHittable(guide)
        guide.tap()
        // The tour contains a sandbox NavigationStack whose sample page contributes
        // the bar title. Identify the owning tour instead of that nested sample title.
        let page = app.otherElements["tour.view"]
        assertFillsWindow(page, app: app)
        XCTAssertGreaterThan(page.frame.height, app.frame.height * 0.90)
        capture("Desktop branch nested full-window guided demo", app: app)
        let close = app.buttons["tour.close"]
        assertHittable(close)
        close.tap()
        let done = app.buttons["monitoring.settings.done"]
        assertHittable(done)
        XCTAssertFalse(page.exists)
        done.tap()
        assertHittable(dashboardSettingsMenu(in: app))
        XCTAssertFalse(done.exists)
    }

    func testDesktopPDFPreviewFillsWindowAndPreservesReport() throws {
        let app = launchDesktopDemo(orientation: .landscapeLeft)
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let reports = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Reports & Export")).firstMatch
        XCTAssertTrue(reports.waitForExistence(timeout: 8), app.debugDescription)
        reports.tap()
        let preview = app.buttons["fleetReport.previewPDF"]
        reveal(preview, in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        let pdfTitle = app.navigationBars["Snapshot PDF"]
        XCTAssertTrue(pdfTitle.waitForExistence(timeout: 8), app.debugDescription)
        let pdfContent = app.descendants(matching: .any)
            .matching(identifier: "fleetReport.pdfPreview").firstMatch
        XCTAssertTrue(pdfContent.waitForExistence(timeout: 8), app.debugDescription)
        assertFillsWindow(pdfContent, app: app)
        capture("Desktop branch full-window PDF preview", app: app)
        pdfTitle.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Fleet Reports"].waitForExistence(timeout: 8))
        XCTAssertFalse(pdfContent.exists)
        XCTAssertFalse(app.staticTexts["fleetReport.exportError"].exists)
    }

    func testDesktopMinerRowsSpanOddCardAndReflowAtNarrowerWidth() throws {
        let app = launchDesktopDemo(orientation: .landscapeLeft)
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let names = ["Little Supra", "Office Gamma", "Workshop Gamma"]
        let miners = names.map { name in
            app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS %@", name
            )).firstMatch
        }
        for miner in miners { XCTAssertTrue(miner.waitForExistence(timeout: 8)) }
        reveal(miners[2], in: app)
        let wide = try cardContentFrames(miners, in: app)
        XCTAssertEqual(wide[0].minY, wide[1].minY, accuracy: 2)
        XCTAssertEqual(wide[2].minX, wide[0].minX, accuracy: 2)
        XCTAssertEqual(wide[2].maxX, wide[1].maxX, accuracy: 2)
        XCTAssertGreaterThan(wide[2].width, max(wide[0].width, wide[1].width) * 1.7)
        XCTAssertGreaterThanOrEqual(wide[2].minY, max(wide[0].maxY, wide[1].maxY) + 14)
        capture("Desktop branch two columns with full-width third miner", app: app)

        XCUIDevice.shared.orientation = .portrait
        // Access frame directly so XCTest requests fresh CGRect geometry after rotation.
        // A string predicate's nested frame.size key path can omit that geometry.
        let reflowed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.frame.width < 1100 }, object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reflowed], timeout: 8), .completed,
                       "Expected a narrower viewport after rotation, actual frame: \(app.frame)")
        reveal(miners[2], in: app)
        let narrow = try cardContentFrames(miners, in: app)
        for index in 1..<narrow.count {
            XCTAssertEqual(narrow[index].minX, narrow[0].minX, accuracy: 2)
            XCTAssertEqual(narrow[index].maxX, narrow[0].maxX, accuracy: 2)
            XCTAssertGreaterThanOrEqual(narrow[index].minY, narrow[index - 1].maxY + 14)
        }
        capture("Desktop branch narrower single-column miner rows", app: app)
    }

    func testDesktopFleetTrendMatchesWebsiteStyleAndKeepsIndividualMode() throws {
        let app = launchDesktopDemo(orientation: .landscapeLeft)
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let bitsy = app.descendants(matching: .any).matching(identifier: "dashboard.bitsy").firstMatch
        let hashNumbers = app.descendants(matching: .any).matching(identifier: "dashboard.fleetHashrate").firstMatch
        let history = app.descendants(matching: .any).matching(identifier: "dashboard.history").firstMatch
        XCTAssertTrue(bitsy.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(hashNumbers.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(history.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertLessThan(bitsy.frame.maxY, hashNumbers.frame.minY, "Bitsy belongs above the hash numbers on the Mac layout")
        XCTAssertLessThan(hashNumbers.frame.maxY, history.frame.minY, "Hash numbers belong above the history chart on the Mac layout")
        let odds = app.descendants(matching: .any).matching(identifier: "dashboard.chains").firstMatch
        XCTAssertTrue(odds.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertLessThan(history.frame.maxY, odds.frame.minY, "Solo odds belongs below the history chart on the Mac layout")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "dashboard.soloOddsWindows").firstMatch.exists)
        for window in ["day", "month", "year"] {
            let control = app.buttons["dashboard.soloOddsWindow.\(window)"]
            reveal(control, in: app)
            XCTAssertTrue(control.exists, app.debugDescription)
            control.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "dashboard.historyRanges").firstMatch.exists)

        let mode = app.buttons["dashboard.historyDisplay"]
        XCTAssertTrue(mode.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(mode.value as? String, "Fleet total")

        let chart = app.descendants(matching: .any).matching(identifier: "dashboard.historyChart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 8), app.debugDescription)
        reveal(chart, in: app)
        XCTAssertTrue(chart.isHittable, app.debugDescription)
        XCTAssertTrue((chart.value as? String ?? "").contains("3 miners"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "dashboard.historyLegend").firstMatch.exists)
        capture("Desktop website-style gold fleet trend", app: app)

        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        let selected = app.staticTexts["dashboard.historySelection.rate"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(selected.label.contains("TH/s"), selected.label)
        capture("Desktop website-style fleet trend inspection", app: app)

        let clear = app.buttons["dashboard.historySelection.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), app.debugDescription)
        clear.tap()
        app.swipeDown()
        reveal(mode, in: app, avoidingNavigationBar: true)
        mode.tap()
        let individual = app.buttons["Individual miners"].firstMatch
        XCTAssertTrue(individual.waitForExistence(timeout: 5), app.debugDescription)
        individual.tap()
        XCTAssertTrue(app.staticTexts["1-minute average per-miner reading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "dashboard.historyLegend").firstMatch.exists)
        XCTAssertFalse(app.buttons["dashboard.historySelection.clear"].exists)
        capture("Desktop individual miner history mode", app: app)

        mode.tap()
        app.buttons["Fleet total"].firstMatch.tap()
        XCTAssertEqual(mode.value as? String, "Fleet total")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "dashboard.historyLegend").firstMatch.exists)
    }

    private func cardContentFrames(_ miners: [XCUIElement], in app: XCUIApplication) throws -> [CGRect] {
        // One immutable snapshot avoids mixing coordinates during scroll deceleration.
        let tree = try app.snapshot()
        return miners.map { miner in
            let id = String(miner.identifier.dropFirst("dashboard.miner.".count))
            let identifiers = Set([miner.identifier, "dashboard.card.expand.\(id)", "dashboard.card.settings.\(id)"])
            let frame = bounds(in: tree, identifiers: identifiers)
            XCTAssertFalse(frame.isNull)
            XCTAssertGreaterThan(frame.width, 0)
            return frame
        }
    }

    private func bounds(in node: any XCUIElementSnapshot, identifiers: Set<String>) -> CGRect {
        let own = identifiers.contains(node.identifier) ? node.frame : CGRect.null
        return node.children.reduce(own) { $0.union(bounds(in: $1, identifiers: identifiers)) }
    }

    func testDesktopASICRegistersCollapseBelowMinerChartAndUseGrid() throws {
        let app = launchDesktopDemo(
            orientation: .landscapeLeft,
            extraArguments: ["--ui-test-asic-telemetry"]
        )
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let miner = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS %@", "Workshop Gamma"
        )).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 8), app.debugDescription)
        reveal(miner, in: app)
        assertHittable(miner)
        miner.tap()

        let history = app.descendants(matching: .any).matching(identifier: "detail.history").firstMatch
        let disclosure = app.buttons["detail.asicTelemetry.disclosure"]
        XCTAssertTrue(history.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(disclosure.waitForExistence(timeout: 8), app.debugDescription)
        let firstDomain = app.descendants(matching: .any)
            .matching(identifier: "detail.asicDomain.0.0").firstMatch
        XCTAssertFalse(firstDomain.exists, "ASIC register tiles must start collapsed")
        let historyBounds = bounds(in: try app.snapshot(), identifiers: ["detail.history"])
        XCTAssertFalse(historyBounds.isNull)
        XCTAssertGreaterThanOrEqual(disclosure.frame.minY, historyBounds.maxY,
                                    "Each miner's registers belong below its individual chart")
        reveal(disclosure, in: app, avoidingNavigationBar: true)
        assertHittable(disclosure)
        capture("Shared ASIC registers collapsed below miner chart", app: app)
        disclosure.tap()

        let grid = app.descendants(matching: .any).matching(identifier: "detail.asicTelemetry.grid").firstMatch
        let secondDomain = app.descendants(matching: .any)
            .matching(identifier: "detail.asicDomain.0.1").firstMatch
        XCTAssertTrue(firstDomain.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(secondDomain.waitForExistence(timeout: 5), app.debugDescription)
        capture("Expanded ASIC grid before semantic bounds check", app: app)
        XCTAssertTrue(grid.exists, app.debugDescription)
        XCTAssertEqual(firstDomain.frame.minY, secondDomain.frame.minY, accuracy: 3,
                       "A wide miner workspace must show multiple register tiles across")
        XCTAssertGreaterThan(secondDomain.frame.minX, firstDomain.frame.minX)
        for tile in [firstDomain, secondDomain] {
            XCTAssertGreaterThanOrEqual(tile.frame.minX, grid.frame.minX - 1)
            XCTAssertLessThanOrEqual(tile.frame.maxX, grid.frame.maxX + 1)
        }
        capture("Shared ASIC registers expanded responsive grid", app: app)
        reveal(disclosure, in: app, avoidingNavigationBar: true)
        disclosure.tap()
        XCTAssertFalse(firstDomain.exists, "Collapsing the section must remove the register tiles")
    }

    func testReadableSettingsGeometryDetectsThePriorSidebarOverlap() {
        let window = CGRect(x: 0, y: 0, width: 1376, height: 1032)
        let sidebarRow = CGRect(x: 16, y: 184, width: 268, height: 42)
        // Actual UI7 and UI8 observations, retained as a detecting positive control.
        // Both List containers reported full-window AX bounds, but only one row was safe.
        XCTAssertFalse(readableSettingsRowFitsWorkspace(
            CGRect(x: 158, y: 300.5, width: 1060, height: 84.5),
            window: window, sidebar: sidebarRow))
        XCTAssertTrue(readableSettingsRowFitsWorkspace(
            CGRect(x: 474, y: 300.5, width: 728, height: 84.5),
            window: window, sidebar: sidebarRow))
        XCTAssertFalse(readableSettingsRowFitsWorkspace(
            CGRect(x: 800, y: 300.5, width: 50, height: 84.5),
            window: window, sidebar: sidebarRow))
    }

    func assertReadableSettingsRow(
        _ row: XCUIElement, app: XCUIApplication, sidebar: XCUIElement
    ) {
        assertHittable(row)
        XCTAssertTrue(readableSettingsRowFitsWorkspace(
            row.frame, window: app.frame, sidebar: sidebar.frame),
            "Settings row must be wholly in the detail column, centered and readable: \(row.frame)")
    }

    private func readableSettingsRowFitsWorkspace(
        _ row: CGRect, window: CGRect, sidebar: CGRect
    ) -> Bool {
        let availableWidth = window.maxX - sidebar.maxX
        let detailCenter = (sidebar.maxX + window.maxX) / 2
        return row.minX >= sidebar.maxX && row.maxX <= window.maxX
            && row.height > 0 && row.width >= min(760, availableWidth) * 0.90
            && row.width <= 760 && abs(row.midX - detailCenter) <= 12
    }

    private func launchDesktopDemo(
        orientation: UIDeviceOrientation, extraArguments: [String] = []
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-desktop-layout"] + extraArguments
        app.launch()
        return app
    }

    func assertFillsWindow(
        _ page: XCUIElement, app: XCUIApplication, visibleContent: XCUIElement? = nil
    ) {
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        // October 25 requirement: pages fill the owning workspace, not the sidebar too.
        // The sidebar must remain interactive, and an app-owned page must not be a sheet.
        XCTAssertEqual(app.sheets.count, 0)
        let overview = sidebarOverview(in: app)
        if overview.exists {
            assertHittable(overview)
            // UIKit's grouped List and merged navigation bar report hosting-window AX bounds.
            // Measure the real semantic row for their left edge, not that backing viewport.
            // UI7's clipped row fails this check even though its List frame matches UI8's.
            if let visibleContent {
                assertHittable(visibleContent)
                XCTAssertGreaterThanOrEqual(visibleContent.frame.minX, overview.frame.maxX - 16)
                XCTAssertLessThanOrEqual(visibleContent.frame.maxX, app.frame.maxX)
            } else {
                XCTAssertGreaterThanOrEqual(page.frame.minX, overview.frame.maxX - 16)
            }
            XCTAssertEqual(page.frame.maxX, app.frame.maxX, accuracy: 12)
            XCTAssertGreaterThan(page.frame.width, (app.frame.maxX - overview.frame.maxX) * 0.90)
        } else {
            XCTAssertGreaterThan(page.frame.width, app.frame.width * 0.90)
        }
        XCTAssertGreaterThan(page.frame.height, 0)
    }

    func sidebarOverview(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Overview")).firstMatch
    }

    func assertHittable(_ element: XCUIElement) {
        let interactive = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in element.exists && element.isHittable }, object: element
        )
        let result = XCTWaiter.wait(for: [interactive], timeout: 8)
        if result != .completed {
            let app = XCUIApplication()
            capture("Unreachable page control", app: app)
            print("[UNREACHABLE_CONTROL] \(element.debugDescription)\n\(app.debugDescription)")
        }
        XCTAssertEqual(result, .completed,
                       "Expected the page control or restored workspace to be interactive")
    }

    func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        avoidingNavigationBar: Bool = false
    ) {
        for _ in 0..<10 {
            let navigationBottom = app.navigationBars.firstMatch.frame.maxY
            let coveredByNavigationBar = avoidingNavigationBar
                && element.exists
                && element.frame.minY < navigationBottom + 4
            if element.exists && element.isHittable && !coveredByNavigationBar { return }
            let isAboveViewport = element.exists && element.frame.maxY <= navigationBottom
            let shouldScrollDown = coveredByNavigationBar || isAboveViewport
            let startY: CGFloat = shouldScrollDown ? 0.30 : 0.75
            let endY: CGFloat = shouldScrollDown ? 0.75 : 0.30
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: startY))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: endY))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
    }

    func capture(_ name: String, app: XCUIApplication) {
        // The app-element capture used a rotated crop in this simulator fixture.
        // Capture the screen itself so landscape evidence includes the whole viewport.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[DESKTOP_LAYOUT_CHECK] \(name): app=\(app.frame), screenImage=\(screenshot.image.size)")
    }
}
