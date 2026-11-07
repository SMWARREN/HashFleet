import Foundation
import HashFleetCore

/// Presentation-only data shared by the activity popup and the native Mac companion.
/// Neither a cached all-time high nor an old boot is allowed to masquerade as a current session.
@MainActor
enum FleetActivityPresentation {
    static let notificationLimit = 8

    static func sessionBest(
        snapshot: MinerSnapshot?, isDemo: Bool, now: Date = .now
    ) -> String? {
        guard let snapshot, snapshot.error == nil,
              !snapshot.isCached, !snapshot.isReconnecting, let info = snapshot.info else { return nil }
        if !isDemo {
            guard let observedAt = snapshot.completeSnapshotAt ?? snapshot.updatedAt else { return nil }
            let age = now.timeIntervalSince(observedAt)
            guard age.isFinite, age >= -5, age < FleetGlance.freshnessInterval else { return nil }
        }
        return MiningDifficultyFormat.short(info.raw["bestSessionDiff"])
    }

    static func notifications(from store: FleetStore) -> [FleetMenuBarNotificationSummary] {
        let devices = Dictionary(store.visibleDevices.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return store.notificationInbox
            .filter { entry in
                devices[entry.event.deviceID] != nil
                    && entry.event.occurredAt.timeIntervalSince1970.isFinite
                    && FleetNotificationDelivery.isEnabled(entry.event, in: store)
            }
            .sorted { lhs, rhs in
                if lhs.event.occurredAt != rhs.event.occurredAt {
                    return lhs.event.occurredAt > rhs.event.occurredAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(notificationLimit)
            .map { entry in
                FleetMenuBarNotificationSummary(
                    id: entry.id,
                    minerName: boundedLabel(devices[entry.event.deviceID] ?? "Miner"),
                    title: title(for: entry.event),
                    occurredAt: entry.event.occurredAt
                )
            }
    }

    /// Only fixed app-owned wording. Raw pool messages, URLs, wallet values and fault detail
    /// never enter the aggregate-only companion cache through a notification.
    static func title(for event: FleetNotificationEvent) -> String {
        switch event {
        case .bestShare(let share):
            return share.kind == .session ? "New session-best share" : "New all-time best share"
        case .blockFound: return "Miner reported a block"
        case .temperature: return "Temperature alert"
        case .power(let power):
            return power.kind == .exceeded ? "High-power alert" : "Power recovered"
        case .stateChange(let change):
            return change.kind == .offline ? "Miner offline" : "Miner connection update"
        case .metricAlert: return "Miner reading changed"
        }
    }

    private static func boundedLabel(_ text: String) -> String {
        let printable = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(printable)).prefix(80).description
    }
}
