import XCTest
import UIKit

@MainActor
final class CompactDashboardUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testInitialViewportShowsMinerBeforeSecondaryInformation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 5))
        XCTAssertTrue(miner.isHittable, "A miner must be reachable without scrolling or a jump button")
        XCTAssertLessThanOrEqual(miner.frame.maxY, app.windows.firstMatch.frame.maxY,
                                 "The first complete miner card should fit in the initial viewport")
        let chains = app.descendants(matching: .any).matching(identifier: "dashboard.chains").firstMatch
        XCTAssertLessThan(chains.frame.height, 190,
                          "Collapsed solo comparison should stay compact at default text size")
        XCTAssertLessThan(chains.frame.maxY, miner.frame.minY)
        let poolStats = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'fleetPools.stats.'")).firstMatch
        XCTAssertFalse(poolStats.exists)
        capture("Compact home initial viewport", app)
        miner.tap()
        let tuning = app.buttons["detail.quick.tuning"]
        reveal(tuning, app)
        XCTAssertTrue(tuning.isHittable)
        let settings = app.buttons["detail.settings"]
        reveal(settings, app)
        XCTAssertTrue(settings.isHittable)
        let poolsEdit = app.buttons["detail.pools.edit"]
        XCTAssertTrue(poolsEdit.waitForExistence(timeout: 5))
        let detailBest = app.descendants(matching: .any)["detail.bestShare.ever"]
        let detailSessionBest = app.descendants(matching: .any)["detail.bestShare.session"]
        XCTAssertTrue(detailBest.waitForExistence(timeout: 5))
        XCTAssertTrue(detailSessionBest.exists)
        XCTAssertTrue(detailBest.label.contains("18.40G"), detailBest.label)
        XCTAssertTrue(detailSessionBest.label.contains("9.20M"), detailSessionBest.label)
        assertQuickActionsPresent(app)
        verifyQuickControlLayout(app)
        verifyQuickActionLayout(app)
        let power = app.descendants(matching: .any)["detail.metric.Power"]
        let voltage = app.descendants(matching: .any)["detail.metric.Input voltage"]
        reveal(power, app)
        XCTAssertTrue(power.isHittable)
        XCTAssertTrue(voltage.isHittable)
        let accountRows = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'fleetPools.stats.'")).firstMatch
        XCTAssertFalse(accountRows.exists, "Account information must stay collapsed until requested")
        capture("Compact miner quick controls", app)
    }

    func testExactNumericBestShareRendersAs392MThroughNativeTransport() throws {
        let server = try LoopbackMinerServer()
        let formatJSON = #"{"ASICModel":"BM1370","hostname":"format-check","hashRate":1234,"power":20,"# +
            #""temp":51,"bestDiff":392000000,"bestSessionDiff":1234000,"# +
            #""uptimeSeconds":245820,"version":"2.13.0"}"#
        server.setInfoResponse(status: 200, json: formatJSON)
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["dashboard.addMiner"].tap()
        let input = app.textFields["addMiner.address"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(address + "\n")
        let best = app.descendants(matching: .any).matching(identifier: "bestShare.ever").firstMatch
        reveal(best, app)
        XCTAssertTrue(best.label.contains("392.00M"), best.label)
        XCTAssertFalse(best.label.contains("392000000"), "Visible best difficulty should use SI notation")
        let session = app.descendants(matching: .any).matching(identifier: "bestShare.session").firstMatch
        XCTAssertTrue(session.label.contains("1.23M"), session.label)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, app)
        XCTAssertTrue(miner.label.contains("BM1370"), miner.label)
        XCTAssertFalse(miner.label.contains("Uptime"), "Fleet cards should not show uptime: \(miner.label)")
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        let detailUptime = app.descendants(matching: .any)["detail.uptime"]
        XCTAssertTrue(detailUptime.waitForExistence(timeout: 5))
        XCTAssertTrue(detailUptime.label.contains("Uptime"), detailUptime.label)
        let freshness = app.descendants(matching: .any)["detail.sampleAge"]
        XCTAssertTrue(freshness.waitForExistence(timeout: 5))
        XCTAssertTrue(freshness.label.contains("Updated"), freshness.label)
        XCTAssertFalse(freshness.label.contains("Sampled"), "A connected reading must not be called a sample")
        XCTAssertTrue(server.writes.isEmpty)
        XCTAssertTrue(server.journal.contains { $0.method == "GET" && $0.path == "/api/system/info" })
        capture("Exact best share abbreviation", app)
    }

    func testAddMinerOffersExplicitWiFiDiscoveryWithoutHidingManualEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }

        let connectButton = app.buttons["dashboard.connectFirstMiner"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 10))
        connectButton.tap()

        XCTAssertTrue(app.navigationBars["Add a miner"].waitForExistence(timeout: 5))
        let start = app.descendants(matching: .any)["addMiner.discoveryStart"]
        let discoveryScreen = XCTAttachment(screenshot: app.screenshot())
        discoveryScreen.name = "Add Miner discovery screen"
        discoveryScreen.lifetime = .keepAlways
        self.add(discoveryScreen)
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addMiner.discoveryCancel"].exists,
                       "Discovery must be opt-in rather than an automatic network scan")
        XCTAssertTrue(app.textFields["addMiner.name"].exists)
        XCTAssertTrue(app.textFields["addMiner.address"].exists)
        XCTAssertTrue(app.buttons["addMiner.save"].exists)

        start.tap()
        let cancel = app.descendants(matching: .any)["addMiner.discoveryCancel"]
        let empty = app.descendants(matching: .any)["addMiner.discoveryEmpty"]
        let resultsTitle = app.staticTexts["Compatible miners"]
        let result = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'addMiner.discoveryResult.'")
        ).firstMatch

        // The simulator may have no local Wi-Fi interface, while a real device may
        // finish with no results or discover a compatible miner. Accept each honest
        // terminal state, but always require the manual form to remain available.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && !cancel.exists && !empty.exists && !resultsTitle.exists && !result.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(cancel.exists || empty.exists || resultsTitle.exists || result.exists,
                      "Discovery should expose progress or an honest terminal state")
        XCTAssertTrue(app.textFields["addMiner.address"].exists)
        XCTAssertTrue(app.buttons["addMiner.save"].exists)
        capture("Explicit Wi-Fi discovery with manual fallback", app)
    }

    func testSearchRevealsOnPullDownAndFiltersMiners() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        let search = app.textFields["dashboard.search"]
        XCTAssertFalse(search.isHittable, "Search should not occupy the initial dashboard")
        app.swipeDown()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable, "Pulling back above the content should reveal search")
        let bar = app.navigationBars["Hash Fleet"]
        XCTAssertGreaterThanOrEqual(search.frame.minY, bar.frame.minY)
        XCTAssertLessThanOrEqual(search.frame.maxY, bar.frame.maxY + 1,
                                 "Search belongs in the main bar, not the content")
        app.swipeUp()
        XCTAssertFalse(search.isHittable, "Scrolling away should restore the title")
        for _ in 0..<4 {
            if search.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("Office")
        let miners = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'"))
        let filterDeadline = Date().addingTimeInterval(5)
        while Date() < filterDeadline && miners.count != 1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(miners.count, 1)
        XCTAssertTrue(miners.firstMatch.label.contains("Office Gamma"))
        capture("Pull-down search filters native miner list", app)
    }

    func testFleetMenuStatusFooterStaysPinnedWhileNavigationScrolls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        let menuButton = app.buttons["dashboard.headerLogoButton"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 10))
        menuButton.tap()

        let footerStatus = app.staticTexts["Demo Fleet"]
        XCTAssertTrue(footerStatus.waitForExistence(timeout: 5))
        let initialFrame = footerStatus.frame
        XCTAssertGreaterThan(initialFrame.height, 0)

        app.swipeUp()
        app.swipeUp()

        XCTAssertTrue(footerStatus.exists)
        XCTAssertEqual(footerStatus.frame.minY, initialFrame.minY, accuracy: 1)
        XCTAssertEqual(footerStatus.frame.maxY, initialFrame.maxY, accuracy: 1)
        capture("Fleet menu status footer remains readable while scrolling", app)
    }

    func testFleetToolsAndMinerControlsAreExplicitlyDiscoverable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))

        let controls = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")
        ).firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        XCTAssertTrue(controls.label.contains("Controls"), controls.label)

        let tools = app.descendants(matching: .any)["dashboard.fleetTools"]
        XCTAssertTrue(tools.exists)
        let network = app.buttons["dashboard.tools.network"]
        reveal(network, app)
        XCTAssertTrue(network.isHittable)
        let energy = app.buttons["dashboard.tools.energy"]
        XCTAssertTrue(energy.exists)
        XCTAssertGreaterThan(network.frame.width, 300,
                             "Compact Fleet Tools actions should use one readable column")
        XCTAssertGreaterThan(energy.frame.minY, network.frame.maxY,
                             "Compact Fleet Tools actions should stack instead of forming two columns")
        XCTAssertEqual(energy.frame.minX, network.frame.minX, accuracy: 2)
        for identifier in [
            "dashboard.tools.network",
            "dashboard.tools.energy",
            "dashboard.tools.achievements",
            "dashboard.tools.reports",
            "dashboard.tools.backup"
        ] {
            let action = app.buttons[identifier]
            reveal(action, app)
            XCTAssertTrue(action.exists, "Missing visible Fleet Tools action: \(identifier)")
        }

        // Visiting the lower tools can leave Network behind the navigation bar.
        // XCUI may still call that offscreen row hittable, so return it to the
        // actual content viewport before tapping. Keep every route assertion.
        for _ in 0..<8 {
            let navigationBottom = app.navigationBars.firstMatch.frame.maxY
            if network.isHittable && network.frame.minY >= navigationBottom + 4 { break }
            app.swipeDown()
        }
        XCTAssertTrue(network.isHittable)
        XCTAssertGreaterThanOrEqual(network.frame.minY, app.navigationBars.firstMatch.frame.maxY + 4)
        network.tap()
        XCTAssertTrue(app.navigationBars["Network insights"].waitForExistence(timeout: 5))
        capture("Visible Fleet Tools and miner Controls", app)
    }

    func testPowerAndSupplyVoltageUseReportedUnitsAndMissingValues() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        for reportsVoltage in [true, false] {
            let fullJSON = #"{"ASICModel":"BM1370","hostname":"voltage-check","hashRate":1234,"power":20,"# +
                #""voltage":5150,"coreVoltage":1150}"#
            let partialJSON = #"{"ASICModel":"BM1370","hostname":"voltage-check","hashRate":1234,"power":20}"#
            server.setInfoResponse(status: 200, json: reportsVoltage ? fullJSON : partialJSON)
            app.launchArguments = ["--ui-testing"]
            app.launch()
            assertNoLegacyModeSelector(in: app)
            app.buttons["dashboard.addMiner"].tap()
            let input = app.textFields["addMiner.address"]
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            input.tap()
            input.typeText(address + "\n")
            let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
            XCTAssertTrue(miner.waitForExistence(timeout: 5))
            miner.tap()
            let power = app.descendants(matching: .any)["detail.metric.Power"]
            let voltage = app.descendants(matching: .any)["detail.metric.Input voltage"]
            // The responsive detail screen uses lazy metric grids. Reveal the row through the
            // real scroll path before asserting its public accessibility output.
            reveal(voltage, app)
            XCTAssertTrue(voltage.exists)
            XCTAssertTrue(power.exists)
            XCTAssertTrue(power.isHittable && voltage.isHittable)
            XCTAssertEqual(power.label, "Power, 20 W")
            XCTAssertEqual(voltage.label, reportsVoltage ? "Input voltage, 5.2 V" : "Input voltage, not reported")
            capture(reportsVoltage ? "Reported watts and supply volts" : "Missing voltage is not a zero reading", app)
            XCTAssertTrue(server.writes.isEmpty)
            app.terminate()
        }
    }

    func testGuidedSharedPoolSetupPreparesDraftWithoutChangingMiner() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        defer { app.terminate() }
        let workshopPredicate = NSPredicate(
            format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS 'Workshop Gamma'")
        let miner = app.buttons.matching(workshopPredicate).firstMatch
        reveal(miner, app)
        miner.tap()
        let pools = app.buttons["detail.pools.edit"]
        XCTAssertTrue(pools.waitForExistence(timeout: 5))
        pools.tap()
        XCTAssertTrue(app.navigationBars["Pools"].waitForExistence(timeout: 5))
        let guide = app.buttons["settings.pools.guidedSetup"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), app.debugDescription)
        reveal(guide, app)
        guide.tap()
        XCTAssertTrue(app.navigationBars["Guided Pool Setup"].waitForExistence(timeout: 5))
        let shared = app.segmentedControls.buttons["Shared"]
        reveal(shared, app)
        shared.tap()
        let ocean = app.buttons["miningSetup.usePreset.shared.ocean.btc"]
        reveal(ocean, app)
        let oceanNote = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'mine.ocean.xyz:3334'")).firstMatch
        XCTAssertTrue(oceanNote.exists)
        capture("Shared pool official endpoint and credentials", app)
        ocean.tap()
        XCTAssertTrue(app.navigationBars["Pools"].waitForExistence(timeout: 5))
        let host = app.textFields["Stratum server"]
        reveal(host, app)
        XCTAssertEqual(host.value as? String, "mine.ocean.xyz")
        XCTAssertEqual(app.textFields["Port"].value as? String, "3334")
        let review = app.buttons["settings.pools.review"]
        reveal(review, app)
        XCTAssertFalse(review.isEnabled, "Guided setup must retain explicit replacement and credential review")
        capture("Shared pool draft remains unsubmitted", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5),
                      "The direct Pools quick link returns to its miner without submitting the draft")
    }

    private func assertQuickActionsPresent(_ app: XCUIApplication) {
        for actionID in ["detail.quick.identify", "detail.quick.pause", "detail.quick.resume", "detail.quick.restart"] {
            let action = app.buttons[actionID]
            // The redesign puts the navigation tiles first, so the endpoint actions render just
            // below them and may need one scroll on a compact phone.
            reveal(action, app)
            XCTAssertTrue(action.exists, "Missing nearby miner action: \(actionID)")
        }
    }

    private func verifyQuickControlLayout(_ app: XCUIApplication) {
        reveal(app.buttons["detail.settings"], app)
        let tuningFrame = app.buttons["detail.quick.tuning"].frame
        let settingsFrame = app.buttons["detail.settings"].frame
        XCTAssertGreaterThan(tuningFrame.width, 300,
                             "Phone controls should use one readable column")
        XCTAssertGreaterThan(settingsFrame.minY, tuningFrame.maxY,
                             "Phone controls should stack instead of creating narrow tiles")
        XCTAssertEqual(settingsFrame.minX, tuningFrame.minX, accuracy: 2)
    }

    private func verifyQuickActionLayout(_ app: XCUIApplication) {
        let identify = app.buttons["detail.quick.identify"]
        let pause = app.buttons["detail.quick.pause"]
        let resume = app.buttons["detail.quick.resume"]
        let restart = app.buttons["detail.quick.restart"]
        XCTAssertTrue(identify.exists && pause.exists && resume.exists && restart.exists)

        XCTAssertEqual(pause.frame.minY, identify.frame.minY, accuracy: 4,
                       "Identify and Pause should share the first compact row")
        XCTAssertGreaterThan(pause.frame.minX, identify.frame.minX + 20,
                             "Pause should occupy the second compact column")
        XCTAssertGreaterThan(resume.frame.minY, identify.frame.maxY - 4,
                             "Resume should start the second compact row")
        XCTAssertEqual(restart.frame.minY, resume.frame.minY, accuracy: 4,
                       "Resume and Restart should share the second compact row")
        XCTAssertGreaterThan(restart.frame.minX, resume.frame.minX + 20,
                             "Restart should occupy the second compact column")
    }
}
