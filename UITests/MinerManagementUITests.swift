import XCTest

@MainActor
final class MinerManagementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAutomaticModelNameOfflineRenameRelaunchAndConfirmedRemovalAreLocal() throws {
        let server = try LoopbackMinerServer()
        let infoJSON = #"{"hostname":"bitaxe","ASICModel":"BM1370","boardVersion":"602","hashRate":1250,"power":19}"#
        server.setInfoResponse(status: 200, json: infoJSON)
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        addMiner(address, name: nil, app: app)
        let miners = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'"))
        let miner = miners.firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 10))
        waitForLabel("Gamma", on: miner)
        miner.tap()
        let title = app.descendants(matching: .any)["detail.minerTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        waitForLabel("Gamma", on: title)

        server.setInfoResponse(status: 503, json: #"{"error":"Offline fixture"}"#)
        app.buttons["Refresh"].tap()
        let offlineText = "label CONTAINS[c] 'offline' OR label CONTAINS[c] '503' OR label CONTAINS[c] 'cached'"
        let offline = app.staticTexts.matching(NSPredicate(format: offlineText))
        XCTAssertTrue(offline.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["detail.manageMiner"].tap()
        app.buttons["Rename in app"].firstMatch.tap()
        let rename = app.alerts["Rename miner"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        let name = rename.textFields.firstMatch
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (name.value as? String)?.count ?? 0))
        name.typeText("Desk Gamma")
        rename.buttons["Save"].tap()
        waitForLabel("Desk Gamma", on: title)
        capture("Offline local rename keeps the current miner title", app)
        XCTAssertTrue(server.writes.isEmpty)

        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-test-preserve-storage"]
        app.launch()
        XCTAssertTrue(miners.firstMatch.waitForExistence(timeout: 10))
        waitForLabel("Desk Gamma", on: miners.firstMatch)
        miners.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.manageMiner"].waitForExistence(timeout: 5))
        app.buttons["detail.manageMiner"].tap()
        app.buttons["Remove from fleet"].firstMatch.tap()
        let confirm = app.sheets.buttons["Remove from fleet"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Removal must require confirmation")
        app.sheets.buttons["Keep miner"].tap()
        XCTAssertTrue(title.exists, "Cancelling removal must retain the miner")
        removeMinerAndVerifyPersistence(miners, app: app, server: server)
    }

    private func removeMinerAndVerifyPersistence(
        _ miners: XCUIElementQuery,
        app: XCUIApplication,
        server: LoopbackMinerServer
    ) {
        app.buttons["detail.manageMiner"].tap()
        app.buttons["Remove from fleet"].firstMatch.tap()
        let confirm = app.sheets.buttons["Remove from fleet"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        XCTAssertEqual(miners.count, 0)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 10))
        XCTAssertEqual(miners.count, 0, "Removal must persist across relaunch")
        XCTAssertTrue(server.writes.isEmpty, "Names and removal must never PATCH, reset or restart the miner")
    }

    func testCustomNameAtAddWinsOverModelAndDemoManagementIsDisabled() throws {
        let server = try LoopbackMinerServer()
        let demoJSON = #"{"hostname":"bitaxe","ASICModel":"BM1368","boardVersion":"402","hashRate":638}"#
        server.setInfoResponse(status: 200, json: demoJSON)
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        addMiner(address, name: "Office Supra", app: app)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 10))
        waitForLabel("Office Supra", on: miner)
        miner.tap()
        XCTAssertTrue(app.buttons["detail.manageMiner"].waitForExistence(timeout: 5))
        app.buttons["Refresh"].tap()
        waitForLabel("Office Supra", on: app.descendants(matching: .any)["detail.minerTitle"])
        app.terminate()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        XCTAssertTrue(miner.waitForExistence(timeout: 10))
        miner.tap()
        XCTAssertTrue(app.buttons["detail.manageMiner"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["detail.manageMiner"].isEnabled)
        XCTAssertTrue(server.writes.isEmpty)
    }

    private func addMiner(_ address: String, name: String?, app: XCUIApplication) {
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 10))
        app.buttons["dashboard.addMiner"].tap()
        if let name {
            let field = app.textFields["addMiner.name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name + "\n")
        }
        let field = app.textFields["addMiner.address"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(address + "\n")
    }

    private func waitForLabel(_ text: String, on element: XCUIElement) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
