import XCTest

/// Later capture sections of FleetPageCaptureUITests: miner settings categories, compatibility
/// and endpoint exploration, the Settings tab sub-pages, About, and light appearance coverage.
extension FleetPageCaptureUITests {
    // MARK: - 7. Miner Settings Categories (General, Cooling, Display, Pools, Tuning, Advanced)

    func testCapture07_MinerSettingsCategories() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        defer { app.terminate() }
        let miner = minerCard(named: "Workshop Gamma", in: app)
        reveal(miner, in: app)
        miner.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.textFields["settings.quick.hostname"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.reportedState"].exists)
        saveScreenshot("23_miner_settings_unified_workspace", app: app)
        let pages = [("general", "General", "25"), ("cooling", "Cooling", "26"),
                     ("display", "Display", "27"), ("pools", "Pools", "28"),
                     ("tuning", "Frequency & voltage", "31"), ("advanced", "Tools & firmware", "32")]
        for (id, title, number) in pages {
            let route = app.buttons["settings.\(id)"]
            reveal(route, in: app)
            XCTAssertTrue(route.exists && route.isHittable)
            app.staticTexts[title].firstMatch.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["BackButton"].exists)
            saveScreenshot("\(number)_miner_settings_category_\(id)", app: app)
            if id == "pools" {
                captureGuidedPoolSetup(app)
            }
            if id == "advanced" {
                captureAdvancedDetours(app)
            }
            let backButtons = app.buttons.matching(identifier: "BackButton")
            XCTAssertGreaterThan(backButtons.count, 0)
            backButtons.element(boundBy: backButtons.count - 1).tap()
            let settingsHub = app.textFields["settings.quick.hostname"]
            if !settingsHub.waitForExistence(timeout: 1) {
                let settings = app.buttons["detail.settings"]
                reveal(settings, in: app)
                XCTAssertTrue(settings.waitForExistence(timeout: 5) && settings.isHittable)
                settings.tap()
            }
            XCTAssertTrue(settingsHub.waitForExistence(timeout: 5))
        }
    }

    private func captureGuidedPoolSetup(_ app: XCUIApplication) {
        let guided = app.buttons["settings.pools.guidedSetup"]
        reveal(guided, in: app)
        guided.tap()
        XCTAssertTrue(app.navigationBars["Guided Pool Setup"].waitForExistence(timeout: 5))
        saveScreenshot("29_mining_setup_catalog_modal", app: app)
        app.swipeUp()
        saveScreenshot("30_mining_setup_catalog_scrolled", app: app)
        app.navigationBars["Guided Pool Setup"].buttons.firstMatch.tap()
    }

    private func captureAdvancedDetours(_ app: XCUIApplication) {
        let custom = app.buttons["settings.customJSON"]
        reveal(custom, in: app)
        custom.tap()
        XCTAssertTrue(app.textViews["custom_json.editor"].waitForExistence(timeout: 5))
        saveScreenshot("51_custom_firmware_json", app: app)
        app.navigationBars["Custom JSON"].buttons.firstMatch.tap()
        let firmware = app.buttons["Firmware OTA update"]
        reveal(firmware, in: app)
        firmware.tap()
        XCTAssertTrue(app.navigationBars["Upload firmware"].waitForExistence(timeout: 5))
        saveScreenshot("52_firmware_update", app: app)
        app.navigationBars["Upload firmware"].buttons.firstMatch.tap()
        let webUI = app.buttons["Custom web UI update"]
        reveal(webUI, in: app)
        webUI.tap()
        XCTAssertTrue(app.navigationBars["Upload web interface"].waitForExistence(timeout: 5))
        saveScreenshot("53_web_interface_update", app: app)
        app.navigationBars["Upload web interface"].buttons.firstMatch.tap()
    }

    // MARK: - 8. Compatibility, Endpoint Explorer, Live Console & Write Preview Sheet

    func testCapture08_CompatibilityAndEndpointExplorerAndLiveConsole() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 8))

        // Open first miner
        let miner = minerCard(named: "Workshop Gamma", in: app)
        reveal(miner, in: app)
        miner.tap()

        // 1. Check Compatibility
        let compatLink = app.buttons["detail.compatibility"]
        reveal(compatLink, in: app)
        if compatLink.waitForExistence(timeout: 5) {
            compatLink.tap()
            XCTAssertTrue(app.navigationBars["Check compatibility"].waitForExistence(timeout: 6))
            saveScreenshot("33_miner_compatibility_view", app: app)
            app.swipeUp()
            saveScreenshot("34_miner_compatibility_view_scrolled", app: app)
            app.navigationBars.buttons.firstMatch.tap()
        }

        // Developer tools are directly visible after the explicit mode opt-in. The section header
        // is a visual grouping label and is not guaranteed to remain a separate accessibility node.
        let endpointExplorer = app.buttons["detail.endpointExplorer"]
        reveal(endpointExplorer, in: app)
        XCTAssertTrue(endpointExplorer.exists && endpointExplorer.isHittable)

        // 2. Endpoint Explorer
        endpointExplorer.tap()
        XCTAssertTrue(app.navigationBars["Endpoint explorer"].waitForExistence(timeout: 6))
        saveScreenshot("35_endpoint_explorer_catalog", app: app)

        // Open a read endpoint (e.g. System info GET /api/system/info)
        let systemInfoRow = app.staticTexts["System info"].firstMatch
        if systemInfoRow.waitForExistence(timeout: 4) {
            systemInfoRow.tap()
            XCTAssertTrue(app.navigationBars["System info"].waitForExistence(timeout: 5))
            saveScreenshot("36_miner_endpoint_read_view", app: app)
            app.navigationBars.buttons.firstMatch.tap()
        }

        captureWriteEndpointReview(app)
        app.navigationBars.buttons.firstMatch.tap()

        // 3. Live Console
        let liveConsole = app.buttons["detail.liveConsole"]
        reveal(liveConsole, in: app)
        if liveConsole.waitForExistence(timeout: 5) {
            liveConsole.tap()
            XCTAssertTrue(app.navigationBars["Live console"].waitForExistence(timeout: 6))
            saveScreenshot("39_miner_live_console", app: app)
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    /// Opens a write endpoint (e.g. Restart POST /api/system/restart) and captures the
    /// confirmation review sheet presented before sending.
    private func captureWriteEndpointReview(_ app: XCUIApplication) {
        let restartRow = app.staticTexts["Restart device"].firstMatch
        reveal(restartRow, in: app)
        XCTAssertTrue(restartRow.exists && restartRow.isHittable)
        guard restartRow.waitForExistence(timeout: 4) else { return }
        restartRow.tap()
        XCTAssertTrue(app.navigationBars["Restart device"].waitForExistence(timeout: 5))
        saveScreenshot("37_miner_endpoint_write_view", app: app)

        // Tap send request to bring up the confirmation review sheet
        let sendBtn = app.buttons["endpoint.send"]
        if sendBtn.waitForExistence(timeout: 4), sendBtn.isEnabled {
            sendBtn.tap()
            _ = app.navigationBars["Review before sending"].waitForExistence(timeout: 4)
            saveScreenshot("38_write_confirmation_review_sheet", app: app)
            if app.buttons["Cancel"].exists {
                app.buttons["Cancel"].tap()
            }
        }
        app.navigationBars.buttons.firstMatch.tap()
    }

    // MARK: - 9. Settings Tab & Sub-Pages

    func testCapture09_SettingsTabAndSubPages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 8))
        openFleetSettings(in: app)
        saveScreenshot("40_settings_main_menu", app: app)

        let pages = [
            (id: "monitoring.fleet", title: "Preferences", screenshot: "41_settings_fleet_preferences"),
            (id: "monitoring.widgets", title: "Widgets", screenshot: "42_settings_widgets_page"),
            (id: "monitoring.liveActivity", title: "Live Activity", screenshot: "43_settings_live_activity_page"),
            (id: "monitoring.systemFeatures", title: "Shortcuts & Controls", screenshot: "44_settings_shortcuts_and_controls"),
            (id: "monitoring.performance", title: "Frame Pacing", screenshot: "45_settings_frame_pacing_diagnostics")
        ]

        for page in pages {
            let route = app.buttons[page.id]
            reveal(route, in: app)
            XCTAssertTrue(route.waitForExistence(timeout: 5) && route.isHittable)
            route.tap()
            let navigationBar = app.navigationBars[page.title]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            saveScreenshot(page.screenshot, app: app)
            navigationBar.buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons["monitoring.settings.done"].waitForExistence(timeout: 5))
        }
    }

    // MARK: - 10. About Tab

    func testCapture10_AboutTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 8))
        openFleetAbout(in: app)
        saveScreenshot("46_about_page_top", app: app)

        app.swipeUp()
        saveScreenshot("47_about_page_bottom", app: app)
    }

    // MARK: - 11. Light Appearance Coverage for Key Views

    func testCapture11_LightAppearanceKeyViews() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-light-appearance"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 8))
        saveScreenshot("48_light_dashboard_demo", app: app)

        // Settings tab in light mode
        openFleetSettings(in: app)
        saveScreenshot("49_light_settings_tab", app: app)

        // About tab in light mode
        returnToFleet(in: app)
        openFleetAbout(in: app)
        saveScreenshot("50_light_about_tab", app: app)
    }
}
