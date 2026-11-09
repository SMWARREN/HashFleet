#!/usr/bin/env swift
// Run from the repository root: xcrun swift Tools/export-miner-fans.swift
// Production exports only. Transparent full-resolution masters live outside the app bundle.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("App/Resources/Assets.xcassets/MinerFans.imageset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
var entries: [[String: Any]] = []

// The onboarding card is FleetTheme.charcoal (0x111111) in BOTH appearances, so a light
// variant can never render. Export a single appearance-independent master.
do {
    let url = root.appendingPathComponent("docs/design/miner-fans/master.png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Missing fan master: \(url.path)")
    }
    precondition(sourceImage.width == sourceImage.height && sourceImage.width >= 288)
    for scale in 1...3 {
        let pixels = 96 * scale
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                bytesPerRow: pixels * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let filename = "miner-fans@\(scale)x.png"
        let destination = CGImageDestinationCreateWithURL(
            output.appendingPathComponent(filename) as CFURL,
            UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination), "Failed PNG export: \(filename)")
        entries.append(["filename": filename, "idiom": "universal", "scale": "\(scale)x"])
        print("Exported \(filename): \(pixels) × \(pixels), sRGB RGBA")
    }
}
let catalog: [String: Any] = [
    "images": entries,
    "info": ["author": "xcode", "version": 1],
    "properties": ["template-rendering-intent": "original"]
]
var json = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
json.append(0x0A)
try json.write(to: output.appendingPathComponent("Contents.json"))
