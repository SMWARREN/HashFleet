import XCTest

extension DashboardCardInteractionUITests {
    func testNumberFirstMinerDetailAtStandardText() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for essentials in [true, false] {
            let mode = essentials ? "Essentials" : "Full View"
            let chart = verifyStandardTextMinerHistory(app, essentials: essentials, mode: mode)

            let cooling = app.buttons["detail.previewControls.cooling"]
            let tuning = app.buttons["detail.previewControls.tuning"]
            reveal(cooling, in: app)
            assertTapTarget(cooling)
            assertTapTarget(tuning)
            XCTAssertLessThan(chart.frame.maxY, cooling.frame.minY)
            XCTAssertLessThanOrEqual(cooling.frame.maxX, tuning.frame.minX)
            let actions = minerQuickActions.map { app.buttons["detail.quick.\($0.id)"] }
            reveal(actions[3], in: app)
            for action in actions {
                assertTapTarget(action)
                XCTAssertTrue(action.isHittable, "The quick actions are visible without opening another menu")
            }
            XCTAssertLessThanOrEqual(cooling.frame.maxY, actions[0].frame.minY)
            XCTAssertLessThan(actions[0].frame.minX, actions[1].frame.minX)
            XCTAssertEqual(actions[0].frame.minY, actions[1].frame.minY, accuracy: 2)
            XCTAssertLessThanOrEqual(actions[0].frame.maxY, actions[2].frame.minY)
            XCTAssertLessThan(actions[2].frame.minX, actions[3].frame.minX)
            XCTAssertEqual(actions[2].frame.minY, actions[3].frame.minY, accuracy: 2)
            capture("\(mode) Restored direct controls", app)

            let best = minerReading("detail.bestShare.ever", in: app)
            let sessionBest = minerReading("detail.bestShare.session", in: app)
            XCTAssertTrue(best.label.contains("18.40G"), best.label)
            XCTAssertTrue(sessionBest.label.contains("9.20M"), sessionBest.label)
            XCTAssertLessThan(actions[3].frame.maxY, best.frame.minY)
            reveal(best, in: app, requireHittable: false)
            capture("\(mode) Best shares", app)

            assertRemovedPreviewSections(app)
            let firmware = app.descendants(matching: .any)["detail.firmwareUpdates"].firstMatch
            let raw = app.buttons["detail.rawAPI"]
            let readings = app.staticTexts["Device readings"]
            XCTAssertFalse(app.staticTexts["Shares & uptime"].exists, "No duplicate shares card below controls")
            if essentials {
                for secondary in [app.staticTexts["More miner readings"], readings, firmware, raw,
                                  minerReading("detail.uptimeHeatmap", in: app)] {
                    XCTAssertFalse(secondary.exists, "Essentials ends after Best Shares")
                }
            } else {
                let activity = minerReading("detail.uptimeHeatmap", in: app)
                reveal(activity, in: app, requireHittable: false)
                XCTAssertLessThan(chart.frame.maxY, activity.frame.minY)
                XCTAssertLessThan(activity.frame.maxY, cooling.frame.minY)
                XCTAssertLessThan(activity.frame.maxY, readings.frame.minY)
                reveal(minerReading("detail.previewReading.Wi-Fi signal", in: app), in: app, requireHittable: false)
                for reading in ["Fan speed", "Voltage regulator", "Input voltage", "Fan duty", "Target temperature",
                                "Configured frequency", "Configured core voltage", "Efficiency", "Wi-Fi signal", "Firmware version"] {
                    XCTAssertTrue(minerReading("detail.previewReading.\(reading)", in: app).exists, "Missing reported \(reading)")
                }
                capture("Full View Device readings", app)
                reveal(raw, in: app)
                XCTAssertTrue(raw.isHittable)
                XCTAssertFalse(app.buttons["Firmware OTA update"].exists)
                capture("Full View Tools", app)
                raw.tap()
                XCTAssertTrue(app.navigationBars["System info"].waitForExistence(timeout: 5))
                let stored = minerReading("detail.previewRawInfo", in: app)
                XCTAssertTrue(stored.waitForExistence(timeout: 5))
                XCTAssertTrue(stored.label.contains("hashRate") && stored.label.contains("sharesAccepted"))
                XCTAssertTrue(stored.label.contains("[redacted]"))
                XCTAssertFalse(app.buttons["endpoint.send"].exists)
                capture("Full View Raw API", app)
                app.navigationBars.buttons.firstMatch.tap()
            }

            reveal(cooling, in: app)
            cooling.tap()
            let reading = app.descendants(matching: .any)["settings.cooling.temperatureReading"].firstMatch
            XCTAssertTrue(reading.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Demo settings are previews only"].exists)
            capture("\(mode) Cooling settings", app)
            app.navigationBars.buttons.firstMatch.tap()

            reveal(tuning, in: app)
            tuning.tap()
            let session = app.descendants(matching: .any)["tuningSession.screen"].firstMatch
            XCTAssertTrue(session.waitForExistence(timeout: 5))
            capture("\(mode) Tuning settings", app)
            app.navigationBars.buttons.firstMatch.tap()
            if essentials {
                verifyOneTapMinerQuickActions(app)
            } else {
                captureMinerQuickActionRoutes(app, mode: mode)
            }
            app.terminate()
        }
    }

    func testEssentialsQuickActionsAtLargestText() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openNumberFirstMinerDetail(app, essentials: true, largest: true)
        let button = app.buttons["detail.quick.identify"]
        let next = app.buttons["detail.quick.pause"]
        let result = applyPreviewQuickAction("identify", in: app)
        XCTAssertLessThanOrEqual(button.frame.maxY, result.frame.minY)
        XCTAssertLessThanOrEqual(result.frame.maxY, next.frame.minY)
        reveal(result, in: app, requireHittable: false)
        capture("Essentials Identify at largest text", app)
        _ = applyPreviewQuickAction("restart", in: app)
    }

    func testCaptureOriginalMinerWalkthrough() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openOriginalMiner(app)
        XCTAssertTrue(minerReading("detail.shares.accepted", in: app).exists)
        capture("Original miner overview", app)

        let chart = minerReading("dashboard.historyChart", in: app)
        reveal(chart, in: app, requireHittable: false)
        capture("Original Hashrate chart", app)
        let history = app.buttons["dashboard.viewHistory"]
        reveal(history, in: app)
        history.tap()
        let week = app.buttons["dashboard.historyRange.weekly"]
        reveal(week, in: app)
        capture("Original History options", app)
        reveal(history, in: app)
        history.tap()
        let tuning = app.buttons["detail.quick.tuning"]
        reveal(tuning, in: app)
        capture("Original Control miner panel", app)
        tuning.tap()
        XCTAssertTrue(minerReading("tuningSession.screen", in: app).waitForExistence(timeout: 5))
        capture("Original Tuning settings", app)
        app.navigationBars.buttons.firstMatch.tap()
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 5))
        capture("Original Miner settings page", app)
        app.navigationBars.buttons.firstMatch.tap()
        let restart = app.buttons["detail.quick.restart"]
        reveal(restart, in: app)
        capture("Original Direct actions", app)
        captureMinerQuickActionRoutes(app, mode: "Original")
    }

    func testCaptureOriginalMinerTools() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openOriginalMiner(app)
        let tools = app.buttons["detail.apiToolsDisclosure"]
        reveal(tools, in: app)
        tools.tap()
        let raw = app.buttons["detail.rawAPI"]
        reveal(raw, in: app)
        capture("Original API and diagnostics tools", app)
        raw.tap()
        XCTAssertTrue(app.navigationBars["System info"].waitForExistence(timeout: 5))
        capture("Original Raw API", app)
        app.navigationBars.buttons.firstMatch.tap()
        for (id, title) in [("diagnostics", "Diagnostics"), ("compatibility", "Check compatibility"),
                            ("endpointExplorer", "Endpoint explorer")] {
            let route = app.buttons["detail.\(id)"]
            reveal(route, in: app)
            route.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            capture("Original \(title)", app)
            app.navigationBars.buttons.firstMatch.tap()
        }
        reveal(tools, in: app)
        tools.tap()
        let fleetManagement = app.staticTexts["Fleet management"].firstMatch
        reveal(fleetManagement, in: app, requireHittable: false)
        capture("Original Fleet management", app)
    }

    func testCaptureOriginalMinerSupplementalReadings() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openOriginalMiner(app)
        openOriginalMoreReadings(app)
        let best = minerReading("detail.bestShare.ever", in: app)
        reveal(best, in: app, requireHittable: false)
        capture("Original Best shares and activity", app)
        let identity = app.buttons["detail.identityDisclosure"]
        reveal(identity, in: app)
        identity.tap()
        reveal(app.staticTexts["Firmware"], in: app, requireHittable: false)
        capture("Original identity and firmware", app)
        let cooling = app.buttons["detail.coolingDisclosure"]
        reveal(cooling, in: app)
        if cooling.value as? String != "Expanded" { cooling.tap() }
        let coolingNote = app.staticTexts["Temperature labels follow the reported sensors, not ASIC count."]
        XCTAssertTrue(coolingNote.waitForExistence(timeout: 5))
        reveal(coolingNote, in: app, requireHittable: false)
        capture("Original Device readings", app)
        let coolingSettings = app.buttons["detail.cooling.settings"]
        reveal(coolingSettings, in: app)
        coolingSettings.tap()
        XCTAssertTrue(minerReading("settings.cooling.temperatureReading", in: app).waitForExistence(timeout: 5))
        capture("Original Cooling settings", app)
        app.navigationBars.buttons.firstMatch.tap()
        let pools = app.buttons["detail.poolsDisclosure"]
        reveal(pools, in: app)
        pools.tap()
        capture("Original Pool status", app)
    }

    func testCaptureOriginalMinerASICReadings() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openOriginalMiner(app, essentials: false, extraArguments: ["--ui-test-asic-telemetry"])
        let asic = app.buttons["detail.asicTelemetry.disclosure"]
        reveal(asic, in: app)
        asic.tap()
        let domain = minerReading("detail.asicDomain.0.0", in: app)
        reveal(domain, in: app, requireHittable: false)
        XCTAssertTrue(domain.label.contains("building trend"))
        capture("Original ASIC registers and domain readings", app)
    }

    func testCaptureFullViewMinerHistory() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openNumberFirstMinerDetail(app, essentials: false, largest: false)
        app.chooseSavedHistoryWindow("weekly", beforeSelection: {
            self.capture("Full View individual miner History options", app)
        })
        XCTAssertTrue(app.staticTexts["No readings in this time window yet."].waitForExistence(timeout: 5))
    }

    func testNumberFirstMinerDetailHidesUnavailableAPISections() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for mode in ["limited", "read-only"] {
            for essentials in [true, false] {
                openNumberFirstMinerDetail(app, essentials: essentials, largest: false,
                                          extraArguments: ["--ui-test-preview-detail-\(mode)", "--ui-test-asic-telemetry"])
                assertRemovedPreviewSections(app)
                XCTAssertFalse(app.staticTexts["Control miner"].exists)
                XCTAssertFalse(app.buttons["detail.previewControls.cooling"].exists)
                XCTAssertFalse(app.buttons["detail.previewControls.tuning"].exists)
                for action in minerQuickActions {
                    XCTAssertFalse(app.buttons["detail.quick.\(action.id)"].exists)
                }
                XCTAssertFalse(app.staticTexts["Firmware updates"].exists)
                XCTAssertEqual(app.buttons["detail.rawAPI"].exists, !essentials, "A permitted read is separate from settings access")
                let temperature = app.descendants(matching: .any)["detail.hero.temperature"].firstMatch
                XCTAssertEqual(temperature.exists, mode == "read-only", "Denied writes must not hide valid readings")
                for reading in ["detail.shares.accepted", "detail.shares.rejected", "detail.uptime", "detail.bestShare.ever"] {
                    XCTAssertEqual(minerReading(reading, in: app).exists, mode == "read-only", reading)
                }
                XCTAssertEqual(app.staticTexts["Device readings"].exists, mode == "read-only" && !essentials)
                XCTAssertTrue(app.descendants(matching: .any)["dashboard.historyChart"].firstMatch.exists)
                capture("\(essentials ? "Essentials" : "Full View") \(mode) miner", app)
                app.terminate()
            }
        }
    }

    func testNumberFirstMinerDetailAtLargestText() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for essentials in [true, false] {
            let mode = essentials ? "Essentials" : "Full View"
            openNumberFirstMinerDetail(app, essentials: essentials, largest: true)
            capture("\(mode) miner detail at largest text", app)
            let chart = assertNumberFirstMinerReadings(app)
            // Check that the preview still responds to the accessibility setting instead of
            // borrowing the dashboard's compact text-size cap.
            XCTAssertGreaterThan(app.descendants(matching: .any)["detail.previewHashrate"].firstMatch.frame.height, 80)
            let metric = app.buttons["detail.historyMetric"]
            let history = app.buttons[essentials ? "dashboard.viewHistory" : "dashboard.historyDisplay"]
            reveal(metric, in: app)
            assertTapTarget(metric)
            reveal(history, in: app)
            assertTapTarget(history)
            reveal(chart, in: app, requireHittable: false)
            capture("\(mode) individual miner chart at largest text", app)
            reveal(history, in: app)
            history.tap()
            for option in ["weekly", "monthly", "yearly"] {
                let action = app.buttons["dashboard.historyRange.\(option)"].firstMatch
                XCTAssertTrue(action.waitForExistence(timeout: 5))
                assertTapTarget(action)
                if essentials { reveal(action, in: app) }
                XCTAssertTrue(action.isHittable)
            }
            XCTAssertFalse(app.buttons["Individual miners"].exists, "A single miner needs no fleet comparison selector")
            capture("\(mode) individual miner History at largest text", app)
            app.buttons["dashboard.historyRange.yearly"].firstMatch.tap()
            let yearlyCaption = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "· Last 365 days ·")).firstMatch
            XCTAssertTrue(yearlyCaption.waitForExistence(timeout: 5))
            if essentials {
                reveal(history, in: app)
                history.tap()
            }
            let cooling = app.buttons["detail.previewControls.cooling"]
            let tuning = app.buttons["detail.previewControls.tuning"]
            reveal(tuning, in: app)
            for control in [cooling, tuning] { assertTapTarget(control) }
            XCTAssertLessThanOrEqual(cooling.frame.maxY, tuning.frame.minY)
            capture("\(mode) Compact controls at largest text", app)
            let identify = app.buttons["detail.quick.identify"]
            let pause = app.buttons["detail.quick.pause"]
            reveal(pause, in: app)
            assertTapTarget(identify)
            assertTapTarget(pause)
            XCTAssertEqual(identify.frame.minX, pause.frame.minX, accuracy: 2)
            XCTAssertLessThanOrEqual(identify.frame.maxY, pause.frame.minY)
            capture("\(mode) Direct actions at largest text", app)
            app.terminate()
        }
    }

    private func verifyStandardTextMinerHistory(
        _ app: XCUIApplication, essentials: Bool, mode: String
    ) -> XCUIElement {
        openNumberFirstMinerDetail(app, essentials: essentials, largest: false)
        capture("\(mode) miner detail at standard text", app)
        let chart = assertNumberFirstMinerReadings(app)
        assertRestoredShareReadings(app)
        XCTAssertLessThan(chart.frame.minY, app.frame.maxY, "The opening view should show the trend")
        if !essentials {
            let updates = app.buttons["detail.firmwareDisclosure"]
            let example = app.staticTexts["Demo release example · no install"]
            XCTAssertTrue(updates.isHittable)
            XCTAssertLessThan(updates.frame.maxY, minerReading("detail.previewHashrate", in: app).frame.minY)
            XCTAssertEqual(updates.value as? String, "Collapsed")
            XCTAssertFalse(example.exists)
            updates.tap()
            XCTAssertTrue(example.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Firmware OTA update"].exists)
            capture("Full View firmware disclosure expanded", app)
            updates.tap()
            XCTAssertFalse(example.exists)
        }
        let history = app.buttons[essentials ? "dashboard.viewHistory" : "dashboard.historyDisplay"]
        reveal(history, in: app)
        assertTapTarget(history)
        if essentials {
            history.tap()
            let week = app.buttons["dashboard.historyRange.weekly"]
            XCTAssertTrue(week.waitForExistence(timeout: 5))
            capture("Essentials individual miner History options", app)
            week.tap()
            history.tap()
        } else {
            app.chooseSavedHistoryWindow("weekly", beforeSelection: {
                self.capture("Full View individual miner History options", app)
            })
        }
        XCTAssertTrue(app.staticTexts["No readings in this time window yet."].waitForExistence(timeout: 5))

        let recent = app.buttons[essentials ? "dashboard.historyRangeMenu" : "dashboard.historyRange.oneMinute"]
        reveal(recent, in: app)
        assertTapTarget(recent)
        recent.tap()
        if essentials {
            let minute = app.descendants(matching: .any)["dashboard.historyRange.oneMinute"].firstMatch
            XCTAssertTrue(minute.waitForExistence(timeout: 5))
            minute.tap()
        }
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertTrue((chart.value as? String ?? "").contains("Last minute"))
        let metric = app.buttons["detail.historyMetric"]
        reveal(metric, in: app)
        assertTapTarget(metric)
        metric.tap()
        let temperature = app.descendants(matching: .any)["detail.historyMetric.temperature"].firstMatch
        XCTAssertTrue(temperature.waitForExistence(timeout: 5))
        temperature.tap()
        XCTAssertTrue(app.staticTexts["Temperature trend"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample miners don’t store temperature or power history."].exists)
        metric.tap()
        app.descendants(matching: .any)["detail.historyMetric.hashrate"].firstMatch.tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        reveal(chart, in: app, requireHittable: false)
        capture("\(mode) Hashrate chart", app)
        return chart
    }
}
