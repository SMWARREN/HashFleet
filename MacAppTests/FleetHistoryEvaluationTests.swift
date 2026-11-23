import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

@Suite("Fleet History Evaluation Tests", .serialized)
@MainActor
struct FleetHistoryEvaluationTests {
    private func makeStore(demo: Bool = true) -> (FleetStore, UserDefaults) {
        let suite = "app.hashfleet.mac.historytests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let session = URLSession(configuration: .ephemeral)
        let store = FleetStore(defaults: defaults, session: session)
        if demo {
            store.loadDemo()
        }
        return (store, defaults)
    }

    private func evaluate<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 1200)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 1200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    @Test func evaluateFleetHistoryCardModes() {
        let (demoStore, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        let devices = demoStore.visibleDevices
        let snapshots = demoStore.snapshots

        // Fleet mode across ranges
        evaluate(FleetHistoryCard(
            devices: devices,
            snapshots: snapshots,
            isDemo: true,
            initialDisplay: .fleet,
            initialRecentRange: .oneMinute
        ))
        evaluate(FleetHistoryCard(
            devices: devices,
            snapshots: snapshots,
            isDemo: true,
            initialDisplay: .fleet,
            initialRecentRange: .fifteenMinutes
        ))
        evaluate(FleetHistoryCard(
            devices: devices,
            snapshots: snapshots,
            isDemo: true,
            initialDisplay: .fleet,
            initialRecentRange: .hour
        ))
        evaluate(FleetHistoryCard(
            devices: devices,
            snapshots: snapshots,
            isDemo: true,
            initialDisplay: .fleet,
            initialRecentRange: .day
        ))

        // Miners mode
        evaluate(FleetHistoryCard(
            devices: devices,
            snapshots: snapshots,
            isDemo: true,
            initialDisplay: .miners,
            initialRecentRange: .hour
        ))

        // Empty devices
        evaluate(FleetHistoryCard(
            devices: [],
            snapshots: [:],
            isDemo: true,
            initialDisplay: .fleet
        ))
    }

    @Test func evaluateFleetHistoryCardDetailAndCompact() {
        let (demoStore, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let firstDevice = demoStore.visibleDevices.first else { return }
        let snapshots = demoStore.snapshots

        let heatmap = MinerUptimeHeatmap(
            deviceID: firstDevice.id,
            isDemo: true,
            recentHistory: []
        )

        // Detail view with heatmap and number first
        evaluate(FleetHistoryCard(
            devices: [firstDevice],
            snapshots: snapshots,
            isDemo: true,
            initialDisplay: .fleet,
            isMinerDetail: true,
            isCompactDashboard: false,
            uptime: heatmap,
            dashboardMode: .full,
            numberFirst: true
        ))

        // Compact dashboard with essentials mode
        evaluate(FleetHistoryCard(
            devices: demoStore.visibleDevices,
            snapshots: snapshots,
            isDemo: true,
            initialDisplay: .fleet,
            isMinerDetail: false,
            isCompactDashboard: true,
            dashboardMode: .essentials,
            numberFirst: false
        ))
    }

    @Test func evaluateFleetHistoryPageCache() {
        let (demoStore, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        let card = FleetHistoryCard(
            devices: demoStore.visibleDevices,
            snapshots: demoStore.snapshots,
            isDemo: true
        )
        let cache = FleetHistoryPageCache()
        let data1 = card.pageData(for: .daily, cache: cache)
        #expect(!data1.histories.isEmpty)

        // Second call with same cache hits cache
        let data2 = card.pageData(for: .daily, cache: cache)
        #expect(data2.histories.count == data1.histories.count)
    }

    @Test func evaluateFleetHistoryRangeCache() {
        let cache = FleetHistoryRangeCache()
        let id1 = FleetHistoryRangeIdentity(
            kind: .sha256,
            currentSignatures: [],
            storedSignatures: [],
            storedRevision: 1
        )

        let now = Date()
        var calls = 0
        let ranges1 = cache.resolve(id1, now: now) {
            calls += 1
            return (ranges: [.hour, .day], expiration: now.addingTimeInterval(60))
        }
        #expect(calls == 1)
        #expect(ranges1.count == 2)

        // Cache hit within expiration
        let ranges2 = cache.resolve(id1, now: now.addingTimeInterval(30)) {
            calls += 1
            return (ranges: [.hour], expiration: now.addingTimeInterval(120))
        }
        #expect(calls == 1)
        #expect(ranges2.count == 2)

        // Expired call misses cache
        let ranges3 = cache.resolve(id1, now: now.addingTimeInterval(100)) {
            calls += 1
            return (ranges: [.day], expiration: now.addingTimeInterval(200))
        }
        #expect(calls == 2)
        #expect(ranges3.count == 1)
    }

    @Test func evaluateMinerLiveView() {
        let (demoStore, defaults) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        guard let firstDevice = demoStore.visibleDevices.first else { return }

        // Live view in demo mode
        evaluate(MinerLiveView(device: firstDevice, isDemo: true))
        evaluate(MinerLiveView(device: firstDevice, isDemo: true, initialEndpoint: .logWebSocket))

        // Live model lifecycle
        let model = MinerLiveModel()
        #expect(!model.isConnected)
        model.connect(device: firstDevice, endpoint: .liveWebSocket, isDemo: true)
        #expect(!model.isConnected)
        model.disconnect()
        model.clear()
    }
}
