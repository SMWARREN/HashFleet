import SwiftUI
import HashFleetCore

/// Summary of fleet block finds and achievements for the dashboard.
struct FleetMilestonesSummary: Equatable, Sendable {
    let totalBlocksFound: Int
    let latestBlockMinerName: String?
    let latestBlockHeight: Int?
    let latestBlockCoin: String?
    let latestBlockDate: Date?
    let bestShareDisplay: String?
    let bestShareMinerName: String?
    let totalMiners: Int

    init(
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot],
        blockObservations: [String: MinerBlockFoundObservation],
        latestEvent: MinerBlockFoundEvent?
    ) {
        self.totalMiners = devices.count

        // Block finds must come from verified evidence only. The raw firmware `blockFound`
        // counter resets to 0 on every reboot and re-climbs, so summing it (or the observation
        // mirror of it) reports phantom blocks after a power-cycle or reflash and stamps them
        // with the latest poll time (today). A guarded live `latestEvent` is the only in-memory
        // signal we trust here; historical counts come from the achievements database.
        var blocks = 0
        var latestMiner: String?
        var latestHeight: Int?
        var latestCoin: String?
        var latestDate: Date?

        if let event = latestEvent {
            blocks = 1
            latestMiner = event.minerName
            latestHeight = event.height
            latestCoin = event.coinLabel
            latestDate = event.occurredAt
        }

        _ = blockObservations

        self.totalBlocksFound = blocks
        self.latestBlockMinerName = latestMiner
        self.latestBlockHeight = latestHeight
        self.latestBlockCoin = latestCoin
        self.latestBlockDate = latestDate

        // Best share
        let shareSum = FleetBestShareSummary(devices: devices, snapshots: snapshots)
        self.bestShareDisplay = shareSum.bestEver?.displayString
        self.bestShareMinerName = shareSum.bestEver?.minerName
    }
}

/// Dedicated Dashboard Card for Blocks Found & Mining Achievements.
/// Gives prominent, permanent real-estate on the home screen to solo mining milestones.
struct FleetMilestonesCard: View {
    let devices: [MinerDevice]
    let snapshots: [UUID: MinerSnapshot]
    let blockObservations: [String: MinerBlockFoundObservation]
    let latestBlockEvent: MinerBlockFoundEvent?
    let isDemo: Bool
    let openAchievements: () -> Void

    @State private var dbBlockCount: Int = 0
    @State private var latestDbBlock: AchievementEvent?
    @State private var newBlockEventID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: FleetMilestonesSummary {
        FleetMilestonesSummary(
            devices: devices,
            snapshots: snapshots,
            blockObservations: blockObservations,
            latestEvent: latestBlockEvent
        )
    }

    var effectiveBlockCount: Int {
        max(summary.totalBlocksFound, dbBlockCount)
    }

    var body: some View {
        let sum = summary
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .center) {
                Label("BLOCKS & ACHIEVEMENTS", systemImage: "cube.fill")
                    .font(FleetTheme.mono())
                    .foregroundStyle(effectiveBlockCount > 0 ? Color.green : FleetTheme.accent)
                Spacer()
                if effectiveBlockCount > 0 {
                    Text("\(FleetFormat.integer(effectiveBlockCount)) FOUND")
                        .font(FleetTheme.mono(10))
                        .foregroundStyle(Color.green)
                        .fleetPillPadding()
                        .background(Color.green.opacity(0.14), in: Capsule())
                } else {
                    Text("SOLO MINING")
                        .font(FleetTheme.mono(10))
                        .foregroundStyle(FleetTheme.secondary)
                        .fleetPillPadding()
                        .background(FleetTheme.surface, in: Capsule())
                }
            }

            if effectiveBlockCount > 0 {
                // Celebratory Block Found Card
                blockFoundBanner(sum: sum)
            } else {
                // Searching for blocks status
                searchingContent(sum: sum)
            }

            // Navigation button to full Achievements timeline
            Button(action: openAchievements) {
                HStack {
                    Text(
                        effectiveBlockCount > 0
                            ? "View all achievements & block proof"
                            : "View achievements & best shares"
                    )
                        .fleetFont(.caption, weight: .semibold)
                        .foregroundStyle(FleetTheme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .fleetFont(.caption2, weight: .bold)
                        .foregroundStyle(FleetTheme.secondary)
                }
                .padding(.top, 2)
            }
            .accessibilityIdentifier("milestones.openAchievements")
        }
        .frame(maxHeight: FleetLayout.isMac ? .infinity : nil, alignment: .topLeading)
        .fleetCard(
            padding: 14,
            border: effectiveBlockCount > 0
                ? Color.green.opacity(0.4)
                : FleetTheme.comparisonBorder.opacity(0.25),
            borderWidth: effectiveBlockCount > 0 ? 1 : 0.5
        )
        .task {
            await loadDbMilestones()
        }
        .onChange(of: latestBlockEvent?.id) { _, newID in
            guard let newID else { return }
            newBlockEventID = newID
        }
    }

    @ViewBuilder
    private func blockFoundBanner(sum: FleetMilestonesSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)
                    if reduceMotion {
                        Image(systemName: "trophy.fill")
                            .fleetFont(.title3)
                            .foregroundStyle(Color.green)
                    } else {
                        Image(systemName: "trophy.fill")
                            .fleetFont(.title3)
                            .foregroundStyle(Color.green)
                            .symbolEffect(.bounce, value: newBlockEventID)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Block Found!")
                        .fleetFont(.headline, weight: .bold)
                        .foregroundStyle(FleetTheme.ink)

                    if let miner = sum.latestBlockMinerName ?? latestDbBlock.flatMap({ devName(for: $0.minerId) }) {
                        Text("Mined by \(miner)")
                            .fleetFont(.subheadline)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                }
                Spacer()
            }

            blockDetailRow(sum: sum)
        }
    }

    @ViewBuilder
    private func blockDetailRow(sum: FleetMilestonesSummary) -> some View {
        HStack(spacing: 12) {
            if let height = sum.latestBlockHeight ?? latestDbBlock?.blockHeight {
                VStack(alignment: .leading, spacing: 1) {
                    Text("HEIGHT")
                        .font(FleetTheme.mono(9))
                        .foregroundStyle(FleetTheme.secondary)
                    Text("#\(FleetFormat.blockHeight(height))")
                        .fleetFont(.body, weight: .bold, design: .monospaced)
                        .foregroundStyle(FleetTheme.ink)
                }
            }

            if let coin = sum.latestBlockCoin {
                VStack(alignment: .leading, spacing: 1) {
                    Text("COIN")
                        .font(FleetTheme.mono(9))
                        .foregroundStyle(FleetTheme.secondary)
                    Text(coin)
                        .fleetFont(.body, weight: .bold, design: .monospaced)
                        .foregroundStyle(FleetTheme.accent)
                }
            }

            if let date = sum.latestBlockDate ?? latestDbBlock?.timestamp {
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("FOUND")
                        .font(FleetTheme.mono(9))
                        .foregroundStyle(FleetTheme.secondary)
                    Text(date, style: .date)
                        .fleetFont(.caption, design: .monospaced)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func searchingContent(sum: FleetMilestonesSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .fleetFont(.title2)
                .foregroundStyle(FleetTheme.accent)
                .frame(width: 38, height: 38)
                .background(FleetTheme.accent.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(FleetFormat.integer(0)) Blocks Found")
                    .fleetFont(.subheadline, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                if let best = sum.bestShareDisplay {
                    Text("Fleet best share: \(best)" + (sum.bestShareMinerName.map { " by \($0)" } ?? ""))
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                } else {
                    Text("Solo mining across \(sum.totalMiners) miners. Found blocks appear here.")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
            Spacer()
        }
    }

    private func devName(for id: String) -> String? {
        devices.first(where: { $0.id.uuidString == id })?.name
    }

    private func loadDbMilestones() async {
        guard !isDemo else {
            dbBlockCount = 0
            latestDbBlock = nil
            return
        }
        let dbBlocks = await MinerTelemetryDatabase.shared.getAllAchievements(eventType: "block_found", limit: 5)
        dbBlockCount = dbBlocks.count
        latestDbBlock = dbBlocks.first
    }
}
