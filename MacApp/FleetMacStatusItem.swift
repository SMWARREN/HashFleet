import AppKit
import SwiftUI

@MainActor
final class FleetMacStatusItemController: NSObject {
    private let runtime: FleetMacRuntime
    private let openDestination: @MainActor (FleetSidebarDestination) -> Void
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var timer: Timer?

    init(runtime: FleetMacRuntime, openDestination: @escaping @MainActor (FleetSidebarDestination) -> Void) {
        self.runtime = runtime
        self.openDestination = openDestination
        super.init()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 540)
        popover.contentViewController = NSHostingController(rootView:
            FleetMacMenuBarContent(runtime: runtime) { [weak self] destination in
                guard let self else { return }
                FleetMacMenuNavigation.select(destination,
                    dismiss: { self.popover.performClose(nil) }, open: self.openDestination)
            })
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        popover.performClose(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private func refresh() {
        guard runtime.menuBarPreferences.load().shouldShow else {
            popover.performClose(nil)
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(togglePopover(_:))
            item.button?.image = Self.makeStatusImage(height: 22)
            item.button?.image?.accessibilityDescription = "Hash Fleet"
            item.button?.imagePosition = .imageLeading
            item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            item.button?.setAccessibilityIdentifier("hashfleet.native.status-item")
            statusItem = item
        }
        guard let button = statusItem?.button else { return }
        let snapshot = runtime.store.menuBarSnapshot
        let now = Date.now
        let title = " " + FleetMacChrome.statusTitle(
            compactTitle: FleetMenuBarFormat.compactTitle(snapshot, now: now))
        let accessibilityTitle = FleetMenuBarFormat.accessibilityTitle(snapshot, now: now)
        // This runs every second. Assigning an unchanged title still re-lays out the status
        // bar button, so only write what actually changed.
        if button.title != title { button.title = title }
        if button.toolTip != accessibilityTitle {
            button.toolTip = accessibilityTitle
            button.setAccessibilityLabel(accessibilityTitle)
        }
    }

    static func makeStatusImage(
        height: CGFloat,
        imageNamed: (NSImage.Name) -> NSImage? = { NSImage(named: $0) }
    ) -> NSImage? {
        guard height.isFinite, height > 0,
              let source = imageNamed(NSImage.Name("HashFleetStatusIcon")),
              let image = source.copy() as? NSImage else { return nil }
        let aspectRatio = source.size.width / source.size.height
        guard aspectRatio.isFinite, aspectRatio > 0 else { return nil }
        image.size = NSSize(width: height * aspectRatio, height: height)
        image.isTemplate = false
        return image
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

struct FleetMacMenuBarContent: View {
    let runtime: FleetMacRuntime
    let openDestination: @MainActor (FleetSidebarDestination) -> Void
    @State private var showsNotifications = false

    var body: some View {
        let snapshot = runtime.store.menuBarSnapshot
        let stale = snapshot.glance.isStale(at: .now)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if let statusImage = FleetMacStatusItemController.makeStatusImage(height: 36) {
                    Image(nsImage: statusImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                }
                Text("Hash Fleet").font(.headline)
                Spacer()
                if snapshot.glance.isDemo { Text("DEMO").font(.caption.monospaced()).foregroundStyle(.orange) }
            }
            Text(FleetMenuBarFormat.hashrate(snapshot.reportedHashrate))
                .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack {
                Text("\(snapshot.glance.onlineCount) of \(snapshot.glance.minerCount) online")
                Spacer()
                Text(FleetMenuBarFormat.power(snapshot.reportedPower))
            }.font(.caption).foregroundStyle(.secondary)
            if snapshot.glance.isDemo {
                Label("Sample data. No hardware connections.", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.orange)
            } else if stale {
                Label("Readings are stale or not available.", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Picker("Menu section", selection: $showsNotifications) {
                Text("Miners").tag(false)
                Text("Notifications").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("hashfleet.native.menu-section")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !showsNotifications {
                        // Keep current readings and session bests together. Legacy display
                        // preferences must never hide miners or notification history.
                        ForEach(snapshot.miners) { miner in
                            Button { openMiner(miner.id) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(miner.name).font(.caption.weight(.semibold))
                                        Spacer()
                                        Text(FleetMenuBarFormat.rowStatus(miner, isStale: stale))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text(miner.segments.joined(separator: " · "))
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                    Text("Session best: " + (FleetMenuBarFormat.sessionBest(miner, isStale: stale) ?? "Unavailable"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    ForEach(miner.notices, id: \.self) { Text($0).font(.caption2).foregroundStyle(.orange) }
                                }
                                .padding(FleetSurfaceSpacing.cardInset)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .background(FleetMacChrome.background, in:
                                    RoundedRectangle(cornerRadius: FleetMacChrome.controlRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: FleetMacChrome.controlRadius, style: .continuous)
                                        .strokeBorder(FleetMacChrome.foreground.opacity(0.16))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("hashfleet.native.miner.\(miner.id)")
                            .accessibilityHint("Closes this menu and opens the miner in the workspace.")
                        }
                        if snapshot.miners.isEmpty { Text("Add a miner in the workspace to get started.").font(.caption) }
                    } else {
                        Text("Recent notifications").font(.caption.weight(.semibold))
                        if let notifications = snapshot.notifications, !notifications.isEmpty {
                            ForEach(notifications) { notification in
                                Button {
                                    let minerID = runtime.store.notificationInbox.first { $0.id == notification.id }?.event.deviceID
                                    openMiner(minerID)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        let name = notification.minerName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        Text(name.isEmpty ? "Unknown miner" : name).font(.caption.weight(.medium))
                                        Text(notification.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("hashfleet.native.notification.\(notification.id)")
                            }
                        } else { Text("No recent notifications.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(showsNotifications)
            Divider()
            HStack {
                Button("Open Hash Fleet") { openDestination(.overview) }
                    .buttonStyle(FleetMacToolbarButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityIdentifier("hashfleet.native.open-workspace")
                Spacer()
                Menu {
                    // Secondary support action: routes to the in-app support page, below the miner
                    // cards and never ahead of them. It opens an internal destination only and does
                    // not add a direct payment link that bypasses the storefront.
                    Button("Support Hash Fleet") { openDestination(.support) }
                    Divider()
                    Button("Hide menu bar item") { runtime.menuBarPreferences.save(.hidden) }
                    Divider()
                    Button("Quit Hash Fleet") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }
                .fleetToolbarMenu()
                .fixedSize()
                .accessibilityLabel("Hash Fleet actions")
            }
            Text("Part of this app. Quit Hash Fleet stops both surfaces.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 360, height: 540)
        .fleetMacMenuSurface()
        .preferredColorScheme(runtime.store.preferences.appearance.colorScheme)
    }

    private func openMiner(_ minerID: UUID?) {
        openDestination(FleetMacMenuNavigation.destination(minerID: minerID,
            availableIDs: Set(runtime.store.visibleDevices.map(\.id))))
    }
}
