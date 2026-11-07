import PDFKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct FleetReportPDFPreview: View {
    let data: Data
    @Environment(\.fleetGuidedDemo) private var guidedDemo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FleetPageNavigationStack {
            FleetReportPDFDocumentView(data: data)
                .fleetAppNavigation { $0.navigationTitle("Snapshot PDF") }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !guidedDemo {
                    ToolbarItem(placement: FleetToolbarLocation.trailing) {
                        Button("Done") { dismiss() }
                            .fleetToolbarButton()
                    }
                    .fleetUnadornedToolbarBackground()
                    }
                }
        }
        .accessibilityIdentifier("fleetReport.pdfPreview")
    }
}

#if canImport(UIKit)
private struct FleetReportPDFDocumentView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
#else
private struct FleetReportPDFDocumentView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}
#endif
