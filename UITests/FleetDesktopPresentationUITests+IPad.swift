import XCTest

/// Real iPad workspace workflows, split from FleetDesktopPresentationUITests to keep each file focused.
extension FleetDesktopPresentationUITests {
    func testRealIPadSidebarReplacesTuningAndReselectedRoots() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let miner = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'sidebar.destination.miner-' AND label BEGINSWITH %@", "Workshop Gamma"
        )).firstMatch
        let tuning = app.buttons["detail.tuning.settings"]
        let voltage = app.textFields["tuningSession.voltage.customInput"]
        assertHittable(miner)
        miner.tap()
        // This destination-closure push does not add an element to NavigationPath.
        // Reselecting the same root must close it, not just clear an empty path.
        for _ in 0..<2 {
            reveal(tuning, in: app)
            assertHittable(tuning)
            tuning.tap()
            XCTAssertTrue(voltage.waitForExistence(timeout: 8), app.debugDescription)
            assertHittable(miner)
            miner.tap()
            assertHittable(app.buttons["detail.quick.tuning"])
            XCTAssertFalse(voltage.exists, "Reselection must close the old tuning workspace")
        }

        let roots = [
            ("overview", "Hash Fleet"), ("network", "Network insights"),
            ("energy", "Electricity estimates"), ("achievements", "Mining Achievements"),
            ("reports", "Fleet Reports"), ("backup", "Backup & restore"),
            ("monitoring", "App settings"), ("about", "About Hash Fleet")
        ]
        for (destination, title) in roots {
            miner.tap()
            reveal(tuning, in: app)
            assertHittable(tuning)
            tuning.tap()
            XCTAssertTrue(voltage.waitForExistence(timeout: 8))
            let sidebar = app.buttons["sidebar.destination.\(destination)"]
            assertHittable(sidebar)
            sidebar.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertFalse(voltage.exists)
            XCTAssertEqual(app.sheets.count, 0)
        }

        let overview = app.buttons["sidebar.destination.overview"]
        overview.tap()
        for _ in 0..<2 {
            app.buttons["sidebar.addMiner"].tap()
            XCTAssertTrue(app.textFields["addMiner.address"].waitForExistence(timeout: 8))
            overview.tap()
            assertHittable(dashboardSettingsMenu(in: app))
            XCTAssertFalse(app.textFields["addMiner.address"].exists)
        }
    }

    func testRealIPadSettingsAndNestedGuideStayInsideWorkspace() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        // No desktop-layout override: exercise the physical iPad policy, not a simulated Mac.
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let overview = sidebarOverview(in: app)
        assertHittable(overview)
        openFleetSettings(in: app)
        let settingsDone = app.buttons["monitoring.settings.done"]
        assertHittable(settingsDone)
        assertHittable(overview)
        let settingsTitle = app.navigationBars["App settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 8), app.debugDescription)
        let settingsPage = app.descendants(matching: .any)
            .matching(identifier: "monitoring.settings.page").firstMatch
        capture("Real iPad Settings before workspace bounds check", app: app)
        let notificationsFrame = app.buttons["monitoring.notifications"].frame
        print("[IPAD_SETTINGS_GEOMETRY] page=\(settingsPage.frame), title=\(settingsTitle.frame), notifications=\(notificationsFrame)")
        let notifications = app.buttons["monitoring.notifications"]
        assertFillsWindow(settingsPage, app: app, visibleContent: notifications)
        assertReadableSettingsRow(notifications, app: app, sidebar: overview)
        let hero = app.descendants(matching: .any).matching(identifier: "monitoring.hero").firstMatch
        XCTAssertTrue(hero.exists)
        XCTAssertGreaterThanOrEqual(hero.frame.minX, overview.frame.maxX)
        XCTAssertLessThanOrEqual(hero.frame.maxX, app.frame.maxX)
        XCTAssertEqual(hero.frame.midX, notifications.frame.midX, accuracy: 2)
        capture("Real iPad Settings inside persistent split workspace", app: app)

        let guide = app.buttons["monitoring.featureTour"]
        reveal(guide, in: app)
        assertHittable(guide)
        assertReadableSettingsRow(guide, app: app, sidebar: overview)
        guide.tap()
        let closeGuide = app.buttons["tour.close"]
        assertHittable(closeGuide)
        assertHittable(overview)
        XCTAssertEqual(app.sheets.count, 0, "An iPad app page must not become a sheet")
        capture("Real iPad nested guide stays inside workspace", app: app)
        closeGuide.tap()
        assertHittable(settingsDone)
        settingsDone.tap()
        assertHittable(dashboardSettingsMenu(in: app))
        XCTAssertFalse(settingsDone.exists)
        assertHittable(overview)
    }

    func testRealIPadSidebarAddUsesTheWholeTargetAndDismissesInApp() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let add = app.buttons["sidebar.addMiner"]
        assertHittable(add)
        XCTAssertGreaterThanOrEqual(add.frame.width, 44)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        // Exercise padding away from the plus glyph, not just the glyph's center.
        add.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        let address = app.textFields["addMiner.address"]
        assertHittable(address)
        assertFillsWindow(app.navigationBars["Add a miner"], app: app, visibleContent: address)
        assertHittable(sidebarOverview(in: app))
        capture("Real iPad sidebar Add edge hit stays in the workspace", app: app)
        app.buttons["addMiner.dismiss"].tap()
        XCTAssertFalse(address.exists)
        assertHittable(add)
        assertHittable(dashboardSettingsMenu(in: app))
    }

    func testRealIPadAboutKeepsReadableContentAndInteractiveSidebar() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let overview = sidebarOverview(in: app)
        assertHittable(overview)
        openFleetAbout(in: app)
        let title = app.navigationBars["About Hash Fleet"]
        let hero = app.descendants(matching: .any).matching(identifier: "about.hero").element
        assertFillsWindow(title, app: app, visibleContent: hero)
        assertReadableSettingsRow(hero, app: app, sidebar: overview)
        print("[IPAD_ABOUT_GEOMETRY] hero=\(hero.frame), sidebar=\(overview.frame), window=\(app.frame)")
        capture("Real iPad About with shared reading typography", app: app)

        let done = app.buttons["about.done"]
        assertHittable(done)
        done.tap()
        XCTAssertFalse(done.exists)
        assertHittable(dashboardSettingsMenu(in: app))
        assertHittable(overview)
        overview.tap()
        assertHittable(dashboardSettingsMenu(in: app))
    }

    func testRealIPadSharedDesignReferencePagesKeepTheirControlsReachable() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let overview = sidebarOverview(in: app)
        assertHittable(overview)
        assertHittable(dashboardSettingsMenu(in: app))
        capture("Real iPad shared design Overview reference", app: app)

        let miner = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Workshop Gamma"
        )).firstMatch
        assertHittable(miner)
        miner.tap()
        let pool = app.descendants(matching: .any).matching(identifier: "detail.poolContext").firstMatch
        XCTAssertTrue(pool.waitForExistence(timeout: 8), app.debugDescription)
        assertHittable(overview)
        capture("Real iPad shared design Miner reference", app: app)
        overview.tap()
        assertHittable(dashboardSettingsMenu(in: app))

        openFleetSettings(in: app)
        let preferences = app.buttons["monitoring.fleet"]
        reveal(preferences, in: app)
        assertHittable(preferences)
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Preferences"].waitForExistence(timeout: 8))
        let sort = app.descendants(matching: .any).matching(identifier: "preferences.sortOption").firstMatch
        assertHittable(sort)
        assertHittable(overview)
        capture("Real iPad shared design Preferences top reference", app: app)

        let storage = app.switches["preferences.telemetryStorageEnabled"]
        reveal(storage, in: app)
        assertHittable(storage)
        capture("Real iPad shared design Preferences storage reference", app: app)

        let externalData = app.switches["preferences.externalData"]
        reveal(externalData, in: app)
        assertHittable(externalData)
        capture("Real iPad shared design Preferences bottom reference", app: app)
        overview.tap()
        assertHittable(dashboardSettingsMenu(in: app))
    }

    func testRealIPadSidebarReturnsFromMinerRepeatedlyAndSwitchesRoots() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let overview = app.buttons["sidebar.destination.overview"]
        let miner = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'dashboard.miner.' AND label BEGINSWITH %@", "Workshop Gamma"
        )).firstMatch
        let pool = app.descendants(matching: .any).matching(identifier: "detail.poolContext").firstMatch

        // An already-selected Overview must pop the path every time, not just
        // after replacing the whole split stack on its first activation.
        for _ in 0..<2 {
            reveal(miner, in: app)
            assertHittable(miner)
            miner.tap()
            XCTAssertTrue(pool.waitForExistence(timeout: 8), app.debugDescription)
            assertHittable(overview)
            overview.tap()
            assertHittable(dashboardSettingsMenu(in: app))
            XCTAssertFalse(pool.isHittable)
            XCTAssertEqual(app.sheets.count, 0)
        }

        reveal(miner, in: app)
        miner.tap()
        XCTAssertTrue(pool.waitForExistence(timeout: 8))
        let reports = app.buttons["sidebar.destination.reports"]
        assertHittable(reports)
        reports.tap()
        XCTAssertTrue(app.navigationBars["Fleet Reports"].waitForExistence(timeout: 8))
        XCTAssertFalse(pool.isHittable)
        overview.tap()
        assertHittable(dashboardSettingsMenu(in: app))
        XCTAssertEqual(app.sheets.count, 0)

        let settings = app.buttons["sidebar.destination.monitoring"]
        assertHittable(settings)
        settings.tap()
        let preferences = app.buttons["monitoring.fleet"]
        reveal(preferences, in: app)
        assertHittable(preferences)
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Preferences"].waitForExistence(timeout: 8))
        settings.tap()
        XCTAssertTrue(app.navigationBars["App settings"].waitForExistence(timeout: 8), app.debugDescription)
        assertHittable(app.buttons["monitoring.notifications"])
        XCTAssertFalse(app.navigationBars["Preferences"].exists)
        overview.tap()
        assertHittable(dashboardSettingsMenu(in: app))
        capture("Real iPad repeated root returns preserve interactive workspace", app: app)
    }

    func testRealIPadReportsEnergyAndAchievementsKeepSharedReadingRoles() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let overview = sidebarOverview(in: app)
        assertHittable(overview)
        let reports = app.buttons["sidebar.destination.reports"]
        assertHittable(reports)
        reports.tap()
        XCTAssertTrue(app.navigationBars["Fleet Reports"].waitForExistence(timeout: 8))
        // LabeledContent exposes its combined label/value as the interactive
        // accessibility element, alongside a non-hittable label-only child.
        let fleetSize = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fleet size,")
        ).firstMatch
        reveal(fleetSize, in: app)
        assertHittable(fleetSize)
        let reportBodyHeight = fleetSize.frame.height
        XCTAssertGreaterThanOrEqual(fleetSize.frame.minX, overview.frame.maxX)
        XCTAssertLessThanOrEqual(fleetSize.frame.maxX, app.frame.maxX)
        XCTAssertEqual(app.sheets.count, 0)
        capture("Real iPad Reports shared reading roles", app: app)
        let captureReport = app.buttons["fleetReport.capture"]
        reveal(captureReport, in: app)
        assertHittable(captureReport)
        captureReport.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "fleetReport.capturedAt").firstMatch.exists)

        let energy = app.buttons["sidebar.destination.energy"]
        assertHittable(energy)
        energy.tap()
        XCTAssertTrue(app.navigationBars["Electricity estimates"].waitForExistence(timeout: 8))
        let rate = app.textFields["energy.rateField"]
        assertHittable(rate)
        rate.tap()
        if let previous = rate.value as? String, previous != "Price per kWh" {
            rate.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        rate.typeText("0.15")
        // The system input popover owns a full-window dismiss region. Wait for
        // that modal barrier, not the preview identifier shared by the keyboard.
        let dismissPopover = app.otherElements["PopoverDismissRegion"]
        if dismissPopover.waitForExistence(timeout: 2) {
            assertHittable(dismissPopover)
            dismissPopover.tap()
            let popoverGone = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in !dismissPopover.exists }, object: dismissPopover
            )
            XCTAssertEqual(XCTWaiter.wait(for: [popoverGone], timeout: 5), .completed)
        }
        // Finish editing through the system control before checking reading roles.
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            let hideKeyboard = keyboard.buttons["Hide keyboard"].firstMatch
            assertHittable(hideKeyboard)
            hideKeyboard.tap()
        }
        let keyboardGone = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !keyboard.exists }, object: keyboard
        )
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 5), .completed,
                       "Finish editing before checking Save reachability")
        let save = app.buttons["energy.save"]
        assertHittable(save)
        save.tap()
        let feedback = app.staticTexts["energy.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertTrue(feedback.label.contains("Rate saved"))
        let power = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fresh power subtotal,")
        ).firstMatch
        reveal(power, in: app)
        assertHittable(power)
        XCTAssertEqual(power.frame.height, reportBodyHeight, accuracy: 1,
                       "Matching body labels must not change font size between pages")
        XCTAssertGreaterThanOrEqual(power.frame.minX, overview.frame.maxX)
        XCTAssertLessThanOrEqual(power.frame.maxX, app.frame.maxX)
        XCTAssertEqual(app.sheets.count, 0)
        capture("Real iPad Energy shared reading roles", app: app)

        let achievements = app.buttons["sidebar.destination.achievements"]
        assertHittable(achievements)
        achievements.tap()
        let title = app.navigationBars["Mining Achievements"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        let empty = app.staticTexts["No achievements yet"]
        assertHittable(empty)
        XCTAssertGreaterThanOrEqual(empty.frame.minX, overview.frame.maxX)
        XCTAssertLessThanOrEqual(empty.frame.maxX, app.frame.maxX)
        let filter = app.buttons["achievements.filter"]
        assertHittable(filter)
        filter.tap()
        app.buttons["Best Shares"].tap()
        assertHittable(empty)
        XCTAssertEqual(app.sheets.count, 0)
        capture("Real iPad Achievements shared reading roles", app: app)
        overview.tap()
        assertHittable(dashboardSettingsMenu(in: app))
    }
}
