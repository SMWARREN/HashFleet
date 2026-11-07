import XCTest

/// End-to-end safety regression using a real HTTP connection to an in-process,
/// loopback-only fixture. No demo mode, URLProtocol interception or physical miner.
@MainActor
final class RealModeControlUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCustomJSONStagesUnknownFieldsButNeverBypassesTypedConfirmation() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        try addFixture(address: address, app: app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        assertBecomesOnline(miner)
        miner.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        prepareFrequencyRiskAcknowledgement(app: app)
        let advanced = app.buttons["settings.advanced"]
        reveal(advanced, in: app)
        advanced.tap()
        let custom = app.buttons["settings.customJSON"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Raw JSON editors"].exists,
                       "The unified hub must expose one canonical request JSON editor, not a duplicate disclosure.")
        custom.tap()
        let editor = app.textViews["custom_json.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        reveal(editor, in: app)
        assertCustomJSONEditorLayout(app: app, editor: editor, phase: "before focus")
        let draftJSON = #"{"customFeature":{"enabled":true,"counter":18446744073709551615},"# +
            #""frequency":500}"#
        replaceText(editor, with: draftJSON, in: app)
        assertCustomJSONEditorLayout(app: app, editor: editor, phase: "after text entry")
        XCTAssertTrue(server.writes.isEmpty, "Editor layout and text entry must never send a request.")
        try stageAndCancelCustomJSON(app: app, server: server)
    }

    // Retain the existing test name for configured test-plan selectors. The settings hub is now
    // unified: tuning risk acknowledgement is local to the tuning session, while safe hostname
    // changes use the same direct Save action as every other everyday settings entry point.
    func testUnifiedSettingsDirectApplyHostnameWrite() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        try addFixture(address: address, app: app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        assertBecomesOnline(miner)
        miner.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        prepareFrequencyRiskAcknowledgement(app: app)
        try verifyUnifiedHostnameDirectApply(app: app, server: server)
        verifyBackgroundRetainsRiskAcknowledgementWithoutExtraWrite(app: app, server: server)
    }

    func testOfflineRelaunchShowsCachedSettingsButLocksChanges() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        assertNoLegacyModeSelector(in: app)
        try addFixture(address: address, app: app, server: server)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        expectation(for: NSPredicate(format: "label CONTAINS[c] 'online'"), evaluatedWith: miner)
        waitForExpectations(timeout: 10)
        app.terminate()
        server.stop()
        app.launchArguments = ["--ui-testing", "--ui-test-preserve-storage"]
        app.launch()
        XCTAssertTrue(miner.waitForExistence(timeout: 10), "Saved miner must survive offline relaunch")
        reveal(miner, in: app)
        XCTAssertTrue(miner.label.contains("Unreachable"), miner.label)
        miner.tap()
        let notice = app.descendants(matching: .any).matching(identifier: "miner.offlineReadOnly").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("Last known settings"), notice.label)
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.reportedState"].waitForExistence(timeout: 5))
        let source = app.descendants(matching: .any)
            .matching(identifier: "settings.reportedState.source").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.label.contains("Cached reading"), source.label)
        XCTAssertTrue(source.label.contains("read only"), source.label)
        let easyHostname = app.textFields["settings.quick.hostname"]
        reveal(easyHostname, in: app)
        XCTAssertEqual(easyHostname.value as? String, "loopback-before")
        XCTAssertFalse(easyHostname.isEnabled)
        let easyReview = app.buttons["settings.quick.review"]
        reveal(easyReview, in: app)
        XCTAssertFalse(easyReview.isEnabled)
        XCTAssertTrue(server.writes.isEmpty)
        let general = app.buttons["settings.general"]
        reveal(general, in: app)
        general.tap()
        let hostname = app.textFields["Network hostname"]
        reveal(hostname, in: app)
        XCTAssertEqual(hostname.value as? String, "loopback-before")
        XCTAssertFalse(hostname.isEnabled, "Cached settings may be inspected but not edited offline")
        let review = app.buttons["Review hostname change"].exists
            ? app.buttons["Review hostname change"] : app.buttons["Save name"]
        reveal(review, in: app)
        XCTAssertFalse(review.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Cached offline hostname remains visible and read only"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(server.writes.isEmpty)
    }

    /// Hostname is in the pre-vetted safe-field allowlist, so in
    /// the default unified flow it now applies directly like a normal settings toggle instead of
    /// requiring the review-and-typed-APPLY gate. This still verifies the underlying safety
    /// invariants that mattered before the UX change: exactly one PATCH, the correct body, and a
    /// telemetry refresh afterward — just without the now-removed friction for this safe field.
    func testRealModeHostnameWriteAppliesDirectlyForSafeField() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()

        try addFixture(address: address, app: app, server: server)
        XCTAssertTrue(server.writes.isEmpty, "Connecting and reading telemetry must not write.")
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        let live = NSPredicate(format: "label CONTAINS[c] 'online'")
        expectation(for: live, evaluatedWith: miner)
        waitForExpectations(timeout: 10)
        miner.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 5))
        let general = app.buttons["settings.general"]
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        reveal(general, in: app)
        general.tap()

        let hostname = app.textFields["Network hostname"]
        reveal(hostname, in: app)
        XCTAssertEqual(hostname.value as? String, "loopback-before",
                       "The form must be populated from the live fixture response.")
        replaceText(hostname, with: "loopback-after", in: app)
        let saveButton = app.buttons["Save name"]
        reveal(saveButton, in: app)
        XCTAssertTrue(saveButton.isEnabled, "Real-mode save must not inherit the demo lock.")
        XCTAssertFalse(app.buttons["Review hostname change"].exists,
                       "Safe quick changes keep the direct-save path without mandatory JSON review.")
        XCTAssertTrue(server.writes.isEmpty, "Editing a hostname must not write.")
        saveButton.tap()
        try verifyDirectApplySendsPatch(app: app, server: server)
    }
}
