import XCTest

extension DashboardCardInteractionUITests {
    func testOverviewCardsAtLargestDynamicType() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion",
                               "--ui-test-dashboard-essentials", "--ui-test-light-appearance",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        reveal(chart, in: app)
        XCTAssertGreaterThan(chart.frame.height, 100)
        XCTAssertTrue(chart.label.localizedCaseInsensitiveContains("hashrate"))
        XCTAssertTrue((chart.value as? String ?? "").contains("Last minute"))
        capture("Overview chart at largest Dynamic Type", app)

        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 5))
        let id = String(miner.identifier.dropFirst("dashboard.miner.".count))
        let rate = app.descendants(matching: .any).matching(identifier: "dashboard.hashrateRow.\(id)").firstMatch
        reveal(rate, in: app, requireHittable: false)
        for reading in ["Hashrate", "Temperature", "degrees Celsius", "Power", "watts", "Fan speed", "percent"] {
            XCTAssertTrue(miner.label.contains(reading), "Missing \(reading) in \(miner.label)")
        }
        let controls = app.buttons["dashboard.card.settings.\(id)"]
        let expand = app.buttons["dashboard.card.expand.\(id)"]
        reveal(controls, in: app)
        XCTAssertGreaterThanOrEqual(controls.frame.height, 44)
        XCTAssertGreaterThanOrEqual(controls.frame.width, 44)
        XCTAssertGreaterThanOrEqual(controls.frame.minY, expand.frame.maxY, "Large-text controls must stack")
        XCTAssertTrue(controls.label.hasPrefix("Controls for"))
        capture("Miner card actions at largest Dynamic Type", app)
    }

    func testOverviewCardAccessibilityAuditInBothAppearances() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        defer { app.terminate() }
        for light in [true, false] {
            app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion"]
                + (light ? ["--ui-test-light-appearance"] : ["--ui-test-dashboard-essentials"])
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["dashboard.historyChart"].firstMatch.waitForExistence(timeout: 10))
            let rangeID = light ? "dashboard.historyRange.oneMinute" : "dashboard.historyRangeMenu"
            let historyID = light ? "dashboard.historyDisplay" : "dashboard.viewHistory"
            for id in ["dashboard.exitDemo", rangeID, historyID] {
                assertTapTarget(app.buttons[id])
            }
            try auditOverview(app)
            let controls = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")).firstMatch
            reveal(controls, in: app)
            assertTapTarget(controls)
            let id = String(controls.identifier.dropFirst("dashboard.card.settings.".count))
            assertTapTarget(app.buttons["dashboard.card.expand.\(id)"])
            capture("Overview miner readings and controls - \(light ? "light" : "dark")", app)
            try auditOverview(app)
            app.terminate()
        }
    }

    func testHashrateReservesItsOwnRowAtZeroAndWideReadings() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        defer { server.stop() }
        var heights: [CGFloat] = []
        for rate in [0, 1250, 1234567] {
            server.setInfoResponse(status: 200, json: hashrateJSON(rate))
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing"]
            app.launch()
            addFixture(address, in: app)
            let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
            // This HTTP-only fixture rejects the live socket asynchronously. Compare
            // identical content states, not a card before vs after its error row appears.
            let fallback = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS 'Live monitoring unavailable'"), object: miner)
            XCTAssertEqual(XCTWaiter.wait(for: [fallback], timeout: 10), .completed)
            reveal(miner, in: app)
            XCTAssertTrue(miner.label.contains("Best reported share difficulty"), miner.label)
            let id = String(miner.identifier.dropFirst("dashboard.miner.".count))
            let reading = app.descendants(matching: .any).matching(identifier: "dashboard.hashrateRow.\(id)")
            let best = app.descendants(matching: .any).matching(identifier: "dashboard.bestRow.\(id)")
            XCTAssertGreaterThan(reading.count, 0)
            XCTAssertGreaterThan(best.count, 0)
            // Capture one immutable AX tree. Querying each live element separately can mix
            // coordinate systems while the scroll view is still decelerating.
            let tree = try app.snapshot()
            func bounds(_ node: any XCUIElementSnapshot, identifier: String) -> CGRect {
                let own = node.identifier == identifier ? node.frame : CGRect.null
                return node.children.reduce(own) { $0.union(bounds($1, identifier: identifier)) }
            }
            let readingFrame = bounds(tree, identifier: "dashboard.hashrateRow.\(id)")
            let bestFrame = bounds(tree, identifier: "dashboard.bestRow.\(id)")
            XCTAssertFalse(readingFrame.isNull || bestFrame.isNull)
            XCTAssertGreaterThanOrEqual(bestFrame.minY, readingFrame.maxY,
                                        "Best must always be below the full-width hashrate row")
            // SF Symbols have a small optical inset within the left-aligned label.
            XCTAssertEqual(readingFrame.minX, bestFrame.minX, accuracy: 2)
            heights.append(bounds(tree, identifier: miner.identifier).height)
            capture("Gamma hashrate \(rate) keeps Best below", app)
            app.terminate()
        }
        XCTAssertEqual(heights.min() ?? 0, heights.max() ?? 1, accuracy: 1,
                       "Changing number width must not switch the card's row layout")
        XCTAssertTrue(server.writes.isEmpty)
    }

    func testIndividualCardCollapsesAndExpandsWithoutOpeningDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        let miners = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'"))
        let miner = miners.firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 5))
        let minerID = String(miner.identifier.dropFirst("dashboard.miner.".count))
        let expansion = app.buttons["dashboard.card.expand.\(minerID)"]
        let settings = app.buttons["dashboard.card.settings.\(minerID)"]
        reveal(expansion, in: app)
        XCTAssertEqual(expansion.value as? String, "Expanded")
        XCTAssertGreaterThanOrEqual(expansion.frame.width, 44)
        XCTAssertGreaterThanOrEqual(expansion.frame.height, 44)
        XCTAssertGreaterThanOrEqual(settings.frame.width, 44)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        XCTAssertFalse(expansion.frame.intersects(miner.frame),
                       "Expansion must be a sibling, not an overlapping details target")
        XCTAssertFalse(settings.frame.intersects(miner.frame), "Settings must be separate from the details target")
        let expandedHeight = miner.frame.height
        XCTAssertTrue(miner.label.contains("Temperature"), miner.label)
        XCTAssertTrue(miner.label.contains("Power"), miner.label)
        expansion.tap()
        waitForValue("Collapsed", on: expansion)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["detail.minerTitle"].exists)
        XCTAssertFalse(miner.label.contains("Temperature"), miner.label)
        XCTAssertTrue(miner.label.contains("Sample"), miner.label)
        XCTAssertFalse(miner.label.contains("Simulated reading"), "Per-miner freshness belongs in the dashboard hero")
        XCTAssertTrue(miner.label.contains("Power"), miner.label)
        XCTAssertTrue(miner.label.contains("Best reported share difficulty"), miner.label)
        XCTAssertTrue(miner.label.contains("H/s"), miner.label)
        XCTAssertLessThan(miner.frame.height, expandedHeight)
        XCTAssertEqual(Set(miners.allElementsBoundByIndex.map(\.identifier)).count, miners.count,
                       "Only navigation targets may carry dashboard.miner.UUID")
        let expandPrefix = "identifier BEGINSWITH 'dashboard.card.expand.' AND identifier != %@"
        let otherExpansions = app.buttons.matching(NSPredicate(format: expandPrefix, expansion.identifier))
        for other in otherExpansions.allElementsBoundByIndex {
            XCTAssertEqual(other.value as? String, "Expanded", "Collapsing one miner must not collapse its neighbors")
        }
        capture("Collapsed miner retains vital readings and sibling controls", app)
        expansion.tap()
        waitForValue("Expanded", on: expansion)
        XCTAssertTrue(miner.label.contains("Temperature"), miner.label)
        XCTAssertTrue(miner.label.contains("Power"), miner.label)
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5),
                      "The original details link must still work")
    }

    func testMinerAddressOpensAsBrowserLinkFromMinerDetail() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()

        addFixture(address, in: app)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        miner.tap()
        let addressLink = app.buttons["detail.address"]
        reveal(addressLink, in: app)
        XCTAssertTrue(addressLink.isHittable)
        XCTAssertTrue(addressLink.label.contains("127.0.0.1"), addressLink.label)

        // The dashboard card remains a clean details target. The address link lives in miner detail
        // and hands the local miner dashboard URL to Safari.
        addressLink.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 5),
                      "Tapping a miner IP should open its web dashboard in Safari")
        app.activate()
    }

    func testNearbySettingsCategoriesOnlyNavigateAndNeverWrite() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        for (category, title) in [("cooling", "Cooling"), ("pools", "Pools")] {
            app.launchArguments = ["--ui-testing"]
            app.launch()
            assertNoLegacyModeSelector(in: app)
            addFixture(address, in: app)
            let settingsPredicate = NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")
            let settings = app.buttons.matching(settingsPredicate).firstMatch
            reveal(settings, in: app)
            settings.tap()
            let route = app.buttons["dashboard.card.settingsRoute.\(category)"]
            XCTAssertTrue(route.waitForExistence(timeout: 5), app.debugDescription)
            route.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5),
                          "The nearby menu must open the category directly")
            XCTAssertTrue(app.staticTexts["Review and confirm before sending to your miner."].exists)
            XCTAssertFalse(app.buttons["detail.quick.tuning"].exists, "A settings tap must not activate miner details")
            XCTAssertTrue(server.writes.isEmpty, "Opening \(title) must not send a hardware write")
            XCTAssertTrue(server.journal.contains { $0.method == "GET" && $0.path == "/api/system/info" })
            capture("Nearby \(title) opens the existing reviewed form", app)
            app.terminate()
        }
        XCTAssertTrue(server.writes.isEmpty)
    }

    func testIndividualMinerPoolsRouteDoesNotCrashInDemo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10), app.debugDescription)
        let settings = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")
        ).firstMatch
        reveal(settings, in: app)
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let pools = app.buttons["dashboard.card.settingsRoute.pools"]
        XCTAssertTrue(pools.waitForExistence(timeout: 5), app.debugDescription)
        pools.tap()

        XCTAssertTrue(app.navigationBars["Pools"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(
            app.staticTexts["Review and confirm before sending to your miner."]
                .waitForExistence(timeout: 5),
            app.debugDescription
        )
        XCTAssertFalse(app.buttons["detail.quick.tuning"].exists)
    }
}
