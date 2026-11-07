import HashFleetWatchCore
import SwiftUI

enum WatchRoute: Hashable {
    case miner(UUID)
    case add
    case help
}

/// Root navigation. The demo store is separate from the real one, so demo data is never mixed with the saved
/// inventory. The real store may be absent (a `--demo` launch) and is built lazily by `onRestoreRealFleet`.
struct WatchRootView: View {
    @Binding var store: WatchFleetStore?
    @Binding var demoStore: WatchFleetStore?
    var makeDemoStore: @MainActor () -> WatchFleetStore
    var onRestoreRealFleet: @MainActor () -> WatchFleetStore
    let discovery: WatchMinerDiscoveryController
    let activity: WatchFleetActivity

    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [WatchRoute] = []
    @State private var setup = WatchConfigurationReceiver()
    @State private var showsSetup = false

    var body: some View {
        Group {
            if let active = demoStore ?? store {
                navigation(for: active)
            } else {
                // Only reachable for an instant while the real store is being restored.
                ProgressView()
                    .task { restoreRealFleet() }
            }
        }
        .containerBackground(.black, for: .navigation)
        .onChange(of: scenePhase, initial: true) { _, _ in updateActivity() }
        .onChange(of: demoStore != nil) { _, _ in updateActivity() }
        .onChange(of: store != nil) { _, _ in updateActivity() }
        .onChange(of: store?.miners.map(\.id)) { _, _ in
            activity.inventoryDidChange(store: store)
        }
        .onChange(of: setup.pending?.id) { _, id in
            if id != nil, demoStore == nil, scenePhase == .active { showsSetup = true }
        }
        .sheet(isPresented: $showsSetup, onDismiss: { setup.finish() }) {
            if let transfer = setup.pending, let store, demoStore == nil {
                WatchSetupInboxView(transfer: transfer, store: store) {
                    setup.finish()
                    showsSetup = false
                    Task { await store.refresh() }
                }
            }
        }
    }

    private func navigation(for active: WatchFleetStore) -> some View {
        NavigationStack(path: $path) {
            FleetListView(store: active, discovery: discovery, onEnterDemo: enterDemo, onExitDemo: exitDemo)
                .navigationDestination(for: WatchRoute.self) { route in
                    switch route {
                    case let .miner(id):
                        MinerDetailView(store: active, minerID: id)
                    case .add:
                        AddMinerView(store: active)
                    case .help:
                        WatchHelpView()
                    }
                }
        }
    }

    private func updateActivity() {
        let phase: WatchFleetActivity.Phase
        switch scenePhase {
        case .active: phase = .active
        case .inactive: phase = .inactive
        case .background: phase = .background
        @unknown default: phase = .background
        }
        activity.update(phase: phase, store: demoStore ?? store, discovery: discovery)
        if scenePhase == .active, demoStore == nil {
            setup.start()
            showsSetup = setup.pending != nil
        }
    }

    private func enterDemo() {
        discovery.cancel()
        path.removeAll()
        demoStore = makeDemoStore()
    }

    private func exitDemo() {
        path.removeAll()
        restoreRealFleet()
        demoStore = nil
    }

    private func restoreRealFleet() {
        if store == nil { store = onRestoreRealFleet() }
    }
}
