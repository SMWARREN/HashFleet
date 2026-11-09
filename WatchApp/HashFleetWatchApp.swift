import HashFleetWatchCore
import SwiftUI

/// Independent watchOS entry point. It owns the Watch-local miner list and never depends on a paired iPhone.
@main
struct HashFleetWatchApp: App {
    private let configuration: WatchLaunchConfiguration
    @State private var store: WatchFleetStore?
    @State private var demoStore: WatchFleetStore?
    @State private var discovery: WatchMinerDiscoveryController
    @State private var activity = WatchFleetActivity()

    init() {
        let configuration = WatchLaunchConfiguration.current
        self.configuration = configuration
        _discovery = State(initialValue: configuration.makeDiscoveryController())
        // `--demo` must not open production storage: the real store is built lazily when demo is exited.
        if configuration.startsInDemo {
            _store = State(initialValue: nil)
            _demoStore = State(initialValue: configuration.makeDemoStore())
        } else {
            _store = State(initialValue: configuration.makeRealStore())
            _demoStore = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(
                store: $store,
                demoStore: $demoStore,
                makeDemoStore: { configuration.makeDemoStore() },
                onRestoreRealFleet: { configuration.makeRealStore() },
                discovery: discovery,
                activity: activity
            )
            .tint(.hashGold)
        }
    }
}
