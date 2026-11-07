import XCTest

/// Installed-phone-sized acceptance using synthetic demo data only.
/// Selecting or staging a value never sends a request to a miner.
@MainActor
final class PhoneTuningAndTelemetryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRightMenuKeepsSettingsAndAboutWithoutFeatureTour() throws {
        let app = launchDemo()
        defer { app.terminate() }
        let menu = app.buttons["dashboard.settingsMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        XCTAssertTrue(app.buttons["dashboard.openSettings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.openAbout"].exists)
        XCTAssertFalse(app.buttons["dashboard.featureTour"].exists)
        XCTAssertFalse(app.buttons["Feature tour"].exists)
        capture("Right menu without Feature tour", app)
        app.buttons["dashboard.openSettings"].tap()
        XCTAssertTrue(app.navigationBars["App settings"].waitForExistence(timeout: 5))
    }

    func testEasyDirectFrequencyAndAdvancedUseTheSameGuardedDraft() throws {
        let app = launchDemo()
        defer { app.terminate() }
        openTuner(in: app)
        let modes = app.segmentedControls["tuningSession.controlMode"]
        XCTAssertTrue(modes.buttons["Easy"].isSelected)
        XCTAssertFalse(app.buttons["tuningSession.master.plus10"].exists)
        let value = app.staticTexts["tuningSession.frequencyValue"]
        let configured = try numericValue(value)
        XCTAssertTrue(app.textFields["tuningSession.voltage.customInput"].isHittable)
        XCTAssertFalse(app.buttons["tuningSession.master.dropdown"].exists)
        XCTAssertFalse(app.buttons["tuningSession.master.customUse"].exists)
        capture("Direct frequency and voltage together", app)

        replaceCustomFrequency("65536", in: app)
        finishFleetTuningInput(prefix: "tuningSession.master", in: app)
        let error = app.staticTexts["tuningSession.master.customError"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(try numericValue(value), configured, "Invalid custom input must not change the draft")
        XCTAssertFalse(modes.isEnabled, "Invalid text must not be discarded by switching modes")
        replaceCustomFrequency("612.5", in: app)
        finishFleetTuningInput(prefix: "tuningSession.master", in: app)
        XCTAssertFalse(error.exists)
        XCTAssertEqual(try numericValue(value), 612.5)

        selectAdvancedTuningControls(in: app)
        XCTAssertEqual(try numericValue(value), 612.5)
        let plus10 = app.buttons["tuningSession.master.plus10"]
        revealFleetControl(plus10, in: app)
        plus10.tap()
        XCTAssertEqual(try numericValue(value), 622.5)
        capture("Advanced keeps the car-style tuner", app)
        revealFleetControl(modes, in: app)
        modes.buttons["Easy"].tap()
        XCTAssertEqual(try numericValue(value), 622.5)
        XCTAssertEqual(app.textFields["tuningSession.master.customInput"].value as? String, "622.5")
        app.buttons["tuningSession.reset"].tap()
        XCTAssertEqual(try numericValue(value), configured)
        replaceCustomFrequency("612.5", in: app)
        finishFleetTuningInput(prefix: "tuningSession.master", in: app)
        XCTAssertEqual(try numericValue(value), 612.5)

        app.buttons["tuningSession.jump.apply"].tap()
        let payload = app.staticTexts["tuningSession.payload"]
        XCTAssertTrue(payload.waitForExistence(timeout: 5), app.debugDescription)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.label.utf8)) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["frequency"])
        XCTAssertEqual(fields["frequency"] as? Double, 612.5)
        let apply = app.buttons["tuningSession.apply"]
        revealFleetControl(apply, in: app)
        XCTAssertFalse(apply.isEnabled, "Easy mode must retain the real demo write lock")
        capture("Easy mode retains exact guarded review", app)
    }

    func testEasyDirectVoltageAndAdvancedKeepAVoltageOnlyDraft() throws {
        let app = launchDemo()
        defer { app.terminate() }
        openTuner(in: app)
        let value = app.staticTexts["tuningSession.voltageValue"]
        XCTAssertTrue(app.textFields["tuningSession.voltage.customInput"].isHittable)
        let configured = try numericValue(value)
        let error = app.staticTexts["tuningSession.voltage.customError"]

        replaceCustomValue("1125.5", identifier: "tuningSession.voltage.customInput", in: app)
        finishFleetTuningInput(prefix: "tuningSession.voltage", in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(try numericValue(value), configured, "Fractional voltage must not be rounded or staged")
        XCTAssertFalse(app.segmentedControls["tuningSession.controlMode"].isEnabled)

        replaceCustomValue("1100", identifier: "tuningSession.voltage.customInput", in: app)
        finishFleetTuningInput(prefix: "tuningSession.voltage", in: app)
        XCTAssertFalse(error.exists)
        XCTAssertEqual(try numericValue(value), 1100)

        selectAdvancedTuningControls(in: app)
        XCTAssertEqual(try numericValue(value), 1100)
        let plus25 = app.buttons["tuningSession.voltage.plusCoarse"]
        revealFleetControl(plus25, in: app)
        XCTAssertEqual(plus25.label, "Increase Core voltage by 25 mV")
        plus25.tap()
        XCTAssertEqual(try numericValue(value), 1125)
        let modes = app.segmentedControls["tuningSession.controlMode"]
        revealFleetControl(modes, in: app)
        modes.buttons["Easy"].tap()
        XCTAssertEqual(try numericValue(value), 1125)

        XCTAssertEqual(app.textFields["tuningSession.voltage.customInput"].value as? String, "1125")
        XCTAssertFalse(app.buttons["tuningSession.voltage.dropdown"].exists)
        app.buttons["tuningSession.reset"].tap()
        XCTAssertEqual(try numericValue(value), configured)

        replaceCustomValue("1125", identifier: "tuningSession.voltage.customInput", in: app)
        finishFleetTuningInput(prefix: "tuningSession.voltage", in: app)
        app.buttons["tuningSession.jump.apply"].tap()
        let payload = app.staticTexts["tuningSession.payload"]
        XCTAssertTrue(payload.waitForExistence(timeout: 5), app.debugDescription)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.label.utf8)) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["coreVoltage"])
        XCTAssertEqual(fields["coreVoltage"] as? Int, 1125)
        let apply = app.buttons["tuningSession.apply"]
        revealFleetControl(apply, in: app)
        XCTAssertFalse(apply.isEnabled, "Voltage editing must retain the real Demo write lock")
        capture("Easy and Advanced retain exact voltage-only review", app)

        app.buttons["tuningSession.reset"].tap()
        XCTAssertTrue(app.staticTexts["tuningSession.payloadUnavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["tuningSession.payload"].exists)
    }

    func testEasyPairCommitsOnFocusChangeAndResetClearsInvalidText() throws {
        let app = launchDemo()
        defer { app.terminate() }
        openTuner(in: app)
        let frequency = app.staticTexts["tuningSession.frequencyValue"]
        let configured = try numericValue(frequency)
        replaceCustomFrequency("612.5", in: app)
        app.textFields["tuningSession.voltage.customInput"].tap()
        XCTAssertEqual(try numericValue(frequency), 612.5, "Moving straight to voltage commits frequency without Use value")
        finishFleetTuningInput(prefix: "tuningSession.voltage", in: app)
        XCTAssertFalse(app.staticTexts["tuningSession.changeSummary"].label.contains("Voltage"))
        replaceCustomValue("1125.5", identifier: "tuningSession.voltage.customInput", in: app)
        finishFleetTuningInput(prefix: "tuningSession.voltage", in: app)
        XCTAssertTrue(app.staticTexts["tuningSession.voltage.customError"].exists)
        app.buttons["tuningSession.reset"].tap()
        XCTAssertFalse(app.staticTexts["tuningSession.voltage.customError"].exists)
        XCTAssertEqual(try numericValue(frequency), configured)
        XCTAssertTrue(app.segmentedControls["tuningSession.controlMode"].isEnabled)
        XCTAssertFalse(app.staticTexts["tuningSession.changeSummary"].label.contains("→"))
        XCTAssertFalse(app.buttons["tuningSession.apply"].isEnabled)
        capture("Both direct inputs recover after reset", app)
    }

    func testPhoneASICChartShowsAnObservedSampleAndExplainsBuildingHistory() throws {
        let app = launchDemo(extra: ["--ui-test-asic-telemetry"])
        defer { app.terminate() }
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        revealFleetControl(miner, in: app)
        miner.tap()
        let disclosure = app.buttons["detail.asicTelemetry.disclosure"]
        revealFleetControl(disclosure, in: app)
        XCTAssertTrue(disclosure.exists)
        disclosure.tap()
        let domain = app.descendants(matching: .any)["detail.asicDomain.0.0"].firstMatch
        revealFleetControl(domain, in: app, requireHittable: false)
        XCTAssertTrue(domain.label.contains("building trend"), domain.label)
        XCTAssertGreaterThanOrEqual(domain.frame.height, 140)
        capture("Phone ASIC chart with first observed marker", app)
    }

    func testSettingsMenuRowsHaveVisibleGapsAndStillOpenTheirPages() throws {
        let app = launchDemo()
        defer { app.terminate() }
        assertSettingsMenuSpacingAndNavigation(in: app)
    }

    func testSettingsMenuRowsStaySeparatedAtAccessibilityTextSize() throws {
        let app = launchDemo(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        assertSettingsMenuSpacingAndNavigation(in: app)
    }

    private func assertSettingsMenuSpacingAndNavigation(in app: XCUIApplication) {
        app.buttons["dashboard.settingsMenu"].tap()
        app.buttons["dashboard.openSettings"].tap()
        XCTAssertTrue(app.navigationBars["App settings"].waitForExistence(timeout: 5))
        let widgets = app.buttons["monitoring.widgets"]
        let activity = app.buttons["monitoring.liveActivity"]
        revealFleetControl(activity, in: app)
        XCTAssertTrue(widgets.exists)
        XCTAssertTrue(activity.isHittable)
        capture("App settings gray menu rows and their spacing", app)
        let gap = activity.frame.minY - widgets.frame.maxY
        XCTAssertGreaterThanOrEqual(gap, 10,
            "Gray menu rows need real space outside the tappable rows, not a divider inside one joined surface")
        XCTAssertGreaterThanOrEqual(widgets.frame.height, 44)
        XCTAssertGreaterThanOrEqual(activity.frame.height, 44)
        revealFleetControl(widgets, in: app)
        widgets.tap()
        XCTAssertTrue(app.navigationBars["Widgets"].waitForExistence(timeout: 5))
    }

    private func launchDemo(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        return app
    }

    private func openTuner(in app: XCUIApplication) {
        let controls = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")).firstMatch
        revealFleetControl(controls, in: app)
        controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let session = fleetTuningSessionMenuItem(in: app)
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
    }

    private func replaceCustomFrequency(_ text: String, in app: XCUIApplication) {
        replaceCustomValue(text, identifier: "tuningSession.master.customInput", in: app)
    }

    private func replaceCustomValue(_ text: String, identifier: String, in app: XCUIApplication) {
        let prefix = String(identifier.dropLast(".customInput".count))
        replaceFleetTuningInput(text, prefix: prefix, in: app)
    }

    private func numericValue(_ element: XCUIElement) throws -> Double {
        let tokens = element.label.split(separator: " ").compactMap { Double($0) }
        return try XCTUnwrap(tokens.first, element.label)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
