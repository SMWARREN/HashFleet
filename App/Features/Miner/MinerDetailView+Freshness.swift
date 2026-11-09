import Foundation

/// Honest, plain-language freshness for the telemetry snapshot behind the miner detail screen.
///
/// Instrument-panel rule: a reading is only as trustworthy as its age. This type turns
/// `snapshot.updatedAt` into a short "Updated …" line and flags staleness so the screen can
/// show data age instead of implying permanently live values. It never claims connectivity;
/// it only describes when the snapshot was taken.
struct MinerSnapshotFreshness: Equatable, Sendable {
    /// Seconds between the snapshot timestamp and `now`. Never negative; future timestamps
    /// (clock skew) clamp to zero so we never render a negative age.
    let ageSeconds: TimeInterval

    /// Snapshots older than this are labelled as possibly stale. Chosen well beyond the normal
    /// refresh cadence so routine polls never alarm, while a miner that stopped answering
    /// (or a backgrounded app) becomes visible.
    static let staleAfterSeconds: TimeInterval = 120

    /// A coarse UI clock, independent of telemetry arrival. Never drives polling or chart redraws.
    static let refreshInterval: TimeInterval = 5

    init?(updatedAt: Date?, now: Date = Date()) {
        guard let updatedAt else { return nil }
        ageSeconds = max(0, now.timeIntervalSince(updatedAt))
    }

    var isStale: Bool { ageSeconds > Self.staleAfterSeconds }

    /// Coarse wording on purpose: fine-grained seconds would imply a polling cadence and
    /// timing precision the snapshot does not guarantee.
    var summary: String {
        switch ageSeconds {
        case ..<5:
            return "Updated just now"
        case ..<60:
            return "Updated \(Int(ageSeconds)) s ago"
        case ..<3_600:
            return "Updated \(Int(ageSeconds / 60)) min ago"
        default:
            return "Updated \(Int(ageSeconds / 3_600)) h ago"
        }
    }

    /// VoiceOver wording stays a complete sentence and names the staleness state explicitly
    /// rather than relying on the warning colour.
    var accessibilityLabel: String {
        isStale ? "\(summary). Snapshot may be stale." : summary
    }
}
