import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

// Read-only sRGB sample extraction. Rectangles are top-left pixel coordinates.
// Regional means describe textured material, not an alleged globally dominant color.
struct Region {
    let name: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fatalError("Usage: swift ExtractLogo.swift DARK_MASTER LIGHT_MASTER")
}
let groups: [(String, String, [Region])] = [
    ("dark", arguments[1], [
        Region(name: "casingGold", x: 895, y: 258, width: 45, height: 60),
        Region(name: "frontGold", x: 465, y: 335, width: 300, height: 10),
        Region(name: "hubGraphite", x: 600, y: 620, width: 80, height: 80),
        Region(name: "bladeShadow", x: 785, y: 693, width: 10, height: 20),
        Region(name: "fanHighlight", x: 590, y: 385, width: 45, height: 30),
        Region(name: "displayGlow", x: 548, y: 266, width: 175, height: 6),
        Region(name: "metalHighlight", x: 369, y: 205, width: 10, height: 10),
        Region(name: "bronzeEdge", x: 284, y: 900, width: 14, height: 55),
    ]),
    ("light", arguments[2], [
        Region(name: "ivoryBackdrop", x: 40, y: 40, width: 80, height: 80),
        Region(name: "litBackdrop", x: 540, y: 120, width: 100, height: 40),
        Region(name: "warmBackdrop", x: 160, y: 170, width: 80, height: 60),
        Region(name: "frontGold", x: 465, y: 335, width: 300, height: 10),
        Region(name: "displayGlow", x: 548, y: 266, width: 175, height: 6),
        Region(name: "hubGraphite", x: 600, y: 620, width: 80, height: 80),
        Region(name: "metalHighlight", x: 369, y: 205, width: 10, height: 10),
        Region(name: "bronzeEdge", x: 284, y: 900, width: 14, height: 55),
    ]),
]

func hex(_ values: [Int]) -> String {
    String(format: "#%02X%02X%02X", values[0], values[1], values[2])
}

var result: [[String: Any]] = []
for (mode, path, regions) in groups {
    let url = URL(fileURLWithPath: path)
    let fileData = try Data(contentsOf: url)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let space = CGColorSpace(name: CGColorSpace.sRGB) else { fatalError("Cannot decode \(path)") }
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var samples: [[String: Any]] = []
    for region in regions {
        precondition(region.x >= 0 && region.y >= 0 && region.x + region.width <= width && region.y + region.height <= height)
        var pixels: [[Int]] = []
        for y in region.y..<region.y + region.height {
            for x in region.x..<region.x + region.width {
                let offset = (y * width + x) * 4
                guard bytes[offset + 3] == 255 else { continue }
                pixels.append((0..<3).map { Int(bytes[offset + $0]) })
            }
        }
        precondition(!pixels.isEmpty)
        let mean = (0..<3).map { channel in
            Int((Double(pixels.reduce(0) { $0 + $1[channel] }) / Double(pixels.count)).rounded())
        }
        let median = (0..<3).map { channel in pixels.map { $0[channel] }.sorted()[pixels.count / 2] }
        func distance(_ p: [Int]) -> Int { zip(p, mean).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) } }
        let representative = pixels.min { distance($0) < distance($1) }!
        samples.append(["name": region.name, "rect": [region.x, region.y, region.width, region.height],
                        "opaquePixels": pixels.count, "meanHex": hex(mean),
                        "medianHex": hex(median), "actualPixelNearestMean": hex(representative)])
    }
    result.append(["mode": mode, "sourceFile": url.lastPathComponent,
                   "sha256": SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined(),
                   "width": width, "height": height, "colorSpace": "sRGB", "samples": samples])
}
let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: json, as: UTF8.self))
