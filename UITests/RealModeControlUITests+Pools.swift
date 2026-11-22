import XCTest

#if HASHFLEET_LIVE_REVIEW
extension RealModeControlUITests {
    func testEssentialsPoolsSaveOnlyTheReviewedConnectionAndVerifyReadback() throws {
        continueAfterFailure = false
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        server.setInfoResponse(status: 200, json: try poolFixture(port: 3333))
        server.acceptPoolWrite(readbackJSON: try poolFixture(port: 4444))
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: ["--ui-test-dashboard-essentials"])
        openPools(app)

        let primary = app.buttons["settings.pools.primary"]
        let fallback = app.buttons["settings.pools.fallback"]
        XCTAssertTrue(primary.isHittable && fallback.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["settings.pools.slot"].exists)
        recordScreenshot("Essentials normal pool connections", app: app)
        fallback.tap()
        let backupBar = app.navigationBars["Fallback pool"]
        XCTAssertTrue(backupBar.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["settings.pool.server"].value as? String, "backup.example.invalid")
        XCTAssertEqual(app.textFields["settings.pool.port"].value as? String, "5555")
        backupBar.buttons["BackButton"].tap()
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.tap()

        let port = app.textFields["settings.pool.port"]
        XCTAssertTrue(port.waitForExistence(timeout: 5))
        XCTAssertEqual(port.value as? String, "3333")
        XCTAssertEqual(app.textFields["settings.pool.server"].value as? String, "primary.example.invalid")
        XCTAssertEqual(app.textFields["settings.pool.worker"].value as? String, "sample.worker")
        XCTAssertEqual(app.secureTextFields["settings.pool.password"].value as? String, "Leave blank to keep it")
        recordScreenshot("Essentials ordinary Primary pool form", app: app)
        XCTAssertTrue(server.writes.isEmpty)
        replaceText(port, with: "4444", in: app)
        app.buttons["settings.pool.keyboardDone"].tap()
        let review = app.buttons["settings.pool.review"]
        reveal(review, in: app)
        review.tap()
        let alert = app.alerts["Save primary pool?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "primary.example.invalid:4444")).firstMatch.exists)
        XCTAssertTrue(server.writes.isEmpty)
        alert.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertEqual(port.value as? String, "4444")
        XCTAssertTrue(server.writes.isEmpty)
        review.tap()
        alert.buttons["settings.pool.confirm"].firstMatch.tap()

        let saved = app.descendants(matching: .any)["settings.pool.saved"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(saved.label.contains("saved and verified"))
        let request = try XCTUnwrap(server.writes.first)
        XCTAssertEqual(server.writes.count, 1)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.path, "/api/system")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["pools"])
        let records = try XCTUnwrap(payload["pools"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(NSDictionary(dictionary: try XCTUnwrap(records.first)),
                       NSDictionary(dictionary: poolRecord(id: 5, host: "primary.example.invalid", port: 4444)))
        let writesBefore = server.journal.prefix { $0.method != "PATCH" }
        XCTAssertEqual(writesBefore.last?.path, "/api/system/info")
        XCTAssertTrue(server.journal.dropFirst(writesBefore.count + 1).contains { $0.method == "GET" && $0.path == "/api/system/info" })
    }

    func testEssentialsPoolsKeepAllFourFieldsClearAndDoneDoesNotSave() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        server.setInfoResponse(status: 200, json: try poolFixture(port: 3333))
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: ["--ui-test-dashboard-essentials"])
        openPools(app)
        app.buttons["settings.pools.primary"].tap()
        let nav = app.navigationBars["Primary pool"]
        XCTAssertTrue(nav.waitForExistence(timeout: 5))
        let keyboard = app.keyboards.firstMatch
        let done = nav.buttons["settings.pool.keyboardDone"]
        let serverField = app.textFields["settings.pool.server"]
        let port = app.textFields["settings.pool.port"]
        let worker = app.textFields["settings.pool.worker"]
        let password = app.secureTextFields["settings.pool.password"]

        reveal(serverField, in: app)
        serverField.tap()
        assertFleetEditingFieldAboveKeyboard(serverField, in: app, navigation: nav)
        serverField.typeText("\n")
        assertFleetEditingFieldAboveKeyboard(port, in: app, navigation: nav)
        replaceText(port, with: "4444", in: app)
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertEqual(port.value as? String, "4444")
        XCTAssertEqual(serverField.value as? String, "primary.example.invalid")

        reveal(worker, in: app)
        replaceText(worker, with: "keyboard.fixture", in: app)
        assertFleetEditingFieldAboveKeyboard(worker, in: app, navigation: nav)
        worker.typeText("\n")
        assertFleetEditingFieldAboveKeyboard(password, in: app, navigation: nav)
        password.typeText("sample-edit")
        recordScreenshot("Essentials secure pool input above keyboard", app: app)
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(password.value as? String, "Leave blank to keep it")
        XCTAssertEqual(worker.value as? String, "keyboard.fixture")
        XCTAssertFalse(app.alerts["Save primary pool?"].exists)
        XCTAssertTrue(server.writes.isEmpty)
    }

    func testEssentialsPoolsDoNotWriteWhenRoleChangedSinceReview() throws {
        continueAfterFailure = false
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        server.setInfoResponse(status: 200, json: try poolFixture(port: 3333))
        try launchWithConfiguredReviewFixture(app, server: server, extraArguments: [
            "--ui-test-dashboard-essentials", "--ui-test-loopback-manual-refresh"
        ])
        openPools(app)
        app.buttons["settings.pools.primary"].tap()
        let port = app.textFields["settings.pool.port"]
        reveal(port, in: app)
        replaceText(port, with: "4444", in: app)
        app.buttons["settings.pool.keyboardDone"].tap()
        let review = app.buttons["settings.pool.review"]
        reveal(review, in: app)
        review.tap()
        let alert = app.alerts["Save primary pool?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        server.setInfoResponse(status: 200, json: try poolFixture(port: 3333, primaryID: 2))
        alert.buttons["settings.pool.confirm"].firstMatch.tap()
        let error = app.descendants(matching: .any)["settings.pool.error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("Nothing was sent"))
        XCTAssertFalse(review.isEnabled)
        XCTAssertTrue(server.writes.isEmpty)
    }

    func testFullViewStillHasTheAdvancedPoolEditor() throws {
        continueAfterFailure = false
        let server = try LoopbackMinerServer()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        server.setInfoResponse(status: 200, json: try poolFixture(port: 3333, includeLegacyAliases: true))
        try launchWithConfiguredReviewFixture(app, server: server)
        openPools(app)
        let firmwarePickerLabel = app.staticTexts["Firmware API"]
        reveal(firmwarePickerLabel, in: app)
        XCTAssertFalse(app.descendants(matching: .any)["settings.pools.essentials"].exists)
        XCTAssertTrue(server.writes.isEmpty)
    }

    private func openPools(_ app: XCUIApplication) {
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        // On shorter phones, the chart and attention summary can leave this row outside the viewport.
        revealFleetControl(card, in: app)
        assertBecomesOnline(card)
        card.tap()
        let settings = app.buttons["detail.previewControls.settings"]
        reveal(settings, in: app)
        settings.tap()
        let pools = app.buttons["settings.preview.pools"]
        XCTAssertTrue(pools.waitForExistence(timeout: 5))
        pools.tap()
        XCTAssertTrue(app.navigationBars["Pools"].waitForExistence(timeout: 5))
    }

    private func poolFixture(port: Int, primaryID: Int = 5, includeLegacyAliases: Bool = false) throws -> String {
        var payload: [String: Any] = [
            "hostname": "Loopback fixture", "version": "fixture-pools", "macAddr": "02:00:00:00:00:01",
            "ASICModel": "BM1370", "hashRate": 1234, "power": 19.5, "temp": 51, "fanspeed": 65, "fanrpm": 4200,
            "voltage": 5000, "coreVoltage": 1100, "frequency": 500, "uptimeSeconds": 1200,
            "primaryPoolIndex": primaryID, "secondaryPoolIndex": primaryID == 5 ? 2 : 5,
            "pools": [poolRecord(id: 2, host: "backup.example.invalid", port: 5555),
                      poolRecord(id: 5, host: "primary.example.invalid", port: port)]
        ]
        if includeLegacyAliases {
            payload["stratumURL"] = "primary.example.invalid"
            payload["fallbackStratumURL"] = "backup.example.invalid"
        }
        guard let json = String(bytes: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return json
    }

    private func poolRecord(id: Int, host: String, port: Int) -> [String: Any] {
        ["id": id, "stratumURL": host, "stratumPort": port, "stratumUser": "sample.worker", "stratumPassword": "*****",
         "stratumProtocol": "SV1", "stratumSuggestedDifficulty": 32, "stratumExtranonceSubscribe": true,
         "stratumTLS": 1, "stratumCert": "", "stratumDecodeCoinbase": true, "stratumShareWarning": false,
         "stratumV2ChannelType": "extended", "stratumV2AuthorityPubkey": "", "stratumV2RequireAuth": false,
         "rotationEnabled": false, "rotationWeight": 7]
    }
}
#endif
