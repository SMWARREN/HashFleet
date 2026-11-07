import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import UserNotifications

/// Rich notification artwork. iOS plays an animated GIF attachment when the notification is
/// expanded, so each fan loop ships a small GIF twin alongside the in-app WebP.
/// The system moves attachment files into its own store, so every post copies to a fresh temp file.
enum FleetNotificationArt {
    static func gifAssetName(for loop: FleetArtLoop) -> String { loop.loopAssetName + "GIF" }

    static func attachment(for loop: FleetArtLoop) -> UNNotificationAttachment? {
        #if canImport(UIKit)
        guard let data = NSDataAsset(name: gifAssetName(for: loop))?.data
            ?? UIImage(named: loop.staticImageName)?.pngData() else { return nil }
        #else
        let fallback = NSImage(named: loop.staticImageName)?.tiffRepresentation.flatMap {
            NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
        }
        guard let data = NSDataAsset(name: gifAssetName(for: loop))?.data ?? fallback else { return nil }
        #endif
        let isGIF = NSDataAsset(name: gifAssetName(for: loop)) != nil
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-notification-\(UUID().uuidString)")
            .appendingPathExtension(isGIF ? "gif" : "png")
        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(
                identifier: loop.rawValue,
                url: url,
                options: [UNNotificationAttachmentOptionsTypeHintKey: isGIF ? "com.compuserve.gif" : "public.png"]
            )
        } catch {
            return nil
        }
    }
}
