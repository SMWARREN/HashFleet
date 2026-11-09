import SwiftUI
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers
import HashFleetCore

/// Accessible custom JSON editor view for custom firmware properties.
/// Accepts arbitrary keys and nested JSON, validates format, size, finite numbers, and nonempty objects,
/// preserves unknown keys and integer precision, and hands off the validated UTF-8 JSON text
/// via `onStaged` to the existing PendingMinerWrite review and confirmation flow.
/// All draft state is held strictly in memory. Never executes network operations or merges stock defaults.
struct MinerCustomJSONView: View {
    let device: MinerDevice
    let isDemo: Bool
    let isOffline: Bool
    let onStaged: (String) -> Void

    @State private var draft = MinerCustomJSONDraft()
    @FocusState private var editorFocused: Bool
    @State private var errorMessage: String?
    @State private var showingFileImporter = false
    @State private var importNotice: String?
    @State private var copyNotice: String?

    init(
        device: MinerDevice,
        isDemo: Bool = false,
        isOffline: Bool = false,
        initialJSON: String? = nil,
        onStaged: @escaping (String) -> Void
    ) {
        self.device = device
        self.isDemo = isDemo
        self.isOffline = isOffline
        self.onStaged = onStaged
        if let initialJSON {
            _draft = State(initialValue: MinerCustomJSONDraft(rawText: initialJSON))
        }
    }

    var body: some View {
        FleetSettingsForm {
            noticeSection
            editorSection
            actionSection
            reviewTriggerSection
        }
        .navigationTitle("Custom JSON")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: FleetToolbarLocation.trailing) {
                Spacer()
                Button("Format") { formatJSON() }
                Button("Done") { editorFocused = false }
                    .accessibilityIdentifier("custom_json.done")
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) {
            handleFileImport($0)
        }
    }

    // MARK: - Sections

    private var noticeSection: some View {
        FleetSettingsSection {
            Label("Custom firmware settings editor", systemImage: "cpu.fill")
                .fleetFont(.headline)
                .foregroundStyle(FleetTheme.accent)
            Text(
                "Enter any custom or firmware-specific JSON"
                    + " fields. Values stage only and are never"
                    + " merged or altered. Target endpoint:"
                    + " PATCH /api/system."
            )
            .fleetFont(.footnote)
            .foregroundStyle(FleetTheme.secondary)
            if isDemo {
                Label("Demo mode: mutations are locked and cannot be applied.", systemImage: "lock.fill")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
            }
            if isOffline && !isDemo {
                Label("Miner is offline or stale. Settings are read-only.", systemImage: "wifi.slash")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.warning)
            }
        }
        .listRowBackground(FleetTheme.surface)
    }

    private var editorSection: some View {
        FleetSettingsSection("JSON Payload (Object Only)") {
            TextEditor(text: $draft.rawText)
                .focused($editorFocused)
                .fleetFont(.caption, design: .monospaced)
                .frame(minHeight: 220)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Custom JSON payload editor")
                .accessibilityIdentifier("custom_json.editor")

            if let errorMessage {
                Text(errorMessage)
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.warning)
                    .accessibilityIdentifier("custom_json.error")
            }
            if let importNotice {
                Text(importNotice)
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.accent)
            }
            if let copyNotice {
                Text(copyNotice)
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            }
        }
        .listRowBackground(FleetTheme.surface)
    }

    private var actionSection: some View {
        FleetSettingsSection("Payload Tools") {
            Button(action: formatJSON) {
                Label("Format & Validate JSON", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("custom_json.format")

            Button(action: pasteFromClipboard) {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
            }
            .accessibilityIdentifier("custom_json.paste")

            Button(
                action: { showingFileImporter = true },
                label: { Label("Import .json File…", systemImage: "arrow.down.doc") }
            )
            .accessibilityIdentifier("custom_json.import_file")
        }
        .listRowBackground(FleetTheme.surface)
    }

    private var reviewTriggerSection: some View {
        FleetSettingsSection {
            Button(action: stageForReview) {
                HStack {
                    Label("Review in Endpoint Explorer…", systemImage: "hand.raised.fill")
                    Spacer()
                    Image(systemName: "chevron.right").fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                }
            }
            .disabled(isOffline && !isDemo)
            .accessibilityIdentifier("custom_json.stage_review")

            Text(
                "Validates the JSON and opens the exact request"
                    + " review before any transmission. Nothing is"
                    + " sent until confirmed with APPLY in the"
                    + " review gate."
            )
            .fleetFont(.footnote)
            .foregroundStyle(FleetTheme.secondary)
        }
        .listRowBackground(FleetTheme.surface)
    }

    // MARK: - Actions

    private func formatJSON() {
        errorMessage = nil
        importNotice = nil
        copyNotice = nil
        do {
            try draft.format()
            copyNotice = "Formatted and validated successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pasteFromClipboard() {
        errorMessage = nil
        importNotice = nil
        copyNotice = nil
        #if canImport(UIKit)
            let pasteboardString = UIPasteboard.general.string
        #else
            let pasteboardString = NSPasteboard.general.string(forType: .string)
        #endif
            guard let pasteboardString, !pasteboardString.isEmpty else {
                errorMessage = "Clipboard is empty or does not contain text."
                return
            }
            do {
                try draft.importJSON(pasteboardString)
                importNotice = "Imported JSON from clipboard."
            } catch {
                errorMessage = error.localizedDescription
            }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        importNotice = nil
        copyNotice = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try draft.importFromFile(url: url)
                importNotice = "Imported \(url.lastPathComponent) successfully."
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func stageForReview() {
        errorMessage = nil
        importNotice = nil
        copyNotice = nil
        do {
            let (wireData, _) = try draft.validate()
            let validatedJSONString = String(bytes: wireData, encoding: .utf8) ?? "{}"
            onStaged(validatedJSONString)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Custom JSON editor · demo") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.json-preview")!)
    store.loadDemo()
    return NavigationStack {
        MinerCustomJSONView(
            device: store.devices[0],
            isDemo: true,
            isOffline: false,
            initialJSON: "{\n  \"frequency\": 550\n}"
        ) { _ in }
    }
}
