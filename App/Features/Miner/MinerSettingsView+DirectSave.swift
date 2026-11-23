import SwiftUI
#if os(macOS)
import AppKit
#endif
import HashFleetCore

/// Safe everyday settings save straight to the miner, like a normal settings screen, instead of
/// showing the JSON request page. Only a small allowlist of low-risk fields qualifies. Pools,
/// credentials, clocks, voltage, fan controls, custom JSON and hardware-risk changes keep the
/// existing reviewed flow. Automatic fan control and temperature targets always use that reviewed
/// flow as well.
enum MinerDirectSavePolicy {
    static let directKeys: Set<String> = [
        "hostname", "statsFrequency", "rotation", "invertscreen", "displayTimeout"
    ]

    static func qualifies(endpoint: MinerEndpoint, payload: JSONValue) -> Bool {
        guard endpoint == .settings,
            let object = payload.objectValue, !object.isEmpty
        else { return false }
        return Set(object.keys).isSubset(of: directKeys)
    }
}

enum MinerDisplaySetting: String {
    case rotation, colors = "invertscreen", timeout = "displayTimeout"

    func matches(_ payload: JSONValue, in info: MinerInfo) -> Bool {
        let requested = payload[rawValue]
        let reported = info.raw[rawValue]
        if self == .colors, let inverted = requested?.boolValue { return reported?.boolValue == inverted }
        guard let value = requested?.doubleValue else { return false }
        return reported?.doubleValue == value
    }
}

struct MinerSettingsSaveAlert {
    let title: String
    let message: String
    var restartIdentity: MinerInlineActionState.Identity?
}

extension MinerSettingsView {
    /// Whether everyday buttons can use the safe direct-save path.
    var savesDirectly: Bool { true }

    func everydayTitle(review: String, save: String) -> String {
        savesDirectly ? save : review
    }

    /// Routes a native draft: direct save when eligible, otherwise the existing review page.
    func submit(_ endpoint: MinerEndpoint, json: JSONValue, fromQuickChanges: Bool = false) {
        guard MinerDirectSavePolicy.qualifies(endpoint: endpoint, payload: json)
        else {
            show(endpoint, json: json, fromQuickChanges: fromQuickChanges)
            return
        }
        saveDirectly(json)
    }

    func submit(_ endpoint: MinerEndpoint, object: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            submit(endpoint, json: try JSONDecoder().decode(JSONValue.self, from: data))
        } catch { self.error = error.localizedDescription }
    }

    var showsDisplayFeedbackByButton: Bool { usesCompactSettingsHubPreview && !store.isDemo }

    func displaySaveButton(_ title: String, setting: MinerDisplaySetting, payload: @escaping () throws -> JSONValue) -> some View {
        let isPending = savingDisplaySetting == setting || (isRestartingDisplay && displayFeedbackSetting == setting)
        let pendingTitle = isRestartingDisplay ? "Requesting restart…" : "Saving…"
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                guard !isSaving, !isRestartingDisplay else { return }
                if showsDisplayFeedbackByButton {
                    displayFeedbackSetting = setting
                    saveMessage = nil
                }
                do {
                    let draft = try payload()
                    guard draft.objectValue?.count == 1, draft[setting.rawValue] != nil else { return }
                    if showsDisplayFeedbackByButton {
                        saveDirectly(draft, displaySetting: setting)
                    } else {
                        submit(.settings, json: draft)
                    }
                } catch { self.error = error.localizedDescription }
            } label: {
                FleetPendingButtonLabel(title: title, pendingTitle: pendingTitle, isPending: isPending)
            }
            .buttonStyle(FleetPrimaryButtonStyle(tone: .accent, size: .compact, fullWidth: true))
            .disabled(isSaving || isRestartingDisplay)
            .accessibilityLabel(isPending ? pendingTitle : title)
            .accessibilityIdentifier("settings.display.save.\(setting.rawValue)")

            if showsDisplayFeedbackByButton, displayFeedbackSetting == setting, !isPending {
                if let error { Text(error).fleetFont(.footnote).foregroundStyle(FleetTheme.warning) }
                directSaveStatus
            }
        }
        .padding(.top, 5)
    }

    private var canWriteDirectly: Bool {
        MinerWriteAvailability.allows(
            store.snapshot(for: device.id), device: device,
            currentDevices: store.visibleDevices, isDemo: store.isDemo
        )
    }

    private var directSaveIdentity: MinerInlineActionState.Identity? {
        guard canWriteDirectly, let info else { return nil }
        return MinerInlineActionState.identity(from: info)
    }

    func saveDirectly(_ payload: JSONValue, displaySetting: MinerDisplaySetting? = nil) {
        guard !isSaving, !isRestartingDisplay else { return }
        guard MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: payload) else { return }
        saveMessage = nil
        saveAlert = nil
        guard !store.isDemo else {
            let message = "Demo mode is read only. Nothing was sent."
            error = message
            saveAlert = MinerSettingsSaveAlert(title: "Settings not saved", message: message)
            return
        }
        guard canWriteDirectly else {
            let message = "Offline settings are read only. Reconnect and refresh first."
            error = message
            saveAlert = MinerSettingsSaveAlert(title: "Settings not saved", message: message)
            return
        }
        let body: Data
        do { body = try JSONEncoder().encode(payload) } catch {
            let message = error.localizedDescription
            self.error = message
            saveAlert = MinerSettingsSaveAlert(title: "Settings not saved", message: message)
            return
        }
        error = nil
        let identity = displaySetting == nil ? nil : directSaveIdentity
        savingDisplaySetting = displaySetting
        isSaving = true
        #if os(macOS)
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        #else
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        #endif
        Task { @MainActor in
            defer {
                isSaving = false
                savingDisplaySetting = nil
            }
            let operation = MinerOperationModel(session: store.session)
            // execute() re-reads system info first, so a miner that dropped off since the
            // last refresh is never written to.
            await operation.execute(
                device: device,
                endpoint: .settings,
                body: body,
                query: [],
                isDemo: store.isDemo,
                validatePreflight: { preflight in
                    if let identity, MinerInlineActionState.identity(from: preflight) != identity {
                        throw MinerToolError.message("The miner identity changed. Nothing was sent.")
                    }
                },
                writeAuthorized: { canWriteDirectly && (identity == nil || directSaveIdentity == identity) }
            )
            if let failure = operation.error {
                let message = "Couldn't save: \(failure)"
                error = message
                saveAlert = MinerSettingsSaveAlert(title: "Settings not saved", message: message)
                return
            }
            guard await store.refreshAfterWrite(for: device) else {
                let message = "The request was accepted, but fresh settings could not be read. Your draft was kept. Reconnect and refresh before making another change."
                error = message
                saveAlert = MinerSettingsSaveAlert(title: "Request accepted · refresh unavailable", message: message)
                return
            }
            if let displaySetting {
                guard let info, displaySetting.matches(payload, in: info),
                      identity == nil || directSaveIdentity == identity else {
                    let message = "The miner accepted the request, but the new display setting could not be verified. Refresh before trying again."
                    error = message
                    saveAlert = MinerSettingsSaveAlert(title: "Display change not verified", message: message)
                    return
                }
                loaded = false
                load()
                saveMessage = "Display settings saved. They take effect after a restart."
                saveAlert = MinerSettingsSaveAlert(
                    title: "Display settings saved",
                    message: identity == nil
                        ? "Restart the miner to see the change. Restart from here is unavailable because the miner’s identity could not be verified."
                        : "Restart \(device.name) to see the change. Mining will pause briefly.",
                    restartIdentity: identity
                )
                return
            }
            loaded = false
            load()
            saveMessage = "Request accepted for \(device.name)"
            saveAlert = MinerSettingsSaveAlert(
                title: "Request accepted",
                message: "The request was accepted by \(device.name). Latest readings were refreshed, but this safe settings path does not claim a verified readback."
            )
        }
    }

    /// Called only by the explicit Restart Miner button on the Display success alert.
    func restartAfterDisplaySave(_ identity: MinerInlineActionState.Identity) {
        guard usesCompactSettingsHubPreview, !isSaving, !isRestartingDisplay else { return }
        guard directSaveIdentity == identity else {
            error = "The miner is offline or its identity changed. No restart was sent."
            return
        }
        error = nil
        isRestartingDisplay = true
        saveMessage = nil
        Task { @MainActor in
            defer { isRestartingDisplay = false }
            let operation = MinerOperationModel(session: store.session)
            await operation.execute(device: device, endpoint: .restart, body: nil, query: [], isDemo: store.isDemo,
                                    validatePreflight: { preflight in
                guard MinerInlineActionState.identity(from: preflight) == identity else {
                    throw MinerToolError.message("The miner identity changed. No restart was sent.")
                }
            }, writeAuthorized: { directSaveIdentity == identity })
            if let failure = operation.error {
                error = "Restart not confirmed: \(failure)"
            } else {
                saveMessage = "Miner accepted the restart request."
            }
        }
    }

    /// Inline progress and result for direct saves.
    @ViewBuilder
    var directSaveStatus: some View {
        if isSaving && savingDisplaySetting == nil {
            HStack(spacing: 8) {
                ProgressView()
                Text("Saving…").fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.saveStatus")
        } else if let saveMessage {
            Label(saveMessage, systemImage: "checkmark.circle.fill")
                .fleetFont(.footnote, weight: .semibold)
                .foregroundStyle(FleetTheme.positive)
                .accessibilityIdentifier("settings.saveStatus")
        }
    }
}
