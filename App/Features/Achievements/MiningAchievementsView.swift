import SwiftUI
import HashFleetCore

struct MiningAchievementsView: View {
    let devices: [MinerDevice]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fleetStandalonePage) private var standalonePage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var achievements: [AchievementEvent] = []
    @State private var isLoading = false
    @State private var selectedFilter: AchievementFilter = .all

    enum AchievementFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case blocks = "Blocks Found"
        case shares = "Best Shares"

        var id: String { rawValue }

        var eventType: String? {
            switch self {
            case .all: return nil
            case .blocks: return "block_found"
            case .shares: return "best_share"
            }
        }
    }

    var body: some View {
        FleetSettingsList {
            if isLoading {
                FleetSettingsSection {
                    FleetSettingsRow(showsSeparator: false) {
                        ProgressView("Loading achievements...")
                            .frame(maxWidth: .infinity)
                    }
                }
            } else if achievements.isEmpty {
                FleetSettingsSection {
                    FleetSettingsRow(showsSeparator: false) { emptyState }
                }
                .fleetSettingsSectionIdentifier("achievements.emptySection")
            } else {
                ForEach(groupedAchievements.keys.sorted(by: >), id: \.self) { date in
                    FleetSettingsSection(header: AnyView(sectionHeader(for: date))) {
                        ForEach(Array((groupedAchievements[date] ?? []).enumerated()), id: \.element.id) { index, achievement in
                            FleetSettingsRow {
                                achievementRow(achievement)
                                    .fleetStaggeredEntrance(index: index, reduceMotion: reduceMotion)
                            }
                        }
                    }
                    .fleetSettingsSectionIdentifier("achievements.section.\(Int(date.timeIntervalSince1970))")
                }
            }
        }
        .accessibilityIdentifier("achievements.page")
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .navigationTitle("Mining Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !standalonePage {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .fleetToolbarButton()
                }
                .fleetUnadornedToolbarBackground()
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(AchievementFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .fleetToolbarMenu()
                .accessibilityIdentifier("achievements.filter")
            }
            .fleetUnadornedToolbarBackground()
        }
        .task(id: selectedFilter) {
            await loadAchievements()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("FleetClusterArt")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 86)
                .accessibilityHidden(true)
                .fleetStaggeredEntrance(index: 0, reduceMotion: reduceMotion)

            Text("No achievements yet")
                .fleetFont(.title3, weight: .semibold)
                .fleetStaggeredEntrance(index: 1, reduceMotion: reduceMotion)

            BitsySays(
                mood: .sleepy,
                message: "I'll be ready to cheer for your first best share or block!",
                size: 64
            )
            .accessibilityIdentifier("achievements.bitsy")
            .fleetStaggeredEntrance(index: 2, reduceMotion: reduceMotion)

            Text("Your mining milestones will appear here.\nBlocks found and best shares are tracked automatically.")
                .fleetFont(.subheadline)
                .foregroundStyle(FleetTheme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fleetStaggeredEntrance(index: 3, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .listRowBackground(FleetTheme.surface)
    }

    private var groupedAchievements: [Date: [AchievementEvent]] {
        Dictionary(grouping: achievements) { achievement in
            Calendar.current.startOfDay(for: achievement.timestamp)
        }
    }

    private func sectionHeader(for date: Date) -> some View {
        Text(date, style: .date)
            .fleetFont(.subheadline, weight: .semibold)
            .foregroundStyle(FleetTheme.ink)
    }

    private func achievementRow(_ achievement: AchievementEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: achievement.eventType == "block_found" ? "cube.fill" : "star.fill")
                    .foregroundStyle(achievement.eventType == "block_found" ? .green : .yellow)
                    .accessibilityHidden(true)

                Text(achievement.eventType == "block_found" ? "Block Found!" : "Best Share")
                    .fleetFont(.headline)

                Spacer()

                Text(achievement.timestamp, style: .time)
                    .fleetFont(.caption, design: .monospaced)
                    .foregroundStyle(FleetTheme.secondary)
            }

            if let minerName = minerName(for: achievement.minerId) {
                Text(minerName)
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
            }

            if achievement.eventType == "block_found", let height = achievement.blockHeight {
                HStack(spacing: 4) {
                    Text("Block Height:")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                    Text(FleetFormat.blockHeight(height))
                        .fleetFont(.caption, design: .monospaced)
                        .foregroundStyle(FleetTheme.ink)
                }
            }

            if achievement.eventType == "best_share", let difficulty = achievement.difficulty {
                HStack(spacing: 4) {
                    Text("Difficulty:")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                    Text(FleetFormat.difficulty(difficulty))
                        .fleetFont(.caption, design: .monospaced)
                        .foregroundStyle(FleetTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func minerName(for minerId: String) -> String? {
        devices.first(where: { $0.id.uuidString == minerId })?.name
    }

    private func loadAchievements() async {
        // Capture filter at call time so a rapid change doesn't overwrite with stale results.
        let filter = selectedFilter
        isLoading = true
        defer { isLoading = false }

        // Query all devices in parallel for better performance on large fleets.
        let fetched: [[AchievementEvent]] = await withTaskGroup(of: [AchievementEvent].self) { group in
            for device in devices {
                group.addTask {
                    await MinerTelemetryDatabase.shared.getAchievements(
                        minerId: device.id.uuidString,
                        eventType: filter.eventType
                    )
                }
            }
            var results: [[AchievementEvent]] = []
            for await result in group { results.append(result) }
            return results
        }

        // Only update if filter hasn't changed since we started loading.
        guard selectedFilter == filter else { return }

        achievements = fetched.flatMap { $0 }.sorted { $0.timestamp > $1.timestamp }
    }
}

#Preview {
    NavigationStack {
        MiningAchievementsView(devices: [])
    }
}
