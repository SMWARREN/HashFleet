import Foundation
#if os(iOS)
import UIKit
#endif

/// Host identity is independent of window width. An iPad in a narrow window is still an iPad.
/// Keep the copy policy pure so every supported device can be checked on any test host.
enum FleetDeviceCopy: CaseIterable, Sendable {
    case mac, iPhone, iPad

    @MainActor
    static var current: Self {
        #if os(macOS)
        .mac
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }

    var name: String {
        switch self {
        case .mac: "Mac"
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        }
    }

    var systemName: String {
        switch self {
        case .mac: "macOS"
        case .iPhone: "iOS"
        case .iPad: "iPadOS"
        }
    }

    var symbol: String {
        switch self {
        case .mac: "desktopcomputer"
        case .iPhone: "iphone"
        case .iPad: "ipad"
        }
    }

    var settingsAppName: String { self == .mac ? "System Settings" : "Settings" }
    var notificationSettingsButtonTitle: String { self == .mac ? "Open Notification Settings" : "Open Settings" }

    /// The mobile Settings app has the same name on iPhone and iPad. These values are safe
    /// in nonisolated error descriptions and never read UIKit outside the main actor.
    static var hostSettingsAppName: String {
        #if os(macOS)
        Self.mac.settingsAppName
        #else
        Self.iPhone.settingsAppName
        #endif
    }

    static var hostNotificationSettingsButtonTitle: String {
        #if os(macOS)
        Self.mac.notificationSettingsButtonTitle
        #else
        Self.iPhone.notificationSettingsButtonTitle
        #endif
    }

    var addMinerNetworkExplanation: String {
        "Your \(name) and miner need to be on the same local network. Hash Fleet connects directly to your hardware, without an account or cloud service."
    }

    var discoveryEmptyMessage: String {
        "Make sure the miner is powered on and your \(name) is on the same local network. Guest-network isolation can block local devices. You can still enter its address below."
    }

    var onboardingNetworkDetail: String { "Keep your \(name) and miner on the same local network." }

    var coinSelectionFooter: String {
        "Saved on this \(name). Display only: selecting a coin never switches a miner's pool. Coins without active miners remain hypothetical full-fleet comparisons."
    }

    var xmrigConnectionExplanation: String {
        if self == .mac {
            "XMRig must enable its HTTP API. A loopback address works when XMRig runs on this Mac. A remote host needs a LAN-reachable address protected by an access token."
        } else {
            "XMRig must enable its HTTP API. Your \(name) needs a LAN-reachable address protected by an access token. A loopback address only works on the computer running XMRig."
        }
    }

    var notificationConnectionExplanation: String {
        "Your \(name) must be able to reach the miner on its local network or a working VPN. " +
        "Offline miners and firmware that does not report the required values " +
        "cannot produce these alerts."
    }

    var queuedTestNotificationMessage: String {
        if self == .mac {
            "Test scheduled for five seconds from now. Leave Hash Fleet open, " +
            "though the workspace window may be closed, and check Notification Center. " +
            "Focus or notification settings may delay or silence it. " +
            "This checks local notification delivery, not miner connectivity or background refresh."
        } else {
            "Test scheduled for five seconds from now. Leave the app or lock your \(name) now, " +
            "then check Notification Center. \(systemName) may silence or delay it " +
            "through Focus or Scheduled Summary. " +
            "This checks local notification delivery, not miner connectivity or background refresh."
        }
    }

    var backgroundExplanation: String {
        if self == .mac {
            "Hash Fleet checks miners while the app is running. " +
            "Closing the workspace window does not stop monitoring. " +
            "Quitting the app stops local checks."
        } else {
            "\(systemName) decides when background refresh runs and may delay or skip it entirely. " +
            "There is no guaranteed check interval or instant delivery. " +
            "Hash Fleet cannot continuously monitor miners in the background."
        }
    }
}
