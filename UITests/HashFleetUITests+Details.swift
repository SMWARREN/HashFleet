import XCTest

/// Miner detail and snoozable notice acceptance tests for HashFleetUITests.
extension HashFleetUITests {
    func testResponsiveMinerRowsAndWholeCardNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            app.launchArguments = ["--demo", "--ui-testing", "--ui-test-desktop-layout"]
            app.launch()
            let viewport = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                orientation == .portrait ? app.frame.height > app.frame.width : app.frame.width > app.frame.height
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [viewport], timeout: 8), .completed)
            let miner = minerButton(named: "Workshop Gamma", in: app)
            XCTAssertTrue(miner.waitForExistence(timeout: 10))
            reveal(miner, in: app)
            waitForStableFrame(miner)
            miner.tap()
            captureResponsiveMiner("Miner after whole-card entry \(orientation.rawValue)")
            XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
            let actions = ["identify", "pause", "resume", "restart"].map { app.buttons["detail.quick." + $0] }
            revealResponsiveMiner(actions[0], in: app)
            let frames = actions.map(\.frame)
            XCTAssertTrue(frames.allSatisfy { $0.width >= 100 && $0.height >= 44 })
            XCTAssertLessThan((frames.map(\.width).max() ?? 0) - (frames.map(\.width).min() ?? 0), 2,
                              "All four actions should share available columns, not leave empty adaptive slots")
            for (action, title) in zip(actions, ["Identify device", "Pause mining", "Resume mining", "Restart device"]) {
                revealResponsiveMiner(action, in: app)
                waitForStableFrame(action)
                // The lower-right padding is outside the centered symbol and text.
                action.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.88)).tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5),
                              "The full quick-action card must open its existing review form")
                let send = app.buttons["endpoint.send"]
                XCTAssertTrue(send.waitForExistence(timeout: 5))
                XCTAssertFalse(send.isEnabled, "Demo review forms must keep hardware writes locked")
                let back = app.buttons["BackButton"]
                XCTAssertTrue(back.exists)
                back.tap()
                XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
            }
            let bestShare = app.descendants(matching: .any)["detail.bestShare.ever"].firstMatch
            revealResponsiveMiner(bestShare, in: app)
            XCTAssertTrue(app.descendants(matching: .any)["detail.bestShare.session"].exists,
                          "A card container must not overwrite its individual reading identifiers")
            for titles in [["Power", "Input voltage"], ["Temperature", "VR temp"],
                           ["Fan speed", "Fan rotation"], ["Frequency", "Core voltage"], ["Wi-Fi signal", "Efficiency"]] {
                let first = app.descendants(matching: .any)["detail.metric." + titles[0]].firstMatch
                let second = app.descendants(matching: .any)["detail.metric." + titles[1]].firstMatch
                revealResponsiveMiner(first, in: app)
                XCTAssertTrue(second.exists)
                XCTAssertLessThan(abs(first.frame.width - second.frame.width), 2)
                if abs(first.frame.minY - second.frame.minY) < 2 {
                    XCTAssertLessThan(abs(first.frame.height - second.frame.height), 2)
                }
            }
            let disclosure = app.buttons["detail.diagnosticsDisclosure"]
            revealResponsiveMiner(disclosure, in: app)
            XCTAssertEqual(disclosure.value as? String, "Collapsed")
            XCTAssertTrue(disclosure.isHittable)
            // The middle of the label, deliberately nowhere near the trailing chevron.
            disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
            let expanded = expectation(for: NSPredicate(format: "value == 'Expanded'"), evaluatedWith: disclosure)
            wait(for: [expanded], timeout: 5)
            XCTAssertTrue(app.descendants(matching: .any)["diagnostics.section.electrical"].exists)
            disclosure.tap()
            let collapsed = expectation(for: NSPredicate(format: "value == 'Collapsed'"), evaluatedWith: disclosure)
            wait(for: [collapsed], timeout: 5)
            let diagnosticsPage = app.buttons["detail.diagnostics"]
            revealResponsiveMiner(diagnosticsPage, in: app)
            XCTAssertTrue(diagnosticsPage.isHittable)
            diagnosticsPage.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.7)).tap()
            XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 5),
                          "The full tool row must navigate, not just its arrow")
            captureResponsiveMiner("Responsive miner and full-row navigation \(orientation.rawValue)")
            app.terminate()
        }
    }

    func testLargestTextMinerCardsStackAndRemainWholeCardLinks() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-desktop-layout",
                               "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let miner = minerButton(named: "Workshop Gamma", in: app)
        XCTAssertTrue(miner.waitForExistence(timeout: 10))
        reveal(miner, in: app)
        waitForStableFrame(miner)
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        let actions = ["identify", "pause", "resume", "restart"].map { app.buttons["detail.quick." + $0] }
        revealResponsiveMiner(actions[0], in: app)
        waitForStableFrame(actions[0])
        XCTAssertTrue(actions.allSatisfy(\.exists))
        let frames = actions.map(\.frame)
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.width, 100)
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            XCTAssertLessThan(abs(frame.minX - frames[0].minX), 2)
            XCTAssertLessThan(abs(frame.width - frames[0].width), 2)
        }
        for (previous, next) in zip(frames, frames.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.minY, previous.maxY,
                                       "The mounted largest-text environment must stack actions even at landscape width")
        }
        captureResponsiveMiner("Mounted largest-text single-column miner actions")
        actions[0].coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.88)).tap()
        XCTAssertTrue(app.navigationBars["Identify device"].waitForExistence(timeout: 5))
        let send = app.buttons["endpoint.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled, "Largest-text navigation must preserve the demo write lock")
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        let power = app.descendants(matching: .any)["detail.metric.Power"].firstMatch
        let voltage = app.descendants(matching: .any)["detail.metric.Input voltage"].firstMatch
        revealResponsiveMiner(power, in: app)
        waitForStableFrame(power)
        XCTAssertTrue(voltage.exists)
        XCTAssertLessThan(abs(power.frame.minX - voltage.frame.minX), 2)
        XCTAssertLessThan(abs(power.frame.width - voltage.frame.width), 2)
        XCTAssertGreaterThanOrEqual(voltage.frame.minY, power.frame.maxY,
                                   "Actual largest-text readings must use one full-width column")
        captureResponsiveMiner("Mounted largest-text single-column miner readings")
    }

    private func revealResponsiveMiner(_ element: XCUIElement, in app: XCUIApplication) {
        // The persistent sidebar is a separate scroll view. Drag in the detail column,
        // as the established desktop workflows do, rather than swiping the app root.
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            let top = app.navigationBars.firstMatch.frame.maxY
            let above = element.exists && element.frame.maxY <= top
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: above ? 0.30 : 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: above ? 0.75 : 0.30))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        captureResponsiveMiner("Unreachable responsive miner control")
        print("[RESPONSIVE_MINER_UNREACHABLE] \(element.debugDescription)\n\(app.debugDescription)")
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable whole-card control: \(element)")
    }

    private func captureResponsiveMiner(_ name: String) {
        // App-element screenshots in this simulator have a rotated crop.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMinerDetailShowsCompleteReviewedToolsAndUnifiedSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()
        defer { app.terminate() }

        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")
        ).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 10))
        reveal(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.identityDisclosure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.compatibility"].exists)
        let diagnostics = app.buttons["detail.diagnostics"]
        reveal(diagnostics, in: app)
        XCTAssertTrue(diagnostics.exists)
        let endpointExplorer = app.buttons["detail.endpointExplorer"]
        reveal(endpointExplorer, in: app)
        XCTAssertTrue(endpointExplorer.exists)
        let rawAPI = app.buttons["detail.rawAPI"]
        reveal(rawAPI, in: app)
        XCTAssertTrue(rawAPI.exists)
        XCTAssertTrue(app.descendants(matching: .any)["detail.advancedSection"].exists)
        recordScreenshot("Miner detail with complete reviewed tools", app: app)

        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.textFields["settings.quick.hostname"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.tuning"].exists)
        XCTAssertTrue(app.buttons["settings.advanced"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.reportedState"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["settings.quick.hostname"].exists)
    }

    func testMiningFallbackNoticeCanBeSilencedForFourHours() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-fallback-notice"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        let dashboardSilence = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.notice.snooze.'")
        ).firstMatch
        XCTAssertFalse(dashboardSilence.exists, "The dashboard card must not offer a direct silence control.")

        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS 'Workshop Gamma'")
        ).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 5))
        reveal(miner, in: app)
        XCTAssertTrue(miner.label.contains("Mining fallback"),
                      "The combined card must still report the fallback notice.")
        miner.tap()

        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        let faults = app.descendants(matching: .any)["detail.reportedFaults"]
        XCTAssertTrue(faults.waitForExistence(timeout: 5))
        let faultText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Mining on the fallback pool'")
        ).firstMatch
        XCTAssertTrue(faultText.exists, "Reported warning must be displayed in miner detail.")

        let silenceInDetail = app.buttons["detail.notice.snooze"]
        XCTAssertTrue(silenceInDetail.waitForExistence(timeout: 5))
        recordScreenshot("Detail notice before silence", app: app)

        silenceInDetail.tap()

        let silencedStatus = app.descendants(matching: .any)["detail.notice.silencedStatus"]
        XCTAssertTrue(silencedStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(faultText.exists, "Warning details must remain truthful and visible when snoozed.")
        recordScreenshot("Detail notice after silence", app: app)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        let quietCard = expectation(
            for: NSPredicate(format: "NOT (label CONTAINS %@)", "Mining fallback"),
            evaluatedWith: miner
        )
        wait(for: [quietCard], timeout: 5)
        XCTAssertFalse(dashboardSilence.exists)

        reveal(miner, in: app)
        miner.tap()
        XCTAssertTrue(silencedStatus.waitForExistence(timeout: 5), "Snooze must persist when reopening miner details.")
        XCTAssertFalse(silenceInDetail.exists)
        XCTAssertTrue(faultText.exists, "Silencing the dashboard notice must never hide the miner's actual warning.")
    }

    func testDemoMinerToolsCannotWrite() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        let miner = minerButton(named: "Workshop Gamma", in: app)
        reveal(miner, in: app)
        miner.tap()
        let minerTitle = app.descendants(matching: .any)["detail.minerTitle"]
        XCTAssertTrue(minerTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(minerTitle.label.contains("Workshop Gamma"), minerTitle.label)
        XCTAssertTrue(minerTitle.label.contains("BTC"), minerTitle.label)
        XCTAssertFalse(minerTitle.label.contains("CKPool"), minerTitle.label)
        XCTAssertTrue(app.descendants(matching: .any)["detail.poolContext"].waitForExistence(timeout: 5))
        recordScreenshot("Miner detail", app: app)
        let explorer = app.buttons["detail.endpointExplorer"]
        reveal(explorer, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["detail.advancedSection"].exists,
                      "Tools and firmware are directly available from the unified settings routes.")
        explorer.tap()
        XCTAssertTrue(app.navigationBars["Endpoint explorer"].waitForExistence(timeout: 5))
        let nestedMinerTitle = app.descendants(matching: .any)["miner.navigationTitle"]
        XCTAssertTrue(nestedMinerTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(nestedMinerTitle.label.contains("BTC"), nestedMinerTitle.label)
        XCTAssertTrue(nestedMinerTitle.label.contains("Workshop Gamma"), nestedMinerTitle.label)
        XCTAssertFalse(nestedMinerTitle.label.contains("CKPool"), nestedMinerTitle.label)
        recordScreenshot("Endpoint explorer", app: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("restart")
        let operation = app.staticTexts["Restart device"]
        XCTAssertTrue(operation.waitForExistence(timeout: 5))
        operation.tap()
        let endpointDetailTitle = app.descendants(matching: .any)["miner.navigationTitle"]
        XCTAssertTrue(endpointDetailTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(endpointDetailTitle.label.contains("BTC"), endpointDetailTitle.label)
        XCTAssertTrue(endpointDetailTitle.label.contains("Workshop Gamma"), endpointDetailTitle.label)
        XCTAssertFalse(endpointDetailTitle.label.contains("CKPool"), endpointDetailTitle.label)
        let send = app.buttons["endpoint.send"]
        reveal(send, in: app)
        XCTAssertFalse(send.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Demo write safety lock"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testOnboardingRejectsAddressWithPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].waitForExistence(timeout: 10))
        app.buttons["dashboard.addMiner"].tap()
        let address = app.textFields["addMiner.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        reveal(address, in: app)
        address.tap()
        address.typeText("http://127.0.0.1/path\n")
        let error = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Unable to add miner'")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Add a miner"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["dashboard.exploreDemo"].exists)
    }

    func testFleetPreferencesAndSearchStayLocal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        openFleetSettings(in: app)
        let notifications = app.buttons["monitoring.notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        notifications.tap()
        let sendTest = app.buttons["preferences.sendTestNotification"]
        reveal(sendTest, in: app)
        XCTAssertTrue(sendTest.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["App settings"].exists)
        // The inline group is above the preview controls. A virtualized off-screen
        // row has no frame, so the generic reveal helper would incorrectly scroll down.
        for _ in 0..<8 {
            if notifications.exists && notifications.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(notifications.exists && notifications.isHittable)
        notifications.tap()
        let preferences = app.buttons["monitoring.fleet"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 5))
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Preferences"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["preferences.refreshInterval"].exists,
                       "The live stream and HTTP fallback do not expose a polling interval control.")
        XCTAssertTrue(app.buttons["preferences.sortOption"].exists)
        let compact = app.switches["preferences.compactCards"]
        reveal(compact, in: app)
        XCTAssertEqual(compact.value as? String, "0")
        // SwiftUI exposes both a full-width accessibility row and its native switch.
        // Tap the observed control, not a guessed coordinate within the wrapper row.
        let compactControl = compact.switches.firstMatch
        XCTAssertTrue(compactControl.exists)
        waitForStableFrame(compactControl)
        compactControl.tap()
        let compactChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: compact)
        XCTAssertEqual(XCTWaiter.wait(for: [compactChanged], timeout: 5), .completed)
        XCTAssertEqual(compact.value as? String, "1")
        let realtime = app.switches["preferences.realtimeMonitoring"]
        reveal(realtime, in: app)
        XCTAssertEqual(realtime.value as? String, "1")
        let realtimeControl = realtime.switches.firstMatch
        XCTAssertTrue(realtimeControl.exists)
        waitForStableFrame(realtimeControl)
        realtimeControl.tap()
        let realtimeChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: realtime)
        XCTAssertEqual(XCTWaiter.wait(for: [realtimeChanged], timeout: 5), .completed)
        XCTAssertEqual(realtime.value as? String, "0")
        let blockNotifications = app.switches["preferences.blockNotifications"]
        reveal(blockNotifications, in: app)
        XCTAssertEqual(blockNotifications.value as? String, "0")
        recordScreenshot("Fleet preferences", app: app)
        app.navigationBars["Preferences"].buttons.element(boundBy: 0).tap()
        app.navigationBars["App settings"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(app.navigationBars["App settings"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        let search = app.textFields["dashboard.search"]
        for _ in 0..<4 {
            if search.exists && search.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("Workshop\n")
        // Search narrows only the miner list, not the full-fleet aggregate.
        let miner = minerButton(named: "Workshop Gamma", in: app)
        reveal(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Workshop Gamma"].waitForExistence(timeout: 5))
        app.navigationBars["Workshop Gamma"].buttons.element(boundBy: 0).tap()
        app.buttons["Clear search"].tap()
        app.swipeUp()
        openFleetSettings(in: app)
        XCTAssertTrue(preferences.waitForExistence(timeout: 5))
        preferences.tap()
        reveal(compact, in: app)
        XCTAssertEqual(app.switches["preferences.compactCards"].value as? String, "1")
    }

    func testRejectedLocalPushIsRemovedAndLocalNotificationsRemainAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        openFleetSettings(in: app)
        let preferencesButton = app.buttons["monitoring.fleet"]
        reveal(preferencesButton, in: app)
        preferencesButton.tap()
        XCTAssertTrue(app.navigationBars["Preferences"].waitForExistence(timeout: 5))

        XCTAssertFalse(app.switches["preferences.localPush"].exists,
                       "The rejected Local Push Connectivity feature must not be offered in any build.")
        XCTAssertFalse(app.descendants(matching: .any)["preferences.localPush.unavailable"].exists)
        XCTAssertFalse(app.staticTexts["preferences.localPush.unavailable.explanation"].exists,
                       "Removal must not leave the old unavailable-feature setup instructions behind.")

        app.navigationBars["Preferences"].buttons.element(boundBy: 0).tap()
        let notifications = app.buttons["monitoring.notifications"]
        reveal(notifications, in: app)
        notifications.tap()
        let sendTest = app.buttons["preferences.sendTestNotification"]
        reveal(sendTest, in: app)
        XCTAssertTrue(
            sendTest.waitForExistence(timeout: 5),
            "Removing Local Push Connectivity must preserve ordinary local notification settings."
        )
        XCTAssertTrue(app.navigationBars["App settings"].exists)
        recordScreenshot("Foreground notifications available in this build", app: app)
    }
}
