import XCTest

@MainActor
final class LoadingAppearanceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testInitialSkeletonBecomesRealReadingInBothModes() throws {
        for mode in ["Dark", "Light"] {
            let server = try LoopbackMinerServer()
            server.setInfoDelay(6)
            let address = try server.start()
            let app = XCUIApplication()
            defer { app.terminate(); server.stop() }
            app.launchArguments = ["--ui-testing"]
            app.launch()
            setDashboardAppearance(mode, in: app)
            app.buttons["dashboard.addMiner"].tap()
            let field = app.textFields["addMiner.address"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(address + "\n")
            let rate = app.descendants(matching: .any).matching(identifier: "dashboard.fleetHashrate").firstMatch
            XCTAssertTrue(rate.waitForExistence(timeout: 3))
            XCTAssertTrue(rate.label.contains("Loading"), rate.label)
            XCTAssertFalse(rate.label.contains("0.00"), "An unread miner is not a zero-hashrate miner")
            let loading = XCTAttachment(screenshot: app.screenshot())
            loading.name = "\(mode) initial loading skeletons"
            loading.lifetime = .keepAlways
            add(loading)
            let loadedPredicate = NSPredicate(format: "label CONTAINS '1.23' AND NOT label CONTAINS 'Loading'")
            let loaded = XCTNSPredicateExpectation(predicate: loadedPredicate, object: rate)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 12), .completed, app.debugDescription)
            XCTAssertTrue(server.writes.isEmpty)
            app.terminate()
            server.stop()
        }
    }
}
