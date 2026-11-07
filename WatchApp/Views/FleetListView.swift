import HashFleetWatchCore
import SwiftUI

struct FleetListView: View {
    let store: WatchFleetStore
    let discovery: WatchMinerDiscoveryController
    var onEnterDemo: () -> Void
    var onExitDemo: () -> Void

    var body: some View {
        List {
            if store.isDemo {
                DemoBanner()
            }

            if let storageError = store.storageError {
                Section {
                    Label(storageError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.hashCaution)
                        .accessibilityIdentifier("watch.storageError")
                }
            }

            if store.miners.isEmpty {
                if !store.isDemo { WatchDiscoverySection(discovery: discovery, store: store) }
                Section {
                    addMinerLink
                }
                EmptyFleetView()
            } else {
                Section {
                    FleetSummaryView(store: store)
                }

                Section("Miners") {
                    ForEach(store.miners) { miner in
                        NavigationLink(value: WatchRoute.miner(miner.id)) {
                            MinerRowView(store: store, miner: miner)
                        }
                        .accessibilityIdentifier("watch.miner.\(miner.id.uuidString)")
                    }
                }

                if hasFailures {
                    Section {
                        ConnectionGuidanceView(scope: allUnreachable ? .all : .some)
                    }
                }
            }

            if !store.isDemo && !store.miners.isEmpty {
                WatchDiscoverySection(discovery: discovery, store: store)
            }
            actionsSection
            Section {
                NavigationLink(value: WatchRoute.help) {
                    Label("Connection & help", systemImage: "info.circle")
                }
                .accessibilityIdentifier("watch.help")
            }
        }
        .accessibilityIdentifier("watch.fleet")
        .navigationTitle("Hash Fleet")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasFailures: Bool {
        store.miners.contains { store.failures[$0.id] != nil }
    }

    private var allUnreachable: Bool {
        !store.miners.isEmpty && store.miners.allSatisfy { store.failures[$0.id] != nil }
    }

    private var addMinerLink: some View {
        NavigationLink(value: WatchRoute.add) {
            Label("Add miner", systemImage: "plus.circle")
        }
        .accessibilityIdentifier("watch.addMiner")
    }

    @ViewBuilder
    private var actionsSection: some View {
        if store.isDemo {
            Section {
                Button("Exit demo", systemImage: "xmark.circle", action: onExitDemo)
                    .accessibilityIdentifier("watch.exitDemo")
            }
        } else {
            Section {
                if !store.miners.isEmpty {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Image(systemName: "arrow.clockwise")
                                    .opacity(store.isRefreshing ? 0 : 1)
                                ProgressView()
                                    .controlSize(.small)
                                    .opacity(store.isRefreshing ? 1 : 0)
                            }
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                            Text("Refresh")
                                .font(.body)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(store.isRefreshing)
                    .accessibilityIdentifier("watch.refresh")
                    .accessibilityValue(store.isRefreshing ? "Refreshing" : "Ready")
                    .accessibilityHint("Reads each miner over Wi-Fi. Nothing on a miner is changed.")

                    addMinerLink
                }

                Button("Try demo", systemImage: "play.circle", action: onEnterDemo)
                    .accessibilityIdentifier("watch.demo")
            }
        }
    }
}

private struct DemoBanner: View {
    var body: some View {
        Section {
            Label("Demo data. No miners are contacted.", systemImage: "play.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color.hashGold)
                .accessibilityIdentifier("watch.demoBanner")
        }
    }
}

/// Explanation only. The primary Add action stays above this text in an empty fleet.
private struct EmptyFleetView: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("No miners yet")
                    .font(.headline)
                Text("This Watch looks for compatible miners on its Wi-Fi. You can scan again or add one manually. Your phone is not needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("watch.empty")
        }
    }
}
