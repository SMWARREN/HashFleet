import XCTest

@MainActor
final class HashFleetUITests: XCTestCase {
    func testSplashAutomaticallyContinuesWithoutHoldingUpStartup() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--show-launch-splash"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].exists)
        let bitsy = app.descendants(matching: .any)["onboarding.bitsy"]
        XCTAssertTrue(bitsy.waitForExistence(timeout: 5), "Bitsy should greet users on the welcome screen.")
        XCTAssertTrue(bitsy.isHittable, "The character should be visible without scrolling.")
        XCTAssertTrue(bitsy.label.localizedCaseInsensitiveContains("Bitsy"), bitsy.label)
        recordScreenshot("Welcome screen with prominent Bitsy", app: app)
        XCTAssertFalse(app.descendants(matching: .any)["launch.splash"].exists)
    }

    func testDigiByteIconAndAdvancedPoolCoinLabels() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--pool-icon-demo"]
        app.launch()
        defer { app.terminate() }
        let miner = app.buttons["demo.pool.miner.6"]
        reveal(miner, in: app)
        XCTAssertTrue(miner.label.contains("DGB · SoloPool"), miner.label)
        miner.tap()
        XCTAssertTrue(app.staticTexts["SOLOPOOL"].waitForExistence(timeout: 5))
        recordScreenshot("DigiByte SoloPool active mock miner", app: app)
        let edit = app.buttons["detail.pools.edit"]
        reveal(edit, in: app)
        edit.tap()
        let configured = app.descendants(matching: .any)["settings.pools.configured.6"]
        reveal(configured, in: app)
        XCTAssertTrue(configured.label.contains("DGB"), configured.label)
        recordScreenshot("Advanced configured pools include DGB coin", app: app)
        let slot = app.buttons["settings.pools.slot"]
        reveal(slot, in: app)
        slot.tap()
        let dgbSlot = app.buttons["Slot 6 · DGB"]
        XCTAssertTrue(dgbSlot.waitForExistence(timeout: 5))
        dgbSlot.tap()
        let draft = app.descendants(matching: .any)["settings.pools.draftCoin"]
        reveal(draft, in: app)
        XCTAssertTrue(draft.label.contains("DGB"), draft.label)
        recordScreenshot("Advanced pool draft identifies DigiByte", app: app)
    }

    func testPoolIconDemoShowsAllMinersAndLetsEachChangePool() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }
        openFleetSettings(in: app)
        let entry = app.buttons["monitoring.poolIconDemo"]
        reveal(entry, in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let tickers = ["BTC", "BTC", "BCH", "BC2", "BCH2", "XEC", "DGB"]
        for index in tickers.indices {
            let card = app.buttons["demo.pool.miner.\(index)"]
            reveal(card, in: app)
            XCTAssertTrue(card.label.contains(tickers[index]), card.label)
        }
        app.swipeDown()
        recordScreenshot("All supported mock pools and coin icons", app: app)
        for index in tickers.indices {
            let card = app.buttons["demo.pool.miner.\(index)"]
            reveal(card, in: app)
            card.tap()
            let change = app.buttons["demo.pool.change"]
            XCTAssertTrue(change.waitForExistence(timeout: 5))
            let next = (index + 1) % tickers.count
            change.tap()
            let option = app.buttons["demo.pool.select.\(next)"]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            let title = app.descendants(matching: .any)["detail.minerTitle"]
            XCTAssertTrue(title.label.contains(tickers[next]), title.label)
            XCTAssertTrue(app.staticTexts[next == 0 ? "CKPOOL" : (next == 6 ? "SOLOPOOL" : "SOLOFURY")].exists)
            recordScreenshot("Mock miner \(index + 1) switched to \(tickers[next])", app: app)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(card, in: app)
            XCTAssertTrue(card.label.contains(tickers[next]), card.label)
        }
        let exit = app.buttons["dashboard.exitDemo"]
        reveal(exit, in: app)
        exit.tap()
        XCTAssertFalse(app.buttons["demo.pool.miner.0"].exists)
        XCTAssertFalse(exit.exists)
    }

    func testRotatingPoolShowsCurrentCoinAndProviderInsteadOfPrimary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-pool-rotation"]
        app.launch()
        defer { app.terminate() }
        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS 'Workshop Gamma'")
        ).firstMatch
        reveal(miner, in: app)
        let coin = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.coin.'")
        ).firstMatch
        XCTAssertTrue(coin.waitForExistence(timeout: 5))
        XCTAssertTrue(coin.label.contains("BCH"), coin.label)
        miner.tap()
        let title = app.descendants(matching: .any)["detail.minerTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("BCH"), title.label)
        XCTAssertTrue(app.staticTexts["SOLOFURY"].exists)
        XCTAssertFalse(app.staticTexts["CKPOOL"].exists)
        recordScreenshot("Rotated BCH SoloFury pool with primary still CKPool", app: app)
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    /// Run on physical iPhone as well as simulator. The device's smaller main-thread
    /// stack exposed an eager generic view construction overflow the simulator missed.
    func testEveryMinerDetailCanBeOpenedAndReopenedInBothModes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()
        defer { app.terminate() }
        let appearance = dashboardSettingsMenu(in: app)
        for mode in ["Dark", "Light"] {
            setDashboardAppearance(mode, in: app)
            XCTAssertEqual(appearance.value as? String, mode)
            for name in ["Little Supra", "Office Gamma", "Workshop Gamma", "Little Supra"] {
                let miner = minerButton(named: name, in: app)
                reveal(miner, in: app)
                waitForStableFrame(miner)
                miner.tap()
                XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
                XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].exists)
                let cooling = app.buttons["detail.coolingDisclosure"]
                reveal(cooling, in: app)
                XCTAssertEqual(cooling.value as? String, "Expanded")
                cooling.tap()
                XCTAssertEqual(cooling.value as? String, "Collapsed")
                cooling.tap()
                XCTAssertEqual(cooling.value as? String, "Expanded")
                XCTAssertEqual(app.state, .runningForeground)
                recordScreenshot("\(mode) stable \(name) detail", app: app)
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
            }
        }
    }

    func testDemoDashboardAndNativeNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'demo'")).firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Fleet demo dashboard"
        attachment.lifetime = .keepAlways
        add(attachment)
        openFleetAbout(in: app)
        XCTAssertTrue(app.navigationBars["About Hash Fleet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Hash Fleet account or analytics"].exists)
        returnToFleet(in: app)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].exists)
    }

    func testFleetArtworkAndCoolingReadingsOnRealDashboardNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()
        defer { app.terminate() }

        let fleetRate = app.descendants(matching: .any)["dashboard.fleetHashrate"]
        XCTAssertTrue(fleetRate.waitForExistence(timeout: 10))
        recordScreenshot("Fleet artwork on the live dashboard presentation", app: app)

        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")
        ).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(miner.isHittable, miner.debugDescription)
        miner.tap()

        let settings = app.buttons["detail.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        settings.tap()
        let cooling = app.buttons["settings.cooling"]
        XCTAssertTrue(cooling.waitForExistence(timeout: 5))
        cooling.tap()

        XCTAssertTrue(app.staticTexts["settings.cooling.temperatureReading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settings.cooling.fanSpeedReading"].exists)
        recordScreenshot("Cooling illustration and animated live reading values", app: app)
    }

    func testCoolingReadingsStackAtLargestDynamicType() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--demo", "--ui-testing",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        defer { app.terminate() }

        // Open the unified settings routes from the dashboard before opening miner details.
        assertNoLegacyModeSelector(in: app)

        let miner = minerButton(named: "Little Supra", in: app)
        reveal(miner, in: app)
        let tabTop = app.windows.firstMatch.frame.maxY
        let viewport = CGRect(x: 0, y: 170, width: app.frame.width, height: max(0, tabTop - 180))
        let visibleMinerCard = miner.frame.intersection(viewport)
        XCTAssertFalse(visibleMinerCard.isNull || visibleMinerCard.isEmpty)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visibleMinerCard.midX, dy: visibleMinerCard.midY))
            .tap()

        let settings = app.buttons["detail.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        settings.tap()

        let cooling = app.buttons["settings.cooling"]
        XCTAssertTrue(cooling.waitForExistence(timeout: 5), app.debugDescription)
        reveal(cooling, in: app)
        cooling.tap()

        let temperature = app.staticTexts["settings.cooling.temperatureReading"]
        let fanSpeed = app.staticTexts["settings.cooling.fanSpeedReading"]
        XCTAssertTrue(temperature.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(fanSpeed.exists)
        reveal(temperature, in: app)
        reveal(fanSpeed, in: app)
        XCTAssertTrue(temperature.isHittable, temperature.debugDescription)
        XCTAssertTrue(fanSpeed.isHittable, fanSpeed.debugDescription)
        XCTAssertGreaterThan(fanSpeed.frame.minY, temperature.frame.maxY,
                             "Cooling readings should stack vertically at Accessibility XXXL")
        recordScreenshot("Cooling readings at Accessibility XXXL", app: app)
    }

    func testDashboardKeepsCompactPoolContextWithoutFleetWatchPanel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["dashboard.fleetWatch"].exists)
        XCTAssertFalse(app.staticTexts["REPORTED MINING SETUP"].exists)

        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS 'Workshop Gamma'")
        ).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.poolContext.'")
        ).firstMatch.exists)
        let coinIcon = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.coin.'")
        ).firstMatch
        XCTAssertTrue(coinIcon.waitForExistence(timeout: 5))
        XCTAssertTrue(coinIcon.label.contains("BTC"), coinIcon.label)
        XCTAssertFalse(app.staticTexts["stratum.ckpool.org"].exists,
                       "The dashboard context identifies the pool without exposing its URL.")
    }

    func testUnifiedTuningWorkspaceShowsLiveContextStagesCombinedChangesAndRemembersAcknowledgment() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        let miner = minerButton(named: "Workshop Gamma", in: app)
        reveal(miner, in: app)
        waitForStableFrame(miner)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Workshop Gamma"].waitForExistence(timeout: 5))

        let tuning = app.buttons["detail.quick.tuning"]
        XCTAssertTrue(tuning.waitForExistence(timeout: 5))
        tuning.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        selectAdvancedTuningControls(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.screen"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.liveContext"].exists)
        XCTAssertTrue(app.staticTexts["Configured"].exists)
        XCTAssertTrue(app.staticTexts["Measured"].exists)
        XCTAssertTrue(app.staticTexts["ASIC errors"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.journal"].exists)
        XCTAssertTrue(app.staticTexts["Session opened"].exists)
        XCTAssertFalse(app.segmentedControls["settings.mode"].exists)

        XCTAssertFalse(app.textFields["tuning.frequency"].exists)
        XCTAssertFalse(app.textFields["tuning.coreVoltage"].exists)
        XCTAssertFalse(app.textFields["tuning.temperatureTarget"].exists)
        let coreTemperature = app.descendants(matching: .any)["tuningSession.asic.1.temperature"]
        reveal(coreTemperature, in: app)
        XCTAssertTrue(coreTemperature.exists)
        let coreVoltage = app.descendants(matching: .any)["tuningSession.asic.1.voltage"]
        reveal(coreVoltage, in: app)
        XCTAssertTrue(coreVoltage.exists)

        let plus10 = app.buttons["tuningSession.master.plus10"]
        let frequencyValue = app.descendants(matching: .any)["tuningSession.frequencyValue"]
        // Earlier reveals can leave the rail scrolled beneath the navigation bar, where the
        // element reports hittable but the tap lands on the bar. Scroll back until the whole
        // frequency card is clear of it.
        let navigationBar = app.navigationBars["Frequency & voltage"]
        for _ in 0..<8 where !(frequencyValue.exists && plus10.exists
            && frequencyValue.frame.minY > navigationBar.frame.maxY
            && plus10.frame.minY > navigationBar.frame.maxY) {
            app.swipeDown()
        }
        XCTAssertGreaterThan(plus10.frame.minY, navigationBar.frame.maxY, "+10 is hidden under the navigation bar")
        XCTAssertTrue(plus10.isEnabled)
        let initialFrequency = frequencyValue.label
        plus10.tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", initialFrequency),
            object: frequencyValue
        )
        let changeResult = XCTWaiter.wait(for: [changed], timeout: 5)
        XCTAssertEqual(
            changeResult,
            .completed,
            "The detail-route +10 control did not update the shared frequency. " +
                "Initial: \(initialFrequency), observed: \(frequencyValue.label), " +
                "plus10: \(plus10.debugDescription), hittable: \(plus10.isHittable), " +
                "value: \(frequencyValue.debugDescription)"
        )

        let review = app.buttons["tuningSession.jump.apply"]
        XCTAssertTrue(review.waitForExistence(timeout: 5), app.debugDescription)
        review.tap()
        let payload = app.descendants(matching: .any)["tuningSession.payload"]
        XCTAssertTrue(payload.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(payload.label.contains("frequency"), payload.label)
        let risk = app.switches["tuningSession.riskAcknowledgement"]
        reveal(risk, in: app)
        XCTAssertTrue(risk.isHittable)
        if risk.value as? String != "1" {
            risk.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        let apply = app.buttons["tuningSession.apply"]
        reveal(apply, in: app)
        XCTAssertFalse(apply.isEnabled, "Demo mode must keep the real write action locked")
        XCTAssertFalse(app.buttons["endpoint.send"].exists)

        app.navigationBars["Frequency & voltage"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.quick.tuning"].waitForExistence(timeout: 5))
        app.buttons["detail.quick.tuning"].tap()
        app.buttons["tuningSession.jump.apply"].tap()
        let rememberedRisk = app.switches["tuningSession.riskAcknowledgement"]
        reveal(rememberedRisk, in: app)
        XCTAssertTrue(rememberedRisk.exists)
        XCTAssertEqual(rememberedRisk.value as? String, "1", "The per-miner acknowledgement should be remembered.")
        XCTAssertTrue(app.staticTexts["tuningSession.payloadUnavailable"].exists,
                      "Reopening a clean session must not silently stage previously configured settings.")
        XCTAssertFalse(app.textViews["endpoint.json"].exists)
        recordScreenshot("Unified tuning session with inline payload and core readings", app: app)
    }

    func testCanonicalRequestJSONEditorIsDirectlyReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        let miner = minerButton(named: "Workshop Gamma", in: app)
        reveal(miner, in: app)
        miner.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        let advanced = app.buttons["settings.advanced"]
        reveal(advanced, in: app)
        advanced.tap()
        XCTAssertTrue(app.navigationBars["Tools & firmware"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Raw JSON editors"].exists)
        let custom = app.buttons["settings.customJSON"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.tap()
        XCTAssertTrue(app.navigationBars["Custom JSON"].waitForExistence(timeout: 5))
    }

    func testPoolStatsHubRendersOneCardPerSharedAccountWithConnectedMinerTags() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["dashboard.headerLogoButton"].waitForExistence(timeout: 10))
        app.buttons["dashboard.headerLogoButton"].tap()
        let network = app.staticTexts["Network insights"]
        XCTAssertTrue(network.waitForExistence(timeout: 5))
        network.tap()
        XCTAssertTrue(app.navigationBars["Network insights"].waitForExistence(timeout: 5))
        let hub = app.buttons["insights.poolHub"]
        reveal(hub, in: app)
        hub.tap()
        XCTAssertTrue(app.descendants(matching: .any)["poolHub.page"].waitForExistence(timeout: 5))

        let cards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'poolHub.card.'")
        )
        XCTAssertEqual(cards.count, 2, "Three miners sharing two accounts should render exactly two pool cards.")
        let connectedLabels = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "3 connected")
        )
        XCTAssertEqual(connectedLabels.count, 2)
        for minerName in ["Workshop Gamma", "Office Gamma", "Little Supra"] {
            let tags = app.descendants(matching: .any).matching(
                identifier: "poolHub.connectedMiner.\(minerName)"
            )
            XCTAssertEqual(tags.count, 2, "Each shared account should identify \(minerName) once.")
        }
        recordScreenshot("Deduplicated pool stats hub with connected miner tags", app: app)
    }

    func testLargestDynamicTypeKeepsMinerNavigationReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 10))
        recordScreenshot("Largest Dynamic Type fleet", app: app)
        app.buttons["dashboard.addMiner"].tap()
        XCTAssertTrue(app.navigationBars["Add a miner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        app.buttons["Cancel"].tap()
        let miner = minerButton(named: "Little Supra", in: app)
        reveal(miner, in: app)
        // At accessibility XXXL a card exceeds the viewport. XCTest's default
        // center tap can fall beneath the floating Settings tab despite a visible
        // card edge being hittable. Tap the visible content intersection instead.
        let tabTop = app.windows.firstMatch.frame.maxY
        let viewport = CGRect(x: 0, y: 170, width: app.frame.width, height: max(0, tabTop - 180))
        let visible = miner.frame.intersection(viewport)
        XCTAssertFalse(visible.isNull || visible.isEmpty)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
        XCTAssertTrue(app.navigationBars["Little Supra"].waitForExistence(timeout: 5))
        recordScreenshot("Largest Dynamic Type miner", app: app)
    }

    /// Preview all record kinds above the existing settings sheet. Dismissing a popup must
    /// restore the same inline controls rather than navigating away or closing App settings.
    func testNotificationCelebrationPreviewsPreserveAppSettingsAndSessionDoesNotToast() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 10))
        openFleetSettings(in: app)
        let notifications = app.buttons["monitoring.notifications"]
        reveal(notifications, in: app)
        XCTAssertTrue(notifications.waitForExistence(timeout: 5), "Expected the inline notification group")
        notifications.tap()
        XCTAssertTrue(app.navigationBars["App settings"].exists)
        XCTAssertFalse(app.navigationBars["Notifications"].exists, "Do not introduce a settings subpage")
        XCTAssertEqual(notifications.value as? String, "Expanded")

        let previews = [
            ("notifications.previewSessionBest", "SESSION BEST"),
            ("notifications.previewBestShare", "NEW HIGH SCORE"),
            ("notifications.previewBlock", "BLOCK FOUND")
        ]
        for (identifier, eyebrow) in previews {
            let preview = app.buttons[identifier]
            reveal(preview, in: app)
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            XCTAssertTrue(app.navigationBars["App settings"].exists)
            if eyebrow == "SESSION BEST" {
                recordScreenshot("Inline notifications and session preview within App settings", app: app)
            }
            preview.tap()
            let title = app.staticTexts["celebration.eyebrow"]
            XCTAssertTrue(title.waitForExistence(timeout: 8))
            XCTAssertEqual(title.label, eyebrow)
            XCTAssertTrue(app.staticTexts["celebration.headline"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["celebration.mascot"].exists,
                          "Every record should use the existing illustrated miner popup")
            XCTAssertTrue(app.buttons["celebration.viewMiner"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["inAppAlert.banner"].exists)
            XCTAssertEqual(app.buttons["celebration.disableSessionAlerts"].exists, eyebrow == "SESSION BEST",
                           "Only session popups may offer the session-only opt-out")
            if eyebrow == "SESSION BEST" {
                let disappeared = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"), object: title)
                disappeared.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 12), .completed,
                               "The session popup must not expire like a brief toast")
            }
            recordScreenshot("\(eyebrow) illustrated record popup over Settings", app: app)
            app.buttons["celebration.dismiss"].tap()
            XCTAssertTrue(app.navigationBars["App settings"].waitForExistence(timeout: 5))
            XCTAssertTrue(preview.isHittable, "Preserve the exact settings screen and scroll position")
            XCTAssertFalse(title.exists)
        }
        recordScreenshot("App settings retained after all record popups", app: app)
    }
}
