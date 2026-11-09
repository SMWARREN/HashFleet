import SwiftUI
import UniformTypeIdentifiers

/// Document wrapper enabling native system file save/export via .fileExporter
struct FleetReportDocument: FileDocument, Sendable {
    static let readableContentTypes: [UTType] = [.pdf, .commaSeparatedText]

    var data: Data
    var contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        self.contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Settings integration: `FleetReportView(store: store)`. Reads the existing live store only.
@MainActor
struct FleetReportView: View {
    let store: FleetStore
    @State private var report: FleetReportSnapshot?
    @State private var presentation: Presentation?
    // Retain the lease independently until onDismiss, even after the sheet binding becomes nil.
    @State private var sharedFile: FleetReportTemporaryFile?
    @State private var exportError: String?
    @State private var exportDocument: FleetReportDocument?
    @State private var isExporterPresented = false
    @State private var exportFilename = ""

    /// Content and presentation are one atomic value, avoiding a blank first sheet caused by
    /// SwiftUI capturing an optional payload before an independent presentation flag changes.
    private enum Presentation: Identifiable {
        case pdf(id: UUID, data: Data)
        case share(FleetReportTemporaryFile)

        var id: UUID {
            switch self {
            case .pdf(let id, _): id
            case .share(let file): file.id
            }
        }

        var isSharing: Bool {
            if case .share = self { true } else { false }
        }
    }

    var body: some View {
        FleetSettingsList {
            if let report {
                captureSection(report)
                summarySection(report)
                exportSection(report)
                FleetSettingsSection("Snapshot preview") {
                    if report.miners.isEmpty {
                        FleetSettingsRow(showsSeparator: false) {
                            ContentUnavailableView(
                                "No miners to report", systemImage: "square.grid.2x2",
                                description: Text("Add a miner to your fleet, then capture a new snapshot. You can still export this empty report.")
                            )
                            .accessibilityIdentifier("fleetReport.empty")
                        }
                    }
                    ForEach(report.miners) { miner in
                        FleetSettingsRow { FleetReportMinerPreview(miner: miner) }
                    }
                }
                .fleetSettingsSectionIdentifier("fleetReport.previewSection")
                .fleetSectionFullWidth()
            }
        }
        .tint(FleetTheme.accent)
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .fleetAppNavigation { $0.navigationTitle("Fleet Reports") }
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("fleetReport.page")
        .fleetDismissPresentationsOnNavigation {
            presentation = nil
            isExporterPresented = false
        }
        .onAppear {
            if report == nil { capture() }
        }
        .onDisappear {
            // Presenting the activity sheet may disappear this view. Do not revoke its URL early.
            if presentation?.isSharing != true { clearSharedFile() }
        }
        .sheet(item: sheetPresentation, onDismiss: clearSharedFile) { item in
            switch item {
            case .pdf(_, let data):
                FleetReportPDFPreview(data: data)
            case .share(let file):
                FleetReportShareSheet(url: file.url) { presentation = nil }
            }
        }
        .fleetPagePresentation(item: fullWindowPDF, onDismiss: clearSharedFile) { item in
            if case .pdf(_, let data) = item {
                FleetReportPDFPreview(data: data)
            }
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: exportDocument?.contentType ?? .pdf,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                exportError = nil
            case .failure(let error):
                if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
                    exportDocument = nil
                    return
                }
                if error is CancellationError {
                    exportDocument = nil
                    return
                }
                exportError = "The report could not be saved. Try again when local storage is available. No data was shared."
            }
            exportDocument = nil
        }
    }

    /// Keep native share panels separate from app-owned full-window PDF pages.
    private var sheetPresentation: Binding<Presentation?> {
        Binding(
            get: { FleetPagePresentationPolicy.usesInAppPages && presentation?.isSharing == false ? nil : presentation },
            set: { presentation = $0 }
        )
    }

    private var fullWindowPDF: Binding<Presentation?> {
        Binding(
            get: { FleetPagePresentationPolicy.usesInAppPages && presentation?.isSharing == false ? presentation : nil },
            set: { presentation = $0 }
        )
    }

    private func captureSection(_ report: FleetReportSnapshot) -> some View {
        FleetSettingsSection(footer: "The preview and any exports stay frozen at this capture time. Capture again to copy the latest "
            + "readings already in the app. This never contacts or changes your miners.") {
            FleetSettingsRow(showsSeparator: false) {
                FleetReportIllustration(width: 176)
                    .frame(maxWidth: .infinity, maxHeight: 116)
            }
            FleetSettingsRow {
                Label("On-demand snapshot", systemImage: "doc.text")
                    .fleetFont(.headline)
            }
            FleetSettingsRow {
                LabeledContent("Captured", value: FleetReportSnapshot.timestamp(report.capturedAt))
                    .fleetFont(.subheadline)
                    .accessibilityIdentifier("fleetReport.capturedAt")
            }
            if report.isDemo {
                FleetSettingsRow {
                    Label("Demo / simulated readings", systemImage: "flask")
                        .foregroundStyle(FleetTheme.warning)
                        .accessibilityIdentifier("fleetReport.demo")
                }
            }
            FleetSettingsRow {
                Text(FleetReportSnapshot.scopeNote)
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
            }
            FleetSettingsRow(showsSeparator: false) {
                Button("Capture latest stored readings", systemImage: "arrow.clockwise", action: capture)
                    .accessibilityIdentifier("fleetReport.capture")
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        .fleetSettingsSectionIdentifier("fleetReport.captureSection")
    }

    private func summarySection(_ report: FleetReportSnapshot) -> some View {
        FleetSettingsSection("At capture time", footer: FleetReportSnapshot.freshnessNote) {
            FleetSettingsRow { LabeledContent("Fleet size", value: "\(report.miners.count)") }
            FleetSettingsRow { LabeledContent("Online at last response", value: "\(report.onlineCount)") }
            FleetSettingsRow { LabeledContent("Offline at last check", value: "\(report.offlineCount)") }
            FleetSettingsRow { LabeledContent("Connection unconfirmed", value: "\(report.unconfirmedCount)") }
            FleetSettingsRow { LabeledContent("Fresh online readings", value: "\(report.currentCount)") }
            FleetSettingsRow { LabeledContent("Readings not fresh", value: "\(report.nonFreshCount)") }
            FleetSettingsRow { hashrateSubtotal("Hashrate subtotal", total: report.hashrate) }
            FleetSettingsRow(showsSeparator: false) { subtotal("Power subtotal", total: report.power, unit: "W") }
        }
        .fleetSettingsSectionIdentifier("fleetReport.summarySection")
    }

    private func hashrateSubtotal(_ title: String, total: FleetReportSnapshot.Total) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(
                title,
                value: FleetReportSnapshot.formattedHashrate(total.value)
            )
            Text(total.coverage)
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func subtotal(_ title: String, total: FleetReportSnapshot.Total, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: total.value.map { "\(FleetReportSnapshot.number($0)) \(unit)" } ?? "Not reported")
            Text(total.coverage)
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func exportSection(_ report: FleetReportSnapshot) -> some View {
        FleetSettingsSection("Preview & export", footer: "Generated locally. Nothing is sent unless you choose a destination in the system share sheet. "
            + "Temporary export files are removed after it closes. Copies you save or send remain at your "
            + "chosen destination.") {
            FleetSettingsRow {
                Label("Private by default", systemImage: "lock.shield")
                    .fleetFont(.headline)
            }
            FleetSettingsRow {
                Text(FleetReportSnapshot.privacyNote)
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
            }
            FleetSettingsRow {
                Button("Preview PDF", systemImage: "doc.richtext") {
                    guard presentation == nil else { return }
                    presentation = .pdf(id: UUID(), data: FleetReportPDF.render(report))
                }
                .accessibilityIdentifier("fleetReport.previewPDF")
                .fleetTourTarget("guide.previewPDF")
                .keyboardShortcut("p", modifiers: [.command])
            }

            FleetSettingsRow {
                Button("Save PDF…", systemImage: "arrow.down.doc") { save(report, format: .pdf) }
                    .accessibilityIdentifier("fleetReport.savePDF")
                    .keyboardShortcut("s", modifiers: [.command])
            }

            FleetSettingsRow {
                Button("Save CSV…", systemImage: "arrow.down.doc.fill") { save(report, format: .csv) }
                    .accessibilityIdentifier("fleetReport.saveCSV")
                    .keyboardShortcut("s", modifiers: [.command, .option])
            }

            FleetSettingsRow {
                Button("Share PDF…", systemImage: "square.and.arrow.up") { share(report, format: .pdf) }
                    .accessibilityIdentifier("fleetReport.sharePDF")
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            FleetSettingsRow(showsSeparator: false) {
                Button("Share CSV…", systemImage: "tablecells") { share(report, format: .csv) }
                    .accessibilityIdentifier("fleetReport.shareCSV")
                    .keyboardShortcut("e", modifiers: [.command, .option])
            }
            if let exportError {
                FleetSettingsRow(showsSeparator: false) {
                    Text(exportError).fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                        .accessibilityIdentifier("fleetReport.exportError")
                }
            }
        }
        .fleetSettingsSectionIdentifier("fleetReport.exportSection")
    }

    private func capture() {
        guard presentation == nil else { return }
        clearSharedFile()
        exportError = nil
        report = FleetReportSnapshot.capture(store: store)
    }

    private func save(_ report: FleetReportSnapshot, format: FleetReportTemporaryFile.Format) {
        guard presentation == nil else { return }
        clearSharedFile()
        exportError = nil
        let data = format == .pdf ? FleetReportPDF.render(report) : FleetReportCSV.encode(report)
        let stamp = FleetReportSnapshot.timestamp(report.capturedAt)
            .filter { $0.isASCII && ($0.isNumber || $0 == "T" || $0 == "Z") }.prefix(20)
        let filename = "hash-fleet-snapshot-\(stamp).\(format.rawValue)"
        let uti: UTType = format == .pdf ? .pdf : .commaSeparatedText

        exportDocument = FleetReportDocument(data: data, contentType: uti)
        exportFilename = filename
        isExporterPresented = true
    }

    private func share(_ report: FleetReportSnapshot, format: FleetReportTemporaryFile.Format) {
        guard presentation == nil else { return }
        clearSharedFile()
        exportError = nil
        do {
            let data = format == .pdf ? FleetReportPDF.render(report) : FleetReportCSV.encode(report)
            let file = try FleetReportTemporaryFile.create(data: data, format: format, capturedAt: report.capturedAt)
            sharedFile = file
            presentation = .share(file)
        } catch {
            exportError = "The report could not be prepared. Try again when local storage is available. No data was shared."
        }
    }

    private func clearSharedFile() {
        sharedFile?.remove()
        sharedFile = nil
    }
}
