import SwiftUI
import AppKit
import HashFleetCore

@main
struct HashFleetMenuBarApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    /// A fixed status-item width keeps the popover anchor stationary while live digits change.
    /// Variable-length items move their left edge as the title grows or shrinks, which makes an
    /// already-open popover visibly jump across the menu bar.
    private let statusItem = NSStatusBar.system.statusItem(withLength: 164)
    private let popover = NSPopover()
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        refreshStatusItem()

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusItem() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = FleetMenuBarBrand.logoImage
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.contentViewController = NSHostingController(rootView: FleetMenuBarContent())
    }

    private func refreshStatusItem() {
        let now = Date()
        let mode = FleetMenuBarPreferenceStorage.shared.load()
        statusItem.isVisible = mode.shouldShow

        guard let button = statusItem.button else { return }
        let snapshot = FleetMenuBarSnapshotStorage.shared.load()
        button.title = snapshot.glance.minerCount > 0 ? "  " + FleetMenuBarFormat.compactTitle(snapshot, now: now) : ""
        button.toolTip = FleetMenuBarFormat.accessibilityTitle(snapshot, now: now)
        button.setAccessibilityLabel(button.toolTip ?? "Hash Fleet")
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private struct FleetMenuBarContent: View {
    @State private var refreshDate = Date()

    var body: some View {
        let snapshot = FleetMenuBarSnapshotStorage.shared.load()
        let glance = snapshot.glance
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(nsImage: FleetMenuBarBrand.logoImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(glance.isDemo ? "Hash Fleet · DEMO" : "Hash Fleet").font(.headline)
                    Text(FleetMenuBarFormat.hashrate(snapshot.reportedHashrate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Label("\(glance.isStale(at: refreshDate) ? "Stale · " : "")\(glance.onlineCount)/\(glance.minerCount)", systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(glance.isStale(at: refreshDate) || glance.isDemo ? .orange : .green)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if glance.minerCount == 0 {
                        Text("Open Hash Fleet on this Mac to publish fleet stats.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 14) {
                            Label(FleetMenuBarFormat.power(snapshot.reportedPower), systemImage: "bolt.fill")
                            Label {
                                Text(glance.updatedAt, style: .relative)
                            } icon: {
                                Image(systemName: "clock")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Divider()
                        if snapshot.miners.isEmpty {
                            Text("Open Hash Fleet to refresh the miner list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(snapshot.miners) { miner in
                                    FleetMenuBarMinerRow(miner: miner, isStale: glance.isStale(at: refreshDate))
                                    if miner.id != snapshot.miners.last?.id { Divider() }
                                }
                            }
                        }
                    }

                    // One miner-first view, including block-found history regardless of
                    // any display preference saved by an older app version.
                    Divider()
                    sessionSection(snapshot, isStale: glance.isStale(at: refreshDate))
                    Divider()
                    notificationSection(snapshot)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(URL(string: "hashfleet://fleet")!)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                Spacer()
                Button {
                    FleetMenuBarPreferenceStorage.shared.save(.hidden)
                } label: {
                    Image(systemName: "eye.slash")
                }
                .help("Hide system menu item")
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit companion")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 360, height: 520)
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                refreshDate = .now
            }
        }
    }

    private func notificationSection(_ snapshot: FleetMenuBarSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent notifications").font(.subheadline.weight(.semibold))
            if let entries = snapshot.notifications, !entries.isEmpty {
                ForEach(entries) { entry in
                    // Miner name is the primary line so history rows read like the miner cards
                    // above them. An empty name falls back to an explicit label, never an orphan
                    // title-only row.
                    VStack(alignment: .leading, spacing: 2) {
                        let name = entry.minerName.trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(name.isEmpty ? "Unknown miner" : name).font(.callout.weight(.medium))
                        Text(entry.title).font(.caption)
                        Text(entry.occurredAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text("No recent notifications")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("menuActivity.notifications")
    }

    private func sessionSection(_ snapshot: FleetMenuBarSnapshot, isStale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session best").font(.subheadline.weight(.semibold))
            Text("Best share since each miner's session reset, not a solved block.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if snapshot.miners.isEmpty {
                Text("Open Hash Fleet to refresh session records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.miners) { miner in
                HStack(alignment: .firstTextBaseline) {
                    Text(miner.name).lineLimit(2)
                    Spacer(minLength: 8)
                    Text(FleetMenuBarFormat.sessionBest(miner, isStale: isStale) ?? "Not currently reported")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("menuActivity.sessionBest")
    }
}

private struct FleetMenuBarMinerRow: View {
    let miner: FleetMenuBarMinerSummary
    let isStale: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(miner.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if miner.isSimulated {
                        Text("DEMO")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 4)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(detailText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let notice = miner.notices.first {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 7)
    }

    private var detailText: String {
        miner.segments.isEmpty ? statusText : miner.segments.joined(separator: "  ·  ")
    }

    private var statusText: String {
        FleetMenuBarFormat.rowStatus(miner, isStale: isStale)
    }

    private var statusColor: Color {
        if FleetMenuBarFormat.rowIsLive(miner, isStale: isStale) { return .green }
        if isStale || miner.isSimulated { return .orange }
        switch miner.status {
        case .online: return .green
        case .connecting, .reconnecting: return .orange
        case .offline: return .red
        }
    }
}

private enum FleetMenuBarBrand {
    static let logoImage: NSImage = {
        if let image = NSImage(named: "HashFleetStatusIcon") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            image.accessibilityDescription = "Hash Fleet"
            return image
        }
        return NSImage(
            systemSymbolName: "server.rack",
            accessibilityDescription: "Hash Fleet"
        ) ?? NSImage()
    }()
}
