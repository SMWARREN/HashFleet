import SwiftUI

extension HashFleetApp {
    @MainActor
    func refreshRemotePushWhileActive() async {
        guard !isTesting, scenePhase == .active else { return }
        let push = FleetRemotePushCoordinator.shared
        while !Task.isCancelled {
            push.updateFleet(devices: store.visibleDevices, snapshots: store.snapshots, isDemo: store.isDemo)
            await push.resume()
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
    }
}
