import SwiftUI
import LucideSwift

/// Wrapper to make Lucide icons compatible with the existing SF Symbols Image(systemName:) API.
/// Allows gradual migration while maintaining a consistent icon API.
struct LucideIconImage: View {
    let iconName: LucideIconName
    let size: CGFloat
    let color: Color?

    init(_ iconName: LucideIconName, size: CGFloat = 24, color: Color? = nil) {
        self.iconName = iconName
        self.size = size
        self.color = color
    }

    var body: some View {
        LucideIcon(iconName, size: size, color: color, strokeWidth: 2, absoluteStrokeWidth: false)
    }
}

/// Extension to create SwiftUI Image from Lucide icons for use in Labels, Buttons, etc.
/// Note: LucideSwift 0.9.3 does not expose shape API for custom rendering.
/// Use Label { Text } icon: { LucideIcon(...) } for now.
extension Image {
    // Placeholder: LucideSwift does not support direct Image rendering
    // Use LucideIcon view directly in SwiftUI
}

/// Icon name mapping from SF Symbols to Lucide equivalents.
/// Use this to quickly find the Lucide name for common SF Symbols.
@MainActor
enum FleetIcon {
    // Tab bar
    nonisolated(unsafe) static let dashboard = LucideIconName.layoutDashboard
    nonisolated(unsafe) static let miner = LucideIconName.cpu
    nonisolated(unsafe) static let network = LucideIconName.network
    nonisolated(unsafe) static let settings = LucideIconName.settings
    nonisolated(unsafe) static let about = LucideIconName.info

    // Common actions
    nonisolated(unsafe) static let add = LucideIconName.plus
    nonisolated(unsafe) static let remove = LucideIconName.minus
    nonisolated(unsafe) static let delete = LucideIconName.trash
    nonisolated(unsafe) static let edit = LucideIconName.pencil
    nonisolated(unsafe) static let save = LucideIconName.save
    nonisolated(unsafe) static let search = LucideIconName.search
    // nonisolated(unsafe) static let filter = LucideIconName.filter // Not available in package
    nonisolated(unsafe) static let refresh = LucideIconName.refreshCw

    // Status
    nonisolated(unsafe) static let success = LucideIconName.check
    nonisolated(unsafe) static let warning = LucideIconName.circle
    nonisolated(unsafe) static let error = LucideIconName.x
    nonisolated(unsafe) static let info = LucideIconName.info

    // Mining
    nonisolated(unsafe) static let hashrate = LucideIconName.zap
    nonisolated(unsafe) static let pool = LucideIconName.database
    nonisolated(unsafe) static let worker = LucideIconName.users
    nonisolated(unsafe) static let block = LucideIconName.box
    nonisolated(unsafe) static let coin = LucideIconName.coins

    // Hardware
    nonisolated(unsafe) static let temperature = LucideIconName.thermometer
    nonisolated(unsafe) static let fan = LucideIconName.wind
    nonisolated(unsafe) static let power = LucideIconName.zap
    nonisolated(unsafe) static let chip = LucideIconName.cpu

    // Navigation
    nonisolated(unsafe) static let back = LucideIconName.arrowLeft
    nonisolated(unsafe) static let forward = LucideIconName.arrowRight
    nonisolated(unsafe) static let up = LucideIconName.arrowUp
    nonisolated(unsafe) static let down = LucideIconName.arrowDown
    nonisolated(unsafe) static let close = LucideIconName.x
    nonisolated(unsafe) static let menu = LucideIconName.menu

    // Network
    nonisolated(unsafe) static let wifi = LucideIconName.wifi
    nonisolated(unsafe) static let wifiOff = LucideIconName.wifiOff
    nonisolated(unsafe) static let link = LucideIconName.link
    // nonisolated(unsafe) static let linkBreak = LucideIconName.linkBreak // Not available
}
