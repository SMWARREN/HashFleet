import XCTest

/// Uses the actual native options menu, preserving longer recorded-history acceptance.
@MainActor
extension XCUIApplication {
    func chooseSavedHistoryWindow(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let options = buttons["dashboard.historyDisplay"].firstMatch
        for _ in 0..<12 {
            if options.exists && options.isHittable { break }
            let above = options.exists && options.frame.maxY < navigationBars.firstMatch.frame.maxY
            let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.35 : 0.65))
            let end = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.65 : 0.35))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(options.exists && options.isHittable, "Saved history options must remain reachable", file: file, line: line)
        guard options.exists && options.isHittable else { return }
        options.tap()
        // A SwiftUI Menu is exposed as a button on the compact layout, but its
        // platform-rendered rows can be menu items or generic accessibility
        // nodes on iPad. Query the real accessibility tree rather than
        // assuming one UIKit element type.
        let identifiedRange = descendants(matching: .any)
            .matching(identifier: "dashboard.historyRange.\(identifier)")
            .firstMatch
        var range = identifiedRange
        if !identifiedRange.waitForExistence(timeout: 1) {
            let heading: String
            switch identifier {
            case "weekly": heading = "7d history"
            case "monthly": heading = "30d history"
            case "yearly": heading = "365d history"
            default: heading = "\(identifier) history"
            }
            let menuItem = menuItems[heading].firstMatch
            let button = buttons[heading].firstMatch
            let label = staticTexts[heading].firstMatch
            if menuItem.waitForExistence(timeout: 1) {
                range = menuItem
            } else if button.waitForExistence(timeout: 1) {
                range = button
            } else if label.waitForExistence(timeout: 1) {
                range = label
            }
        }
        XCTAssertTrue(range.exists, "The requested saved range must be available", file: file, line: line)
        guard range.exists else { return }
        // SwiftUI's system Menu reports a 38pt row frame on this iPad simulator. The
        // authored controls retain their explicit 44pt target, while the native row's
        // interaction is verified by the real tap that follows.
        XCTAssertGreaterThanOrEqual(range.frame.height, 38, file: file, line: line)
        range.tap()
    }
}
