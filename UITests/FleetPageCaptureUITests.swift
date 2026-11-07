import XCTest

/// Accepts and captures screenshots of all navigable app screens and modal sheet flows
/// in Hash Fleet, saving PNG files directly to the designated scratch directory.
@MainActor
final class FleetPageCaptureUITests: XCTestCase {
    private var outputDir: URL {
        if let path = ProcessInfo.processInfo.environment["HASHFLEET_SCREENSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("HashFleetScreenshots", isDirectory: true)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    func saveScreenshot(_ name: String, app: XCUIApplication) {
        let screenshot = app.screenshot()
        let fileURL = outputDir.appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: fileURL)
            print("[FLEET_PAGE_CAPTURE] Wrote \(fileURL.path)")
        } catch {
            XCTFail("[FLEET_PAGE_CAPTURE] Failed to write \(fileURL.path): \(error)")
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<16 {
            if element.exists && element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.25 : 0.58))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.58 : 0.22))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
    }

    func firstMinerCard(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
    }

    func minerCard(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS %@", name)
        ).firstMatch
    }

    // MARK: - 1. Empty State & Onboarding & Add Miner Sheet

    func testCapture01_EmptyStateAndAddMinerSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }

        // Dashboard empty state (no miners)
        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].waitForExistence(timeout: 8))
        saveScreenshot("01_dashboard_empty_state", app: app)

        // Open Add Miner sheet
        app.buttons["dashboard.addMiner"].tap()
        XCTAssertTrue(app.textFields["addMiner.address"].waitForExistence(timeout: 5))
        saveScreenshot("02_add_miner_sheet_empty", app: app)

        // Fill Add Miner form
        let addressField = app.textFields["addMiner.address"]
        addressField.tap()
        addressField.typeText("192.168.1.150")
        saveScreenshot("03_add_miner_sheet_filled", app: app)

        // Tap cancel to dismiss
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        }
    }

    // MARK: - 2. Launch Splash

    func testCapture02_LaunchSplash() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--show-launch-splash", "--ui-test-hold-splash"]
        app.launch()
        defer { app.terminate() }

        let splash = app.descendants(matching: .any)["launch.splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 5))
        saveScreenshot("04_launch_splash", app: app)

        if app.buttons["launch.continue"].exists {
            app.buttons["launch.continue"].tap()
        }
    }

    // MARK: - 3. Demo Fleet Dashboard & Cards

    func testCapture03_DashboardDemoFleet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 8))
        saveScreenshot("05_dashboard_demo_top", app: app)

        // Scroll down to view miner cards and middle sections
        app.swipeUp()
        saveScreenshot("06_dashboard_demo_miners", app: app)

        // History is now prominent, not hidden behind a disclosure.
        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        reveal(chart, in: app)
        saveScreenshot("07_dashboard_history_visible", app: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["dashboard.historySelection.timestamp"].waitForExistence(timeout: 5))
        saveScreenshot("08_dashboard_history_point_selected", app: app)

        // Scroll to Pools card
        let poolsCard = app.descendants(matching: .any)["fleetPools.card"].firstMatch
        if poolsCard.waitForExistence(timeout: 5) {
            reveal(poolsCard, in: app)
            saveScreenshot("09_dashboard_pools_card", app: app)
        }

        // Scroll to Chain / Network summary card
        let chainCard = app.descendants(matching: .any)["dashboard.chains"].firstMatch
        if chainCard.waitForExistence(timeout: 5) {
            reveal(chainCard, in: app)
            saveScreenshot("10_dashboard_chain_card", app: app)
        }

        // Expand first miner card details / settings menu from dashboard
        let settingsPrefix = "identifier BEGINSWITH 'dashboard.card.settings.'"
        let firstSettingsBtn = app.buttons.matching(NSPredicate(format: settingsPrefix)).firstMatch
        if firstSettingsBtn.waitForExistence(timeout: 5) {
            reveal(firstSettingsBtn, in: app)
            firstSettingsBtn.tap()
            saveScreenshot("11_dashboard_card_settings_menu_opened", app: app)
            // Tap outside or dismiss menu
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        }
    }

    // MARK: - 4. Pool Icon Demo Gallery

    func testCapture04_PoolIconDemoGallery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--pool-icon-demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 8))
        saveScreenshot("12_pool_icon_demo_gallery_top", app: app)
        app.swipeUp()
        saveScreenshot("13_pool_icon_demo_gallery_scrolled", app: app)
    }

    // MARK: - 5. Network Insights & CKPool Lookup

    func testCapture05_NetworkInsightsAndCKPoolLookup() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 8))
        // Scroll down to Network card
        let networkBtn = app.buttons["dashboard.networkDetails"]
        reveal(networkBtn, in: app)
        if networkBtn.waitForExistence(timeout: 5) {
            networkBtn.tap()
        } else {
            let netLink = app.staticTexts["Network"].firstMatch
            reveal(netLink, in: app)
            netLink.tap()
        }

        XCTAssertTrue(app.navigationBars["Network insights"].waitForExistence(timeout: 6))
        saveScreenshot("14_network_insights_top", app: app)

        app.swipeUp()
        saveScreenshot("15_network_insights_scrolled", app: app)

        // Tap CKPool lookup link
        let lookupBtn = app.buttons["insights.lookup"]
        if lookupBtn.waitForExistence(timeout: 5) {
            reveal(lookupBtn, in: app)
            lookupBtn.tap()
            XCTAssertTrue(app.navigationBars["CKPool lookup"].waitForExistence(timeout: 5))
            saveScreenshot("16_ckpool_lookup_empty", app: app)

            // Enter a sample address and lookup
            let addrField = app.textFields["poolLookup.address"]
            if addrField.waitForExistence(timeout: 4) {
                addrField.tap()
                addrField.typeText("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa")
                saveScreenshot("17_ckpool_lookup_address_entered", app: app)
            }
            // Go back to Network
            app.navigationBars.buttons.firstMatch.tap()
        }

        // Go back to Fleet
        app.navigationBars.buttons.firstMatch.tap()
    }

    // MARK: - 6. Miner Detail View & All Inner Subsections

    func testCapture06_MinerDetailViewAndSections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 8))

        // Tap the first miner card to open Miner Detail
        let miner = firstMinerCard(in: app)
        XCTAssertTrue(miner.waitForExistence(timeout: 5))
        reveal(miner, in: app)
        miner.tap()

        _ = app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 6)
        saveScreenshot("18_miner_detail_top", app: app)

        // Scroll down to Diagnostics section
        let diagSection = app.buttons["detail.diagnosticsDisclosure"]
        if diagSection.waitForExistence(timeout: 4) {
            reveal(diagSection, in: app)
            diagSection.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            let expandedPredicate = NSPredicate(format: "value == %@", "Expanded")
            let expanded = XCTNSPredicateExpectation(predicate: expandedPredicate, object: diagSection)
            XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
            let electrical = app.staticTexts["ELECTRICAL & CLOCKS"]
            reveal(electrical, in: app)
            XCTAssertTrue(electrical.isHittable)
            saveScreenshot("19_miner_detail_diagnostics_expanded", app: app)
        }

        // Scroll further down in detail view
        app.swipeUp()
        saveScreenshot("20_miner_detail_middle", app: app)

        app.swipeUp()
        saveScreenshot("21_miner_detail_tools_bottom", app: app)

        // Developer tools are a direct section, not an additional disclosure. The header is a
        // visual grouping label and is not guaranteed to remain a separate accessibility node.
        let endpointExplorer = app.buttons["detail.endpointExplorer"]
        reveal(endpointExplorer, in: app)
        XCTAssertTrue(endpointExplorer.exists && endpointExplorer.isHittable)
        saveScreenshot("22_miner_detail_developer_tools", app: app)
    }
}
