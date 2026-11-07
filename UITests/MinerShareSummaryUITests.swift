import XCTest

@MainActor
final class MinerShareSummaryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCountsRejectionAndFirmwareErrorsAreDistinctInBothModes() throws {
        let server = try LoopbackMinerServer()
        let infoJSON = #"{"hostname":"Gamma","ASICModel":"BM1370","hashRate":1250,"power":19,"# +
            #""sharesAccepted":980,"sharesRejected":20,"errorPercentage":0.12}"#
        server.setInfoResponse(status: 200, json: infoJSON)
        let address = try server.start()
        defer { server.stop() }
        for mode in ["Dark", "Light"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing"]
            app.launch()
            defer { app.terminate() }
            setDashboardAppearance(mode, in: app)
            app.buttons["dashboard.addMiner"].tap()
            let field = app.textFields["addMiner.address"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(address + "\n")
            let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
            XCTAssertTrue(miner.waitForExistence(timeout: 10))
            miner.tap()
            for (id, label) in [
                ("accepted", "Accepted, 980"), ("rejected", "Rejected, 20"),
                ("rejectedPercentage", "Rejected share rate, 2.00%"),
                ("firmwareErrors", "Firmware errors, 0.12%")
            ] {
                let metric = app.descendants(matching: .any).matching(identifier: "detail.shares.\(id)").firstMatch
                XCTAssertTrue(metric.waitForExistence(timeout: 5), app.debugDescription)
                XCTAssertEqual(metric.label, label)
                XCTAssertTrue(metric.isHittable, "Share metric must remain visible near the hashrate")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(mode) accepted rejected rate and separate firmware errors"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
        XCTAssertTrue(server.writes.isEmpty)
    }
}
