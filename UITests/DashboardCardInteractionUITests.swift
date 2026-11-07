import XCTest

/// Dashboard controls must remain independent of the details link and never send settings writes.
@MainActor
final class DashboardCardInteractionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

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
        app.launchArguments = ["--ui-testing", "--demo"]
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

    func testTuningSessionOpensFromControlsMenuAndShowsNumberedRails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        let controls = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")
        ).firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 10), app.debugDescription)
        reveal(controls, in: app)
        controls.tap()

        let session = fleetTuningSessionMenuItem(in: app)
        XCTAssertTrue(session.waitForExistence(timeout: 5), app.debugDescription)
        session.tap()

        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5), app.debugDescription)
        selectAdvancedTuningControls(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.screen"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.frequencyControl"].exists)
        let frequencyPlus10 = app.buttons["tuningSession.master.plus10"]
        XCTAssertTrue(frequencyPlus10.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(frequencyPlus10.isEnabled, "The demo's reported frequency should enable the stepped rail")
        let frequencyValue = app.descendants(matching: .any)["tuningSession.frequencyValue"]
        XCTAssertTrue(frequencyValue.exists)
        let initialFrequencyLabel = frequencyValue.label
        frequencyPlus10.tap()
        let stepped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", initialFrequencyLabel),
            object: frequencyValue
        )
        XCTAssertEqual(XCTWaiter.wait(for: [stepped], timeout: 5), .completed,
                       "The master +10 control should change the displayed frequency")
        let firstASICJump = app.buttons["tuningSession.jump.1"]
        reveal(firstASICJump, in: app)
        XCTAssertEqual(firstASICJump.label, "ASIC 1")
        let secondASICJump = app.buttons["tuningSession.jump.2"]
        reveal(secondASICJump, in: app)
        XCTAssertEqual(secondASICJump.label, "ASIC 2")
        secondASICJump.tap()
        XCTAssertTrue(app.staticTexts["tuningSession.asic.2.title"].waitForExistence(timeout: 5),
                      app.debugDescription)
        XCTAssertTrue(app.switches["tuningSession.riskAcknowledgement"].exists)
        XCTAssertFalse(app.textFields["tuningSession.frequency"].exists,
                       "The session uses stepped controls instead of numeric frequency entry")
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.asic.1.temperature"].exists,
                      "Each ASIC card must expose its chip temperature, even when the value is unknown")
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.asic.1.voltage"].exists,
                      "Each ASIC card must expose its core voltage, even when the value is unknown")
        let review = app.buttons["tuningSession.jump.apply"]
        XCTAssertTrue(review.waitForExistence(timeout: 5), app.debugDescription)
        review.tap()
        let payload = app.descendants(matching: .any)["tuningSession.payload"]
        XCTAssertTrue(payload.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(payload.label.contains("frequency"), payload.label)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.journal"].exists)
        XCTAssertTrue(app.staticTexts["Session opened"].exists)
        let apply = app.buttons["tuningSession.apply"]
        reveal(apply, in: app)
        XCTAssertFalse(apply.isEnabled, "Demo mode must show the one apply action without allowing a write")
        XCTAssertFalse(app.buttons["tuningSession.review"].exists)
        XCTAssertFalse(app.buttons["endpoint.send"].exists)
        capture("Scrollable numbered ASIC tuning session", app)
    }

    func testCockpitStagesEachDialTogetherAndRestoresWithoutWriting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        openCockpit(in: app)
        capture("Car-style frequency cockpit at phone width", app)
        let frequency = app.staticTexts["tuningSession.frequencyValue"]
        let voltage = app.staticTexts["tuningSession.voltageValue"]
        let initialFrequency = try numericReading(frequency)
        let initialVoltage = try numericReading(voltage)
        XCTAssertFalse(app.buttons["tuningSession.reset"].isEnabled)

        let frequencyStep = app.buttons["tuningSession.master.plus10"]
        reveal(frequencyStep, in: app)
        frequencyStep.tap()
        XCTAssertEqual(try numericReading(frequency), initialFrequency + 10)
        reviewCockpit(in: app)
        var fields = try cockpitPayload(in: app)
        XCTAssertEqual(Set(fields.keys), ["frequency"])
        XCTAssertEqual(fields["frequency"] as? Double, initialFrequency + 10)
        app.buttons["tuningSession.reset"].tap()
        XCTAssertTrue(app.staticTexts["tuningSession.payloadUnavailable"].exists)

        let voltageStep = app.buttons["tuningSession.voltage.plusCoarse"]
        reveal(voltageStep, in: app)
        XCTAssertGreaterThanOrEqual(voltageStep.frame.height, 44)
        voltageStep.tap()
        XCTAssertEqual(try numericReading(voltage), initialVoltage + 25)
        reveal(app.descendants(matching: .any)["tuningSession.voltage.dial"], in: app, requireHittable: false)
        capture("Core voltage gauge with staged 25 mV delta", app)
        reviewCockpit(in: app)
        fields = try cockpitPayload(in: app)
        XCTAssertEqual(Set(fields.keys), ["coreVoltage"])
        XCTAssertEqual(fields["coreVoltage"] as? Int, Int(initialVoltage + 25))

        reveal(frequencyStep, in: app)
        frequencyStep.tap()
        reviewCockpit(in: app)
        fields = try cockpitPayload(in: app)
        XCTAssertEqual(Set(fields.keys), ["frequency", "coreVoltage"])
        XCTAssertEqual(fields["frequency"] as? Double, initialFrequency + 10)
        XCTAssertEqual(fields["coreVoltage"] as? Int, Int(initialVoltage + 25))
        let apply = app.buttons["tuningSession.apply"]
        reveal(apply, in: app)
        XCTAssertFalse(apply.isEnabled, "Demo mode must not write even after both dials move")
        capture("Both dials staged in one exact JSON review", app)
        app.buttons["tuningSession.reset"].tap()
        XCTAssertTrue(app.staticTexts["tuningSession.payloadUnavailable"].exists)
        XCTAssertEqual(try numericReading(frequency), initialFrequency)
        XCTAssertEqual(try numericReading(voltage), initialVoltage)
        XCTAssertFalse(app.buttons["tuningSession.reset"].isEnabled)

        let dial = app.descendants(matching: .any)["tuningSession.master.dial"]
        reveal(dial, in: app, requireHittable: false)
        capture("Frequency dial positioned before rim drag", app)
        let start = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let end = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let dragEvidence = "DIAL_FRAME=\(dial.frame) APP_FRAME=\(app.frame) " +
            "DRAG_START=\(start.screenPoint) DRAG_END=\(end.screenPoint) BEFORE=\(initialFrequency)"
        print(dragEvidence)
        let coordinates = XCTAttachment(string: dragEvidence)
        coordinates.name = "Real rim drag coordinates before touch"
        coordinates.lifetime = .keepAlways
        add(coordinates)
        start.press(forDuration: 0.1, thenDragTo: end)
        let draggedFrequency = try numericReading(frequency)
        print("DIAL_DRAG_AFTER=\(draggedFrequency) BEFORE=\(initialFrequency)")
        XCTAssertNotEqual(draggedFrequency, initialFrequency, "Dragging the rim must stage a change")
        XCTAssertTrue(app.buttons["tuningSession.reset"].isEnabled)
        capture("Frequency needle follows a real rim drag", app)
    }

    func testCockpitConfirmsOneLoopbackWriteAndReportsReadbackMismatchHonestly() throws {
        for matches in [true, false] {
            let server = try LoopbackMinerServer()
            server.enableTuningWrites(readbackMatches: matches)
            let address = try server.start()
            let app = XCUIApplication()
            defer { app.terminate(); server.stop() }
            app.launchArguments = ["--ui-testing"]
            app.launch()
            addFixture(address, in: app)
            openCockpit(in: app, fromMinerDetail: true)
            let frequencyStep = app.buttons["tuningSession.master.plus10"]
            reveal(frequencyStep, in: app)
            frequencyStep.tap()
            let voltageStep = app.buttons["tuningSession.voltage.plusCoarse"]
            reveal(voltageStep, in: app)
            voltageStep.tap()
            XCTAssertTrue(server.writes.isEmpty, "Turning dials must never write")
            reviewCockpit(in: app)
            let risk = app.switches["tuningSession.riskAcknowledgement"]
            reveal(risk, in: app)
            if (risk.value as? String) != "1" {
                risk.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            XCTAssertEqual(risk.value as? String, "1", "The actual hardware-risk switch must be on before Apply")
            let apply = app.buttons["tuningSession.apply"]
            reveal(apply, in: app)
            XCTAssertTrue(apply.isEnabled)
            apply.tap()
            let confirmation = app.alerts["Apply tuning change?"]
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            XCTAssertTrue(server.writes.isEmpty, "Review must not write before explicit confirmation")
            confirmation.buttons["Cancel"].tap()
            XCTAssertTrue(server.writes.isEmpty)
            apply.tap()
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            confirmation.buttons["Apply"].tap()
            let outcome = app.staticTexts[matches ? "tuningSession.status" : "tuningSession.error"]
            XCTAssertTrue(outcome.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(server.writes.count, 1)
            let write = try XCTUnwrap(server.writes.first)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: write.body) as? [String: Int])
            XCTAssertEqual(fields, ["frequency": 510, "coreVoltage": 1175])
            let journal = server.journal
            let writeIndex = try XCTUnwrap(journal.firstIndex { $0.method == "PATCH" })
            XCTAssertTrue(journal[..<writeIndex].contains { $0.path == "/api/system/info" && $0.method == "GET" })
            XCTAssertTrue(journal.dropFirst(writeIndex + 1).contains {
                $0.path == "/api/system/info" && $0.method == "GET"
            }, "Verification must use an Info GET started after the actual PATCH")
            if matches {
                XCTAssertTrue(outcome.label.contains("Verified"), outcome.label)
                XCTAssertFalse(app.buttons["tuningSession.reset"].isEnabled)
                XCTAssertFalse(app.staticTexts["tuningSession.payload"].exists)
            } else {
                XCTAssertTrue(outcome.label.contains("do not match"), outcome.label)
                XCTAssertTrue(app.buttons["tuningSession.reset"].isEnabled, "An unverified draft must survive")
                XCTAssertTrue(app.staticTexts["tuningSession.payload"].exists)
                XCTAssertFalse(app.staticTexts["Tuning applied"].exists)
            }
            capture(matches ? "Actual app verified loopback tuning" : "Actual app retains unverified tuning draft", app)
            app.terminate()
            server.stop()
        }
    }

    func testCockpitMissingVoltageKeepsFrequencyUsableWithoutInventingPayloadFields() throws {
        let server = try LoopbackMinerServer()
        server.setInfoResponse(status: 200, json: #"{"hostname":"Partial","ASICModel":"BM1370","frequency":500}"#)
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        addFixture(address, in: app)
        openCockpit(in: app, fromMinerDetail: true)
        let frequencyStep = app.buttons["tuningSession.master.plus10"]
        reveal(frequencyStep, in: app)
        XCTAssertTrue(frequencyStep.isEnabled)
        frequencyStep.tap()
        XCTAssertTrue(app.staticTexts["tuningSession.voltageValue"].label.contains("—"))
        XCTAssertFalse(app.buttons["tuningSession.voltage.plusCoarse"].isEnabled)
        reviewCockpit(in: app)
        let fields = try cockpitPayload(in: app)
        XCTAssertEqual(Set(fields.keys), ["frequency"])
        XCTAssertEqual(fields["frequency"] as? Int, 510)
        XCTAssertTrue(server.writes.isEmpty)
        capture("Missing core voltage does not block frequency or invent voltage", app)
    }

    func testCockpitLargestTextKeepsBothDialsAndReviewReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        openCockpit(in: app)
        for identifier in ["tuningSession.master.plus10", "tuningSession.voltage.plus"] {
            let step = app.buttons[identifier]
            reveal(step, in: app)
            XCTAssertTrue(step.isEnabled)
            XCTAssertGreaterThanOrEqual(step.frame.width, 44)
            XCTAssertGreaterThanOrEqual(step.frame.height, 44)
            step.tap()
            captureSettled("Largest text \(identifier) stays reachable", app)
        }
        let deltaStrip = app.descendants(matching: .any)["tuningSession.deltaStrip"]
        reveal(deltaStrip, in: app, requireHittable: false)
        XCTAssertTrue(deltaStrip.label.contains("Frequency staged"), deltaStrip.label)
        XCTAssertTrue(deltaStrip.label.contains("Core voltage staged"), deltaStrip.label)
        XCTAssertTrue(deltaStrip.label.contains("+10 from"), deltaStrip.label)
        XCTAssertTrue(deltaStrip.label.contains("+5 from"), deltaStrip.label)
        captureSettled("Largest text summary shows both staged values and miner baselines", app)
        reviewCockpit(in: app)
        XCTAssertEqual(Set(try cockpitPayload(in: app).keys), ["frequency", "coreVoltage"])
        XCTAssertTrue(app.buttons["tuningSession.reset"].isEnabled)
        app.buttons["tuningSession.reset"].tap()
        XCTAssertTrue(app.staticTexts["tuningSession.payloadUnavailable"].exists)
    }

    func testCockpitControlsMenuSurvivesHTTPRefreshAndOpensTuner() throws {
        let server = try LoopbackMinerServer()
        server.setInfoResponse(status: 200, json: hashrateJSON(1000))
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        addFixture(address, in: app)
        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10), "The live dashboard must keep its trend visible")
        let controls = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")
        ).firstMatch
        reveal(controls, in: app)
        capture("Live Controls before first tap", app)
        controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let session = fleetTuningSessionMenuItem(in: app)
        XCTAssertTrue(session.waitForExistence(timeout: 5), "The first Controls tap must present its menu")
        capture("Live Controls menu before HTTP refresh", app)
        let requestCount = server.journal.filter { $0.method == "GET" && $0.path == "/api/system/info" }.count
        server.setInfoResponse(status: 200, json: hashrateJSON(1200))
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.journal.filter { $0.method == "GET" && $0.path == "/api/system/info" }.count > requestCount
                && miner.exists && miner.label.contains("1.20")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 75), .completed,
                       "The app must display a new loopback Info response while the menu is open")
        XCTAssertTrue(session.exists && session.isHittable, "An HTTP refresh must not dismiss the Controls menu")
        capture("Live Controls menu survives changed HTTP telemetry", app)
        session.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        XCTAssertTrue(server.writes.isEmpty, "Opening Controls and navigating must never write")
    }

}
