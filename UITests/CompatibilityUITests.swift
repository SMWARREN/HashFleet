import XCTest

/// Uses actual URLSession requests against an IPv4-loopback-only HTTP fixture.
/// Normal foreground Info polling is allowed. ASIC is checked automatically once
/// after recognized Info, then only on an explicit retry or identity change.
@MainActor
final class CompatibilityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testManualCheckDistinguishesUnsupportedUnknownModelAndAuthenticationFailure() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].waitForExistence(timeout: 10))
        app.buttons["dashboard.addMiner"].tap()
        let name = app.textFields["addMiner.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Compatibility fixture\n")
        let addressField = app.textFields["addMiner.address"]
        addressField.tap()
        addressField.typeText(address + "\n")
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        let onlinePredicate = NSPredicate(format: "label CONTAINS[c] 'online'")
        let online = XCTNSPredicateExpectation(predicate: onlinePredicate, object: miner)
        XCTAssertEqual(XCTWaiter.wait(for: [online], timeout: 10), .completed)
        miner.tap()
        let compatibility = app.buttons["detail.compatibility"]
        reveal(compatibility, in: app)
        compatibility.tap()
        XCTAssertTrue(app.navigationBars["Check compatibility"].waitForExistence(timeout: 5))
        // The normal Info poll triggers one safe ASIC read. Opening the page adds no requests.
        assertSummary("Partly supported", in: app)
        let check = app.buttons["compatibility.check"]
        reveal(check, in: app)
        XCTAssertEqual(asicReads(server), 1)
        XCTAssertTrue(server.writes.isEmpty)
        capture("Compatibility-partial-support", app: app)

        runUnknownModelStep(server: server, app: app, check: check)
        runAuthenticationFailureStep(server: server, app: app, check: check)
    }

    func testDemoCompatibilityDoesNotInventProbeResults() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        miner.tap()
        let compatibility = app.buttons["detail.compatibility"]
        reveal(compatibility, in: app)
        compatibility.tap()
        assertSummary("Demo preview", in: app)
        let check = app.buttons["compatibility.check"]
        reveal(check, in: app)
        XCTAssertFalse(check.isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["compatibility.infoStatus"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["compatibility.asicStatus"].exists)
    }

    func testMissingFieldsAndReportedReferencesRenderAcrossNativeSettings() throws {
        let server = try LoopbackMinerServer()
        let infoJSON = #"{"hostname":"partial-fixture","version":"fixture","ASICModel":"FutureASIC","# +
            #""frequency":500,"coreVoltage":1150}"#
        server.setInfoResponse(status: 200, json: infoJSON)
        setFutureBoardASICResponse(server)
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        try openFixture(server, in: app)

        let notReportedPredicate = NSPredicate(format: "label CONTAINS[c] 'not reported'")
        let notReported = app.staticTexts.matching(notReportedPredicate).firstMatch
        XCTAssertTrue(notReported.waitForExistence(timeout: 5),
                      "A missing fleet metric must not appear as a zero reading.")
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.staticTexts["Not reported"].waitForExistence(timeout: 5))
        // Share counters render as separate rows. Missing counters must read "not reported", never zero.
        for id in ["accepted", "rejected"] {
            let row = app.descendants(matching: .any).matching(identifier: "detail.shares.\(id)").firstMatch
            reveal(row, in: app)
            XCTAssertTrue(row.label.localizedCaseInsensitiveContains("not reported"), "\(id): \(row.label)")
        }
        let compatibility = app.buttons["detail.compatibility"]
        reveal(compatibility, in: app)
        compatibility.tap()
        let check = app.buttons["compatibility.check"]
        reveal(check, in: app)
        assertSummary("Detected ESP-Miner-compatible API", in: app)
        let checkedAt = app.descendants(matching: .any).matching(identifier: "compatibility.checkedAt").firstMatch
        reveal(checkedAt, in: app)
        XCTAssertTrue(checkedAt.exists)
        XCTAssertTrue(checkedAt.label.contains("Checked"))
        let dated = app.staticTexts["From this check, not live. Check again after firmware changes."]
        reveal(dated, in: app)
        XCTAssertTrue(dated.isHittable)
        let model = app.staticTexts["Device model, FutureBoard"]
        reveal(model, in: app)
        XCTAssertTrue(model.exists)
        let rawInfo = app.buttons["compatibility.rawInfo"]
        reveal(rawInfo, in: app)
        XCTAssertTrue(app.buttons["compatibility.rawAsic"].exists)
        XCTAssertEqual(asicReads(server), 1)
        back(in: app)

        verifyMissingSettingsFields(app: app)
        verifyReportedReferences(app: app, server: server)
    }

    func testCatalogStatusesAndLastKnownTelemetryRenderWithoutInventingSupport() throws {
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        try openFixture(server, in: app)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        miner.tap()
        let compatibility = app.buttons["detail.compatibility"]
        reveal(compatibility, in: app)
        compatibility.tap()
        let check = app.buttons["compatibility.check"]
        reveal(check, in: app)
        assertSummary("Partly supported", in: app)
        back(in: app)
        let explorer = app.buttons["detail.endpointExplorer"]
        reveal(explorer, in: app)
        explorer.tap()
        for (path, status) in [("/api/system/info", "Detected: Supported"),
                               ("/api/system/asic", "Detected: Not supported"),
                               ("restart", "Detected ESP-Miner-compatible API · support unverified")] {
            filterCatalog(path, in: app)
            XCTAssertTrue(app.staticTexts[status].waitForExistence(timeout: 5), "Expected \(status) for \(path).")
        }
        back(in: app)
        // The next actual poll fails. Historical values must remain explicitly last-known, not live.
        server.setInfoResponse(status: 503, json: #"{"error":"temporarily unavailable"}"#)
        app.navigationBars.buttons["Refresh"].tap()
        let unavailable = app.staticTexts.matching(identifier: "UNAVAILABLE").firstMatch
        reveal(unavailable, in: app, towardTop: true)
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10))
        let lastKnown = app.staticTexts["LAST KNOWN HASHRATE"]
        reveal(lastKnown, in: app)
        XCTAssertTrue(lastKnown.isHittable)
        XCTAssertFalse(app.staticTexts["LATEST HASHRATE"].exists)
        XCTAssertTrue(server.writes.isEmpty)
        XCTAssertEqual(asicReads(server), 1)
    }
}
