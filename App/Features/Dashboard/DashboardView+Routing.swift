import SwiftUI
import HashFleetCore

extension DashboardView {
    /// Menu actions use one route at a time. Clear every presentation binding first, then wait
    /// for SwiftUI to finish dismissal before opening the requested page. This prevents a stale
    /// sheet from reopening over the new destination on iPad and macOS.
    func routeToDashboardPage(_ destination: DashboardPageDestination) {
        #if os(macOS)
        if let onSelectSidebarDestination {
            switch destination {
            case .overview:
                onSelectSidebarDestination(.overview)
                return
            case .miner(let id):
                onSelectSidebarDestination(.miner(id))
                return
            case .settings:
                onSelectSidebarDestination(.monitoring)
                return
            case .about:
                onSelectSidebarDestination(.about)
                return
            case .support:
                onSelectSidebarDestination(.support)
                return
            case .energy:
                onSelectSidebarDestination(.energy)
                return
            case .network:
                onSelectSidebarDestination(.network)
                return
            case .reports:
                onSelectSidebarDestination(.reports)
                return
            case .backup:
                onSelectSidebarDestination(.backup)
                return
            case .achievements:
                onSelectSidebarDestination(.achievements)
                return
            case .featureTour:
                break
            }
        }
        #endif
        let needsDismissal = showingAddMiner || showingSettings || showingAbout || showingSupport || showingFeatureTour
            || showingSideMenu || showingEnergy || showingNetwork || showingReports || showingBackup
            || showingAchievements || selectedMinerRoute != nil || minerSettingsRoute != nil
            || minerTuningSessionDevice != nil || minerToRemove != nil

        pendingPageDestination = destination
        clearDashboardPresentations()
        guard needsDismissal else {
            pendingPageDestination = nil
            presentDashboardPage(destination)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 300))
            guard pendingPageDestination == destination else { return }
            pendingPageDestination = nil
            presentDashboardPage(destination)
        }
    }

    private func clearDashboardPresentations() {
        pendingCelebrationPreview = nil
        showingAddMiner = false
        showingSettings = false
        showingAbout = false
        showingSupport = false
        showingFeatureTour = false
        showingSideMenu = false
        showingEnergy = false
        showingNetwork = false
        showingReports = false
        showingBackup = false
        showingAchievements = false
        selectedMinerRoute = nil
        minerSettingsRoute = nil
        minerTuningSessionDevice = nil
        minerToRemove = nil
    }

    private func presentDashboardPage(_ destination: DashboardPageDestination) {
        switch destination {
        case .overview:
            break
        case .miner(let id):
            selectedMinerRoute = store.visibleDevices.first(where: { $0.id == id })
        case .settings:
            showingSettings = true
        case .about:
            showingAbout = true
        case .support:
            showingSupport = true
        case .featureTour:
            showingFeatureTour = true
        case .energy:
            showingEnergy = true
        case .network:
            showingNetwork = true
        case .reports:
            showingReports = true
        case .backup:
            showingBackup = true
        case .achievements:
            showingAchievements = true
        }
    }
}
