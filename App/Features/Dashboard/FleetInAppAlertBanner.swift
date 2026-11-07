import SwiftUI
import HashFleetCore

/// One alert shown inside the app while it is open. Each event is presented either here or as a
/// system notification, never both: foreground delivery routes to this banner and posts nothing
/// to iOS, and background delivery posts the notification and never reaches this banner.
struct FleetInAppAlert: Identifiable, Equatable, Sendable {
    enum Style: Equatable, Sendable { case warning, recovery, record }

    let id: UUID
    let deviceID: UUID
    let title: String
    let body: String
    let style: Style
    let isConnectionStatus: Bool
    let requiresAcknowledgement: Bool
    /// Alerts in the same slot replace each other (e.g. "back online" replaces "offline").
    let slot: String

    init(_ event: FleetNotificationEvent) {
        id = event.id
        deviceID = event.deviceID
        if case .temperature = event {
            requiresAcknowledgement = true
        } else {
            requiresAcknowledgement = false
        }
        slot = FleetNotificationDelivery.statusSlot(for: event) ?? "event|\(event.id.uuidString)"
        if case .stateChange(let change) = event {
            isConnectionStatus = change.kind == .offline || change.kind == .backOnline
        } else {
            isConnectionStatus = false
        }
        switch event {
        case .stateChange(let change):
            let copy = FleetStateChangeNotificationContent(event: change)
            title = copy.title
            body = copy.body
            style = change.kind == .offline ? .warning : .recovery
        case .metricAlert(let alert):
            let copy = FleetMetricAlertNotificationContent(event: alert)
            title = copy.title
            body = copy.body
            style = .warning
        case .power(let power):
            let copy = FleetPowerAlertNotificationContent(event: power)
            title = copy.title
            body = copy.body
            style = power.kind == .exceeded ? .warning : .recovery
        case .temperature(let temperature):
            let copy = FleetTemperatureAlertNotificationContent(event: temperature)
            title = copy.title
            body = copy.body
            style = .warning
        case .bestShare(let share):
            let copy = FleetBestShareNotificationContent(event: share)
            title = copy.title
            body = copy.body
            style = .record
        case .blockFound(let block):
            let copy = FleetBlockNotificationContent(event: block)
            title = copy.title
            body = copy.body
            style = .record
        }
    }

    /// Hold a previous connectivity banner while the foreground check establishes current state.
    func shouldPresent(isReconnecting: Bool) -> Bool {
        !isConnectionStatus || !isReconnecting
    }
}

/// App-wide queue. Only three banners occupy the screen at once, but additional warnings remain
/// queued instead of being silently discarded. Repeated status events replace the same slot.
@MainActor @Observable
final class FleetInAppAlertCenter {
    static let shared = FleetInAppAlertCenter()
    static let visibleLimit = 3

    private var queue: [FleetInAppAlert] = []
    var alerts: [FleetInAppAlert] { Array(queue.prefix(Self.visibleLimit)) }
    var pendingAlertCount: Int { max(0, queue.count - Self.visibleLimit) }

    func present(_ alert: FleetInAppAlert) {
        queue.removeAll { $0.slot == alert.slot || $0.id == alert.id }
        queue.insert(alert, at: 0)
    }

    func dismiss(_ id: UUID) {
        queue.removeAll { $0.id == id }
    }

    func removeAll(for deviceID: UUID) {
        queue.removeAll { $0.deviceID == deviceID }
    }

    func clear() { queue.removeAll() }
}

struct FleetInAppAlertBanner: View {
    let alert: FleetInAppAlert
    let open: () -> Void
    let dismiss: () -> Void

    private var symbol: String {
        switch alert.style {
        case .warning: "exclamationmark.triangle.fill"
        case .recovery: "checkmark.circle.fill"
        case .record: "trophy.fill"
        }
    }

    private var tint: Color {
        switch alert.style {
        case .warning: FleetTheme.accent
        case .recovery: .green
        case .record: FleetTheme.accent
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .fleetFont(.title3)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .fleetFont(.subheadline, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                Text(alert.body)
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .fleetFont(.caption, weight: .bold)
                .foregroundStyle(FleetTheme.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Dismiss alert")
        }
        .padding(FleetSurfaceSpacing.cardInset)
        .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Dismiss"), dismiss)
        .accessibilityIdentifier("inAppAlert.banner")
    }
}

/// Hosts the in-app alert stack at the top of the app, above every screen. Each banner
/// auto-dismisses; warnings stay longer than recoveries and records.
struct FleetInAppAlertOverlay: View {
    @Bindable var center: FleetInAppAlertCenter
    var reconnectingDeviceIDs: Set<UUID> = []
    let openMiner: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ForEach(center.alerts.filter {
                $0.shouldPresent(isReconnecting: reconnectingDeviceIDs.contains($0.deviceID))
            }) { alert in
                FleetInAppAlertBanner(
                    alert: alert,
                    open: {
                        center.dismiss(alert.id)
                        openMiner(alert.deviceID)
                    },
                    dismiss: { withAnimation(animation) { center.dismiss(alert.id) } }
                )
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: FleetNotificationHitRegions.self,
                            value: [geometry.frame(in: .global)]
                        )
                    }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .task(id: alert.id) {
                    guard !alert.requiresAcknowledgement else { return }
                    let seconds: Double = alert.style == .warning ? 8 : 5
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled else { return }
                    withAnimation(animation) { center.dismiss(alert.id) }
                }
            }
            if center.pendingAlertCount > 0 {
                Text("\(center.pendingAlertCount) more alerts · dismiss a banner to view")
                    .fleetFont(.caption, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(FleetTheme.surface, in: Capsule())
                    .accessibilityIdentifier("inAppAlert.pendingCount")
            }
        }
        .frame(maxWidth: FleetLayout.pageMaximumWidth(760))
        .padding(.horizontal, 16)
        // Sit below the navigation bar so toolbar buttons (Settings, Add miner) stay reachable.
        .padding(.top, 52)
        .animation(animation, value: center.alerts)
        .onChange(of: center.alerts, initial: true) { _, alerts in
            FleetInAppSurface.dashboardBannerVisible = alerts.contains { $0.style == .record }
        }
        .onDisappear { FleetInAppSurface.dashboardBannerVisible = false }
    }

    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)
    }
}
