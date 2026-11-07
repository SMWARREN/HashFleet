import XCTest

/// Fixture navigation and assertion helpers for CompatibilityUITests.
extension CompatibilityUITests {
    /// An unknown device model with a recognizable typed response is supported.
    /// The app must not reject it because it is absent from an internal model list.
    func runUnknownModelStep(server: LoopbackMinerServer, app: XCUIApplication, check: XCUIElement) {
        setFutureBoardASICResponse(server)
        reveal(check, in: app)
        check.tap()
        assertSummary("Detected ESP-Miner-compatible API", in: app)
        XCTAssertEqual(asicReads(server), 2)
        XCTAssertTrue(server.writes.isEmpty)
        capture("Compatibility-both-reads-supported", app: app)
    }

    /// Authentication failure is not evidence that hardware is unsupported.
    /// Response text must not leak through a friendly status summary.
    func runAuthenticationFailureStep(server: LoopbackMinerServer, app: XCUIApplication, check: XCUIElement) {
        server.setASICResponse(status: 401, json: #"{"error":"private-fixture-token-do-not-display"}"#)
        reveal(check, in: app)
        check.tap()
        assertSummary("Check incomplete", in: app)
        XCTAssertEqual(asicReads(server), 3)
        let retry = app.buttons["compatibility.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        let leak = NSPredicate(format: "label CONTAINS 'private-fixture-token-do-not-display'")
        XCTAssertFalse(app.staticTexts.containing(leak).firstMatch.exists)

        server.setASICResponse(status: 200, json: "{}")
        reveal(retry, in: app)
        retry.tap()
        let fourthRead = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.asicReads(server) == 4 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fourthRead], timeout: 10), .completed)
        assertSummary("Check incomplete", in: app)
        XCTAssertTrue(server.writes.isEmpty, "A compatibility check must never mutate even a loopback miner.")
        assertOnlyReadPaths(server)
    }

    func setFutureBoardASICResponse(_ server: LoopbackMinerServer) {
        let json = #"{"ASICModel":"FutureASIC","deviceModel":"FutureBoard","defaultFrequency":525,"# +
            #""defaultVoltage":1150,"frequencyOptions":[400,525],"voltageOptions":[1100,1150]}"#
        server.setASICResponse(status: 200, json: json)
    }

    func verifyMissingSettingsFields(app: XCUIApplication) {
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app, towardTop: true)
        settings.tap()
        XCTAssertFalse(app.textFields["Network hostname"].exists, "The root remains categories rather than a wall of controls.")
        app.buttons["settings.general"].tap()
        assertMissingField("statsFrequency", in: app)
        XCTAssertEqual(app.textFields["Network hostname"].value as? String, "partial-fixture")
        back(in: app)

        app.buttons["settings.cooling"].tap()
        assertMissingField("autofanspeed", in: app)
        assertMissingField("temptarget", in: app)
        assertMissingField("minFanSpeed", in: app)
        let automatic = app.switches["Automatic fan control"]
        reveal(automatic, in: app, towardTop: true)
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        assertMissingField("manualFanSpeed", in: app)
        back(in: app)

        app.buttons["settings.display"].tap()
        for key in ["rotation", "invertscreen", "displayTimeout"] { assertMissingField(key, in: app) }
        back(in: app)
    }

    func verifyReportedReferences(app: XCUIApplication, server: LoopbackMinerServer) {
        let tuning = app.buttons["settings.tuning"]
        reveal(tuning, in: app)
        tuning.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        let references = app.descendants(matching: .any)["tuningSession.references"]
        reveal(references, in: app)
        let option = app.staticTexts["525 MHz"]
        reveal(option, in: app)
        XCTAssertTrue(option.isHittable)
        XCTAssertEqual(asicReads(server), 1, "Opening reference details must reuse the automatic compatibility read.")
        XCTAssertFalse(app.textFields["tuning.frequency"].exists)
        let review = app.buttons["tuningSession.jump.apply"]
        XCTAssertTrue(review.waitForExistence(timeout: 5), app.debugDescription)
        review.tap()
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.payload"].waitForExistence(timeout: 5),
                      app.debugDescription)
        XCTAssertTrue(server.writes.isEmpty)
        assertOnlyReadPaths(server)
    }

    func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func assertOnlyReadPaths(_ server: LoopbackMinerServer) {
        // Foreground monitoring also reads the firmware scoreboard. It is a GET, never a write.
        let readPaths = ["/api/system/info", "/api/system/asic", "/api/ws/live", "/api/system/scoreboard"]
        XCTAssertTrue(server.journal.allSatisfy {
            $0.method == "GET" && readPaths.contains($0.path)
        }, "Unexpected request: \(server.journal.map { "\($0.method) \($0.path)" })")
    }

    func openFixture(_ server: LoopbackMinerServer, in app: XCUIApplication) throws {
        let address = try server.start()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].waitForExistence(timeout: 10))
        app.buttons["dashboard.addMiner"].tap()
        let name = app.textFields["addMiner.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Output acceptance\n")
        let addressField = app.textFields["addMiner.address"]
        addressField.tap()
        addressField.typeText(address + "\n")
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        let online = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1 of 1 online'")).firstMatch
        XCTAssertTrue(online.waitForExistence(timeout: 10))
    }

    func back(in app: XCUIApplication) {
        // Search mode inserts Cancel before the navigation back button. Never select by index.
        let closeSearch = app.navigationBars.buttons["Close"]
        if closeSearch.exists { closeSearch.tap() }
        let button = app.navigationBars.buttons["BackButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    func assertMissingField(_ key: String, in app: XCUIApplication) {
        let format = "label CONTAINS %@ AND label BEGINSWITH 'This miner did not report'"
        let note = app.staticTexts.matching(NSPredicate(format: format, "(\(key))")).firstMatch
        reveal(note, in: app)
        XCTAssertTrue(note.label.contains("not proof the firmware rejects it"))
    }

    func filterCatalog(_ text: String, in app: XCUIApplication) {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        if let value = search.value as? String, value != search.placeholderValue {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        search.typeText(text + "\n")
    }

    func asicReads(_ server: LoopbackMinerServer) -> Int {
        server.journal.filter { $0.method == "GET" && $0.path == "/api/system/asic" }.count
    }

    func assertSummary(_ text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let summary = app.descendants(matching: .any).matching(identifier: "compatibility.status").firstMatch
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text),
                                                    object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
                       "Expected compatibility summary: \(text)", file: file, line: line)
    }

    func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.25 : 0.65))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.65 : 0.25))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        if !element.exists || !element.isHittable {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Unreachable output hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Unreachable output screen"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Control must be reachable: \(element)")
    }
}
