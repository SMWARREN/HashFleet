import XCTest

@MainActor
final class FleetWidgetRefreshUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLocalRefreshIsSeparateOffAndUnavailableInPrivateTestMode() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        for light in [false, true] {
            app.launchArguments = ["--ui-testing"]
            if light { app.launchArguments.append("--ui-test-light-appearance") }
            app.launch()
            XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 10))
            openFleetSettings(in: app)
            let widgets = app.buttons["monitoring.widgets"]
            for _ in 0..<6 where !widgets.isHittable { app.swipeUp() }
            XCTAssertTrue(widgets.waitForExistence(timeout: 5))
            XCTAssertTrue(widgets.isHittable)
            widgets.tap()
            XCTAssertTrue(app.navigationBars["Widgets"].waitForExistence(timeout: 5))
            let sharing = app.switches["monitoring.widgetSharing"]
            XCTAssertTrue(sharing.waitForExistence(timeout: 5))
            XCTAssertEqual(sharing.value as? String, "0")
            let refresh = app.switches["monitoring.widgetRefresh"]
            for _ in 0..<4 where !refresh.isHittable { app.swipeUp() }
            XCTAssertTrue(refresh.waitForExistence(timeout: 5))
            XCTAssertEqual(refresh.value as? String, "0")
            XCTAssertFalse(refresh.isEnabled, "Private UI-test mode must not configure real miner reads")
            let status = app.staticTexts["monitoring.widgetRefreshStatus"]
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            XCTAssertTrue(status.label.contains("Off"))
            let disclosure = app.staticTexts.containing(NSPredicate(format:
                "label CONTAINS %@ AND label CONTAINS %@", "Off by default", "MAC identity pins")).firstMatch
            XCTAssertTrue(disclosure.exists, "Local addresses and identity sharing must be explicitly disclosed")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = light ? "Optional local refresh light" : "Optional local refresh dark"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    func testLocalUpdateSectionExplainsWiFiBackgroundAndStaleWithoutCloudEnrollment() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        for light in [false, true] {
            app.launchArguments = ["--ui-testing", "--demo"]
            if light { app.launchArguments.append("--ui-test-light-appearance") }
            app.launch()
            openFleetSettings(in: app)
            let activity = app.buttons["monitoring.liveActivity"]
            for _ in 0..<6 where !activity.isHittable { app.swipeUp() }
            XCTAssertTrue(activity.waitForExistence(timeout: 5))
            activity.tap()
            XCTAssertTrue(app.navigationBars["Live Activity"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Local readings from your miners. No remote service is required."].exists)
            for phrase in ["Updates on your Wi-Fi", "While the app is open, monitoring reads your miners directly",
                "For a manual update without opening the app", "iOS does not keep local monitoring running continuously",
                "Stale means the reading is old"] {
                let explanation = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", phrase)).firstMatch
                for _ in 0..<10 where !explanation.isHittable { app.swipeUp() }
                XCTAssertTrue(explanation.exists && explanation.isHittable, "Missing or unreachable local-update guidance: \(phrase)")
            }
            XCTAssertFalse(app.buttons["Connect cloud relay"].exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = light ? "Local-only update explanation light" : "Local-only update explanation dark"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    func testWidgetAndActivityPreviewsUseTheSameSafeDemoSummary() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        for light in [false, true] {
            for destination in ["monitoring.widgets", "monitoring.liveActivity"] {
                // --ui-testing alone deliberately opens an empty fleet. This check exercises
                // the existing synthetic Demo fixture, never a persisted hardware inventory.
                app.launchArguments = ["--ui-testing", "--demo"]
                if light { app.launchArguments.append("--ui-test-light-appearance") }
                app.launch()
                XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 10))
                openFleetSettings(in: app)
                let button = app.buttons[destination]
                for _ in 0..<6 where !button.isHittable { app.swipeUp() }
                XCTAssertTrue(button.waitForExistence(timeout: 5))
                XCTAssertTrue(button.isHittable)
                button.tap()

                let preview = app.descendants(matching: .any).matching(identifier: "monitoring.glancePreview").firstMatch
                for _ in 0..<6 where !preview.isHittable { app.swipeUp() }
                XCTAssertTrue(preview.waitForExistence(timeout: 5))
                XCTAssertTrue(preview.isHittable)
                XCTAssertTrue(preview.label.hasPrefix("Preview."))
                XCTAssertTrue(preview.label.contains("Demo sample data. No hardware connected."), preview.label)
                XCTAssertTrue(preview.label.contains("SAMPLE HASHRATE"))
                XCTAssertTrue(preview.label.contains("Sample data · no connection"))
                XCTAssertTrue(preview.label.contains("Updated"))
                XCTAssertFalse(preview.label.contains("miners online"))
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "Consistent preview \(destination) \(light ? "light" : "dark")"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
    }
}
