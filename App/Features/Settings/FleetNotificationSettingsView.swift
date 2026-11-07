import SwiftUI

struct FleetNotificationSettingsView: View {
    let preferences: FleetPreferences
    var onPreviewCelebration: ((FleetCelebration.Kind) -> Void)?

    var body: some View {
        FleetSettingsForm {
            FleetNotificationSettingsSections(
                preferences: preferences,
                onPreviewCelebration: onPreviewCelebration
            )
        }
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shared with Preferences so existing navigation paths and automation identifiers keep working.
struct FleetNotificationSettingsSections: View {
    private let onPreviewCelebration: ((FleetCelebration.Kind) -> Void)?
    @State private var model: FleetNotificationSettingsModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.fleetGuidedDemo) private var guidedDemo
    @Environment(\.openURL) private var openURL

    init(
        preferences: FleetPreferences,
        onPreviewCelebration: ((FleetCelebration.Kind) -> Void)? = nil
    ) {
        self.onPreviewCelebration = onPreviewCelebration
        _model = State(initialValue: FleetNotificationSettingsModel(preferences: preferences))
    }

    var body: some View {
        Group {
            permissionSection
                .task { if !guidedDemo { await model.refresh() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && !guidedDemo {
                        Task { await model.refresh() }
                    }
                }
            testNotificationSection
            alertsSection
#if os(iOS)
            FleetRemotePushSettingsSection()
#endif
            deliverySection
        }
    }

    private var permissionSection: some View {
        FleetSettingsSection {
            if guidedDemo {
                MonitoringNoteRow(symbol: "flask", title: "Sample permission state",
                    message: "The guided demo does not read or change your system notification permission.",
                    tint: FleetTheme.accent)
            } else if let access = model.access {
                MonitoringNoteRow(
                    symbol: access.permitsNotifications ? "bell.badge" : "bell.slash",
                    title: access.title,
                    message: access.explanation,
                    tint: access.authorization == .denied ? FleetTheme.warning : FleetTheme.accent
                )
                .accessibilityIdentifier("notifications.permissionStatus")
            } else {
                ProgressView("Checking notification permission…")
                    .accessibilityIdentifier("notifications.checkingPermission")
            }
            Button {
                Task { @MainActor in
                    let success = await FleetExternalURL.open(FleetNotificationSettingsModel.settingsURL, using: openURL)
                    guard !Task.isCancelled else { return }
                    model.settingsDidOpen(success)
                }
            } label: {
                Label(FleetDeviceCopy.hostNotificationSettingsButtonTitle, systemImage: "arrow.up.forward.app")
                    .frame(minHeight: 44)
            }
            .accessibilityHint("Opens system settings to manage Hash Fleet notifications")
            .accessibilityIdentifier("notifications.openSettings")
            if let error = model.error {
                MonitoringNoteRow(symbol: "exclamationmark.triangle", message: error, tint: FleetTheme.warning)
                    .accessibilityIdentifier("notifications.error")
            }
        } header: {
            Text("Notification access")
        }
        .listRowBackground(FleetTheme.surface)
    }

    private var testNotificationSection: some View {
        FleetSettingsSection {
            BitsySays(
                mood: .wave,
                message: "Preview how I'll celebrate a new high score or a found block.",
                size: 84
            )
            .padding(.vertical, 6)
            .accessibilityIdentifier("notifications.bitsy")
            Button {
                previewCelebration(.bestShareAllTime)
            } label: {
                Label("Preview high-score celebration", systemImage: "trophy.fill")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("notifications.previewBestShare")
            Button {
                previewCelebration(.bestShareSession)
            } label: {
                Label("Preview session-best popup", systemImage: "trophy")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("notifications.previewSessionBest")
            Button {
                previewCelebration(.blockFound)
            } label: {
                Label("Preview block-found celebration", systemImage: "cube.fill")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("notifications.previewBlock")
            Button {
                Task { await model.sendTestNotification() }
            } label: {
                Label("Send a local test notification", systemImage: "bell.badge")
                    .frame(minHeight: 44)
            }
            .disabled(model.isRequesting)
            .accessibilityIdentifier("preferences.sendTestNotification")
            .fleetTourTarget("guide.notificationTest")
            .accessibilityHint("Tests local notification delivery, not internet push or background refresh. Saved alert choices stay unchanged.")
            if model.testNotificationState == .sending {
                ProgressView("Requesting test notification…")
                    .accessibilityIdentifier("notifications.testSending")
            }
            if let message = model.testNotificationState.message {
                MonitoringNoteRow(
                    symbol: model.testNotificationState == .queued ? "info.circle" : "exclamationmark.triangle",
                    message: message,
                    tint: model.testNotificationState == .queued ? FleetTheme.accent : FleetTheme.warning
                )
                .accessibilityIdentifier("notifications.testResult")
            }
        } header: {
            Text("Check delivery")
        } footer: {
            Text("Tests local notifications without waiting for a mining event. It does not test APNs or background miner checks. No alert needs to be on, and your alert choices stay unchanged.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(FleetTheme.surface)
    }

    /// The app-wide notification window presents above Settings without navigating away.
    /// Use one owner only so a preview cannot be requested twice.
    private func previewCelebration(_ kind: FleetCelebration.Kind) {
        if let onPreviewCelebration {
            onPreviewCelebration(kind)
        } else {
            FleetCelebrationPreview.request(kind: kind)
        }
    }

    private var alertsSection: some View {
        FleetSettingsSection {
            ForEach(FleetNotificationSettingsModel.Alert.allCases, id: \.self) { alert in
                Toggle(isOn: Binding(
                    get: { model.isSelected(alert) },
                    set: { enabled in Task { await model.setEnabled(enabled, for: alert) } }
                )) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(alert.title)
                            .foregroundStyle(FleetTheme.ink)
                        Text(alert.explanation)
                            .fleetFont(.footnote)
                            .foregroundStyle(FleetTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let deliveryNote = model.deliveryNote(for: alert) {
                            Text(deliveryNote)
                                .fleetFont(.footnote, weight: .semibold)
                                .foregroundStyle(FleetTheme.warning)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .disabled(model.isRequesting || model.access == nil
                    || (alert == .sessionBestShare && !model.isSelected(.bestShare)))
                .accessibilityIdentifier(alert.identifier)
                .accessibilityHint("Record popups stay in the app until dismissed. Background notification delivery is best effort.")
            }
            if model.isRequesting, model.testNotificationState != .sending {
                ProgressView("Updating notification permission…")
            }
        } header: {
            Text("Choose your alerts")
        } footer: {
            Text(FleetNotificationSettingsModel.frequencyExplanation)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(FleetTheme.surface)
    }

    private var deliverySection: some View {
        FleetSettingsSection {
#if os(iOS)
            MonitoringNoteRow(
                symbol: "clock",
                title: model.backgroundTitle,
                message: model.backgroundDetail,
                tint: model.backgroundRefreshStatus == .available ? FleetTheme.accent : FleetTheme.warning
            )
            .accessibilityIdentifier("notifications.backgroundStatus")
            DisclosureGroup("Local refresh details") {
                if let request = model.backgroundDiagnostics.refresh {
                    MonitoringNoteRow(symbol: "clock.arrow.circlepath", title: "Refresh request",
                        message: "\(request.requestedAt.formatted(date: .abbreviated, time: .shortened)): \(request.submission.explanation).")
                }
                if let request = model.backgroundDiagnostics.processing {
                    MonitoringNoteRow(symbol: "clock.arrow.circlepath", title: "Processing request",
                        message: "\(request.requestedAt.formatted(date: .abbreviated, time: .shortened)): \(request.submission.explanation).")
                }
                if let started = model.backgroundDiagnostics.startedAt {
                    MonitoringNoteRow(symbol: "wifi", title: "Last background check",
                        message: "\(started.formatted(date: .abbreviated, time: .shortened)): \(model.backgroundDiagnostics.outcome?.explanation ?? "Started; completion has not been recorded").")
                } else {
                    Text("No background check has been recorded yet. Opening Hash Fleet still refreshes local readings. A scheduled request is not proof that iOS ran it.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("These details stay on this device. Local checks need access to the miner network and do not require APNs. Widget display updates remain controlled by iOS.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("notifications.localRefreshDetails")
#endif
            DisclosureGroup("Why didn’t I receive an alert?") {
#if os(macOS)
                let deliverySettingsMessage = "Allow notifications for Hash Fleet in System Settings. Focus and notification settings may "
                    + "delay or silence alerts. Hash Fleet continues monitoring after its window closes; quitting "
                    + "the app stops local checks."
#else
                let deliverySettingsMessage = "Allow Notifications must be on for Hash Fleet. Check banners, sounds, Focus and Scheduled "
                    + "Summary. Force-quitting Hash Fleet prevents background checks until you open it again."
#endif
                MonitoringNoteRow(
                    symbol: "wifi",
                    title: "Your miner must be reachable",
                    message: FleetNotificationSettingsModel.connectionExplanation
                )
                MonitoringNoteRow(
                    symbol: "bell.badge",
                    title: "On-screen events stay in the app",
                    message: FleetNotificationSettingsModel.foregroundExplanation
                )
                MonitoringNoteRow(
                    symbol: "moon",
                    title: "Check notification delivery options",
                    message: deliverySettingsMessage
                )
            }
            .accessibilityIdentifier("notifications.troubleshooting")
        } header: {
            Text("What to expect")
        } footer: {
#if os(macOS)
            Text("""
                Event alerts use local monitoring and notifications. The workspace and menu bar are one app; \
                closing the window does not stop monitoring, while quitting does. No miner hardware settings \
                are changed.
                """)
#else
            Text("Event alerts use local monitoring. Scheduled internet push summaries are a separate, optional service above. Neither changes miner hardware.")
#endif
        }
        .listRowBackground(FleetTheme.surface)
    }
}
