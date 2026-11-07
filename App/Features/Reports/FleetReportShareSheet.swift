import SwiftUI
#if canImport(UIKit)
import UIKit

struct FleetReportShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: @MainActor @Sendable () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in onFinish() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct FleetReportShareSheet: View {
    let url: URL
    let onFinish: @MainActor @Sendable () -> Void

    var body: some View {
        ShareLink(item: url) {
            Label("Share PDF…", systemImage: "square.and.arrow.up")
        }
        .padding()
    }
}
#endif
