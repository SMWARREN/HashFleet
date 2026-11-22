import XCTest
import UIKit

/// Appearance switching acceptance tests for HashFleetUITests.
extension HashFleetUITests {
    #if HASHFLEET_LIVE_REVIEW
    func testFreshDashboardKeepsGearDuringSearchAndChangesViewWithOneTap() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--ui-test-dashboard-fresh", "--ui-test-reduce-motion"]
        app.launch()

        let skip = app.buttons["dashboard.chooseView.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].exists)
        let miners = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'"))
        XCTAssertEqual(miners.count, 0)

        let gear = app.buttons["dashboard.settingsMenu"]
        let add = app.buttons["dashboard.addMiner"]
        func assertToolbar(line: UInt = #line) {
            XCTAssertTrue(gear.isHittable && add.isHittable, line: line)
            XCTAssertEqual(gear.frame.midY, add.frame.midY, accuracy: 1, line: line)
            XCTAssertGreaterThan(add.frame.midX, gear.frame.midX, line: line)
            XCTAssertLessThanOrEqual(add.frame.minX - gear.frame.maxX, 10, line: line)
        }
        assertToolbar()
        app.swipeDown()
        let search = app.textFields["dashboard.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("fixture")
        assertFleetEditingFieldAboveKeyboard(search, in: app)
        assertToolbar()
        recordScreenshot("Search with Dashboard gear and Add still visible", app: app)
        search.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "fixture")

        gear.tap()
        let settingsItem = app.buttons["dashboard.openSettings"]
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 5))
        settingsItem.tap()
        let essentials = app.buttons["settings.dashboardView.essentials"]
        let full = app.buttons["settings.dashboardView.full"]
        reveal(full, in: app)
        XCTAssertTrue(essentials.isSelected)
        XCTAssertGreaterThanOrEqual(full.frame.height, 44)
        XCTAssertGreaterThanOrEqual(essentials.frame.height, 44)
        // Tap away from the text, like a normal segmented control touch target.
        full.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.28)).tap()
        XCTAssertTrue(full.isSelected)
        XCTAssertFalse(essentials.isSelected)
        essentials.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.68)).tap()
        XCTAssertTrue(essentials.isSelected)
        XCTAssertFalse(full.isSelected)
        full.tap()
        XCTAssertTrue(full.isSelected)

        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-test-preserve-storage", "--ui-test-reduce-motion"]
        app.launch()
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        XCTAssertFalse(skip.exists)
        XCTAssertEqual(miners.count, 0)
        assertToolbar()
        openFleetSettings(in: app)
        reveal(full, in: app)
        XCTAssertTrue(full.isSelected)
    }
    #endif

    private func dashboardModeButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let singleTapChoice = app.buttons["settings.dashboardView.\(title == "Essentials" ? "essentials" : "full")"]
        return singleTapChoice.exists ? singleTapChoice : app.segmentedControls["settings.dashboardView"].buttons[title]
    }

    func testDashboardWelcomeIsForegroundAndBothChoicesPersist() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        let freshArguments = ["--ui-testing", "--ui-test-dashboard-fresh", "--ui-test-reduce-motion"]
        let essentials = app.buttons["dashboard.chooseView.essentials"]
        let full = app.buttons["dashboard.chooseView.full"]
        let add = app.buttons["dashboard.addMiner"]
        let skip = app.buttons["dashboard.chooseView.skip"]
        for light in [true, false] {
            app.launchArguments = freshArguments + (light ? ["--ui-test-light-appearance", "--show-launch-splash"] : [])
            app.launch()
            XCTAssertTrue(essentials.waitForExistence(timeout: 10))
            XCTAssertTrue(essentials.isHittable)
            XCTAssertTrue(full.isHittable)
            XCTAssertTrue(skip.isHittable)
            XCTAssertFalse(add.isHittable, "The underlying dashboard must not receive taps through the foreground sheet")
            XCTAssertGreaterThanOrEqual(essentials.frame.height, 44)
            XCTAssertGreaterThanOrEqual(full.frame.height, 44)
            XCTAssertGreaterThanOrEqual(skip.frame.height, 44)
            recordScreenshot("Dashboard welcome - \(light ? "light" : "dark")", app: app)
            (light ? essentials : full).tap()
            XCTAssertTrue(full.waitForNonExistence(timeout: 5))
            app.terminate()

            app.launchArguments = ["--ui-testing", "--ui-test-preserve-storage"]
            app.launch()
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            XCTAssertFalse(full.exists, "Choosing either mode must end the first-launch offer")
            openFleetSettings(in: app)
            let useEssentials = dashboardModeButton("Essentials", in: app)
            let useFull = dashboardModeButton("Full View", in: app)
            reveal(useEssentials, in: app)
            XCTAssertTrue((light ? useEssentials : useFull).isSelected)
            XCTAssertTrue(useEssentials.isHittable && useFull.isHittable)
            if light { app.terminate() }
        }

        let useEssentials = dashboardModeButton("Essentials", in: app)
        XCTAssertTrue(useEssentials.waitForExistence(timeout: 5))
        useEssentials.tap()
        XCTAssertTrue(useEssentials.isSelected)
        XCTAssertFalse(dashboardModeButton("Full View", in: app).isSelected)
        recordScreenshot("Dashboard view in App settings", app: app)
        app.terminate()
        app.launch()
        openFleetSettings(in: app)
        reveal(useEssentials, in: app)
        XCTAssertTrue(useEssentials.isSelected)
        XCTAssertFalse(full.exists)
    }

    func testNotNowStartsInEssentialsAndDoesNotAskAgain() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--ui-test-dashboard-fresh", "--ui-test-reduce-motion"]
        app.launch()
        let skip = app.buttons["dashboard.chooseView.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        recordScreenshot("Foreground welcome before Not now", app: app)
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))

        let add = app.buttons["dashboard.addMiner"]
        XCTAssertTrue(add.waitForExistence(timeout: 7))
        add.tap()
        let form = app.navigationBars["Add a miner"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        form.buttons["Cancel"].tap()
        XCTAssertTrue(form.waitForNonExistence(timeout: 5))
        XCTAssertFalse(skip.exists)
        app.terminate()

        app.launchArguments = ["--ui-testing", "--ui-test-preserve-storage", "--ui-test-reduce-motion"]
        app.launch()
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertFalse(skip.exists)
        openFleetSettings(in: app)
        let useEssentials = dashboardModeButton("Essentials", in: app)
        reveal(useEssentials, in: app)
        XCTAssertTrue(useEssentials.isSelected)
    }

    func testSwipeDismissOfDashboardWelcomeKeepsEssentials() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--ui-test-dashboard-fresh", "--ui-test-reduce-motion"]
        app.launch()
        let heading = app.staticTexts["dashboard.chooseView"]
        guard heading.waitForExistence(timeout: 10) else { return XCTFail("Missing dashboard welcome") }
        let dragFrom = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: app.frame.midX, dy: heading.frame.minY - 24
        ))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        dragFrom.press(forDuration: 0.05, thenDragTo: bottom)
        XCTAssertTrue(heading.waitForNonExistence(timeout: 7))
        app.terminate()

        app.launchArguments = ["--ui-testing", "--ui-test-preserve-storage"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 10))
        XCTAssertFalse(heading.exists)
        openFleetSettings(in: app)
        let useEssentials = dashboardModeButton("Essentials", in: app)
        reveal(useEssentials, in: app)
        XCTAssertTrue(useEssentials.isSelected)
    }

    func testDemoAndPreviouslySelectedDashboardDoNotShowWelcome() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-dashboard-fresh"]
        app.launch()
        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["dashboard.chooseView.skip"].exists)
        app.terminate()

        app.launchArguments = ["--ui-testing", "--ui-test-reduce-motion"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["dashboard.chooseView.skip"].exists)
        openFleetSettings(in: app)
        let useFull = dashboardModeButton("Full View", in: app)
        reveal(useFull, in: app)
        XCTAssertTrue(useFull.isSelected)
    }

    func testChooseDashboardAtLargestDynamicType() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--ui-test-dashboard-fresh", "--ui-test-light-appearance",
                               "--ui-test-reduce-motion", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let essentials = app.buttons["dashboard.chooseView.essentials"]
        XCTAssertTrue(essentials.waitForExistence(timeout: 10))
        reveal(essentials, in: app)
        XCTAssertTrue(essentials.label.contains("charts"), "The option's complete description must remain available")
        XCTAssertGreaterThan(essentials.frame.height, 80, "Largest Dynamic Type must grow the option rather than clip it")
        recordScreenshot("Dashboard chooser - largest Dynamic Type", app: app)
        let full = app.buttons["dashboard.chooseView.full"]
        reveal(full, in: app)
        XCTAssertTrue(full.label.contains("API tools"))
        full.tap()
        XCTAssertTrue(full.waitForNonExistence(timeout: 5))
    }

    func testBothDashboardViewsOpenWithFleetAndMinerCharts() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        for isEssentials in [true, false] {
            let mode = isEssentials ? "Essentials" : "Full View"
            app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion"]
                + (isEssentials ? ["--ui-test-dashboard-essentials"] : [])
            app.launch()
            let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 10), "\(mode) must plot fleet hashrate without opening advanced tools")
            reveal(chart, in: app)
            let chartSummary = chart.value as? String ?? ""
            XCTAssertTrue(chartSummary.contains("Last minute"), "The default graph must expose its actual range: \(chartSummary)")
            recordScreenshot("\(mode) - fleet chart", app: app)
            if isEssentials {
                let options = app.buttons["dashboard.viewHistory"]
                reveal(options, in: app)
                options.tap()
                let week = app.buttons["dashboard.historyRange.weekly"]
                reveal(week, in: app)
                week.tap()
                XCTAssertEqual(app.buttons["dashboard.historyRangeMenu"].value as? String, "Last 7 days")
                app.buttons["dashboard.viewHistory"].tap()
            }
            let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
            reveal(miner, in: app)
            miner.tap()
            XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
            XCTAssertTrue(chart.waitForExistence(timeout: 5), "\(mode) must plot the miner chart without a disclosure")
            reveal(chart, in: app)
            XCTAssertTrue(chart.label.contains("by miner"))
            recordScreenshot("\(mode) - miner chart", app: app)
            if isEssentials {
                let metric = app.buttons["detail.historyMetric"]
                reveal(metric, in: app)
                metric.tap()
                app.buttons["Temperature"].tap()
                let empty = app.staticTexts.matching(NSPredicate(
                    format: "label CONTAINS[c] %@", "store temperature or power history"
                )).firstMatch
                XCTAssertTrue(empty.waitForExistence(timeout: 5), "Demo must explain the absence of a saved sensor trend")
                XCTAssertEqual(metric.value as? String, "Temperature")
                let tools = app.buttons["detail.apiToolsDisclosure"]
                reveal(tools, in: app)
                XCTAssertFalse(app.buttons["detail.rawAPI"].exists)
                tools.tap()
                let rawAPI = app.buttons["detail.rawAPI"]
                reveal(rawAPI, in: app)
                rawAPI.tap()
                XCTAssertTrue(app.navigationBars["System info"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["GET /api/system/info"].exists)
                XCTAssertTrue(app.buttons["endpoint.send"].isHittable)
            }
            app.terminate()
        }
    }

    func testEssentialsSidebarKeepsSettingsAndDisclosesMoreTools() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires the native iPad sidebar")
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-dashboard-essentials"]
        app.launch()
        let tools = app.buttons["sidebar.moreTools"]
        let settings = app.buttons["sidebar.destination.monitoring"]
        let network = app.buttons["sidebar.destination.network"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        XCTAssertTrue(settings.isHittable)
        XCTAssertFalse(network.exists)
        recordScreenshot("iPad Essentials with collapsed sidebar tools", app: app)
        tools.tap()
        XCTAssertTrue(network.waitForExistence(timeout: 5))
        XCTAssertEqual(tools.value as? String, "Expanded")
        network.tap()
        XCTAssertTrue(app.buttons["insights.poolNetworks"].waitForExistence(timeout: 5))
        XCTAssertTrue(network.waitForExistence(timeout: 5), "Active tool must stay disclosed in the sidebar")
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let dashboardView = app.segmentedControls["settings.dashboardView"]
        XCTAssertTrue(dashboardView.waitForExistence(timeout: 5))
        XCTAssertTrue(dashboardView.buttons["Essentials"].isSelected)
    }

    func testNativeAccessibilityAuditForFirstMiner() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate() }
        let checks: XCUIAccessibilityAuditType = [.contrast, .hitRegion, .sufficientElementDescription,
                                                 .dynamicType, .textClipped, .trait]
        for light in [true, false] {
            app.launchArguments = ["--ui-testing", "--ui-test-reduce-motion"]
                + (light ? ["--ui-test-light-appearance"] : [])
            app.launch()
            let connect = app.buttons["dashboard.connectFirstMiner"]
            XCTAssertTrue(connect.waitForExistence(timeout: 10))
            reveal(connect, in: app)
            let appearance = light ? "light" : "dark"
            try runAccessibilityAudit(app, checks: checks, screen: "Onboarding (\(appearance))")
            connect.tap()
            let sheetBar = app.navigationBars["Add a miner"]
            XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
            let scroll = app.scrollViews["addMiner.formScroll"]
            let address = app.textFields["addMiner.address"]
            revealManualEntryControl(address, in: scroll, below: sheetBar, app: app)
            XCTAssertEqual(address.label, "Miner IP address or hostname")
            try runAccessibilityAudit(app, checks: checks, screen: "Add Miner (\(appearance))")
            app.terminate()
        }
    }

    private func runAccessibilityAudit(_ app: XCUIApplication, checks: XCUIAccessibilityAuditType, screen: String) throws {
        try app.performAccessibilityAudit(for: checks) { issue in
            print("[AX AUDIT \(screen)] type=\(issue.auditType.rawValue) id=\(issue.element?.identifier ?? "") "
                  + "label=\(issue.element?.label ?? "") \(issue.compactDescription): \(issue.detailedDescription)")
            return false
        }
    }

    func testSystemAppearanceAndManualOverride() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-system-appearance"]
        app.launch()
        defer { app.terminate() }
        let appearance = dashboardSettingsMenu(in: app)
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        let initial = try XCTUnwrap(appearance.value as? String)
        XCTAssertTrue(["System · Light", "System · Dark"].contains(initial), initial)
        let followsDark = initial == "System · Dark"
        let rate = app.descendants(matching: .any)["dashboard.fleetHashrate"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        let canvasRect = CGRect(x: app.frame.minX + 4, y: rate.frame.midY, width: 6, height: 3)
        let canvas = try sampleRegionRGB(app, in: canvasRect)
        for channel in [canvas.r, canvas.g, canvas.b] {
            // The proposed dark canvas is a near-black graphite, not pure black.
            XCTAssertEqual(channel, followsDark ? 0 : 1, accuracy: followsDark ? 0.06 : 0.025)
        }
        recordScreenshot("System \(followsDark ? "Dark" : "Light") dashboard", app: app)
        let manual = followsDark ? "Light" : "Dark"
        setDashboardAppearance(manual, in: app)
        let changed = expectation(for: NSPredicate(format: "value == %@", manual), evaluatedWith: appearance)
        wait(for: [changed], timeout: 5)
        let overridden = try sampleRegionRGB(app, in: canvasRect)
        XCTAssertEqual(overridden.r, followsDark ? 1 : 0, accuracy: followsDark ? 0.025 : 0.06)

        openFleetSettings(in: app)
        app.buttons["monitoring.fleet"].tap()
        let picker = app.buttons["preferences.appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let system = app.buttons["System"]
        XCTAssertTrue(system.waitForExistence(timeout: 5))
        system.tap()
        returnToFleet(in: app)
        let restoredPredicate = NSPredicate(format: "value == %@", initial)
        let restored = expectation(for: restoredPredicate, evaluatedWith: appearance)
        wait(for: [restored], timeout: 5)
        XCTAssertEqual(try sampleRegionRGB(app, in: canvasRect).r, canvas.r, accuracy: 0.025)
        recordScreenshot("Restored \(initial)", app: app)
    }

    func testAppearanceSwitchUpdatesDashboardDetailsAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()
        let appearance = dashboardSettingsMenu(in: app)
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        XCTAssertEqual(appearance.value as? String, "Dark")
        recordScreenshot("Black graphite and gold dark dashboard", app: app)

        let regions = try dashboardSampleRegions(in: app)
        let chains = app.descendants(matching: .any)["dashboard.chains"]
        XCTAssertTrue(chains.waitForExistence(timeout: 5))
        let dark = try verifyDarkSurfaces(app: app, regions: regions, chains: chains)

        setDashboardAppearance("Light", in: app)
        XCTAssertEqual(appearance.value as? String, "Light")
        recordScreenshot("White and gold light dashboard", app: app)
        let light = try verifyLightSurfaces(app: app, regions: regions, chains: chains, dark: dark)

        let lightCard = try verifyLightDetailSettingsAndAbout(app: app, lightSummary: light)
        try restoreDarkModeAndVerify(app: app, appearance: appearance, dark: dark, lightCard: lightCard)
    }

    private func dashboardSampleRegions(in app: XCUIApplication) throws -> DashboardRegions {
        let ticker = app.descendants(matching: .any)["fleet.ticker"]
        XCTAssertTrue(ticker.waitForExistence(timeout: 10))
        let marquee = CGRect(x: max(10, ticker.frame.minX + 10), y: ticker.frame.maxY - 3, width: 12, height: 2)
        let hashrate = app.descendants(matching: .any)["dashboard.fleetHashrate"]
        XCTAssertTrue(hashrate.waitForExistence(timeout: 5))
        // Ticker AX bounds exclude some of its padding. The 16pt gutter beside
        // the hashrate card is the actual canvas, not the ticker background.
        let canvas = CGRect(x: app.frame.minX + 4, y: hashrate.frame.midY, width: 6, height: 3)
        let heroSurface = CGRect(x: app.frame.maxX - 65, y: hashrate.frame.midY, width: 12, height: 3)
        return DashboardRegions(marquee: marquee, canvas: canvas,
                                heroSurface: heroSurface, rate: hashrate.frame.insetBy(dx: 1, dy: 1))
    }

    private func summarySample(app: XCUIApplication, card: XCUIElement) throws -> RGBSample {
        let summaryRect = CGRect(x: card.frame.midX, y: card.frame.minY + 5, width: 12, height: 3)
        return try sampleRegionRGB(app, in: summaryRect)
    }

    private struct DarkBaselines {
        let summary: RGBSample
        let marquee: RGBSample
        let canvas: RGBSample
    }

    private func verifyDarkSurfaces(app: XCUIApplication, regions: DashboardRegions,
                                    chains: XCUIElement) throws -> DarkBaselines {
        let darkMarquee = try sampleRegionRGB(app, in: regions.marquee)
        let darkCanvas = try sampleRegionRGB(app, in: regions.canvas)
        let darkHero = try sampleRegionRGB(app, in: regions.heroSurface)
        XCTAssertLessThan(darkHero.r, 0.20, "Dark mode hashrate uses a raised graphite surface, not the canvas")
        XCTAssertGreaterThan(darkHero.r, darkCanvas.r, "The hashrate surface must lift off the dark canvas")
        let darkRateRegion = try sampleRegionRGB(app, in: regions.rate)
        XCTAssertGreaterThan(darkRateRegion.r, darkHero.r + 0.03,
                             "Light ink must remain visible on the dark hashrate surface")
        XCTAssertLessThan(darkMarquee.r, 0.06, "Dark ticker must stay near-black")
        XCTAssertLessThan(darkMarquee.g, 0.08, "Dark ticker must stay near-black")
        XCTAssertLessThan(darkMarquee.b, 0.09, "Dark ticker must stay near-black")
        let darkSummary = try summarySample(app: app, card: chains)
        try assertRestoredSolo(app, card: chains, top: darkSummary)
        XCTAssertLessThan(darkCanvas.r, 0.06, "Dark canvas must start near-black")
        XCTAssertLessThan(darkCanvas.g, 0.08, "Dark canvas must start near-black")
        XCTAssertLessThan(darkCanvas.b, 0.09, "Dark canvas must start near-black")
        return DarkBaselines(summary: darkSummary, marquee: darkMarquee, canvas: darkCanvas)
    }

    private func verifyLightSurfaces(app: XCUIApplication, regions: DashboardRegions,
                                     chains: XCUIElement, dark: DarkBaselines) throws -> RGBSample {
        let lightMarquee = try sampleRegionRGB(app, in: regions.marquee)
        let lightCanvas = try sampleRegionRGB(app, in: regions.canvas)
        let lightHero = try sampleRegionRGB(app, in: regions.heroSurface)
        XCTAssertLessThan(lightHero.r, 0.20, "Light mode hashrate needs a contrasting charcoal surface")
        XCTAssertEqual(lightHero.r, lightHero.g, accuracy: 0.02)
        XCTAssertEqual(lightHero.g, lightHero.b, accuracy: 0.02)
        let lightRateRegion = try sampleRegionRGB(app, in: regions.rate)
        XCTAssertGreaterThan(lightRateRegion.r, lightHero.r + 0.03, "Light ink must remain visible on charcoal")
        XCTAssertGreaterThan(lightMarquee.r, 0.97, "Light marquee must blend into the white page")
        XCTAssertGreaterThan(lightMarquee.g, 0.97, "Light marquee must blend into the white page")
        XCTAssertGreaterThan(lightMarquee.b, 0.97, "Light marquee must blend into the white page")
        XCTAssertGreaterThan(lightCanvas.r, 0.97, "Light canvas must start with clean white")
        XCTAssertGreaterThan(lightCanvas.g, 0.97, "Light canvas must start with clean white")
        XCTAssertGreaterThan(lightCanvas.b, 0.97, "Light canvas must not have a cream tint")
        XCTAssertEqual(lightMarquee.r, lightCanvas.r, accuracy: 0.025, "No separate light marquee background")
        XCTAssertEqual(dark.marquee.r, dark.canvas.r, accuracy: 0.025, "No separate dark marquee background")
        XCTAssertGreaterThan(lightCanvas.r - dark.canvas.r, 0.35,
                             "Canvas background must distinctly differ between modes")
        let lightSummary = try summarySample(app: app, card: chains)
        try assertRestoredSolo(app, card: chains, top: lightSummary)
        XCTAssertEqual(lightSummary.r, 33.0 / 255.0, accuracy: 0.01,
                       "Solo must use slightly lighter blade graphite in light mode")
        return lightSummary
    }

    private func verifyLightDetailSettingsAndAbout(app: XCUIApplication,
                                                   lightSummary: RGBSample) throws -> RGBSample {
        app.buttons["dashboard.addMiner"].tap()
        XCTAssertTrue(app.navigationBars["Add a miner"].waitForExistence(timeout: 5))
        recordScreenshot("White and gold add miner sheet", app: app)
        app.buttons["Cancel"].tap()

        let miner = minerButton(named: "Little Supra", in: app)
        reveal(miner, in: app)
        // The AX link bounds contain the title, not the outer card. Sample its
        // 14pt top padding, centered away from the rounded corners and glyphs.
        let lightCardRect = CGRect(x: miner.frame.midX, y: miner.frame.minY - 9, width: 12, height: 3)
        let lightCard = try sampleRegionRGB(app, in: lightCardRect)
        XCTAssertGreaterThan(lightCard.r, 0.75, "Light miner card surface should be neutral light gray")
        XCTAssertGreaterThan(lightCard.g, 0.70, "Light miner card surface should be neutral light gray")
        XCTAssertLessThan(abs(lightCard.r - lightCard.g), 0.02, "Light cards must remain neutral")
        XCTAssertLessThan(abs(lightCard.g - lightCard.b), 0.02, "Light cards must not have a cream tint")
        XCTAssertEqual(lightCard.r, 229.0 / 255.0, accuracy: 0.025, "Miner cards must use the visible silver layer")
        XCTAssertGreaterThan(lightCard.r - lightSummary.r, 0.75,
                             "Silver miners must contrast with the black comparison panel")
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        recordScreenshot("White and gold light miner details", app: app)
        app.navigationBars.buttons.firstMatch.tap()

        openFleetSettings(in: app)
        app.buttons["monitoring.fleet"].tap()
        let picker = app.buttons["preferences.appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("Light") || (picker.value as? String) == "Light", picker.debugDescription)
        recordScreenshot("White and gold light preferences", app: app)
        returnToFleet(in: app)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        // No tab bar in this app shell; the dashboard toolbar menu proves we are back on the fleet.
        XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 5))

        openFleetAbout(in: app)
        XCTAssertTrue(app.navigationBars["About Hash Fleet"].waitForExistence(timeout: 5))
        recordScreenshot("White and gold light about form", app: app)
        returnToFleet(in: app)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        return lightCard
    }

    private func restoreDarkModeAndVerify(app: XCUIApplication, appearance: XCUIElement,
                                          dark: DarkBaselines, lightCard: RGBSample) throws {
        XCTAssertEqual(appearance.value as? String, "Light")
        setDashboardAppearance("Dark", in: app)
        XCTAssertEqual(appearance.value as? String, "Dark")
        recordScreenshot("Restored logo graphite and gold dark dashboard", app: app)
        let miner = minerButton(named: "Little Supra", in: app)
        reveal(miner, in: app)
        let darkCardRect = CGRect(x: miner.frame.midX, y: miner.frame.minY - 9, width: 12, height: 3)
        let darkCard = try sampleRegionRGB(app, in: darkCardRect)
        XCTAssertLessThan(darkCard.r, 0.50, "Dark miner card surface should be dark graphite")
        XCTAssertLessThan(darkCard.g, 0.50, "Dark miner card surface should be dark graphite")
        XCTAssertGreaterThan(lightCard.r - darkCard.r, 0.30, "Card surface must distinctly differ between modes")
        XCTAssertEqual(darkCard.r, 24.0 / 255.0, accuracy: 0.025, "Miner cards must use the raised graphite layer")
        XCTAssertEqual(dark.summary.r, 33.0 / 255.0, accuracy: 0.01,
                       "Solo keeps its sampled blade graphite in dark mode")
        XCTAssertNotEqual(darkCard.r, dark.summary.r, accuracy: 0.01,
                          "Miner cards must stay distinct from Solo's blade graphite")
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        recordScreenshot("Gold miner hashrate without border", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        let bestShares = app.descendants(matching: .any)["bestShare.card"]
        reveal(bestShares, in: app)
        XCTAssertTrue(bestShares.exists)
        recordScreenshot("Fleet best shares subtle border", app: app)

        openFleetAbout(in: app)
        XCTAssertTrue(app.navigationBars["About Hash Fleet"].waitForExistence(timeout: 5))
        recordScreenshot("Graphite and gold dark about form", app: app)
        returnToFleet(in: app)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
    }
}
