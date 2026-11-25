import SwiftUI
#if os(macOS)
import AppKit
#endif
import HashFleetCore

/// Wide-window arrangement for the dashboard (iPad and the iPad app on a Mac). Phones keep the
/// existing single column because their width never reaches the two-column threshold.
extension DashboardView {
    func isWideDashboard(_ viewport: GeometryProxy) -> Bool {
        FleetLayout.usesTwoColumns(
            width: FleetLayout.dashboardAvailableWidth(for: viewport.size.width),
            regularSizeClass: !usesCompactHorizontalLayout
        ) && !dynamicTypeSize.isAccessibilitySize
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
    @State private var showsMoreTools = false
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

    private var isEssentials: Bool { store.preferences.dashboardMode == .essentials }

    private var analyticsDestinations: [FleetSidebarDestination] { [.network, .energy, .achievements, .reports] }
    private var additionalDestinations: [FleetSidebarDestination] { [.backup, .about, .support] }

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

                if isEssentials {
                    Section {
                        appSettingsRow
                        moreToolsDisclosure
                    }
                }
                if !isEssentials || showsMoreTools {
                    analyticsSection
                    managementSection
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
        .onChange(of: selection, initial: true) { _, current in
            revealSidebarDestination(current)
        }
        .onChange(of: isEssentials) { _, essentials in
            if essentials { revealSidebarDestination(selection) }
        }
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

    private func revealSidebarDestination(_ destination: FleetSidebarDestination?) {
        guard isEssentials, let destination,
              analyticsDestinations.contains(destination) || additionalDestinations.contains(destination) else { return }
        showsMoreTools = true
    }

    private var moreToolsDisclosure: some View {
        Button {
            showsMoreTools.toggle()
        } label: {
            HStack(spacing: 8) {
                Label("More tools", systemImage: "ellipsis.circle")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: showsMoreTools ? "chevron.up" : "chevron.down")
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(FleetTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showsMoreTools ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("sidebar.moreTools")
    }

    private var analyticsSection: some View {
        Section {
            sidebarDestinationRow(.network) { FleetSidebarTileLabel(title: "Network insights", destination: .network) }
            sidebarDestinationRow(.energy) { FleetSidebarTileLabel(title: "Energy & Efficiency", destination: .energy) }
            sidebarDestinationRow(.achievements) { FleetSidebarTileLabel(title: "Achievements", destination: .achievements) }
            sidebarDestinationRow(.reports) { FleetSidebarTileLabel(title: "Reports & Export", destination: .reports) }
        } header: {
            sidebarSectionHeader("Analytics & Insights")
        }
    }

    private var managementSection: some View {
        Section {
            sidebarDestinationRow(.backup) { FleetSidebarTileLabel(title: "Backup & Restore", destination: .backup) }
            if !isEssentials { appSettingsRow }
            sidebarDestinationRow(.about) { FleetSidebarTileLabel(title: "About Hash Fleet", destination: .about) }
            sidebarDestinationRow(.support) { FleetSidebarTileLabel(title: "Support Hash Fleet", destination: .support) }
        } header: {
            sidebarSectionHeader("Management")
        }
    }

    private var appSettingsRow: some View {
        sidebarDestinationRow(.monitoring) { FleetSidebarTileLabel(title: "App settings", destination: .monitoring) }
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
        var destinations: [FleetSidebarDestination] = [.overview] + filteredDevices.map { .miner($0.id) }
        if isEssentials { destinations.append(.monitoring) }
        if !isEssentials || showsMoreTools {
            destinations += analyticsDestinations
            destinations.append(.backup)
            if !isEssentials { destinations.append(.monitoring) }
            destinations += [.about, .support]
        }
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
