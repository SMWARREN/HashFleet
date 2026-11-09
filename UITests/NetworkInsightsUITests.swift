import XCTest

@MainActor
final class NetworkInsightsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDemoNetworkDataAndLookupRemainExplicitlyOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-fallback-notice"]
        app.launch()
        XCTAssertFalse(app.tabBars.buttons["Network"].exists)
        let best = app.descendants(matching: .any).matching(identifier: "bestShare.ever").firstMatch
        reveal(best, in: app)
        XCTAssertTrue(best.label.contains("18.40G"), best.label)
        app.swipeDown()
        app.swipeDown()
        let btc = app.descendants(matching: .any).matching(identifier: "dashboard.chain.BTC").firstMatch
        let bch = app.descendants(matching: .any).matching(identifier: "dashboard.chain.BCH").firstMatch
        reveal(btc, in: app)
        XCTAssertTrue(btc.label.contains("%"))
        reveal(bch, in: app)
        XCTAssertTrue(bch.label.contains("%"))
        record("Home best share and separate BTC BCH odds", app)
        let details = app.buttons["dashboard.networkDetails"]
        reveal(details, in: app)
        details.tap()
        XCTAssertTrue(app.buttons["insights.load"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Demo · not live"].exists)
        XCTAssertTrue(app.staticTexts["BTC · USD"].waitForExistence(timeout: 5))
        let fee = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'Fastest' AND label CONTAINS 'sat/vB'")).firstMatch
        reveal(fee, in: app)
        XCTAssertTrue(fee.label.contains("4"))
        let chance = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Chance over 30 days'")).firstMatch
        reveal(chance, in: app)
        XCTAssertTrue(chance.label.contains("%"))
        let fleetOutcome = app.descendants(matching: .any)
            .matching(identifier: "insights.soloOutcomeScope.fleet").firstMatch
        XCTAssertTrue(fleetOutcome.waitForExistence(timeout: 5), app.debugDescription)
        let outcomePager = app.collectionViews.firstMatch
        XCTAssertTrue(outcomePager.waitForExistence(timeout: 5), app.debugDescription)
        outcomePager.swipeLeft()
        XCTAssertTrue(app.staticTexts["Workshop Gamma"].waitForExistence(timeout: 5), app.debugDescription)
        let pool = app.staticTexts["CKPool · public pool"]
        reveal(pool, in: app)
        let poolNotice = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'Sample data' AND label CONTAINS 'not live'")).firstMatch
        XCTAssertTrue(poolNotice.exists)
        let lookup = app.buttons["insights.lookup"]
        reveal(lookup, in: app, towardTop: true)
        record("Network demo sources and pool", app)
        verifyDemoLookupIsLocal(app: app, lookup: lookup)
    }

    /// The demo pool lookup keeps every typed address local and refuses submission.
    private func verifyDemoLookupIsLocal(app: XCUIApplication, lookup: XCUIElement) {
        lookup.tap()
        let address = app.textFields["poolLookup.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("1BoatSLRHtKNngkdXEeobR76b53LETtpyT\n")
        let submit = app.buttons["poolLookup.submit"]
        reveal(submit, in: app)
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(app.staticTexts["Address lookup is disabled in demo. No address is sent."].exists)
    }

    func testLocalOnlyPreferenceDisablesPublicDataAndAccountLookup() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["dashboard.addMiner"].tap()
        let field = app.textFields["addMiner.address"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(address + "\n")
        let details = app.buttons["dashboard.networkDetails"]
        reveal(details, in: app)
        let offlineNote = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'External data is off'")).firstMatch
        XCTAssertTrue(offlineNote.exists)
        details.tap()
        XCTAssertFalse(app.buttons["insights.load"].isEnabled)
        XCTAssertFalse(app.staticTexts["BTC · USD"].exists)
        let lookup = app.buttons["insights.lookup"]
        reveal(lookup, in: app)
        lookup.tap()
        let input = app.textFields["poolLookup.address"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("1BoatSLRHtKNngkdXEeobR76b53LETtpyT\n")
        let submit = app.buttons["poolLookup.submit"]
        reveal(submit, in: app)
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(server.writes.isEmpty)
        record("Local-only preference blocks public lookups", app)
    }

    func testReadOnlyDiagnosticsExposeUnitsWithoutChangingSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        let miner = minerButton(named: "Workshop Gamma", in: app)
        reveal(miner, in: app)
        miner.tap()
        let diagnostics = app.descendants(matching: .any)
            .matching(identifier: "detail.diagnosticsDisclosure").firstMatch
        reveal(diagnostics, in: app)
        diagnostics.tap()
        let estimate = staticText(containing: "Continuous draw estimate", in: app)
        reveal(estimate, in: app)
        XCTAssertTrue(estimate.label.contains("Not an actual energy meter"))
        let mains = staticText(containing: "not mains current", in: app)
        reveal(mains, in: app)
        XCTAssertTrue(mains.exists)
        record("Read-only energy and DC-current diagnostics", app)
    }

    func testConfiguredPoolStatisticsAndSoloPoolPresetAreNativeAndReadOnly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        defer { app.terminate() }
        let miner = minerButton(named: "Workshop Gamma", in: app)
        reveal(miner, in: app)
        miner.tap()
        let pools = app.buttons["detail.poolsDisclosure"]
        reveal(pools, in: app)
        pools.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "detail.poolsDisclosure").count, 1,
                       "Expanded account content must not inherit the header identifier")
        XCTAssertTrue(app.buttons["detail.pools.edit"].exists)
        let primaryRole = app.staticTexts["minerPools.role.slot-0"]
        let fallbackRole = app.staticTexts["minerPools.role.slot-1"]
        // Pool rows are lazy and their sanitized browser destinations are exposed as native
        // buttons on iOS 26. Reveal the fallback row through the same scroll path a user uses.
        let primaryHost = app.buttons["minerPools.host.slot-0"]
        let fallbackHost = app.buttons["minerPools.host.slot-1"]
        reveal(fallbackHost, in: app)
        XCTAssertTrue(fallbackHost.exists)
        XCTAssertEqual(primaryRole.frame.minX, fallbackRole.frame.minX, accuracy: 1)
        XCTAssertEqual(primaryHost.frame.minX, fallbackHost.frame.minX, accuracy: 1)
        XCTAssertEqual(app.staticTexts["minerPools.activity.slot-0"].frame.minX,
                       app.staticTexts["minerPools.activity.slot-1"].frame.minX, accuracy: 1)
        XCTAssertLessThan(primaryRole.frame.height, 25)
        XCTAssertLessThan(fallbackRole.frame.height, 25)
        record("Aligned primary and fallback rows", app)
        let pool = app.buttons.matching(identifier: "fleetPools.stats.soloFury.bch").firstMatch
        reveal(pool, in: app)
        pool.tap()
        let rate = app.staticTexts["Account 1h rolling rate:"]
        reveal(rate, in: app)
        let dailyPredicate = NSPredicate(format: "label BEGINSWITH 'Account 24h rolling rate:'")
        let daily = app.staticTexts.matching(dailyPredicate).firstMatch
        reveal(daily, in: app)
        XCTAssertTrue(daily.label.contains("1.70TH/s"))
        XCTAssertTrue(app.staticTexts["Reported account workers: 2"].exists)
        XCTAssertTrue(staticText(containing: "Demo account sample", in: app).exists)
        XCTAssertFalse(staticText(containing: "1BoatSLRHtKNngkdXEeobR76b53LETtpyT", in: app).exists)
        record("Configured BCH fallback public account sample", app)
        verifySoloFuryPresetFlow(app: app, pools: pools)
    }

    /// Collapses the inline account section, then drafts and reviews the SoloFury BCH preset.
    private func verifySoloFuryPresetFlow(app: XCUIApplication, pools: XCUIElement) {
        // Collapse the inline account section before reaching local settings.
        reveal(pools, in: app, towardTop: true)
        pools.tap()
        XCTAssertEqual(pools.value as? String, "Collapsed")
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        app.buttons["settings.pools"].tap()
        let preset = app.buttons["settings.pools.preset"]
        reveal(preset, in: app)
        preset.tap()
        app.buttons["SoloFury · BCH"].tap()
        let add = app.buttons["settings.pools.addPreset"]
        reveal(add, in: app)
        XCTAssertTrue(add.isEnabled)
        add.tap()
        let draftNote = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'BCH draft prepared in slot 2'")).firstMatch
        XCTAssertTrue(draftNote.exists)
        let server = app.textFields["Stratum server"]
        reveal(server, in: app)
        XCTAssertEqual(server.value as? String, "bch.solofury.com")
        XCTAssertEqual(app.textFields["Port"].value as? String, "7070")
        let user = app.textFields["settings.pools.user"]
        XCTAssertTrue((user.value as? String ?? "").isEmpty || user.value as? String == user.placeholderValue)
        user.tap()
        user.typeText("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a.native-test\n")
        let review = app.buttons["settings.pools.review"]
        reveal(review, in: app)
        XCTAssertFalse(review.isEnabled)
        record("Native BCH preset still requires full replacement review", app)
    }

    func testReportedPoolHostOpensAsBrowserLink() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        let miner = minerButton(named: "Workshop Gamma", in: app)
        reveal(miner, in: app)
        miner.tap()

        let pools = app.buttons["detail.poolsDisclosure"]
        reveal(pools, in: app)
        pools.tap()
        // SwiftUI exposes Link as a native Button in the iOS 26 accessibility tree. The
        // control still performs the real Link handoff, so query the public identifier rather
        // than assuming XCTest's element type is AXLink.
        let host = app.buttons["minerPools.host.slot-0"]
        XCTAssertTrue(host.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(host.label.contains("stratum.ckpool.org"), host.label)
        reveal(host, in: app)
        XCTAssertTrue(host.isHittable)

        host.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 5),
                      "Tapping a reported pool URL should hand the sanitized web destination to Safari")
        app.activate()
    }

    private func minerButton(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS %@", name))
            .firstMatch
    }

    private func staticText(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<30 {
            if element.exists && element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.3 : 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.72 : 0.3))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Network acceptance hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        record("Unreachable network output", app)
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable output: \(element)")
    }

    private func record(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
