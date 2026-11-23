import SwiftUI
import AppKit
import Testing
import UserNotifications
import HashFleetCore
@testable import HashFleetMac

/// Hosts a SwiftUI view in a transparent, mouse-transparent window and drives it in-process.
/// SwiftUI only publishes its accessibility tree to a trusted assistive client, so controls are
/// located through their focus proxies and pressed with synthesized clicks sent to this window.
@MainActor
private final class HostedView {
    let window: NSWindow
    let host: NSView

    init<V: View>(_ view: V, size: NSSize = NSSize(width: 800, height: 1400)) {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        (window.isReleasedWhenClosed, window.alphaValue, window.ignoresMouseEvents) = (false, 0, true)
        host = NSHostingView(rootView: view)
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
    }

    func close() {
        if let sheet = window.attachedSheet { window.endSheet(sheet) }
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Lets SwiftUI run tasks, apply state changes and re-render, then refreshes the key-view proxies
    /// so control discovery reflects controls that were just enabled, disabled or moved.
    func settle(_ milliseconds: Int = 200) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
        host.layoutSubtreeIfNeeded()
        window.recalculateKeyViewLoop()
        window.attachedSheet?.recalculateKeyViewLoop()
    }

    /// Enabled focusable controls (buttons, toggles, pickers) in reading order, in window coordinates.
    func controls(inSheet: Bool = false) -> [NSRect] {
        guard let root = inSheet ? window.attachedSheet?.contentView : host else { return [] }
        var frames: [NSRect] = []
        Self.collect(root, &frames)
        return frames.sorted { ($0.maxY.rounded(), -$0.minX) > ($1.maxY.rounded(), -$1.minX) }
    }

    @discardableResult
    func click(control index: Int, inSheet: Bool = false) -> Bool {
        let frames = controls(inSheet: inSheet)
        guard frames.indices.contains(index), let target = inSheet ? window.attachedSheet : window else { return false }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: NSPoint(x: frames[index].midX, y: frames[index].midY), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return false }
            target.sendEvent(event)
        }
        return true
    }

    func pressEscapeInSheet() -> Bool {
        guard let sheet = window.attachedSheet, let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: sheet.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ) else { return false }
        return sheet.performKeyEquivalent(with: event)
    }

    /// Types into the SwiftUI text field with this placeholder through its AppKit coordinator.
    @discardableResult
    func enter(_ text: String, placeholder: String) -> Bool {
        guard let field = Self.field(in: host, placeholder: placeholder) else { return false }
        field.stringValue = text
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        return true
    }

    private static func collect(_ view: NSView, _ frames: inout [NSRect]) {
        if String(describing: type(of: view)) == "KeyViewProxy" { frames.append(view.convert(view.bounds, to: nil)) }
        view.subviews.forEach { collect($0, &frames) }
    }

    private static func field(in view: NSView, placeholder: String) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable, field.placeholderString == placeholder { return field }
        return view.subviews.lazy.compactMap { field(in: $0, placeholder: placeholder) }.first
    }
}

@Suite("Settings and alert view evaluation", .serialized)
@MainActor
final class SettingsViewsEvaluationTests {
    private let suite = "app.hashfleet.mac.settingsviews.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: suite) ?? .standard }
    deinit { UserDefaults().removePersistentDomain(forName: suite) }

    private func makeStore(demo: Bool = false) -> FleetStore {
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        if demo { store.loadDemo() }
        return store
    }

    private let miner = MinerDevice(name: "Bench Axe", address: "http://192.0.2.10")
    private func recordingOpenURL(_ urls: @escaping (URL) -> Void, result: OpenURLAction.Result = .handled) -> OpenURLAction {
        OpenURLAction { url in urls(url); return result }
    }

    // MARK: - Per-miner power alert

    @Test func powerAlertViewTogglesSavesAndOpensNotificationSettings() async throws {
        let preferences = FleetPowerAlertPreferences(defaults: defaults)
        try preferences.setPolicy(MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 42), for: miner.id)
        var opened: [URL] = []
        let hosted = HostedView(NavigationStack {
            MinerPowerAlertSettingsView(device: miner, preferences: preferences)
        }.environment(\.openURL, recordingOpenURL { opened.append($0) }))
        defer { hosted.close() }
        await hosted.settle()

        // Toggle and Open Settings are enabled. Save stays disabled until something changes.
        #expect(hosted.controls().count == 2)
        #expect(hosted.click(control: 1))
        await hosted.settle()
        #expect(opened == [FleetNotificationSettingsModel.settingsURL])

        // Turning alerts off never requests notification permission, so the view can save directly.
        #expect(hosted.click(control: 0))
        await hosted.settle()
        #expect(hosted.controls().count == 3)
        #expect(hosted.click(control: 1))
        await hosted.settle(400)
        #expect(preferences.policy(for: miner.id) == (try MinerPowerAlertPolicy(isEnabled: false, thresholdWatts: 42)))
        #expect(hosted.controls().count == 2)
    }

    @Test func powerAlertViewRejectsInvalidThresholdThenSavesValidOne() async {
        let preferences = FleetPowerAlertPreferences(defaults: defaults)
        let hosted = HostedView(NavigationStack { MinerPowerAlertSettingsView(device: miner, preferences: preferences) })
        defer { hosted.close() }
        await hosted.settle()
        #expect(hosted.enter("not watts", placeholder: "Alert threshold (W)"))
        await hosted.settle()
        #expect(hosted.controls().count == 2, "Save must stay disabled for an invalid threshold")
        hosted.enter("250", placeholder: "Alert threshold (W)")
        await hosted.settle()
        #expect(hosted.controls().count == 3)
        #expect(hosted.click(control: 1))
        await hosted.settle(400)
        #expect(preferences.policy(for: miner.id) == (try? MinerPowerAlertPolicy(isEnabled: false, thresholdWatts: 250)))
    }

    @Test func alertModelsRequirePermissionOnlyToEnableAndValidateRanges() async throws {
        let id = UUID()
        let power = FleetPowerAlertPreferences(defaults: defaults)
        var granted = false
        let powerModel = MinerPowerAlertSettingsModel(deviceID: id, preferences: power) { granted }
        powerModel.thresholdText = "9999999"
        await powerModel.save()
        #expect(powerModel.error == MinerPowerAlertPolicy.ValidationError.invalidThreshold.localizedDescription)
        powerModel.thresholdText = " 120,5 "
        powerModel.isEnabled = true
        await powerModel.save()
        #expect(powerModel.error?.contains("permission was not granted") == true)
        #expect(power.policy(for: id) == MinerPowerAlertPolicy())
        granted = true
        await powerModel.save()
        #expect(power.policy(for: id) == (try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 120.5)))
        let temperature = FleetTemperatureAlertPreferences(defaults: defaults)
        let denied = MinerTemperatureAlertSettingsModel(deviceID: id, preferences: temperature) { false }
        denied.thresholdText = "120"
        await denied.save()
        #expect(denied.error == MinerTemperatureAlertPolicy.ValidationError.invalidThreshold.localizedDescription)
        denied.thresholdText = "80"
        denied.isEnabled = true
        await denied.save()
        #expect(temperature.policy(for: id).isEnabled == false)
        let allowed = MinerTemperatureAlertSettingsModel(deviceID: id, preferences: temperature) { true }
        allowed.thresholdText = "80"
        allowed.isEnabled = true
        await allowed.save()
        #expect(allowed.savedMessage == "Temperature alert settings saved.")
        #expect(!allowed.hasChanges)
    }

    // MARK: - Per-miner temperature alert

    @Test func temperatureAlertViewValidatesSavesAndOpensSettings() async throws {
        let preferences = FleetTemperatureAlertPreferences(defaults: defaults)
        var opened: [URL] = []
        let hosted = HostedView(NavigationStack {
            MinerTemperatureAlertSettingsView(device: miner, preferences: preferences)
        }.environment(\.openURL, recordingOpenURL { opened.append($0) }))
        defer { hosted.close() }
        await hosted.settle()
        #expect(hosted.click(control: 1))
        await hosted.settle()
        #expect(opened == [FleetNotificationSettingsModel.settingsURL])
        #expect(hosted.enter("5", placeholder: "Alert threshold (°C)"))
        await hosted.settle()
        #expect(hosted.controls().count == 2, "30–110 °C is the only accepted range")
        hosted.enter("68", placeholder: "Alert threshold (°C)")
        await hosted.settle()
        #expect(hosted.click(control: 1))
        await hosted.settle(400)
        #expect(preferences.policy(for: miner.id) == (try MinerTemperatureAlertPolicy(isEnabled: false, thresholdCelsius: 68)))
    }

    // MARK: - Notification settings

    @Test func notificationSettingsRoutePreviewsAndOpenSettingsInGuidedDemo() async {
        let store = makeStore()
        var previews: [FleetCelebration.Kind] = []
        var opened: [URL] = []
        // The guided demo never reads system permission, so alert toggles stay disabled and
        // the only enabled controls are Open Settings, three previews, Send test and a disclosure.
        let hosted = HostedView(NavigationStack {
            FleetNotificationSettingsView(preferences: store.preferences) { previews.append($0) }
        }
        .environment(\.fleetGuidedDemo, true)
        .environment(\.openURL, recordingOpenURL({ opened.append($0) }, result: .discarded)))
        defer { hosted.close() }
        await hosted.settle(300)
        #expect(hosted.controls().count >= 5)
        for index in 1...3 { hosted.click(control: index) }
        await hosted.settle()
        #expect(previews == [.bestShareAllTime, .bestShareSession, .blockFound])
        hosted.click(control: 0)
        await hosted.settle(300)
        #expect(opened == [FleetNotificationSettingsModel.settingsURL])
    }

    @Test func notificationSectionsPostPreviewWhenNoOwnerIsInstalled() async {
        let store = makeStore()
        var posted: [FleetCelebration.Kind] = []
        let token = NotificationCenter.default.addObserver(forName: FleetCelebrationPreview.requested, object: nil, queue: nil) { note in
            let kind = FleetCelebrationPreview.kind(from: note)
            MainActor.assumeIsolated { kind.map { posted.append($0) } }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let hosted = HostedView(FleetSettingsForm {
            FleetNotificationSettingsSections(preferences: store.preferences)
        }.environment(\.fleetGuidedDemo, true))
        defer { hosted.close() }
        await hosted.settle(300)
        hosted.click(control: 3)
        await hosted.settle()
        #expect(posted == [.blockFound])
    }

    @Test func notificationSettingsRefreshLiveAccessWithoutChangingChoices() async {
        let store = makeStore()
        let before = FleetNotificationSettingsModel.Alert.allCases.map { FleetNotificationSettingsModel(preferences: store.preferences).isSelected($0) }
        let hosted = HostedView(NavigationStack { FleetNotificationSettingsView(preferences: store.preferences) })
        defer { hosted.close() }
        await hosted.settle(800)
        let after = FleetNotificationSettingsModel.Alert.allCases.map { FleetNotificationSettingsModel(preferences: store.preferences).isSelected($0) }
        #expect(before == after)
        #expect(!hosted.controls().isEmpty)
    }

    @Test func notificationModelExplainsBackgroundAndDeliveryStates() async {
        let preferences = FleetPreferences(defaults: defaults)
        var access = FleetNotificationSettingsModel.Access(authorization: .denied)
        var background: FleetNotificationSettingsModel.BackgroundRefreshStatus = .available
        let model = FleetNotificationSettingsModel(
            preferences: preferences, readAccess: { access }, requestAccess: { true },
            readBackgroundStatus: { background }, readBackgroundDiagnostics: { .init() }
        )
        let statuses: [FleetNotificationSettingsModel.BackgroundRefreshStatus] = [.available, .denied, .restricted, .unavailable]
        var titles = Set<String>()
        for status in statuses {
            background = status
            await model.refresh()
            titles.insert(model.backgroundTitle + model.backgroundDetail)
        }
        #expect(titles.count == statuses.count)
        preferences.blockNotificationsEnabled = true
        preferences.metricAlertNotificationsEnabled = false
        #expect(model.deliveryNote(for: .blockFound)?.hasPrefix("Selected, but blocked") == true)
        #expect(model.deliveryNote(for: .metricChange)?.hasPrefix("Blocked by system") == true)
        #expect(!model.isEnabled(.blockFound))
        preferences.bestShareNotificationsEnabled = false
        #expect(model.deliveryNote(for: .sessionBestShare)?.hasPrefix("Best-share alerts are off") == true)

        access = .init(authorization: .authorized, alertsEnabled: false, soundsEnabled: false)
        await model.refresh()
        #expect(model.deliveryNote(for: .blockFound) == nil)
        #expect(model.isEnabled(.blockFound))
        #expect(model.access?.title == "Banners and alerts are off")
        #expect(model.access?.explanation.contains("sounds are off") == true)
        model.settingsDidOpen(false)
        #expect(model.error?.contains("Notification Settings") == true)
        model.settingsDidOpen(true)
        #expect(model.error == nil)
    }

    @Test func notificationModelTestDeliveryOutcomes() async {
        let preferences = FleetPreferences(defaults: defaults)
        func run(_ status: UNAuthorizationStatus, post: @escaping @MainActor () async throws -> Void) async
            -> FleetNotificationSettingsModel.TestNotificationState {
            let model = FleetNotificationSettingsModel(
                preferences: preferences, readAccess: { .init(authorization: status) }, requestAccess: { false },
                readBackgroundStatus: { .unavailable }, readBackgroundDiagnostics: { .init() }, postTestNotification: post
            )
            await model.sendTestNotification()
            #expect(!model.isRequesting)
            return model.testNotificationState
        }
        struct PostFailure: Error {}
        #expect(await run(.authorized) {} == .queued)
        #expect(await run(.denied) {} == .blocked)
        #expect(await run(.notDetermined) {} == .blocked)
        #expect(await run(.authorized) { throw PostFailure() } == .failed)
        #expect(await run(.authorized) { throw CancellationError() } == .idle)
        #expect(FleetNotificationSettingsModel.TestNotificationState.sending.message == nil)
    }

    // MARK: - Electricity estimates

    @Test func energyViewRejectsInvalidRateThenSavesValidRate() async {
        let hosted = HostedView(NavigationStack { FleetEnergyView(store: makeStore(demo: true)) })
        defer { hosted.close() }
        await hosted.settle()
        // Currency picker, then Save electricity rate.
        #expect(hosted.controls().count == 2)
        #expect(hosted.enter("twelve", placeholder: "Price per kWh"))
        hosted.click(control: 1)
        await hosted.settle()
        #expect(defaults.object(forKey: FleetEnergySettings.rateKey) == nil)

        hosted.enter("0.25", placeholder: "Price per kWh")
        await hosted.settle()
        hosted.click(control: 1)
        await hosted.settle()
        #expect(defaults.double(forKey: FleetEnergySettings.rateKey) == 0.25)
        #expect(defaults.string(forKey: FleetEnergySettings.currencyKey) == "USD")
        // Saved settings are restored for the next view, and an unsupported currency falls back to USD.
        defaults.set("XYZ", forKey: FleetEnergySettings.currencyKey)
        let restored = FleetEnergySettings(defaults: defaults)
        #expect(restored.rate == 0.25)
        #expect(restored.currency == "USD")

        let estimate = FleetEnergyEstimate(watts: 1000, reportingCount: 1, deviceCount: 2, isDemo: false)
        #expect(estimate.dailyKWh == 24)
        #expect(estimate.monthlyCost(rate: 0.5) == 360)
        #expect(estimate.dailyCost(rate: nil) == nil)
        #expect(estimate.dailyCost(rate: -1) == nil)
    }

    // MARK: - In-app alerts

    private func events(device id: UUID, at date: Date = .now) -> [FleetNotificationEvent] {
        [
            .stateChange(MinerStateChangeEvent(deviceID: id, minerName: "Axe", kind: .offline, occurredAt: date)),
            .stateChange(MinerStateChangeEvent(deviceID: id, minerName: "Axe", kind: .backOnline, occurredAt: date)),
            .metricAlert(MinerMetricAlertEvent(deviceID: id, minerName: "Axe", kind: .hashrateDrop,
                                               title: "Hashrate dropped", detail: "Down 40%", occurredAt: date)),
            .power(MinerPowerAlertEvent(deviceID: id, minerName: "Axe", kind: .exceeded, watts: 30, thresholdWatts: 25, occurredAt: date)),
            .power(MinerPowerAlertEvent(deviceID: id, minerName: "Axe", kind: .resolved, watts: 20, thresholdWatts: 25, occurredAt: date)),
            .temperature(MinerTemperatureAlertEvent(deviceID: id, minerName: "Axe", temperatureCelsius: 80, thresholdCelsius: 70, occurredAt: date)),
            .bestShare(MinerBestShareEvent(deviceID: id, minerName: "Axe", kind: .allTime,
                                           displayValue: "1.2G", rawValue: "1200000000", occurredAt: date)),
            .blockFound(MinerBlockFoundEvent(deviceID: id, minerName: "Axe", coinLabel: "BTC", height: 900_000, count: 1, occurredAt: date))
        ]
    }

    @Test func inAppAlertMapsEveryEventKindToStyleAndSlot() {
        let id = UUID()
        let alerts = events(device: id).map(FleetInAppAlert.init)
        #expect(alerts.map(\.style) == [.warning, .recovery, .warning, .warning, .recovery, .warning, .record, .record])
        #expect(alerts.map(\.isConnectionStatus) == [true, true, false, false, false, false, false, false])
        #expect(alerts.map(\.requiresAcknowledgement) == [false, false, false, false, false, true, false, false])
        #expect(alerts.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty && $0.deviceID == id })
        #expect(alerts[0].slot == alerts[1].slot)
        #expect(alerts[3].slot == alerts[4].slot)
        #expect(alerts[6].slot == "event|\(alerts[6].id.uuidString)")
        #expect(!alerts[0].shouldPresent(isReconnecting: true))
        #expect(alerts[0].shouldPresent(isReconnecting: false))
        #expect(alerts[2].shouldPresent(isReconnecting: true))
    }

    @Test func inAppAlertCenterQueuesReplacesAndDismisses() {
        let center = FleetInAppAlertCenter()
        let first = UUID()
        let firstAlerts = events(device: first).map(FleetInAppAlert.init)
        firstAlerts.forEach(center.present)
        // Offline/back-online and exceeded/resolved share slots, so eight events leave six queued.
        #expect(center.alerts.count == FleetInAppAlertCenter.visibleLimit)
        #expect(center.pendingAlertCount == 3)
        #expect(center.alerts.first == firstAlerts.last)
        center.present(firstAlerts[7])
        #expect(center.pendingAlertCount == 3)
        center.dismiss(firstAlerts[7].id)
        #expect(center.pendingAlertCount == 2)

        let other = FleetInAppAlert(events(device: UUID())[5])
        center.present(other)
        center.removeAll(for: first)
        #expect(center.alerts == [other])
        #expect(center.pendingAlertCount == 0)
        center.clear()
        #expect(center.alerts.isEmpty)
    }

    @Test func inAppAlertBannerDismissesFromItsButton() async {
        let alerts = events(device: UUID()).map(FleetInAppAlert.init)
        for alert in [alerts[0], alerts[1], alerts[6]] {
            var opened = 0
            var dismissed = 0
            let hosted = HostedView(
                FleetInAppAlertBanner(alert: alert, open: { opened += 1 }, dismiss: { dismissed += 1 })
                    .frame(width: 600, height: 160),
                size: NSSize(width: 600, height: 160)
            )
            defer { hosted.close() }
            await hosted.settle(100)
            #expect(hosted.click(control: 0), "Dismiss is the banner's only focusable control")
            await hosted.settle(100)
            // Tapping the body opens the miner, but tap gestures need a key window, which a
            // background test must not steal. The dismiss button must never trigger open.
            #expect(dismissed == 1)
            #expect(opened == 0)
        }
    }

    @Test func inAppAlertOverlayPublishesRecordBannerVisibility() async {
        let id = UUID()
        let center = FleetInAppAlertCenter()
        events(device: id).map(FleetInAppAlert.init).forEach(center.present)
        var opened: [UUID] = []
        let hosted = HostedView(FleetInAppAlertOverlay(center: center, reconnectingDeviceIDs: [id]) { opened.append($0) })
        defer {
            hosted.close()
            FleetInAppSurface.dashboardBannerVisible = false
        }
        await hosted.settle()
        #expect(FleetInAppSurface.dashboardBannerVisible)
        center.clear()
        await hosted.settle()
        #expect(!FleetInAppSurface.dashboardBannerVisible)
        #expect(opened.isEmpty)
    }

    // MARK: - Dashboard welcome

    private func welcomeHost(_ store: FleetStore, canPresent: Bool = true) -> HostedView {
        HostedView(Color.clear.frame(width: 500, height: 500)
            .fleetDashboardWelcome(store: store, canPresent: canPresent)
            .environment(\.scenePhase, .active), size: NSSize(width: 600, height: 600))
    }

    @Test func dashboardWelcomeRecordsTheChosenView() async {
        let store = makeStore()
        #expect(store.preferences.shouldOfferDashboardChoice)
        let hosted = welcomeHost(store)
        defer { hosted.close() }
        await hosted.settle(600)
        #expect(hosted.window.attachedSheet != nil, "An eligible empty fleet must be offered the choice")
        // Essentials, Full View, then Not now.
        #expect(hosted.controls(inSheet: true).count == 3)
        #expect(hosted.click(control: 1, inSheet: true))
        await hosted.settle(400)
        #expect(store.preferences.dashboardMode == .full)
        #expect(!store.preferences.shouldOfferDashboardChoice)
        #expect(hosted.window.attachedSheet == nil)
    }

    @Test func dashboardWelcomeEscapeStartsInEssentials() async {
        let store = makeStore()
        let hosted = welcomeHost(store)
        defer { hosted.close() }
        await hosted.settle(600)
        #expect(hosted.pressEscapeInSheet())
        await hosted.settle(400)
        #expect(store.preferences.dashboardMode == .essentials)
        #expect(!store.preferences.shouldOfferDashboardChoice)
    }

    @Test func dashboardWelcomeIsWithheldWhenIneligible() async {
        let empty = makeStore()
        let blocked = welcomeHost(empty, canPresent: false)
        defer { blocked.close() }
        await blocked.settle(400)
        #expect(blocked.window.attachedSheet == nil)
        #expect(empty.preferences.shouldOfferDashboardChoice)

        // A demo fleet is never offered the choice, even though the preference is still unset.
        let demo = welcomeHost(makeStore(demo: true))
        defer { demo.close() }
        await demo.settle(400)
        #expect(demo.window.attachedSheet == nil)
    }
}
