import XCTest

/// Shared navigation for UI tests.
///
/// The app has no tab bar. Settings and About are reached from a toolbar menu on the dashboard
/// (`dashboard.settingsMenu`). Large parts of the UI test suite still drove `app.tabBars`, which
/// silently matches nothing, so those tests failed at the first tap having asserted nothing.
///
/// These live on `XCTestCase` rather than on one test class so every UI test file can use them.
@MainActor
extension XCTestCase {
    /// Returns the dashboard menu that owns Settings, About, and the appearance toggle.
    func dashboardSettingsMenu(in app: XCUIApplication, timeout: TimeInterval = 10) -> XCUIElement {
        let menu = app.buttons["dashboard.settingsMenu"]
        let exists = menu.waitForExistence(timeout: timeout)
        if !exists {
            print("[DASHBOARD_MENU_MISSING] \(app.debugDescription)")
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "Missing dashboard menu after navigation"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(exists, "Expected the dashboard settings menu")
        return menu
    }

    /// Opens and activates the dashboard appearance action for the requested mode.
    func setDashboardAppearance(_ mode: String, in app: XCUIApplication, timeout: TimeInterval = 10) {
        let menu = dashboardSettingsMenu(in: app, timeout: timeout)
        let current = menu.value as? String
        let currentMode = current?.hasSuffix("Dark") == true ? "Dark" : "Light"
        guard currentMode != mode else { return }
        menu.tap()
        let item = app.buttons[mode == "Dark" ? "Switch to dark mode" : "Switch to light mode"]
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "Expected the appearance menu action")
        item.tap()
    }

    /// Opens App settings from the dashboard toolbar menu.
    /// Falls back to a tab bar so the helper keeps working if a tab layout ever returns.
    func openFleetSettings(in app: XCUIApplication, timeout: TimeInterval = 10) {
        openFleetMenuItem(named: "App settings", identifier: "dashboard.openSettings", in: app, timeout: timeout)
    }

    /// Compatibility helper retained for existing route-coverage call sites. Advanced routes are
    /// now available directly, so there is no preference toggle or extra sheet round trip.
    func assertNoLegacyModeSelector(in app: XCUIApplication, timeout: TimeInterval = 10) {
        _ = timeout
        XCTAssertFalse(app.segmentedControls["preferences.appMode"].exists)
    }

    /// Opens About from the dashboard toolbar menu.
    func openFleetAbout(in app: XCUIApplication, timeout: TimeInterval = 10) {
        openFleetMenuItem(named: "About", identifier: "dashboard.openAbout", in: app, timeout: timeout)
    }

    /// Dismisses a presented sheet and returns to the fleet list.
    /// Replaces the old `app.tabBars.buttons["Fleet"].tap()`, which never matched anything.
    func returnToFleet(in app: XCUIApplication, timeout: TimeInterval = 5) {
        if app.tabBars.buttons["Fleet"].exists {
            app.tabBars.buttons["Fleet"].tap()
            return
        }
        for label in ["Done", "Close", "Cancel"] {
            let globalButton = app.buttons[label]
            if globalButton.exists && globalButton.isHittable {
                globalButton.tap()
                return
            }
            let button = app.navigationBars.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                return
            }
        }
        // A navigation push uses a back button whose identifier is stable across title changes.
        let back = app.buttons["BackButton"]
        if back.exists && back.isHittable {
            back.tap()
        } else {
            let fallbackBack = app.navigationBars.buttons.element(boundBy: 0)
            if fallbackBack.exists && fallbackBack.isHittable {
                fallbackBack.tap()
            }
        }
        // The nested page may have popped back to the sheet's root, which owns the dismiss button.
        let done = app.buttons["monitoring.settings.done"]
        if done.waitForExistence(timeout: 1), done.isHittable {
            done.tap()
            return
        }
        let menu = app.buttons["dashboard.settingsMenu"]
        if menu.waitForExistence(timeout: timeout), !menu.isHittable {
            // Returning from a nested settings page exposes the root of the sheet. Dismiss that
            // root with the standard sheet gesture so the dashboard is interactive again.
            app.swipeDown()
        }
        _ = menu.waitForExistence(timeout: timeout)
    }

    private func openFleetMenuItem(
        named name: String, identifier: String, in app: XCUIApplication, timeout: TimeInterval
    ) {
        let menu = app.buttons["dashboard.settingsMenu"]
        if menu.waitForExistence(timeout: timeout) {
            menu.tap()
            let item = app.buttons[identifier]
            XCTAssertTrue(
                item.waitForExistence(timeout: timeout),
                "Expected a \(name) item in the dashboard toolbar menu"
            )
            item.tap()
            return
        }
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(
            tab.waitForExistence(timeout: timeout),
            "Found neither dashboard.settingsMenu nor a \(name) tab. The app shell may have changed."
        )
        tab.tap()
    }
}
