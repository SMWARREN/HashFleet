import SwiftUI

/// Quick bulk table view of queued celebrations so the user can review each miner's
/// best-share or block milestone before clearing them all.
struct FleetCelebrationQueueSheet: View {
    let celebrations: [FleetCelebration]
    let totalCount: Int
    let onClearAll: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var overflowCount: Int {
        max(0, totalCount - celebrations.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerRow
                    Divider()
                    ForEach(celebrations) { item in
                        celebrationRow(item)
                        Divider()
                    }
                    if overflowCount > 0 {
                        Text("+\(overflowCount) more queued")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Celebrations (\(totalCount))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("celebration.queueSheet.done")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        dismiss()
                        onClearAll()
                    } label: {
                        Label("Clear all", systemImage: "trash")
                    }
                    .tint(.red)
                    .accessibilityIdentifier("celebration.queueSheet.clearAll")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 320, idealHeight: 420)
        #endif
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Miner")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Milestone")
                .frame(width: 112, alignment: .leading)
            Text("Best / Block")
                .frame(width: 104, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func celebrationRow(_ item: FleetCelebration) -> some View {
        HStack(spacing: 12) {
            Text(item.minerName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(kindLabel(item.kind))
                .font(.caption.weight(.medium))
                .foregroundStyle(kindColor(item.kind))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(kindColor(item.kind).opacity(0.14), in: Capsule())
                .frame(width: 112, alignment: .leading)
            Text(item.value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func kindLabel(_ kind: FleetCelebration.Kind) -> String {
        switch kind {
        case .blockFound: "Block Found"
        case .bestShareAllTime: "All-Time Best"
        case .bestShareSession: "Session Best"
        }
    }

    private func kindColor(_ kind: FleetCelebration.Kind) -> Color {
        switch kind {
        case .blockFound: .orange
        case .bestShareAllTime: .yellow
        case .bestShareSession: .secondary
        }
    }
}

struct FleetCelebrationTopMenu: View {
    let totalCount: Int
    let pendingCount: Int
    let appeared: Bool
    let animation: Animation?
    let onViewAll: () -> Void
    let onDismissAll: () -> Void

    var body: some View {
        Menu {
            Button(action: onViewAll) {
                Label(
                    totalCount > 1 ? "View all (\(totalCount))" : "View details",
                    systemImage: "tablecells"
                )
            }
            .accessibilityIdentifier("celebration.viewAll")
            Button(role: .destructive, action: onDismissAll) {
                Label(
                    pendingCount > 0 ? "Clear all (\(pendingCount + 1))" : "Clear all",
                    systemImage: "trash"
                )
            }
            .accessibilityIdentifier("celebration.dismissAll")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.14), in: Circle())
                .contentShape(Circle())
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel("More options")
        .accessibilityIdentifier("celebration.moreMenu")
        .padding(.top, 12)
        .padding(.trailing, 16)
        .opacity(appeared ? 1 : 0)
        .animation(animation, value: appeared)
    }
}
