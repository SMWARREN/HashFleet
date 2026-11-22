#if os(iOS)
import SwiftUI
import WebKit
import HashFleetCore

extension MinerDetailView {
    var compactMinerRefreshButton: some View {
        let refreshing = store.isRefreshing
        return Button {
            Task { await store.refresh() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .opacity(refreshing ? 0 : 1)
                .overlay {
                    if refreshing {
                        ProgressView().controlSize(.mini).accessibilityHidden(true)
                    }
                }
        }
        .disabled(refreshing)
        .accessibilityLabel("Refresh")
        .accessibilityValue(refreshing ? "Refreshing" : "")
        .accessibilityIdentifier("detail.refresh")
    }

    var compactMinerStatus: some View {
        let observed = snapshot.flatMap { value in
            value.updatedAt.map { max($0, value.completeSnapshotAt ?? $0) } ?? value.completeSnapshotAt
        }
        let statusLines = dynamicTypeSize.isAccessibilitySize ? 2 : 1
        let address = currentDevice.address
        let target = try? currentDevice.validatedURL()
        return MinerReviewDisclosure(symbol: "antenna.radiowaves.left.and.right", identifier: "detail.statusDisclosure") {
            TimelineView(.periodic(from: .now, by: MinerSnapshotFreshness.refreshInterval)) { context in
                let freshness = MinerSnapshotFreshness(updatedAt: observed, now: context.date)
                let state = compactConnectionState(freshness: freshness)
                Text(freshness.map { "\(state.title) · \($0.summary)" } ?? state.title)
                    .foregroundStyle(state.color)
                    .lineLimit(statusLines, reservesSpace: true)
            }
        } details: {
            if let snapshot, snapshot.info != nil || snapshot.error != nil, !MinerWriteAvailability.allows(snapshot) {
                MinerOfflineSettingsNotice(snapshot: snapshot)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = snapshot?.error, snapshot?.isReconnecting != true {
                Label(error, systemImage: "wifi.exclamationmark")
                    .foregroundStyle(FleetTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("detail.telemetryError")
            }
            if let target {
                NavigationLink {
                    MinerWebInterface(url: target)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Open miner web page")
                                .foregroundStyle(FleetTheme.accent)
                            Text(address).foregroundStyle(FleetTheme.secondary)
                                .fleetFont(.caption, design: .monospaced)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right").accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.address")
            } else {
                Text(address).foregroundStyle(FleetTheme.secondary).textSelection(.enabled)
            }
            if let version = FirmwareUpdateStore.currentVersion(from: info) {
                LabeledContent("Installed firmware", value: version)
                    .accessibilityIdentifier("detail.installedFirmware")
            }
            if snapshot?.isReconnecting != true, snapshot?.error == nil, liveConnectionError != nil {
                Label("Live monitoring unavailable · using HTTP refresh", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(FleetTheme.warning)
                    .accessibilityIdentifier("detail.liveError")
            }
        }
        .fleetCard(padding: 0, border: .clear, cornerRadius: 14)
    }

    private func compactConnectionState(freshness: MinerSnapshotFreshness?) -> (title: String, color: Color) {
        if snapshot?.isReconnecting == true { return ("Reconnecting", FleetTheme.secondary) }
        if snapshot?.error != nil { return ("Offline", FleetTheme.warning) }
        if snapshot?.isCached == true { return ("Cached readings", FleetTheme.secondary) }
        guard info != nil, let freshness else { return ("Waiting for readings", FleetTheme.secondary) }
        if freshness.isStale { return ("Readings may be stale", FleetTheme.warning) }
        // Pause is an operating state, not a fault. Keep it inside the reserved status line.
        if info?.raw["miningPaused"]?.boolValue == true { return ("Mining paused", FleetTheme.warning) }
        return (isLive ? "Live" : "Connected", FleetTheme.positive)
    }

    private var compactFirmwareNotice: FirmwareUpdateNotice? {
        if store.isDemo {
            return info.flatMap { NumberFirstPreview.minerAvailability($0).firmwareUpdate(NumberFirstPreview.minerFirmwareNotice) }
        }
        guard let notice = store.firmwareUpdates.notice(for: device.id), !notice.checkFailed,
              notice.currentVersion == FirmwareUpdateStore.currentVersion(from: info),
              store.firmwareUpdates.shouldShow(notice, for: device.id)
        else { return nil }
        return notice
    }

    @ViewBuilder var compactMinerFirmwareUpdates: some View {
        if let notice = compactFirmwareNotice, let latest = notice.latestVersion {
            MinerReviewDisclosure(symbol: "arrow.down.circle", identifier: "detail.firmwareDisclosure") {
                Text("Firmware update · \(latest)")
                    .foregroundStyle(FleetTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            } details: {
                LabeledContent("Installed", value: notice.currentVersion)
                LabeledContent("Available", value: latest)
                if store.isDemo {
                    Text("Demo release example · no install").foregroundStyle(FleetTheme.secondary)
                } else {
                    ForEach(notice.releases.prefix(5)) { release in firmwareReleaseRow(release) }
                    Button("Dismiss this update") {
                        store.firmwareUpdates.dismiss(deviceID: device.id, releaseVersion: latest)
                    }
                    .fontWeight(.semibold)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("detail.firmwareUpdates.dismiss")
                }
            }
            .fleetCard(padding: 0, fill: FleetTheme.accent.opacity(0.10), border: .clear, cornerRadius: 14)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.firmwareUpdates")
        }
    }
}

private struct MinerReviewDisclosure<Summary: View, Details: View>: View {
    let symbol: String
    let identifier: String
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let details: () -> Details
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol).accessibilityHidden(true)
                    summary()
                    Spacer(minLength: 2)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                }
                .foregroundStyle(FleetTheme.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fleetFont(.caption, weight: .semibold)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier(identifier)
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    details()
                }
                .fleetFont(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .bottom], 12)
            }
        }
    }
}

/// A one-origin browser for the saved miner. The native navigation Back button
/// returns directly to its detail page and the browser has no access to app credentials.
private struct MinerWebInterface: View {
    let url: URL
    @State private var failed = false

    var body: some View {
        MinerWebPage(url: url, failed: $failed)
            .overlay {
                if failed {
                    ContentUnavailableView("Miner web page unavailable", systemImage: "wifi.exclamationmark",
                                           description: Text("Go back to the miner to verify its address and connection."))
                        .background(FleetTheme.canvas)
                }
            }
            .navigationTitle("Miner web page")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MinerWebPage: UIViewRepresentable {
    let url: URL
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(origin: url, failed: $failed) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let origin: URL
        @Binding var failed: Bool

        init(origin: URL, failed: Binding<Bool>) {
            self.origin = origin
            _failed = failed
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.targetFrame != nil, let url = navigationAction.request.url,
                  url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port,
                  url.user == nil, url.password == nil else { return .cancel }
            return .allow
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            if (error as NSError).code != NSURLErrorCancelled { failed = true }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            if (error as NSError).code != NSURLErrorCancelled { failed = true }
        }
    }
}
#endif
