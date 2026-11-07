import XCTest

extension HashFleetUITests {
    func testFleetToolsNativeSharingAndImportCancellation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        openFleetSettings(in: app)
        let reports = app.buttons["monitoring.reports"]
        reveal(reports, in: app)
        reports.tap()
        for identifier in ["fleetReport.sharePDF", "fleetReport.shareCSV"] {
            let share = app.buttons[identifier]
            reveal(share, in: app)
            share.tap()
            let close = app.buttons["Close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
            recordScreenshot(identifier + " native activity sheet", app: app)
            close.tap()
            XCTAssertTrue(app.navigationBars["Fleet Reports"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["fleetReport.exportError"].exists)
        }
        app.navigationBars["Fleet Reports"].buttons.element(boundBy: 0).tap()
        let backup = app.buttons["monitoring.backup"]
        reveal(backup, in: app)
        backup.tap()
        app.buttons["fleetBackup.import"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
        recordScreenshot("Fleet backup native document picker", app: app)
        cancel.tap()
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["fleetBackup.confirm"].exists)
        XCTAssertFalse(app.buttons["fleetBackup.export"].isEnabled)
    }

    func testFleetToolsPrivateAddressRequiresRevealAndRehidesAfterBackground() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        defer { app.terminate() }
        let miner = minerButton(named: "Workshop Gamma", in: app)
        reveal(miner, in: app)
        miner.tap()
        let identity = app.buttons["detail.identityDisclosure"]
        reveal(identity, in: app)
        identity.tap()
        let show = app.buttons["detail.privateAddress.reveal"]
        reveal(show, in: app)
        XCTAssertFalse(app.staticTexts["detail.privateAddress.value"].exists)
        XCTAssertFalse(app.buttons["detail.privateAddress.copy"].exists)
        show.tap()
        XCTAssertTrue(app.staticTexts["detail.privateAddress.value"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.privateAddress.copy"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["detail.privateAddress.value"].exists)
        XCTAssertFalse(app.buttons["detail.privateAddress.copy"].exists)
    }

    func testFleetToolsReportPreviewAndBackupDemoSafety() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        openFleetSettings(in: app)
        let reports = app.buttons["monitoring.reports"]
        reveal(reports, in: app)
        reports.tap()
        XCTAssertTrue(app.navigationBars["Fleet Reports"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["fleetReport.demo"].exists)
        let preview = app.buttons["fleetReport.previewPDF"]
        reveal(preview, in: app)
        preview.tap()
        XCTAssertTrue(app.navigationBars["Snapshot PDF"].waitForExistence(timeout: 5))
        recordScreenshot("Fleet snapshot PDF", app: app)
        app.navigationBars["Snapshot PDF"].buttons["Done"].tap()
        app.navigationBars["Fleet Reports"].buttons.element(boundBy: 0).tap()
        let backup = app.buttons["monitoring.backup"]
        reveal(backup, in: app)
        backup.tap()
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["fleetBackup.export"].isEnabled)
        XCTAssertTrue(app.buttons["fleetBackup.import"].isEnabled)
        XCTAssertFalse(app.buttons["fleetBackup.confirm"].exists)
        recordScreenshot("Fleet backup privacy and demo guard", app: app)
    }

    func testFleetToolsThermalPageNeverConfiguresDemoMiners() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        openFleetSettings(in: app)
        let thermal = app.buttons["monitoring.temperatureAlerts"]
        reveal(thermal, in: app)
        thermal.tap()
        XCTAssertTrue(app.navigationBars["Temperature alerts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No miners yet"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "temperatureAlerts.miner.")).count, 0)
        recordScreenshot("Thermal alerts real-fleet guard", app: app)
    }

    func testFleetToolsEnergyPageUsesExplicitEstimateCopy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        openFleetSettings(in: app)
        let energy = app.buttons["monitoring.energy"]
        reveal(energy, in: app)
        energy.tap()
        let rate = app.textFields["energy.rateField"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        rate.tap()
        if let previous = rate.value as? String, previous != "Price per kWh" {
            rate.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        rate.typeText("0.15")
        app.buttons["energy.save"].tap()
        XCTAssertTrue(app.staticTexts["energy.feedback"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["energy.feedback"].label.contains("Rate saved"))
        let dailyCost = app.descendants(matching: .any)["energy.dailyCostValue"]
        reveal(dailyCost, in: app)
        XCTAssertTrue(dailyCost.exists, app.debugDescription)
        XCTAssertTrue(dailyCost.label.contains("$"), dailyCost.debugDescription)
        let disclaimer = app.descendants(matching: .any)["energy.disclaimerLabel"]
        reveal(disclaimer, in: app)
        XCTAssertTrue(disclaimer.exists)
        recordScreenshot("Electricity estimate assumptions", app: app)
    }
}
