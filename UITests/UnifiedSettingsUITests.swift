import XCTest

/// End-to-end safety acceptance for the unified settings surface against a loopback miner.
/// Safe fields may save directly, while restart and other risky operations retain typed
/// confirmation. No path may send a write before its explicit safety flow completes.
@MainActor
final class UnifiedSettingsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    // Local copies rather than shared XCTestCase helpers: several UI test files declare their
    // own private/internal `reveal`/`addFixture` with slightly different signatures, so widening
    // an existing helper's scope caused ambiguous-use build errors across unrelated suites.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<15 {
            if element.exists && element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            start.press(forDuration: 0.02, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable UI control: \(element)")
    }

    /// A direct coordinate tap on an element's own center. Used instead of `element.tap()` after
    /// a sheet dismiss, where SwiftUI can leave an element existing at its final, correct frame
    /// before the system's hit-testable flag catches up; `element.tap()` refuses to synthesize
    /// against a non-hittable element while a raw coordinate tap does not depend on that flag.
    private func forceTap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// forceTap throughout: this fixture helper is used both from a cold launch (where normal
    /// `.tap()` is fine) and after a Settings sheet round trip in this suite's second test (where
    /// elements can exist at their correct frame before isHittable catches up).
    private func addFixture(address: String, app: XCUIApplication, server: LoopbackMinerServer) throws {
        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].waitForExistence(timeout: 10))
        let addButton = app.buttons["dashboard.addMiner"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        forceTap(addButton)
        let name = app.textFields["addMiner.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        forceTap(name)
        name.typeText("Loopback fixture\n")
        let addressField = app.textFields["addMiner.address"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
        forceTap(addressField)
        addressField.typeText(address + "\n")
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.journal.contains { $0.method == "GET" && $0.path == "/api/system/info" }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 10), .completed,
                       "The actual app must fetch telemetry over loopback HTTP.")
    }

    private func assertBecomesOnline(_ miner: XCUIElement) {
        let online = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS[c] 'online'"),
                                               object: miner)
        XCTAssertEqual(XCTWaiter.wait(for: [online], timeout: 10), .completed)
    }

    func testRestartRequiresTypedApplyBeforeReachingTheMiner() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        try addFixture(address: address, app: app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        assertBecomesOnline(miner)
        miner.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.textFields["settings.quick.hostname"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.reportedState"].exists)
        XCTAssertTrue(app.buttons["settings.tuning"].exists,
                      "Tuning must be available directly from miner settings.")
        XCTAssertTrue(app.buttons["settings.advanced"].exists)
        XCTAssertFalse(app.switches["settings.powerUser"].exists)
        XCTAssertTrue(server.writes.isEmpty, "Opening the unified settings hub must never send a miner write.")
        let restart = app.buttons["settings.restart"]
        reveal(restart, in: app)
        restart.tap()
        let send = app.buttons["endpoint.send"]
        reveal(send, in: app)
        send.tap()
        // Restart remains behind the typed-APPLY field, not the optional quick confirmation.
        let typedField = app.textFields["confirmation.token"]
        XCTAssertTrue(typedField.waitForExistence(timeout: 5))
        let oneTapNotice = app.staticTexts["confirmation.powerUser"]
        XCTAssertFalse(oneTapNotice.exists, "The unified settings flow must not show one-tap mode copy.")
        let apply = app.buttons["confirmation.apply"]
        reveal(apply, in: app)
        XCTAssertEqual(apply.label, "Send confirmed request")
        XCTAssertFalse(apply.isEnabled, "Apply must stay disabled until APPLY is typed and risk acknowledged.")
        XCTAssertTrue(server.writes.isEmpty, "No restart may reach the miner before typed confirmation.")
    }

    private func stageUnifiedDraftChanges(in app: XCUIApplication, server: LoopbackMinerServer) -> XCUIElement {
        let hostname = app.textFields["settings.quick.hostname"]
        reveal(hostname, in: app)
        XCTAssertEqual(hostname.value as? String, "loopback-before")
        XCTAssertTrue(app.staticTexts["0 pending changes"].exists)
        hostname.tap()
        hostname.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        hostname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "loopback-before".count)
                          + "loopback-draft\n")
        XCTAssertEqual(hostname.value as? String, "loopback-draft",
                       "The fixture must replace the exact draft, not prepend to the original name.")
        let changes = app.descendants(matching: .any)["settings.quick.changes"]
        reveal(changes, in: app)
        XCTAssertTrue(app.staticTexts["1 pending change"].exists)
        let hostnameChange = app.descendants(matching: .any)["settings.quick.change.hostname"]
        XCTAssertTrue(hostnameChange.exists)
        XCTAssertTrue(hostnameChange.label.contains("loopback-before"), hostnameChange.label)
        XCTAssertTrue(hostnameChange.label.contains("loopback-draft"), hostnameChange.label)
        XCTAssertTrue(server.writes.isEmpty, "Editing a unified quick-change draft must not send a request.")
        let easyShot = XCTAttachment(screenshot: app.screenshot())
        easyShot.name = "Unified miner controls with a staged hostname change"
        easyShot.lifetime = .keepAlways
        add(easyShot)
        XCTAssertTrue(server.writes.isEmpty, "A unified hostname draft is still unsent.")
        return hostname
    }

    private func verifyReportedStateAndRoutes(in app: XCUIApplication, hostname: XCUIElement, server: LoopbackMinerServer) {
        let state = app.descendants(matching: .any)["settings.reportedState"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCTAssertTrue(hostname.exists)
        XCTAssertTrue(app.buttons["settings.tuning"].exists)
        XCTAssertTrue(app.buttons["settings.advanced"].exists)
        XCTAssertFalse(app.switches["settings.powerUser"].exists)
        XCTAssertTrue(server.writes.isEmpty)
        let expectedReportedRows = [
            ("identity", "BM1370"), ("firmware", "ui-loopback-fixture"),
            ("frequency.configured", "500 MHz"), ("frequency.measured", "Not reported"),
            ("voltage.configured", "1150 mV"), ("voltage.measured", "Not reported"),
            ("temperature.primary", "51 °C"), ("temperature.vr", "48 °C"),
            ("fan.percent", "65%"), ("fan.rpm", "4200 RPM"), ("hardwareErrors", "Not reported")
        ]
        for (suffix, expectedValue) in expectedReportedRows {
            let row = app.descendants(matching: .any)
                .matching(identifier: "settings.reportedState.\(suffix)").firstMatch
            XCTAssertTrue(row.exists, suffix)
            let label = row.label.replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{202F}", with: " ")
            XCTAssertTrue(label.contains(expectedValue), "\(suffix): \(label)")
        }
        let source = app.descendants(matching: .any)["settings.reportedState.source"]
        XCTAssertTrue(source.label.contains("Reported reading"), source.label)
        XCTAssertTrue(source.label.contains("read only"), source.label)
        for route in ["settings.general", "settings.pools", "settings.cooling", "settings.tuning", "settings.display", "settings.advanced", "settings.compatibility"] {
            XCTAssertTrue(app.buttons[route].exists, route)
        }
        let settingsShot = XCTAttachment(screenshot: app.screenshot())
        settingsShot.name = "Unified settings with reported state and direct category access"
        settingsShot.lifetime = .keepAlways
        add(settingsShot)
    }

    private func verifyDiagnosticsAndCompatibility(in app: XCUIApplication, server: LoopbackMinerServer) {
        let diagnostics = app.descendants(matching: .any)
            .matching(identifier: "detail.diagnosticsDisclosure").firstMatch
        reveal(diagnostics, in: app)
        diagnostics.tap()
        XCTAssertTrue((diagnostics.value as? String ?? "").contains("Expanded"),
                      "The diagnostics disclosure must open from the unified settings hub.")
        for _ in 0..<4 { app.swipeUp() }
        let electrical = app.descendants(matching: .any)["diagnostics.section.electrical"]
        XCTAssertTrue(electrical.waitForExistence(timeout: 5),
                       "The unified detail view should expose comprehensive read-only diagnostics.")
        XCTAssertTrue(server.writes.isEmpty, "Inspecting diagnostics must never write to a miner.")

        let compatibility = app.buttons["settings.compatibility"]
        reveal(compatibility, in: app)
        let asicReadsBefore = server.journal.filter { $0.method == "GET" && $0.path == "/api/system/asic" }.count
        compatibility.tap()
        let compatibilityBar = app.navigationBars["Check compatibility"]
        XCTAssertTrue(compatibilityBar.waitForExistence(timeout: 5))
        XCTAssertEqual(server.journal.filter { $0.method == "GET" && $0.path == "/api/system/asic" }.count,
                       asicReadsBefore, "Opening compatibility must not perform an unsolicited probe.")
        XCTAssertTrue(server.writes.isEmpty)
        compatibilityBar.buttons.firstMatch.tap()
    }

    private func verifyRiskyDraftOpensReview(
        in app: XCUIApplication,
        server: LoopbackMinerServer,
        hostname: XCUIElement
    ) {
        reveal(hostname, in: app)
        XCTAssertEqual(hostname.value as? String, "loopback-draft",
                       "Changing presentation must preserve the user's unsubmitted draft.")
        let cooling = app.buttons["settings.cooling"]
        reveal(cooling, in: app)
        cooling.tap()
        XCTAssertTrue(app.navigationBars["Cooling"].waitForExistence(timeout: 5))
        let autoFan = app.switches["Automatic fan control"]
        reveal(autoFan, in: app)
        XCTAssertEqual(autoFan.value as? String, "1")
        autoFan.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(autoFan.value as? String, "0")
        let review = app.buttons["Review cooling change"]
        reveal(review, in: app)
        XCTAssertTrue(server.writes.isEmpty, "Nothing is sent while the cooling draft is being reviewed.")
        review.tap()
        XCTAssertTrue(app.navigationBars["Update settings"].waitForExistence(timeout: 5),
                      "The cooling category must open the exact review page.")
        let send = app.buttons["endpoint.send"]
        reveal(send, in: app)
        XCTAssertTrue(send.exists)
        XCTAssertTrue(server.writes.isEmpty, "Opening review must never send a write.")
    }

    func testUnifiedSettingsPreserveDraftAndExposeReadOnlyDiagnosticsWithoutWrites() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        try addFixture(address: address, app: app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        assertBecomesOnline(miner)
        miner.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()

        let hostname = stageUnifiedDraftChanges(in: app, server: server)
        verifyReportedStateAndRoutes(in: app, hostname: hostname, server: server)
        verifyDiagnosticsAndCompatibility(in: app, server: server)
        // Returning from a nested category restores the hub's last scroll offset. Bring the
        // everyday card back into the viewport before continuing the same real user workflow.
        for _ in 0..<4 { app.swipeDown() }
        verifyRiskyDraftOpensReview(in: app, server: server, hostname: hostname)
    }

}
