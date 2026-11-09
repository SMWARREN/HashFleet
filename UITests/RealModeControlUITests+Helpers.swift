import XCTest

/// Fixture setup, scrolling, editing, and staged-review helpers for RealModeControlUITests.
extension RealModeControlUITests {
    enum ScrollDirection { case up, down }

    func addFixture(address: String, app: XCUIApplication, server: LoopbackMinerServer) throws {
        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].waitForExistence(timeout: 10))
        app.buttons["dashboard.addMiner"].tap()
        let name = app.textFields["addMiner.name"]
        reveal(name, in: app)
        name.tap()
        name.typeText("Loopback fixture\n")
        let addressField = app.textFields["addMiner.address"]
        reveal(addressField, in: app)
        addressField.tap()
        addressField.typeText(address + "\n")
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.journal.contains { $0.method == "GET" && $0.path == "/api/system/info" }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 10), .completed,
                       "The actual app must fetch telemetry over loopback HTTP.")
    }

    func assertBecomesOnline(_ miner: XCUIElement) {
        let online = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS[c] 'online'"),
                                               object: miner)
        XCTAssertEqual(XCTWaiter.wait(for: [online], timeout: 10), .completed)
    }

    /// The unified tuning session keeps its risk acknowledgement local to the one-screen flow.
    /// All settings routes are available from the hub without a hidden mode toggle.
    func prepareFrequencyRiskAcknowledgement(app: XCUIApplication) {
        let tuning = app.buttons["settings.tuning"]
        reveal(tuning, in: app)
        tuning.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        let risk = app.switches["tuningSession.riskAcknowledgement"]
        reveal(risk, in: app)
        if risk.value as? String != "1" {
            risk.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(risk.value as? String, "1")
        app.navigationBars["Frequency & voltage"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["settings.advanced"].waitForExistence(timeout: 5))
    }

    func reveal(_ element: XCUIElement, in app: XCUIApplication, direction: ScrollDirection = .up) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            // Gesture in the content area avoids typing on an onscreen keyboard.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: direction == .up ? 0.58 : 0.25))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: direction == .up ? 0.22 : 0.58))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable UI control: \(element)")
    }

    func replaceText(_ element: XCUIElement, with replacement: String, in app: XCUIApplication) {
        XCTAssertTrue(element.exists && element.isHittable)
        let previous = element.value as? String ?? ""
        element.tap()
        // A coordinate near a multiline editor's bottom is not the document end.
        // Single-line inputs here fit on screen, so use trailing-caret deletion for
        // those instead of relying on Simulator hardware-keyboard shortcuts.
        if !previous.isEmpty {
            if element.elementType == .textView {
                element.typeKey("a", modifierFlags: .command)
                element.typeText(XCUIKeyboardKey.delete.rawValue)
                if let remaining = element.value as? String, !remaining.isEmpty {
                    // If the shortcut was not delivered, use the native editing menu.
                    element.press(forDuration: 1.2)
                    let selectAll = app.menuItems["Select All"]
                    XCTAssertTrue(selectAll.waitForExistence(timeout: 3), app.debugDescription)
                    selectAll.tap()
                    element.typeText(XCUIKeyboardKey.delete.rawValue)
                }
                XCTAssertEqual(element.value as? String, "",
                               "Clear the complete JSON document before entering a reviewed replacement.")
            } else {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
                element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
            }
        }
        if !replacement.isEmpty { element.typeText(replacement) }
        if !replacement.isEmpty {
            XCTAssertEqual(element.value as? String, replacement, "Typing must create the exact reviewed value.")
        }
    }

    func assertNoWrites(_ server: LoopbackMinerServer, for duration: TimeInterval) {
        let unexpected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !server.writes.isEmpty },
                                                   object: nil)
        unexpected.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpected], timeout: duration), .completed)
        XCTAssertTrue(server.writes.isEmpty)
    }

    func assertApplyRevealedWithoutScrolling(_ apply: XCUIElement, in app: XCUIApplication) {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: apply)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed,
                       "Typing APPLY must reveal the send action without a manual scroll")
        let keyboardHidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: 5), .completed)
    }
}
