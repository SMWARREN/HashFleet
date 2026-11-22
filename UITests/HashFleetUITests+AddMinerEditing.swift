import XCTest
import UIKit

/// Onboarding layout and editing regressions.
extension HashFleetUITests {
    func testManualEntryKeyboardAndButtonsInBothAppearances() throws {
        XCUIDevice.shared.orientation = .portrait
        try exerciseManualEntryWithKeyboard(light: true, layout: "portrait")
        try exerciseManualEntryWithKeyboard(light: false, layout: "portrait")
    }

    func testManualEntryKeyboardAndButtonsInLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        try exerciseManualEntryWithKeyboard(light: false, layout: "landscape")
    }

    func testFirstMinerHeadingHasSpaceBeforeOnboarding() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        for (name, options) in [
            ("Full View", [String]()),
            ("Essentials, largest text", ["--ui-test-dashboard-essentials", "--ui-test-light-appearance",
                                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        ] {
            app.launchArguments = ["--ui-testing", "--ui-test-reduce-motion"] + options
            app.launch()
            assertFirstMinerHeadingClearance(in: app, mode: name)
            app.terminate()
        }
    }

    private func assertFirstMinerHeadingClearance(in app: XCUIApplication, mode: String) {
        let heading = app.descendants(matching: .any)["dashboard.firstMinerHeading"]
        let bitsy = app.descendants(matching: .any)["onboarding.bitsy"]
        XCTAssertTrue(heading.waitForExistence(timeout: 8))
        XCTAssertTrue(heading.label.contains("Good things start with a single miner."))
        XCTAssertTrue(bitsy.waitForExistence(timeout: 5))
        XCTAssertTrue(bitsy.isHittable)
        // Bitsy begins 26 points inside the card. Measure only the gap outside it.
        let visibleMargin = bitsy.frame.minY - 26 - heading.frame.maxY
        XCTAssertGreaterThanOrEqual(visibleMargin, 27, "\(mode) caption-to-card margin")
        recordScreenshot("First miner caption margin, \(mode)", app: app)
    }

    func testPendingRecordsLeaveAddMinerInputsAboveKeyboard() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion",
                               "--ui-test-celebration=session", "--ui-test-queue-celebration"]
        app.launch()
        defer { app.terminate() }
        let later = app.buttons["celebration.reviewLater"]
        XCTAssertTrue(later.waitForExistence(timeout: 10))
        later.tap()
        let pendingRecords = app.buttons["celebration.queue.resume"]
        XCTAssertTrue(pendingRecords.waitForExistence(timeout: 5))
        XCTAssertEqual(pendingRecords.value as? String, "1")

        let sheetBar = openAddMinerForRecordKeyboardTest(in: app)
        let scroll = app.scrollViews["addMiner.formScroll"]
        let name = app.textFields["addMiner.name"]
        revealManualEntryControl(name, in: scroll, below: sheetBar, app: app)
        name.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        assertAddMinerFieldIsUnobscured(name, keyboard: keyboard, pendingRecords: pendingRecords)
        name.typeText("Desk fixture\n")
        let address = app.textFields["addMiner.address"]
        assertAddMinerFieldIsUnobscured(address, keyboard: keyboard, pendingRecords: pendingRecords)
        address.typeText("fixture.invalid")
        XCTAssertEqual(address.value as? String, "fixture.invalid")
        recordScreenshot("Add Miner field clear of keyboard with a record waiting", app: app)
        sheetBar.buttons["addMiner.keyboardDone"].tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(pendingRecords.isHittable)
        XCTAssertEqual(pendingRecords.value as? String, "1")
    }

    func testSessionBestClosesAddMinerKeyboardAndKeepsDraft() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion",
                               "--ui-test-celebration=session", "--ui-test-notification-delay=22"]
        app.launch()
        defer { app.terminate() }
        let sheetBar = openAddMinerForRecordKeyboardTest(in: app)
        let name = app.textFields["addMiner.name"]
        revealManualEntryControl(name, in: app.scrollViews["addMiner.formScroll"], below: sheetBar, app: app)
        name.tap()
        name.typeText("Keep this draft")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let celebration = app.descendants(matching: .any)["celebration.screen"]
        XCTAssertFalse(celebration.exists, "The keyboard must already be open before the record appears")
        XCTAssertTrue(celebration.waitForExistence(timeout: 25))
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        recordScreenshot("Session Best with the keyboard closed", app: app)
        app.buttons["celebration.dismiss"].tap()
        XCTAssertTrue(celebration.waitForNonExistence(timeout: 5))
        XCTAssertTrue(sheetBar.buttons["addMiner.dismiss"].isHittable)
        XCTAssertEqual(name.value as? String, "Keep this draft")
        XCTAssertFalse(keyboard.exists)
    }

    private func openAddMinerForRecordKeyboardTest(in app: XCUIApplication) -> XCUIElement {
        let addMiner = app.buttons["dashboard.addMiner"]
        XCTAssertTrue(addMiner.waitForExistence(timeout: 10))
        addMiner.tap()
        let sheetBar = app.navigationBars["Add a miner"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
        return sheetBar
    }

    private func assertAddMinerFieldIsUnobscured(
        _ field: XCUIElement,
        keyboard: XCUIElement,
        pendingRecords: XCUIElement,
        line: UInt = #line
    ) {
        let unobscured = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard field.exists, field.isHittable, keyboard.exists else { return false }
            let fieldFrame = field.frame
            let aboveKeyboard = fieldFrame.maxY + 16 <= keyboard.frame.minY
            let overlapsRecord = pendingRecords.exists && fieldFrame.intersects(pendingRecords.frame)
            return aboveKeyboard && !overlapsRecord
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [unobscured], timeout: 5), .completed,
                       "Input needs at least 16 points of clearance: field \(field.frame), keyboard \(keyboard.frame)",
                       line: line)
    }

    func testDecimalKeyboardDoneKeepsUnsavedElectricityRate() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-test-light-appearance"]
        app.launch()
        defer { app.terminate() }
        openFleetSettings(in: app)
        let energy = app.buttons["monitoring.energy"]
        reveal(energy, in: app)
        energy.tap()
        let rate = app.textFields["energy.rateField"]
        reveal(rate, in: app)
        rate.tap()
        rate.typeText("0.15")

        let keyboard = app.keyboards.firstMatch
        let done = app.navigationBars.buttons["energy.keyboardDone"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        assertFleetEditingFieldAboveKeyboard(rate, in: app, navigation: app.navigationBars.firstMatch)
        recordScreenshot("Electricity rate keyboard and navigation Done", app: app)
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rate.value as? String, "0.15")
        XCTAssertFalse(app.staticTexts["energy.feedback"].exists, "Done must not save")
        let save = app.buttons["energy.save"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["energy.feedback"].waitForExistence(timeout: 5))
    }

    private func exerciseManualEntryWithKeyboard(light: Bool, layout: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (light ? ["--ui-test-light-appearance"] : [])
        app.launch()
        defer { app.terminate() }
        if layout == "landscape" {
            XCTAssertGreaterThan(app.frame.width, app.frame.height)
        }
        let connect = app.buttons["dashboard.connectFirstMiner"]
        let add = app.buttons["dashboard.addMiner"]
        let appearance = light ? "light" : "dark"
        if connect.waitForExistence(timeout: 5), connect.isHittable {
            XCTAssertGreaterThanOrEqual(connect.frame.height, 44)
            recordScreenshot("Connect first miner - \(layout) \(appearance)", app: app)
            connect.tap()
        } else {
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
        }

        let sheetBar = app.navigationBars["Add a miner"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
        let scroll = app.scrollViews["addMiner.formScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let save = app.buttons["addMiner.save"]
        revealManualEntryControl(save, in: scroll, below: sheetBar, app: app)
        XCTAssertFalse(save.isEnabled, "An empty address cannot be submitted")
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        recordScreenshot("Disabled Add miner - \(layout) \(appearance)", app: app)

        let address = app.textFields["addMiner.address"]
        revealManualEntryControl(address, in: scroll, below: sheetBar, app: app)
        address.tap()
        address.typeText("fixture.invalid")
        let keyboard = app.keyboards.firstMatch
        let done = sheetBar.buttons["addMiner.keyboardDone"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        assertFleetEditingFieldAboveKeyboard(address, in: app, navigation: sheetBar)
        recordScreenshot("Address keyboard - \(layout) \(appearance)", app: app)
        XCTAssertTrue(done.isHittable)
        XCTAssertLessThan(done.frame.maxY, keyboard.frame.minY)
        done.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(sheetBar.exists, "Done must not close the sheet or try to add a miner")
        XCTAssertEqual(address.value as? String, "fixture.invalid")
        sheetBar.buttons["addMiner.dismiss"].tap()
        XCTAssertTrue(sheetBar.waitForNonExistence(timeout: 5))
    }

    func revealManualEntryControl(
        _ element: XCUIElement,
        in scroll: XCUIElement,
        below bar: XCUIElement,
        app: XCUIApplication
    ) {
        let visibleScroll = scroll.frame.intersection(app.frame)
        let top = max(visibleScroll.minY, bar.frame.maxY) + 4
        let bottom = visibleScroll.maxY - 16
        let viewport = CGRect(x: visibleScroll.minX, y: top,
                              width: visibleScroll.width, height: bottom - top)
        guard !viewport.isEmpty else {
            XCTFail("No visible Add Miner form: \(scroll.frame), navigation: \(bar.frame)")
            return
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for attempt in 0..<10 {
            let frame = element.exists ? element.frame : .zero
            if !frame.isEmpty && viewport.contains(frame) && element.isHittable { return }
            let isAbove = !frame.isEmpty && frame.minY < viewport.minY
            // Stay inside the form and away from the sheet, navigation and home gestures.
            let x = viewport.minX + viewport.width * (attempt.isMultiple(of: 2) ? 0.3 : 0.5)
            let startY = viewport.minY + viewport.height * (isAbove ? 0.22 : 0.78)
            let endY = viewport.minY + viewport.height * (isAbove ? 0.78 : 0.22)
            let start = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: endY - app.frame.minY))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.12)
        }
        XCTAssertTrue(element.exists && viewport.contains(element.frame) && element.isHittable,
                      "Expected visible, reachable form control: \(element), frame: \(element.frame), viewport: \(viewport)")
    }
}
