import XCTest

/// Staged-review and confirmation flows for RealModeControlUITests.
extension RealModeControlUITests {
    #if HASHFLEET_LIVE_REVIEW
    func testCompactSettingsKeyboardKeepsHostnameAndDisplayDraftsWithoutSaving() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let server = try LoopbackMinerServer()
        server.setInfoResponse(status: 200, json: #"""
        {"hostname":"loopback-before","version":"fixture-forms","macAddr":"02:00:00:00:00:01",
         "ASICModel":"BM1370","hashRate":1234,"power":19.5,"temp":51,"frequency":500,"coreVoltage":1100,
         "statsFrequency":60,"displayTimeout":5,"rotation":0,"invertscreen":0}
        """#)
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: ["--ui-test-dashboard-essentials"])
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        assertBecomesOnline(miner)
        miner.tap()
        let settings = app.buttons["detail.previewControls.settings"]
        reveal(settings, in: app)
        settings.tap()
        let general = app.buttons["settings.preview.general"]
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        general.tap()
        let generalBar = app.navigationBars["General"]
        XCTAssertTrue(generalBar.waitForExistence(timeout: 5))
        let hostname = app.textFields["settings.general.hostname"]
        reveal(hostname, in: app)
        replaceText(hostname, with: "keyboard-fixture", in: app)
        assertFleetEditingFieldAboveKeyboard(hostname, in: app, navigation: generalBar)
        hostname.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(hostname.value as? String, "keyboard-fixture")
        XCTAssertTrue(server.writes.isEmpty)
        generalBar.buttons["BackButton"].tap()
        let display = app.buttons["settings.preview.display"]
        XCTAssertTrue(display.waitForExistence(timeout: 5))
        display.tap()
        let displayBar = app.navigationBars["Display"]
        XCTAssertTrue(displayBar.waitForExistence(timeout: 5))
        let timeout = app.textFields["settings.display.timeout"]
        reveal(timeout, in: app)
        XCTAssertEqual(timeout.value as? String, "5")
        timeout.tap()
        // Either caret edge produces 55. This checks native typing and dismissal,
        // rather than depending on a tap landing after a right-aligned digit.
        timeout.typeText("5")
        assertFleetEditingFieldAboveKeyboard(timeout, in: app, navigation: displayBar)
        let done = displayBar.buttons["settings.keyboardDone"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(timeout.value as? String, "55")
        XCTAssertFalse(app.alerts["Display settings saved"].exists)
        XCTAssertTrue(server.writes.isEmpty)
    }

    func testCompactEssentialsAdvancedRequiresExplicitConfirmation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let server = try LoopbackMinerServer()
        server.setInfoResponse(status: 200, json: #"""
        {"hostname":"tuning-fixture","version":"fixture-tuning","macAddr":"02:00:00:00:00:01",
         "ASICModel":"BM1370","hashRate":1234,"power":19.5,"temp":51,"frequency":500,"coreVoltage":1100}
        """#)
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: [
            "--ui-test-dashboard-essentials", "--ui-test-loopback-manual-refresh"
        ])
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        assertBecomesOnline(miner)
        revealFleetControl(miner, in: app)
        miner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(app.navigationBars["Loopback review fixture"].waitForExistence(timeout: 8))
        let tuning = app.buttons["detail.previewControls.tuning"]
        revealFleetControl(tuning, in: app)
        tuning.tap()
        let advanced = app.switches["tuningSession.advancedToggle"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        XCTAssertTrue(advanced.isHittable)
        XCTAssertEqual(advanced.value as? String, "0")
        advanced.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(advanced.value as? String, "1")

        let risk = app.switches["tuningSession.riskAcknowledgement"]
        revealFleetControl(risk, in: app, below: advanced)
        let riskTarget = risk.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        if risk.value as? String == "1" { riskTarget.tap() }
        XCTAssertEqual(risk.value as? String, "0")
        let step = app.buttons["tuningSession.master.plus10"]
        revealFleetControl(step, in: app)
        step.tap()
        let jump = app.buttons["tuningSession.jump.apply"]
        jump.tap()
        let apply = app.buttons["tuningSession.apply"]
        revealFleetControl(apply, in: app, requireHittable: false)
        XCTAssertFalse(apply.isEnabled, "Risk acknowledgement must still gate the compact tuner.")

        revealFleetControl(risk, in: app, below: advanced)
        riskTarget.tap()
        XCTAssertEqual(risk.value as? String, "1")
        jump.tap()
        revealFleetControl(apply, in: app)
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        let confirmation = app.alerts["Apply tuning change?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let preview = confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\"frequency\""))
            .firstMatch
        XCTAssertTrue(preview.exists)
        XCTAssertTrue(preview.label.contains("510"))
        XCTAssertFalse(preview.label.contains("coreVoltage"))
        XCTAssertTrue(server.writes.isEmpty, "Opening the review must not write.")
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(advanced.isHittable)
        XCTAssertTrue(advanced.isEnabled)
        assertNoWrites(server, for: 1)
    }

    func testEssentialsControlsMenuShowsInlineAdvancedSwitch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let server = try LoopbackMinerServer()
        server.setInfoResponse(status: 200, json: #"""
        {"hostname":"tuning-fixture","version":"fixture-tuning","macAddr":"02:00:00:00:00:01",
         "ASICModel":"BM1370","hashRate":1234,"power":19.5,"temp":51,"frequency":500,"coreVoltage":1100}
        """#)
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: ["--ui-test-dashboard-essentials"])
        let controls = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")).firstMatch
        revealFleetControl(controls, in: app)
        controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let tuner = fleetTuningSessionMenuItem(in: app)
        XCTAssertTrue(tuner.waitForExistence(timeout: 5))
        tuner.tap()

        let navigation = app.navigationBars["Frequency & voltage"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        let advanced = app.switches["tuningSession.advancedToggle"]
        XCTAssertTrue(advanced.isHittable)
        XCTAssertEqual(advanced.value as? String, "0")
        let easyField = app.textFields["tuningSession.master.customInput"]
        XCTAssertTrue(easyField.exists)
        let target = advanced.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        target.tap()
        let dial = app.descendants(matching: .any)["tuningSession.master.dial"].firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        XCTAssertEqual(advanced.value as? String, "1")
        XCTAssertFalse(app.segmentedControls["tuningSession.controlMode"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuningSession.liveContext"].exists)
        XCTAssertFalse(easyField.exists)
        target.tap()
        XCTAssertTrue(easyField.waitForExistence(timeout: 5))
        XCTAssertFalse(dial.exists)
        XCTAssertEqual(advanced.value as? String, "0")
        navigation.buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        XCTAssertTrue(server.writes.isEmpty, "Neither toggling nor navigating authorizes a miner update.")
    }
    #endif

    /// Navigation actions remain reachable without installing a keyboard-accessory toolbar.
    /// Inspect the actual editor both before focus and after entering the complete draft.
    func assertCustomJSONEditorLayout(app: XCUIApplication, editor: XCUIElement, phase: String) {
        let navigation = app.navigationBars["Custom JSON"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5), phase)
        XCTAssertTrue(navigation.buttons["Format"].isHittable, "Format must remain reachable \(phase).")
        XCTAssertTrue(navigation.buttons["custom_json.done"].isHittable, "Done must remain reachable \(phase).")
        let frame = editor.frame
        XCTAssertTrue(frame.width.isFinite && frame.height.isFinite, "Editor frame must be finite \(phase).")
        XCTAssertGreaterThan(frame.width, 0, "Editor width must be positive \(phase).")
        XCTAssertGreaterThan(frame.height, 0, "Editor height must be positive \(phase).")
        if phase == "after text entry" {
            assertFleetEditingFieldAboveKeyboard(editor, in: app, navigation: navigation)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Custom JSON navigation actions and editor \(phase)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Stages the custom JSON document, verifies the staged review keeps typed APPLY,
    /// then cancels without ever writing.
    func stageAndCancelCustomJSON(app: XCUIApplication, server: LoopbackMinerServer) throws {
        let done = app.buttons["custom_json.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let format = app.buttons["custom_json.format"]
        reveal(format, in: app)
        format.tap()
        let stage = app.buttons["custom_json.stage_review"]
        reveal(stage, in: app)
        stage.tap()
        XCTAssertTrue(app.navigationBars["Update settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Review before sending"].exists,
                       "Staging must not require duplicate authorization")
        let stagedEditor = app.textViews["endpoint.json"]
        reveal(stagedEditor, in: app, direction: .down)
        let stagedText = try XCTUnwrap(stagedEditor.value as? String)
        XCTAssertTrue(stagedText.contains("customFeature"))
        XCTAssertTrue(stagedText.contains("18446744073709551615"), "Unknown integer fields must retain all digits")
        stagedEditor.tap()
        let requestBar = app.navigationBars["Update settings"]
        assertFleetEditingFieldAboveKeyboard(stagedEditor, in: app, navigation: requestBar)
        let doneEditingRequest = requestBar.buttons["endpoint.keyboardDone"]
        XCTAssertTrue(doneEditingRequest.isHittable)
        doneEditingRequest.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(stagedEditor.value as? String, stagedText)
        let review = app.buttons["endpoint.send"]
        reveal(review, in: app)
        review.tap()
        XCTAssertTrue(app.navigationBars["Review before sending"].waitForExistence(timeout: 5))
        let token = app.textFields["confirmation.token"]
        reveal(token, in: app)
        XCTAssertTrue(token.exists, "Custom JSON retains typed APPLY even when the frequency risk acknowledgement is active")
        XCTAssertFalse(app.staticTexts["confirmation.quickConfirmation"].exists)
        XCTAssertTrue(server.writes.isEmpty)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Custom firmware JSON typed review with exact UInt64"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let nav = app.navigationBars["Review before sending"]
        token.tap()
        token.typeText("APP")
        assertFleetEditingFieldAboveKeyboard(token, in: app, navigation: nav)
        let doneEditing = nav.buttons["confirmation.keyboardDone"]
        XCTAssertTrue(doneEditing.isHittable)
        doneEditing.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(token.value as? String, "APP")
        let apply = app.buttons["confirmation.apply"]
        reveal(apply, in: app)
        XCTAssertFalse(apply.isEnabled, "Keyboard Done must not authorize or send a partial token")
        let cancel = nav.buttons["confirmation.cancel"]
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        assertNoWrites(server, for: 0.5)
    }

    func testCustomJSONKeyboardKeepsTheEditorClearInLandscape() throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        device.orientation = .portrait
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop(); device.orientation = .portrait }
        try launchWithConfiguredReviewFixture(app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        assertBecomesOnline(miner)
        miner.tap()
        let custom = app.buttons["detail.customJSON"]
        reveal(custom, in: app)
        custom.tap()
        let nav = app.navigationBars["Custom JSON"]
        XCTAssertTrue(nav.waitForExistence(timeout: 5))
        device.orientation = .landscapeLeft
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        let editor = app.textViews["custom_json.editor"]
        reveal(editor, in: app)
        let draft = #"{"fixture":1}"#
        replaceText(editor, with: draft, in: app)
        assertFleetEditingFieldAboveKeyboard(editor, in: app, navigation: nav)
        recordScreenshot("Custom JSON entire editor visible in landscape", app: app)
        let done = nav.buttons["custom_json.done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertTrue(server.writes.isEmpty)
    }

    /// The unified settings hub keeps safe hostname changes on the native form. The tuning
    /// acknowledgement does not turn a safe field into a separate JSON review flow.
    func verifyUnifiedHostnameDirectApply(app: XCUIApplication, server: LoopbackMinerServer) throws {
        let general = app.buttons["settings.general"]
        reveal(general, in: app, direction: .down)
        general.tap()
        let hostname = app.textFields["Network hostname"]
        reveal(hostname, in: app)
        replaceText(hostname, with: "unified-settings-fixture", in: app)
        let save = app.buttons["Save name"]
        reveal(save, in: app)
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.buttons["Review hostname change"].exists,
                       "Safe hostname changes must not expose a separate review route.")
        XCTAssertTrue(server.writes.isEmpty, "Editing a hostname must not write.")
        save.tap()
        try verifyDirectApplySendsPatch(
            app: app,
            server: server,
            expectedHostname: "unified-settings-fixture"
        )
        let write = try XCTUnwrap(server.writes.first)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: write.body) as? [String: String],
                       ["hostname": "unified-settings-fixture"])
    }

    /// The risk acknowledgement remains visible after backgrounding, while no extra write
    /// is authorized or sent merely by leaving and returning to the app.
    func verifyBackgroundRetainsRiskAcknowledgementWithoutExtraWrite(
        app: XCUIApplication,
        server: LoopbackMinerServer
    ) {
        if app.navigationBars["Update settings"].exists {
            app.navigationBars["Update settings"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 5))
            app.navigationBars["General"].buttons.firstMatch.tap()
        } else {
            XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 5))
            app.navigationBars["General"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 5))
        }
        XCUIDevice.shared.press(.home)
        app.activate()
        let tuning = app.buttons["settings.tuning"]
        reveal(tuning, in: app)
        tuning.tap()
        let risk = app.switches["tuningSession.riskAcknowledgement"]
        reveal(risk, in: app)
        XCTAssertEqual(risk.value as? String, "1", "The per-miner acknowledgement should remain remembered.")
        XCTAssertEqual(server.writes.count, 1, "Backgrounding must not authorize an additional device write.")
    }

    /// The confirmed send produces exactly one PATCH and refreshes live telemetry after it.
    func verifyApplySendsConfirmedPatch(app: XCUIApplication, server: LoopbackMinerServer) throws {
        app.buttons["confirmation.apply"].tap()
        let received = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.writes.count == 1 },
                                                 object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 10), .completed)
        let completion = app.alerts["Request accepted"]
        XCTAssertTrue(completion.waitForExistence(timeout: 10))
        completion.buttons["OK"].tap()
        let success = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS 'Loopback hostname updated'")).firstMatch
        // The response lives below the request editor in a lazy SwiftUI Form.
        // Scroll it into the accessibility tree after the confirmation dismisses.
        XCTAssertTrue(app.navigationBars["Update settings"].waitForExistence(timeout: 5))
        reveal(success, in: app)
        XCTAssertTrue(success.waitForExistence(timeout: 10))
        XCTAssertEqual(server.hostname, "loopback-after")
        let request = try XCTUnwrap(server.writes.first)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.path, "/api/system")
        XCTAssertEqual(request.headers["content-type"], "application/json")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.body) as? [String: String])
        XCTAssertEqual(body, ["hostname": "loopback-after"], "Only the reviewed hostname key may be sent.")
        let readsAfterWrite = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let journal = server.journal
            guard let index = journal.firstIndex(where: { $0.method == "PATCH" }) else { return false }
            return journal.dropFirst(index + 1).contains { $0.method == "GET" && $0.path == "/api/system/info" }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [readsAfterWrite], timeout: 10), .completed,
                       "A successful write should refresh real telemetry.")
        let noDuplicate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.writes.count > 1 },
                                                    object: nil)
        noDuplicate.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [noDuplicate], timeout: 1), .completed)
        XCTAssertEqual(server.writes.count, 1, "Exactly one PATCH must result from one explicitly confirmed send.")
    }

    /// A safe-field (e.g. hostname) write in default mode skips the review sheet entirely: no
    /// "Review before sending" screen ever appears, and the PATCH fires the moment the
    /// native form's review action is tapped. Verifies the same invariants the old typed-APPLY
    /// flow verified: exactly one PATCH, the correct body, and a telemetry refresh afterward.
    func verifyDirectApplySendsPatch(
        app: XCUIApplication,
        server: LoopbackMinerServer,
        expectedHostname: String = "loopback-after"
    ) throws {
        let received = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.writes.count >= 1 },
                                                 object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 10), .completed,
                       "A unified-form Save must send its PATCH directly, without any review page.")
        XCTAssertFalse(app.navigationBars["Review before sending"].exists,
                       "Safe fields must not show the Advanced review sheet.")
        XCTAssertFalse(app.navigationBars["Update settings"].exists,
                       "Safe quick changes must not show the JSON request page unless review is required.")
        XCTAssertTrue(app.navigationBars["General"].exists, "Saving stays on the settings form.")
        let completion = app.alerts["Request accepted"]
        XCTAssertTrue(completion.waitForExistence(timeout: 10),
                      "A direct settings save should provide explicit completion feedback.")
        completion.buttons["OK"].tap()
        let status = app.descendants(matching: .any)["settings.saveStatus"]
        let saved = NSPredicate(format: "label BEGINSWITH 'Request accepted for'")
        expectation(for: saved, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Unified settings saved directly on the General form"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertEqual(server.hostname, expectedHostname)
        let request = try XCTUnwrap(server.writes.first)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.path, "/api/system")
        XCTAssertEqual(request.headers["content-type"], "application/json")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.body) as? [String: String])
        XCTAssertEqual(body, ["hostname": expectedHostname], "Only the edited hostname key may be sent.")
        let readsAfterWrite = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let journal = server.journal
            guard let index = journal.firstIndex(where: { $0.method == "PATCH" }) else { return false }
            return journal.dropFirst(index + 1).contains { $0.method == "GET" && $0.path == "/api/system/info" }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [readsAfterWrite], timeout: 10), .completed,
                       "A successful write should refresh real telemetry.")
        let noDuplicate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.writes.count > 1 },
                                                    object: nil)
        noDuplicate.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [noDuplicate], timeout: 1), .completed)
        XCTAssertEqual(server.writes.count, 1, "Exactly one PATCH must result from one direct-apply safe-field change.")
    }
}
