import SwiftUI
import HashFleetCore

/// A controlled tap-through of production screens backed only by an isolated sample fleet.
/// The underlying screens cannot receive touch or accessibility actions. Only the highlighted
/// lesson action and navigation controls are enabled, so no OS prompt, share or miner write occurs.
struct FleetTourView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var dontShowAgain: Bool
    var onPreviewCelebration: ((FleetCelebration.Kind) -> Void)?
    @State private var sandbox: FleetGuidedDemoSandbox?
    @State private var coordinator: FleetGlanceCoordinator?
    @State private var index = 0
    @State private var pdfData: Data?
    private let steps = FleetGuidedDemoStep.all

    init(
        dontShowAgain: Binding<Bool> = .constant(false),
        onPreviewCelebration: ((FleetCelebration.Kind) -> Void)? = nil
    ) {
        _dontShowAgain = dontShowAgain
        self.onPreviewCelebration = onPreviewCelebration
    }

    private var step: FleetGuidedDemoStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let sandbox, let coordinator {
                guidedScreen(sandbox, coordinator: coordinator)
            } else {
                ProgressView("Loading the sample fleet…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            coach
        }
        .background(FleetTheme.canvas)
        .foregroundStyle(FleetTheme.ink)
        .navigationTitle("Guided demo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: FleetToolbarLocation.trailing) {
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("tour.close")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.view")
        .task {
            guard sandbox == nil else { return }
            let sample = FleetGuidedDemoSandbox()
            sandbox = sample
            coordinator = FleetGlanceCoordinator(defaults: sample.store.defaults,
                storage: FleetGlanceStorage(defaults: nil), isTesting: true, activityName: "GuidedDemo")
            try? FleetEnergySettings(defaults: sample.store.defaults)
                .save(rateText: "0.15", currency: "USD", locale: Locale(identifier: "en_US_POSIX"))
            await sample.prepare()
        }
        .onDisappear { sandbox?.cleanup() }
    }

    private var sampleSummary: String {
        guard let sandbox else { return "Loading sample miners" }
        let coins = sandbox.store.preferences.dashboardCoins?.map(\.ticker).sorted().joined(separator: ", ") ?? "Automatic"
        return "\(sandbox.store.devices.count) sample miners. Display coins: \(coins)."
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(dynamicTypeSize.isAccessibilitySize ? "Demo" : "Demo • Sample miners", systemImage: "flask")
                .fleetFont(.caption, weight: .semibold)
                .lineLimit(1)
                .accessibilityLabel("Demo, sample miners")
                .accessibilityIdentifier("tour.sampleBanner")
                .accessibilityValue(sampleSummary)
            Spacer(minLength: 4)
            Text("\(index + 1)/\(steps.count)").fleetFont(.caption, design: .monospaced)
                .fixedSize()
                .accessibilityIdentifier("tour.progress")
            Menu {
                ForEach(Array(steps.enumerated()), id: \.element.id) { offset, item in
                    Button(item.title) { goTo(offset) }
                        .accessibilityIdentifier("tour.jump.\(item.id)")
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Jump to a lesson")
            .accessibilityIdentifier("tour.chooser")
        }
        .foregroundStyle(FleetTheme.accent)
        .padding(.horizontal, 16)
    }

    private func guidedScreen(_ sample: FleetGuidedDemoSandbox, coordinator: FleetGlanceCoordinator) -> some View {
        guidedNavigation {
            ScrollViewReader { scroll in
                ZStack {
                screenContent(sample, coordinator: coordinator)
                    .environment(\.fleetGuidedDemo, true)
                    .environment(\.fleetGuidedTargetID, targetID(sample))
                    .disabled(true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            .overlayPreferenceValue(FleetTourAnchorKey.self) { anchors in
                GeometryReader { geometry in
                    FleetGuidedSpotlight(target: anchors[targetID(sample)].map { geometry[$0] },
                        actionTitle: step.tapTitle ?? "Read the highlighted area",
                        isInteractive: step.tapTitle != nil, action: advance)
                        .disabled(false)
                        .allowsHitTesting(true)
                        .accessibilityHidden(false)
                }
            }
            .task(id: step.id) {
                // Wait for the actual List/ScrollView to lay out before requesting its real target.
                do {
                    try await Task.sleep(for: .milliseconds(180))
                    try Task.checkCancellation()
                    if step.id == "openMiner" {
                        scroll.scrollTo("fleet-miners", anchor: .top)
                        try await Task.sleep(for: .milliseconds(180))
                    }
                    scroll.scrollTo(targetID(sample), anchor: .center)
                    try await Task.sleep(for: .milliseconds(180))
                    try Task.checkCancellation()
                    scroll.scrollTo(targetID(sample), anchor: .center)
                } catch { }
            }
            }
        }
        .id(step.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func guidedNavigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if os(macOS)
        content()
        #else
        NavigationStack { content() }
        #endif
    }

    private func targetID(_ sample: FleetGuidedDemoSandbox) -> String {
        if step.id == "openMiner", let device = sample.store.devices.first {
            return "guide.miner.\(device.id.uuidString)"
        }
        return step.target
    }

    @ViewBuilder
    private func screenContent(_ sample: FleetGuidedDemoSandbox, coordinator: FleetGlanceCoordinator) -> some View {
        switch step.screen {
        case .fleet:
            DashboardView(store: sample.store, insights: sample.insights, coordinator: coordinator, startupReady: false)
        case .miner:
            minerScreenContent(sample)
        case .coins:
            FleetCoinSelectionView(preferences: sample.store.preferences, automaticCoins: [.btc, .bch])
        case .settings:
            MonitoringSettingsView(
                store: sample.store,
                coordinator: coordinator,
                onPreviewCelebration: onPreviewCelebration
            )
        case .preferences:
            FleetPreferencesView(
                preferences: sample.store.preferences,
                onPreviewCelebration: onPreviewCelebration
            )
        case .energy:
            FleetEnergyView(store: sample.store)
        case .report:
            FleetReportView(store: sample.store)
        case .pdf:
            pdfScreenContent
        case .notifications:
            MonitoringSettingsView(
                store: sample.store,
                coordinator: coordinator,
                onPreviewCelebration: onPreviewCelebration,
                notificationsExpanded: true
            )
        }

    }

    @ViewBuilder
    private func minerScreenContent(_ sample: FleetGuidedDemoSandbox) -> some View {
        if let device = sample.store.devices.first {
            MinerDetailView(device: device, store: sample.store, insights: sample.insights)
        }
    }

    @ViewBuilder
    private var pdfScreenContent: some View {
        if let pdfData { FleetReportPDFPreview(data: pdfData).fleetTourTarget("guide.pdf") }
    }

    private var coach: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title)
                .fleetFont(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("tour.step.\(step.id)")
            ScrollView {
                Text(step.instruction)
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("tour.instruction")
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 110 : 65)
            controls
            Toggle("Don’t show again", isOn: $dontShowAgain)
                .fleetFont(.caption)
                .accessibilityIdentifier("tour.dontShowAgain")
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
        .background(FleetTheme.surface)
        .tint(FleetTheme.accent)
    }

    private var controls: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button { goTo(index - 1) } label: {
                Text("Back")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 8)
                    .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 16))
            }
                .buttonStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)
                .disabled(index == 0)
                .accessibilityIdentifier("tour.back")
            Button(isLast ? "Done" : "Next") {
                if isLast { dismiss() } else { advance() }
            }
            .buttonStyle(FleetPrimaryButtonStyle())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(isLast ? "tour.done" : "tour.next")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func advance() {
        guard !isLast else { return }
        goTo(index + 1)
    }

    private func goTo(_ target: Int) {
        guard steps.indices.contains(target), let sandbox else { return }
        let selected = steps[target]
        // Scripted practice changes affect only the throwaway sample preference suite.
        if selected.id == "chooseDGB" { sandbox.store.preferences.dashboardCoins = [.btc, .bch] }
        if selected.id == "coinResult" { sandbox.store.preferences.dashboardCoins = [.btc, .bch, .dgb] }
        if selected.screen == .pdf {
            pdfData = FleetReportPDF.render(FleetReportSnapshot.capture(store: sandbox.store))
        }
        index = target
    }
}
