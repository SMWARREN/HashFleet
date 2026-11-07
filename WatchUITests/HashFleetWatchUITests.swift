import XCTest

@MainActor
final class HashFleetWatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testIndependentEmptyLaunchAndManualSetup() {
        let app = launch()
        XCTAssertTrue(element("watch.fleet", in: app).waitForExistence(timeout: 10))
        reveal(app.buttons["watch.addMiner"], in: app)
        XCTAssertTrue(app.buttons["watch.addMiner"].isHittable)
        capture("Independent Watch empty state")
        app.buttons["watch.addMiner"].tap()
        XCTAssertTrue(element("watch.add.name", in: app).waitForExistence(timeout: 5))
        let address = element("watch.add.address", in: app)
        for _ in 0..<5 where !address.exists { app.swipeUp() }
        XCTAssertTrue(address.exists)
        let save = app.buttons["watch.add.save"]
        for _ in 0..<5 where !save.exists { app.swipeUp() }
        XCTAssertTrue(save.exists)
        capture("Manual setup without iPhone")
    }

    func testDemoFleetAndMinerDetails() {
        let app = launch(demo: true)
        XCTAssertTrue(element("watch.summary", in: app).waitForExistence(timeout: 10))
        capture("Sample Watch fleet")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "watch.miner.")).firstMatch
        reveal(row, in: app)
        XCTAssertTrue(row.exists)
        row.tap()
        XCTAssertTrue(element("watch.detail", in: app).waitForExistence(timeout: 5))
        capture("Sample Watch miner details")
        app.swipeUp()
        capture("Sample Watch lower miner details")
        XCTAssertFalse(app.buttons["Restart miner"].exists)
        XCTAssertFalse(app.buttons["Apply settings"].exists)
    }

    func testAccessibilityTextStillAllowsSetup() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let add = app.buttons["watch.addMiner"]
        XCTAssertTrue(element("watch.fleet", in: app).waitForExistence(timeout: 10))
        reveal(add, in: app)
        XCTAssertTrue(add.isHittable)
        capture("Watch accessibility text")
        add.tap()
        let address = element("watch.add.address", in: app)
        for _ in 0..<5 where !address.exists { app.swipeUp() }
        XCTAssertTrue(address.exists)
    }

    func testStaleReadingsAreNotCountedAsCurrent() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-stale"]
        app.launch()
        let summary = element("watch.summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("0 of 3 miners current"), summary.label)
        XCTAssertTrue(summary.label.localizedCaseInsensitiveContains("Hashrate: Not reported"), summary.label)
        capture("Stale readings excluded from current totals")
    }

    func testDisconnectedWatchKeepsUsableNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seeded", "--ui-testing-offline"]
        app.launch()
        let summary = element("watch.summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("0 of 3 miners current"), summary.label)
        capture("Unreachable network without phone dependency")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "watch.miner.")).firstMatch
        reveal(row, in: app)
        capture("Offline fleet after scrolling")
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(element("watch.detail", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("watch.detail.status", in: app).label.contains("Can't reach"))
        capture("Unreachable miner details")
    }

    func testAutomaticallyFindsMinersWithoutManualSetupAndRescanDoesNotDuplicate() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-discovery-found"]
        app.launch()
        let summary = element("watch.summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        let current = NSPredicate(format: "label CONTAINS %@", "2 of 2 miners current")
        expectation(for: current, evaluatedWith: summary)
        waitForExpectations(timeout: 8)
        capture("Miners found and read automatically without a phone")
        let scan = app.buttons["watch.discovery.scan"]
        reveal(scan, in: app)
        XCTAssertTrue(scan.isHittable)
        scan.tap()
        let result = element("watch.discovery.result", in: app)
        reveal(result, in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("No new entries added"), result.label)
        capture("Rescan preserves saved miners without duplicates")
        reveal(summary, in: app, towardTop: true)
        XCTAssertTrue(summary.label.contains("2 of 2 miners current"), summary.label)
    }

    func testAutomaticSearchCanBeStoppedWithoutSavingAnything() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-discovery-stalled"]
        app.launch()
        XCTAssertTrue(element("watch.discovery.progress", in: app).waitForExistence(timeout: 10))
        capture("Automatic Watch scan progress")
        let stop = app.buttons["watch.discovery.stop"]
        reveal(stop, in: app)
        XCTAssertTrue(stop.isHittable)
        stop.tap()
        let result = element("watch.discovery.result", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Search stopped"), result.label)
        XCTAssertFalse(element("watch.summary", in: app).exists)
        let add = app.buttons["watch.addMiner"]
        reveal(add, in: app)
        XCTAssertTrue(add.isHittable)
        capture("Stopped search keeps manual setup usable")
    }

    func testExplicitStopRemainsStoppedAfterLeavingWatchApp() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-discovery-stalled"]
        app.launch()
        XCTAssertTrue(element("watch.discovery.progress", in: app).waitForExistence(timeout: 10))
        let stop = app.buttons["watch.discovery.stop"]
        reveal(stop, in: app)
        stop.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        let result = element("watch.discovery.result", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.contains("Search stopped"), result.label)
        XCTAssertFalse(element("watch.discovery.progress", in: app).exists)
        capture("Returning to Watch preserves stopped foreground search")
    }

    func testBackgroundedSearchAutomaticallyRetriesOnReturn() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-discovery-stalled"]
        app.launch()
        XCTAssertTrue(element("watch.discovery.progress", in: app).waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(element("watch.discovery.progress", in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(element("watch.discovery.result", in: app).exists)
        capture("Returning to Watch retries interrupted search automatically")
        let stop = app.buttons["watch.discovery.stop"]
        reveal(stop, in: app)
        stop.tap()
    }

    func testRefreshKeepsSingleLineTextAndStableSizeWhileBusy() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-discovery-found", "--ui-testing-refresh-slow"]
        app.launch()
        let summary = element("watch.summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        let current = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "2 of 2 miners current"), object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [current], timeout: 10), .completed)
        let refresh = app.buttons["watch.refresh"]
        reveal(refresh, in: app)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        revealForCapture(refresh, in: app)
        let text = refresh.staticTexts["Refresh"]
        XCTAssertTrue(text.exists)
        let before = text.frame
        let buttonBefore = refresh.frame
        capture("Refresh label before reading")
        refresh.tap()
        XCTAssertFalse(refresh.isEnabled)
        XCTAssertEqual(refresh.value as? String, "Refreshing")
        XCTAssertEqual(text.label, "Refresh")
        capture("Refresh busy geometry before unchanged frame assertions")
        print("REFRESH_GEOMETRY beforeText=\(before) beforeButton=\(buttonBefore) busyText=\(text.frame) busyButton=\(refresh.frame)")
        XCTAssertEqual(text.frame.height, before.height, accuracy: 1, "Busy indicator must not wrap Refresh")
        XCTAssertEqual(text.frame.width, before.width, accuracy: 1)
        XCTAssertEqual(refresh.frame.height, buttonBefore.height, accuracy: 1)
        capture("Refresh label remains intact during actual in-flight fixture read")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
        XCTAssertEqual(text.frame.height, before.height, accuracy: 1)
        capture("Refresh label after reading")
    }

    func testNoDirectWiFiExplainsRetryAndKeepsManualFallback() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-discovery-unavailable"]
        app.launch()
        let result = element("watch.discovery.result", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.localizedCaseInsensitiveContains("Wi-Fi"), result.label)
        XCTAssertFalse(result.label.localizedCaseInsensitiveContains("offline"), result.label)
        let retry = app.buttons["watch.discovery.scan"]
        reveal(retry, in: app, towardTop: true)
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let add = app.buttons["watch.addMiner"]
        reveal(add, in: app)
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(element("watch.add.name", in: app).waitForExistence(timeout: 5))
        capture("Manual setup remains available when discovery cannot use Wi-Fi")
    }

    func testDemoDoesNotAutoImportDiscoveryFixtures() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-discovery-found", "--demo"]
        app.launch()
        let summary = element("watch.summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("3 of 3 miners current"), summary.label)
        XCTAssertTrue(element("watch.demoBanner", in: app).exists)
        XCTAssertFalse(element("watch.discovery.progress", in: app).exists)
        capture("Demo stays separate from automatic discovery")
    }

    /// Explicit opt-in: changes only the dedicated simulator's Smart Stack, not a user's Watch.
    func testSmartStackWidgetOpensIndependentWatchApp() throws {
        guard ProcessInfo.processInfo.environment["HASHFLEET_SMART_STACK_UI"] == "1" else {
            throw XCTSkip("Requires a dedicated simulator authorized for system Smart Stack editing.")
        }
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        // Cleanup only runs after the launch assertions, so it cannot fake a widget-open pass.
        defer { if app.state != .runningForeground { app.activate() } }
        XCTAssertTrue(element("watch.fleet", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("watch.demoBanner", in: app).exists)
        XCUIDevice.shared.press(.home)
        let system = XCUIApplication(bundleIdentifier: "com.apple.clockface")
        print("SMART STACK HOME\n\(system.debugDescription)")
        // System UI persists across tests. Exit any previous gallery and edit mode first.
        let previousBack = system.buttons["BackButton"]
        if previousBack.exists { previousBack.tap() }
        let previousClose = system.buttons["Close"]
        if previousClose.exists { previousClose.tap() }
        let previousDone = system.buttons["Done"]
        if previousDone.exists { previousDone.tap() }
        let editStack = system.buttons["Edit"]
        if !editStack.isHittable { system.swipeUp() }
        print("SMART STACK OPEN\n\(system.debugDescription)")
        let stack = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        stack.name = "Watch Smart Stack before adding Hash Fleet"
        stack.lifetime = .keepAlways
        add(stack)
        for _ in 0..<8 where !editStack.isHittable { system.swipeUp() }
        guard editStack.isHittable else {
            XCTFail("Scroll to the real Smart Stack Edit control.")
            return
        }
        editStack.tap()
        print("SMART STACK EDIT\n\(system.debugDescription)")
        let edit = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        edit.name = "Watch Smart Stack edit controls"
        edit.lifetime = .keepAlways
        add(edit)
        // Idempotent on this opt-in isolated simulator: replace only our own prior card.
        let previousLauncher = system.cells.containing(.any, identifier: "watch.widget.launch").firstMatch
        if previousLauncher.exists {
            // Do not drag a card in edit mode: watchOS 26 interprets it as reordering.
            // Native edit controls are siblings of the remote widget subtree on watchOS 26.
            let cardTop = previousLauncher.frame.minY
            let removals = system.buttons.matching(identifier: "StackCollectionViewCell-LeadingButton-Remove")
            guard let remove = removals.allElementsBoundByIndex.first(where: {
                abs($0.frame.midY - cardTop) < 20 && $0.isHittable
            }) else {
                XCTFail("An existing test launcher must expose its own adjacent remove control.")
                return
            }
            remove.tap()
        }
        let addWidget = system.cells["Add widget"]
        guard addWidget.waitForExistence(timeout: 5) else {
            XCTFail("The real Smart Stack must expose its add-widget control.")
            return
        }
        addWidget.tap()
        print("SMART STACK GALLERY\n\(system.debugDescription)")
        let gallery = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        gallery.name = "Hash Fleet widget in the system gallery"
        gallery.lifetime = .keepAlways
        add(gallery)
        let fleetApp = system.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] %@ OR identifier CONTAINS[c] %@", "Hash Fleet", "hashfleet")).firstMatch
        for _ in 0..<24 {
            if fleetApp.exists && fleetApp.isHittable { break }
            // A flick can skip the entire H section on a tiny Watch display.
            let from = system.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let to = system.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
            print("SMART STACK GALLERY ROWS: \(system.cells.allElementsBoundByIndex.map(\.label))")
        }
        print("SMART STACK GALLERY SCROLLED\n\(system.debugDescription)")
        guard fleetApp.exists && fleetApp.isHittable else {
            XCTFail("The installed Watch extension must appear in the real widget gallery.")
            return
        }
        fleetApp.tap()
        print("SMART STACK PICKER\n\(system.debugDescription)")
        let renderedLauncher = system.descendants(matching: .any).matching(identifier: "watch.widget.launch").firstMatch
        guard renderedLauncher.waitForExistence(timeout: 8) else {
            XCTFail("The real rectangular launcher must render in the gallery.")
            return
        }
        // The remote SwiftUI view reports local coordinates. Tap its real system cell.
        let launcher = system.cells.containing(.any, identifier: "watch.widget.launch").firstMatch
        guard launcher.isHittable else {
            XCTFail("The system gallery must offer a tappable rendered Hash Fleet card.")
            return
        }
        let preview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        preview.name = "Rendered Hash Fleet launcher in the actual widget gallery"
        preview.lifetime = .keepAlways
        add(preview)
        launcher.tap()
        print("SMART STACK ADDED\n\(system.debugDescription)")
        let done = system.buttons["Done"]
        guard done.waitForExistence(timeout: 5) else {
            XCTFail("Adding the launcher must return to Smart Stack editing.")
            return
        }
        done.tap()
        revealForCapture(launcher, in: system)
        XCTAssertTrue(launcher.isHittable)
        XCTAssertGreaterThanOrEqual(launcher.frame.minY, system.frame.height * 0.24)
        let installed = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        installed.name = "Hash Fleet launcher added to the real Smart Stack"
        installed.lifetime = .keepAlways
        add(installed)
        XCTAssertNotEqual(app.state, .runningForeground)
        launcher.tap()
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "state == %d", XCUIApplication.State.runningForeground.rawValue), object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 8), .completed, "Tapping the actual widget must foreground Hash Fleet without app.activate().")
        XCTAssertTrue(element("watch.fleet", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("watch.demoBanner", in: app).exists)
        capture("Smart Stack tap opens the independent production Watch app")
        app.terminate()
        if !launcher.exists { system.swipeUp() }
        // A card can be technically hittable while its center is covered by the clock header.
        revealForCapture(launcher, in: system)
        guard launcher.isHittable && launcher.frame.minY >= system.frame.height * 0.24 else {
            XCTFail("The retained launcher must be fully clear of the Smart Stack header before a cold tap.")
            return
        }
        let coldCard = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        coldCard.name = "Actual retained Smart Stack card framed before cold launch"
        coldCard.lifetime = .keepAlways
        add(coldCard)
        launcher.tap()
        let coldOpened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "state == %d", XCUIApplication.State.runningForeground.rawValue), object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [coldOpened], timeout: 8), .completed, "The widget must also cold-launch the app without phone or fixture arguments.")
        XCTAssertTrue(element("watch.fleet", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("watch.demoBanner", in: app).exists)
        capture("Smart Stack widget cold-launches Hash Fleet")
    }

    /// Explicit opt-in only: this issues real, bounded GET requests on the simulator's local LAN.
    /// Set HASHFLEET_LIVE_EXPECTED_MINERS in the test runner environment, never in ordinary CI runs.
    func testProductionDiscoveryAndReadingsOnLocalNetwork() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let count = environment["HASHFLEET_LIVE_EXPECTED_MINERS"].flatMap(Int.init),
              (1...16).contains(count) else {
            throw XCTSkip("Requires an explicitly authorized real-LAN miner count. Fixture tests do not cover production discovery.")
        }
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(element("watch.fleet", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("watch.demoBanner", in: app).exists)
        capture("Production scanner without demo or fixture arguments")

        // Require a dedicated empty simulator so cached/manual entries cannot masquerade as discovery.
        // On completion, the real summary is inserted above the discovery controls, which may be virtualized.
        let summary = element("watch.summary", in: app)
        XCTAssertFalse(summary.exists, "Run real discovery acceptance on a dedicated empty simulator.")
        XCTAssertTrue(summary.waitForExistence(timeout: 75), "A successful bounded real scan must save actual miners.")
        reveal(summary, in: app, towardTop: true)
        let current = NSPredicate(format: "label CONTAINS %@", "\(count) of \(count) miners current")
        let currentExpectation = XCTNSPredicateExpectation(predicate: current, object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [currentExpectation], timeout: 15), .completed, summary.label)
        revealForCapture(summary, in: app)
        capture("Production discovery with current real LAN readings")

        // The reported failure concerns the actual Scan button, not only the automatic empty launch.
        let scan = app.buttons["watch.discovery.scan"]
        reveal(scan, in: app)
        XCTAssertTrue(scan.isHittable)
        scan.tap()
        let progress = element("watch.discovery.progress", in: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        revealForCapture(progress, in: app)
        capture("Actual Scan button starts production LAN requests")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 75), .completed, "Real explicit scan must finish within its bounded budget.")
        let result = element("watch.discovery.result", in: app)
        reveal(result, in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "Found \(count) compatible miners. No new entries added.")
        revealForCapture(result, in: app)
        capture("Actual LAN rescan finds existing miners without duplicates")
        reveal(summary, in: app, towardTop: true)
        let afterRescan = XCTNSPredicateExpectation(predicate: current, object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [afterRescan], timeout: 15), .completed, summary.label)
        revealForCapture(summary, in: app)
        capture("Four current production miners remain after explicit rescan")

        // Freshness is proved by the oldest miner observation advancing repeatedly, not a static current badge.
        for cycle in 1...3 {
            let previous = try XCTUnwrap(summary.value as? String)
            let oldTimestamp = try XCTUnwrap(Double(previous))
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let value = summary.value as? String, let timestamp = Double(value) else { return false }
                return timestamp > oldTimestamp
            }, object: summary)
            XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 20), .completed, "Automatic refresh cycle \(cycle) must advance every miner without a tap")
            XCTAssertTrue(summary.label.contains("\(count) of \(count) miners current"), summary.label)
            XCTAssertEqual(app.state, .runningForeground)
            capture("Real automatic refresh cycle \(cycle) advances every miner")
        }
        let beforeReturn = try XCTUnwrap(summary.value as? String)
        XCUIDevice.shared.press(.home)
        app.activate()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", beforeReturn), object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 8), .completed, "Returning to the app must fetch immediately")
        XCTAssertTrue(summary.label.contains("\(count) of \(count) miners current"), summary.label)
        capture("Returning to production app immediately refreshes every real miner")
    }

    /// A hittable text element can still have most of its frame below the Watch's visible edge.
    /// Keep production evidence inside the content area, clear of the translucent navigation header.
    private func revealForCapture(_ target: XCUIElement, in app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        let bounds = app.frame
        let top = bounds.minY + bounds.height * 0.24
        let bottom = bounds.maxY - 8
        for _ in 0..<12 {
            var towardTop = false
            if target.exists {
                let frame = target.frame
                if frame.height > 0 && frame.minY >= top && frame.maxY <= bottom { return }
                towardTop = frame.minY < top
            }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.45 : 0.8))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.75 : 0.55))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        let list = app.collectionViews.firstMatch
        for _ in 0..<24 {
            if target.exists && target.isHittable { return }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.45 : 0.8))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.75 : 0.55))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launch(demo: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (demo ? ["--demo"] : [])
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
