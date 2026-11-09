import SwiftUI
#if os(macOS)
import AppKit
#endif
import HashFleetCore

/// Wide-window arrangement for the dashboard (iPad and the iPad app on a Mac). Phones keep the
/// existing single column because their width never reaches the two-column threshold.
extension DashboardView {
    func isWideDashboard(_ viewport: GeometryProxy) -> Bool {
        FleetLayout.usesTwoColumns(width: FleetLayout.dashboardAvailableWidth(for: viewport.size.width))
            && !dynamicTypeSize.isAccessibilitySize
    }

    /// Places two related cards side by side on wide windows, stacked otherwise.
    @ViewBuilder
    func dashboardPair<Leading: View, Trailing: View>(
        wide: Bool,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        if wide && FleetLayout.isMac {
            FleetMinerDetailGrid(maximumColumns: 2, minimumColumnWidth: 320, spacing: 14) {
                leading()
                trailing()
            }
        } else if wide {
            HStack(alignment: .top, spacing: 14) {
                leading().frame(maxWidth: .infinity, alignment: .top)
                trailing().frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            leading()
            trailing()
        }
    }
}

/// Navigation targets accessible directly from the Mac / wide sidebar.
enum FleetSidebarDestination: Hashable, Identifiable, Sendable {
    case overview
    case miner(UUID)
    case network
    case energy
    case achievements
    case reports
    case backup
    case monitoring
    case preferences
    case about
    case support

    var id: String {
        switch self {
        case .overview: return "overview"
        case .miner(let id): return "miner-\(id.uuidString)"
        case .network: return "network"
        case .energy: return "energy"
        case .achievements: return "achievements"
        case .reports: return "reports"
        case .backup: return "backup"
        case .monitoring: return "monitoring"
        case .preferences: return "preferences"
        case .about: return "about"
        case .support: return "support"
        }
    }
}

/// A compact miner row designed for the Mac sidebar with status indicator, live hashrate, and temp.
struct MinerSidebarRow: View {
    let device: MinerDevice
    let snapshot: MinerSnapshot?
    let isDemo: Bool
    let isLive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var attention: MinerSidebarAttention? {
        MinerSidebarAttention.resolve(
            state: presentationState,
            temperature: snapshot?.info.flatMap { FleetFormat.sensor($0, keys: "temp") }
        )
    }

    private var presentationState: FleetMinerPresentationState {
        if snapshot?.info == nil, snapshot?.isReconnecting == true { return .loading }
        return FleetMinerPresentationState.resolve(
            isDemo: isDemo,
            hasInfo: snapshot?.info != nil,
            hasError: snapshot?.error != nil,
            isLive: isLive,
            isReconnecting: snapshot?.isReconnecting == true
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            // Dot and halo share one fixed slot the width of the sidebar icon tiles, pinned to
            // the slot's leading edge so the halo lines up flush with the tiles above and below.
            ZStack {
                if presentationState.isOperational {
                    Circle()
                        .strokeBorder(presentationState.color.opacity(0.35), lineWidth: 2)
                }
                Circle()
                    .fill(presentationState.color)
                    .frame(width: 8, height: 8)
                    // One ripple when the miner goes offline or comes back (ShipSwift swPing idea,
                    // using the app's existing one-shot pulse). Never repeats while idle.
                    .fleetStatusTransitionPulse(
                        isOnline: presentationState.isOperational,
                        color: presentationState.color,
                        reduceMotion: reduceMotion
                    )
            }
            .frame(width: 14, height: 14)
            .frame(width: FleetLayout.sidebarIconWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .fleetFont(.subheadline, weight: .medium)
                    .foregroundStyle(FleetTheme.ink)
                    .lineLimit(1)

                Text(device.address)
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if let attention, attention == .offline {
                    FleetStatusPill(text: attention.text, systemImage: attention.systemImage, tint: FleetTheme.warning)
                        .accessibilityLabel(attention.accessibilityLabel)
                } else if let info = snapshot?.info {
                    Text(FleetFormat.sensor(info, keys: "hashRate", "hashrate")
                        .map { FleetFormat.hashrateWithUnit($0) } ?? "Not reported")
                        .fleetFont(.caption2, weight: .semibold, design: .monospaced)
                        .foregroundStyle(FleetTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let attention {
                        FleetStatusPill(text: attention.text, systemImage: attention.systemImage, tint: MinerSidebarAttention.hotTint)
                            .accessibilityLabel(attention.accessibilityLabel)
                    } else if let temp = FleetFormat.sensor(info, keys: "temp") {
                        // `sensor` only guarantees finite; garbage like 1e300 from firmware would trap Int().
                        Text("\(FleetFormat.number(temp))°C")
                            .fleetFont(.caption2, design: .monospaced)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                } else {
                    Text("—")
                        .font(FleetTheme.mono(11))
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.address, forType: .string)
                #else
                UIPasteboard.general.string = device.address
                #endif
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }

            if let url = try? device.validatedURL() {
                Link(destination: url) {
                    Label("Open Web Interface", systemImage: "safari")
                }
            }
        }
    }
}

/// Persistent footer pinned at the bottom of the desktop sidebar showing live fleet vitals.
struct FleetSidebarFooter: View {
    let store: FleetStore
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(store.onlineCount > 0 ? FleetTheme.positive : FleetTheme.warning)
                            .frame(width: 6, height: 6)
                        Text(store.isDemo ? "Demo Fleet" : "\(store.onlineCount)/\(store.visibleDevices.count) Online")
                            .fleetFont(.caption2, weight: .medium)
                            .foregroundStyle(FleetTheme.secondary)
                    }

                    if store.totalHashrate > 0 {
                        Text(FleetFormat.hashrateWithUnit(store.totalHashrate))
                            .font(FleetTheme.mono(12).weight(.bold))
                            .foregroundStyle(FleetTheme.ink)
                    }
                }

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .fleetFont(.caption, weight: .semibold)
                        .foregroundStyle(FleetTheme.ink)
                        .frame(width: 28, height: 28)
                        .background(FleetTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Refresh fleet (⌘R)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            FleetTheme.surface
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FleetTheme.separator)
                .frame(height: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: -2)
    }
}

/// The dedicated macOS and wide iPad sidebar view giving direct access to all fleet features.
struct FleetSidebarView: View {
    @Binding var selection: FleetSidebarDestination?
    @Bindable var store: FleetStore
    var insights: MiningInsightsStore
    @Binding var showingAddMiner: Bool
    var onRefresh: () -> Void
    var onSelect: ((FleetSidebarDestination) -> Void)?

    @State private var searchText = ""
    @State private var confirmingDeleteAll = false
    #if os(macOS)
    @State private var showsSidebarSearch = false
    @FocusState private var sidebarSearchFocused: Bool
    @FocusState private var focusedDestination: FleetSidebarDestination?
    #endif

    private var filteredDevices: [MinerDevice] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return store.visibleDevices }
        return store.visibleDevices.filter { device in
            device.name.lowercased().contains(query) ||
            device.address.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            if showsSidebarSearch {
                HStack {
                    TextField("Filter miners…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($sidebarSearchFocused)
                        .accessibilityIdentifier("sidebar.search")
                    Button("Close filter", systemImage: "xmark") { closeSidebarSearch() }
                        .labelStyle(.iconOnly)
                        .help("Close miner filter")
                }
                .padding(12)
                .onExitCommand { closeSidebarSearch() }
            }
            #endif
            FleetSidebarList(selection: $selection) {
                Section {
                    sidebarDestinationRow(.overview) {
                        HStack {
                            FleetSidebarTileLabel(title: "Overview", destination: .overview)
                            Spacer()
                            if store.totalHashrate > 0 {
                                Text(FleetFormat.hashrateWithUnit(store.totalHashrate))
                                    .font(FleetTheme.mono(10))
                                    .fleetPillPadding()
                                    .background(FleetTheme.surface, in: Capsule())
                            }
                        }
                    }
                } header: {
                    sidebarSectionHeader("Fleet")
                }

                Section {
                    #if os(macOS)
                    // Native outline section headers flatten interactive children into
                    // an AXHeading. Keep this visually identical heading in list content
                    // so Add remains a real keyboard- and VoiceOver-accessible Button.
                    minerSectionHeading
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    #endif
                    ForEach(filteredDevices) { device in
                        sidebarDestinationRow(.miner(device.id)) {
                            MinerSidebarRow(
                                device: device,
                                snapshot: store.snapshots[device.id],
                                isDemo: store.isDemo,
                                isLive: store.liveConnectedDeviceIDs.contains(device.id)
                            )
                        }
                    }
                    if filteredDevices.isEmpty {
                        if store.visibleDevices.isEmpty {
                            Button {
                                showingAddMiner = true
                            } label: {
                                Label("Add your first miner", systemImage: "plus.circle")
                                    .fleetFont(.subheadline)
                            }
                        } else {
                            Text("No matching miners")
                                .fleetFont(.caption)
                                .foregroundStyle(FleetTheme.secondary)
                        }
                    }
                } header: {
                    #if os(iOS)
                    minerSectionHeading
                    #endif
                }

                Section {
                    sidebarDestinationRow(.network) {
                        FleetSidebarTileLabel(title: "Network insights", destination: .network)
                    }
                    sidebarDestinationRow(.energy) {
                        FleetSidebarTileLabel(title: "Energy & Efficiency", destination: .energy)
                    }
                    sidebarDestinationRow(.achievements) {
                        FleetSidebarTileLabel(title: "Achievements", destination: .achievements)
                    }
                    sidebarDestinationRow(.reports) {
                        FleetSidebarTileLabel(title: "Reports & Export", destination: .reports)
                    }
                } header: {
                    sidebarSectionHeader("Analytics & Insights")
                }

                Section {
                    sidebarDestinationRow(.backup) {
                        FleetSidebarTileLabel(title: "Backup & Restore", destination: .backup)
                    }
                    sidebarDestinationRow(.monitoring) {
                        FleetSidebarTileLabel(title: "App settings", destination: .monitoring)
                    }
                    sidebarDestinationRow(.about) {
                        FleetSidebarTileLabel(title: "About Hash Fleet", destination: .about)
                    }
                    sidebarDestinationRow(.support) {
                        FleetSidebarTileLabel(title: "Support Hash Fleet", destination: .support)
                    }
                } header: {
                    sidebarSectionHeader("Management")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(FleetTheme.sidebarSurface)
            .labelStyle(FleetSidebarLabelStyle())
            .fleetFont(.body)
            #if os(macOS)
            .environment(\.defaultMinListRowHeight, 44)
            #else
            .environment(\.defaultMinListRowHeight, 32)
            #endif
            .modifier(FleetSidebarSearchModifier(text: $searchText))
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Find a miner", systemImage: "magnifyingglass") {
                        showsSidebarSearch = true
                        sidebarSearchFocused = true
                    }
                    .labelStyle(.iconOnly)
                    .fleetToolbarButton()
                    .keyboardShortcut("f", modifiers: .command)
                    .help("Find a miner (⌘F)")
                    .accessibilityIdentifier("sidebar.findMiner")
                }
                .fleetUnadornedToolbarBackground()
            }
            #endif

            FleetSidebarFooter(store: store, onRefresh: onRefresh)
        }
        #if os(macOS)
        .fleetMacSidebarSurface(fill: FleetTheme.sidebarSurface)
        #else
        .background(FleetTheme.sidebarSurface)
        #endif
        .fleetWindowToolbarChrome()
        .confirmationDialog(
            "Delete all \(store.devices.count) miners?",
            isPresented: $confirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete all miners", role: .destructive) {
                selection = .overview
                store.removeAllMiners()
            }
            .accessibilityIdentifier("sidebar.confirmDeleteAllMiners")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every miner and its saved history from Hash Fleet. The miners themselves are not changed.")
        }
    }

    private var minerSectionHeading: some View {
        HStack {
            Text("Miners (\(store.visibleDevices.count))")
                #if os(macOS)
                .fleetFont(.body)
                #endif
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showingAddMiner = true
            } label: {
                Label("Add a new miner", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .fleetFont(.caption, weight: .bold)
                    .foregroundStyle(FleetTheme.accent)
                    .frame(width: FleetLayout.sidebarAddTargetSize, height: FleetLayout.sidebarAddTargetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar.addMiner")
            .help("Add a new miner")
            if !store.isDemo, !store.devices.isEmpty {
                Menu {
                    Button("Add miner…", systemImage: "plus") { showingAddMiner = true }
                    Divider()
                    Button("Delete all miners…", systemImage: "trash", role: .destructive) {
                        confirmingDeleteAll = true
                    }
                    .accessibilityIdentifier("sidebar.deleteAllMiners")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .fleetFont(.caption, weight: .bold)
                        .foregroundStyle(FleetTheme.accent)
                        .frame(width: FleetLayout.sidebarAddTargetSize, height: FleetLayout.sidebarAddTargetSize)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Miner actions")
                .accessibilityIdentifier("sidebar.minerActions")
                .help("Miner actions")
            }
        }
    }

    @ViewBuilder
    private func sidebarDestinationRow<Label: View>(
        _ destination: FleetSidebarDestination,
        @ViewBuilder label: () -> Label
    ) -> some View {
        #if os(macOS)
        Button {
            activate(destination)
        } label: {
            label()
                // Keep both text and trailing readings away from the rounded selection edge.
                .padding(FleetSurfaceSpacing.selection)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .background {
                    if selection == destination {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(FleetTheme.sidebarSelection)
                    }
                }
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(selection == destination ? .isSelected : [])
        .focused($focusedDestination, equals: destination)
        .onMoveCommand { direction in moveSidebarFocus(direction, from: destination) }
        .accessibilityIdentifier("sidebar.destination.\(destination.id)")
        #else
        // Explicit activation includes the already-selected row, so touch, keyboard
        // and VoiceOver use the same root-resetting selection binding.
        Button {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                NSLog("[FleetSidebarActivation] button %@", destination.id)
            }
            #endif
            activate(destination)
        } label: {
            label()
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tag(destination)
        .accessibilityAddTraits(selection == destination ? .isSelected : [])
        .accessibilityIdentifier("sidebar.destination.\(destination.id)")
        #endif
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            #if os(macOS)
            .fleetFont(.body)
            #endif
    }

    private func activate(_ destination: FleetSidebarDestination) {
        if let onSelect {
            onSelect(destination)
        } else {
            selection = destination
        }
    }

    #if os(macOS)
    private func moveSidebarFocus(_ direction: MoveCommandDirection, from destination: FleetSidebarDestination) {
        let destinations: [FleetSidebarDestination] = [.overview]
            + filteredDevices.map { .miner($0.id) }
            + [.network, .energy, .achievements, .reports, .backup, .monitoring, .about]
        guard let index = destinations.firstIndex(of: destination) else { return }
        let next: Int
        switch direction {
        case .up: next = max(0, index - 1)
        case .down: next = min(destinations.count - 1, index + 1)
        default: return
        }
        focusedDestination = destinations[next]
        activate(destinations[next])
    }

    private func closeSidebarSearch() {
        searchText = ""
        showsSidebarSearch = false
        sidebarSearchFocused = false
    }
    #endif
}

/// The same content and explicit selection state drive both targets. Native rows
/// are real Buttons with a themed selection surface, not AppKit accent-filled rows.
private struct FleetSidebarList<Content: View>: View {
    @Binding var selection: FleetSidebarDestination?
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        List { content }
        #else
        List(selection: $selection) { content }
        #endif
    }
}

private struct FleetSidebarSearchModifier: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content.searchable(text: $text, placement: .sidebar, prompt: "Filter miners...")
        #endif
    }
}

private struct FleetSidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: FleetLayout.sidebarIconSize, weight: .semibold))
                .frame(width: FleetLayout.sidebarIconWidth, alignment: .center)
            configuration.title
        }
    }
}
