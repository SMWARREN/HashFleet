import XCTest

extension DashboardCardInteractionUITests {
    func testCoolingPreviewEssentialsAppliesInPlace() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openCooling(app, essentials: true)
        let commit = app.buttons["cooling.commit"]
        let automatic = app.buttons["cooling.mode.automatic"]
        let manual = app.buttons["cooling.mode.manual"]
        assertTapTarget(automatic)
        assertTapTarget(manual)
        XCTAssertTrue(automatic.isSelected)
        XCTAssertEqual(commit.label, "Apply Changes")
        XCTAssertFalse(commit.isEnabled)
        XCTAssertEqual(app.staticTexts["settings.cooling.fanSpeedReading"].label, "65 %")

        stepCooling("temptarget", in: app, increasing: true, to: 56)
        XCTAssertFalse(app.staticTexts["cooling.result"].exists)
        assertTapTarget(commit)
        reveal(commit, in: app)
        capture("Essentials Cooling settings revised", app)
        commit.tap()
        XCTAssertTrue(app.staticTexts["cooling.result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["cooling.review.json"].exists)
        XCTAssertFalse(app.navigationBars["Review cooling changes"].exists)
        XCTAssertFalse(commit.isEnabled)
        capture("Essentials Cooling applied", app)

        stepCooling("minFanSpeed", in: app, increasing: false, to: 24)
        reveal(manual, in: app)
        manual.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.8)).tap()
        XCTAssertTrue(manual.isSelected, "One tap near the edge must select Manual")
        XCTAssertFalse(automatic.isSelected)
        XCTAssertTrue(app.staticTexts["cooling.manualFanSpeed.value"].label.contains("60"))
        XCTAssertFalse(app.staticTexts["cooling.minFanSpeed.value"].exists)
        stepCooling("manualFanSpeed", in: app, increasing: true, to: 61)
        capture("Essentials Cooling manual", app)
        reveal(automatic, in: app)
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.8)).tap()
        XCTAssertTrue(automatic.isSelected, "One tap near the edge must select Automatic")
        XCTAssertFalse(manual.isSelected)
        XCTAssertTrue(app.staticTexts["cooling.minFanSpeed.value"].label.contains("24"))
    }

    func testCoolingPreviewFullReviewsJSON() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openCooling(app, essentials: false)
        let commit = app.buttons["cooling.commit"]
        let automatic = app.buttons["cooling.mode.automatic"]
        let manual = app.buttons["cooling.mode.manual"]
        XCTAssertTrue(automatic.isSelected)
        XCTAssertEqual(commit.label, "Review Changes")
        XCTAssertFalse(commit.isEnabled)
        stepCooling("temptarget", in: app, increasing: true, to: 56)
        reveal(commit, in: app)
        capture("Full View Cooling settings revised", app)
        commit.tap()

        let json = app.staticTexts["cooling.review.json"]
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        XCTAssertTrue(json.label.contains("\"temptarget\""))
        XCTAssertTrue(json.label.contains("56"))
        for unedited in ["autofanspeed", "minFanSpeed", "manualFanSpeed", "overheat"] {
            XCTAssertFalse(json.label.contains(unedited))
        }
        capture("Full View Cooling JSON review", app)
        app.buttons["cooling.review.cancel"].tap()
        XCTAssertTrue(commit.waitForExistence(timeout: 5))
        XCTAssertTrue(commit.isEnabled)
        XCTAssertTrue(app.staticTexts["cooling.temptarget.value"].label.contains("56"))
        XCTAssertFalse(app.staticTexts["cooling.result"].exists)
        commit.tap()
        let apply = app.buttons["cooling.review.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()
        XCTAssertTrue(app.staticTexts["cooling.result"].waitForExistence(timeout: 5))
        XCTAssertFalse(commit.isEnabled)

        reveal(manual, in: app)
        manual.tap()
        XCTAssertTrue(manual.isSelected)
        stepCooling("manualFanSpeed", in: app, increasing: true, to: 61)
        capture("Full View Cooling manual", app)
        commit.tap()
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        XCTAssertTrue(json.label.contains("\"autofanspeed\""))
        XCTAssertTrue(json.label.contains("\"manualFanSpeed\""))
        XCTAssertTrue(json.label.contains("61"))
        XCTAssertFalse(json.label.contains("\"temptarget\""))
    }

    func testCoolingPreviewDoesNotOfferMissingConfiguration() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openCooling(app, essentials: true, extraArguments: ["--ui-test-preview-cooling-partial"])
        XCTAssertEqual(app.staticTexts["cooling.mode.fixed"].label, "Automatic mode")
        XCTAssertFalse(app.buttons["cooling.mode.automatic"].exists)
        XCTAssertFalse(app.buttons["cooling.mode.manual"].exists)
        XCTAssertFalse(app.buttons["cooling.mode.menu"].exists)
        XCTAssertFalse(app.buttons["cooling.minFanSpeed.increase"].exists)
        XCTAssertFalse(app.buttons["cooling.manualFanSpeed.increase"].exists)
        stepCooling("temptarget", in: app, increasing: false, to: 54)
    }

    func testCoolingPreviewAtLargestText() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openCooling(app, essentials: true, largest: true)
        let mode = app.buttons["cooling.mode.menu"]
        reveal(mode, in: app)
        assertTapTarget(mode)
        XCTAssertEqual(mode.value as? String, "Automatic")
        capture("Essentials Cooling selector at largest text", app)
        for next in ["Manual", "Automatic"] {
            mode.tap()
            let choice = app.buttons[next].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
            XCTAssertEqual(mode.value as? String, next)
        }
        stepCooling("temptarget", in: app, increasing: true, to: 56)
        assertTapTarget(app.buttons["cooling.temptarget.decrease"])
        capture("Essentials Cooling adjuster at largest text", app)
        let commit = app.buttons["cooling.commit"]
        reveal(commit, in: app)
        assertTapTarget(commit)
        commit.tap()
        XCTAssertTrue(app.staticTexts["cooling.result"].waitForExistence(timeout: 5))
    }

    func testTuningPreviewEssentialsAppliesInPlace() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openTuningPreview(app, essentials: true)
        assertTuningMeasurements(in: app)
        XCTAssertTrue(app.staticTexts["Adjust settings"].exists)
        XCTAssertFalse(app.staticTexts["Tuning draft"].exists)
        let advanced = app.switches["tuningSession.advancedToggle"]
        XCTAssertTrue(advanced.isHittable)
        XCTAssertEqual(advanced.value as? String, "0")
        let apply = app.buttons["tuning.preview.apply"]
        let warning = app.staticTexts["tuning.preview.risk"]
        XCTAssertEqual(apply.label, "Apply Changes")
        XCTAssertFalse(apply.isEnabled)
        let increase = app.buttons["tuning.preview.frequency.increase"]
        reveal(increase, in: app)
        assertTapTarget(increase)
        increase.tap()
        XCTAssertEqual(app.textFields["tuning.preview.frequency.input"].value as? String, "526")
        XCTAssertEqual(app.staticTexts["tuning.preview.frequency.configured"].label, "Configured 525 MHz")
        reveal(apply, in: app)
        assertTapTarget(apply)
        XCTAssertTrue(warning.isHittable)
        XCTAssertTrue(warning.label.contains("damage hardware"))
        XCTAssertLessThan(warning.frame.maxY, apply.frame.minY)
        capture("Essentials Tuning one-step settings", app)
        apply.tap()
        let result = app.staticTexts["tuning.preview.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "Applied in this demo. Nothing sent.")
        XCTAssertFalse(apply.isEnabled)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.navigationBars["Review tuning changes"].exists)
        XCTAssertFalse(app.switches["tuning.preview.acknowledge"].exists)
        XCTAssertFalse(app.staticTexts["tuning.preview.json"].exists)
        XCTAssertEqual(app.staticTexts["tuning.preview.frequency.configured"].label, "Configured 525 MHz")
        assertTuningMeasurements(in: app)
        capture("Essentials Tuning applied in place", app)

        app.buttons["tuning.preview.reset"].tap()
        XCTAssertFalse(result.exists)
        XCTAssertFalse(apply.isEnabled)
        let voltage = app.buttons["tuning.preview.coreVoltage.decrease"]
        reveal(voltage, in: app)
        voltage.tap()
        XCTAssertEqual(app.textFields["tuning.preview.coreVoltage.input"].value as? String, "1145")
        apply.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.navigationBars["Review tuning changes"].exists)
    }

    func testTuningPreviewEssentialsAdvancedKeepsEasyDraftAndReviewSafeguards() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        openTuningPreview(app, essentials: true)
        let advanced = app.switches["tuningSession.advancedToggle"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        XCTAssertEqual(advanced.label, "Advanced")
        XCTAssertTrue(advanced.isHittable, "The switch must be visible without scrolling in Essentials.")
        XCTAssertTrue(advanced.isEnabled)
        XCTAssertEqual(advanced.value as? String, "0")
        XCTAssertFalse(app.buttons["tuningSession.master.plus10"].exists)
        XCTAssertFalse(app.segmentedControls["tuning.preview.mode"].exists)
        capture("Essentials Advanced switch off", app)
        let switchY = advanced.frame.midY
        let switchTarget = advanced.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        let increase = app.buttons["tuning.preview.frequency.increase"]
        reveal(increase, in: app)
        increase.tap()
        let easyInput = app.textFields["tuning.preview.frequency.input"]
        XCTAssertEqual(easyInput.value as? String, "526")
        switchTarget.tap()
        let plus10 = app.buttons["tuningSession.master.plus10"]
        XCTAssertTrue(plus10.waitForExistence(timeout: 5))
        XCTAssertEqual(advanced.value as? String, "1")
        XCTAssertEqual(advanced.frame.midY, switchY, accuracy: 1)
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].exists)
        XCTAssertFalse(app.segmentedControls["tuningSession.controlMode"].exists)
        XCTAssertFalse(easyInput.exists)
        let content = app.descendants(matching: .any)
        for id in ["screen", "header", "liveContext", "references", "journal"] {
            XCTAssertFalse(content["tuningSession.\(id)"].firstMatch.exists)
        }
        XCTAssertTrue(app.staticTexts["tuningSession.writeRestriction"].label.contains("no changes are sent"))
        let frequencyDial = content["tuningSession.master.dial"].firstMatch
        XCTAssertTrue(frequencyDial.exists)
        XCTAssertLessThanOrEqual(frequencyDial.frame.width, 249, "Use the smaller shared dial in Essentials.")
        XCTAssertTrue(content["tuningSession.voltage.dial"].firstMatch.exists)
        capture("Essentials Advanced switch on and compact controls", app)
        let risk = app.switches["tuningSession.riskAcknowledgement"]
        reveal(risk, in: app)
        if risk.value as? String != "1" {
            risk.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(risk.value as? String, "1")
        reveal(plus10, in: app)
        assertTapTarget(plus10)
        plus10.tap()
        capture("Essentials Advanced dials", app)

        app.buttons["tuningSession.jump.apply"].tap()
        let payload = app.staticTexts["tuningSession.payload"]
        reveal(payload, in: app)
        XCTAssertTrue(payload.label.contains("\"frequency\""))
        XCTAssertTrue(payload.label.contains("535"))
        XCTAssertFalse(payload.label.contains("coreVoltage"))
        let apply = app.buttons["tuningSession.apply"]
        reveal(apply, in: app, requireHittable: false)
        XCTAssertFalse(apply.isEnabled, "Demo cannot write even after acknowledging risk.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("Essentials Advanced exact review in Demo", app)

        XCTAssertTrue(advanced.isHittable, "The switch stays reachable while reviewing the draft.")
        switchTarget.tap()
        XCTAssertTrue(easyInput.waitForExistence(timeout: 5))
        XCTAssertEqual(advanced.value as? String, "0")
        XCTAssertFalse(plus10.exists)
        XCTAssertEqual(easyInput.value as? String, "526", "Switching views must not replace an Easy draft.")
        XCTAssertFalse(app.staticTexts["tuning.preview.result"].exists)
        switchTarget.tap()
        XCTAssertTrue(plus10.waitForExistence(timeout: 5))
        XCTAssertTrue(payload.label.contains("535"), "The Advanced draft must also survive the switch.")
        app.navigationBars["Frequency & voltage"].buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["detail.previewControls.tuning"].waitForExistence(timeout: 5),
                      "A single Back tap returns to the miner from expanded Advanced.")
    }

    func testTuningPreviewFullReviewsJSONAndKeepsReadingsAboveKeypad() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openSettingsHubPreview(app, essentials: false, largest: false,
                               extraArguments: ["--preview-number-first-tuning"])
        let tuning = app.buttons["settings.preview.tuning"]
        reveal(tuning, in: app)
        tuning.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["tuningSession.advancedToggle"].exists)
        assertTuningMeasurements(in: app)
        XCTAssertTrue(app.staticTexts["Tuning draft"].exists)
        XCTAssertFalse(app.staticTexts["Adjust settings"].exists)
        let increase = app.buttons["tuning.preview.frequency.increase"]
        reveal(increase, in: app)
        increase.tap()
        let review = app.buttons["tuning.preview.review"]
        reveal(review, in: app)
        XCTAssertEqual(review.label, "Review Changes")
        capture("Full View Tuning settings revised", app)
        review.tap()

        let json = app.staticTexts["tuning.preview.json"]
        let confirm = app.buttons["tuning.preview.confirm"]
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        XCTAssertTrue(json.label.contains("\"frequency\""))
        XCTAssertTrue(json.label.contains("526"))
        XCTAssertFalse(json.label.contains("coreVoltage"))
        XCTAssertFalse(confirm.isEnabled)
        capture("Full View Tuning review", app)
        app.buttons["tuning.preview.cancel"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.isEnabled)
        XCTAssertFalse(app.staticTexts["tuning.preview.result"].exists)

        let input = app.textFields["tuning.preview.frequency.input"]
        let keyboard = app.keyboards.firstMatch
        let readings = app.staticTexts["tuning.preview.readings"]
        reveal(input, in: app)
        XCTAssertEqual(input.value as? String, "526")
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let done = app.buttons["tuning.preview.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(readings.isHittable)
        XCTAssertLessThan(readings.frame.maxY, input.frame.minY)
        assertFleetEditingFieldAboveKeyboard(input, in: app, navigation: app.navigationBars["Frequency & voltage"])
        XCTAssertFalse(review.isEnabled)
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        input.typeText("526.5")
        XCTAssertEqual(input.value as? String, "526.5")
        assertTuningMeasurements(in: app)
        capture("Full View Tuning numeric keyboard", app)
        done.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        XCTAssertTrue(json.label.contains("526.5"))
        XCTAssertFalse(confirm.isEnabled)
        app.switches["tuning.preview.acknowledge"].coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["tuning.preview.result"].waitForExistence(timeout: 5))

        let modes = app.segmentedControls["tuning.preview.mode"]
        reveal(modes, in: app)
        XCTAssertTrue(modes.buttons["Easy"].isSelected)
        modes.buttons["Advanced"].tap()
        let workspaceModes = app.segmentedControls["tuningSession.controlMode"]
        XCTAssertTrue(workspaceModes.waitForExistence(timeout: 5))
        reveal(workspaceModes, in: app)
        XCTAssertTrue(workspaceModes.buttons["Advanced"].isSelected)
        XCTAssertFalse(app.switches["tuningSession.advancedToggle"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.advancedControlsSection"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.header"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.liveContext"].firstMatch.exists)
        app.buttons["tuningSession.jump.apply"].tap()
        let advancedApply = app.buttons["tuningSession.apply"]
        XCTAssertTrue(advancedApply.waitForExistence(timeout: 5))
        reveal(advancedApply, in: app, requireHittable: false)
        XCTAssertFalse(advancedApply.isEnabled)
        reveal(workspaceModes, in: app)
        workspaceModes.buttons["Easy"].tap()
        XCTAssertTrue(modes.waitForExistence(timeout: 5))
        XCTAssertTrue(modes.buttons["Easy"].isSelected)
    }

    func testTuningPreviewEssentialsKeepsBothInputsAboveKeypad() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        openTuningPreview(app, essentials: true)
        let navigation = app.navigationBars["Frequency & voltage"]
        let advanced = app.switches["tuningSession.advancedToggle"]
        let keyboard = app.keyboards.firstMatch
        let done = navigation.buttons["tuning.preview.done"]
        for (field, text) in [("frequency", "526"), ("coreVoltage", "1145")] {
            let input = app.textFields["tuning.preview.\(field).input"]
            reveal(input, in: app)
            let existing = input.value as? String ?? ""
            input.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
            assertFleetEditingFieldAboveKeyboard(input, in: app, navigation: navigation)
            XCTAssertFalse(advanced.isEnabled, "Switching controls must not interrupt an active input.")
            XCTAssertTrue(done.isHittable)
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            input.typeText(text)
            XCTAssertEqual(input.value as? String, text)
            done.tap()
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
            XCTAssertTrue(advanced.isEnabled)
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["tuning.preview.result"].exists)
    }

    func testTuningPreviewLargestTextAndMissingMeasurements() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openTuningPreview(app, essentials: true, largest: true,
                          extraArguments: ["--ui-test-preview-tuning-no-measurements"])
        let advanced = app.switches["tuningSession.advancedToggle"]
        XCTAssertTrue(advanced.isHittable, "The switch fits initially at the largest text size.")
        XCTAssertEqual(advanced.value as? String, "0")
        let clock = app.staticTexts["tuning.preview.readings.clock"]
        reveal(clock, in: app)
        XCTAssertEqual(clock.label, "Not reported")
        XCTAssertEqual(app.staticTexts["tuning.preview.readings.voltage"].label, "Not reported")
        capture("Essentials Tuning readings at largest text", app)
        let increase = app.buttons["tuning.preview.frequency.increase"]
        reveal(increase, in: app)
        assertTapTarget(increase)
        increase.tap()
        let apply = app.buttons["tuning.preview.apply"]
        reveal(apply, in: app)
        assertTapTarget(apply)
        XCTAssertTrue(apply.isEnabled)
        let warning = app.staticTexts["tuning.preview.risk"]
        XCTAssertLessThan(warning.frame.maxY, apply.frame.minY)
        capture("Essentials Tuning apply at largest text", app)
        apply.tap()
        XCTAssertTrue(app.staticTexts["tuning.preview.result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.navigationBars["Review tuning changes"].exists)
    }

    func testTuningWithoutPreviewKeepsExistingEditor() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openNumberFirstMinerDetail(app, essentials: true, largest: false)
        let tuning = app.buttons["detail.previewControls.tuning"]
        reveal(tuning, in: app)
        tuning.tap()
        let advanced = app.switches["tuningSession.advancedToggle"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        XCTAssertTrue(advanced.isHittable)
        XCTAssertEqual(advanced.value as? String, "0")
        XCTAssertTrue(app.textFields["tuningSession.master.customInput"].exists)
        XCTAssertFalse(app.staticTexts["tuning.preview.readings"].exists)
        XCTAssertFalse(app.buttons["tuningSession.apply"].isEnabled)
    }

    func testCoolingWithoutPreviewStillOpensReviewedSettings() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openNumberFirstMinerDetail(app, essentials: true, largest: false)
        let cooling = app.buttons["detail.previewControls.cooling"]
        reveal(cooling, in: app)
        cooling.tap()
        XCTAssertTrue(app.buttons["Review cooling change"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cooling.commit"].exists)
    }

    func testSettingsHubPreviewInEssentials() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openSettingsHubPreview(app, essentials: true, captureEntry: true)
        try verifySettingsHubCategories(app, checks: settingsHubDestinations.filter { $0.0 != "restart" })
        XCTAssertFalse(app.buttons["settings.preview.diagnostics"].exists)
        XCTAssertFalse(app.buttons["settings.preview.compatibility"].exists)
        XCTAssertFalse(app.buttons["settings.preview.firmware"].exists)
        capture("Essentials Miner settings hub", app)
        verifySettingsRestartAppliesInPlace(app)
    }

    func testSettingsHubPreviewInFullView() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openSettingsHubPreview(app, essentials: false, captureEntry: true)
        let tools: [(String, String)] = [
            ("diagnostics", "Diagnostics"), ("compatibility", "Check compatibility"),
            ("firmware", "Firmware updates")
        ]
        try verifySettingsHubCategories(app, checks: settingsHubDestinations + tools)
        capture("Full View Miner settings hub", app)
        let firmware = app.buttons["settings.preview.firmware"]
        reveal(firmware, in: app)
        capture("Full View Miner settings tools", app)
    }

    func testSettingsHubPreviewRequiresWriteEvidence() {
        let app = XCUIApplication()
        defer { app.terminate() }
        let denied = ["--ui-test-preview-detail-read-only"]
        openNumberFirstMinerDetail(app, essentials: true, largest: false,
            extraArguments: ["--preview-number-first-settings-hub"] + denied)
        XCTAssertFalse(app.buttons["detail.previewControls.settings"].exists)
        app.terminate()

        openSettingsHubPreview(app, essentials: false, extraArguments: denied)
        XCTAssertTrue(app.staticTexts["No editable settings available"].exists)
        for (id, _) in settingsHubDestinations {
            XCTAssertFalse(app.buttons["settings.preview.\(id)"].exists)
        }
        XCTAssertTrue(app.buttons["settings.preview.diagnostics"].exists)
        XCTAssertTrue(app.buttons["settings.preview.compatibility"].exists)
        XCTAssertFalse(app.buttons["settings.preview.firmware"].exists)
        capture("Full View Miner settings read only", app)
    }

    func testSettingsHubPreviewAtLargestText() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openSettingsHubPreview(app, essentials: true, largest: true,
            extraArguments: ["--ui-test-preview-settings-hub-no-display"])
        XCTAssertFalse(app.buttons["settings.preview.display"].exists)
        let general = app.buttons["settings.preview.general"]
        reveal(general, in: app)
        assertTapTarget(general)
        capture("Essentials Miner settings at largest text", app)
        try verifySettingsHubCategories(app, checks: [("tuning", "Frequency & voltage")])
        verifySettingsRestartAppliesInPlace(app, captureName: "Essentials Settings restart at largest text")
    }

    func testSettingsHubWithoutPreviewRemainsOriginal() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openOriginalMiner(app)
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["settings.quick.hostname"].exists)
        XCTAssertFalse(app.buttons["settings.preview.general"].exists)
    }
}
