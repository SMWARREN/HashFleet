import XCTest

/// Dashboard controls must remain independent of the details link and never send settings writes.
@MainActor
final class DashboardCardInteractionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNumberFirstMinerDetailAtStandardText() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for essentials in [true, false] {
            let mode = essentials ? "Essentials" : "Full View"
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

    private func openOriginalMiner(_ app: XCUIApplication, essentials: Bool = true, extraArguments: [String] = []) {
        // Use the same entry dashboard as the preview, but never enable the detail
        // opt-in. The caller can run these walkthroughs against the untouched source.
        app.launchArguments = numberFirstArguments + (essentials ? ["--ui-test-dashboard-essentials"] : []) + extraArguments
        app.launch()
        let miner = firstNumberFirstMiner(in: app)
        reveal(miner, in: app)
        XCTAssertTrue(miner.label.contains("Little Supra"), miner.label)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Little Supra"].waitForExistence(timeout: 8))
        XCTAssertFalse(minerReading("detail.previewHashrate", in: app).exists)
    }

    private func openOriginalMoreReadings(_ app: XCUIApplication) {
        let more = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "More miner readings")).firstMatch
        reveal(more, in: app)
        more.tap()
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

    private func assertRemovedPreviewSections(_ app: XCUIApplication) {
        for id in ["detail.asicTelemetry.disclosure", "detail.poolDiagnostics", "detail.poolsDisclosure",
                   "detail.apiToolsDisclosure", "detail.advancedSection", "detail.endpointExplorer"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].firstMatch.exists, "Unexpected legacy section: \(id)")
        }
        XCTAssertFalse(app.staticTexts["ASIC Registers"].exists)
        XCTAssertFalse(app.staticTexts["Pool connection"].exists)
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

    func testCoolingPreviewEssentialsAppliesInPlace() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openCooling(app, essentials: true)
        let commit = app.buttons["cooling.commit"]
        let automatic = app.buttons["cooling.mode.automatic"]
        let manual = app.buttons["cooling.mode.manual"]
        assertTapTarget(automatic)
        assertTapTarget(manual)
        XCTAssertTrue(automatic.isSelected)
        XCTAssertEqual(commit.label, "Apply Changes")
        XCTAssertFalse(commit.isEnabled)
        XCTAssertEqual(app.staticTexts["settings.cooling.fanSpeedReading"].label, "65 %")

        stepCooling("temptarget", in: app, increasing: true, to: 56)
        XCTAssertFalse(app.staticTexts["cooling.result"].exists)
        assertTapTarget(commit)
        reveal(commit, in: app)
        capture("Essentials Cooling settings revised", app)
        commit.tap()
        XCTAssertTrue(app.staticTexts["cooling.result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["cooling.review.json"].exists)
        XCTAssertFalse(app.navigationBars["Review cooling changes"].exists)
        XCTAssertFalse(commit.isEnabled)
        capture("Essentials Cooling applied", app)

        stepCooling("minFanSpeed", in: app, increasing: false, to: 24)
        reveal(manual, in: app)
        manual.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.8)).tap()
        XCTAssertTrue(manual.isSelected, "One tap near the edge must select Manual")
        XCTAssertFalse(automatic.isSelected)
        XCTAssertTrue(app.staticTexts["cooling.manualFanSpeed.value"].label.contains("60"))
        XCTAssertFalse(app.staticTexts["cooling.minFanSpeed.value"].exists)
        stepCooling("manualFanSpeed", in: app, increasing: true, to: 61)
        capture("Essentials Cooling manual", app)
        reveal(automatic, in: app)
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.8)).tap()
        XCTAssertTrue(automatic.isSelected, "One tap near the edge must select Automatic")
        XCTAssertFalse(manual.isSelected)
        XCTAssertTrue(app.staticTexts["cooling.minFanSpeed.value"].label.contains("24"))
    }

    func testCoolingPreviewFullReviewsJSON() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openCooling(app, essentials: false)
        let commit = app.buttons["cooling.commit"]
        let automatic = app.buttons["cooling.mode.automatic"]
        let manual = app.buttons["cooling.mode.manual"]
        XCTAssertTrue(automatic.isSelected)
        XCTAssertEqual(commit.label, "Review Changes")
        XCTAssertFalse(commit.isEnabled)
        stepCooling("temptarget", in: app, increasing: true, to: 56)
        reveal(commit, in: app)
        capture("Full View Cooling settings revised", app)
        commit.tap()

        let json = app.staticTexts["cooling.review.json"]
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        XCTAssertTrue(json.label.contains("\"temptarget\""))
        XCTAssertTrue(json.label.contains("56"))
        for unedited in ["autofanspeed", "minFanSpeed", "manualFanSpeed", "overheat"] {
            XCTAssertFalse(json.label.contains(unedited))
        }
        capture("Full View Cooling JSON review", app)
        app.buttons["cooling.review.cancel"].tap()
        XCTAssertTrue(commit.waitForExistence(timeout: 5))
        XCTAssertTrue(commit.isEnabled)
        XCTAssertTrue(app.staticTexts["cooling.temptarget.value"].label.contains("56"))
        XCTAssertFalse(app.staticTexts["cooling.result"].exists)
        commit.tap()
        let apply = app.buttons["cooling.review.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()
        XCTAssertTrue(app.staticTexts["cooling.result"].waitForExistence(timeout: 5))
        XCTAssertFalse(commit.isEnabled)

        reveal(manual, in: app)
        manual.tap()
        XCTAssertTrue(manual.isSelected)
        stepCooling("manualFanSpeed", in: app, increasing: true, to: 61)
        capture("Full View Cooling manual", app)
        commit.tap()
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        XCTAssertTrue(json.label.contains("\"autofanspeed\""))
        XCTAssertTrue(json.label.contains("\"manualFanSpeed\""))
        XCTAssertTrue(json.label.contains("61"))
        XCTAssertFalse(json.label.contains("\"temptarget\""))
    }

    func testCoolingPreviewDoesNotOfferMissingConfiguration() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openCooling(app, essentials: true, extraArguments: ["--ui-test-preview-cooling-partial"])
        XCTAssertEqual(app.staticTexts["cooling.mode.fixed"].label, "Automatic mode")
        XCTAssertFalse(app.buttons["cooling.mode.automatic"].exists)
        XCTAssertFalse(app.buttons["cooling.mode.manual"].exists)
        XCTAssertFalse(app.buttons["cooling.mode.menu"].exists)
        XCTAssertFalse(app.buttons["cooling.minFanSpeed.increase"].exists)
        XCTAssertFalse(app.buttons["cooling.manualFanSpeed.increase"].exists)
        stepCooling("temptarget", in: app, increasing: false, to: 54)
    }

    func testCoolingPreviewAtLargestText() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openCooling(app, essentials: true, largest: true)
        let mode = app.buttons["cooling.mode.menu"]
        reveal(mode, in: app)
        assertTapTarget(mode)
        XCTAssertEqual(mode.value as? String, "Automatic")
        capture("Essentials Cooling selector at largest text", app)
        for next in ["Manual", "Automatic"] {
            mode.tap()
            let choice = app.buttons[next].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
            XCTAssertEqual(mode.value as? String, next)
        }
        stepCooling("temptarget", in: app, increasing: true, to: 56)
        assertTapTarget(app.buttons["cooling.temptarget.decrease"])
        capture("Essentials Cooling adjuster at largest text", app)
        let commit = app.buttons["cooling.commit"]
        reveal(commit, in: app)
        assertTapTarget(commit)
        commit.tap()
        XCTAssertTrue(app.staticTexts["cooling.result"].waitForExistence(timeout: 5))
    }

    func testTuningPreviewEssentialsAppliesInPlace() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openTuningPreview(app, essentials: true)
        assertTuningMeasurements(in: app)
        XCTAssertTrue(app.staticTexts["Adjust settings"].exists)
        XCTAssertFalse(app.staticTexts["Tuning draft"].exists)
        let advanced = app.switches["tuningSession.advancedToggle"]
        XCTAssertTrue(advanced.isHittable)
        XCTAssertEqual(advanced.value as? String, "0")
        let apply = app.buttons["tuning.preview.apply"]
        let warning = app.staticTexts["tuning.preview.risk"]
        XCTAssertEqual(apply.label, "Apply Changes")
        XCTAssertFalse(apply.isEnabled)
        let increase = app.buttons["tuning.preview.frequency.increase"]
        reveal(increase, in: app)
        assertTapTarget(increase)
        increase.tap()
        XCTAssertEqual(app.textFields["tuning.preview.frequency.input"].value as? String, "526")
        XCTAssertEqual(app.staticTexts["tuning.preview.frequency.configured"].label, "Configured 525 MHz")
        reveal(apply, in: app)
        assertTapTarget(apply)
        XCTAssertTrue(warning.isHittable)
        XCTAssertTrue(warning.label.contains("damage hardware"))
        XCTAssertLessThan(warning.frame.maxY, apply.frame.minY)
        capture("Essentials Tuning one-step settings", app)
        apply.tap()
        let result = app.staticTexts["tuning.preview.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "Applied in this demo. Nothing sent.")
        XCTAssertFalse(apply.isEnabled)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.navigationBars["Review tuning changes"].exists)
        XCTAssertFalse(app.switches["tuning.preview.acknowledge"].exists)
        XCTAssertFalse(app.staticTexts["tuning.preview.json"].exists)
        XCTAssertEqual(app.staticTexts["tuning.preview.frequency.configured"].label, "Configured 525 MHz")
        assertTuningMeasurements(in: app)
        capture("Essentials Tuning applied in place", app)

        app.buttons["tuning.preview.reset"].tap()
        XCTAssertFalse(result.exists)
        XCTAssertFalse(apply.isEnabled)
        let voltage = app.buttons["tuning.preview.coreVoltage.decrease"]
        reveal(voltage, in: app)
        voltage.tap()
        XCTAssertEqual(app.textFields["tuning.preview.coreVoltage.input"].value as? String, "1145")
        apply.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.navigationBars["Review tuning changes"].exists)
    }

    func testTuningPreviewEssentialsAdvancedKeepsEasyDraftAndReviewSafeguards() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        openTuningPreview(app, essentials: true)
        let advanced = app.switches["tuningSession.advancedToggle"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        XCTAssertEqual(advanced.label, "Advanced")
        XCTAssertTrue(advanced.isHittable, "The switch must be visible without scrolling in Essentials.")
        XCTAssertTrue(advanced.isEnabled)
        XCTAssertEqual(advanced.value as? String, "0")
        XCTAssertFalse(app.buttons["tuningSession.master.plus10"].exists)
        XCTAssertFalse(app.segmentedControls["tuning.preview.mode"].exists)
        capture("Essentials Advanced switch off", app)
        let switchY = advanced.frame.midY
        let switchTarget = advanced.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        let increase = app.buttons["tuning.preview.frequency.increase"]
        reveal(increase, in: app)
        increase.tap()
        let easyInput = app.textFields["tuning.preview.frequency.input"]
        XCTAssertEqual(easyInput.value as? String, "526")
        switchTarget.tap()
        let plus10 = app.buttons["tuningSession.master.plus10"]
        XCTAssertTrue(plus10.waitForExistence(timeout: 5))
        XCTAssertEqual(advanced.value as? String, "1")
        XCTAssertEqual(advanced.frame.midY, switchY, accuracy: 1)
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].exists)
        XCTAssertFalse(app.segmentedControls["tuningSession.controlMode"].exists)
        XCTAssertFalse(easyInput.exists)
        let content = app.descendants(matching: .any)
        for id in ["screen", "header", "liveContext", "references", "journal"] {
            XCTAssertFalse(content["tuningSession.\(id)"].firstMatch.exists)
        }
        XCTAssertTrue(app.staticTexts["tuningSession.writeRestriction"].label.contains("no changes are sent"))
        let frequencyDial = content["tuningSession.master.dial"].firstMatch
        XCTAssertTrue(frequencyDial.exists)
        XCTAssertLessThanOrEqual(frequencyDial.frame.width, 249, "Use the smaller shared dial in Essentials.")
        XCTAssertTrue(content["tuningSession.voltage.dial"].firstMatch.exists)
        capture("Essentials Advanced switch on and compact controls", app)
        let risk = app.switches["tuningSession.riskAcknowledgement"]
        reveal(risk, in: app)
        if risk.value as? String != "1" {
            risk.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(risk.value as? String, "1")
        reveal(plus10, in: app)
        assertTapTarget(plus10)
        plus10.tap()
        capture("Essentials Advanced dials", app)

        app.buttons["tuningSession.jump.apply"].tap()
        let payload = app.staticTexts["tuningSession.payload"]
        reveal(payload, in: app)
        XCTAssertTrue(payload.label.contains("\"frequency\""))
        XCTAssertTrue(payload.label.contains("535"))
        XCTAssertFalse(payload.label.contains("coreVoltage"))
        let apply = app.buttons["tuningSession.apply"]
        reveal(apply, in: app, requireHittable: false)
        XCTAssertFalse(apply.isEnabled, "Demo cannot write even after acknowledging risk.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("Essentials Advanced exact review in Demo", app)

        XCTAssertTrue(advanced.isHittable, "The switch stays reachable while reviewing the draft.")
        switchTarget.tap()
        XCTAssertTrue(easyInput.waitForExistence(timeout: 5))
        XCTAssertEqual(advanced.value as? String, "0")
        XCTAssertFalse(plus10.exists)
        XCTAssertEqual(easyInput.value as? String, "526", "Switching views must not replace an Easy draft.")
        XCTAssertFalse(app.staticTexts["tuning.preview.result"].exists)
        switchTarget.tap()
        XCTAssertTrue(plus10.waitForExistence(timeout: 5))
        XCTAssertTrue(payload.label.contains("535"), "The Advanced draft must also survive the switch.")
        app.navigationBars["Frequency & voltage"].buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["detail.previewControls.tuning"].waitForExistence(timeout: 5),
                      "A single Back tap returns to the miner from expanded Advanced.")
    }

    func testTuningPreviewFullReviewsJSONAndKeepsReadingsAboveKeypad() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openSettingsHubPreview(app, essentials: false, largest: false,
                               extraArguments: ["--preview-number-first-tuning"])
        let tuning = app.buttons["settings.preview.tuning"]
        reveal(tuning, in: app)
        tuning.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["tuningSession.advancedToggle"].exists)
        assertTuningMeasurements(in: app)
        XCTAssertTrue(app.staticTexts["Tuning draft"].exists)
        XCTAssertFalse(app.staticTexts["Adjust settings"].exists)
        let increase = app.buttons["tuning.preview.frequency.increase"]
        reveal(increase, in: app)
        increase.tap()
        let review = app.buttons["tuning.preview.review"]
        reveal(review, in: app)
        XCTAssertEqual(review.label, "Review Changes")
        capture("Full View Tuning settings revised", app)
        review.tap()

        let json = app.staticTexts["tuning.preview.json"]
        let confirm = app.buttons["tuning.preview.confirm"]
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        XCTAssertTrue(json.label.contains("\"frequency\""))
        XCTAssertTrue(json.label.contains("526"))
        XCTAssertFalse(json.label.contains("coreVoltage"))
        XCTAssertFalse(confirm.isEnabled)
        capture("Full View Tuning review", app)
        app.buttons["tuning.preview.cancel"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.isEnabled)
        XCTAssertFalse(app.staticTexts["tuning.preview.result"].exists)

        let input = app.textFields["tuning.preview.frequency.input"]
        let keyboard = app.keyboards.firstMatch
        let readings = app.staticTexts["tuning.preview.readings"]
        reveal(input, in: app)
        XCTAssertEqual(input.value as? String, "526")
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let done = app.buttons["tuning.preview.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(readings.isHittable)
        XCTAssertLessThan(readings.frame.maxY, input.frame.minY)
        assertFleetEditingFieldAboveKeyboard(input, in: app, navigation: app.navigationBars["Frequency & voltage"])
        XCTAssertFalse(review.isEnabled)
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        input.typeText("526.5")
        XCTAssertEqual(input.value as? String, "526.5")
        assertTuningMeasurements(in: app)
        capture("Full View Tuning numeric keyboard", app)
        done.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        XCTAssertTrue(json.label.contains("526.5"))
        XCTAssertFalse(confirm.isEnabled)
        app.switches["tuning.preview.acknowledge"].coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["tuning.preview.result"].waitForExistence(timeout: 5))

        let modes = app.segmentedControls["tuning.preview.mode"]
        reveal(modes, in: app)
        XCTAssertTrue(modes.buttons["Easy"].isSelected)
        modes.buttons["Advanced"].tap()
        let workspaceModes = app.segmentedControls["tuningSession.controlMode"]
        XCTAssertTrue(workspaceModes.waitForExistence(timeout: 5))
        reveal(workspaceModes, in: app)
        XCTAssertTrue(workspaceModes.buttons["Advanced"].isSelected)
        XCTAssertFalse(app.switches["tuningSession.advancedToggle"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.advancedControlsSection"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.header"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.liveContext"].firstMatch.exists)
        app.buttons["tuningSession.jump.apply"].tap()
        let advancedApply = app.buttons["tuningSession.apply"]
        XCTAssertTrue(advancedApply.waitForExistence(timeout: 5))
        reveal(advancedApply, in: app, requireHittable: false)
        XCTAssertFalse(advancedApply.isEnabled)
        reveal(workspaceModes, in: app)
        workspaceModes.buttons["Easy"].tap()
        XCTAssertTrue(modes.waitForExistence(timeout: 5))
        XCTAssertTrue(modes.buttons["Easy"].isSelected)
    }

    func testTuningPreviewEssentialsKeepsBothInputsAboveKeypad() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        openTuningPreview(app, essentials: true)
        let navigation = app.navigationBars["Frequency & voltage"]
        let advanced = app.switches["tuningSession.advancedToggle"]
        let keyboard = app.keyboards.firstMatch
        let done = navigation.buttons["tuning.preview.done"]
        for (field, text) in [("frequency", "526"), ("coreVoltage", "1145")] {
            let input = app.textFields["tuning.preview.\(field).input"]
            reveal(input, in: app)
            let existing = input.value as? String ?? ""
            input.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
            assertFleetEditingFieldAboveKeyboard(input, in: app, navigation: navigation)
            XCTAssertFalse(advanced.isEnabled, "Switching controls must not interrupt an active input.")
            XCTAssertTrue(done.isHittable)
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            input.typeText(text)
            XCTAssertEqual(input.value as? String, text)
            done.tap()
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
            XCTAssertTrue(advanced.isEnabled)
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["tuning.preview.result"].exists)
    }

    func testTuningPreviewLargestTextAndMissingMeasurements() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openTuningPreview(app, essentials: true, largest: true,
                          extraArguments: ["--ui-test-preview-tuning-no-measurements"])
        let advanced = app.switches["tuningSession.advancedToggle"]
        XCTAssertTrue(advanced.isHittable, "The switch fits initially at the largest text size.")
        XCTAssertEqual(advanced.value as? String, "0")
        let clock = app.staticTexts["tuning.preview.readings.clock"]
        reveal(clock, in: app)
        XCTAssertEqual(clock.label, "Not reported")
        XCTAssertEqual(app.staticTexts["tuning.preview.readings.voltage"].label, "Not reported")
        capture("Essentials Tuning readings at largest text", app)
        let increase = app.buttons["tuning.preview.frequency.increase"]
        reveal(increase, in: app)
        assertTapTarget(increase)
        increase.tap()
        let apply = app.buttons["tuning.preview.apply"]
        reveal(apply, in: app)
        assertTapTarget(apply)
        XCTAssertTrue(apply.isEnabled)
        let warning = app.staticTexts["tuning.preview.risk"]
        XCTAssertLessThan(warning.frame.maxY, apply.frame.minY)
        capture("Essentials Tuning apply at largest text", app)
        apply.tap()
        XCTAssertTrue(app.staticTexts["tuning.preview.result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.navigationBars["Review tuning changes"].exists)
    }

    func testTuningWithoutPreviewKeepsExistingEditor() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openNumberFirstMinerDetail(app, essentials: true, largest: false)
        let tuning = app.buttons["detail.previewControls.tuning"]
        reveal(tuning, in: app)
        tuning.tap()
        let advanced = app.switches["tuningSession.advancedToggle"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        XCTAssertTrue(advanced.isHittable)
        XCTAssertEqual(advanced.value as? String, "0")
        XCTAssertTrue(app.textFields["tuningSession.master.customInput"].exists)
        XCTAssertFalse(app.staticTexts["tuning.preview.readings"].exists)
        XCTAssertFalse(app.buttons["tuningSession.apply"].isEnabled)
    }

    private func openTuningPreview(
        _ app: XCUIApplication, essentials: Bool, largest: Bool = false, extraArguments: [String] = []
    ) {
        openNumberFirstMinerDetail(app, essentials: essentials, largest: largest,
            extraArguments: ["--preview-number-first-tuning"] + extraArguments)
        let tuning = app.buttons["detail.previewControls.tuning"]
        reveal(tuning, in: app)
        tuning.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["tuning.preview.readings"].waitForExistence(timeout: 5))
    }

    private func assertTuningMeasurements(in app: XCUIApplication) {
        for (name, expected) in [("hashrate", "638 GH/s"), ("temperature", "59 °C"),
                                 ("clock", "521 MHz"), ("voltage", "1128 mV")] {
            XCTAssertEqual(app.staticTexts["tuning.preview.readings.\(name)"].label, expected)
        }
    }

    func testCoolingWithoutPreviewStillOpensReviewedSettings() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openNumberFirstMinerDetail(app, essentials: true, largest: false)
        let cooling = app.buttons["detail.previewControls.cooling"]
        reveal(cooling, in: app)
        cooling.tap()
        XCTAssertTrue(app.buttons["Review cooling change"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cooling.commit"].exists)
    }

    func testSettingsHubPreviewInEssentials() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openSettingsHubPreview(app, essentials: true, captureEntry: true)
        try verifySettingsHubCategories(app, checks: settingsHubDestinations.filter { $0.0 != "restart" })
        XCTAssertFalse(app.buttons["settings.preview.diagnostics"].exists)
        XCTAssertFalse(app.buttons["settings.preview.compatibility"].exists)
        XCTAssertFalse(app.buttons["settings.preview.firmware"].exists)
        capture("Essentials Miner settings hub", app)
        verifySettingsRestartAppliesInPlace(app)
    }

    func testSettingsHubPreviewInFullView() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openSettingsHubPreview(app, essentials: false, captureEntry: true)
        let tools: [(String, String)] = [
            ("diagnostics", "Diagnostics"), ("compatibility", "Check compatibility"),
            ("firmware", "Firmware updates")
        ]
        try verifySettingsHubCategories(app, checks: settingsHubDestinations + tools)
        capture("Full View Miner settings hub", app)
        let firmware = app.buttons["settings.preview.firmware"]
        reveal(firmware, in: app)
        capture("Full View Miner settings tools", app)
    }

    func testSettingsHubPreviewRequiresWriteEvidence() {
        let app = XCUIApplication()
        defer { app.terminate() }
        let denied = ["--ui-test-preview-detail-read-only"]
        openNumberFirstMinerDetail(app, essentials: true, largest: false,
            extraArguments: ["--preview-number-first-settings-hub"] + denied)
        XCTAssertFalse(app.buttons["detail.previewControls.settings"].exists)
        app.terminate()

        openSettingsHubPreview(app, essentials: false, extraArguments: denied)
        XCTAssertTrue(app.staticTexts["No editable settings available"].exists)
        for (id, _) in settingsHubDestinations {
            XCTAssertFalse(app.buttons["settings.preview.\(id)"].exists)
        }
        XCTAssertTrue(app.buttons["settings.preview.diagnostics"].exists)
        XCTAssertTrue(app.buttons["settings.preview.compatibility"].exists)
        XCTAssertFalse(app.buttons["settings.preview.firmware"].exists)
        capture("Full View Miner settings read only", app)
    }

    func testSettingsHubPreviewAtLargestText() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openSettingsHubPreview(app, essentials: true, largest: true,
            extraArguments: ["--ui-test-preview-settings-hub-no-display"])
        XCTAssertFalse(app.buttons["settings.preview.display"].exists)
        let general = app.buttons["settings.preview.general"]
        reveal(general, in: app)
        assertTapTarget(general)
        capture("Essentials Miner settings at largest text", app)
        try verifySettingsHubCategories(app, checks: [("tuning", "Frequency & voltage")])
        verifySettingsRestartAppliesInPlace(app, captureName: "Essentials Settings restart at largest text")
    }

    func testSettingsHubWithoutPreviewRemainsOriginal() {
        let app = XCUIApplication()
        defer { app.terminate() }
        openOriginalMiner(app)
        let settings = app.buttons["detail.settings"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["settings.quick.hostname"].exists)
        XCTAssertFalse(app.buttons["settings.preview.general"].exists)
    }

    private var settingsHubDestinations: [(String, String)] {
        [("general", "General"), ("pools", "Pools"), ("display", "Display"), ("cooling", "Cooling"),
         ("tuning", "Frequency & voltage"), ("restart", "Restart device")]
    }

    private func openSettingsHubPreview(
        _ app: XCUIApplication, essentials: Bool, largest: Bool = false, captureEntry: Bool = false,
        extraArguments: [String] = []
    ) {
        openNumberFirstMinerDetail(app, essentials: essentials, largest: largest,
            extraArguments: ["--preview-number-first-settings-hub", "--preview-number-first-cooling"] + extraArguments)
        let settings = app.buttons["detail.previewControls.settings"]
        reveal(settings, in: app)
        assertTapTarget(settings)
        if captureEntry { capture("\(essentials ? "Essentials" : "Full View") Miner settings entry", app) }
        settings.tap()
        XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 5))
    }

    private func verifySettingsHubCategories(_ app: XCUIApplication, checks: [(String, String)]) throws {
        for (id, title) in checks {
            let row = app.buttons["settings.preview.\(id)"]
            reveal(row, in: app)
            assertTapTarget(row)
            row.tap()
            let navigationBar = app.navigationBars[title]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5), "Expected \(title)")
            if id == "restart" {
                let send = app.buttons["endpoint.send"]
                reveal(send, in: app)
                XCTAssertFalse(send.isEnabled)
            } else if id == "compatibility" {
                let check = app.buttons["compatibility.check"]
                reveal(check, in: app)
                XCTAssertFalse(check.isEnabled)
            } else if id == "tuning" {
                XCTAssertTrue(app.descendants(matching: .any)["tuningSession.screen"].firstMatch.exists)
            } else if id == "firmware" {
                XCTAssertTrue(app.staticTexts["Demo release example · no install"].exists)
            }
            let back = try XCTUnwrap(navigationBar.buttons.allElementsBoundByIndex.first,
                                     "Native back button is required to return to the hub")
            back.tap()
            XCTAssertTrue(app.navigationBars["Miner settings"].waitForExistence(timeout: 5))
        }
    }

    private func verifySettingsRestartAppliesInPlace(
        _ app: XCUIApplication, captureName: String = "Essentials Restart from Miner settings"
    ) {
        let restart = app.buttons["settings.preview.restart"]
        reveal(restart, in: app)
        assertTapTarget(restart)
        let result = app.staticTexts["settings.preview.restartResult"]
        XCTAssertFalse(result.exists)
        restart.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "Restart simulated. Nothing sent.")
        assertStayedOnPage("Miner settings", in: app)
        reveal(result, in: app, requireHittable: false)
        capture(captureName, app)
    }

    private func openCooling(
        _ app: XCUIApplication, essentials: Bool, largest: Bool = false, extraArguments: [String] = []
    ) {
        openNumberFirstMinerDetail(app, essentials: essentials, largest: largest,
                                   extraArguments: ["--preview-number-first-cooling"] + extraArguments)
        let cooling = app.buttons["detail.previewControls.cooling"]
        reveal(cooling, in: app)
        cooling.tap()
        XCTAssertTrue(app.navigationBars["Cooling"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cooling.commit"].waitForExistence(timeout: 5))
    }

    private func stepCooling(_ field: String, in app: XCUIApplication, increasing: Bool, to value: Int) {
        let button = app.buttons["cooling.\(field).\(increasing ? "increase" : "decrease")"]
        reveal(button, in: app)
        assertTapTarget(button)
        button.tap()
        let reading = app.staticTexts["cooling.\(field).value"]
        XCTAssertTrue(reading.label.contains(": \(value) "), reading.label)
    }

    private func openNumberFirstMinerDetail(
        _ app: XCUIApplication, essentials: Bool, largest: Bool, extraArguments: [String] = []
    ) {
        app.launchArguments = numberFirstArguments + ["--preview-number-first-detail"]
            + (essentials ? ["--ui-test-dashboard-essentials"] : [])
            + ["-UIPreferredContentSizeCategoryName", largest ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            + extraArguments
        app.launch()
        let miner = firstNumberFirstMiner(in: app)
        reveal(miner, in: app)
        miner.tap()
        XCTAssertTrue(app.navigationBars["Little Supra"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["detail.previewHashrate"].firstMatch.waitForExistence(timeout: 5))
    }

    private func assertNumberFirstMinerReadings(_ app: XCUIApplication) -> XCUIElement {
        let rate = app.descendants(matching: .any)["detail.previewHashrate"].firstMatch
        let temperature = app.descendants(matching: .any)["detail.hero.temperature"].firstMatch
        let power = app.descendants(matching: .any)["detail.hero.power"].firstMatch
        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["detail.previewDemoNotice"].firstMatch.exists)
        XCTAssertEqual(rate.value as? String, "638 GH/s")
        XCTAssertEqual(temperature.value as? String, "59 degrees Celsius")
        XCTAssertEqual(power.value as? String, "12.4 watts")
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertTrue((chart.value as? String ?? "").contains("Last minute"))
        XCTAssertLessThan(rate.frame.maxY, min(temperature.frame.minY, power.frame.minY))
        XCTAssertLessThan(max(temperature.frame.maxY, power.frame.maxY), chart.frame.minY)
        return chart
    }

    private var minerQuickActions: [(id: String, title: String)] {
        [("identify", "Identify device"), ("pause", "Pause mining"),
         ("resume", "Resume mining"), ("restart", "Restart device")]
    }

    private func minerReading(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func assertRestoredShareReadings(_ app: XCUIApplication) {
        let expected = [("accepted", "Accepted, 13,926"), ("rejected", "Rejected, 3"),
                        ("rejectedPercentage", "Rejected share rate, 0.02%")]
        let temperature = minerReading("detail.hero.temperature", in: app)
        for (id, label) in expected {
            let share = minerReading("detail.shares.\(id)", in: app)
            XCTAssertEqual(share.label, label)
            XCTAssertLessThan(share.frame.maxY, temperature.frame.minY)
        }
        XCTAssertTrue(app.staticTexts["2× BM1368"].exists)
        XCTAssertEqual(minerReading("detail.uptime", in: app).label, "Uptime 2d 20h 17m 0s")
        XCTAssertTrue(minerReading("detail.sampleAge", in: app).exists)
    }

    private func verifyOneTapMinerQuickActions(_ app: XCUIApplication) {
        let result = app.staticTexts["detail.previewControls.result"]
        XCTAssertFalse(result.exists, "Opening the screen must not perform an action")
        for (id, title) in minerQuickActions {
            let applied = applyPreviewQuickAction(id, in: app)
            reveal(applied, in: app, requireHittable: false)
            capture("Essentials \(title) applied in place", app)
        }
    }

    private func captureMinerQuickActionRoutes(_ app: XCUIApplication, mode: String) {
        for (id, title) in minerQuickActions {
            let button = app.buttons["detail.quick.\(id)"]
            reveal(button, in: app)
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Demo mode: writes are locked and explorer requests never contact a device."].exists)
            let send = app.buttons["endpoint.send"]
            XCTAssertTrue(send.exists)
            XCTAssertFalse(send.isEnabled)
            capture("\(mode) \(title)", app)
            app.navigationBars[title].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Little Supra"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["detail.previewControls.result"].exists)
        }
    }

    private func applyPreviewQuickAction(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let text = ["identify": "Device signal simulated. Nothing sent.", "pause": "Mining paused in demo. Nothing sent.",
                    "resume": "Mining resumed in demo. Nothing sent.", "restart": "Restart simulated. Nothing sent."]
        let button = app.buttons["detail.quick.\(id)"]
        reveal(button, in: app)
        assertTapTarget(button)
        button.tap()
        let results = app.staticTexts.matching(identifier: "detail.previewControls.result")
        let result = results.firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, text[id])
        XCTAssertEqual(results.count, 1, "Show just the latest action result")
        assertStayedOnPage("Little Supra", in: app)
        return result
    }

    private func assertStayedOnPage(_ title: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars[title].exists)
        for (_, actionTitle) in minerQuickActions {
            XCTAssertFalse(app.navigationBars[actionTitle].exists)
        }
        XCTAssertFalse(app.buttons["endpoint.send"].exists)
        XCTAssertFalse(app.navigationBars["Review before sending"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

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

    private func chooseSoloOption(_ title: String, id: String, in app: XCUIApplication) {
        app.buttons["dashboard.soloOptions"].tap()
        let action = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, title)).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), "Missing Solo odds menu action \(title)")
        action.tap()
    }

    @discardableResult
    private func assertCompactPreviewLayout(in app: XCUIApplication, largestType: Bool) -> CGFloat {
        let chartHeading = app.staticTexts["Hashrate trend"].firstMatch
        let fleetHeading = app.staticTexts["Fleet hashrate"].firstMatch
        let rate = app.descendants(matching: .any)["dashboard.fleetHashrate"].firstMatch
        let notice = app.staticTexts["dashboard.bitsy"].firstMatch
        let exit = app.buttons["dashboard.exitDemo"]
        let miners = app.staticTexts["Your miners"]
        let minerCount = app.staticTexts["3 sample miners"]
        let sort = app.buttons["dashboard.minerDisplay"]
        XCTAssertTrue(chartHeading.waitForExistence(timeout: 10))
        for element in [fleetHeading, rate, notice, exit, miners, minerCount, sort] {
            XCTAssertTrue(element.exists)
        }
        for heading in [fleetHeading, chartHeading] {
            XCTAssertGreaterThan(heading.frame.height, largestType ? 19 : 16)
            XCTAssertLessThanOrEqual(heading.frame.height, largestType ? 21 : 19,
                                     "The preview headings should stay compact without losing all type scaling")
        }
        XCTAssertLessThanOrEqual(rate.frame.height, largestType ? 60 : 55,
                                 "The number and its unit should share a compact line")
        assertSingleRow(left: notice.frame, right: exit.frame)
        assertSingleRow(left: miners.frame.union(minerCount.frame), right: sort.frame)
        // AX can report the same edge as 180 and 179.9999999999999 after coordinate conversion.
        let noticeOverlap = exit.frame.maxY - fleetHeading.frame.minY
        XCTAssertLessThanOrEqual(noticeOverlap, 0.000_001, "The demo notice must not overlap the fleet heading")
        XCTAssertLessThan(rate.frame.maxY, chartHeading.frame.minY)
        XCTAssertLessThan(chartHeading.frame.maxY, miners.frame.minY)
        return chartHeading.frame.height
    }

    private func assertSingleRow(left: CGRect, right: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(left.maxX, right.minX, file: file, line: line)
        XCTAssertEqual(left.midY, right.midY, accuracy: 2, file: file, line: line)
    }

    private func assertRangeBarLayout(in app: XCUIApplication, range: XCUIElement, history: XCUIElement) {
        let heading = app.staticTexts["Hashrate trend"].firstMatch
        let caption = app.staticTexts["Simulated · SHA-256 · TH/s"].firstMatch
        XCTAssertTrue(heading.exists && caption.exists)
        assertTapTarget(range)
        assertTapTarget(history)
        let recentFrame = range.frame
        let historyFrame = history.frame
        let both = recentFrame.union(historyFrame)
        XCTAssertGreaterThanOrEqual(both.width, app.frame.width * 0.75, "The control should fill the chart card")
        XCTAssertLessThanOrEqual(heading.frame.maxY, both.minY)
        XCTAssertLessThanOrEqual(both.maxY, caption.frame.minY)
        XCTAssertEqual(recentFrame.width, historyFrame.width, accuracy: 1)
        XCTAssertEqual(recentFrame.midY, historyFrame.midY, accuracy: 1)
        XCTAssertLessThanOrEqual(recentFrame.maxX, historyFrame.minX)
        XCTAssertLessThanOrEqual(both.height, 46, "Two range controls should fit in one compact tap row")
    }

    private var numberFirstArguments: [String] {
        ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion", "--preview-number-first"]
    }

    private func firstNumberFirstMiner(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
    }

    func testOverviewCardsAtLargestDynamicType() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion",
                               "--ui-test-dashboard-essentials", "--ui-test-light-appearance",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        reveal(chart, in: app)
        XCTAssertGreaterThan(chart.frame.height, 100)
        XCTAssertTrue(chart.label.localizedCaseInsensitiveContains("hashrate"))
        XCTAssertTrue((chart.value as? String ?? "").contains("Last minute"))
        capture("Overview chart at largest Dynamic Type", app)

        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 5))
        let id = String(miner.identifier.dropFirst("dashboard.miner.".count))
        let rate = app.descendants(matching: .any).matching(identifier: "dashboard.hashrateRow.\(id)").firstMatch
        reveal(rate, in: app, requireHittable: false)
        for reading in ["Hashrate", "Temperature", "degrees Celsius", "Power", "watts", "Fan speed", "percent"] {
            XCTAssertTrue(miner.label.contains(reading), "Missing \(reading) in \(miner.label)")
        }
        let controls = app.buttons["dashboard.card.settings.\(id)"]
        let expand = app.buttons["dashboard.card.expand.\(id)"]
        reveal(controls, in: app)
        XCTAssertGreaterThanOrEqual(controls.frame.height, 44)
        XCTAssertGreaterThanOrEqual(controls.frame.width, 44)
        XCTAssertGreaterThanOrEqual(controls.frame.minY, expand.frame.maxY, "Large-text controls must stack")
        XCTAssertTrue(controls.label.hasPrefix("Controls for"))
        capture("Miner card actions at largest Dynamic Type", app)
    }

    func testOverviewCardAccessibilityAuditInBothAppearances() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        defer { app.terminate() }
        for light in [true, false] {
            app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion"]
                + (light ? ["--ui-test-light-appearance"] : ["--ui-test-dashboard-essentials"])
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["dashboard.historyChart"].firstMatch.waitForExistence(timeout: 10))
            let rangeID = light ? "dashboard.historyRange.oneMinute" : "dashboard.historyRangeMenu"
            let historyID = light ? "dashboard.historyDisplay" : "dashboard.viewHistory"
            for id in ["dashboard.exitDemo", rangeID, historyID] {
                assertTapTarget(app.buttons[id])
            }
            try auditOverview(app)
            let controls = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")).firstMatch
            reveal(controls, in: app)
            assertTapTarget(controls)
            let id = String(controls.identifier.dropFirst("dashboard.card.settings.".count))
            assertTapTarget(app.buttons["dashboard.card.expand.\(id)"])
            capture("Overview miner readings and controls - \(light ? "light" : "dark")", app)
            try auditOverview(app)
            app.terminate()
        }
    }

    private func assertTapTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, element.debugDescription, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43.99, element.identifier, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 43.99, element.identifier, file: file, line: line)
    }

    private func auditOverview(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .textClipped]) { issue in
            // On iOS 27 the hit-region audit also reports short static labels. Only exempt
            // the identified, noninteractive captions. Still check their contrast and clipping.
            let staticCaptionIDs = ["dashboard.bitsy", "dashboard.hashrateSource", "dashboard.fleetStatus",
                                    "dashboard.fleetPowerChip", "dashboard.refreshMode"]
            if issue.auditType == .hitRegion, let element = issue.element, element.elementType == .staticText,
               staticCaptionIDs.contains(element.identifier) || element.label == "3 of 3 online"
                || element.label.hasPrefix("Simulated hashrate history · ") {
                return true
            }
            print("Overview audit: \(issue.element?.elementType.rawValue ?? 0) \(issue.element?.identifier ?? "") "
                  + "\(issue.element?.label ?? "") \(issue.compactDescription): \(issue.detailedDescription)")
            return false
        }
    }

    func testHashrateReservesItsOwnRowAtZeroAndWideReadings() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        defer { server.stop() }
        var heights: [CGFloat] = []
        for rate in [0, 1250, 1234567] {
            server.setInfoResponse(status: 200, json: hashrateJSON(rate))
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing"]
            app.launch()
            addFixture(address, in: app)
            let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
            // This HTTP-only fixture rejects the live socket asynchronously. Compare
            // identical content states, not a card before vs after its error row appears.
            let fallback = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS 'Live monitoring unavailable'"), object: miner)
            XCTAssertEqual(XCTWaiter.wait(for: [fallback], timeout: 10), .completed)
            reveal(miner, in: app)
            XCTAssertTrue(miner.label.contains("Best reported share difficulty"), miner.label)
            let id = String(miner.identifier.dropFirst("dashboard.miner.".count))
            let reading = app.descendants(matching: .any).matching(identifier: "dashboard.hashrateRow.\(id)")
            let best = app.descendants(matching: .any).matching(identifier: "dashboard.bestRow.\(id)")
            XCTAssertGreaterThan(reading.count, 0)
            XCTAssertGreaterThan(best.count, 0)
            // Capture one immutable AX tree. Querying each live element separately can mix
            // coordinate systems while the scroll view is still decelerating.
            let tree = try app.snapshot()
            func bounds(_ node: any XCUIElementSnapshot, identifier: String) -> CGRect {
                let own = node.identifier == identifier ? node.frame : CGRect.null
                return node.children.reduce(own) { $0.union(bounds($1, identifier: identifier)) }
            }
            let readingFrame = bounds(tree, identifier: "dashboard.hashrateRow.\(id)")
            let bestFrame = bounds(tree, identifier: "dashboard.bestRow.\(id)")
            XCTAssertFalse(readingFrame.isNull || bestFrame.isNull)
            XCTAssertGreaterThanOrEqual(bestFrame.minY, readingFrame.maxY,
                                        "Best must always be below the full-width hashrate row")
            // SF Symbols have a small optical inset within the left-aligned label.
            XCTAssertEqual(readingFrame.minX, bestFrame.minX, accuracy: 2)
            heights.append(bounds(tree, identifier: miner.identifier).height)
            capture("Gamma hashrate \(rate) keeps Best below", app)
            app.terminate()
        }
        XCTAssertEqual(heights.min() ?? 0, heights.max() ?? 1, accuracy: 1,
                       "Changing number width must not switch the card's row layout")
        XCTAssertTrue(server.writes.isEmpty)
    }

    func testIndividualCardCollapsesAndExpandsWithoutOpeningDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "--ui-test-offline-demo", "--ui-test-reduce-motion"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        let miners = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'"))
        let miner = miners.firstMatch
        XCTAssertTrue(miner.waitForExistence(timeout: 5))
        let minerID = String(miner.identifier.dropFirst("dashboard.miner.".count))
        let expansion = app.buttons["dashboard.card.expand.\(minerID)"]
        let settings = app.buttons["dashboard.card.settings.\(minerID)"]
        reveal(expansion, in: app)
        XCTAssertEqual(expansion.value as? String, "Expanded")
        XCTAssertGreaterThanOrEqual(expansion.frame.width, 44)
        XCTAssertGreaterThanOrEqual(expansion.frame.height, 44)
        XCTAssertGreaterThanOrEqual(settings.frame.width, 44)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        XCTAssertFalse(expansion.frame.intersects(miner.frame),
                       "Expansion must be a sibling, not an overlapping details target")
        XCTAssertFalse(settings.frame.intersects(miner.frame), "Settings must be separate from the details target")
        let expandedHeight = miner.frame.height
        XCTAssertTrue(miner.label.contains("Temperature"), miner.label)
        XCTAssertTrue(miner.label.contains("Power"), miner.label)
        expansion.tap()
        waitForValue("Collapsed", on: expansion)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["detail.minerTitle"].exists)
        XCTAssertFalse(miner.label.contains("Temperature"), miner.label)
        XCTAssertTrue(miner.label.contains("Sample"), miner.label)
        XCTAssertFalse(miner.label.contains("Simulated reading"), "Per-miner freshness belongs in the dashboard hero")
        XCTAssertTrue(miner.label.contains("Power"), miner.label)
        XCTAssertTrue(miner.label.contains("Best reported share difficulty"), miner.label)
        XCTAssertTrue(miner.label.contains("H/s"), miner.label)
        XCTAssertLessThan(miner.frame.height, expandedHeight)
        XCTAssertEqual(Set(miners.allElementsBoundByIndex.map(\.identifier)).count, miners.count,
                       "Only navigation targets may carry dashboard.miner.UUID")
        let expandPrefix = "identifier BEGINSWITH 'dashboard.card.expand.' AND identifier != %@"
        let otherExpansions = app.buttons.matching(NSPredicate(format: expandPrefix, expansion.identifier))
        for other in otherExpansions.allElementsBoundByIndex {
            XCTAssertEqual(other.value as? String, "Expanded", "Collapsing one miner must not collapse its neighbors")
        }
        capture("Collapsed miner retains vital readings and sibling controls", app)
        expansion.tap()
        waitForValue("Expanded", on: expansion)
        XCTAssertTrue(miner.label.contains("Temperature"), miner.label)
        XCTAssertTrue(miner.label.contains("Power"), miner.label)
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5),
                      "The original details link must still work")
    }

    func testMinerAddressOpensAsBrowserLinkFromMinerDetail() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()

        addFixture(address, in: app)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, in: app)
        miner.tap()
        let addressLink = app.buttons["detail.address"]
        reveal(addressLink, in: app)
        XCTAssertTrue(addressLink.isHittable)
        XCTAssertTrue(addressLink.label.contains("127.0.0.1"), addressLink.label)

        // The dashboard card remains a clean details target. The address link lives in miner detail
        // and hands the local miner dashboard URL to Safari.
        addressLink.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 5),
                      "Tapping a miner IP should open its web dashboard in Safari")
        app.activate()
    }

    func testNearbySettingsCategoriesOnlyNavigateAndNeverWrite() throws {
        let server = try LoopbackMinerServer()
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        for (category, title) in [("cooling", "Cooling"), ("pools", "Pools")] {
            app.launchArguments = ["--ui-testing"]
            app.launch()
            assertNoLegacyModeSelector(in: app)
            addFixture(address, in: app)
            let settingsPredicate = NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")
            let settings = app.buttons.matching(settingsPredicate).firstMatch
            reveal(settings, in: app)
            settings.tap()
            let route = app.buttons["dashboard.card.settingsRoute.\(category)"]
            XCTAssertTrue(route.waitForExistence(timeout: 5), app.debugDescription)
            route.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5),
                          "The nearby menu must open the category directly")
            XCTAssertTrue(app.staticTexts["Review and confirm before sending to your miner."].exists)
            XCTAssertFalse(app.buttons["detail.quick.tuning"].exists, "A settings tap must not activate miner details")
            XCTAssertTrue(server.writes.isEmpty, "Opening \(title) must not send a hardware write")
            XCTAssertTrue(server.journal.contains { $0.method == "GET" && $0.path == "/api/system/info" })
            capture("Nearby \(title) opens the existing reviewed form", app)
            app.terminate()
        }
        XCTAssertTrue(server.writes.isEmpty)
    }

    func testIndividualMinerPoolsRouteDoesNotCrashInDemo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10), app.debugDescription)
        let settings = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")
        ).firstMatch
        reveal(settings, in: app)
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let pools = app.buttons["dashboard.card.settingsRoute.pools"]
        XCTAssertTrue(pools.waitForExistence(timeout: 5), app.debugDescription)
        pools.tap()

        XCTAssertTrue(app.navigationBars["Pools"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(
            app.staticTexts["Review and confirm before sending to your miner."]
                .waitForExistence(timeout: 5),
            app.debugDescription
        )
        XCTAssertFalse(app.buttons["detail.quick.tuning"].exists)
    }

    func testTuningSessionOpensFromControlsMenuAndShowsNumberedRails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }

        let controls = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")
        ).firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 10), app.debugDescription)
        reveal(controls, in: app)
        controls.tap()

        let session = fleetTuningSessionMenuItem(in: app)
        XCTAssertTrue(session.waitForExistence(timeout: 5), app.debugDescription)
        session.tap()

        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5), app.debugDescription)
        selectAdvancedTuningControls(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.screen"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.frequencyControl"].exists)
        let frequencyPlus10 = app.buttons["tuningSession.master.plus10"]
        XCTAssertTrue(frequencyPlus10.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(frequencyPlus10.isEnabled, "The demo's reported frequency should enable the stepped rail")
        let frequencyValue = app.descendants(matching: .any)["tuningSession.frequencyValue"]
        XCTAssertTrue(frequencyValue.exists)
        let initialFrequencyLabel = frequencyValue.label
        frequencyPlus10.tap()
        let stepped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", initialFrequencyLabel),
            object: frequencyValue
        )
        XCTAssertEqual(XCTWaiter.wait(for: [stepped], timeout: 5), .completed,
                       "The master +10 control should change the displayed frequency")
        let firstASICJump = app.buttons["tuningSession.jump.1"]
        reveal(firstASICJump, in: app)
        XCTAssertEqual(firstASICJump.label, "ASIC 1")
        let secondASICJump = app.buttons["tuningSession.jump.2"]
        reveal(secondASICJump, in: app)
        XCTAssertEqual(secondASICJump.label, "ASIC 2")
        secondASICJump.tap()
        XCTAssertTrue(app.staticTexts["tuningSession.asic.2.title"].waitForExistence(timeout: 5),
                      app.debugDescription)
        XCTAssertTrue(app.switches["tuningSession.riskAcknowledgement"].exists)
        XCTAssertFalse(app.textFields["tuningSession.frequency"].exists,
                       "The session uses stepped controls instead of numeric frequency entry")
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.asic.1.temperature"].exists,
                      "Each ASIC card must expose its chip temperature, even when the value is unknown")
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.asic.1.voltage"].exists,
                      "Each ASIC card must expose its core voltage, even when the value is unknown")
        let review = app.buttons["tuningSession.jump.apply"]
        XCTAssertTrue(review.waitForExistence(timeout: 5), app.debugDescription)
        review.tap()
        let payload = app.descendants(matching: .any)["tuningSession.payload"]
        XCTAssertTrue(payload.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(payload.label.contains("frequency"), payload.label)
        XCTAssertTrue(app.descendants(matching: .any)["tuningSession.journal"].exists)
        XCTAssertTrue(app.staticTexts["Session opened"].exists)
        let apply = app.buttons["tuningSession.apply"]
        reveal(apply, in: app)
        XCTAssertFalse(apply.isEnabled, "Demo mode must show the one apply action without allowing a write")
        XCTAssertFalse(app.buttons["tuningSession.review"].exists)
        XCTAssertFalse(app.buttons["endpoint.send"].exists)
        capture("Scrollable numbered ASIC tuning session", app)
    }

    func testCockpitStagesEachDialTogetherAndRestoresWithoutWriting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        openCockpit(in: app)
        capture("Car-style frequency cockpit at phone width", app)
        let frequency = app.staticTexts["tuningSession.frequencyValue"]
        let voltage = app.staticTexts["tuningSession.voltageValue"]
        let initialFrequency = try numericReading(frequency)
        let initialVoltage = try numericReading(voltage)
        XCTAssertFalse(app.buttons["tuningSession.reset"].isEnabled)

        let frequencyStep = app.buttons["tuningSession.master.plus10"]
        reveal(frequencyStep, in: app)
        frequencyStep.tap()
        XCTAssertEqual(try numericReading(frequency), initialFrequency + 10)
        reviewCockpit(in: app)
        var fields = try cockpitPayload(in: app)
        XCTAssertEqual(Set(fields.keys), ["frequency"])
        XCTAssertEqual(fields["frequency"] as? Double, initialFrequency + 10)
        app.buttons["tuningSession.reset"].tap()
        XCTAssertTrue(app.staticTexts["tuningSession.payloadUnavailable"].exists)

        let voltageStep = app.buttons["tuningSession.voltage.plusCoarse"]
        reveal(voltageStep, in: app)
        XCTAssertGreaterThanOrEqual(voltageStep.frame.height, 44)
        voltageStep.tap()
        XCTAssertEqual(try numericReading(voltage), initialVoltage + 25)
        reveal(app.descendants(matching: .any)["tuningSession.voltage.dial"], in: app, requireHittable: false)
        capture("Core voltage gauge with staged 25 mV delta", app)
        reviewCockpit(in: app)
        fields = try cockpitPayload(in: app)
        XCTAssertEqual(Set(fields.keys), ["coreVoltage"])
        XCTAssertEqual(fields["coreVoltage"] as? Int, Int(initialVoltage + 25))

        reveal(frequencyStep, in: app)
        frequencyStep.tap()
        reviewCockpit(in: app)
        fields = try cockpitPayload(in: app)
        XCTAssertEqual(Set(fields.keys), ["frequency", "coreVoltage"])
        XCTAssertEqual(fields["frequency"] as? Double, initialFrequency + 10)
        XCTAssertEqual(fields["coreVoltage"] as? Int, Int(initialVoltage + 25))
        let apply = app.buttons["tuningSession.apply"]
        reveal(apply, in: app)
        XCTAssertFalse(apply.isEnabled, "Demo mode must not write even after both dials move")
        capture("Both dials staged in one exact JSON review", app)
        app.buttons["tuningSession.reset"].tap()
        XCTAssertTrue(app.staticTexts["tuningSession.payloadUnavailable"].exists)
        XCTAssertEqual(try numericReading(frequency), initialFrequency)
        XCTAssertEqual(try numericReading(voltage), initialVoltage)
        XCTAssertFalse(app.buttons["tuningSession.reset"].isEnabled)

        let dial = app.descendants(matching: .any)["tuningSession.master.dial"]
        reveal(dial, in: app, requireHittable: false)
        capture("Frequency dial positioned before rim drag", app)
        let start = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let end = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let dragEvidence = "DIAL_FRAME=\(dial.frame) APP_FRAME=\(app.frame) " +
            "DRAG_START=\(start.screenPoint) DRAG_END=\(end.screenPoint) BEFORE=\(initialFrequency)"
        print(dragEvidence)
        let coordinates = XCTAttachment(string: dragEvidence)
        coordinates.name = "Real rim drag coordinates before touch"
        coordinates.lifetime = .keepAlways
        add(coordinates)
        start.press(forDuration: 0.1, thenDragTo: end)
        let draggedFrequency = try numericReading(frequency)
        print("DIAL_DRAG_AFTER=\(draggedFrequency) BEFORE=\(initialFrequency)")
        XCTAssertNotEqual(draggedFrequency, initialFrequency, "Dragging the rim must stage a change")
        XCTAssertTrue(app.buttons["tuningSession.reset"].isEnabled)
        capture("Frequency needle follows a real rim drag", app)
    }

    func testCockpitConfirmsOneLoopbackWriteAndReportsReadbackMismatchHonestly() throws {
        for matches in [true, false] {
            let server = try LoopbackMinerServer()
            server.enableTuningWrites(readbackMatches: matches)
            let address = try server.start()
            let app = XCUIApplication()
            defer { app.terminate(); server.stop() }
            app.launchArguments = ["--ui-testing"]
            app.launch()
            addFixture(address, in: app)
            openCockpit(in: app, fromMinerDetail: true)
            let frequencyStep = app.buttons["tuningSession.master.plus10"]
            reveal(frequencyStep, in: app)
            frequencyStep.tap()
            let voltageStep = app.buttons["tuningSession.voltage.plusCoarse"]
            reveal(voltageStep, in: app)
            voltageStep.tap()
            XCTAssertTrue(server.writes.isEmpty, "Turning dials must never write")
            reviewCockpit(in: app)
            let risk = app.switches["tuningSession.riskAcknowledgement"]
            reveal(risk, in: app)
            if (risk.value as? String) != "1" {
                risk.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            XCTAssertEqual(risk.value as? String, "1", "The actual hardware-risk switch must be on before Apply")
            let apply = app.buttons["tuningSession.apply"]
            reveal(apply, in: app)
            XCTAssertTrue(apply.isEnabled)
            apply.tap()
            let confirmation = app.alerts["Apply tuning change?"]
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            XCTAssertTrue(server.writes.isEmpty, "Review must not write before explicit confirmation")
            confirmation.buttons["Cancel"].tap()
            XCTAssertTrue(server.writes.isEmpty)
            apply.tap()
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            confirmation.buttons["Apply"].tap()
            let outcome = app.staticTexts[matches ? "tuningSession.status" : "tuningSession.error"]
            XCTAssertTrue(outcome.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(server.writes.count, 1)
            let write = try XCTUnwrap(server.writes.first)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: write.body) as? [String: Int])
            XCTAssertEqual(fields, ["frequency": 510, "coreVoltage": 1175])
            let journal = server.journal
            let writeIndex = try XCTUnwrap(journal.firstIndex { $0.method == "PATCH" })
            XCTAssertTrue(journal[..<writeIndex].contains { $0.path == "/api/system/info" && $0.method == "GET" })
            XCTAssertTrue(journal.dropFirst(writeIndex + 1).contains {
                $0.path == "/api/system/info" && $0.method == "GET"
            }, "Verification must use an Info GET started after the actual PATCH")
            if matches {
                XCTAssertTrue(outcome.label.contains("Verified"), outcome.label)
                XCTAssertFalse(app.buttons["tuningSession.reset"].isEnabled)
                XCTAssertFalse(app.staticTexts["tuningSession.payload"].exists)
            } else {
                XCTAssertTrue(outcome.label.contains("do not match"), outcome.label)
                XCTAssertTrue(app.buttons["tuningSession.reset"].isEnabled, "An unverified draft must survive")
                XCTAssertTrue(app.staticTexts["tuningSession.payload"].exists)
                XCTAssertFalse(app.staticTexts["Tuning applied"].exists)
            }
            capture(matches ? "Actual app verified loopback tuning" : "Actual app retains unverified tuning draft", app)
            app.terminate()
            server.stop()
        }
    }

    func testCockpitMissingVoltageKeepsFrequencyUsableWithoutInventingPayloadFields() throws {
        let server = try LoopbackMinerServer()
        server.setInfoResponse(status: 200, json: #"{"hostname":"Partial","ASICModel":"BM1370","frequency":500}"#)
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        addFixture(address, in: app)
        openCockpit(in: app, fromMinerDetail: true)
        let frequencyStep = app.buttons["tuningSession.master.plus10"]
        reveal(frequencyStep, in: app)
        XCTAssertTrue(frequencyStep.isEnabled)
        frequencyStep.tap()
        XCTAssertTrue(app.staticTexts["tuningSession.voltageValue"].label.contains("—"))
        XCTAssertFalse(app.buttons["tuningSession.voltage.plusCoarse"].isEnabled)
        reviewCockpit(in: app)
        let fields = try cockpitPayload(in: app)
        XCTAssertEqual(Set(fields.keys), ["frequency"])
        XCTAssertEqual(fields["frequency"] as? Int, 510)
        XCTAssertTrue(server.writes.isEmpty)
        capture("Missing core voltage does not block frequency or invent voltage", app)
    }

    func testCockpitLargestTextKeepsBothDialsAndReviewReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        openCockpit(in: app)
        for identifier in ["tuningSession.master.plus10", "tuningSession.voltage.plus"] {
            let step = app.buttons[identifier]
            reveal(step, in: app)
            XCTAssertTrue(step.isEnabled)
            XCTAssertGreaterThanOrEqual(step.frame.width, 44)
            XCTAssertGreaterThanOrEqual(step.frame.height, 44)
            step.tap()
            captureSettled("Largest text \(identifier) stays reachable", app)
        }
        let deltaStrip = app.descendants(matching: .any)["tuningSession.deltaStrip"]
        reveal(deltaStrip, in: app, requireHittable: false)
        XCTAssertTrue(deltaStrip.label.contains("Frequency staged"), deltaStrip.label)
        XCTAssertTrue(deltaStrip.label.contains("Core voltage staged"), deltaStrip.label)
        XCTAssertTrue(deltaStrip.label.contains("+10 from"), deltaStrip.label)
        XCTAssertTrue(deltaStrip.label.contains("+5 from"), deltaStrip.label)
        captureSettled("Largest text summary shows both staged values and miner baselines", app)
        reviewCockpit(in: app)
        XCTAssertEqual(Set(try cockpitPayload(in: app).keys), ["frequency", "coreVoltage"])
        XCTAssertTrue(app.buttons["tuningSession.reset"].isEnabled)
        app.buttons["tuningSession.reset"].tap()
        XCTAssertTrue(app.staticTexts["tuningSession.payloadUnavailable"].exists)
    }

    func testCockpitControlsMenuSurvivesHTTPRefreshAndOpensTuner() throws {
        let server = try LoopbackMinerServer()
        server.setInfoResponse(status: 200, json: hashrateJSON(1000))
        let address = try server.start()
        let app = XCUIApplication()
        defer { app.terminate(); server.stop() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        addFixture(address, in: app)
        let chart = app.descendants(matching: .any)["dashboard.historyChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10), "The live dashboard must keep its trend visible")
        let controls = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.settings.'")
        ).firstMatch
        reveal(controls, in: app)
        capture("Live Controls before first tap", app)
        controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let session = fleetTuningSessionMenuItem(in: app)
        XCTAssertTrue(session.waitForExistence(timeout: 5), "The first Controls tap must present its menu")
        capture("Live Controls menu before HTTP refresh", app)
        let requestCount = server.journal.filter { $0.method == "GET" && $0.path == "/api/system/info" }.count
        server.setInfoResponse(status: 200, json: hashrateJSON(1200))
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.journal.filter { $0.method == "GET" && $0.path == "/api/system/info" }.count > requestCount
                && miner.exists && miner.label.contains("1.20")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 75), .completed,
                       "The app must display a new loopback Info response while the menu is open")
        XCTAssertTrue(session.exists && session.isHittable, "An HTTP refresh must not dismiss the Controls menu")
        capture("Live Controls menu survives changed HTTP telemetry", app)
        session.tap()
        XCTAssertTrue(app.navigationBars["Frequency & voltage"].waitForExistence(timeout: 5))
        XCTAssertTrue(server.writes.isEmpty, "Opening Controls and navigating must never write")
    }

}
