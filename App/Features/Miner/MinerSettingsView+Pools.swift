import SwiftUI
import HashFleetCore

extension MinerSettingsView {
    var poolInventory: SoloPoolSlotInventory { SoloPoolSlotInventory(raw: reportedFields) }

    var draftPoolCoin: MiningPoolCoin? {
        ConfiguredMiningPool.resolve(
            info: MinerInfo(raw: [
                "pools": .array([
                    .object([
                        "id": .integer(0), "stratumURL": .string(poolURL), "stratumPort": .string(poolPort)
                    ])
                ])
            ])
        ).first?.coin
    }

    func poolSlotTitle(_ slot: Int) -> String {
        guard let coin = poolInventory.slots.first(where: { $0.id == slot })?.coin else { return "Slot \(slot)" }
        return "Slot \(slot) · \(coin.ticker)"
    }

    func poolCoinIdentity(_ coin: MiningPoolCoin?) -> some View {
        HStack(spacing: 8) {
            if let coin {
                CoinGeckoIcon(coin: coin, fallbackTicker: coin.ticker, size: 24)
            } else {
                Image(systemName: "questionmark.circle").accessibilityHidden(true)
            }
            Text(coin.map { "Coin · \($0.ticker)" } ?? "Coin · unknown")
                .fleetFont(.subheadline, weight: .semibold)
        }
        .accessibilityElement(children: .combine)
    }

    var soloPoolPresets: some View {
        settingsHubCard {
            settingsHubHeader(
                "Guided pool & coin setup",
                subtitle: "Prepare a draft from a known pool.",
                symbol: "wand.and.stars"
            )
            Divider().overlay(FleetTheme.separator)
            NavigationLink {
                MiningSetupView(device: device, store: store, insights: insights) { preset in
                    applyUnifiedPoolDraft(preset)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars").foregroundStyle(FleetTheme.accent).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Guided setup: Solo & shared pools").foregroundStyle(FleetTheme.ink)
                        Text("Explore SHA-256d coins, solo vs shared pools, and verified endpoints")
                            .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(FleetTheme.secondary)
                }
                .fleetFont(.subheadline)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.pools.guidedSetup")
            Divider().overlay(FleetTheme.separator)

            fieldLabel("Solo pool preset")
            Picker("Solo pool preset", selection: soloPoolSelection) {
                Text("Custom / existing configuration").tag(Optional<SoloPoolPreset>.none)
                ForEach(SoloPoolPreset.allCases) { preset in Text(preset.title).tag(Optional(preset)) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("settings.pools.preset")
            if let preset = selectedSoloPool {
                Text("\(preset.server):\(preset.port) · \(preset.stratumProtocol)")
                    .fleetFont(.caption, design: .monospaced).foregroundStyle(FleetTheme.secondary)
                Link("Official \(preset.coin) pool setup", destination: preset.documentationURL)
                    .fleetFont(.subheadline)
                if preset == .soloPoolDGB {
                    Text(
                        "DGB SHA-256 only. SoloPool lists port 8004 at 250K share difficulty, 7004 at 1M and "
                            + "9004 at 10M. Small miners may take a long time to submit a share. "
                            + "Do not use a different DigiByte algorithm endpoint."
                    )
                    .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
                }
            }
            Button {
                addSoloPoolDraft()
            } label: {
                Label(
                    poolInventory.firstEmptySlot.map { "Add draft in empty slot \($0)" } ?? "Add draft in empty slot",
                    systemImage: "plus.circle"
                )
                .fleetFont(.subheadline)
            }
            .disabled(selectedSoloPool == nil || poolInventory.firstEmptySlot == nil)
            .accessibilityIdentifier("settings.pools.addPreset")
            if case .unknown = poolInventory.availability {
                Text(
                    "Empty slots cannot be determined from the current report. "
                        + "Refresh the miner, or deliberately select a slot in the form below."
                )
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
            } else if case .full = poolInventory.availability {
                Text(
                    "All eight slots are configured or assigned a role. "
                        + "Select an existing slot below only if you intend to replace it."
                )
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.warning)
            }
            Text(
                "Presets fill this draft only. Enter a wallet for the selected coin as wallet.worker, "
                    + "for example your-address.bitaxe1. A different preset clears the previous "
                        + "wallet and password draft. "
                    + "Nothing is sent, restarted, or made active automatically."
            )
            .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
            if let poolPresetMessage {
                Text(poolPresetMessage).fleetFont(.caption)
                .foregroundStyle(FleetTheme.accent)
                    .accessibilityIdentifier("settings.pools.presetStatus")
            }
        }
    }

    @ViewBuilder
    var configuredPoolSlots: some View {
        if !poolInventory.slots.isEmpty {
            settingsHubCard {
                settingsHubHeader(
                    "Configured slots",
                    subtitle: "Reported by this miner.",
                    symbol: "square.stack.3d.up"
                )
                ForEach(poolInventory.slots) { configured in
                    Divider().overlay(FleetTheme.separator)
                    VStack(alignment: .leading, spacing: 6) {
                        poolCoinIdentity(configured.coin)
                        Text("Slot \(configured.id) · \(configured.serverLabel)")
                            .fleetFont(.subheadline)
                .foregroundStyle(FleetTheme.ink)
                        Text(configured.roleLabel).fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.pools.configured.\(configured.id)")
                }
                Text(
                    "Adding a draft does not change primary or fallback routing. "
                    + "Configure and confirm the slot first, then review any role change separately."
                )
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
            }
        }
    }

    var soloPoolSelection: Binding<SoloPoolPreset?> {
        Binding(
            get: { selectedSoloPool },
            set: { preset in
                let previous = selectedSoloPool
                selectedSoloPool = preset
                if let preset { applySoloPoolDraft(preset, previous: previous) } else { poolPresetMessage = nil }
            }
        )
    }

    var poolModeSelection: Binding<String> {
        Binding(
            get: { poolMode },
            set: { value in
                poolMode = value
                poolReplacementAcknowledged = false
                loadPool()
            }
        )
    }

    var poolSlotSelection: Binding<Int> {
        Binding(
            get: { slot },
            set: { value in
                slot = value
                poolReplacementAcknowledged = false
                loadPool()
            }
        )
    }

    func addSoloPoolDraft() {
        guard let preset = selectedSoloPool, let empty = poolInventory.firstEmptySlot else { return }
        // These are local form variables, never a request or a change to primary/fallback roles.
        poolMode = "slot"
        slot = empty
        applySoloPoolDraft(preset, previous: nil)
        poolPresetMessage =
            "\(preset.coin) draft prepared in slot \(empty). "
            + "Enter its wallet, acknowledge full replacement, then review the exact JSON before confirming."
    }

    func applySoloPoolDraft(_ preset: SoloPoolPreset, previous: SoloPoolPreset?) {
        let fields = preset.draft(previousPreset: previous, user: poolUser)
        poolURL = fields.server
        poolPort = fields.port
        poolProtocol = fields.stratumProtocol
        poolUser = fields.user
        poolPassword = ""
        poolPasswordMode = .keep
        poolReplacementAcknowledged = false
        error = nil
        poolPresetMessage =
            "\(preset.coin) draft only. Verify a \(preset.coin) wallet before review. No miner settings have changed."
    }

    func applyUnifiedPoolDraft(_ preset: MiningPoolPreset) {
        // Selection populates the local form only; it preserves slot capacity and requires
        // full-slot replacement acknowledgement.
        if let empty = poolInventory.firstEmptySlot {
            poolMode = "slot"
            slot = empty
        }
        selectedSoloPool = nil
        let fields = preset.draft(previousPresetID: nil, currentUser: poolUser)
        poolURL = fields.server
        poolPort = fields.port
        poolProtocol = fields.stratumProtocol
        poolUser = fields.user
        poolPassword = ""
        poolPasswordMode = .keep
        poolReplacementAcknowledged = false
        error = nil
        poolPresetMessage =
            "\(preset.name) (\(preset.coin.symbol) \(preset.mode.rawValue)) draft prepared. "
            + "Enter credentials, acknowledge replacement, then review exact JSON."
    }

    func show(_ endpoint: MinerEndpoint, object: [String: Any]) {
        guard !offlineReadOnly else { error = "Offline settings are read only. Reconnect and refresh first."; return }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            error = nil
            draft = MinerSettingsDraft(
                endpoint: endpoint,
                json: String(data: data, encoding: .utf8) ?? "{}",
                notice: nil
            )
        } catch { self.error = error.localizedDescription }
    }

    func show(_ endpoint: MinerEndpoint, json: JSONValue, notice: String? = nil, fromQuickChanges: Bool = false) {
        guard !offlineReadOnly else { error = "Offline settings are read only. Reconnect and refresh first."; return }
        do {
            let text = try json.prettyPrinted()
            error = nil
            let request = MinerSettingsDraft(endpoint: endpoint, json: text, notice: notice)
            if fromQuickChanges { quickDraft = request } else { draft = request }
        } catch { self.error = error.localizedDescription }
    }

    func reviewPool() {
        if poolMode == "slot" {
            do {
                let pool = MinerTuningPoolDraft(
                    slot: slot,
                    server: poolURL,
                    port: poolPort,
                    user: poolUser,
                    stratumProtocol: poolProtocol,
                    replacePassword: poolPasswordMode != .keep,
                    password: poolPasswordMode == .clear ? "" : poolPassword
                )
                let payload = try pool.payload(replacementAcknowledged: poolReplacementAcknowledged)
                show(.updatePool(slot), json: payload, notice: MinerTuningPoolDraft.replacementNotice)
                poolReplacementAcknowledged = false
            } catch { self.error = error.localizedDescription }
            return
        }
        guard !poolURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !poolUser.isEmpty,
            let port = Int(poolPort), (1...65535).contains(port)
        else {
            error = "Enter a server, worker and integer port from 1 to 65535."
            return
        }
        let prefix = poolMode == "fallback" ? "fallbackStratum" : "stratum"
        var object: [String: Any] = [
            "\(prefix)URL": poolURL, "\(prefix)Port": port, "\(prefix)User": poolUser,
            "\(prefix)Protocol": poolProtocol
        ]
        if poolPasswordMode != .keep { object["\(prefix)Password"] = poolPasswordMode == .clear ? "" : poolPassword }
        show(.settings, object: object)
    }

    func load() {
        guard !loaded, let info else { return }
        loaded = true
        hostname = info.hostname
        tuning = MinerTuningDraft(info: info)
        autoFan = info.raw["autofanspeed"]?.boolValue ?? true
        fanSpeed = MinerTuningDraft.integerDraft(from: info.raw["manualFanSpeed"])
        minFanSpeed = MinerTuningDraft.integerDraft(from: info.raw["minFanSpeed"])
        temperatureTarget = MinerTuningDraft.integerDraft(from: info.raw["temptarget"])
        if let reported = info.raw["statsFrequency"]?.doubleValue, let seconds = Int(exactly: reported),
            (0...65_535).contains(seconds) {
            statsFrequency = seconds
        }
        if let rotation = info.raw["rotation"]?.intValue, [0, 90, 180, 270].contains(rotation) {
            screenRotation = rotation
        }
        screenInverted = info.raw["invertscreen"]?.boolValue ?? false
        displayTimeout = MinerTuningDraft.integerDraft(from: info.raw["displayTimeout"])
        primarySlot = min(7, max(0, info.raw["primaryPoolIndex"]?.intValue ?? 0))
        secondarySlot = min(7, max(0, info.raw["secondaryPoolIndex"]?.intValue ?? 1))
        slot = primarySlot
        loadPool()
    }

    func loadPool() {
        selectedSoloPool = nil
        poolPresetMessage = nil
        let raw: [String: JSONValue]
        let prefix: String
        if poolMode == "slot" {
            raw =
                reportedFields?["pools"]?.arrayValue?.compactMap(\.objectValue)
                .first { $0["id"]?.intValue == slot } ?? [:]
            prefix = "stratum"
        } else {
            raw = reportedFields ?? [:]
            prefix = poolMode == "fallback" ? "fallbackStratum" : "stratum"
        }
        poolURL = raw["\(prefix)URL"]?.stringValue ?? ""
        poolPort = String(raw["\(prefix)Port"]?.intValue ?? 3333)
        poolUser = raw["\(prefix)User"]?.stringValue ?? ""
        poolProtocol = raw["\(prefix)Protocol"]?.stringValue == "SV2" ? "SV2" : "SV1"
        poolPassword = ""
        poolPasswordMode = .keep
    }
}
