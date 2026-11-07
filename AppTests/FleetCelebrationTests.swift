import Foundation
import Testing
import UIKit
@testable import HashFleet

/// Celebration payloads must survive the trip through a notification's userInfo and back, and a
/// tapped notification must route to exactly the miner that produced it.
@Suite @MainActor
struct FleetCelebrationTests {
    private let device = UUID()

    @Test func allTimeBestShareBecomesHighScoreCelebration() {
        let event = MinerBestShareEvent(
            deviceID: device, minerName: "Workshop Gamma", kind: .allTime,
            displayValue: "392.00M", rawValue: "392000000", occurredAt: .now
        )
        let celebration = FleetCelebration(event)
        #expect(celebration.kind == .bestShareAllTime)
        #expect(celebration.eyebrow == "NEW HIGH SCORE")
        #expect(celebration.value == "392.00M")
        #expect(celebration.deviceID == device)
        #expect(celebration.id == event.id)
    }

    @Test func blockWithHeightShowsFormattedHeight() {
        let event = MinerBlockFoundEvent(
            deviceID: device, minerName: "Office Gamma", coinLabel: "BTC",
            height: 912_345, count: 1, occurredAt: .now
        )
        let celebration = FleetCelebration(event)
        #expect(celebration.isBlock)
        #expect(celebration.valueCaption == "height")
        #expect(celebration.detail.contains("BTC"))
    }

    @Test func blockWithoutHeightStillCelebrates() {
        let event = MinerBlockFoundEvent(
            deviceID: device, minerName: "Office Gamma", coinLabel: nil,
            height: nil, count: 1, occurredAt: .now
        )
        let celebration = FleetCelebration(event)
        #expect(celebration.value == "Block")
        #expect(celebration.valueCaption.isEmpty)
    }

    @Test func userInfoRoundTripPreservesEveryField() throws {
        let original = FleetCelebration(
            kind: .bestShareSession, deviceID: device, minerName: "Little Supra",
            value: "9.20M", detail: "New best share this session"
        )
        let decoded = try #require(FleetCelebration(userInfo: original.userInfo))
        #expect(decoded == original)
    }

    @Test func userInfoWithoutCelebrationFieldsIsNotACelebration() {
        #expect(FleetCelebration(userInfo: [FleetCelebration.userInfoDevice: device.uuidString]) == nil)
        #expect(FleetCelebration(userInfo: [:]) == nil)
    }

    @Test func routeStoresMinerAndCelebrationThenClears() throws {
        let defaults = try #require(UserDefaults(suiteName: "celebration-route-\(UUID())"))
        let celebration = FleetCelebration(
            kind: .blockFound, deviceID: device, minerName: "Office Gamma",
            value: "912,345", detail: "BTC block found at this height"
        )
        #expect(FleetNotificationRoute.handle(userInfo: celebration.userInfo, defaults: defaults))
        let route = try #require(FleetNotificationRoute.consume(defaults: defaults))
        #expect(route.deviceID == device)
        #expect(route.celebration == celebration)
        #expect(FleetNotificationRoute.consume(defaults: defaults) == nil, "A route is consumed once")
    }

    @Test func minerOnlyAlertRoutesWithoutCelebration() throws {
        let defaults = try #require(UserDefaults(suiteName: "celebration-route-\(UUID())"))
        #expect(FleetNotificationRoute.handle(
            userInfo: [FleetCelebration.userInfoDevice: device.uuidString], defaults: defaults))
        let route = try #require(FleetNotificationRoute.consume(defaults: defaults))
        #expect(route.deviceID == device)
        #expect(route.celebration == nil)
    }

    @Test func notificationWithoutMinerFallsBackToFleet() throws {
        let defaults = try #require(UserDefaults(suiteName: "celebration-route-\(UUID())"))
        #expect(!FleetNotificationRoute.handle(userInfo: ["unrelated": "x"], defaults: defaults))
        #expect(FleetNotificationRoute.consume(defaults: defaults) == nil)
    }

    @Test func scrambledPlaceholderKeepsWidthForNumericRoll() {
        #expect(FleetCelebrationView.scrambled("392.00M") == "000.00M")
        #expect(FleetCelebrationView.scrambled("912,345") == "000,000")
    }

    @Test(arguments: [FleetArtLoop.fleetCluster, .minerCooling, .brand])
    func everyLoopShipsAnimatedWebPAndGIFTwin(loop: FleetArtLoop) throws {
        let data = try #require(loop.loopData, "Missing animated loop \(loop.loopAssetName)")
        #expect(AnimatedWebPImage.isAnimated(data))
        let gif = try #require(NSDataAsset(name: FleetNotificationArt.gifAssetName(for: loop))?.data)
        #expect(gif.prefix(6) == Data("GIF89a".utf8))
        #expect(gif.count < 1_000_000, "Notification attachments must stay well under the 10 MB image limit")
    }

    @Test func notificationAttachmentIsCreatedAsGIF() throws {
        let attachment = try #require(FleetNotificationArt.attachment(for: .fleetCluster))
        #expect(attachment.url.pathExtension == "gif")
    }

    @Test func everyBitsyMoodHasBundledTransparentArtwork() {
        for mood in BitsyMood.allCases {
            let image = UIImage(named: mood.assetName, in: Bundle.main, compatibleWith: nil)
            #expect(image != nil, "Missing bundled pose asset \(mood.assetName)")
            if let cgImage = image?.cgImage {
                #expect(cgImage.alphaInfo != CGImageAlphaInfo.none,
                        "Pose asset \(mood.assetName) must preserve transparency")
            } else {
                #expect(Bool(false), "Pose asset \(mood.assetName) has no CGImage")
            }
        }
    }
}
