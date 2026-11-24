import SwiftUI
import HashFleetCore

/// Harlo OS extras from the published local API: updates, time, schedules, lighting,
/// Discord alerts, Matter power plug, network, LAN fleet, web logs and factory reset.
/// Every write is a single request; destructive ones always confirm.
struct MinerHarloToolsPage: View {
    let device: MinerDevice
    @Bindable var store: FleetStore

    @State private var updates: [String: JSONValue] = [:]
    @State private var time: [String: JSONValue] = [:]
    @State private var schedules: [[String: JSONValue]] = []
    @State private var lighting: [String: JSONValue] = [:]
    @State private var discord: [String: JSONValue] = [:]
    @State private var matter: [String: JSONValue] = [:]
    @State private var network: [String: JSONValue] = [:]
    @State private var fleet: [String: JSONValue] = [:]

    @State private var ntpServer = ""
    @State private var timezone = ""
    @State private var webhook = ""
    @State private var alertsEnabled = false
    @State private var cooldown = 300
    @State private var plugCode = ""
    @State private var plugAddress = ""
    @State private var minerName = ""
    @State private var wifiSSID = ""
    @State private var wifiPassword = ""
    @State private var wifiNetworks: [String] = []

    @State private var schedSlot = 1
    @State private var schedTime = "21:00"
    @State private var schedDays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var schedKind = 0
    @State private var schedFreq = 500
    @State private var schedMV = 1150
    @State private var schedFan = 60

    @State private var busy = false
    @State private var message: String?
    @State private var failure: String?
    @State private var confirm: ConfirmAction?

    struct ConfirmAction: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let run: () async throws -> Void
    }

    private var client: HarloOSClient {
        HarloOSClient(adapter: MinerFirmwareAdapter(device: device, session: store.session))
    }
    private var essentials: Bool { store.preferences.dashboardMode == .essentials }
    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let scheduleKinds = ["Stop mining", "Start mining", "Reboot", "Tuning", "Fan speed", "Display on", "Display off"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Harlo OS").fleetFont(.title2, weight: .bold).foregroundStyle(FleetTheme.ink)
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.positive)
                        .accessibilityIdentifier("harlo.result")
                }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                        .accessibilityIdentifier("harlo.error")
                }
                updatesCard
                nameCard
                timeCard
                schedulesCard
                if lighting["zones"] != nil { lightingCard }
                alertsCard
                matterCard
                networkCard
                wifiCard
                fleetCard
                maintenanceCard
            }
            .disabled(busy || store.isDemo)
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .background(FleetTheme.canvas)
        .navigationTitle("Harlo OS")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(confirm?.title ?? "", isPresented: Binding(
            get: { confirm != nil }, set: { if !$0 { confirm = nil } }
        ), titleVisibility: .visible, presenting: confirm) { action in
            Button("Continue", role: .destructive) { perform(action.title, action.run) }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { Text($0.detail) }
    }

    // MARK: Cards

    private var updatesCard: some View {
        card("Firmware updates", "Harlo's update server", "arrow.down.circle") {
            row("Installed", updates["installed_version"]?.stringValue)
            row("Available", updates["available"]?.boolValue == true ? updates["version"]?.stringValue : "Up to date")
            if let phase = updates["phase"]?.stringValue { row("Status", phase) }
            HStack {
                button("Check now", id: "harlo.updateCheck") { try await client.checkForUpdate() }
                if updates["available"]?.boolValue == true {
                    Button("Install \(updates["version"]?.stringValue ?? "")") {
                        confirm = ConfirmAction(
                            title: "Install firmware update?",
                            detail: "The miner downloads, verifies and installs the update, then reboots. Mining stops during the update."
                        ) { try await client.installUpdate() }
                    }
                    .buttonStyle(FleetPrimaryButtonStyle(size: .compact))
                    .accessibilityIdentifier("harlo.updateInstall")
                }
            }
            if updates["available"]?.boolValue == true, let version = updates["version"]?.stringValue {
                Toggle("Hide notice for \(version)", isOn: Binding(
                    get: { updates["ignored"]?.boolValue == true },
                    set: { hide in
                        perform(hide ? "Update notice hidden" : "Update notice restored") {
                            try await client.setUpdateIgnored(version: version, ignored: hide)
                        }
                    }
                ))
                .accessibilityIdentifier("harlo.updateIgnore")
            }
        }
    }

    private var nameCard: some View {
        card("Miner name", "Shown on the miner's screen and web page. Blank uses the model name.", "tag") {
            HStack {
                TextField("Miner name", text: $minerName).textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                button("Save", id: "harlo.nameSave") { try await client.setMinerName(minerName) }
            }
        }
    }

    private var wifiCard: some View {
        card("Wi-Fi", "Joining a new network moves the miner off this one", "wifi") {
            HStack {
                button("Scan", id: "harlo.wifiScan", tone: .secondary) {
                    wifiNetworks = try await client.wifiNetworks()
                }
                if !wifiNetworks.isEmpty {
                    Menu(wifiSSID.isEmpty ? "Choose network" : wifiSSID) {
                        ForEach(wifiNetworks, id: \.self) { ssid in Button(ssid) { wifiSSID = ssid } }
                    }
                }
            }
            TextField("Network name", text: $wifiSSID).textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Password", text: $wifiPassword).textFieldStyle(.roundedBorder)
            Button("Connect") {
                let ssid = wifiSSID, pass = wifiPassword
                confirm = ConfirmAction(
                    title: "Connect the miner to \(ssid)?",
                    detail: "The miner leaves its current network. If the password is wrong you may need its HARLO-SETUP access point to recover."
                ) {
                    try await client.connectWiFi(ssid: ssid, password: pass)
                    wifiPassword = ""
                }
            }
            .buttonStyle(FleetPrimaryButtonStyle(size: .compact))
            .disabled(wifiSSID.isEmpty)
            .accessibilityIdentifier("harlo.wifiConnect")
        }
    }

    private var timeCard: some View {
        card("Time", "Clock used by schedules and the display", "clock") {
            row("Miner time", time["local_time"]?.stringValue)
            row("Synced", time["synced"]?.boolValue.map { $0 ? "Yes" : "No" })
            TextField("NTP server", text: $ntpServer).textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Timezone (e.g. America/New_York)", text: $timezone).textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            HStack {
                button("Save", id: "harlo.timeSave") { try await client.setTime(server: ntpServer, timezone: timezone) }
                button("Use this phone's timezone", id: "harlo.timeZoneLocal", tone: .secondary) {
                    try await client.setTime(server: ntpServer, timezone: TimeZone.current.identifier)
                }
                button("Sync now", id: "harlo.timeSync", tone: .secondary) { try await client.syncTime() }
            }
        }
    }

    private var schedulesCard: some View {
        card("Schedules", "Up to eight timed actions on the miner", "calendar") {
            if schedules.isEmpty {
                Text("No schedules saved.").fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            ForEach(Array(schedules.enumerated()), id: \.offset) { _, s in
                HStack {
                    Text(scheduleSummary(s)).fleetFont(.caption, design: .monospaced)
                    Spacer()
                    if let id = s["id"]?.intValue {
                        Button(role: .destructive) {
                            perform("Schedule \(id) deleted") { try await client.deleteSchedule(slot: id) }
                        } label: { Image(systemName: "trash") }
                        .accessibilityIdentifier("harlo.scheduleDelete.\(id)")
                    }
                }
            }
            Divider()
            Stepper("Slot \(schedSlot)", value: $schedSlot, in: 1...8)
            TextField("HH:MM", text: $schedTime).textFieldStyle(.roundedBorder).frame(maxWidth: 100)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { day in
                    Toggle(Self.dayNames[day], isOn: Binding(
                        get: { schedDays.contains(day) },
                        set: { if $0 { schedDays.insert(day) } else { schedDays.remove(day) } }
                    ))
                    .toggleStyle(.button).fleetFont(.caption2)
                }
            }
            Picker("Action", selection: $schedKind) {
                ForEach(Self.scheduleKinds.indices, id: \.self) { Text(Self.scheduleKinds[$0]).tag($0) }
            }
            .onChange(of: schedKind) { FleetHaptics.selection() }
            if schedKind == 3 {
                Stepper("\(schedFreq) MHz", value: $schedFreq, in: 100...1200, step: 5)
                Stepper("\(schedMV) mV", value: $schedMV, in: 900...1400, step: 5)
            } else if schedKind == 4 {
                Stepper("Fan \(schedFan)%", value: $schedFan, in: 20...100, step: 5)
            }
            button("Save schedule", id: "harlo.scheduleSave") {
                let body = try HarloOSClient.scheduleBody(
                    enabled: true, days: Array(schedDays), time: schedTime, action: scheduleAction
                )
                try await client.saveSchedule(slot: schedSlot, body: body)
            }
        }
    }

    private var lightingCard: some View {
        card("Lighting", "Fan light zones", "lightbulb") {
            let rules = lighting["rules"]?.objectValue ?? [:]
            Toggle("Automatic lighting", isOn: Binding(
                get: { rules["enabled"]?.boolValue == true },
                set: { on in perform("Automatic lighting \(on ? "on" : "off")") { try await client.setAutomaticLighting(on) } }
            ))
            .accessibilityIdentifier("harlo.lightAuto")
            ForEach(Array((lighting["zones"]?.arrayValue ?? []).compactMap(\.objectValue).enumerated()), id: \.offset) { _, z in
                let zone = z["zone"]?.intValue ?? 1
                let effect = z["effect"]?.intValue ?? 1
                HStack {
                    Text("Zone \(zone)").fleetFont(.subheadline)
                    Spacer()
                    Menu(HarloOSClient.lightEffects[safe: effect] ?? "Effect") {
                        ForEach(HarloOSClient.lightEffects.indices, id: \.self) { idx in
                            Button(HarloOSClient.lightEffects[idx]) {
                                perform("Zone \(zone) set to \(HarloOSClient.lightEffects[idx])") {
                                    try await client.setZone(
                                        zone, on: idx != 0, colorHex: z["color"]?.stringValue ?? "ffffff",
                                        brightness: z["brightness"]?.intValue ?? 50, effect: idx
                                    )
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("harlo.zone.\(zone)")
                }
            }
            button("Preview block-found lighting", id: "harlo.lightTest", tone: .secondary) {
                try await client.testLighting(event: "block")
            }
        }
    }

    private var alertsCard: some View {
        card("Discord alerts", discord["webhook_configured"]?.boolValue == true ? "Webhook saved" : "No webhook saved", "bell") {
            Toggle("Enable alerts", isOn: $alertsEnabled).accessibilityIdentifier("harlo.alertsEnabled")
            SecureField("Webhook URL (blank keeps the saved one)", text: $webhook).textFieldStyle(.roundedBorder)
            Stepper("At most one message every \(cooldown)s", value: $cooldown, in: 0...86_400, step: 60)
            HStack {
                button("Save", id: "harlo.alertsSave") {
                    try await client.saveDiscord(current: discord, enabled: alertsEnabled,
                                                 webhookURL: webhook.isEmpty ? nil : webhook, cooldownSeconds: cooldown)
                    webhook = ""
                }
                button("Send test", id: "harlo.alertsTest", tone: .secondary) { try await client.testDiscord() }
            }
            if let last = discord["last_delivery"]?.stringValue {
                Text("Last delivery: \(last)").fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
        }
    }

    private var matterCard: some View {
        let configured = matter["configured"]?.boolValue ?? matter["paired"]?.boolValue ?? false
        return card("Smart plug (Matter)", "Measure wall power with a paired plug. The outlet is never switched off.", "powerplug") {
            if configured {
                row("Plug power", matter["power_w"]?.doubleValue.map { String(format: "%.1f W", $0) })
                row("State", matter["state"]?.stringValue)
                HStack {
                    Button("Unpair") {
                        confirm = ConfirmAction(title: "Unpair the plug?", detail: "Deletes the saved pairing and tries to remove it from the plug. The outlet stays on.") {
                            try await client.unpairPlug()
                        }
                    }.buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
                    Button("Forget locally") {
                        confirm = ConfirmAction(title: "Forget the plug?", detail: "Deletes the saved pairing on the miner only.") {
                            try await client.forgetPlug()
                        }
                    }.buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
                }
            } else {
                TextField("Matter setup code", text: $plugCode).textFieldStyle(.roundedBorder)
                TextField("Plug IP address (optional)", text: $plugAddress).textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                button("Pair plug", id: "harlo.matterPair") {
                    try await client.pairPlug(setupCode: plugCode, address: plugAddress)
                    plugCode = ""
                }
            }
        }
    }

    private var networkCard: some View {
        card("Network", "Interfaces reported by the miner", "network") {
            ForEach(Array((network["interfaces"]?.arrayValue ?? []).compactMap(\.objectValue).enumerated()), id: \.offset) { _, n in
                let state = n["available"]?.boolValue == false ? "Not available"
                    : n["active"]?.boolValue == true ? "Active" : n["connected"]?.boolValue == true ? "Connected" : "Inactive"
                row(n["id"]?.stringValue?.capitalized ?? "Interface",
                    [state, n["ip"]?.stringValue, n["ssid"]?.stringValue].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            }
        }
    }

    private var fleetCard: some View {
        let devices = (fleet["devices"]?.arrayValue ?? []).compactMap(\.objectValue)
        return card("Miners seen by this Harlo", "\(devices.count) on the LAN", "dot.radiowaves.left.and.right") {
            ForEach(Array(devices.prefix(12).enumerated()), id: \.offset) { _, d in
                row(d["name"]?.stringValue ?? d["model"]?.stringValue ?? "Miner",
                    "\(d["ip"]?.stringValue ?? "") · \(d["online"]?.boolValue == true ? "online" : "offline")")
            }
            button(fleet["scanning"]?.boolValue == true ? "Scanning…" : "Scan LAN", id: "harlo.fleetScan", tone: .secondary) {
                try await client.scanFleet()
            }
        }
    }

    private var maintenanceCard: some View {
        card("Maintenance", "Logging and reset", "wrench.and.screwdriver") {
            HStack {
                button("Pause web logs", id: "harlo.logsPause", tone: .secondary) { try await client.setWebLogging(false) }
                button("Resume web logs", id: "harlo.logsResume", tone: .secondary) { try await client.setWebLogging(true) }
            }
            Button("Factory reset") {
                confirm = ConfirmAction(
                    title: "Factory reset this miner?",
                    detail: "Erases ALL saved settings including Wi-Fi, pools, tuning and fans. The miner restarts with ASIC power off and must be set up again on its HARLO-SETUP Wi-Fi."
                ) { try await client.factoryReset() }
            }
            .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
            .accessibilityIdentifier("harlo.factoryReset")
        }
    }

    // MARK: Helpers

    private var scheduleAction: HarloOSClient.ScheduleAction {
        switch schedKind {
        case 0: .stop
        case 1: .start
        case 2: .reboot
        case 3: .tuning(frequencyMHz: schedFreq, coreMV: schedMV)
        case 4: .fanPercent(channel: 1, percent: schedFan)
        case 5: .display(on: true)
        default: .display(on: false)
        }
    }

    private func scheduleSummary(_ s: [String: JSONValue]) -> String {
        let days = (s["days"]?.arrayValue ?? []).compactMap(\.intValue).compactMap { Self.dayNames[safe: $0] }.joined(separator: ",")
        let path = s["path"]?.stringValue ?? ""
        return "#\(s["id"]?.intValue ?? 0) \(s["enabled"]?.boolValue == true ? "On" : "Off") \(days) \(s["time"]?.stringValue ?? "") \(path)"
    }

    private func card<Content: View>(_ title: String, _ subtitle: String, _ symbol: String,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        MinerControlsCard {
            MinerControlsHeader(title: title, subtitle: subtitle, symbol: symbol)
            content()
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            Spacer()
            Text(value ?? "Not reported").fleetFont(.caption, design: .monospaced).foregroundStyle(FleetTheme.ink)
        }
    }

    private func button(_ title: String, id: String, tone: FleetPrimaryButtonStyle.Tone = .accent,
                        _ run: @escaping () async throws -> Void) -> some View {
        Button(title) { perform(title, run) }
            .buttonStyle(FleetPrimaryButtonStyle(tone: tone, size: .compact))
            .accessibilityIdentifier(id)
    }

    private func perform(_ label: String, _ run: @escaping () async throws -> Void) {
        confirm = nil
        message = nil
        failure = nil
        guard !store.isDemo, MinerWriteAvailability.allows(
            store.snapshot(for: device.id), device: device, currentDevices: store.visibleDevices, isDemo: store.isDemo
        ) else {
            failure = "Miner offline or stale. Refresh first. Nothing was sent."
            return
        }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await run()
                FleetHaptics.success()
                message = "\(label) · done"
                await load()
                _ = await store.refreshAfterWrite(for: device)
            } catch {
                FleetHaptics.error()
                failure = "Not applied: \(error.localizedDescription)"
            }
        }
    }

    private func load() async {
        guard !store.isDemo else { return }
        let c = client
        async let u = try? c.updates()
        async let t = try? c.time()
        async let s = try? c.schedules()
        async let l = try? c.lighting()
        async let d = try? c.discord()
        async let m = try? c.matter()
        async let n = try? c.network()
        async let f = try? c.fleet()
        updates = await u ?? [:]
        time = await t ?? [:]
        schedules = await s ?? []
        lighting = await l ?? [:]
        discord = await d ?? [:]
        matter = await m ?? [:]
        network = await n ?? [:]
        fleet = await f ?? [:]
        if ntpServer.isEmpty { ntpServer = time["server"]?.stringValue ?? "pool.ntp.org" }
        if timezone.isEmpty { timezone = time["timezone"]?.stringValue ?? TimeZone.current.identifier }
        alertsEnabled = discord["enabled"]?.boolValue ?? false
        cooldown = discord["cooldown_seconds"]?.intValue ?? cooldown
        if minerName.isEmpty { minerName = (try? await c.minerName()) ?? "" }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
