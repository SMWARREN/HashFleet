import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FleetBackupFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    static let writableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// A deliberately manual backup page. Export and import both open the system file/share surfaces;
/// import never mutates the store until the user reviews and confirms the additions.
struct FleetBackupView: View {
    let store: FleetStore

    @State private var isExporting = false
    @State private var exportDocument: FleetBackupFileDocument?
    @State private var pendingData: Data?
    @State private var preview: FleetBackupRestorePreview?
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var didApplyMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Back up your fleet")
                    .fleetFont(.title2, weight: .bold)
                Text(FleetBackup.privacyWarning)
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        prepareExport()
                    } label: {
                        Label("Export fleet backup", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FleetPrimaryButtonStyle())
                    .disabled(store.isDemo)
                    .accessibilityIdentifier("fleetBackup.export")

                    Button {
                        isImporting = true
                    } label: {
                        Label("Import fleet backup", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(FleetTheme.accent)
                    .accessibilityIdentifier("fleetBackup.import")
                }
                .fleetCard()

                if store.isDemo {
                    Label(
                        "Export is unavailable in demo mode. Importing a confirmed backup will add only new saved miners.",
                        systemImage: "info.circle"
                    )
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let preview {
                    restorePreview(preview)
                }

                if let didApplyMessage {
                    Label(didApplyMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(FleetTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .background(FleetTheme.canvas)
        .foregroundStyle(FleetTheme.ink)
        .navigationTitle("Backup & restore")
        .navigationBarTitleDisplayMode(.inline)
        .fleetDismissPresentationsOnNavigation {
            isImporting = false
            isExporting = false
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: readImport
        )
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "hash-fleet-backup.json",
            onCompletion: { result in
                if case .failure(let error) = result,
                    (error as? CocoaError)?.code != .userCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        )
        .alert("Backup unavailable", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Backup restored", isPresented: applyAlertBinding) {
            Button("OK", role: .cancel) { didApplyMessage = nil }
        } message: {
            Text(didApplyMessage ?? "")
        }
    }

    @ViewBuilder
    private func restorePreview(_ preview: FleetBackupRestorePreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review import")
                .fleetFont(.headline)
            if preview.additions.isEmpty {
                Text("No new miners will be added. Existing miners are never overwritten or deleted.")
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
            } else {
                Text("This file will add \(preview.additionCount) miner\(preview.additionCount == 1 ? "" : "s"). Existing miners are not changed.")
                    .fleetFont(.subheadline)
                ForEach(preview.additions, id: \.self) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name.isEmpty ? "Automatic name" : entry.name)
                            .fleetFont(.subheadline, weight: .semibold)
                        Text(entry.address)
                            .fleetFont(.caption, design: .monospaced)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                }
            }
            HStack {
                Button("Cancel") { clearPreview() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Add miners") { confirmImport() }
                    .buttonStyle(FleetPrimaryButtonStyle())
                    .disabled(pendingData == nil || preview.isEmpty)
                    .accessibilityIdentifier("fleetBackup.confirm")
            }
        }
        .fleetCard()
        .accessibilityIdentifier("fleetBackup.preview")
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var applyAlertBinding: Binding<Bool> {
        Binding(
            get: { didApplyMessage != nil },
            set: { if !$0 { didApplyMessage = nil } }
        )
    }

    private func prepareExport() {
        do {
            exportDocument = FleetBackupFileDocument(data: try store.fleetBackupExportData())
            isExporting = true
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func readImport(_ result: Result<[URL], Error>) {
        // A new selection replaces the old pending confirmation. A cancelled or failed selection
        // must never leave an earlier file looking ready to apply.
        clearPreview()
        didApplyMessage = nil
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let data = try FleetBackup.readBoundedFile(from: url)
            let nextPreview = try store.fleetBackupPreview(data: data)
            pendingData = data
            preview = nextPreview
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch is CancellationError {
            return
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func confirmImport() {
        guard let pendingData, let preview else { return }
        do {
            let count = try store.applyFleetBackup(data: pendingData, expectedPreview: preview)
            clearPreview()
            didApplyMessage = "Added \(count) miner\(count == 1 ? "" : "s"). Existing miners were left unchanged."
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func clearPreview() {
        pendingData = nil
        preview = nil
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
