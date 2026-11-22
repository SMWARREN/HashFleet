import XCTest

extension DashboardCardInteractionUITests {
    func testNumberFirstPreviewKeepsNativeHistoryAndMinerActions() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        for essentials in [true, false] {
            app.launchArguments = numberFirstArguments
                + (essentials ? ["--ui-test-dashboard-essentials"] : ["--ui-test-light-appearance"])
                + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launch()

            let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 10))
            XCTAssertTrue(chart.label.contains("Simulated fleet hashrate"), chart.label)
            let rate = app.descendants(matching: .any)["dashboard.fleetHashrate"].firstMatch
            XCTAssertTrue(rate.label.contains("3.02 TH/s"), rate.label)
            XCTAssertTrue(app.staticTexts["3 sample miners"].exists)
            let miner = firstNumberFirstMiner(in: app)
            XCTAssertTrue(miner.waitForExistence(timeout: 5))
            XCTAssertLessThan(chart.frame.maxY, miner.frame.minY)
            XCTAssertTrue(miner.isHittable)
            XCTAssertTrue(miner.label.contains("Temperature") && miner.label.contains("Power"), miner.label)

            let range = app.buttons[essentials ? "dashboard.historyRangeMenu" : "dashboard.historyRange.oneMinute"]
            let history = app.buttons[essentials ? "dashboard.viewHistory" : "dashboard.historyDisplay"]
            for action in [range, history, app.buttons["dashboard.exitDemo"], app.buttons["dashboard.minerDisplay"]] {
                assertTapTarget(action)
            }
            assertCompactPreviewLayout(in: app, largestType: false)
            assertRangeBarLayout(in: app, range: range, history: history)
            try app.performAccessibilityAudit(for: [.contrast, .textClipped])
            capture(essentials ? "Essentials range bar" : "Full View range bar", app)
            if essentials {
                // This point is inside the 44pt target but above the painted pill.
                history.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
                XCTAssertTrue(app.staticTexts["Saved history"].waitForExistence(timeout: 5))
                let week = app.buttons["dashboard.historyRange.weekly"]
                XCTAssertTrue(week.exists)
                week.tap()
                history.tap()
            } else {
                XCTAssertTrue(range.isSelected)
                app.chooseSavedHistoryWindow("weekly")
            }
            let savedCaption = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "· Last 7 days ·")).firstMatch
            XCTAssertTrue(savedCaption.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["No readings in this time window yet."].exists)
            capture(essentials ? "Essentials saved range" : "Full View saved range", app)
            range.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            if essentials {
                let minute = app.descendants(matching: .any)["dashboard.historyRange.oneMinute"].firstMatch
                XCTAssertTrue(minute.waitForExistence(timeout: 5))
                minute.tap()
            } else {
                XCTAssertTrue(range.isSelected)
            }
            XCTAssertTrue(chart.waitForExistence(timeout: 5))
            XCTAssertTrue((chart.value as? String ?? "").contains("Last minute"))

            let id = String(miner.identifier.dropFirst("dashboard.miner.".count))
            let expand = app.buttons["dashboard.card.expand.\(id)"]
            let controls = app.buttons["dashboard.card.settings.\(id)"]
            reveal(expand, in: app)
            assertTapTarget(expand)
            assertTapTarget(controls)
            assertSingleRow(left: expand.frame, right: controls.frame)
            XCTAssertEqual(expand.value as? String, "Collapsed")
            expand.tap()
            XCTAssertEqual(expand.value as? String, "Expanded")
            XCTAssertTrue(miner.label.contains("Fan speed"), miner.label)
            if essentials {
                reveal(miner, in: app)
                miner.tap()
                XCTAssertTrue(app.navigationBars["Little Supra"].waitForExistence(timeout: 8))
            }
            app.terminate()
        }
    }

    func testNumberFirstPreviewAtLargestType() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = numberFirstArguments + ["--ui-test-dashboard-essentials", "--ui-test-light-appearance",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        let range = app.buttons["dashboard.historyRangeMenu"]
        let history = app.buttons["dashboard.viewHistory"]
        let overviewHeadingHeight = assertCompactPreviewLayout(in: app, largestType: true)
        capture("Essentials overview at largest system text", app)
        reveal(history, in: app)
        assertRangeBarLayout(in: app, range: range, history: history)
        capture("Essentials slim range bar at largest type", app)

        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        reveal(chart, in: app)
        XCTAssertGreaterThan(chart.frame.height, 100)
        XCTAssertTrue((chart.value as? String ?? "").contains("Last minute"))
        capture("Number-first chart at largest type", app)

        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                       "dashboard.miner.", "Little Supra")).firstMatch
        reveal(miner, in: app)
        for reading in ["Hashrate", "Sample", "Temperature", "degrees Celsius", "Power", "watts"] {
            XCTAssertTrue(miner.label.contains(reading), "Missing \(reading): \(miner.label)")
        }
        let id = String(miner.identifier.dropFirst("dashboard.miner.".count))
        let expand = app.buttons["dashboard.card.expand.\(id)"]
        let controls = app.buttons["dashboard.card.settings.\(id)"]
        reveal(controls, in: app)
        assertTapTarget(expand)
        assertTapTarget(controls)
        assertSingleRow(left: expand.frame, right: controls.frame)
        capture("Number-first miner controls at largest type", app)

        reveal(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Little Supra"].waitForExistence(timeout: 8))
        let detailHeading = app.staticTexts["Hashrate trend"].firstMatch
        XCTAssertTrue(detailHeading.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(detailHeading.frame.height, overviewHeadingHeight * 1.5,
                             "The overview's type cap must not travel to miner detail")
    }

    func testNumberFirstFullRangeBarAtLargestType() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = numberFirstArguments
            + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        let minute = app.buttons["dashboard.historyRange.oneMinute"]
        let history = app.buttons["dashboard.historyDisplay"]
        assertCompactPreviewLayout(in: app, largestType: true)
        capture("Full View overview at largest system text", app)
        reveal(history, in: app)
        assertRangeBarLayout(in: app, range: minute, history: history)
        capture("Full View slim range bar at largest type", app)

        history.tap()
        let yearly = app.buttons["dashboard.historyRange.yearly"].firstMatch
        XCTAssertTrue(yearly.waitForExistence(timeout: 5))
        for id in ["weekly", "monthly", "yearly"] {
            let option = app.buttons["dashboard.historyRange.\(id)"].firstMatch
            assertTapTarget(option)
            XCTAssertTrue(option.isHittable, "\(id) must fit inside the largest-text popover on the opening screen")
        }
        capture("Full View History options at largest type", app)
        let individual = app.buttons["Individual miners"].firstMatch
        let fleetTotal = app.buttons["Fleet total"].firstMatch
        assertSingleRow(left: fleetTotal.frame, right: individual.frame)
        for choice in [individual, fleetTotal] {
            assertTapTarget(choice)
            XCTAssertTrue(choice.isHittable)
            choice.tap()
            XCTAssertTrue(choice.isSelected)
            if choice == individual {
                capture("Full View History with Individual miners selected at largest type", app)
            }
        }
        yearly.tap()
        XCTAssertTrue((history.value as? String ?? "").contains("Last 365 days"))
        reveal(minute, in: app)
        minute.tap()
        XCTAssertTrue(minute.isSelected)
    }

    func testNumberFirstSoloOddsKeepsTheSlimChartAndShowsTheBlockReward() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        for essentials in [true, false] {
            let name = essentials ? "Essentials" : "Full View"
            app.launchArguments = numberFirstArguments
                + (essentials ? ["--ui-test-dashboard-essentials", "--ui-test-light-appearance"] : [])
                + ["-UIPreferredContentSizeCategoryName", essentials ? "UICTContentSizeCategoryL" : "UICTContentSizeCategoryAccessibilityXXXL",
                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()

            let recent = app.buttons[essentials ? "dashboard.historyRangeMenu" : "dashboard.historyRange.oneMinute"]
            let history = app.buttons[essentials ? "dashboard.viewHistory" : "dashboard.historyDisplay"]
            XCTAssertTrue(recent.waitForExistence(timeout: 10))
            assertRangeBarLayout(in: app, range: recent, history: history)

            let layout = assertSoloOddsDashboardLayout(app, essentials: essentials, recent: recent, history: history)
            let row = layout.row
            let day = layout.day
            let month = layout.month
            let year = layout.year
            let monthly = row.label
            XCTAssertTrue(month.isSelected)
            XCTAssertTrue(monthly.contains("30-day") && monthly.contains("1 in"), monthly)
            let rewardAndValue = "Block reward 3.125 BTC. ≈ $250,000 per block."
            XCTAssertTrue(monthly.hasPrefix(rewardAndValue), monthly)
            XCTAssertFalse(monthly.contains("Price ") || monthly.contains("$80,000"), monthly)
            capture("\(name) opening chart then Solo odds", app)

            day.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07)).tap()
            XCTAssertTrue(day.isSelected)
            let daily = row.label
            XCTAssertTrue(daily.contains("1-day") && daily.hasPrefix(rewardAndValue), daily)
            XCTAssertNotEqual(monthly.components(separatedBy: "Chance ").last, daily.components(separatedBy: "Chance ").last)
            year.tap()
            XCTAssertTrue(year.isSelected)
            let annual = row.label
            XCTAssertTrue(annual.contains("1-year") && annual.hasPrefix(rewardAndValue), annual)
            XCTAssertNotEqual(daily.components(separatedBy: "Chance ").last, annual.components(separatedBy: "Chance ").last)

            chooseSoloOption("Show assumptions", id: "dashboard.soloAssumptions", in: app)
            let explanation = app.staticTexts["dashboard.soloAssumptionsDetails"]
            XCTAssertTrue(explanation.waitForExistence(timeout: 5))
            XCTAssertTrue(explanation.label.contains("excluding transaction fees"))
            XCTAssertTrue(explanation.label.contains("prices, not live"))
            XCTAssertTrue(explanation.label.contains("Neither is a promised miner payout"))
            chooseSoloOption("Hide assumptions", id: "dashboard.soloAssumptions", in: app)
            XCTAssertFalse(explanation.exists)
            try app.performAccessibilityAudit(for: [.contrast, .textClipped])

            if essentials {
                chooseSoloOption("Coins to show", id: "dashboard.coinSelection", in: app)
                XCTAssertTrue(app.navigationBars["Coins to show"].waitForExistence(timeout: 5))
                let automatic = app.switches["coinSelection.automatic"]
                reveal(automatic, in: app)
                XCTAssertEqual(automatic.value as? String, "1")
                automatic.switches.firstMatch.tap()
                XCTAssertEqual(automatic.value as? String, "0")
                let selectAll = app.buttons["coinSelection.all"]
                reveal(selectAll, in: app)
                selectAll.tap()
                app.navigationBars.buttons["Hash Fleet"].tap()
                let usesCoinUnits = [("BTC", "3.125"), ("BCH", "3.125"), ("XEC", "3,125,000"),
                                    ("DGB", "300.04549168"), ("BC2", "50"), ("BCH2", "50")]
                for (ticker, reward) in usesCoinUnits {
                    let coin = app.descendants(matching: .any)["dashboard.chain.\(ticker)"].firstMatch
                    XCTAssertTrue(coin.exists)
                    XCTAssertTrue(coin.label.contains("Block reward \(reward) \(ticker)"), coin.label)
                }
                let fromQuote = [("BCH", "$812.50"), ("XEC", "$84.38"), ("DGB", "$2.40")]
                for (ticker, value) in fromQuote {
                    let coin = app.descendants(matching: .any)["dashboard.chain.\(ticker)"].firstMatch
                    XCTAssertTrue(coin.label.contains("≈ \(value) per block"), coin.label)
                }
                for ticker in ["BC2", "BCH2"] {
                    let coin = app.descendants(matching: .any)["dashboard.chain.\(ticker)"].firstMatch
                    XCTAssertTrue(coin.label.contains("USD value unavailable"), coin.label)
                }
            } else {
                chooseSoloOption("Network", id: "dashboard.networkDetails", in: app)
                XCTAssertTrue(app.navigationBars["Network insights"].waitForExistence(timeout: 8))
            }
            app.terminate()
        }
    }

    private func assertSoloOddsDashboardLayout(
        _ app: XCUIApplication, essentials: Bool, recent: XCUIElement, history: XCUIElement
    ) -> (row: XCUIElement, day: XCUIElement, month: XCUIElement, year: XCUIElement) {
        let panel = app.descendants(matching: .any)["dashboard.chains"].firstMatch
        let row = app.descendants(matching: .any)["dashboard.chain.BTC"].firstMatch
        let heading = app.staticTexts["Solo odds"]
        let day = app.buttons["dashboard.soloOddsWindow.day"]
        let month = app.buttons["dashboard.soloOddsWindow.month"]
        let year = app.buttons["dashboard.soloOddsWindow.year"]
        let options = app.buttons["dashboard.soloOptions"]
        let rate = app.descendants(matching: .any)["dashboard.fleetHashrate"].firstMatch
        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        let chartHeading = app.staticTexts["Hashrate trend"].firstMatch
        let minersHeading = app.staticTexts["Your miners"].firstMatch
        let miner = firstNumberFirstMiner(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.exists && minersHeading.exists && miner.exists && rate.exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "dashboard.chains").count, 1)
        XCTAssertGreaterThan(rate.frame.minY, app.navigationBars["Hash Fleet"].frame.maxY)
        XCTAssertLessThan(rate.frame.maxY, chartHeading.frame.minY)
        XCTAssertLessThan(chart.frame.maxY, panel.frame.minY)
        XCTAssertLessThan(panel.frame.maxY, minersHeading.frame.minY)
        XCTAssertLessThan(minersHeading.frame.maxY, miner.frame.minY)
        let comparison = app.descendants(matching: .any)["dashboard.hashrateShare"].firstMatch
        if essentials {
            XCTAssertFalse(comparison.exists)
            XCTAssertTrue(app.descendants(matching: .any)["dashboard.fleetArtwork"].firstMatch.exists)
            XCTAssertLessThan(panel.frame.maxY, app.frame.maxY - 12,
                              "The reward and chart must fit on the opening Essentials screen")
        } else {
            XCTAssertTrue(comparison.exists)
            XCTAssertLessThan(chart.frame.maxY, comparison.frame.minY)
            XCTAssertLessThan(comparison.frame.maxY, panel.frame.minY)
            // Full View now places the share card ahead of Solo odds. Scroll to it after checking order.
            reveal(options, in: app)
        }
        // No swipe or scroll before these checks: both metrics fit in a single short row.
        XCTAssertLessThanOrEqual(panel.frame.height, 114)
        XCTAssertLessThanOrEqual(heading.frame.height, 22)
        XCTAssertLessThanOrEqual(row.frame.height, 57)
        assertSingleRow(left: heading.frame, right: day.frame)
        assertSingleRow(left: day.frame, right: month.frame)
        assertSingleRow(left: month.frame, right: year.frame)
        assertSingleRow(left: year.frame, right: options.frame)
        for button in [day, month, year, options] {
            assertTapTarget(button)
            XCTAssertTrue(button.isHittable, button.identifier)
        }
        for button in [recent, history] { assertTapTarget(button) }

        return (row, day, month, year)
    }
}
