import XCTest

/// Native interaction coverage using demo data or the IPv4-loopback fixture only.
/// These tests stop at review/cancel and never confirm a miner write.
@MainActor
final class MinerCardInteractionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTelemetryCardsCollapseIndependentlyAndKeepPrimaryReadingsVisible() throws {
        let app = launchDemo()
        defer { app.terminate() }
        openFirstMiner(app)

        let tuningQuick = app.buttons["detail.quick.tuning"]
        let settingsQuick = app.buttons["detail.settings"]
        let poolsEdit = app.buttons["detail.pools.edit"]
        reveal(settingsQuick, app)
        XCTAssertTrue(tuningQuick.isHittable && settingsQuick.isHittable)
        XCTAssertEqual(tuningQuick.frame.minY, settingsQuick.frame.minY, accuracy: 1)
        XCTAssertGreaterThan(settingsQuick.frame.minX, tuningQuick.frame.maxX)
        reveal(poolsEdit, app)
        XCTAssertTrue(poolsEdit.isHittable)
        let power = element("detail.metric.Power", app)
        let voltage = element("detail.metric.Input voltage", app)
        reveal(power, app)
        XCTAssertTrue(power.isHittable && voltage.isHittable)
        XCTAssertEqual(power.frame.minY, voltage.frame.minY, accuracy: 1)

        let cooling = app.buttons["detail.coolingDisclosure"]
        reveal(cooling, app)
        XCTAssertEqual(cooling.value as? String, "Expanded")
        assertIndependentHeader(cooling, settings: app.buttons["detail.cooling.settings"])
        cooling.tap()
        waitForValue("Collapsed", on: cooling)
        XCTAssertFalse(element("detail.metric.Temperature", app).exists)
        XCTAssertTrue(app.buttons["detail.cooling.settings"].isHittable)

        let tuning = app.buttons["detail.tuningDisclosure"]
        reveal(tuning, app)
        XCTAssertEqual(tuning.value as? String, "Expanded", "Cooling must not fold unrelated cards.")
        tuning.tap()
        waitForValue("Collapsed", on: tuning)
        XCTAssertFalse(element("detail.metric.Frequency", app).exists)
        assertIndependentHeader(tuning, settings: app.buttons["detail.tuning.settings"])

        reveal(power, app, towardTop: true)
        XCTAssertTrue(power.isHittable && voltage.isHittable)
        reveal(tuningQuick, app, towardTop: true)
        XCTAssertTrue(tuningQuick.isHittable && settingsQuick.isHittable)
        reveal(element("detail.sampleAge", app), app, towardTop: true)
        XCTAssertTrue(element("detail.sampleAge", app).label.contains("Sampled"))

        reveal(cooling, app)
        cooling.tap()
        waitForValue("Expanded", on: cooling)
        reveal(element("detail.metric.Temperature", app), app)
        XCTAssertTrue(element("detail.metric.Temperature", app).isHittable)
        reveal(tuning, app)
        XCTAssertEqual(tuning.value as? String, "Collapsed")
        tuning.tap()
        waitForValue("Expanded", on: tuning)
        reveal(element("detail.metric.Frequency", app), app)
        XCTAssertTrue(element("detail.metric.Frequency", app).isHittable)
        capture("Expanded native telemetry cards", app)
    }

    func testCollapsedTuningCardOpensUnifiedSessionAndDemoWriteLock() throws {
        let app = launchDemo()
        defer { app.terminate() }
        openFirstMiner(app)
        let disclosure = app.buttons["detail.tuningDisclosure"]
        reveal(disclosure, app)
        disclosure.tap()
        waitForValue("Collapsed", on: disclosure)
        let settings = app.buttons["detail.tuning.settings"]
        assertIndependentHeader(disclosure, settings: settings)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        selectAdvancedTuningControls(in: app)
        let settingsTitle = app.descendants(matching: .any)["miner.navigationTitle"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsTitle.label.contains("Frequency & voltage"), settingsTitle.label)
        XCTAssertTrue(settingsTitle.label.contains("BTC"), settingsTitle.label)
        XCTAssertTrue(settingsTitle.label.contains("Little Supra"), settingsTitle.label)
        XCTAssertFalse(settingsTitle.label.contains("CKPool"), settingsTitle.label)
        XCTAssertFalse(app.navigationBars["Review before sending"].exists)

        let plus10 = app.buttons["tuningSession.master.plus10"]
        reveal(plus10, app)
        XCTAssertTrue(plus10.isEnabled)
        plus10.tap()
        let review = app.buttons["tuningSession.jump.apply"]
        XCTAssertTrue(review.waitForExistence(timeout: 5), app.debugDescription)
        review.tap()
        let payload = app.descendants(matching: .any)["tuningSession.payload"]
        XCTAssertTrue(payload.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(payload.label.contains("frequency"), payload.label)
        let risk = app.switches["tuningSession.riskAcknowledgement"]
        reveal(risk, app, towardTop: true)
        if risk.value as? String != "1" { toggle(risk) }
        let apply = app.buttons["tuningSession.apply"]
        reveal(apply, app)
        XCTAssertFalse(apply.isEnabled, "Demo routes must retain the existing no-write lock.")
        XCTAssertFalse(app.textFields["tuning.frequency"].exists)
        XCTAssertFalse(app.textViews["endpoint.json"].exists)
        capture("Nearby tuning route uses one inline guarded payload", app)
    }

    func testCoolingCardReviewKeepsFaultsAndFreshnessAndNeverWrites() throws {
        let server = try LoopbackMinerServer()
        let cardJSON = #"{"ASICModel":"BM1370","hostname":"card-fixture","hashRate":1234,"power":20,"# +
            #""voltage":5150,"temp":51,"vrTemp":48,"frequency":500,"coreVoltage":1150,"# +
            #""fanspeed":65,"fanrpm":4200,"autofanspeed":1,"temptarget":60,"# +
            #""power_fault":"Fixture supply fault","sharesAccepted":24,"sharesRejected":0}"#
        server.setInfoResponse(status: 200, json: cardJSON)
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 10))
        app.buttons["dashboard.addMiner"].tap()
        let input = app.textFields["addMiner.address"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(address + "\n")
        let addedMiner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")
        ).firstMatch
        XCTAssertTrue(addedMiner.waitForExistence(timeout: 10))
        reveal(addedMiner, app)
        tapVisible(addedMiner, app)
        XCTAssertTrue(app.buttons["detail.quick.tuning"].waitForExistence(timeout: 5))
        let cooling = app.buttons["detail.coolingDisclosure"]
        reveal(cooling, app)
        cooling.tap()
        waitForValue("Collapsed", on: cooling)
        let tuning = app.buttons["detail.tuningDisclosure"]
        reveal(tuning, app)
        tuning.tap()
        waitForValue("Collapsed", on: tuning)
        let faults = element("detail.reportedFaults", app)
        reveal(faults, app, towardTop: true)
        XCTAssertTrue(faults.isHittable, "Folding readings must never fold miner-reported faults.")
        let faultText = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'Fixture supply fault'")).firstMatch
        XCTAssertTrue(faultText.exists)
        XCTAssertTrue(element("detail.sampleAge", app).exists)

        assertRefreshFailureKeepsTelemetry(app: app, server: server)

        verifyStaleCoolingReviewLock(app: app, server: server)
        capture("Nearby cooling route remains guarded on stale telemetry", app)
    }

    func testCollapsedPoolAndIdentityCardsOpenTheirFormsWithoutExpanding() throws {
        for route in [
            (disclosure: "detail.poolsDisclosure", settings: "detail.pools.edit", title: "Pools"),
            (disclosure: "detail.identityDisclosure", settings: "detail.identity.settings", title: "General")
        ] {
            let app = launchDemo()
            defer { app.terminate() }
            openFirstMiner(app)
            let disclosure = app.buttons[route.disclosure]
            reveal(disclosure, app)
            XCTAssertEqual(disclosure.value as? String, "Collapsed")
            let settings = app.buttons[route.settings]
            XCTAssertEqual(app.buttons.matching(identifier: route.settings).count, 1)
            assertIndependentHeader(disclosure, settings: settings)
            let poolStats = app.buttons
                .matching(NSPredicate(format: "identifier BEGINSWITH 'fleetPools.stats.'")).firstMatch
            XCTAssertFalse(poolStats.exists)
            settings.tap()
            XCTAssertTrue(app.navigationBars[route.title].waitForExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars["Review before sending"].exists)
            if route.title == "Pools" {
                let review = app.buttons["settings.pools.review"]
                reveal(review, app)
                XCTAssertFalse(review.isEnabled, "Pool replacement still needs its existing acknowledgement.")
                let acknowledgement = app.switches["settings.pools.replacementAcknowledgement"]
                reveal(acknowledgement, app)
                acknowledgement.tap()
                XCTAssertEqual(acknowledgement.value as? String, "1")
                XCTAssertTrue(review.isEnabled, "Acknowledging the full replacement should make review reachable.")
                review.tap()
                XCTAssertTrue(app.navigationBars["Review before sending"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Cancel"].exists, "Review must offer a no-write cancellation path.")
                app.buttons["Cancel"].tap()
                XCTAssertTrue(app.navigationBars["Pools"].waitForExistence(timeout: 5))
            } else {
                XCTAssertTrue(app.textFields["Network hostname"].exists)
            }
            capture("Collapsed card direct route to \(route.title)", app)
        }
    }

    func testLargestDynamicTypeKeepsCardToggleAndSettingsSeparatelyReachable() throws {
        let app = launchDemo(extraArguments: ["-UIPreferredContentSizeCategoryName",
                                              "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        openFirstMiner(app)
        let cooling = app.buttons["detail.coolingDisclosure"]
        reveal(cooling, app)
        let settings = app.buttons["detail.cooling.settings"]
        assertIndependentHeader(cooling, settings: settings)
        XCTAssertGreaterThanOrEqual(settings.frame.width, 44)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        tapVisible(cooling, app)
        waitForValue("Collapsed", on: cooling)
        XCTAssertFalse(element("detail.metric.Temperature", app).exists)
        reveal(cooling, app, towardTop: true)
        tapVisible(cooling, app)
        waitForValue("Expanded", on: cooling)
        let temperature = element("detail.metric.Temperature", app)
        reveal(temperature, app)
        XCTAssertGreaterThan(temperature.frame.width, app.frame.width * 0.6,
                             "Accessibility text sizes need a single metric column.")
        reveal(settings, app, towardTop: true)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Cooling"].waitForExistence(timeout: 5))
        capture("Largest Dynamic Type independent card settings", app)
    }
}
