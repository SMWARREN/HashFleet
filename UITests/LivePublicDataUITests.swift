import XCTest

/// Opt-in acceptance through production app networking. The public-data test uses loopback miners
/// with no wallet. The separately gated physical-miner test performs monitoring reads only and never
/// invokes a write-capable control.
@MainActor
final class LivePublicDataUITests: XCTestCase {
    func testProductionPublicDataRendersAutomaticallyOnNativeHome() throws {
        guard ProcessInfo.processInfo.environment["HASHFLEET_LIVE_UI"] == "1" else {
            throw XCTSkip("Opt-in production public-data acceptance. Set TEST_RUNNER_HASHFLEET_LIVE_UI=1.")
        }
        continueAfterFailure = false
        let server = try LoopbackMinerServer()
        let readOnlyJSON = #"{"hostname":"read-only acceptance","hashRate":2000,"power":32,"version":"fixture","# +
            #""ASICModel":"BM1370","bestDiff":"18.4G","bestSessionDiff":"2M","# +
            #""stratumURL":"solo.ckpool.org","isUsingFallbackStratum":false}"#
        server.setInfoResponse(status: 200, json: readOnlyJSON)
        let cashServer = try LoopbackMinerServer()
        let bchJSON = #"{"hostname":"BCH acceptance","hashRate":1000,"power":19,"ASICModel":"BM1370","# +
            #""stratumURL":"bch.solofury.com","isUsingFallbackStratum":false}"#
        cashServer.setInfoResponse(status: 200, json: bchJSON)
        let extraServer = try LoopbackMinerServer()
        extraServer.setInfoResponse(status: 200, json: readOnlyJSON)
        let extraAddress = try extraServer.start()
        let address = try server.start()
        let cashAddress = try cashServer.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop(); cashServer.stop(); extraServer.stop() }
        app.launchArguments = ["--ui-testing", "--live-public-data"]
        app.launch()
        for minerAddress in [address, cashAddress, extraAddress] {
            addMiner(minerAddress, app: app)
        }
        verifyCoinSelection(app)
        let btc = app.descendants(matching: .any).matching(identifier: "dashboard.chain.BTC").firstMatch
        reveal(btc, app)
        let loadedPredicate = NSPredicate(
            format: "label CONTAINS %@ AND NOT label CONTAINS 'Unavailable' AND NOT label CONTAINS 'Needs fresh'", "%")
        let loaded = XCTNSPredicateExpectation(predicate: loadedPredicate, object: btc)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 30), .completed)
        let bch = app.descendants(matching: .any).matching(identifier: "dashboard.chain.BCH").firstMatch
        reveal(bch, app)
        XCTAssertTrue(bch.label.contains("%"), "BCH must use its own real difficulty source")
        XCTAssertFalse(bch.label.contains("Unavailable"))
        for coin in ["XEC", "DGB", "BC2", "BCH2"] {
            let row = app.descendants(matching: .any).matching(identifier: "dashboard.chain.\(coin)").firstMatch
            reveal(row, app)
            let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "%"), object: row)
            XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 35), .completed, "\(coin): \(row.label)")
            XCTAssertFalse(row.label.contains("Needs fresh"), row.label)
            if coin == "DGB" { XCTAssertTrue(row.label.contains("SoloPool.org"), row.label) }
            if coin == "BC2" || coin == "BCH2" { XCTAssertTrue(row.label.contains("SoloFury"), row.label) }
        }

        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "Actual public six-coin network odds output"
        home.lifetime = .keepAlways
        add(home)
        let details = app.buttons["dashboard.networkDetails"]
        reveal(details, app)
        details.tap()
        verifyNetworkDetails(app)
        let rendered = XCTAttachment(string: app.debugDescription)
        rendered.name = "Public service output hierarchy, no wallet"
        rendered.lifetime = .keepAlways
        add(rendered)
        XCTAssertTrue(server.writes.isEmpty && cashServer.writes.isEmpty && extraServer.writes.isEmpty)
        // Automatic live telemetry starts with a read-only WebSocket upgrade GET.
        let allowedPaths = ["/api/system/info", "/api/system/asic", "/api/ws/live"]
        for journal in [server.journal, cashServer.journal, extraServer.journal] {
            XCTAssertTrue(journal.allSatisfy { $0.method == "GET" && allowedPaths.contains($0.path) },
                "Unexpected requests: \(journal.map { "\($0.method) \($0.path)" })")
        }
    }

    func testPhysicalMinerMonitoringBootstrapsAutomaticallyReadOnly() throws {
        guard let address = ProcessInfo.processInfo.environment["HASHFLEET_LIVE_MINER_ADDRESS"],
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("Opt-in physical-miner acceptance. Set TEST_RUNNER_HASHFLEET_LIVE_MINER_ADDRESS.")
        }

        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing"]
        app.launch()

        addMiner(address, app: app)
        let miner = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")
        ).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 8))

        let live = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS[c] 'Live'"),
            object: miner
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [live], timeout: 25),
            .completed,
            "The physical miner should become live without a manual Refresh tap: \(miner.label)"
        )

        XCTAssertTrue(miner.label.contains("Power"), miner.label)
        XCTAssertTrue(miner.label.contains("W"), miner.label)

        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 8))
        let sampleAge = app.descendants(matching: .any)["detail.sampleAge"]
        XCTAssertTrue(sampleAge.waitForExistence(timeout: 8))
        XCTAssertEqual(sampleAge.label, "Live now")

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Physical miner loaded automatically through read-only monitoring"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func verifyCoinSelection(_ app: XCUIApplication) {
        func rows(_ coin: String) -> XCUIElementQuery {
            app.descendants(matching: .any).matching(identifier: "dashboard.chain.\(coin)")
        }
        reveal(rows("BTC").firstMatch, app)
        XCTAssertEqual(rows("BTC").count, 1)
        XCTAssertEqual(rows("BCH").count, 1)
        XCTAssertTrue(rows("BTC").firstMatch.label.contains("2 active miners"), rows("BTC").firstMatch.label)
        XCTAssertFalse(rows("BTC").firstMatch.frame.intersects(rows("BCH").firstMatch.frame))
        for coin in ["XEC", "DGB", "BC2", "BCH2"] { XCTAssertFalse(rows(coin).firstMatch.exists) }

        let selection = app.buttons["dashboard.coinSelection"]
        reveal(selection, app)
        selection.tap()
        let automatic = app.switches["coinSelection.automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 5))
        XCTAssertEqual(automatic.value as? String, "1")
        automatic.switches.firstMatch.tap()
        XCTAssertEqual(automatic.value as? String, "0")
        let clear = app.buttons["coinSelection.none"]
        reveal(clear, app)
        clear.tap()
        let dgb = app.switches["coinSelection.DGB"]
        reveal(dgb, app)
        dgb.switches.firstMatch.tap()
        XCTAssertEqual(dgb.value as? String, "1")
        app.navigationBars.buttons["Hash Fleet"].tap()
        reveal(rows("DGB").firstMatch, app)
        XCTAssertEqual(rows("DGB").count, 1)
        XCTAssertFalse(rows("BTC").firstMatch.exists)
        XCTAssertFalse(rows("BCH").firstMatch.exists)

        app.terminate()
        app.launchArguments.append("--ui-test-preserve-storage")
        app.launch()
        reveal(rows("DGB").firstMatch, app)
        XCTAssertEqual(rows("DGB").count, 1)
        XCTAssertFalse(rows("BTC").firstMatch.exists)
        reveal(selection, app)
        selection.tap()
        XCTAssertEqual(automatic.value as? String, "0")
        let all = app.buttons["coinSelection.all"]
        reveal(all, app)
        all.tap()
        app.navigationBars.buttons["Hash Fleet"].tap()
        for coin in ["BTC", "BCH", "XEC", "DGB", "BC2", "BCH2"] {
            XCTAssertEqual(rows(coin).count, 1)
        }
    }

    private func addMiner(_ address: String, app: XCUIApplication) {
        app.buttons["dashboard.addMiner"].tap()
        let input = app.textFields["addMiner.address"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(address + "\n")
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
    }

    private func verifyNetworkDetails(_ app: XCUIApplication) {
        let pools = app.buttons["Pool-reported network data"]
        reveal(pools, app)
        pools.tap()
        for coin in ["BTC", "BCH", "BC2", "BCH2", "XEC"] {
            for (field, title) in [("difficulty", "Reported network difficulty"), ("height", "Reported block height"), ("hashrate", "Pool hashrate · 1 hour"), ("counts", "Pool miners / workers")] {
                let reading = app.descendants(matching: .any).matching(identifier: "insights.poolNetwork.\(coin).\(field)").firstMatch
                reveal(reading, app)
                XCTAssertTrue(reading.label.contains(title), reading.label)
                XCTAssertFalse(reading.label.contains("Not reported"), reading.label)
                XCTAssertFalse(reading.label.contains("?"), reading.label)
                XCTAssertNotNil(reading.label.range(of: "[0-9]", options: .regularExpression), reading.label)
                if field == "hashrate" { XCTAssertTrue(reading.label.contains("H/s"), reading.label) }
            }
        }
        app.navigationBars.buttons["Network insights"].tap()
        let fee = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'Fastest' AND label CONTAINS 'sat/vB'")).firstMatch
        reveal(fee, app)
        XCTAssertTrue(fee.exists)
        let backlog = app.staticTexts["Mempool · waiting transactions"]
        reveal(backlog, app)
        XCTAssertTrue(backlog.exists)
        for coin in ["XEC", "DGB"] {
            for field in ["difficulty", "height"] {
                let reading = app.descendants(matching: .any).matching(identifier: "insights.coinNetwork.\(coin).\(field)").firstMatch
                reveal(reading, app)
                XCTAssertFalse(reading.label.contains("Not reported"), reading.label)
                XCTAssertNotNil(reading.label.range(of: "[0-9]", options: .regularExpression), reading.label)
                if coin == "DGB" && field == "difficulty" {
                    XCTAssertTrue(reading.label.contains("SHA-256d network difficulty"), reading.label)
                }
            }
        }
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<20 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        if !element.exists || !element.isHittable {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Unreachable element native hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.name = "Unreachable element screen"
            screen.lifetime = .keepAlways
            add(screen)
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
}
