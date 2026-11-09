import SwiftUI
import HashFleetCore

extension MinerSettingsView {

    func settingsHubCard<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        MinerControlsCard(content: content)
    }

    /// Visible caption for a control inside a redesign card. Menu pickers outside a
    /// Form render only their current value, so the label is shown alongside them.
    func fieldLabel(_ title: String) -> some View {
        Text(title).fleetFont(.subheadline).foregroundStyle(FleetTheme.ink)
    }

    func settingsHubHeader(_ title: String, subtitle: String, symbol: String) -> some View {
        MinerControlsHeader(title: title, subtitle: subtitle, symbol: symbol)
    }

    func settingsHubRow(_ title: String, value: String?, symbol: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(FleetTheme.ink)
                Spacer()
                if let value { Text(value).foregroundStyle(FleetTheme.ink) }
                if let symbol { Image(systemName: symbol).foregroundStyle(FleetTheme.secondary) }
            }
        }
        .buttonStyle(.plain)
        .fleetFont(.subheadline)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Divider().overlay(FleetTheme.separator) }
    }

    func settingsHubCategory(
        _ title: String,
        subtitle: String,
        symbol: String,
        id: String,
        destination: @escaping () -> AnyView
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(FleetTheme.accent)
                    .frame(width: settingsIconColumnWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(FleetTheme.ink)
                    Text(subtitle).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(FleetTheme.secondary)
            }
        }
        .buttonStyle(.plain)
        .fleetFont(.subheadline)
        .padding(.vertical, 7)
        .accessibilityIdentifier(id)
    }

    func reviewQuickChanges() {
        do {
            let review = try MinerSettingsReview(
                original: info,
                hostname: hostname,
                statsFrequency: statsFrequency,
                autoFan: autoFan,
                temperatureTarget: temperatureTarget
            )
            submit(.settings, json: review.payload, fromQuickChanges: true)
        } catch { self.error = error.localizedDescription }
    }

    var compatibilitySubtitle: String {
        if store.isDemo { return "Demo preview · no miner is contacted" }
        guard let stored = store.capabilities.reports[device.id] else {
            return "Not checked yet · two read operations, nothing written"
        }
        if stored.infoStatus.isFailed || stored.asicStatus.isFailed { return "Last check did not finish · retry" }
        if stored.infoStatus == .supported && stored.asicStatus == .supported { return "Both reads supported" }
        if stored.infoStatus == .supported || stored.asicStatus == .supported {
            return "Partly supported by this firmware"
        }
        return "Neither read is served by this firmware"
    }

    func settingsPage<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        FleetSettingsForm {
            FleetSettingsSection {
                Text("Review the exact change before confirming. Nothing is sent automatically.")
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                if store.isDemo { Label("Demo settings are previews only", systemImage: "lock.fill") }
                if offlineReadOnly { MinerOfflineSettingsNotice(snapshot: store.snapshot(for: device.id)) }
                if let error { Text(error).foregroundStyle(FleetTheme.warning) }
            }
            .listRowBackground(FleetTheme.surface)
            content()
                .disabled(offlineReadOnly)
        }
        .navigationTitle(title)
        .fleetPerformanceScreen(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden).background(FleetTheme.canvas).tint(FleetTheme.accent)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MinerNavigationTitle(pageTitle: title)
            }
        }
        .environment(\.minerNavigationIdentity, navigationIdentity)
        .onAppear { error = nil }
        .navigationDestination(item: $draft) { request in draftDestination(request) }
    }

    func draftDestination(_ draft: MinerSettingsDraft) -> some View {
        MinerEndpointView(
            device: device,
            store: store,
            endpoint: draft.endpoint,
            initialJSON: draft.json,
            insights: insights
        )
        .safeAreaInset(edge: .top) {
            if let notice = draft.notice {
                DisclosureGroup("Full-slot replacement · omitted fields reset") {
                    Text(notice).fleetFont(.caption).textSelection(.enabled)
                }
                .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                .padding(12).background(FleetTheme.canvas)
            }
        }
    }

    func proposalPage<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                minerIdentityHeader
                    .fleetStaggeredEntrance(index: 0, reduceMotion: reduceMotion)

                if store.isDemo {
                    FleetStatusBadge(title: "DEMO · READ ONLY", color: FleetTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fleetStaggeredEntrance(index: 1, reduceMotion: reduceMotion)
                }

                pageTitle(title, subtitle: subtitle)
                    .fleetStaggeredEntrance(index: store.isDemo ? 2 : 1, reduceMotion: reduceMotion)
                Text(
                    "Nothing is sent while you edit. Save sends only the reviewed changes shown here; "
                        + "hardware, pool, firmware and raw requests require explicit confirmation."
                )
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                    .fleetStaggeredEntrance(index: store.isDemo ? 3 : 2, reduceMotion: reduceMotion)
                if store.isDemo {
                    Label("Demo settings are previews only", systemImage: "lock.fill")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                }
                if offlineReadOnly { MinerOfflineSettingsNotice(snapshot: store.snapshot(for: device.id)) }
                if let error { Text(error).fleetFont(.footnote).foregroundStyle(FleetTheme.warning) }
                directSaveStatus
                content()
                    .disabled(offlineReadOnly)
            }
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(title)
        .fleetPerformanceScreen(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MinerNavigationTitle(pageTitle: title)
            }
        }
        .environment(\.minerNavigationIdentity, navigationIdentity)
        .onAppear { error = nil; saveMessage = nil }
        .navigationDestination(item: $draft) { request in draftDestination(request) }
    }

    func proposalReviewButton(_ title: String, action: @escaping () -> Void) -> some View {
        let isSave = title.hasPrefix("Save")
        return Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(isSave ? FleetTheme.accent : FleetTheme.raised)
            .foregroundStyle(isSave ? FleetTheme.buttonInk : FleetTheme.secondary)
            .disabled(isSaving)
            .frame(maxWidth: .infinity)
            .padding(.top, 5)
    }
}
