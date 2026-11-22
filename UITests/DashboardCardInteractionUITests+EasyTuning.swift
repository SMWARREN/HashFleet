import XCTest

extension DashboardCardInteractionUITests {
    func testEasyFrequencySafetyAndApplyAreVisibleWithoutScrolling() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        openEasyTuner(in: app)
        XCTAssertTrue(app.segmentedControls["tuningSession.controlMode"].buttons["Easy"].isSelected)
        // Deliberately no scrolling in the tuner: these controls must share the initial viewport.
        let frequency = app.textFields["tuningSession.master.customInput"]
        let voltage = app.textFields["tuningSession.voltage.customInput"]
        for control in [frequency, voltage,
                        app.switches["tuningSession.riskAcknowledgement"],
                        app.buttons["tuningSession.apply"]] {
            XCTAssertTrue(control.waitForExistence(timeout: 5), control.description)
            XCTAssertTrue(control.isHittable, control.description)
            XCTAssertTrue(app.frame.contains(control.frame), "Must fit without scrolling: \(control)")
        }
        XCTAssertFalse(app.buttons["tuningSession.apply"].isEnabled, "Demo stays read-only")
        XCTAssertFalse(app.buttons["tuningSession.master.plus10"].exists)
        XCTAssertLessThan(frequency.frame.maxY, voltage.frame.minY, "Core voltage must be below Frequency")
        XCTAssertEqual(frequency.frame.minX, voltage.frame.minX, accuracy: 1, "Stacked fields must align")
        XCTAssertEqual(frequency.frame.width, voltage.frame.width, accuracy: 1, "Stacked fields must be equally wide")
        XCTAssertGreaterThanOrEqual(frequency.frame.height, 44)
        XCTAssertGreaterThanOrEqual(voltage.frame.height, 44)
        XCTAssertFalse(app.buttons["tuningSession.master.dropdown"].exists)
        XCTAssertFalse(app.buttons["tuningSession.voltage.dropdown"].exists)
        XCTAssertFalse(app.buttons["tuningSession.master.customUse"].exists)
        XCTAssertFalse(app.buttons["tuningSession.voltage.customUse"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuningSession.liveContext"].exists)
        capture("Easy Frequency above Core voltage, both visible without an arrow", app)
    }

    func testEasyFrequencyConfirmsOneFrequencyOnlyLoopbackWrite() throws {
        try exerciseEasyWrite(includeVoltage: false)
    }

    func testEasyTunerMovesBetweenKeypadsAndRestoresReadOnlyReview() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        openEasyTuner(in: app)

        let frequency = app.textFields["tuningSession.master.customInput"]
        let voltage = app.textFields["tuningSession.voltage.customInput"]
        let keyboard = app.keyboards.firstMatch
        let bar = app.navigationBars["Frequency & voltage"]
        revealFleetControl(frequency, in: app)
        frequency.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(bar.buttons["tuningSession.master.keyboardDone"].isHittable)
        XCTAssertLessThanOrEqual(frequency.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertFalse(app.buttons["tuningSession.apply"].exists, "The dock must not compete with the keypad")

        XCTAssertTrue(voltage.isHittable)
        voltage.tap()
        let done = bar.buttons["tuningSession.voltage.keyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(voltage.frame.maxY, keyboard.frame.minY + 1)
        capture("Easy Tuner keypad and one navigation Done", app)
        done.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        let apply = app.buttons["tuningSession.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertTrue(apply.isHittable)
        XCTAssertFalse(apply.isEnabled, "Dismissal must never loosen the demo write lock")
        capture("Easy Tuner review returns after Done", app)
    }

    func testEasyTunerKeepsEitherFocusedFieldAboveLandscapeKeypad() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        openEasyTuner(in: app)

        let bar = app.navigationBars["Frequency & voltage"]
        for (prefix, title) in [("tuningSession.master", "Frequency"), ("tuningSession.voltage", "Core voltage")] {
            let field = app.textFields["\(prefix).customInput"]
            revealFleetControl(field, in: app)
            field.tap()
            let keyboard = app.keyboards.firstMatch
            let done = bar.buttons["\(prefix).keyboardDone"]
            XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            capture("\(title) stays above its landscape keypad", app)
            XCTAssertGreaterThanOrEqual(field.frame.minY + 1, bar.frame.maxY)
            XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY + 1)
            XCTAssertTrue(field.isHittable)
            XCTAssertTrue(done.isHittable)
            done.tap()
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        }
        let apply = app.buttons["tuningSession.apply"]
        revealFleetControl(apply, in: app)
        XCTAssertFalse(apply.isEnabled, "Dismissal must never loosen the demo write lock")
    }

    func testEasyPairConfirmsOneCombinedLoopbackWriteAndRejectsInvalidInput() throws {
        try exerciseEasyWrite(includeVoltage: true)
    }

    private func exerciseEasyWrite(includeVoltage: Bool) throws {
        XCUIDevice.shared.orientation = .portrait
        let server = try LoopbackMinerServer()
        server.enableTuningWrites()
        server.setASICResponse(status: 200, json:
            #"{"ASICModel":"BM1370","defaultFrequency":500,"defaultVoltage":1150,"frequencyOptions":[500,510],"voltageOptions":[1100,1150]}"#)
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        addFixture(address, in: app)
        openEasyTuner(in: app)
        replaceFleetTuningInput("510", prefix: "tuningSession.master", in: app)
        finishFleetTuningInput(prefix: "tuningSession.master", in: app)
        XCTAssertTrue(server.writes.isEmpty, "Editing is draft-only")
        let summary = app.staticTexts["tuningSession.changeSummary"]
        XCTAssertTrue(summary.label.contains("500 MHz → 510 MHz"), summary.label)
        XCTAssertFalse(summary.label.contains("Voltage"), "Untouched voltage must not be staged")
        let risk = app.switches["tuningSession.riskAcknowledgement"]
        let apply = app.buttons["tuningSession.apply"]
        XCTAssertTrue(risk.isHittable)
        XCTAssertTrue(apply.isHittable)
        XCTAssertEqual(risk.value as? String, "0")
        XCTAssertFalse(apply.isEnabled, "Explicit risk acknowledgement is still required")
        risk.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(apply.isEnabled)
        if includeVoltage {
            replaceFleetTuningInput("1125.5", prefix: "tuningSession.voltage", in: app)
            finishFleetTuningInput(prefix: "tuningSession.voltage", in: app)
            XCTAssertTrue(app.staticTexts["tuningSession.voltage.customError"].exists)
            XCTAssertFalse(apply.isEnabled, "Invalid voltage must block an already acknowledged frequency draft")
            XCTAssertFalse(app.segmentedControls["tuningSession.controlMode"].isEnabled)
            XCTAssertTrue(server.writes.isEmpty)
            replaceFleetTuningInput("1100", prefix: "tuningSession.voltage", in: app)
            finishFleetTuningInput(prefix: "tuningSession.voltage", in: app)
            XCTAssertFalse(app.staticTexts["tuningSession.voltage.customError"].exists)
            XCTAssertTrue(summary.label.contains("Voltage:"), summary.label)
            XCTAssertTrue(apply.isEnabled)
        }
        apply.tap()
        let confirmation = app.alerts["Apply tuning change?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(server.writes.isEmpty, "Opening confirmation never sends settings")
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(server.writes.isEmpty)
        XCTAssertTrue(apply.isHittable)
        apply.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Apply"].tap()
        let outcome = app.staticTexts["tuningSession.status"]
        XCTAssertTrue(outcome.waitForExistence(timeout: 10))
        XCTAssertTrue(outcome.label.contains("Verified"), outcome.label)
        XCTAssertEqual(server.writes.count, 1)
        let write = try XCTUnwrap(server.writes.first)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: write.body) as? [String: Int])
        XCTAssertEqual(fields, includeVoltage ? ["frequency": 510, "coreVoltage": 1100] : ["frequency": 510])
        let index = try XCTUnwrap(server.journal.firstIndex { $0.method == "PATCH" })
        XCTAssertTrue(server.journal.dropFirst(index + 1).contains { $0.method == "GET" && $0.path == "/api/system/info" })
        XCTAssertFalse(apply.isEnabled, "A verified change leaves no second pending write")
        capture("Easy frequency applied once and verified with no trip through diagnostics", app)
    }

    func testEasyLargeTextKeepsSafetyAndApplyAdjacentBeforeTechnicalDetails() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        openEasyTuner(in: app)
        let frequency = app.textFields["tuningSession.master.customInput"]
        let voltage = app.textFields["tuningSession.voltage.customInput"]
        revealFleetControl(frequency, in: app)
        XCTAssertTrue(frequency.isHittable)
        revealFleetControl(voltage, in: app)
        XCTAssertTrue(voltage.isHittable)
        XCTAssertGreaterThan(voltage.frame.minY, frequency.frame.minY, "Accessibility text keeps both fields available without a disclosure")
        let risk = app.switches["tuningSession.riskAcknowledgement"]
        let apply = app.buttons["tuningSession.apply"]
        // Large text uses the short inline review rather than a dock that consumes the viewport.
        revealFleetControl(risk, in: app)
        XCTAssertTrue(risk.isHittable)
        revealFleetControl(apply, in: app)
        XCTAssertTrue(apply.isHittable)
        XCTAssertGreaterThanOrEqual(apply.frame.height, 44)
        XCTAssertFalse(apply.isEnabled)
        XCTAssertFalse(app.buttons["tuningSession.voltage.dropdown"].exists)
        XCTAssertFalse(app.buttons["tuningSession.master.plus10"].exists)
        capture("Large-text Easy review stays before optional technical content", app)
    }

    private func openEasyTuner(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        let controls = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")).firstMatch
        revealFleetControl(controls, in: app)
        controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let tuner = fleetTuningSessionMenuItem(in: app)
        XCTAssertTrue(tuner.waitForExistence(timeout: 5))
        tuner.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
    }
}
