import Foundation
import Testing
import UserNotifications
#if os(macOS)
@testable import HashFleetMac
#else
import UIKit
@testable import HashFleet
#endif

@Suite("Device-appropriate presentation copy")
@MainActor
struct FleetDeviceCopyTests {
    struct ExpectedCopy: Sendable, CustomTestStringConvertible {
        let name: String
        let system: String
        let symbol: String
        let settings: String
        let button: String
        var testDescription: String { name }
    }

    @Test(arguments: [
        (FleetDeviceCopy.mac, ExpectedCopy(name: "Mac", system: "macOS", symbol: "desktopcomputer",
                                           settings: "System Settings", button: "Open Notification Settings")),
        (.iPhone, ExpectedCopy(name: "iPhone", system: "iOS", symbol: "iphone", settings: "Settings", button: "Open Settings")),
        (.iPad, ExpectedCopy(name: "iPad", system: "iPadOS", symbol: "ipad", settings: "Settings", button: "Open Settings"))
    ])
    func explicitDevicePolicy(device: FleetDeviceCopy, expected: ExpectedCopy) {
        let name = expected.name
        #expect(device.name == name)
        #expect(device.systemName == expected.system)
        #expect(device.symbol == expected.symbol)
        #expect(device.settingsAppName == expected.settings)
        #expect(device.notificationSettingsButtonTitle == expected.button)
        #expect(device.addMinerNetworkExplanation == "Your \(name) and miner need to be on the same local network. "
            + "Hash Fleet connects directly to your hardware, without an account or cloud service.")
        #expect(device.onboardingNetworkDetail == "Keep your \(name) and miner on the same local network.")
        #expect(device.coinSelectionFooter.hasPrefix("Saved on this \(name)."))
        #expect(device.discoveryEmptyMessage.contains("your \(name) is on the same local network"))
        #expect(device.notificationConnectionExplanation.hasPrefix("Your \(name) must be able to reach the miner"))
        for other in FleetDeviceCopy.allCases where other != device {
            #expect(!device.coinSelectionFooter.contains(other.name))
            #expect(!device.addMinerNetworkExplanation.contains(other.name))
        }
    }

    @Test(arguments: FleetDeviceCopy.allCases)
    func notificationCopyPreservesPlatformBehaviorAndDeliveryCaveats(device: FleetDeviceCopy) {
        let queued = device.queuedTestNotificationMessage
        #expect(queued.contains("five seconds from now"))
        #expect(queued.contains("check Notification Center"))
        #expect(queued.contains("not miner connectivity or background refresh"))
        #expect(device.coinSelectionFooter.contains("selecting a coin never switches a miner's pool"))
        #expect(device.xmrigConnectionExplanation.contains("access token"))
        if device == .mac {
            #expect(queued.contains("Leave Hash Fleet open"))
            #expect(!queued.contains("lock your"))
            #expect(!queued.contains("iOS"))
            #expect(!device.backgroundExplanation.contains("iOS"))
            #expect(device.backgroundExplanation.contains("Quitting the app stops local checks"))
        } else {
            #expect(queued.contains("lock your \(device.name)"))
            #expect(queued.contains("\(device.systemName) may silence or delay"))
            #expect(device.backgroundExplanation.hasPrefix("\(device.systemName) decides"))
            #expect(device.backgroundExplanation.contains("cannot continuously monitor miners in the background"))
        }
    }

    @Test func currentDeviceUsesTheActualHostRatherThanLayoutWidth() {
        #if os(macOS)
        #expect(FleetDeviceCopy.current == .mac)
        #expect(FleetDeviceCopy.hostSettingsAppName == "System Settings")
        #expect(FleetDeviceCopy.hostNotificationSettingsButtonTitle == "Open Notification Settings")
        #else
        #expect(FleetDeviceCopy.current == (UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone))
        #expect(FleetDeviceCopy.hostSettingsAppName == "Settings")
        #expect(FleetDeviceCopy.hostNotificationSettingsButtonTitle == "Open Settings")
        #endif
        let denied = FleetNotificationSettingsModel.Access(authorization: .denied)
        #expect(denied.title == "Blocked in \(FleetDeviceCopy.hostSettingsAppName)")
        #expect(FleetNotificationSettingsModel.TestNotificationState.blocked.message?.contains(FleetDeviceCopy.hostNotificationSettingsButtonTitle) == true)
        #expect(FleetNotificationSettingsModel.TestNotificationState.queued.message == FleetDeviceCopy.current.queuedTestNotificationMessage)
        #expect(FleetNotificationSettingsModel.connectionExplanation == FleetDeviceCopy.current.notificationConnectionExplanation)
        #expect(FleetNotificationSettingsModel.backgroundExplanation == FleetDeviceCopy.current.backgroundExplanation)
    }
}
