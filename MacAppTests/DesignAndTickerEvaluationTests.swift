import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Hosts the design overlays, startup splash and fleet status ticker that the Mac coverage
/// report still leaves mostly unexecuted. Layout happens in an off-screen window. No network.
@Suite("Design and ticker evaluation", .serialized)
@MainActor
struct DesignAndTickerEvaluationTests {
    private func evaluate<V: View>(_ view: V, width: CGFloat = 800, height: CGFloat = 600) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.contentView = nil
    }

    private func store(demo: Bool, miners: Int = 0) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.designticker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        if demo {
            store.loadDemo()
        } else {
            store.devices = (0..<miners).map { index in
                MinerDevice(name: "Rig \(index)", address: "192.168.1.\(10 + index)")
            }
            for device in store.devices {
                store.snapshots[device.id] = MinerSnapshot(
                    info: MinerInfo(raw: [
                        "hostname": .string(device.name), "hashRate": .number(800),
                        "power": .number(17), "temp": .number(51)
                    ]),
                    previousInfo: nil, error: indexIsOffline(device) ? "offline" : nil,
                    updatedAt: Date(), completeSnapshotAt: Date(), powerObservedAt: Date(),
                    history: [], isCached: false, isReconnecting: false
                )
            }
        }
        return (store, defaults, suite)
    }

    private func indexIsOffline(_ device: MinerDevice) -> Bool {
        device.address.hasSuffix("11") || device.address.hasSuffix("13")
    }

    @Test func evaluateScanningAndGlowOverlays() {
        evaluate(SWScanningOverlay { Text("Scan").frame(width: 240, height: 160) }, width: 300, height: 220)
        evaluate(
            SWScanningOverlay(gridOpacity: 0.4, bandOpacity: 0.6, bandHeightRatio: 0.3, gridSpacing: 12, speed: 3) {
                Color.black.frame(width: 400, height: 240)
            },
            width: 480, height: 300
        )
        evaluate(SWGlowSweep { Text("Hash Fleet").font(.largeTitle) }, width: 400, height: 120)
        evaluate(
            SWGlowSweep(baseColor: .blue, glowColor: .white, duration: 0.4, bandWidth: 80) {
                Image(systemName: "bolt.fill").font(.system(size: 48))
            },
            width: 200, height: 120
        )
    }

    @Test func evaluateStartupSplashStates() {
        evaluate(FleetStartupSplash(holdForTesting: true, onContinue: {}), width: 900, height: 700)
        evaluate(
            FleetStartupSplash(holdForTesting: false, onContinue: {}, previewReducedMotion: true),
            width: 600, height: 500
        )
    }

    @Test func evaluateStatusTickerAcrossFleetSizes() {
        for count in [0, 1, 3, 8] {
            let (fleet, defaults, suite) = store(demo: false, miners: count)
            defer { defaults.removePersistentDomain(forName: suite) }
            evaluate(FleetStatusTicker(fleet: fleet), width: 980, height: 80)
            evaluate(FleetStatusTicker(fleet: fleet, viewport: CGRect(x: 0, y: 0, width: 420, height: 64)), width: 420, height: 80)
        }
        let (demo, defaults, suite) = store(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        evaluate(FleetStatusTicker(fleet: demo), width: 1100, height: 90)
    }
}
