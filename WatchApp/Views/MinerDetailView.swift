import HashFleetWatchCore
import SwiftUI

struct MinerDetailView: View {
    let store: WatchFleetStore
    let minerID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemoval = false
    @State private var removalError: String?

    var body: some View {
        if let miner = store.miners.first(where: { $0.id == minerID }) {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                content(for: MinerSnapshot(miner: miner, store: store, now: context.date), now: context.date)
            }
            .navigationTitle(miner.name)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Remove \(miner.name)?",
                isPresented: $confirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove from Watch", role: .destructive) { remove(miner) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This only removes it from this Watch. The miner isn't changed.")
            }
        } else {
            ContentUnavailableView(
                "Miner removed",
                systemImage: "trash",
                description: Text("This miner is no longer on this Watch.")
            )
            .accessibilityIdentifier("watch.detail.missing")
        }
    }

    private func content(for snapshot: MinerSnapshot, now: Date) -> some View {
        List {
            Section {
                statusBlock(snapshot, now: now)
            }

            Section("Readings") {
                row("Hashrate", WatchFormat.hashrate(snapshot.reading?.hashrateGHs))
                row("Power", WatchFormat.power(snapshot.reading?.powerWatts))
                row("Chip temp", WatchFormat.temperature(snapshot.reading?.chipTemperatureC))
                row("VR temp", WatchFormat.temperature(snapshot.reading?.vrTemperatureC))
                row("Accepted", WatchFormat.count(snapshot.reading?.acceptedShares))
                row("Rejected", WatchFormat.count(snapshot.reading?.rejectedShares))
                row("Uptime", WatchFormat.uptime(snapshot.reading?.uptimeSeconds))
                row("Mining", pauseText(snapshot.reading?.isMiningPaused))
            }

            Section("Address") {
                Text(snapshot.miner.address)
                    .font(.footnote)
                    .accessibilityLabel("Address \(snapshot.miner.address)")
            }

            if snapshot.hasFailure {
                Section { ConnectionGuidanceView(scope: .single) }
            }

            Section {
                if !store.isDemo {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshing)
                    .accessibilityIdentifier("watch.detail.refresh")

                    Button("Remove", systemImage: "trash", role: .destructive) {
                        confirmingRemoval = true
                    }
                    .accessibilityIdentifier("watch.detail.remove")
                    .accessibilityHint("Removes it from this Watch only")
                }
                if let removalError {
                    Text(removalError)
                        .font(.footnote)
                        .foregroundStyle(Color.hashCaution)
                }
            }
        }
        .accessibilityIdentifier("watch.detail")
        .privacySensitive()
    }

    private func statusBlock(_ snapshot: MinerSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(snapshot.status.title, systemImage: snapshot.status.symbol)
                .font(.headline)
                .foregroundStyle(snapshot.status.tint)
            if let reading = snapshot.reading {
                Text("Observed \(WatchFormat.age(of: reading.observedAt, now: now))")
                    .font(.footnote)
                Text(reading.observedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No reading saved yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if snapshot.status == .unreachable {
                Text("The Watch couldn't read this miner. That doesn't prove it's offline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch.detail.status")
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(value == WatchFormat.notReported ? Color.secondary : Color.white)
        }
        .accessibilityElement(children: .combine)
    }

    private func pauseText(_ paused: Bool?) -> String {
        switch paused {
        case .some(true): "Paused"
        case .some(false): "Running"
        case .none: WatchFormat.notReported
        }
    }

    private func remove(_ miner: WatchMiner) {
        do {
            try store.removeMiner(id: miner.id)
            dismiss()
        } catch {
            removalError = "Couldn't remove this miner. Try again."
        }
    }
}
