import XCTest

@MainActor
func replaceFleetTuningInput(_ text: String, prefix: String, in app: XCUIApplication) {
    let input = app.textFields["\(prefix).customInput"]
    revealFleetControl(input, in: app)
    let previous = input.value as? String ?? ""
    // Focus once at the trailing edge. A preceding center tap can put the caret
    // before a short right-aligned value, then the second tap opens the edit menu.
    input.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
    let cleared = input.value as? String ?? ""
    if !cleared.isEmpty && cleared != input.placeholderValue {
        XCTContext.runActivity(named: "Direct input deletion diagnostics") { activity in
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            activity.add(hierarchy)
        }
    }
    XCTAssertTrue(cleared.isEmpty || cleared == input.placeholderValue,
                  "The complete old value must be cleared: \(cleared)")
    input.typeText(text)
    XCTAssertEqual(input.value as? String, text)
}

@MainActor
func finishFleetTuningInput(prefix: String, in app: XCUIApplication) {
    let done = app.buttons["\(prefix).keyboardDone"]
    XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
    done.tap()
    XCTAssertTrue(done.waitForNonExistence(timeout: 5))
}
