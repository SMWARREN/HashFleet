// Run from the repository root: swift Tools/generate-icon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.14, green: 0.16, blue: 0.15, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let accent = CGColor(red: 0.93, green: 0.40, blue: 0.20, alpha: 1)
func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
context.setFillColor(CGColor(red: 0.535, green: 0.28, blue: 0.175, alpha: 1))
for coordinate in stride(from: 332, through: 692, by: 72) {
    for rect in [CGRect(x: 162, y: coordinate, width: 105, height: 18),
                 CGRect(x: 757, y: coordinate, width: 105, height: 18),
                 CGRect(x: coordinate, y: 162, width: 18, height: 105),
                 CGRect(x: coordinate, y: 757, width: 18, height: 105)] {
        context.addPath(rounded(rect, radius: 9))
        context.fillPath()
    }
}
context.setStrokeColor(accent)
context.setLineWidth(22)
context.addPath(rounded(CGRect(x: 258, y: 258, width: 508, height: 508), radius: 100))
context.strokePath()
let mark = CGMutablePath()
mark.move(to: CGPoint(x: 554, y: 692))
let marks = [
    CGPoint(x: 365, y: 477),
    CGPoint(x: 482, y: 477),
    CGPoint(x: 442, y: 335),
    CGPoint(x: 658, y: 570),
    CGPoint(x: 530, y: 570)
]
for point in marks {
    mark.addLine(to: point)
}
mark.closeSubpath()
context.setFillColor(accent)
context.addPath(mark)
context.fillPath()
let directory = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let output = directory.appendingPathComponent("AppIcon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save icon") }
print("Generated opaque 1024 × 1024 app icon")
