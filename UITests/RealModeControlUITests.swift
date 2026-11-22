import XCTest

/// End-to-end safety regression using a real HTTP connection to an in-process,
/// loopback-only fixture. No demo mode, URLProtocol interception or physical miner.
@MainActor
final class RealModeControlUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    #if HASHFLEET_LIVE_REVIEW
    func testCompactMinerMenuRenamesAndRemovesOnlyTheLocalEntry() throws {
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: ["--ui-test-dashboard-essentials"])
        let miners = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'"))
        let miner = miners.firstMatch
        assertBecomesOnline(miner)
        revealTelemetryControl(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.buttons["detail.statusDisclosure"].waitForExistence(timeout: 5))

        let menu = app.buttons["detail.manageMiner"]
        let title = app.descendants(matching: .any)["detail.minerTitle"].firstMatch
        let rename = app.alerts["Rename miner"]
        menu.tap()
        app.buttons["Rename in app"].firstMatch.tap()
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        let name = rename.textFields.firstMatch
        XCTAssertEqual(name.value as? String, "Loopback review fixture")
        name.typeText(" draft")
        rename.buttons["Cancel"].tap()
        XCTAssertTrue(rename.waitForNonExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("Loopback review fixture"))

        menu.tap()
        app.buttons["Rename in app"].firstMatch.tap()
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Loopback review fixture")
        name.typeText(" revisited")
        rename.buttons["Save"].tap()
        let localName = "Loopback review fixture revisited"
        let renamed = NSPredicate(format: "label CONTAINS %@", localName)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: renamed, object: title)], timeout: 5), .completed)
        XCTAssertEqual(server.hostname, "loopback-before")
        XCTAssertTrue(server.writes.isEmpty)

        app.terminate()
        app.launchArguments.append("--ui-test-preserve-storage")
        app.launch()
        XCTAssertTrue(miner.waitForExistence(timeout: 8))
        XCTAssertTrue(miner.label.contains(localName))
        revealTelemetryControl(miner, in: app)
        miner.tap()

        let remove = app.sheets.buttons["Remove from fleet"]
        menu.tap()
        app.buttons["Remove from fleet"].firstMatch.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        app.sheets.buttons["Keep miner"].tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertTrue(title.exists)

        menu.tap()
        app.buttons["Remove from fleet"].firstMatch.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        XCTAssertEqual(miners.count, 0)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 8))
        XCTAssertEqual(miners.count, 0)
        XCTAssertTrue(server.writes.isEmpty, "Local management must never write to the miner")
    }

    func testEssentialsCoolingProgressStaysInApplyButton() throws {
        try verifyCoolingProgress(essentials: true)
    }

    func testFullViewCoolingProgressStaysInReviewApplyButton() throws {
        try verifyCoolingProgress(essentials: false)
    }

    func testCompactPauseAndResumeKeepStatusAndControlsInPlace() throws {
        let server = try LoopbackMinerServer()
        server.holdMiningActions()
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: [
            "--ui-test-dashboard-essentials", "--ui-test-loopback-manual-refresh"
        ])
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        assertBecomesOnline(miner)
        revealTelemetryControl(miner, in: app)
        miner.tap()

        let status = app.buttons["detail.statusDisclosure"]
        let readout = app.descendants(matching: .any)["detail.previewHashrate"].firstMatch
        let pause = app.buttons["detail.quick.pause"]
        let resume = app.buttons["detail.quick.resume"]
        let settings = app.buttons["detail.previewControls.settings"]
        let refresh = app.buttons["detail.refresh"]
        func waitFor(_ element: XCUIElement, field: String, contains text: String, line: UInt = #line) {
            let predicate = NSPredicate(format: "%K CONTAINS[c] %@", field, text)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
                                          timeout: 5), .completed, element.debugDescription, line: line)
        }
        waitFor(status, field: "label", contains: "Connected")
        XCTAssertTrue(readout.exists)
        let headerGap = readout.frame.minY - status.frame.maxY
        revealTelemetryControl(settings, in: app)
        XCTAssertTrue(pause.isHittable && resume.isHittable)
        let tracked = [pause, resume, settings, refresh]
        let geometry = tracked.map(\.frame)
        func assertLayout(line: UInt = #line) {
            for (element, frame) in zip(tracked, geometry) {
                XCTAssertEqual(element.frame.minY, frame.minY, accuracy: 1, element.identifier, line: line)
                XCTAssertEqual(element.frame.height, frame.height, accuracy: 1, element.identifier, line: line)
            }
            XCTAssertEqual(readout.frame.minY - status.frame.maxY, headerGap, accuracy: 1, line: line)
            XCTAssertFalse(app.descendants(matching: .any)["detail.reportedFaults"].exists, line: line)
        }
        func start(_ button: XCUIElement, named action: String) {
            button.tap()
            let held = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.hasPendingMiningAction },
                                                 object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 4), .completed)
            XCTAssertFalse(pause.isEnabled || resume.isEnabled)
            waitFor(button, field: "value", contains: "Sending \(action)")
            assertLayout()
        }

        start(pause, named: "pause")
        XCTAssertTrue(server.finishMiningAction())
        waitFor(pause, field: "value", contains: "accepted the request")
        waitFor(status, field: "label", contains: "Connected")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        assertLayout()
        refresh.tap()
        waitFor(status, field: "label", contains: "Mining paused")
        assertLayout()

        start(resume, named: "resume")
        XCTAssertTrue(server.finishMiningAction())
        waitFor(resume, field: "value", contains: "accepted the request")
        waitFor(status, field: "label", contains: "Mining paused")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        refresh.tap()
        waitFor(status, field: "label", contains: "Connected")
        assertLayout()

        start(pause, named: "pause")
        XCTAssertTrue(server.finishMiningAction(accept: false))
        let error = app.alerts["Miner command not confirmed"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.staticTexts.containing(NSPredicate(format: "label CONTAINS '404'")).firstMatch.exists)
        error.buttons["OK"].tap()
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        XCTAssertFalse(pause.isEnabled)
        XCTAssertTrue(resume.isEnabled)
        assertLayout()
        XCTAssertEqual(server.writes.map(\.path), ["/api/system/pause", "/api/system/resume", "/api/system/pause"])
        XCTAssertTrue(server.writes.allSatisfy { $0.method == "POST" && $0.body.isEmpty })
    }

    func testCompactMinerRefreshRetainsReadingAndLayoutAcrossFailureAndRecovery() throws {
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); server.stop() }
        func info(_ hashrate: Int) -> String {
            """
            {"hostname":"loopback-before","version":"ui-loopback-fixture","ASICModel":"BM1370",
            "hashRate":\(hashrate),"power":19.5,"temp":51,"uptimeSeconds":1200,"sharesAccepted":24,
            "sharesRejected":0,"bestDiff":"42M","autofanspeed":1,"temptarget":66}
            """
        }
        let original = info(1234)
        server.setInfoResponse(status: 200, json: original)
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: ["--ui-test-loopback-manual-refresh"])
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        assertBecomesOnline(miner)
        revealTelemetryControl(miner, in: app)
        miner.tap()

        let status = app.buttons["detail.statusDisclosure"]
        let refresh = app.buttons["detail.refresh"]
        let readout = app.descendants(matching: .any)["detail.previewHashrate"].firstMatch
        let trend = app.buttons["detail.historyMetric"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertTrue(trend.exists)
        XCTAssertTrue(status.label.contains("Connected · Updated"), status.label)
        let oldReading = try XCTUnwrap(readout.value as? String)
        XCTAssertTrue(oldReading.contains("1.23"), oldReading)
        let trackedFrames = [status, readout, trend, refresh].map(\.frame)
        func assertLayoutUnchanged(line: UInt = #line) {
            for (element, frame) in zip([status, readout, trend, refresh], trackedFrames) {
                XCTAssertTrue(element.exists, element.identifier, line: line)
                XCTAssertEqual(element.frame.minY, frame.minY, accuracy: 1, element.identifier, line: line)
                XCTAssertEqual(element.frame.height, frame.height, accuracy: 1, element.identifier, line: line)
            }
        }
        func startHeldRefresh() {
            server.holdNextInfoRead()
            XCTAssertTrue(refresh.isEnabled)
            refresh.tap()
            let pending = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.hasPendingInfoRead }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 4), .completed)
            XCTAssertFalse(refresh.isEnabled)
            XCTAssertEqual(refresh.value as? String, "Refreshing")
        }
        func waitForStatus(_ label: String) {
            let expected = NSPredicate(format: "label CONTAINS %@", label)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expected, object: status)],
                                          timeout: 5), .completed)
        }

        startHeldRefresh()
        XCTAssertEqual(readout.value as? String, oldReading)
        assertLayoutUnchanged()
        XCTAssertTrue(server.finishInfoRead(status: 500, json: "{}"))
        waitForStatus("Offline · Updated")
        XCTAssertEqual(readout.value as? String, oldReading)
        assertLayoutUnchanged()
        XCTAssertFalse(app.buttons["detail.previewControls.cooling"].exists, "Offline settings must remain locked")

        startHeldRefresh()
        XCTAssertEqual(readout.value as? String, oldReading)
        waitForStatus("Offline · Updated")
        assertLayoutUnchanged()
        recordScreenshot("Miner refresh retains last reading and toolbar size", app: app)
        XCTAssertTrue(server.finishInfoRead(status: 200, json: info(1560)))
        waitForStatus("Connected · Updated just now")
        XCTAssertTrue((readout.value as? String)?.contains("1.56") == true, "Expected the changed Info response")
        assertLayoutUnchanged()
        XCTAssertTrue(refresh.isEnabled)
        XCTAssertTrue(server.writes.isEmpty, "A failed and recovered refresh may only read from the miner")
    }

    func testCompactMinerStatusOpensWebPageAndReturnsToSameMiner() throws {
        let server = try LoopbackMinerServer()
        server.enableWebPage()
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.errorSummary"].firstMatch.waitForExistence(timeout: 10))
        assertBecomesOnline(miner)
        revealTelemetryControl(miner, in: app)
        miner.tap()

        let status = app.buttons["detail.statusDisclosure"]
        let address = app.buttons["detail.address"]
        let installed = app.descendants(matching: .any)["detail.installedFirmware"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Connected · Updated"), status.label)
        XCTAssertEqual(status.value as? String, "Collapsed")
        XCTAssertFalse(app.buttons["detail.firmwareDisclosure"].exists, "No unverified release should be shown")
        XCTAssertFalse(address.exists)
        status.tap()
        XCTAssertEqual(status.value as? String, "Expanded")
        XCTAssertTrue(installed.exists)
        XCTAssertTrue(address.label.contains("127.0.0.1"), address.label)
        XCTAssertFalse(server.journal.contains { $0.path == "/" }, "Expanding status must not open the webpage")
        recordScreenshot("Expanded status and miner web link", app: app)
        address.tap()

        let browser = app.navigationBars["Miner web page"]
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts["Loopback miner web interface"].waitForExistence(timeout: 10))
        XCTAssertTrue(server.journal.contains { $0.method == "GET" && $0.path == "/" })
        let back = try XCTUnwrap(browser.buttons.allElementsBoundByIndex.first)
        back.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "Expanded")
        XCTAssertTrue(app.descendants(matching: .any)["detail.previewHashrate"].firstMatch.exists)
        XCTAssertTrue(server.writes.isEmpty)
    }

    func testDisplaySaveOffersLaterAndExplicitRestartOnlyAfterReadback() throws {
        let server = try LoopbackMinerServer()
        server.holdDisplayWrites()
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: ["--ui-test-dashboard-essentials"])
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.errorSummary"].firstMatch.waitForExistence(timeout: 10))
        assertBecomesOnline(miner)
        revealTelemetryControl(miner, in: app)
        miner.tap()
        let settings = app.buttons["detail.previewControls.settings"]
        revealTelemetryControl(settings, in: app)
        settings.tap()
        let display = app.buttons["settings.preview.display"]
        XCTAssertTrue(display.waitForExistence(timeout: 5))
        display.tap()

        let toggle = app.switches["settings.display.inversion"]
        let save = app.buttons["settings.display.save.invertscreen"]
        let offer = app.alerts["Display settings saved"]
        let restart = offer.buttons["Restart Miner"]
        let later = offer.buttons["Later"]
        let rejected = app.alerts["Settings not saved"]
        for (index, accept) in [false, true, true].enumerated() {
            revealTelemetryControl(toggle, in: app)
            if index != 1 { toggle.tap() }
            XCTAssertEqual(toggle.value as? String, index == 2 ? "0" : "1")
            revealTelemetryControl(save, in: app)
            let original = save.frame
            save.tap()
            XCTAssertTrue(save.wait(for: \.label, toEqual: "Saving…", timeout: 3))
            XCTAssertFalse(save.isEnabled)
            XCTAssertEqual(save.frame.minY, original.minY, accuracy: 1)
            XCTAssertEqual(save.frame.height, original.height, accuracy: 1)
            XCTAssertFalse(app.descendants(matching: .any)["settings.saveStatus"].firstMatch.exists)
            XCTAssertFalse(offer.exists, "The restart offer must wait for a verified save")
            let waiting = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.hasPendingDisplayWrite }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [waiting], timeout: 2), .completed)
            XCTAssertTrue(server.finishDisplayWrite(accept: accept))
            if accept {
                XCTAssertTrue(offer.waitForExistence(timeout: 5))
                XCTAssertTrue(later.isHittable && restart.isHittable)
                XCTAssertEqual(server.writes.map(\.method), Array(repeating: "PATCH", count: index + 1))
                if index == 1 {
                    recordScreenshot("Display save offers Restart Miner or Later", app: app)
                    later.tap()
                    XCTAssertTrue(offer.waitForNonExistence(timeout: 5))
                    XCTAssertEqual(server.writes.map(\.method), ["PATCH", "PATCH"])
                } else {
                    restart.tap()
                }
            } else {
                XCTAssertTrue(rejected.waitForExistence(timeout: 5))
                XCTAssertFalse(rejected.buttons["Restart Miner"].exists)
                rejected.buttons["OK"].tap()
                XCTAssertTrue(rejected.waitForNonExistence(timeout: 5))
            }
        }
        let receipt = app.staticTexts["settings.saveStatus"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(receipt.label.contains("accepted the restart request"))
        XCTAssertEqual(server.writes.map(\.method), ["PATCH", "PATCH", "PATCH", "POST"])
        XCTAssertEqual(server.writes.map(\.path), Array(repeating: "/api/system", count: 3) + ["/api/system/restart"])
        XCTAssertTrue(server.writes.last?.body.isEmpty == true)
        for (request, value) in zip(server.writes.prefix(3), [1, 1, 0]) {
            XCTAssertEqual(try JSONSerialization.jsonObject(with: request.body) as? [String: Int], ["invertscreen": value])
        }
    }

    private func verifyCoolingProgress(essentials: Bool) throws {
        let server = try LoopbackMinerServer()
        server.holdCoolingWrites()
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); server.stop() }
        let arguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            + (essentials ? ["--ui-test-dashboard-essentials"] : [])
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: arguments)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.errorSummary"].firstMatch.waitForExistence(timeout: 10))
        assertBecomesOnline(miner)
        revealTelemetryControl(miner, in: app)
        miner.tap()
        let cooling = app.buttons["detail.previewControls.cooling"]
        revealTelemetryControl(cooling, in: app)
        cooling.tap()

        let automatic = app.buttons["cooling.mode.automatic"]
        let manual = app.buttons["cooling.mode.manual"]
        let commit = app.buttons["cooling.commit"]
        XCTAssertTrue(commit.waitForExistence(timeout: 5))
        XCTAssertTrue(automatic.isSelected)
        XCTAssertFalse(commit.isEnabled)
        reveal(manual, in: app)
        manual.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.8)).tap()
        XCTAssertTrue(manual.isSelected)
        XCTAssertTrue(commit.isEnabled)
        reveal(commit, in: app)
        let review = app.navigationBars["Review cooling changes"]
        let apply = essentials ? commit : app.buttons["cooling.review.apply"]
        if !essentials {
            XCTAssertEqual(commit.label, "Review Changes")
            commit.tap()
            XCTAssertTrue(review.waitForExistence(timeout: 5))
            let json = app.staticTexts["cooling.review.json"]
            XCTAssertTrue(json.label.contains("\"autofanspeed\""))
            XCTAssertFalse(json.label.contains("manualFanSpeed"), "An unchanged setpoint must not be sent")
            reveal(apply, in: app)
        }
        XCTAssertTrue(server.writes.isEmpty, "Mode selection and review must not send a write")
        XCTAssertEqual(apply.label, "Apply Changes")
        let frame = apply.frame
        apply.tap()
        XCTAssertTrue(apply.wait(for: \.label, toEqual: "Applying…", timeout: 3))
        XCTAssertFalse(apply.isEnabled)
        let applyingFrame = apply.frame
        XCTAssertEqual(applyingFrame.minY, frame.minY, accuracy: 1)
        XCTAssertEqual(applyingFrame.height, frame.height, accuracy: 1)
        XCTAssertFalse(app.descendants(matching: .any)["cooling.progress"].exists)
        XCTAssertEqual(review.exists, !essentials)
        if !essentials { XCTAssertFalse(app.buttons["cooling.review.cancel"].isEnabled) }
        recordScreenshot(essentials ? "Essentials Cooling applying in button" : "Full View Cooling applying in button", app: app)

        let held = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.hasPendingCoolingWrite }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 2), .completed)
        XCTAssertTrue(server.finishCoolingWrite())
        if !essentials { XCTAssertTrue(review.waitForNonExistence(timeout: 5)) }
        let result = app.staticTexts["cooling.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.hasPrefix("Cooling changes verified"))
        XCTAssertFalse(commit.isEnabled)
        XCTAssertTrue(manual.isSelected)

        XCTAssertEqual(server.writes.count, 1)
        let request = try XCTUnwrap(server.writes.first)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.path, "/api/system")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: request.body) as? [String: Int], ["autofanspeed": 0])
    }
    #endif

    func testPauseReviewStaysInFrontAndRequiresExplicitConfirmation() throws {
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        // The fixture deliberately serves HTTP rather than a live WebSocket. Its fallback
        // banner changes the dashboard layout, so don't tap the card while that row is appearing.
        let fallback = app.descendants(matching: .any)["dashboard.errorSummary"].firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 10))
        assertBecomesOnline(miner)
        revealTelemetryControl(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5),
                      "Tapping the visible fixture card must enter miner detail")
        let pause = app.buttons["detail.quick.pause"]
        revealTelemetryControl(pause, in: app)
        pause.tap()

        let requestForm = app.navigationBars["Pause mining"]
        XCTAssertTrue(requestForm.waitForExistence(timeout: 5), "Pause must bring the request form to the foreground")
        let review = app.buttons["endpoint.send"]
        reveal(review, in: app)
        review.tap()
        let reviewBar = app.navigationBars["Review before sending"]
        XCTAssertTrue(reviewBar.waitForExistence(timeout: 5))
        let cancel = reviewBar.buttons["confirmation.cancel"]
        XCTAssertTrue(cancel.isHittable, "The review must own the interactive foreground")
        let method = app.descendants(matching: .any)["confirmation.methodAndPath"].firstMatch
        reveal(method, in: app)
        XCTAssertEqual(method.label, "POST /api/system/pause")
        XCTAssertTrue(app.staticTexts["No request body"].exists)
        XCTAssertTrue(app.staticTexts["This stops mining on this device until you resume."].exists)
        XCTAssertFalse(review.isHittable, "The underlying request form must not receive taps through the sheet")
        assertNoWrites(server, for: 0.5)
        let receipt = XCTAttachment(screenshot: app.screenshot())
        receipt.name = "Full View - exact Pause review in front"
        receipt.lifetime = .keepAlways
        add(receipt)

        cancel.tap()
        XCTAssertTrue(reviewBar.waitForNonExistence(timeout: 5))
        XCTAssertTrue(requestForm.exists)
        assertNoWrites(server, for: 0.5)
        reveal(review, in: app)
        review.tap()
        XCTAssertTrue(reviewBar.waitForExistence(timeout: 5))
        let acknowledgement = app.switches["confirmation.understood"]
        reveal(acknowledgement, in: app)
        XCTAssertEqual(acknowledgement.value as? String, "0", "Cancel must discard the previous review state")
        let send = app.buttons["confirmation.apply"]
        reveal(send, in: app)
        XCTAssertFalse(send.isEnabled)
        reveal(acknowledgement, in: app, direction: .down)
        acknowledgement.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(acknowledgement.value as? String, "1")
        reveal(send, in: app)
        XCTAssertFalse(send.isEnabled, "Acknowledgement alone must never authorize a write")
        let token = app.textFields["confirmation.token"]
        reveal(token, in: app)
        token.tap()
        token.typeText("APPLY")
        assertApplyRevealedWithoutScrolling(send, in: app)
        XCTAssertTrue(send.isEnabled)
        assertNoWrites(server, for: 0.5)
        send.tap()
        XCTAssertTrue(reviewBar.waitForNonExistence(timeout: 5))
        let completion = app.alerts["Request accepted"]
        XCTAssertTrue(completion.waitForExistence(timeout: 10), "Result must appear after the review, not behind it")
        completion.buttons["OK"].tap()
        XCTAssertTrue(requestForm.exists)
        let actual = try XCTUnwrap(server.writes.first)
        XCTAssertEqual(actual.method, "POST")
        XCTAssertEqual(actual.path, "/api/system/pause")
        XCTAssertTrue(actual.body.isEmpty)
        XCTAssertEqual(server.writes.count, 1)
    }

    func testEssentialsPauseShowsPlainForegroundReviewAndExactRequestOnDemand() throws {
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server,
                                              extraArguments: ["--ui-test-dashboard-essentials"])
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.errorSummary"].firstMatch.waitForExistence(timeout: 10))
        assertBecomesOnline(miner)
        revealTelemetryControl(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        let pause = app.buttons["detail.quick.pause"]
        revealTelemetryControl(pause, in: app)
        pause.tap()
        let review = app.buttons["endpoint.send"]
        reveal(review, in: app)
        review.tap()
        let bar = app.navigationBars["Review before sending"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertTrue(bar.buttons["confirmation.cancel"].isHittable)
        XCTAssertFalse(review.isHittable)
        XCTAssertTrue(app.staticTexts["Pause mining?"].exists)
        XCTAssertTrue(app.staticTexts["This stops mining on this device until you resume."].exists)
        let method = app.descendants(matching: .any)["confirmation.methodAndPath"].firstMatch
        XCTAssertFalse(method.exists)
        let details = app.buttons["confirmation.showExactRequest"]
        reveal(details, in: app)
        XCTAssertEqual(details.value as? String, "Collapsed")
        recordScreenshot("Essentials - plain Pause review in front", app: app)
        details.tap()
        reveal(method, in: app)
        XCTAssertEqual(method.label, "POST /api/system/pause")
        XCTAssertTrue(app.staticTexts["No request body"].exists)
        recordScreenshot("Essentials - exact Pause request expanded", app: app)
        bar.buttons["confirmation.cancel"].tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
        assertNoWrites(server, for: 0.5)
    }

    private func revealTelemetryControl(_ control: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            let top = app.navigationBars.firstMatch.frame.maxY + 12
            let bottom = app.frame.maxY - 36
            let center = control.exists ? control.frame.midY : CGFloat.infinity
            if center > top, center < bottom, control.isHittable { return }
            // Scroll outside the interactive telemetry charts.
            let above = center <= top
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: above ? 0.32 : 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: above ? 0.78 : 0.32))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTFail("Could not bring the control into the unobscured viewport: \(control)")
    }

    func testCustomJSONStagesUnknownFieldsButNeverBypassesTypedConfirmation() throws {
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        try launchWithConfiguredReviewFixture(app, server: server)
        assertNoLegacyModeSelector(in: app)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        assertBecomesOnline(miner)
        miner.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        prepareFrequencyRiskAcknowledgement(app: app)
        let advanced = app.buttons["settings.advanced"]
        reveal(advanced, in: app)
        advanced.tap()
        let custom = app.buttons["settings.customJSON"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Raw JSON editors"].exists,
                       "The unified hub must expose one canonical request JSON editor, not a duplicate disclosure.")
        custom.tap()
        let editor = app.textViews["custom_json.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        reveal(editor, in: app)
        assertCustomJSONEditorLayout(app: app, editor: editor, phase: "before focus")
        let draftJSON = #"{"customFeature":{"enabled":true,"counter":18446744073709551615},"# +
            #""frequency":500}"#
        replaceText(editor, with: draftJSON, in: app)
        assertCustomJSONEditorLayout(app: app, editor: editor, phase: "after text entry")
        XCTAssertTrue(server.writes.isEmpty, "Editor layout and text entry must never send a request.")
        try stageAndCancelCustomJSON(app: app, server: server)
    }

    // Retain the existing test name for configured test-plan selectors. The settings hub is now
    // unified: tuning risk acknowledgement is local to the tuning session, while safe hostname
    // changes use the same direct Save action as every other everyday settings entry point.
    func testUnifiedSettingsDirectApplyHostnameWrite() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        try addFixture(address: address, app: app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        assertBecomesOnline(miner)
        miner.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        prepareFrequencyRiskAcknowledgement(app: app)
        try verifyUnifiedHostnameDirectApply(app: app, server: server)
        verifyBackgroundRetainsRiskAcknowledgementWithoutExtraWrite(app: app, server: server)
    }

    func testOfflineRelaunchShowsCachedSettingsButLocksChanges() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        try addFixture(address: address, app: app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        expectation(for: NSPredicate(format: "label CONTAINS[c] 'online'"), evaluatedWith: miner)
        waitForExpectations(timeout: 10)
        app.terminate()
        server.stop()
        app.launchArguments = ["--ui-testing", "--ui-test-preserve-storage"]
        app.launch()
        XCTAssertTrue(miner.waitForExistence(timeout: 10), "Saved miner must survive offline relaunch")
        reveal(miner, in: app)
        XCTAssertTrue(miner.label.contains("Unreachable"), miner.label)
        miner.tap()
        let notice = app.descendants(matching: .any).matching(identifier: "miner.offlineReadOnly").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("Last known settings"), notice.label)
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.reportedState"].waitForExistence(timeout: 5))
        let source = app.descendants(matching: .any)
            .matching(identifier: "settings.reportedState.source").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.label.contains("Cached reading"), source.label)
        XCTAssertTrue(source.label.contains("read only"), source.label)
        let easyHostname = app.textFields["settings.quick.hostname"]
        reveal(easyHostname, in: app)
        XCTAssertEqual(easyHostname.value as? String, "loopback-before")
        XCTAssertFalse(easyHostname.isEnabled)
        let easyReview = app.buttons["settings.quick.review"]
        reveal(easyReview, in: app)
        XCTAssertFalse(easyReview.isEnabled)
        XCTAssertTrue(server.writes.isEmpty)
        let general = app.buttons["settings.general"]
        reveal(general, in: app)
        general.tap()
        let hostname = app.textFields["Network hostname"]
        reveal(hostname, in: app)
        XCTAssertEqual(hostname.value as? String, "loopback-before")
        XCTAssertFalse(hostname.isEnabled, "Cached settings may be inspected but not edited offline")
        let review = app.buttons["Review hostname change"].exists
            ? app.buttons["Review hostname change"] : app.buttons["Save name"]
        reveal(review, in: app)
        XCTAssertFalse(review.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Cached offline hostname remains visible and read only"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(server.writes.isEmpty)
    }

    /// Hostname is in the pre-vetted safe-field allowlist, so in
    /// the default unified flow it now applies directly like a normal settings toggle instead of
    /// requiring the review-and-typed-APPLY gate. This still verifies the underlying safety
    /// invariants that mattered before the UX change: exactly one PATCH, the correct body, and a
    /// telemetry refresh afterward — just without the now-removed friction for this safe field.
    func testRealModeHostnameWriteAppliesDirectlyForSafeField() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()

        try addFixture(address: address, app: app, server: server)
        XCTAssertTrue(server.writes.isEmpty, "Connecting and reading telemetry must not write.")
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        let live = NSPredicate(format: "label CONTAINS[c] 'online'")
        expectation(for: live, evaluatedWith: miner)
        waitForExpectations(timeout: 10)
        miner.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 5))
        let general = app.buttons["settings.general"]
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        reveal(general, in: app)
        general.tap()

        let hostname = app.textFields["Network hostname"]
        reveal(hostname, in: app)
        XCTAssertEqual(hostname.value as? String, "loopback-before",
                       "The form must be populated from the live fixture response.")
        replaceText(hostname, with: "loopback-after", in: app)
        let saveButton = app.buttons["Save name"]
        reveal(saveButton, in: app)
        XCTAssertTrue(saveButton.isEnabled, "Real-mode save must not inherit the demo lock.")
        XCTAssertFalse(app.buttons["Review hostname change"].exists,
                       "Safe quick changes keep the direct-save path without mandatory JSON review.")
        XCTAssertTrue(server.writes.isEmpty, "Editing a hostname must not write.")
        saveButton.tap()
        try verifyDirectApplySendsPatch(app: app, server: server)
    }
}
