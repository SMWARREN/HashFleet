import XCTest

/// Native coverage for the optional fleet feature tour.
///
/// The tour's content identifiers are intentionally opaque to this suite. The shell contract is
/// stable: the presented root is `tour.view`, each page exposes `tour.step.<id>`, and navigation
/// uses the fixed control identifiers below.
extension HashFleetUITests {
    #if HASHFLEET_LIVE_REVIEW
    func testFirstRunWalkthroughShowsCurrentEssentialsAndReturnsToViewChoice() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--ui-test-dashboard-fresh"]
        app.launch()

        let entry = app.buttons["dashboard.chooseView.walkthrough"]
        let full = app.buttons["dashboard.chooseView.full"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8) && entry.isHittable)
        XCTAssertGreaterThan(entry.frame.minY, full.frame.minY)
        XCTAssertFalse(tourView(in: app).exists)
        recordScreenshot("First-run view choice with optional walkthrough", app: app)
        entry.tap()
        for (id, tap) in [("overview", false), ("history", false), ("openMiner", true),
                          ("minerSettings", true), ("pools", false), ("dashboardView", false)] {
            XCTAssertTrue(app.staticTexts["tour.step.\(id)"].waitForExistence(timeout: 10), "Missing step \(id)")
            let target = app.descendants(matching: .any)[tap ? "tour.tapTarget" : "tour.highlight"]
            XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing real target for \(id)")
            XCTAssertGreaterThan(target.frame.height, 10)
            if id == "pools" { recordScreenshot("Walkthrough points to Primary and Fallback", app: app) }
            if tap { target.tap() } else { app.buttons[id == "dashboardView" ? "tour.done" : "tour.next"].tap() }
        }
        XCTAssertTrue(tourView(in: app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(entry.waitForExistence(timeout: 5) && entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.staticTexts["tour.step.overview"].waitForExistence(timeout: 8))
        app.buttons["tour.close"].tap()
        XCTAssertTrue(full.waitForExistence(timeout: 5))
        full.tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].exists)
        XCTAssertTrue(minerIDs(in: app).isEmpty)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-test-preserve-storage"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 8))
        XCTAssertFalse(entry.exists)
        XCTAssertFalse(tourView(in: app).exists)
        openFleetSettings(in: app)
        let fullSegment = app.buttons["settings.dashboardView.full"]
        reveal(fullSegment, in: app)
        XCTAssertTrue(fullSegment.isSelected)
    }

    func testSkippingWalkthroughLeavesEssentialsAndCanReplayFromAppSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--ui-test-dashboard-fresh", "--ui-test-reduce-motion"]
        app.launch()
        let skip = app.buttons["dashboard.chooseView.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertFalse(tourView(in: app).exists)
        openFleetSettings(in: app)
        let essentials = app.buttons["settings.dashboardView.essentials"]
        reveal(essentials, in: app)
        XCTAssertTrue(essentials.isSelected)
        let replay = app.buttons["monitoring.featureTour"]
        reveal(replay, in: app)
        XCTAssertTrue(replay.label.contains("Essentials walkthrough"))
        replay.tap()
        XCTAssertTrue(app.staticTexts["tour.step.overview"].waitForExistence(timeout: 8))
        let chooser = app.buttons["tour.chooser"]
        XCTAssertTrue(chooser.isHittable)
        chooser.tap()
        XCTAssertTrue(app.buttons["tour.jump.pools"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tour.jump.openCoins"].exists)
        app.buttons["tour.jump.pools"].tap()
        XCTAssertTrue(app.staticTexts["tour.step.pools"].waitForExistence(timeout: 8))
        app.buttons["tour.close"].tap()
        XCTAssertTrue(tourView(in: app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
    }

    func testWalkthroughAndSkipAreReachableAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--ui-test-dashboard-fresh", "--ui-test-reduce-motion",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let entry = app.buttons["dashboard.chooseView.walkthrough"]
        XCTAssertTrue(app.staticTexts["dashboard.chooseView"].waitForExistence(timeout: 10))
        for _ in 0..<3 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.staticTexts["tour.step.overview"].waitForExistence(timeout: 8))
        let close = app.buttons["tour.close"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        let skip = app.buttons["dashboard.chooseView.skip"]
        for _ in 0..<3 where !skip.isHittable { app.swipeUp() }
        XCTAssertTrue(skip.isHittable)
        skip.tap()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 6))
        XCTAssertFalse(tourView(in: app).exists)
    }
    #endif

    func testGuidedDemoWalksRealScreensWithHighlightedTapsAndKeepsSavedFleet() throws {
        continueAfterFailure = false
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate(); server.stop() }
        try addTourFixture(address: address, app: app, server: server)
        let originalIDs = minerIDs(in: app)
        XCTAssertEqual(originalIDs.count, 1)
        openDashboardTour(in: app)
        let route: [(String, Bool)] = [
            ("overview", false), ("history", false), ("openMiner", true), ("cooling", false),
            ("openCoins", true), ("chooseDGB", true), ("coinResult", false),
            ("openPreferences", true), ("appearance", false),
            ("openEnergy", true), ("energy", false), ("openReports", true),
            ("previewReport", true), ("pdf", false), ("openAlerts", true),
            ("alerts", false), ("complete", false)
        ]
        for (id, tap) in route {
            let arrived = app.staticTexts["tour.step.\(id)"].waitForExistence(timeout: 10)
            if !arrived { print("TOUR ARRIVAL DEBUG \(app.debugDescription)") }
            XCTAssertTrue(arrived, "Did not reach \(id)")
            let highlight = app.descendants(matching: .any)[tap ? "tour.tapTarget" : "tour.highlight"]
            let visible = highlight.waitForExistence(timeout: 10)
            if !visible { print("TOUR DEBUG \(app.debugDescription)") }
            XCTAssertTrue(visible, "Missing real target on \(id)")
            XCTAssertGreaterThan(highlight.frame.width, 10)
            XCTAssertGreaterThan(highlight.frame.height, 10)
            if id == "coinResult" {
                XCTAssertTrue((app.staticTexts["tour.sampleBanner"].value as? String)?.contains("DGB") == true)
            }
            recordScreenshot("Guided real screen \(id)", app: app)
            if tap {
                let target = app.buttons["tour.tapTarget"]
                XCTAssertTrue(target.isHittable)
                target.tap()
            } else {
                app.buttons[id == "complete" ? "tour.done" : "tour.next"].tap()
            }
        }
        XCTAssertTrue(tourView(in: app).waitForNonExistence(timeout: 5))
        XCTAssertEqual(minerIDs(in: app), originalIDs)
        // Completion and early exit must survive a cold launch, not just keep an in-memory list.
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-test-preserve-storage"]
        app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.miner.")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(minerIDs(in: app), originalIDs)
        openDashboardTour(in: app)
        app.buttons["tour.close"].tap()
        XCTAssertTrue(tourView(in: app).waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.miner.")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(minerIDs(in: app), originalIDs)
        XCTAssertTrue(server.writes.isEmpty)
        XCTAssertTrue(server.journal.allSatisfy { $0.method == "GET" })
    }

    func testFeatureTourFirstLaunchAfterSplashAndPersistentOptOut() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--show-feature-tour", "--show-launch-splash"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(tourView(in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["launch.splash"].exists)
        let optOut = app.switches["tour.dontShowAgain"]
        XCTAssertTrue(optOut.waitForExistence(timeout: 5))
        XCTAssertEqual(optOut.value as? String, "0")
        optOut.switches.firstMatch.tap()
        XCTAssertEqual(optOut.value as? String, "1")
        // Persist immediately, even if the user leaves before finishing or closing the tour.
        app.terminate()
        app.launchArguments = ["--ui-testing", "--show-feature-tour", "--show-launch-splash", "--ui-test-preserve-storage"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 15))
        XCTAssertFalse(tourView(in: app).exists)
        openDashboardTour(in: app)
        assertTourPageVisible(in: app)
        XCTAssertEqual(app.switches["tour.dontShowAgain"].value as? String, "1")
        app.buttons["tour.close"].tap()
        XCTAssertTrue(tourView(in: app).waitForNonExistence(timeout: 5))
    }

    func testFeatureTourFirstDismissalDoesNotRepeatOnLaterLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--show-feature-tour"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(tourView(in: app).waitForExistence(timeout: 10))
        app.buttons["tour.close"].tap()
        XCTAssertTrue(tourView(in: app).waitForNonExistence(timeout: 5))
        app.terminate()
        app.launchArguments += ["--ui-test-preserve-storage"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 10))
        XCTAssertFalse(tourView(in: app).exists)
    }

    func testFeatureTourIsOptionalAndDashboardSkipReopenResets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        XCTAssertFalse(tourView(in: app).exists, "The optional tour must not appear automatically.")

        openDashboardTour(in: app)
        assertTourPageVisible(in: app)
        recordScreenshot("Feature tour first page", app: app)

        let firstStepIdentifier = tourStep(in: app).identifier
        let close = app.buttons["tour.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(tourView(in: app).waitForNonExistence(timeout: 5), app.debugDescription)

        openDashboardTour(in: app)
        assertTourPageVisible(in: app)
        XCTAssertEqual(tourStep(in: app).identifier, firstStepIdentifier,
                       "Reopening the tour must reset to its first step.")
    }

    func testFeatureTourSupportsNextBackAndDoneDismissal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 10))
        openDashboardTour(in: app)
        assertTourPageVisible(in: app)

        let firstStepIdentifier = tourStep(in: app).identifier
        let next = app.buttons["tour.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        assertTourPageVisible(in: app)
        XCTAssertNotEqual(tourStep(in: app).identifier, firstStepIdentifier,
                          "Next must advance to a different tour step.")

        let back = app.buttons["tour.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        assertTourPageVisible(in: app)
        XCTAssertEqual(tourStep(in: app).identifier, firstStepIdentifier,
                       "Back must return to the preceding tour step.")

        // Advance through the opaque set of steps until the final Done control appears.
        // The guard prevents a broken next action from turning this into an unbounded test.
        for _ in 0..<20 where !app.buttons["tour.done"].exists {
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        let done = app.buttons["tour.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Tour did not reach its final step.")
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(tourView(in: app).waitForNonExistence(timeout: 5), app.debugDescription)
    }

    func testFeatureTourDoesNotMutateDemoFleetOrRealSavedFixture() throws {
        let demoApp = XCUIApplication()
        demoApp.launchArguments = ["--ui-testing", "--demo"]
        demoApp.launch()
        defer { demoApp.terminate() }

        XCTAssertTrue(demoApp.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        let demoMiner = demoApp.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")
        ).firstMatch
        XCTAssertTrue(demoMiner.waitForExistence(timeout: 5))
        let demoMinerIDs = minerIDs(in: demoApp)
        openDashboardTour(in: demoApp)
        assertTourPageVisible(in: demoApp)
        demoApp.buttons["tour.close"].tap()
        XCTAssertTrue(tourView(in: demoApp).waitForNonExistence(timeout: 5))
        XCTAssertEqual(minerIDs(in: demoApp), demoMinerIDs,
                       "Skipping the tour must preserve the demo fleet.")

        let server = try LoopbackMinerServer()
        let address = try server.start()
        let realApp = XCUIApplication()
        defer { realApp.terminate(); server.stop() }
        realApp.launchArguments = ["--ui-testing"]
        realApp.launch()
        try addTourFixture(address: address, app: realApp, server: server)

        let savedMiner = realApp.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")
        ).firstMatch
        XCTAssertTrue(savedMiner.waitForExistence(timeout: 5))
        let savedMinerID = savedMiner.identifier
        XCTAssertTrue(savedMiner.label.contains("Tour loopback"), savedMiner.label)
        XCTAssertTrue(server.writes.isEmpty, "Reading and saving the fixture must not write.")

        openDashboardTour(in: realApp)
        assertTourPageVisible(in: realApp)
        realApp.buttons["tour.close"].tap()
        XCTAssertTrue(tourView(in: realApp).waitForNonExistence(timeout: 5))
        let restoredMiner = realApp.descendants(matching: .any)[savedMinerID]
        XCTAssertTrue(restoredMiner.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredMiner.label.contains("Tour loopback"), restoredMiner.label)
        XCTAssertTrue(server.writes.isEmpty, "Opening or dismissing the tour must not issue miner commands.")
    }

    func testFeatureTourFitsAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--demo",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        openDashboardTour(in: app)
        assertTourPageVisible(in: app)
        XCTAssertTrue(app.buttons["tour.close"].isHittable)
        XCTAssertTrue(app.buttons["tour.next"].isHittable)
        XCTAssertGreaterThan(app.buttons["tour.next"].frame.width, app.frame.width * 0.75)
        XCTAssertFalse(app.buttons["tour.next"].frame.intersects(app.buttons["tour.back"].frame))
        recordScreenshot("Feature tour largest text", app: app)
        app.buttons["tour.next"].tap()
        XCTAssertTrue(app.buttons["tour.back"].isHittable)
    }

    func testFeatureTourEmptyFleetInvitationAndDirectStepChooser() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }
        let invitation = app.buttons["dashboard.onboardingTour"]
        reveal(invitation, in: app)
        invitation.tap()
        assertTourPageVisible(in: app)
        let first = tourStep(in: app).identifier
        app.buttons["tour.chooser"].tap()
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tour.jump.'"))
        XCTAssertGreaterThan(choices.count, 1)
        let last = choices.element(boundBy: choices.count - 1)
        let lastID = last.identifier
        let target = lastID.replacingOccurrences(of: "tour.jump.", with: "tour.step.")
        app.buttons[lastID].tap()
        XCTAssertTrue(app.descendants(matching: .any)[target].waitForExistence(timeout: 5))
        XCTAssertNotEqual(tourStep(in: app).identifier, first)
        XCTAssertTrue(app.buttons["tour.done"].isHittable)
        app.buttons["tour.done"].tap()
        XCTAssertTrue(tourView(in: app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].exists)
    }

    func testFeatureTourCanBeReopenedFromSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        openFleetSettings(in: app)
        let launch = app.buttons["monitoring.featureTour"]
        reveal(launch, in: app)
        launch.tap()
        assertTourPageVisible(in: app)
        app.buttons["tour.close"].tap()
        XCTAssertTrue(tourView(in: app).waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
    }

    private func tourView(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["tour.view"]
    }

    private func openDashboardTour(in app: XCUIApplication) {
        // The right-hand menu deliberately no longer contains Feature tour. Keep exercising
        // the same tour through its existing onboarding/Fleet tools entry, not a hidden route.
        let onboarding = app.buttons["dashboard.onboardingTour"]
        let launch = onboarding.exists ? onboarding : app.buttons["dashboard.tools.featureTour"]
        revealFleetControl(launch, in: app)
        XCTAssertTrue(launch.waitForExistence(timeout: 5), app.debugDescription)
        launch.tap()
    }

    private func tourStep(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'tour.step.'")
        ).firstMatch
    }

    private func minerIDs(in app: XCUIApplication) -> [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'"))
            .allElementsBoundByIndex
            .map(\.identifier)
    }

    private func assertTourPageVisible(in app: XCUIApplication,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) {
        let root = tourView(in: app)
        XCTAssertTrue(root.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        let step = tourStep(in: app)
        XCTAssertTrue(step.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
    }

    private func addTourFixture(address: String, app: XCUIApplication,
                                server: LoopbackMinerServer) throws {
        let connect = app.buttons["dashboard.connectFirstMiner"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        app.buttons["dashboard.addMiner"].tap()

        let name = app.textFields["addMiner.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Tour loopback\n")

        let addressField = app.textFields["addMiner.address"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
        addressField.tap()
        addressField.typeText(address + "\n")
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))

        let connected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.journal.contains { $0.method == "GET" && $0.path == "/api/system/info" }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 10), .completed,
                       "The saved fixture must use the real loopback transport.")
    }
}
