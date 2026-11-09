import Foundation
import HashFleetCore

/// Compact per-miner status line for the dashboard ticker.
///
/// Built from the values `FleetStore` already holds; performs no networking. The ticker is a
/// presentation of *reported* state only: it never invents events, never claims blocks were found,
/// and never surfaces addresses, hosts, pool URLs, or credentials. Names come from the user's own
/// device labels, metrics come from firmware readings, failures collapse to the single word
/// "Offline" because raw connection errors can embed hostnames or URLs, and a miner that has not
/// answered yet is "Connecting", not offline.
struct FleetStatusTickerModel: Equatable, Sendable {

    /// A pending foreground check is distinct from both an initial connection and a failed check.
    enum Status: Equatable, Sendable {
        case connecting
        case reconnecting
        case offline
        case online
    }

    struct Item: Identifiable, Equatable, Sendable {
        let id: UUID
        /// User-supplied device label. Never the device address.
        let name: String
        let status: Status
        /// Ordered human-readable readings, e.g. "512 GH/s", "12 W", "Accepted 1,234".
        /// Only metrics the firmware actually reported appear here; missing readings are omitted.
        let segments: [String]
        /// Firmware-reported cautions ("Mining paused", "Overheat protection active",
        /// "Power fault reported", ...). Fixed strings only: raw firmware
        /// fault text and pool URLs are deliberately never shown, matching MinerReportedAlerts'
        /// key coverage without its embedded live strings.
        let notices: [String]
        /// Full plain-language status used by VoiceOver and the Reduce Motion layout.
        let summary: String
        /// True when fleet demo data backs this row; visible text should say so.
        let isSimulated: Bool

        var isOnline: Bool { status == .online }
    }

    let items: [Item]

    static let empty = FleetStatusTickerModel(items: [])

    /// One reported-notice mapping: which MinerInfo key to inspect, whether it is a boolean flag,
    /// and the fixed notice string shown when the reported value warrants it.
    private struct NoticeRule {
        let key: String
        let isFlag: Bool
        let notice: String
    }

    /// Same reported keys as `MinerReportedAlerts`, reduced to fixed safe strings so the ticker
    /// can never echo firmware-supplied fault text, pool URLs, or credentials.
    private static let noticeRules: [NoticeRule] = [
        NoticeRule(key: "miningPaused", isFlag: true, notice: "Mining paused"),
        NoticeRule(key: "overheat_mode", isFlag: true, notice: "Overheat protection active"),
        NoticeRule(key: "power_fault", isFlag: false, notice: "Power fault reported"),
        NoticeRule(key: "hardware_fault", isFlag: false, notice: "Hardware fault reported")
    ]

    init(items: [Item]) {
        self.items = items
    }

    /// Builds the ticker from the fleet's current (newest) readings. `isDemo` prefixes the
    /// accessibility summary with "Simulated:" so demo readings are never mistaken for live ones.
    init(devices: [MinerDevice], snapshots: [UUID: MinerSnapshot], isDemo: Bool = false) {
        items = devices.map { Self.item(for: $0, snapshot: snapshots[$0.id], isDemo: isDemo) }
    }

    private static func item(for device: MinerDevice, snapshot: MinerSnapshot?, isDemo: Bool) -> Item {
        let name = device.name

        func finish(status: Status, segments: [String] = [], notices: [String] = []) -> Item {
            let statePhrase: String
            switch status {
            case .connecting: statePhrase = "connecting, no reading reported yet"
            case .reconnecting: statePhrase = "reconnecting, checking for a current reading"
            case .offline: statePhrase = "offline"
            case .online: statePhrase = segments.isEmpty ? "online" : "online, " + segments.joined(separator: ", ")
            }
            var summary = "\(name) is \(statePhrase)."
            if !notices.isEmpty { summary += " " + notices.joined(separator: ". ") + "." }
            if isDemo { summary = "Simulated: " + summary }
            return Item(
                id: device.id,
                name: name,
                status: status,
                segments: segments,
                notices: notices,
                summary: summary,
                isSimulated: isDemo
            )
        }

        guard let snapshot else { return finish(status: .connecting) }
        if snapshot.isReconnecting, !isDemo { return finish(status: .reconnecting) }
        if snapshot.isCached, !isDemo { return finish(status: .offline) }
        guard snapshot.error == nil else { return finish(status: .offline) }
        guard let info = snapshot.info else { return finish(status: .connecting) }

        var segments: [String] = []
        if let rate = FleetMetricTotal.reading(info, keys: FleetTotals.hashrateKeys) {
            segments.append(FleetFormat.hashrateWithUnit(rate))
        }
        if let watts = FleetMetricTotal.reading(info, keys: FleetTotals.powerKeys) {
            segments.append("\(FleetFormat.number(watts)) W")
        }
        if let accepted = acceptedShares(info) {
            segments.append("Accepted \(accepted.formatted())")
        }
        if let best = MiningDifficultyFormat.short(info.raw["bestDiff"])
            ?? MiningDifficultyFormat.short(info.raw["bestSessionDiff"]) {
            segments.append("Best \(best)")
        }
        let notices = Self.notices(from: info)
        return finish(status: .online, segments: segments, notices: notices)
    }

    /// Only genuine reported cautions. Flag keys yield their notice on any truthy boolean-style
    /// value; fault keys on presence of any non-empty value (message text itself is not shown).
    private static func notices(from info: MinerInfo) -> [String] {
        noticeRules.compactMap { rule in
            guard let value = info.raw[rule.key] else { return nil }
            if rule.isFlag { return value.boolValue == true ? rule.notice : nil }
            switch value {
            case .string(let text):
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : rule.notice
            case .null:
                return nil
            default:
                return rule.notice
            }
        }
    }

    /// Accepts only exact, non-negative integer share counts. Fractional, boolean, negative, and
    /// non-numeric payloads are firmware noise or a truncated count, neither of which is share data.
    private static func acceptedShares(_ info: MinerInfo) -> Int? {
        guard let raw = info.raw["sharesAccepted"] else { return nil }
        switch raw {
        case .integer(let value): return value >= 0 ? Int(exactly: value) : nil
        case .unsignedInteger(let value): return Int(exactly: value)
        case .number(let value):
            guard value.isFinite, value >= 0 else { return nil }
            return Int(exactly: value)
        case .string(let text):
            guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 else {
                return nil
            }
            return value
        default:
            return nil
        }
    }

    /// Debug/test aid: no address, host, or credential-like text from the firmware payload
    /// may reach a summary.
    static func assertsPrivacy(from info: MinerInfo, into summary: String) -> Bool {
        for key in [
            "stratumURL", "poolURL", "fallbackStratumURL", "stratumUser", "stratumPassword",
            "hostname", "power_fault", "hardware_fault"
        ] {
            if let leak = info.raw[key]?.stringValue, !leak.isEmpty, summary.contains(leak) { return false }
        }
        return true
    }
}

/// Which ticker slot is on screen. The view owns pause state; the cursor only answers
/// "which item should be visible" and stays valid as the fleet grows or shrinks.
struct FleetTickerCursor: Equatable, Sendable {
    private(set) var index = 0

    /// Manual selection lands exactly on the requested item, clamped into range.
    mutating func select(_ index: Int, itemCount: Int) {
        guard itemCount > 0 else { self.index = 0; return }
        self.index = min(max(0, index), itemCount - 1)
    }

    /// Advances one slot, wrapping to the start. Stable when the fleet is empty.
    mutating func advance(itemCount: Int) {
        guard itemCount > 0 else { index = 0; return }
        index = (index % itemCount + 1) % itemCount
    }

    /// Current selection, or nil when there is nothing to show. Wrapping here keeps a cursor
    /// that outlives a shrunk fleet pointing at a real item rather than crash or blank.
    func selected(itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        return index % itemCount
    }
}

/// One clock shared by the pause control and marquee drawing. Freezing is synchronous
/// with the tap, so switching rendering schedules cannot briefly change the text offset.
struct FleetMarqueeClock: Equatable, Sendable {
    private(set) var isRunning = false
    private var accumulated: TimeInterval = 0
    private var startedAt = Date.distantPast

    mutating func setRunning(_ running: Bool, at date: Date) {
        guard running != isRunning else { return }
        if isRunning { accumulated = elapsed(at: date) }
        if running { startedAt = date }
        isRunning = running
    }

    mutating func reset(at date: Date) {
        accumulated = 0
        startedAt = date
    }

    func remaining(in duration: TimeInterval, at date: Date) -> TimeInterval {
        max(0, duration - elapsed(at: date))
    }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (isRunning ? max(0, date.timeIntervalSince(startedAt)) : 0)
    }

    /// A live reading can change the measured width of the repeated track. Rebase the clock so the
    /// same physical pixel remains under the viewport instead of recalculating the old elapsed phase
    /// against a new travel distance and visibly jumping.
    mutating func preserveOffset(
        from oldCopyWidth: CGFloat,
        to newCopyWidth: CGFloat,
        gap: CGFloat,
        at date: Date,
        pixelsPerSecond: Double
    ) {
        guard oldCopyWidth > 0, newCopyWidth > 0, pixelsPerSecond > 0 else { return }
        let oldOffset = FleetMarqueeLayout.offset(
            elapsed: elapsed(at: date),
            copyWidth: oldCopyWidth,
            gap: gap,
            pixelsPerSecond: pixelsPerSecond
        )
        let newTravel = FleetMarqueeLayout.travelDistance(copyWidth: newCopyWidth, gap: gap)
        guard newTravel > 0 else { return }
        let newOffset = oldOffset.truncatingRemainder(dividingBy: newTravel)
        let newElapsed = TimeInterval(newOffset / pixelsPerSecond)
        if isRunning {
            accumulated = 0
            startedAt = date.addingTimeInterval(-newElapsed)
        } else {
            accumulated = newElapsed
        }
    }
}
