import SwiftUI

extension View {
    func fleetDashboardWelcome(store: FleetStore, canPresent: Bool) -> some View {
        modifier(FleetDashboardWelcomePresentation(store: store, canPresent: canPresent))
    }
}

/// The window owns the sheet so changing between the compact stack and split view does not
/// recreate it. Only a person's choice or native dismissal resolves the welcome preference.
private struct FleetDashboardWelcomePresentation: ViewModifier {
    let store: FleetStore
    let canPresent: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var showing = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    private var isEligible: Bool {
        canPresent && store.preferences.shouldOfferDashboardChoice && !store.isDemo
            && store.devices.isEmpty && store.persistenceError == nil
            && !ProcessInfo.processInfo.arguments.contains("--show-feature-tour")
    }

    private var presentation: Binding<Bool> {
        Binding(get: { showing }, set: { newValue in
            // SwiftUI writes false for interactive dismissal. Navigation clears the state
            // directly, so a competing destination never silently chooses a dashboard.
            if showing && !newValue { store.preferences.continueWithCurrentDashboard() }
            showing = newValue
        })
    }

    func body(content: Content) -> some View {
        let ready = isEligible && scenePhase == .active
        content
            .task(id: ready) {
                guard ready else { return }
                // Let the scene restore its initial destination before opening this sheet.
                await Task.yield()
                guard !Task.isCancelled else { return }
                showing = true
            }
            .onChange(of: isEligible) { _, eligible in
                if !eligible { showing = false }
            }
            .fleetDismissPresentationsOnNavigation { showing = false }
            .sheet(isPresented: presentation) {
                welcomeSheet.preferredColorScheme(store.preferences.appearance.colorScheme)
            }
    }

    private func choose(_ mode: FleetPreferences.DashboardMode) {
        if store.preferences.shouldOfferDashboardChoice { store.preferences.dashboardMode = mode }
        showing = false
    }

    private var welcomeSheet: FleetDashboardWelcomeSheet {
        #if os(macOS)
        FleetDashboardWelcomeSheet(choose: choose)
        #else
        FleetDashboardWelcomeSheet(
            floating: horizontalSizeClass == .regular && verticalSizeClass == .regular,
            short: verticalSizeClass == .compact,
            offersWalkthrough: NumberFirstPreview.usesLivePhoneLayouts && horizontalSizeClass == .compact,
            choose: choose
        )
        #endif
    }
}

private struct FleetDashboardWelcomeSheet: View {
    #if os(iOS)
    let floating: Bool
    let short: Bool
    let offersWalkthrough: Bool
    #endif
    let choose: (FleetPreferences.DashboardMode) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingWalkthrough = false

    var body: some View {
        sizedPanel.sheet(isPresented: $showingWalkthrough) {
            FleetPageNavigationStack { FleetTourView(showsEssentialsWalkthrough: true) }
                .fleetPageSheet()
        }
    }

    @ViewBuilder private var sizedPanel: some View {
        #if os(macOS)
        if #available(macOS 15, *) {
            panel.frame(width: 440, height: 354).presentationSizing(.fitted)
        } else {
            panel.frame(width: 440, height: 354)
        }
        #else
        if floating {
            if #available(iOS 18, *) {
                panel.frame(width: 480, height: typeSize.isAccessibilitySize ? 690 : 380)
                    .presentationSizing(.fitted)
            } else {
                panel
            }
        } else {
            panel
                .presentationDetents(typeSize.isAccessibilitySize || short
                    ? [.large] : offersWalkthrough ? [.fraction(0.62), .large] : [.fraction(0.48)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        #endif
    }

    private var panel: some View {
        ViewThatFits(in: .vertical) {
            contents.fixedSize(horizontal: false, vertical: true)
            ScrollView { contents }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FleetTheme.canvas.ignoresSafeArea())
        .foregroundStyle(FleetTheme.ink)
        #if os(iOS)
        .presentationBackground(FleetTheme.canvas)
        #endif
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Hash Fleet")
                        .fleetFont(.title, weight: .bold)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("dashboard.chooseView")
                    Text("How much detail would you like to see?")
                        .fleetFont(.subheadline)
                        .foregroundStyle(FleetTheme.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize {
                    Image(BitsyMood.wave.assetName)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 62, height: 62)
                        .accessibilityHidden(true)
                }
            }

            VStack(spacing: 0) {
                option(.essentials)
                Rectangle()
                    .fill(FleetTheme.separator)
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .accessibilityHidden(true)
                option(.full)
            }
            .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 4) {
                #if os(iOS)
                if offersWalkthrough {
                    Button {
                        showingWalkthrough = true
                    } label: {
                        Label("Show walkthrough", systemImage: "play.circle")
                            .fleetFont(.callout, weight: .semibold)
                            .foregroundStyle(FleetTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Practice with sample miners without choosing a view.")
                    .accessibilityIdentifier("dashboard.chooseView.walkthrough")
                }
                #endif
                Button {
                    choose(.essentials)
                } label: {
                    Text("Not now")
                        .fleetFont(.callout, weight: .semibold)
                        .foregroundStyle(FleetTheme.secondary)
                        .frame(minWidth: 48, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("dashboard.chooseView.skip")
                .accessibilityHint("Starts in Essentials.")
                Text("Change anytime in App settings.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    private func option(_ mode: FleetPreferences.DashboardMode) -> some View {
        let detail = mode == .full ? "Adds comparisons, diagnostics, and API tools" : mode.summary
        return Button { choose(mode) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title).fleetFont(.headline)
                    Text(detail).fleetFont(.subheadline).foregroundStyle(FleetTheme.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .fleetFont(.footnote, weight: .semibold)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(FleetTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title). \(detail)")
        .accessibilityIdentifier("dashboard.chooseView.\(mode.rawValue)")
    }
}
