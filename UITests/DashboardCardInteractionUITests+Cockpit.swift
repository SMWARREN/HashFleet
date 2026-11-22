import XCTest

extension DashboardCardInteractionUITests {
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
