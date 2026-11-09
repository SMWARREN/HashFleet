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

    private var canWriteDirectly: Bool {
        MinerWriteAvailability.allows(
            store.snapshot(for: device.id), device: device,
            currentDevices: store.visibleDevices, isDemo: store.isDemo
        )
    }

    private func saveDirectly(_ payload: JSONValue) {
        guard !isSaving else { return }
        saveMessage = nil
        saveAlert = nil
        guard !store.isDemo else {
            let message = "Demo mode is read only. Nothing was sent."
            error = message
            saveAlert = MinerCompletionAlert(title: "Settings not saved", message: message)
            return
        }
        guard canWriteDirectly else {
            let message = "Offline settings are read only. Reconnect and refresh first."
            error = message
            saveAlert = MinerCompletionAlert(title: "Settings not saved", message: message)
            return
        }
        let body: Data
        do { body = try JSONEncoder().encode(payload) } catch {
            let message = error.localizedDescription
            self.error = message
            saveAlert = MinerCompletionAlert(title: "Settings not saved", message: message)
            return
        }
        error = nil
        isSaving = true
        #if os(macOS)
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        #else
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        #endif
        Task { @MainActor in
            let operation = MinerOperationModel()
            // execute() re-reads system info first, so a miner that dropped off since the
            // last refresh is never written to.
            await operation.execute(
                device: device,
                endpoint: .settings,
                body: body,
                query: [],
                isDemo: store.isDemo,
                writeAuthorized: { canWriteDirectly }
            )
            defer { isSaving = false }
            if let failure = operation.error {
                let message = "Couldn't save: \(failure)"
                error = message
                saveAlert = MinerCompletionAlert(title: "Settings not saved", message: message)
                return
            }
            guard await store.refreshAfterWrite(for: device) else {
                let message = "The request was accepted, but fresh settings could not be read. Your draft was kept. Reconnect and refresh before making another change."
                error = message
                saveAlert = MinerCompletionAlert(title: "Request accepted · refresh unavailable", message: message)
                return
            }
            loaded = false
            load()
            saveMessage = "Request accepted for \(device.name)"
            saveAlert = MinerCompletionAlert(
                title: "Request accepted",
                message: "The request was accepted by \(device.name). Latest readings were refreshed, but this safe settings path does not claim a verified readback."
            )
        }
    }

    /// Inline progress and result for direct saves.
    @ViewBuilder
    var directSaveStatus: some View {
        if isSaving {
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
