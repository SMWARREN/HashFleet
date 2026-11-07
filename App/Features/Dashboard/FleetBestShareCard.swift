import SwiftUI
import HashFleetCore

/// A parsed difficulty candidate with its comparable Decimal value, original raw string, and source miner label.
struct FleetDifficultyCandidate: Equatable, Sendable {
    let decimalValue: Decimal
    let rawString: String
    let displayString: String
    let minerName: String
    let isSession: Bool

    init(decimalValue: Decimal, rawString: String, displayString: String, minerName: String, isSession: Bool) {
        self.decimalValue = decimalValue
        self.rawString = rawString
        self.displayString = displayString
        self.minerName = minerName
        self.isSession = isSession
    }

    /// Backwards-compatible initializer keeping the original signature
    init(decimalValue: Decimal, displayString: String, minerName: String, isSession: Bool) {
        self.decimalValue = decimalValue
        self.rawString = displayString
        self.displayString = displayString
        self.minerName = minerName
        self.isSession = isSession
    }
}

/// Pure presentation logic for resolving fleet-wide best difficulty shares.
struct FleetBestShareSummary: Equatable, Sendable {
    let bestEver: FleetDifficultyCandidate?
    let bestSession: FleetDifficultyCandidate?
    let reportingMinerCount: Int
    let totalMinerCount: Int
    let offlineOrMissingCount: Int

    init(
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot],
        bestShareObservations: [String: MinerBestShareObservation] = [:]
    ) {
        self.totalMinerCount = devices.count
        var reporting = 0
        var everCandidates: [FleetDifficultyCandidate] = []
        var sessionCandidates: [FleetDifficultyCandidate] = []

        for device in devices {
            guard let snap = snapshots[device.id], let info = snap.info, snap.error == nil else {
                continue
            }
            let devName = device.name

            var hasShare = false
            let liveEver = Self.parseDifficulty(info.bestDiff, minerName: devName, isSession: false)
            let persistedEver = bestShareObservations[device.id.uuidString].flatMap {
                Self.parseDifficulty($0.bestDiff, minerName: devName, isSession: false)
            }
            if let parsedEver = [liveEver, persistedEver].compactMap({ $0 }).max(by: {
                $0.decimalValue < $1.decimalValue
            }) {
                everCandidates.append(parsedEver)
                hasShare = true
            }
            if let parsedSession = Self.parseDifficulty(info.bestSessionDiff, minerName: devName, isSession: true) {
                sessionCandidates.append(parsedSession)
                hasShare = true
            }
            if hasShare { reporting += 1 }
        }

        self.reportingMinerCount = reporting
        self.offlineOrMissingCount = max(0, totalMinerCount - reporting)

        // Find maximums without summing, preserving original exact string display
        self.bestEver = everCandidates.max(by: { $0.decimalValue < $1.decimalValue })
        self.bestSession = sessionCandidates.max(by: { $0.decimalValue < $1.decimalValue })
    }

    /// Parses difficulty strings (e.g. "16384", "1.25G", "3.45M", "450.5K", "9007199254740993", "392000000").
    /// Reuses `MiningDifficultyFormat` for exact parsing and abbreviated short display (e.g. 392M).
    /// Rejects booleans, nulls, negatives, infinities, and NaNs.
    static func parseDifficulty(_ rawString: String?, minerName: String, isSession: Bool) -> FleetDifficultyCandidate? {
        guard let rawString else {
            return nil
        }
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Not reported" else {
            return nil
        }

        guard let decimal = MiningDifficultyFormat.parse(trimmed) else {
            return nil
        }

        let shortDisplay = MiningDifficultyFormat.format(decimal)

        return FleetDifficultyCandidate(
            decimalValue: decimal,
            rawString: trimmed,
            displayString: shortDisplay,
            minerName: minerName,
            isSession: isSession
        )
    }
}

/// Compact native home card displaying fleet-wide best-ever and session-best difficulty shares.
/// Supports compact strip presentation while keeping full accessibility hints and coverage telemetry.
struct FleetBestShareCard: View {
    let devices: [MinerDevice]
    let snapshots: [UUID: MinerSnapshot]
    let bestShareObservations: [String: MinerBestShareObservation]
    let isDemo: Bool
    let isCompact: Bool

    init(
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot],
        bestShareObservations: [String: MinerBestShareObservation] = [:],
        isDemo: Bool,
        isCompact: Bool = false
    ) {
        self.devices = devices
        self.snapshots = snapshots
        self.bestShareObservations = bestShareObservations
        self.isDemo = isDemo
        self.isCompact = isCompact
    }

    private var summary: FleetBestShareSummary {
        FleetBestShareSummary(
            devices: devices,
            snapshots: snapshots,
            bestShareObservations: bestShareObservations
        )
    }

    var body: some View {
        let sum = summary
        VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
            HStack(alignment: .center) {
                Label("BEST SHARE", systemImage: "trophy.fill")
                    .font(FleetTheme.mono())
                    .foregroundStyle(FleetTheme.accent)
                Spacer()
                coverageBadge(sum)
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                shareMetric(
                    title: "Best all-time",
                    candidate: sum.bestEver,
                    identifier: "bestShare.ever"
                )
                .fleetRecordShine(sum.bestEver?.decimalValue)

                Divider()
                    .frame(height: 32)
                    .overlay(FleetTheme.separator)

                shareMetric(
                    title: "Best this session",
                    candidate: sum.bestSession,
                    identifier: "bestShare.session"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: FleetLayout.isMac ? .infinity : nil, alignment: .topLeading)
        .fleetCard(
            padding: isCompact ? 12 : 16,
            border: FleetTheme.comparisonBorder.opacity(0.25),
            borderWidth: 0.5
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bestShare.card")
    }

    private func shareMetric(title: String, candidate: FleetDifficultyCandidate?, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
            Text(candidate?.displayString ?? "—")
                .fleetFont(.title3, weight: .bold, design: .rounded)
                .foregroundStyle(FleetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let miner = candidate?.minerName {
                Text(miner)
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(
            "\(title): \(candidate?.displayString ?? "Not reported")\(candidate.map { ", from " + $0.minerName } ?? "")"
        )
        .accessibilityHint(candidate.map { "Raw reading: " + $0.rawString } ?? "No share recorded")
    }

    private func coverageBadge(_ sum: FleetBestShareSummary) -> some View {
        let text = isDemo ? "DEMO" : "\(sum.reportingMinerCount)/\(sum.totalMinerCount) reporting"
        return Text(text)
            .font(FleetTheme.mono(10))
            .foregroundStyle(FleetTheme.secondary)
            .fleetPillPadding()
            .background(FleetTheme.separator.opacity(0.4), in: Capsule())
            .accessibilityIdentifier("bestShare.coverage")
    }
}
